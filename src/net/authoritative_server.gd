class_name AuthoritativeServer
extends RefCounted

const WORLD_ID_DEFAULT: String = "world_3k_main"

var world_id: String = WORLD_ID_DEFAULT
var world_seed: int = 18401
var state_crc32: int = 0
var _next_ev_seq: int = 1

var clock: SimClock = null
var event_bus: SimEventBus = null
var world_graph: WorldGraph = null
var army_manager: ArmyCaravanManager = null
var regional_market: RegionalMarket = null
var storyteller: StorytellerEngine = null
var faction_manager: FactionManager = null
var espionage_service: EspionageService = null
var diplomacy_engine: DiplomacyTreatyEngine = null
var social_service: SocialBanquetService = null
var siege_resolver: SiegeBattleResolver = null

var command_validator: CommandValidator = null
var interest_manager: InterestDeltaManager = null
var chronicle_inbox: ChronicleInboxService = null
var transport: NetworkTransport = null

# Player/Session registries
var sessions_by_peer: Dictionary = {}      # peer_key -> player_id
var peer_by_player: Dictionary = {}        # player_id -> peer_key
var player_accounts: Dictionary = {}       # player_id -> full player relational metadata
var manors: Dictionary = {}                # player_id -> ManorState
var persona_challenges: Dictionary = {}    # challenge_id -> challenge record
var account_cooldown_until: Dictionary = {}
var account_tamper_strikes: Dictionary = {}

# Queued validated commands waiting for exec_tick_id
var _pending_commands: Array[Dictionary] = []
var _tick_events_buffer: Array[Dictionary] = []

# Optional persistence hooks (decoupled from src/persistence/ concrete types)
var _persistence_hooks: Dictionary = {}


static func _to_int(v: Variant, fallback: int = 0) -> int:
	if v is int:
		var iv: int = v
		return iv
	if v is float:
		var fv: float = v
		return int(fv)
	if v is bool:
		var bv: bool = v
		return int(bv)
	return fallback


static func _to_bool(v: Variant, fallback: bool = false) -> bool:
	if v is bool:
		var bv: bool = v
		return bv
	if v is int:
		var iv: int = v
		return iv != 0
	return fallback


static func _extract_string_array(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		var arr: Array = raw
		for item: Variant in arr:
			var s: String = str(item)
			if not s.is_empty():
				out.append(s)
	return out


func _init(p_world_seed: int = 18401, p_storyteller_id: String = "ST_SIMA_QIAN") -> void:
	world_seed = p_world_seed
	clock = SimClock.new(0)
	event_bus = SimEventBus.new()
	world_graph = WorldGraph.new({}, true)
	army_manager = ArmyCaravanManager.new()
	regional_market = RegionalMarket.new(world_graph)
	storyteller = StorytellerEngine.new(p_storyteller_id, 1000)
	faction_manager = FactionManager.new()
	espionage_service = EspionageService.new()
	diplomacy_engine = DiplomacyTreatyEngine.new()
	social_service = SocialBanquetService.new()
	siege_resolver = SiegeBattleResolver.new()

	command_validator = CommandValidator.new()
	interest_manager = InterestDeltaManager.new()
	chronicle_inbox = ChronicleInboxService.new()
	transport = NetworkTransport.new(NetworkTransport.MODE_LOOPBACK)

	_seed_default_world_factions()
	state_crc32 = compute_state_crc32()


func _seed_default_world_factions() -> void:
	# Ensure NEUTRAL / YELLOW_TURBAN baseline records exist so SQLite foreign keys on macro_nodes never fail
	if not faction_manager.has_faction("NEUTRAL"):
		var _n_res: Dictionary = faction_manager.create_faction("NEUTRAL", "중립군웅", "npc_neutral_lord", "luoyang", null, 10000, 10000, "GOVERNOR_INSPECTOR")
	if not faction_manager.has_faction("YELLOW_TURBAN"):
		var _y_res: Dictionary = faction_manager.create_faction("YELLOW_TURBAN", "황건적", "npc_zhang_jiao", "ye_city", null, 8000, 5000, "GOVERNOR_INSPECTOR")


func attach_persistence_handlers(on_wal_record: Callable, on_daily_checkpoint: Callable) -> void:
	_persistence_hooks["on_wal_record"] = on_wal_record
	_persistence_hooks["on_daily_checkpoint"] = on_daily_checkpoint


func _emit_wal_hook(record: Dictionary) -> void:
	var cb_v: Variant = _persistence_hooks.get("on_wal_record", null)
	if cb_v is Callable:
		var cb: Callable = cb_v
		if cb.is_valid():
			cb.call(record)


func _emit_checkpoint_hook() -> void:
	var cb_v: Variant = _persistence_hooks.get("on_daily_checkpoint", null)
	if cb_v is Callable:
		var cb: Callable = cb_v
		if cb.is_valid():
			cb.call(self)


func register_session(
	peer_id: Variant,
	player_id: String,
	display_name: String = "",
	auth_token_hash: String = "dev_auth_hash"
) -> Dictionary:
	if player_id.is_empty():
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Empty player_id"}

	var pkey: String = str(peer_id)
	if pkey.is_empty():
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Empty peer_id"}

	if transport.mode == NetworkTransport.MODE_LOOPBACK:
		var _reg_p: String = transport.register_loopback_peer(peer_id)

	sessions_by_peer[pkey] = player_id
	peer_by_player[player_id] = pkey

	var resolved_name: String = display_name if not display_name.is_empty() else player_id
	if not player_accounts.has(player_id):
		var default_node: String = "xuchang" if world_graph.has_node("xuchang") else (world_graph.get_node_ids()[0] if not world_graph.get_node_ids().is_empty() else "luoyang")
		player_accounts[player_id] = {
			"player_id": player_id,
			"display_name": resolved_name,
			"auth_token_hash": auth_token_hash if not auth_token_hash.is_empty() else "dev_auth_hash",
			"origin_archetype": "ORIGIN_CHIVALROUS_HERO",
			"creation_mode": "INTERVIEW_ONLY",
			"persona_profile_json": "{}",
			"persona_challenge_id": null,
			"import_audit_status": "NONE",
			"coercion_flag": "R0_CLEAN",
			"host_node_id": default_node,
			"manor_id": "manor_" + player_id,
			"is_online": 1,
			"last_seen_tick": clock.current_tick_id,
			"truce_shield_until_tick": 0,
			"adaptation_factor_bp": 1000
		}
	else:
		var acct: Dictionary = player_accounts[player_id]
		if not display_name.is_empty():
			acct["display_name"] = display_name
		if not auth_token_hash.is_empty():
			acct["auth_token_hash"] = auth_token_hash
		acct["is_online"] = 1

	if not faction_manager.has_player(player_id):
		var _fp: Dictionary = faction_manager.register_player(player_id)

	var default_chans: Array[String] = [DtoSchemas.CHAN_GLOBAL_MACRO]
	if manors.has(player_id):
		var mv: Variant = manors[player_id]
		if mv is ManorState:
			var m: ManorState = mv
			default_chans.append(DtoSchemas.CHAN_MANOR + ":" + m.manor_id)
			default_chans.append(DtoSchemas.CHAN_NODE + ":" + m.host_node_id)
	var prof: Dictionary = faction_manager.get_player_profile(player_id)
	var fid: String = str(prof.get("faction_id", ""))
	if not fid.is_empty():
		default_chans.append(DtoSchemas.CHAN_FACTION + ":" + fid)

	interest_manager.register_peer(pkey, default_chans)
	_sync_all_manor_lods()

	return {
		"ok": true,
		"peer_key": pkey,
		"player_id": player_id,
		"subscriptions": interest_manager.get_subscriptions(pkey)
	}


func set_player_online(player_id: String, is_online: bool) -> Dictionary:
	if not player_accounts.has(player_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown player_id"}

	var acct: Dictionary = player_accounts[player_id]
	var was_online: bool = _to_int(acct.get("is_online", 0), 0) == 1
	var cur_resources: Dictionary = {}
	if manors.has(player_id):
		var mv: Variant = manors[player_id]
		if mv is ManorState:
			var m: ManorState = mv
			cur_resources = m.resources.duplicate(true)

	if not is_online:
		acct["is_online"] = 0
		acct["last_seen_tick"] = clock.current_tick_id
		if was_online:
			chronicle_inbox.mark_player_offline(player_id, clock.current_tick_id, cur_resources)
		if peer_by_player.has(player_id):
			var pkey: String = str(peer_by_player[player_id])
			if manors.has(player_id):
				var mv2: Variant = manors[player_id]
				if mv2 is ManorState:
					var m2: ManorState = mv2
					var _u: bool = interest_manager.unsubscribe(pkey, DtoSchemas.CHAN_MANOR + ":" + m2.manor_id)
		_sync_all_manor_lods()
		return {"ok": true, "player_id": player_id, "is_online": false}

	# Reconnecting online
	var from_tick: int = _to_int(acct.get("last_seen_tick", clock.current_tick_id), clock.current_tick_id)
	acct["is_online"] = 1
	acct["last_seen_tick"] = clock.current_tick_id

	if peer_by_player.has(player_id):
		var pkey2: String = str(peer_by_player[player_id])
		if manors.has(player_id):
			var mv3: Variant = manors[player_id]
			if mv3 is ManorState:
				var m3: ManorState = mv3
				var _sub: bool = interest_manager.subscribe(pkey2, DtoSchemas.CHAN_MANOR + ":" + m3.manor_id)

	_sync_all_manor_lods()

	var gazette: Dictionary = {}
	if not was_online:
		gazette = chronicle_inbox.build_reconnect_gazette(
			player_id,
			from_tick,
			clock.current_tick_id,
			cur_resources
		)
		if peer_by_player.has(player_id):
			var pkey3: String = str(peer_by_player[player_id])
			var _sent: bool = transport.server_send_to_peer(pkey3, gazette)

	return {
		"ok": true,
		"player_id": player_id,
		"is_online": true,
		"gazette": gazette
	}


func _sync_all_manor_lods() -> void:
	var online_map: Dictionary = {}
	for pid_v: Variant in player_accounts.keys():
		var pid: String = str(pid_v)
		var acct_v: Variant = player_accounts[pid]
		if acct_v is Dictionary:
			var acct: Dictionary = acct_v
			online_map[pid] = _to_int(acct.get("is_online", 0), 0) == 1
	interest_manager.sync_manor_lods(manors, online_map)


func _build_validator_context() -> Dictionary:
	return {
		"current_tick_id": clock.current_tick_id,
		"peer_to_player": sessions_by_peer,
		"manors": manors,
		"world_graph": world_graph,
		"faction_manager": faction_manager,
		"regional_market": regional_market,
		"chronicle_inbox": chronicle_inbox
	}


func submit_raw_command(peer_id: Variant, raw_payload: Variant) -> Dictionary:
	var ctx: Dictionary = _build_validator_context()
	var res: Dictionary = command_validator.validate_raw_command(peer_id, raw_payload, ctx)
	var receipt_v: Variant = res.get("receipt", {})
	if receipt_v is Dictionary:
		var receipt: Dictionary = receipt_v
		var _sent: bool = transport.server_send_to_peer(peer_id, receipt)

	if _to_bool(res.get("accepted", false), false):
		var env_v: Variant = res.get("envelope", {})
		if env_v is Dictionary:
			var env: Dictionary = env_v
			var exec_tick: int = _to_int(res.get("exec_tick_id", clock.current_tick_id + 1), clock.current_tick_id + 1)
			_pending_commands.append({
				"peer_id": peer_id,
				"peer_key": str(peer_id),
				"exec_tick_id": exec_tick,
				"envelope": env.duplicate(true)
			})
			var wal_rec: Dictionary = {
				"tick_id": exec_tick,
				"cmd_seq": _to_int(env.get("cmd_seq", 0), 0),
				"player_id": str(env.get("player_id", "")),
				"cmd_type": str(env.get("cmd_type", "")),
				"payload": env.get("args", {}),
				"crc32": StateHasher.crc32_dict(env)
			}
			_emit_wal_hook(wal_rec)
	return res


func _drain_transport_commands() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var incoming: Array[Dictionary] = transport.server_drain_incoming()
	for pkt: Dictionary in incoming:
		var pid: Variant = pkt.get("peer_id", pkt.get("peer_key", ""))
		var raw_utf8: String = str(pkt.get("raw_utf8", ""))
		results.append(submit_raw_command(pid, raw_utf8))
	return results


func _record_tick_event(ev_type: String, details: Dictionary) -> void:
	var ev_id: int = _next_ev_seq
	_next_ev_seq += 1
	var entry: Dictionary = {
		"ev_id": ev_id,
		"type": ev_type,
		"tick_id": clock.current_tick_id
	}
	for k: Variant in details.keys():
		entry[str(k)] = details[k]
	_tick_events_buffer.append(entry)


func _execute_validated_command(peer_id: Variant, env: Dictionary) -> Dictionary:
	var player_id: String = str(env.get("player_id", ""))
	var cmd_type: String = str(env.get("cmd_type", ""))
	var args_v: Variant = env.get("args", {})
	var args: Dictionary = args_v if args_v is Dictionary else {}
	var pkey: String = str(peer_id)
	var tick_id: int = clock.current_tick_id

	match cmd_type:
		"CMD_REQUEST_PERSONA_CHALLENGE":
			var account_id: String = str(args.get("account_id", player_id))
			var salt: int = _to_int(args.get("nonce_salt", _to_int(env.get("cmd_seq", 0), 0)), 0)
			var chal_res: Dictionary = SealedTokenCodec.issue_challenge(
				account_id,
				player_id,
				tick_id,
				persona_challenges,
				account_cooldown_until,
				world_seed,
				salt
			)
			if _to_bool(chal_res.get("ok", false), false):
				var msg_v: Variant = chal_res.get("data", {})
				if msg_v is Dictionary:
					var msg: Dictionary = msg_v
					var _s: bool = transport.server_send_to_peer(peer_id, msg)
			else:
				var err_msg: Dictionary = {
					"v": 1,
					"msg_type": DtoSchemas.MSG_CMD_RECEIPT,
					"cmd_seq": _to_int(env.get("cmd_seq", 0), 0),
					"status": "REJECTED",
					"error_code": str(chal_res.get("error_code", DtoSchemas.ERR_CHALLENGE_COOLDOWN)),
					"exec_tick_id": tick_id
				}
				var _s2: bool = transport.server_send_to_peer(peer_id, err_msg)
			return chal_res

		"CMD_CREATE_CHARACTER":
			var params: Dictionary = args.duplicate(true)
			params["player_id"] = player_id
			var c_res: Dictionary = CharacterCreationEngine.create_character_and_manor(
				params,
				persona_challenges,
				account_cooldown_until,
				account_tamper_strikes,
				world_seed,
				tick_id
			)
			if not _to_bool(c_res.get("ok", false), false):
				var fail_receipt: Dictionary = {
					"v": 1,
					"msg_type": DtoSchemas.MSG_CMD_RECEIPT,
					"cmd_seq": _to_int(env.get("cmd_seq", 0), 0),
					"status": "REJECTED",
					"error_code": str(c_res.get("error_code", DtoSchemas.ERR_TOKEN_FORMAT)),
					"exec_tick_id": tick_id
				}
				var _sf: bool = transport.server_send_to_peer(peer_id, fail_receipt)
				return c_res

			var manor_v: Variant = c_res.get("manor", null)
			var avatar_v: Variant = c_res.get("avatar", null)
			if manor_v is ManorState:
				var m_new: ManorState = manor_v
				manors[player_id] = m_new
				if player_accounts.has(player_id):
					var acct: Dictionary = player_accounts[player_id]
					acct["creation_mode"] = str(c_res.get("creation_mode", "INTERVIEW_ONLY"))
					acct["import_audit_status"] = str(c_res.get("import_audit_status", "NONE"))
					acct["coercion_flag"] = str(c_res.get("coercion_flag", "R0_CLEAN"))
					var cid_used: String = str(c_res.get("challenge_id", ""))
					acct["persona_challenge_id"] = cid_used if not cid_used.is_empty() else null
					acct["host_node_id"] = m_new.host_node_id
					acct["manor_id"] = m_new.manor_id
					if avatar_v is PawnEntity:
						var av: PawnEntity = avatar_v
						acct["origin_archetype"] = av.origin_archetype
						acct["persona_profile_json"] = StateHasher.canonical_json({
							"avatar_name": av.name,
							"courtesy_name": av.courtesy_name,
							"epithet": av.epithet,
							"stats": av.stats,
							"traits": av.traits
						})
				var _sm: bool = interest_manager.subscribe(pkey, DtoSchemas.CHAN_MANOR + ":" + m_new.manor_id)
				var _sn: bool = interest_manager.subscribe(pkey, DtoSchemas.CHAN_NODE + ":" + m_new.host_node_id)
				_sync_all_manor_lods()
			_record_tick_event("CHARACTER_CREATED", {"player_id": player_id})
			return c_res

		"CMD_SET_WORK_PRIORITY":
			var manor: ManorState = _get_manor(player_id)
			if manor == null:
				return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE}
			var pawn: PawnEntity = manor.get_pawn_by_id(str(args.get("pawn_id", "")))
			if pawn == null:
				return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE}
			pawn.set_work_priority(str(args.get("domain", "")), _to_int(args.get("priority", 2), 2))
			return {"ok": true}

		"CMD_SET_SCHEDULE":
			var manor: ManorState = _get_manor(player_id)
			if manor == null:
				return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE}
			var target_pawns: Array[PawnEntity] = []
			var pid_arg: String = str(args.get("pawn_id", ""))
			if not pid_arg.is_empty():
				var p_found: PawnEntity = manor.get_pawn_by_id(pid_arg)
				if p_found != null:
					target_pawns.append(p_found)
			else:
				target_pawns = manor.pawns
			for p: PawnEntity in target_pawns:
				if args.has("schedule") and args["schedule"] is Array:
					var sched_arr: Array = args["schedule"]
					for si: int in range(mini(12, sched_arr.size())):
						p.set_schedule_activity(si, str(sched_arr[si]))
				else:
					p.set_schedule_activity(_to_int(args.get("shichen_index", 0), 0), str(args.get("activity", "WORK")))
			return {"ok": true}

		"CMD_SET_DOCTRINE":
			var manor: ManorState = _get_manor(player_id)
			if manor == null:
				return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE}
			for dk: Variant in args.keys():
				var k_str: String = str(dk)
				if k_str != "manor_id":
					manor.standing_doctrine[k_str] = args[dk]
			return {"ok": true}

		"CMD_BUILD_OR_UPGRADE":
			var manor: ManorState = _get_manor(player_id)
			if manor == null:
				return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE}
			var up_ok: bool = manor.upgrade_building(str(args.get("building_id", "")))
			return {"ok": up_ok}

		"CMD_PROMOTE_TROOPS":
			var manor: ManorState = _get_manor(player_id)
			if manor == null:
				return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE}
			return world_graph.promote_troops(manor, str(args.get("unit_type", "SPEAR_SHIELD")), _to_int(args.get("count", 0), 0))

		"CMD_DISPATCH_EXPEDITION":
			var manor: ManorState = _get_manor(player_id)
			if manor == null:
				return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE}
			var oids: Array[String] = _extract_string_array(args.get("officer_ids", []))
			var path_ids: Array[String] = _extract_string_array(args.get("path_edge_ids", []))
			var cargo_v: Variant = args.get("cargo", {})
			var cargo: Dictionary = cargo_v if cargo_v is Dictionary else {}
			var disp_res: Dictionary = ManorSimulator.dispatch_expedition_from_manor(
				manor,
				oids,
				_to_int(args.get("troop_count", 0), 0),
				_to_int(args.get("carried_grain", 0), 0),
				cargo,
				path_ids,
				str(args.get("unit_type", "ARMY")),
				clock,
				event_bus
			)
			if _to_bool(disp_res.get("ok", false), false):
				var spawned: Array[Dictionary] = army_manager.ingest_micro_events(event_bus, world_graph, tick_id)
				var fac_id: String = str(faction_manager.get_player_profile(player_id).get("faction_id", ""))
				if not fac_id.is_empty():
					for sp: Dictionary in spawned:
						var sp_id: String = str(sp.get("entity_id", ""))
						if army_manager.entities.has(sp_id):
							var ent_ref: Dictionary = army_manager.entities[sp_id]
							ent_ref["faction_id"] = fac_id
							if args.has("target_manor_id"):
								ent_ref["target_manor_id"] = str(args.get("target_manor_id", ""))
							if args.has("target_node_id"):
								ent_ref["target_node_id"] = str(args.get("target_node_id", ""))
				_record_tick_event("EXPEDITION_DISPATCHED", {"player_id": player_id, "count": spawned.size()})
			return disp_res

		"CMD_PLACE_MARKET_ORDER":
			var manor: ManorState = _get_manor(player_id)
			if manor == null:
				return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE}
			var nid: String = str(args.get("node_id", manor.host_node_id))
			var comm: String = str(args.get("commodity", "GRAIN"))
			var side: String = str(args.get("side", "BID"))
			var price_bp: int = _to_int(args.get("price_bp", 1000), 1000)
			var qty: int = _to_int(args.get("quantity", 1), 1)
			if side == "BID":
				@warning_ignore("integer_division")
				var coin_escrow: int = maxi(1, (price_bp * qty) / 1000)
				if not manor.try_spend_resource("COIN", coin_escrow):
					return {"ok": false, "error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE}
			else:
				if not manor.try_spend_resource(comm, qty):
					return {"ok": false, "error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE}
			var m_res: Dictionary = regional_market.place_order(nid, player_id, comm, side, price_bp, qty, tick_id)
			return m_res

		"CMD_CANCEL_MARKET_ORDER":
			var oid: String = str(args.get("order_id", ""))
			var ord_before: Dictionary = regional_market.get_order(oid)
			var c_ord_res: Dictionary = regional_market.cancel_order(oid, player_id)
			if _to_bool(c_ord_res.get("ok", false), false):
				var manor: ManorState = _get_manor(player_id)
				if manor != null:
					var rem_q: int = maxi(0, _to_int(ord_before.get("quantity", 0), 0) - _to_int(ord_before.get("filled_quantity", 0), 0))
					if str(ord_before.get("side", "")) == "BID":
						@warning_ignore("integer_division")
						var refund_coin: int = maxi(0, (_to_int(ord_before.get("price_bp", 0), 0) * rem_q) / 1000)
						var _ac: int = manor.add_resource("COIN", refund_coin)
					else:
						var _ag: int = manor.add_resource(str(ord_before.get("commodity", "GRAIN")), rem_q)
			return c_ord_res

		"CMD_ENLIST_FACTION":
			var target_fid: String = str(args.get("faction_id", ""))
			var init_rank: String = str(args.get("initial_rank", "RANK_9"))
			var e_res: Dictionary = faction_manager.enlist_officer(player_id, target_fid, init_rank)
			if _to_bool(e_res.get("ok", false), false):
				var _sub_f: bool = interest_manager.subscribe(pkey, DtoSchemas.CHAN_FACTION + ":" + target_fid)
			return e_res

		"CMD_POST_MISSION":
			var p_prof: Dictionary = faction_manager.get_player_profile(player_id)
			var fid: String = str(p_prof.get("faction_id", ""))
			return faction_manager.post_mission(fid, args)

		"CMD_APPOINT_GOVERNOR":
			return faction_manager.appoint_governor(
				player_id,
				str(args.get("target_player_id", "")),
				str(args.get("node_id", "")),
				world_graph
			)

		"CMD_SET_NODE_POLICY":
			return faction_manager.set_node_local_policy(
				player_id,
				str(args.get("node_id", "")),
				_to_int(args.get("tax_rate_bp", 1000), 1000),
				_to_int(args.get("defense_budget", 0), 0),
				world_graph
			)

		"CMD_PROPOSE_OR_SIGN_TREATY":
			var p_prof: Dictionary = faction_manager.get_player_profile(player_id)
			var my_fid: String = str(p_prof.get("faction_id", ""))
			return diplomacy_engine.propose_and_sign_treaty(
				my_fid,
				str(args.get("target_faction_id", "")),
				str(args.get("treaty_type", "NON_AGGRESSION")),
				_to_int(args.get("duration_days", 10), 10),
				clock,
				_to_int(args.get("tribute_coin_per_day", 0), 0),
				_to_int(args.get("tribute_grain_per_day", 0), 0)
			)

		"CMD_BREAK_TREATY":
			var p_prof: Dictionary = faction_manager.get_player_profile(player_id)
			var my_fid: String = str(p_prof.get("faction_id", ""))
			return diplomacy_engine.break_treaty(
				str(args.get("treaty_id", "")),
				my_fid,
				faction_manager,
				_collect_all_pawns(),
				clock
			)

		"CMD_FUND_INSURGENTS":
			var p_prof: Dictionary = faction_manager.get_player_profile(player_id)
			var my_fid: String = str(p_prof.get("faction_id", ""))
			return diplomacy_engine.fund_regional_insurgency(
				my_fid,
				str(args.get("target_node_id", "")),
				_to_int(args.get("coin_amount", 500), 500),
				faction_manager,
				world_graph
			)

		"CMD_CREATE_COALITION_RALLY":
			var p_prof: Dictionary = faction_manager.get_player_profile(player_id)
			var my_fid: String = str(p_prof.get("faction_id", ""))
			var army_v: Variant = args.get("army", args)
			var army_d: Dictionary = {}
			if army_v is Dictionary:
				var ad_tmp: Dictionary = army_v
				army_d = ad_tmp.duplicate(true)
			army_d["owner_player_id"] = player_id
			return siege_resolver.create_coalition_rally(
				my_fid,
				str(args.get("target_node_id", "")),
				army_d,
				clock
			)

		"CMD_JOIN_COALITION_RALLY":
			var p_prof: Dictionary = faction_manager.get_player_profile(player_id)
			var my_fid: String = str(p_prof.get("faction_id", ""))
			var army_v: Variant = args.get("army", args)
			var army_d: Dictionary = {}
			if army_v is Dictionary:
				var ad_tmp2: Dictionary = army_v
				army_d = ad_tmp2.duplicate(true)
			army_d["owner_player_id"] = player_id
			army_d["faction_id"] = my_fid
			return siege_resolver.join_coalition_rally(
				str(args.get("rally_id", "")),
				army_d,
				diplomacy_engine,
				clock
			)

		"CMD_EXECUTE_COALITION_SIEGE":
			var rally_id: String = str(args.get("rally_id", ""))
			var target_nid: String = str(args.get("target_node_id", ""))
			var def_v: Variant = args.get("defender_army", {"troop_count": 400, "morale_bp": 8000})
			var def_army: Dictionary = def_v if def_v is Dictionary else {"troop_count": 400, "morale_bp": 8000}
			return siege_resolver.resolve_coalition_siege(
				rally_id,
				target_nid,
				def_army,
				world_graph,
				social_service,
				clock,
				world_seed,
				faction_manager
			)

		"CMD_HOST_BANQUET":
			var manor: ManorState = _get_manor(player_id)
			if manor == null:
				return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE}
			var host_pawn: PawnEntity = manor.get_pawn_by_id(str(args.get("host_pawn_id", player_id + "_avatar")))
			if host_pawn == null and not manor.pawns.is_empty():
				host_pawn = manor.pawns[0]
			var guest_pawns: Array[PawnEntity] = []
			for p: PawnEntity in manor.pawns:
				if host_pawn != null and p.pawn_id != host_pawn.pawn_id:
					guest_pawns.append(p)
			return social_service.host_banquet(
				manor,
				host_pawn,
				guest_pawns,
				_to_int(args.get("wine_cost", 10), 10),
				_to_int(args.get("grain_cost", 20), 20),
				clock,
				world_seed
			)

		"CMD_SOW_DISCORD":
			var agent_m: ManorState = _get_manor(player_id)
			var agent_p: PawnEntity = agent_m.get_pawn_by_id(str(args.get("agent_pawn_id", player_id + "_avatar"))) if agent_m != null else null
			var target_p: PawnEntity = _find_pawn_globally(str(args.get("target_pawn_id", "")))
			return espionage_service.execute_sow_discord(agent_p, target_p, clock, world_seed)

		"CMD_POACH_RETAINER":
			var dest_m: ManorState = _get_manor(player_id)
			var agent_p: PawnEntity = dest_m.get_pawn_by_id(str(args.get("agent_pawn_id", player_id + "_avatar"))) if dest_m != null else null
			var target_p: PawnEntity = _find_pawn_globally(str(args.get("target_pawn_id", "")))
			var src_m: ManorState = _get_manor(target_p.owner_player_id) if target_p != null else null
			return espionage_service.execute_poach_retainer(
				agent_p,
				target_p,
				_to_int(args.get("offer_coin", 500), 500),
				faction_manager,
				clock,
				world_seed,
				src_m,
				dest_m
			)

		"CMD_RAISE_UPRISING":
			var manor: ManorState = _get_manor(player_id)
			var up_res: Dictionary = espionage_service.raise_free_officer_uprising(
				player_id,
				manor,
				str(args.get("node_id", manor.host_node_id if manor != null else "ye_county")),
				str(args.get("new_faction_id", "fac_" + player_id)),
				faction_manager,
				world_graph,
				str(args.get("new_faction_name", ""))
			)
			if _to_bool(up_res.get("ok", false), false):
				var new_fid: String = str(up_res.get("new_faction_id", ""))
				var _sub_u: bool = interest_manager.subscribe(pkey, DtoSchemas.CHAN_FACTION + ":" + new_fid)
			return up_res

		"CMD_DECIDE_INBOX_EVENT":
			var sub_res: Dictionary = chronicle_inbox.submit_decision(
				player_id,
				str(args.get("decision_id", "")),
				str(args.get("chosen_option", "")),
				tick_id
			)
			if _to_bool(sub_res.get("ok", false), false):
				var dec_v: Variant = sub_res.get("decision", {})
				if dec_v is Dictionary:
					var dec_d: Dictionary = dec_v
					_apply_inbox_decision_outcome(dec_d)
			return sub_res

		"CMD_SUBSCRIBE_CHANNEL":
			var chan: String = str(args.get("channel", ""))
			var unsub: bool = _to_bool(args.get("unsubscribe", false), false)
			var ok_s: bool = false
			if unsub:
				ok_s = interest_manager.unsubscribe(pkey, chan)
			else:
				ok_s = interest_manager.subscribe(pkey, chan)
			_sync_all_manor_lods()
			return {"ok": ok_s, "channel": chan, "unsubscribed": unsub}

	return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA}


func _apply_inbox_decision_outcome(dec: Dictionary) -> void:
	var pid: String = str(dec.get("player_id", ""))
	var etype: String = str(dec.get("event_type", ""))
	var choice: String = str(dec.get("chosen_option", ""))
	var manor: ManorState = _get_manor(pid)
	if etype == "RETAINER_PROPOSAL":
		var payload_v: Variant = dec.get("payload", {})
		var payload: Dictionary = payload_v if payload_v is Dictionary else {}
		var prop_id: String = str(payload.get("proposal_id", ""))
		var pawn_id: String = str(payload.get("pawn_id", ""))
		var pawn: PawnEntity = manor.get_pawn_by_id(pawn_id) if manor != null else null
		if not prop_id.is_empty() and pawn != null:
			if choice == "ADOPT":
				var _ar: Dictionary = faction_manager.adopt_proposal(prop_id, pawn, manor)
			else:
				var _rr: Dictionary = faction_manager.reject_proposal(prop_id, pawn)
	elif etype == "IMPERIAL_LEVY" and manor != null:
		if choice == "PAY_LEVY":
			var _sp: bool = manor.try_spend_resource("COIN", mini(100, manor.get_resource("COIN")))
		else:
			var _ad: int = manor.add_resource("MERIT_PRESTIGE", 0)
	_record_tick_event("INBOX_DECISION_RESOLVED", {
		"player_id": pid,
		"decision_id": str(dec.get("decision_id", "")),
		"choice": choice,
		"resolution_mode": str(dec.get("resolution_mode", ""))
	})


func _get_manor(player_id: String) -> ManorState:
	var v: Variant = manors.get(player_id, null)
	if v is ManorState:
		var m: ManorState = v
		return m
	return null


func _find_pawn_globally(pawn_id: String) -> PawnEntity:
	if pawn_id.is_empty():
		return null
	for pid_v: Variant in manors.keys():
		var m_v: Variant = manors[pid_v]
		if m_v is ManorState:
			var m: ManorState = m_v
			var p: PawnEntity = m.get_pawn_by_id(pawn_id)
			if p != null:
				return p
	return null


func _collect_all_pawns() -> Array[PawnEntity]:
	var out: Array[PawnEntity] = []
	for pid_v: Variant in _sorted_keys(manors):
		var m_v: Variant = manors[pid_v]
		if m_v is ManorState:
			var m: ManorState = m_v
			for p: PawnEntity in m.pawns:
				out.append(p)
	return out


static func _sorted_keys(d: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for k: Variant in d.keys():
		keys.append(str(k))
	keys.sort()
	return keys


func _step_raid_arrivals(tick_id: int) -> void:
	var events: Array[Dictionary] = event_bus.drain_for_tick(tick_id)
	for ev: Dictionary in events:
		var ev_type: String = str(ev.get("event", ""))
		var p_v: Variant = ev.get("payload", {})
		if not (p_v is Dictionary):
			continue
		var payload: Dictionary = p_v
		if ev_type == SimEventBus.EVENT_MACRO_TO_MICRO_RAID_INCOMING:
			var target_mid: String = str(payload.get("target_manor_id", ""))
			for pid_str: String in _sorted_keys(manors):
				var m: ManorState = manors[pid_str]
				if m.manor_id == target_mid:
					var acct_rv: Variant = player_accounts.get(pid_str, {})
					var acct_rd: Dictionary = acct_rv if acct_rv is Dictionary else {}
					var is_online: bool = _to_int(acct_rd.get("is_online", 0), 0) == 1
					var raid_sum: Dictionary = ManorSimulator.resolve_manor_raid_defense(m, payload, clock, world_seed, is_online)
					if player_accounts.has(pid_str):
						var acct: Dictionary = player_accounts[pid_str]
						acct["truce_shield_until_tick"] = m.truce_shield_until_tick
					if not is_online:
						chronicle_inbox.record_offline_event(pid_str, ChronicleInboxService.CATEGORY_BATTLE_REPLAY, raid_sum)
					_record_tick_event("RAID_DEFENSE_RESOLVED", raid_sum)
					break
		elif ev_type == SimEventBus.EVENT_CARAVAN_ARRIVED:
			var eid: String = str(payload.get("entity_id", ""))
			var nid: String = str(payload.get("node_id", ""))
			var owner_pid: String = str(payload.get("owner_player_id", ""))
			if army_manager.entities.has(eid):
				var ent: Dictionary = army_manager.entities[eid]
				var settle_res: Dictionary = regional_market.settle_caravan_trade(ent, nid, tick_id)
				var owner_m: ManorState = _get_manor(owner_pid)
				if owner_m != null:
					var earned: int = _to_int(settle_res.get("coin_earned", 0), 0)
					var _ac: int = owner_m.add_resource("COIN", earned)
				_record_tick_event(SimEventBus.EVENT_CARAVAN_ARRIVED, settle_res)


func _run_daily_settlement() -> void:
	var tick_id: int = clock.current_tick_id
	var manors_by_pid: Dictionary = manors
	var pawns_by_pid: Dictionary = {}
	for pid: String in _sorted_keys(manors):
		var m: ManorState = manors[pid]
		for p: PawnEntity in m.pawns:
			if p.is_avatar:
				pawns_by_pid[pid] = p
				break

	# 1. Macro node tax collection into owning faction treasuries
	for nid: String in world_graph.get_node_ids():
		var nd: Dictionary = world_graph.get_node(nid)
		var owner_fid: String = str(nd.get("owner_faction_id", ""))
		var tax_bp: int = _to_int(nd.get("tax_rate_bp", 1000), 1000)
		@warning_ignore("integer_division")
		var coin_tax: int = maxi(10, tax_bp / 5)
		@warning_ignore("integer_division")
		var grain_tax: int = maxi(20, tax_bp / 2)
		if faction_manager.has_faction(owner_fid):
			var _adj: Dictionary = faction_manager.adjust_faction_treasury(owner_fid, coin_tax, grain_tax, 0)

	# 2. Daily stipends & auto-assigned idle faction missions
	for fid: String in faction_manager.get_faction_ids():
		if fid == "NEUTRAL" or fid == "YELLOW_TURBAN":
			continue
		var stip_res: Dictionary = faction_manager.settle_daily_stipends(fid, pawns_by_pid, manors_by_pid, clock, event_bus)
		var paid_v: Variant = stip_res.get("paid_officers", [])
		if paid_v is Array:
			var paid_arr: Array = paid_v
			for p_item: Variant in paid_arr:
				var paid_pid: String = str(p_item)
				var p_acct_v: Variant = player_accounts.get(paid_pid, {})
				var p_acct_d: Dictionary = p_acct_v if p_acct_v is Dictionary else {}
				var is_on: bool = _to_int(p_acct_d.get("is_online", 0), 0) == 1
				if not is_on:
					chronicle_inbox.record_offline_event(paid_pid, ChronicleInboxService.CATEGORY_STIPEND, {
						"tick_id": tick_id,
						"faction_id": fid,
						"coin": _to_int(stip_res.get("total_coin_paid", 0), 0),
						"grain": _to_int(stip_res.get("total_grain_paid", 0), 0)
					})
		var completed_missions: Array[Dictionary] = faction_manager.process_idle_mission_queue(fid, clock, world_seed, manors_by_pid, pawns_by_pid)
		for cm: Dictionary in completed_missions:
			var cm_pid: String = str(cm.get("player_id", ""))
			var m_acct_v: Variant = player_accounts.get(cm_pid, {})
			var m_acct_d: Dictionary = m_acct_v if m_acct_v is Dictionary else {}
			var is_on_m: bool = _to_int(m_acct_d.get("is_online", 0), 0) == 1
			if not is_on_m:
				chronicle_inbox.record_offline_event(cm_pid, ChronicleInboxService.CATEGORY_MISSION, cm)
			_record_tick_event("MISSION_COMPLETED", cm)

	# 3. Daily treaties & storyteller evaluation
	var treaty_evs: Array[Dictionary] = diplomacy_engine.settle_daily_treaties(faction_manager, clock)
	for tev: Dictionary in treaty_evs:
		_record_tick_event(str(tev.get("type", "TREATY_EVENT")), tev)

	for pid: String in _sorted_keys(manors):
		var m: ManorState = manors[pid]
		var acct_v: Variant = player_accounts.get(pid, {})
		var acct: Dictionary = acct_v if acct_v is Dictionary else {}
		var pstate: Dictionary = {
			"player_id": pid,
			"adaptation_factor_bp": _to_int(acct.get("adaptation_factor_bp", 1000), 1000)
		}
		var st_sum: Dictionary = storyteller.evaluate_daily_storyteller(pstate, m, clock, world_seed, event_bus)
		acct["adaptation_factor_bp"] = storyteller.get_player_adaptation(pid)
		var cat: String = str(st_sum.get("category", "CALM"))
		if cat != "CALM":
			_record_tick_event("STORYTELLER_" + cat, st_sum)
			if str(st_sum.get("event_code", "")) == "IMPERIAL_LEVY":
				var _enq: Dictionary = chronicle_inbox.enqueue_decision(
					pid,
					"IMPERIAL_LEVY",
					["PAY_LEVY", "REFUSE_LEVY"],
					"PAY_LEVY",
					tick_id + SimClock.TICKS_PER_DAY,
					st_sum
				)

	# 4. Expire overdue async inbox decisions using default fallbacks (never blocks sim)
	var expired_decs: Array[Dictionary] = chronicle_inbox.process_expired_decisions(tick_id)
	for exp_d: Dictionary in expired_decs:
		_apply_inbox_decision_outcome(exp_d)

	# 5. Invoke daily persistence checkpoint hook if attached
	_emit_checkpoint_hook()


func step_micro_tick() -> Dictionary:
	var _drained: Array[Dictionary] = _drain_transport_commands()
	var next_tick: int = clock.step_micro()
	_tick_events_buffer.clear()

	# Execute validated commands scheduled for current_tick_id
	var remaining_cmds: Array[Dictionary] = []
	for cmd_entry: Dictionary in _pending_commands:
		var exec_t: int = _to_int(cmd_entry.get("exec_tick_id", 0), 0)
		if exec_t <= next_tick:
			var p_id: Variant = cmd_entry.get("peer_id", "")
			var env_v: Variant = cmd_entry.get("envelope", {})
			if env_v is Dictionary:
				var env: Dictionary = env_v
				var _exec_res: Dictionary = _execute_validated_command(p_id, env)
		else:
			remaining_cmds.append(cmd_entry)
	_pending_commands = remaining_cmds

	_sync_all_manor_lods()

	# Step LOD 0 manors every micro tick
	for pid: String in _sorted_keys(manors):
		var m: ManorState = manors[pid]
		if m.current_lod == 0:
			ManorSimulator.step_lod0_micro_tick(m, clock, world_seed, event_bus)

	# Macro tick (every 6 micro ticks)
	var did_macro: bool = clock.is_macro_tick()
	if did_macro:
		for pid: String in _sorted_keys(manors):
			var m: ManorState = manors[pid]
			if m.current_lod == 1:
				ManorSimulator.step_lod1_macro_tick(m, clock, world_seed, event_bus)
		var _army_evs: Array[Dictionary] = army_manager.step_macro_tick(world_graph, clock, world_seed, event_bus)
		_step_raid_arrivals(next_tick)
		for nid: String in world_graph.get_node_ids():
			var _m_res: Dictionary = regional_market.match_node_orders(nid, next_tick)
		regional_market.sync_prices_to_world_graph(world_graph)

	# Daily settlement tick (every 24 micro ticks)
	var did_daily: bool = clock.is_daily_settlement_tick()
	if did_daily:
		_run_daily_settlement()

	state_crc32 = compute_state_crc32()

	# Broadcast interest-filtered MSG_TICK_DELTA on macro ticks (or when tick events occurred)
	var deltas_sent: int = 0
	if did_macro or not _tick_events_buffer.is_empty():
		var srv_state: Dictionary = {
			"clock": clock,
			"state_crc32": state_crc32,
			"world_graph": world_graph,
			"army_manager": army_manager,
			"regional_market": regional_market,
			"faction_manager": faction_manager,
			"diplomacy": diplomacy_engine,
			"siege_resolver": siege_resolver,
			"manors": manors
		}
		for pkey: String in interest_manager.peer_subscriptions.keys():
			var delta_msg: Dictionary = interest_manager.build_tick_delta_for_peer(pkey, srv_state, _tick_events_buffer)
			var chans_v: Variant = delta_msg.get("channels", {})
			var evs_v: Variant = delta_msg.get("events", [])
			var chans_empty: bool = true
			if chans_v is Dictionary:
				var chans_d: Dictionary = chans_v
				chans_empty = chans_d.is_empty()
			var evs_empty: bool = true
			if evs_v is Array:
				var evs_a: Array = evs_v
				evs_empty = evs_a.is_empty()
			if not chans_empty or not evs_empty:
				var _ok_send: bool = transport.server_send_to_peer(pkey, delta_msg)
				deltas_sent += 1

	return {
		"tick_id": next_tick,
		"macro_tick": did_macro,
		"daily_tick": did_daily,
		"state_crc32": state_crc32,
		"deltas_sent": deltas_sent
	}


func compute_state_crc32() -> int:
	return StateHasher.crc32_dict(to_deterministic_hash_dict())


func to_deterministic_hash_dict() -> Dictionary:
	var manors_arr: Array[Dictionary] = []
	for pid: String in _sorted_keys(manors):
		var mv: Variant = manors[pid]
		if mv is ManorState:
			var m_st: ManorState = mv
			manors_arr.append(m_st.to_dict())
	var accts_arr: Array[Dictionary] = []
	for pid: String in _sorted_keys(player_accounts):
		var av: Variant = player_accounts[pid]
		if av is Dictionary:
			var ad: Dictionary = av
			accts_arr.append(ad.duplicate(true))
	return {
		"world_id": world_id,
		"world_seed": world_seed,
		"clock": clock.to_dict(),
		"world_graph": world_graph.to_dict(),
		"army_manager": army_manager.to_dict(),
		"regional_market": regional_market.to_dict(),
		"storyteller": storyteller.to_dict(),
		"faction_manager": faction_manager.to_dict(),
		"espionage_service": espionage_service.to_dict(),
		"diplomacy_engine": diplomacy_engine.to_dict(),
		"social_service": social_service.to_dict(),
		"siege_resolver": siege_resolver.to_dict(),
		"manors": manors_arr,
		"player_accounts": accts_arr,
		"chronicle_inbox": chronicle_inbox.to_dict()
	}


func _map_node_tier_sql(raw_tier: String) -> String:
	match raw_tier:
		"CAPITAL", "CAPITAL_METROPOLIS":
			return "CAPITAL_METROPOLIS"
		"CITY", "COMMANDERY_CITY":
			return "COMMANDERY_CITY"
		"PASS", "STRATEGIC_PASS":
			return "STRATEGIC_PASS"
		_:
			return "COUNTY_TOWN"


func _map_royal_rank_sql(raw_rank: String) -> String:
	match raw_rank:
		"GOVERNOR_INSPECTOR", "PREFECT":
			return "PREFECT"
		"PROVINCE_GOVERNOR", "GOVERNOR_GENERAL":
			return "GOVERNOR_GENERAL"
		"DUKE", "KING", "EMPEROR":
			return raw_rank
		_:
			return "PREFECT"


func _map_storyteller_sql(raw_st: String) -> String:
	match raw_st:
		"ST_SIMA_QIAN", "SIMA_QIAN":
			return "SIMA_QIAN"
		"ST_DONG_ZHUO", "DONG_ZHUO":
			return "DONG_ZHUO"
		"ST_WEN_JING", "WEN_JING":
			return "WEN_JING"
		_:
			return "SIMA_QIAN"


func export_relational_snapshot() -> Dictionary:
	# 1. world_meta
	var world_meta_rows: Array[Dictionary] = [{
		"world_id": world_id,
		"world_seed": world_seed,
		"current_tick_id": clock.current_tick_id,
		"current_day_id": clock.get_day_id(),
		"season": clock.get_season(),
		"storyteller_id": _map_storyteller_sql(storyteller.persona_id),
		"state_crc32": state_crc32,
		"updated_at_utc": "tick:%d" % clock.current_tick_id
	}]

	# 2. factions
	var factions_rows: Array[Dictionary] = []
	for fid: String in faction_manager.get_faction_ids():
		var f: Dictionary = faction_manager.get_faction(fid)
		factions_rows.append({
			"faction_id": fid,
			"name": str(f.get("name", fid)),
			"lord_player_id": str(f.get("lord_player_id", "npc_lord")),
			"capital_node_id": str(f.get("capital_node_id", "luoyang")),
			"royal_rank": _map_royal_rank_sql(str(f.get("royal_rank", "PREFECT"))),
			"treasury_grain": maxi(0, _to_int(f.get("treasury_grain", 0), 0)),
			"treasury_coin": maxi(0, _to_int(f.get("treasury_coin", 0), 0)),
			"imperial_edicts": maxi(0, _to_int(f.get("imperial_edicts", 0), 0)),
			"prestige": maxi(0, _to_int(f.get("prestige", 0), 0)),
			"oathbreaker_until_tick": maxi(0, _to_int(f.get("oathbreaker_until_tick", 0), 0))
		})

	# 3. macro_nodes
	var macro_nodes_rows: Array[Dictionary] = []
	for nid: String in world_graph.get_node_ids():
		var nd: Dictionary = world_graph.get_node(nid)
		var owner_fid: String = str(nd.get("owner_faction_id", "NEUTRAL"))
		if not faction_manager.has_faction(owner_fid):
			owner_fid = "NEUTRAL"
		var gov_pid: String = str(nd.get("governor_player_id", ""))
		var max_hp: int = maxi(1, _to_int(nd.get("max_fortification_hp", 5000), 5000))
		var cur_hp: int = clampi(_to_int(nd.get("fortification_hp", max_hp), max_hp), 0, max_hp)
		macro_nodes_rows.append({
			"node_id": nid,
			"name": str(nd.get("name_ko", nid)),
			"province": str(nd.get("province", "YU_ZHOU")),
			"node_tier": _map_node_tier_sql(str(nd.get("node_tier", "COUNTY"))),
			"owner_faction_id": owner_fid,
			"governor_player_id": gov_pid if not gov_pid.is_empty() else null,
			"fortification_hp": cur_hp,
			"max_fortification_hp": max_hp,
			"public_order_bp": clampi(_to_int(nd.get("security_bp", 7000), 7000), 0, 10000),
			"bandit_pressure_bp": clampi(_to_int(nd.get("bandit_pressure_bp", 200), 200), 0, 10000),
			"tax_rate_bp": clampi(_to_int(nd.get("tax_rate_bp", 1000), 1000), 500, 5000),
			"treasury_grain": maxi(0, _to_int(nd.get("treasury_grain", 0), 0)),
			"treasury_coin": maxi(0, _to_int(nd.get("treasury_coin", 0), 0)),
			"grain_price_bp": clampi(_to_int(nd.get("grain_price_bp", 1000), 1000), 100, 100000),
			"iron_price_bp": clampi(_to_int(nd.get("iron_price_bp", 2000), 2000), 100, 100000)
		})

	# 4. persona_import_challenges
	var challenges_rows: Array[Dictionary] = []
	for cid: String in _sorted_keys(persona_challenges):
		var cv: Variant = persona_challenges[cid]
		if cv is Dictionary:
			var ch: Dictionary = cv
			var st: String = str(ch.get("status", "ISSUED"))
			var cat: Variant = ch.get("consumed_at_tick", null)
			if st == "CONSUMED" and cat == null:
				cat = _to_int(ch.get("issued_at_tick", 0), 0)
			elif st != "CONSUMED":
				cat = null
			challenges_rows.append({
				"challenge_id": cid,
				"account_id": str(ch.get("account_id", "acc")),
				"bound_player_id": ch.get("bound_player_id", null),
				"nonce": str(ch.get("nonce", cid + "_nonce")),
				"session_salt": str(ch.get("session_salt", "salt")),
				"cipher_key_hint": str(ch.get("cipher_key_hint", "hint")),
				"issued_at_tick": maxi(0, _to_int(ch.get("issued_at_tick", 0), 0)),
				"ttl_expires_tick": maxi(1, _to_int(ch.get("ttl_expires_tick", 900), 900)),
				"consumed_at_tick": cat,
				"status": st,
				"attempt_count": clampi(_to_int(ch.get("attempt_count", 0), 0), 0, 10),
				"max_attempts": clampi(_to_int(ch.get("max_attempts", 3), 3), 1, 10),
				"cooldown_until_tick": maxi(0, _to_int(ch.get("cooldown_until_tick", 0), 0)),
				"last_coercion_flag": str(ch.get("last_coercion_flag", "R0_CLEAN")),
				"last_reject_reason": ch.get("last_reject_reason", null)
			})

	# 5. players
	var players_rows: Array[Dictionary] = []
	var all_pids: Array[String] = _sorted_keys(player_accounts)
	for fp_id: String in faction_manager.get_player_ids():
		if not all_pids.has(fp_id):
			all_pids.append(fp_id)
	all_pids.sort()

	for pid: String in all_pids:
		var acct_v: Variant = player_accounts.get(pid, {})
		var acct: Dictionary = acct_v if acct_v is Dictionary else {}
		var prof: Dictionary = faction_manager.get_player_profile(pid)
		var m: ManorState = _get_manor(pid)
		var host_nid: String = m.host_node_id if m != null else str(acct.get("host_node_id", "xuchang"))
		if not world_graph.has_node(host_nid) and not world_graph.get_node_ids().is_empty():
			host_nid = world_graph.get_node_ids()[0]
		var fid: String = str(prof.get("faction_id", ""))
		players_rows.append({
			"player_id": pid,
			"display_name": str(acct.get("display_name", pid)),
			"auth_token_hash": str(acct.get("auth_token_hash", "hash")),
			"origin_archetype": str(acct.get("origin_archetype", "ORIGIN_CHIVALROUS_HERO")),
			"creation_mode": str(acct.get("creation_mode", "INTERVIEW_ONLY")),
			"persona_profile_json": str(acct.get("persona_profile_json", "{}")),
			"persona_challenge_id": acct.get("persona_challenge_id", null),
			"import_audit_status": str(acct.get("import_audit_status", "NONE")),
			"coercion_flag": str(acct.get("coercion_flag", "R0_CLEAN")),
			"role_tier": str(prof.get("role_tier", "FREE_OFFICER")),
			"faction_id": fid if not fid.is_empty() else null,
			"court_rank": str(prof.get("court_rank", "NONE")),
			"war_merit": maxi(0, _to_int(prof.get("war_merit", 0), 0)),
			"host_node_id": host_nid,
			"manor_id": m.manor_id if m != null else str(acct.get("manor_id", "manor_" + pid)),
			"is_online": 1 if _to_int(acct.get("is_online", 0), 0) == 1 else 0,
			"last_seen_tick": maxi(0, _to_int(acct.get("last_seen_tick", 0), 0)),
			"truce_shield_until_tick": m.truce_shield_until_tick if m != null else maxi(0, _to_int(acct.get("truce_shield_until_tick", 0), 0)),
			"adaptation_factor_bp": clampi(_to_int(acct.get("adaptation_factor_bp", 1000), 1000), 400, 1500)
		})

	# 6. manors & 7. pawns_officers
	var manors_rows: Array[Dictionary] = []
	var pawns_rows: Array[Dictionary] = []
	for pid: String in _sorted_keys(manors):
		var m: ManorState = manors[pid]
		var m_host: String = m.host_node_id
		if not world_graph.has_node(m_host) and not world_graph.get_node_ids().is_empty():
			m_host = world_graph.get_node_ids()[0]
		manors_rows.append({
			"manor_id": m.manor_id,
			"player_id": m.player_id,
			"host_node_id": m_host,
			"current_lod": 0 if m.current_lod == 0 else 1,
			"grain_stock": m.get_resource("GRAIN"),
			"coin_stock": m.get_resource("COIN"),
			"iron_stock": m.get_resource("IRON"),
			"wood_stock": m.get_resource("WOOD"),
			"horse_stock": m.get_resource("HORSES"),
			"herbs_wine_stock": m.get_resource("HERBS_WINE"),
			"weapon_stock": m.get_resource("WEAPONS"),
			"household_troops": clampi(m.household_troops, 0, 3000),
			"vault_protected_bp": clampi(m.vault_protected_bp, 4000, 6500),
			"wall_hp": maxi(0, m.wall_hp),
			"standing_doctrine_json": StateHasher.canonical_json(m.standing_doctrine),
			"grid_zones_json": StateHasher.canonical_json({"zones": m.zones, "buildings": m.buildings})
		})
		for p: PawnEntity in m.pawns:
			pawns_rows.append({
				"pawn_id": p.pawn_id,
				"owner_player_id": p.owner_player_id,
				"manor_id": m.manor_id,
				"name": p.name,
				"is_avatar": 1 if p.is_avatar else 0,
				"state": p.state,
				"health_state": p.health_state,
				"leadership": p.get_stat("LEA"),
				"martial": p.get_stat("MAR"),
				"intelligence": p.get_stat("INT"),
				"politics": p.get_stat("POL"),
				"charisma": p.get_stat("CHA"),
				"food_need_bp": p.get_need("FOOD"),
				"rest_need_bp": p.get_need("REST"),
				"morale_bp": p.get_need("MORALE"),
				"loyalty_bp": p.get_need("LOYALTY"),
				"ambition_bp": p.get_need("AMBITION"),
				"mood": p.mood,
				"mental_state": p.mental_state,
				"traits_json": StateHasher.canonical_json(p.traits),
				"work_priorities_json": StateHasher.canonical_json(p.work_priorities),
				"daily_schedule_json": StateHasher.canonical_json(p.daily_schedule)
			})

	# 8. armies_caravans
	var armies_rows: Array[Dictionary] = []
	for eid: String in army_manager.get_entity_ids():
		var ent: Dictionary = army_manager.get_entity(eid)
		var owner_pid: String = str(ent.get("owner_player_id", ""))
		if owner_pid.is_empty():
			continue
		armies_rows.append({
			"entity_id": eid,
			"owner_player_id": owner_pid,
			"faction_id": str(ent.get("faction_id", "NEUTRAL")),
			"unit_type": str(ent.get("unit_type", "ARMY")),
			"current_node_id": str(ent.get("current_node_id", "")),
			"current_edge_id": str(ent.get("current_edge_id", "")),
			"edge_progress_pm": clampi(_to_int(ent.get("edge_progress_pm", 0), 0), 0, 1000),
			"troop_count": maxi(0, _to_int(ent.get("troop_count", 0), 0)),
			"morale_bp": clampi(_to_int(ent.get("morale_bp", 8000), 8000), 0, 10000),
			"carried_grain": maxi(0, _to_int(ent.get("carried_grain", 0), 0)),
			"carried_coin": maxi(0, _to_int(ent.get("carried_coin", 0), 0)),
			"cargo_json": StateHasher.canonical_json(ent.get("cargo", {})),
			"doctrine_json": StateHasher.canonical_json(ent.get("standing_doctrine", {}))
		})

	# 9. market_orders
	var orders_rows: Array[Dictionary] = []
	for oid: String in _sorted_keys(regional_market.orders):
		var ord: Dictionary = regional_market.get_order(oid)
		var qty: int = maxi(1, _to_int(ord.get("quantity", 1), 1))
		var filled: int = clampi(_to_int(ord.get("filled_quantity", 0), 0), 0, qty)
		orders_rows.append({
			"order_id": oid,
			"node_id": str(ord.get("node_id", "xuchang")),
			"player_id": str(ord.get("player_id", "")),
			"commodity": str(ord.get("commodity", "GRAIN")),
			"side": str(ord.get("side", "BID")),
			"price_bp": clampi(_to_int(ord.get("price_bp", 1000), 1000), 100, 100000),
			"quantity": qty,
			"filled_quantity": filled,
			"created_tick": maxi(0, _to_int(ord.get("created_tick", 0), 0)),
			"status": str(ord.get("status", "OPEN"))
		})

	# 10. command_audit_log
	var audit_rows: Array[Dictionary] = []
	for al: Dictionary in command_validator.audit_log:
		audit_rows.append({
			"tick_id": maxi(0, _to_int(al.get("tick_id", 0), 0)),
			"player_id": str(al.get("player_id", "UNKNOWN")),
			"cmd_type": str(al.get("cmd_type", "UNKNOWN")),
			"status": str(al.get("status", "REJECTED")),
			"reject_reason": str(al.get("reject_reason", "")) if not str(al.get("reject_reason", "")).is_empty() else null,
			"payload_json": str(al.get("payload_json", "{}"))
		})

	return {
		"world_meta": world_meta_rows,
		"factions": factions_rows,
		"macro_nodes": macro_nodes_rows,
		"persona_import_challenges": challenges_rows,
		"players": players_rows,
		"manors": manors_rows,
		"pawns_officers": pawns_rows,
		"armies_caravans": armies_rows,
		"market_orders": orders_rows,
		"command_audit_log": audit_rows
	}


func to_dict() -> Dictionary:
	var core: Dictionary = to_deterministic_hash_dict()
	core["next_ev_seq"] = _next_ev_seq
	core["state_crc32"] = state_crc32
	core["sessions_by_peer"] = sessions_by_peer.duplicate(true)
	core["peer_by_player"] = peer_by_player.duplicate(true)
	core["persona_challenges"] = persona_challenges.duplicate(true)
	core["account_cooldown_until"] = account_cooldown_until.duplicate(true)
	core["account_tamper_strikes"] = account_tamper_strikes.duplicate(true)
	core["pending_commands"] = _pending_commands.duplicate(true)
	core["event_bus"] = event_bus.to_dict()
	core["command_validator"] = command_validator.to_dict()
	core["interest_manager"] = interest_manager.to_dict()
	return core


static func from_dict(data: Dictionary) -> AuthoritativeServer:
	var seed_v: int = _to_int(data.get("world_seed", 18401), 18401)
	var srv: AuthoritativeServer = AuthoritativeServer.new(seed_v)
	srv.world_id = str(data.get("world_id", WORLD_ID_DEFAULT))
	srv._next_ev_seq = maxi(1, _to_int(data.get("next_ev_seq", 1), 1))

	var clock_v: Variant = data.get("clock", null)
	if clock_v is Dictionary:
		var cd: Dictionary = clock_v
		srv.clock = SimClock.from_dict(cd)
	var eb_v: Variant = data.get("event_bus", null)
	if eb_v is Dictionary:
		var ebd: Dictionary = eb_v
		srv.event_bus = SimEventBus.from_dict(ebd)
	var wg_v: Variant = data.get("world_graph", null)
	if wg_v is Dictionary:
		var wgd: Dictionary = wg_v
		srv.world_graph = WorldGraph.from_dict(wgd)
	var am_v: Variant = data.get("army_manager", null)
	if am_v is Dictionary:
		var amd: Dictionary = am_v
		srv.army_manager = ArmyCaravanManager.from_dict(amd)
	var rm_v: Variant = data.get("regional_market", null)
	if rm_v is Dictionary:
		var rmd: Dictionary = rm_v
		srv.regional_market = RegionalMarket.from_dict(rmd)
	var st_v: Variant = data.get("storyteller", null)
	if st_v is Dictionary:
		var std: Dictionary = st_v
		srv.storyteller = StorytellerEngine.from_dict(std)
	var fm_v: Variant = data.get("faction_manager", null)
	if fm_v is Dictionary:
		var fmd: Dictionary = fm_v
		srv.faction_manager = FactionManager.from_dict(fmd)
	var es_v: Variant = data.get("espionage_service", null)
	if es_v is Dictionary:
		var esd: Dictionary = es_v
		srv.espionage_service = EspionageService.from_dict(esd)
	var de_v: Variant = data.get("diplomacy_engine", null)
	if de_v is Dictionary:
		var ded: Dictionary = de_v
		srv.diplomacy_engine = DiplomacyTreatyEngine.from_dict(ded)
	var ss_v: Variant = data.get("social_service", null)
	if ss_v is Dictionary:
		var ssd: Dictionary = ss_v
		srv.social_service = SocialBanquetService.from_dict(ssd)
	var sr_v: Variant = data.get("siege_resolver", null)
	if sr_v is Dictionary:
		var srd: Dictionary = sr_v
		srv.siege_resolver = SiegeBattleResolver.from_dict(srd)
	var cv_v: Variant = data.get("command_validator", null)
	if cv_v is Dictionary:
		var cvd: Dictionary = cv_v
		srv.command_validator = CommandValidator.from_dict(cvd)
	var im_v: Variant = data.get("interest_manager", null)
	if im_v is Dictionary:
		var imd: Dictionary = im_v
		srv.interest_manager = InterestDeltaManager.from_dict(imd)
	var ci_v: Variant = data.get("chronicle_inbox", null)
	if ci_v is Dictionary:
		var cid: Dictionary = ci_v
		srv.chronicle_inbox = ChronicleInboxService.from_dict(cid)

	srv.manors.clear()
	var manors_v: Variant = data.get("manors", [])
	if manors_v is Array:
		var m_arr: Array = manors_v
		for item: Variant in m_arr:
			if item is Dictionary:
				var md: Dictionary = item
				var m: ManorState = ManorState.from_dict(md)
				srv.manors[m.player_id] = m

	srv.player_accounts.clear()
	var accts_v: Variant = data.get("player_accounts", [])
	if accts_v is Array:
		var a_arr: Array = accts_v
		for item: Variant in a_arr:
			if item is Dictionary:
				var ad: Dictionary = item
				var pid: String = str(ad.get("player_id", ""))
				if not pid.is_empty():
					srv.player_accounts[pid] = ad.duplicate(true)

	var sbp_v: Variant = data.get("sessions_by_peer", {})
	if sbp_v is Dictionary:
		var sbp: Dictionary = sbp_v
		srv.sessions_by_peer = sbp.duplicate(true)

	var pbp_v: Variant = data.get("peer_by_player", {})
	if pbp_v is Dictionary:
		var pbp: Dictionary = pbp_v
		srv.peer_by_player = pbp.duplicate(true)

	var pc_v: Variant = data.get("persona_challenges", {})
	if pc_v is Dictionary:
		var pc: Dictionary = pc_v
		srv.persona_challenges = pc.duplicate(true)

	var acu_v: Variant = data.get("account_cooldown_until", {})
	if acu_v is Dictionary:
		var acu: Dictionary = acu_v
		srv.account_cooldown_until = acu.duplicate(true)

	var ats_v: Variant = data.get("account_tamper_strikes", {})
	if ats_v is Dictionary:
		var ats: Dictionary = ats_v
		srv.account_tamper_strikes = ats.duplicate(true)

	srv._pending_commands.clear()
	var pend_v: Variant = data.get("pending_commands", [])
	if pend_v is Array:
		var pa: Array = pend_v
		for item: Variant in pa:
			if item is Dictionary:
				var pd: Dictionary = item
				srv._pending_commands.append(pd.duplicate(true))

	srv.state_crc32 = srv.compute_state_crc32()
	return srv
