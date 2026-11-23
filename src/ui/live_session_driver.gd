class_name LiveSessionDriver
extends RefCounted

const MODE_NONE: int = 0
const MODE_LOCAL_DEMO: int = 1
const MODE_REMOTE_WS: int = 2

const BOT_WEI_ID: String = "lord_wei"
const BOT_SHU_ID: String = "ally_shu"
const BOT_WEI_PEER: String = "peer_lord_wei"
const BOT_SHU_PEER: String = "peer_ally_shu"

var mode: int = MODE_NONE
var player_id: String = "player_01"
var display_name: String = "조자룡"
var local_peer_id: String = "peer_player_01"

var local_server: AuthoritativeServer = null
var ws_transport: NetworkTransport = null
var ws_url: String = ""

var _bot_seq: Dictionary = {
	BOT_WEI_ID: 0,
	BOT_SHU_ID: 0
}
var _ws_was_open: bool = false
var _ws_handshake_sent: bool = false
var _remote_cmd_seq: int = 0
var _remote_client_tick: int = 0


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


func is_active() -> bool:
	return mode != MODE_NONE


func is_local_mode() -> bool:
	return mode == MODE_LOCAL_DEMO and local_server != null


func is_remote_mode() -> bool:
	return mode == MODE_REMOTE_WS and ws_transport != null


func is_remote_connected() -> bool:
	return is_remote_mode() and ws_transport.is_ws_client_open()


func get_remote_connection_state() -> String:
	if not is_remote_mode():
		return "CLOSED"
	var st: int = ws_transport.get_ws_client_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		return "OPEN"
	if st == WebSocketPeer.STATE_CONNECTING:
		return "CONNECTING"
	return "CLOSED"


func get_remote_cmd_seq() -> int:
	return _remote_cmd_seq


func get_current_tick() -> int:
	if is_local_mode():
		return local_server.clock.current_tick_id
	return _remote_client_tick


func update_remote_tick(tick_id: int) -> void:
	_remote_client_tick = maxi(_remote_client_tick, tick_id)


func stop() -> void:
	if ws_transport != null:
		ws_transport.close()
		ws_transport = null
	if local_server != null and local_server.transport != null:
		local_server.transport.close()
	local_server = null
	ws_url = ""
	_ws_was_open = false
	_ws_handshake_sent = false
	_remote_cmd_seq = 0
	_remote_client_tick = 0
	_bot_seq[BOT_WEI_ID] = 0
	_bot_seq[BOT_SHU_ID] = 0
	mode = MODE_NONE


func _next_bot_seq(bot_id: String) -> int:
	var nxt: int = _to_int(_bot_seq.get(bot_id, 0), 0) + 1
	_bot_seq[bot_id] = nxt
	return nxt


func _make_envelope(pid: String, seq: int, tick_id: int, cmd_type: String, args: Dictionary) -> Dictionary:
	return {
		"v": 1,
		"cmd_seq": seq,
		"client_tick": tick_id,
		"player_id": pid,
		"cmd_type": cmd_type,
		"args": args.duplicate(true)
	}


func start_local_demo(world_seed: int = 18401, p_player_id: String = "player_01", p_display_name: String = "조자룡") -> Dictionary:
	stop()

	player_id = p_player_id if not p_player_id.is_empty() else "player_01"
	display_name = p_display_name if not p_display_name.is_empty() else "조자룡"
	local_peer_id = "peer_" + player_id

	local_server = AuthoritativeServer.new(world_seed, "ST_SIMA_QIAN")
	var _lb: NetworkTransport = local_server.transport.create_loopback()
	mode = MODE_LOCAL_DEMO

	# Register player_01 and 2 autonomous AI rival/ally lords on valid macro_map_3k.json provinces
	var _r_p1: Dictionary = local_server.register_session(local_peer_id, player_id, display_name)
	var _r_wei: Dictionary = local_server.register_session(BOT_WEI_PEER, BOT_WEI_ID, "조조 · 위공")
	var _r_shu: Dictionary = local_server.register_session(BOT_SHU_PEER, BOT_SHU_ID, "유비 · 좌장군")

	# Bootstrap characters & manors via genuine CommandValidator/AuthoritativeServer flow
	var _c1: Dictionary = local_server.submit_raw_command(local_peer_id, _make_envelope(
		player_id, 1, 0, "CMD_CREATE_CHARACTER", {
			"avatar_name": display_name,
			"creation_mode": "INTERVIEW_ONLY",
			"origin_override": "ORIGIN_CHIVALROUS_HERO",
			"province_override": "YU_ZHOU",
			"interview_answers": [0, 1, 2, 0, 1, 2, 0, 1]
		}
	))
	var _cw: Dictionary = local_server.submit_raw_command(BOT_WEI_PEER, _make_envelope(
		BOT_WEI_ID, _next_bot_seq(BOT_WEI_ID), 0, "CMD_CREATE_CHARACTER", {
			"avatar_name": "조조",
			"creation_mode": "INTERVIEW_ONLY",
			"origin_override": "ORIGIN_FRONTIER_OFFICER",
			"province_override": "XU_ZHOU",
			"interview_answers": [1, 0, 1, 2, 1, 0, 2, 1]
		}
	))
	var _cs: Dictionary = local_server.submit_raw_command(BOT_SHU_PEER, _make_envelope(
		BOT_SHU_ID, _next_bot_seq(BOT_SHU_ID), 0, "CMD_CREATE_CHARACTER", {
			"avatar_name": "유비",
			"creation_mode": "INTERVIEW_ONLY",
			"origin_override": "ORIGIN_FALLEN_ROYAL",
			"province_override": "YI_ZHOU",
			"interview_answers": [0, 2, 0, 1, 2, 0, 1, 0]
		}
	))

	# Step tick 1 to execute character creation & spawn starter manors + pawns
	var _step1: Dictionary = local_server.step_micro_tick()

	# Populate authentic Three Kingdoms hero & sworn retainer identity on starter manor
	if local_server.manors.has(player_id):
		var m_init_v: Variant = local_server.manors[player_id]
		if m_init_v is ManorState:
			var m_init: ManorState = m_init_v
			for p_init: PawnEntity in m_init.pawns:
				if p_init.is_avatar:
					p_init.name = display_name
					p_init.courtesy_name = "자룡" if display_name == "조자룡" else p_init.courtesy_name
					p_init.epithet = "한실 신흥군 주군"
					p_init.set_stat("LEA", 74)
					p_init.set_stat("MAR", 86)
					p_init.set_stat("INT", 70)
					p_init.set_stat("POL", 72)
					p_init.set_stat("CHA", 79)
					p_init.traits = ["T_CHIVALROUS", "T_AMBITIOUS"]
					p_init.set_work_priority("PATROL", 1)
					p_init.set_work_priority("TRAINING", 2)
					p_init.set_work_priority("AGRICULTURE", 2)
					p_init.set_work_priority("LOGISTICS", 2)
					p_init.grid_x = 15
					p_init.grid_y = 6
					if local_server.player_accounts.has(player_id):
						var acct_p: Dictionary = local_server.player_accounts[player_id]
						acct_p["persona_profile_json"] = StateHasher.canonical_json({
							"avatar_name": p_init.name,
							"courtesy_name": p_init.courtesy_name,
							"epithet": p_init.epithet,
							"stats": p_init.stats,
							"traits": p_init.traits
						})
				else:
					p_init.name = "진도"
					p_init.epithet = "백이병 도독"
					p_init.traits = ["T_AGRARIAN", "T_UNSELFISH"]
					p_init.set_work_priority("AGRICULTURE", 1)
					p_init.set_work_priority("LOGISTICS", 2)
					p_init.set_work_priority("PATROL", 2)
					p_init.grid_x = 8
					p_init.grid_y = 9

	# Establish authentic Three Kingdoms factions & diplomatic alliance
	var _f_han: Dictionary = local_server.faction_manager.create_faction(
		"fac_han", "한실 신흥군", player_id, "xuchang", local_server.world_graph, 8000, 9000, "DUKE"
	)
	var _f_wei: Dictionary = local_server.faction_manager.create_faction(
		"fac_wei", "위(魏) 조조군", BOT_WEI_ID, "xiapi", local_server.world_graph, 12000, 12000, "KING"
	)
	var _f_shu: Dictionary = local_server.faction_manager.create_faction(
		"fac_shu", "촉(蜀) 유비군", BOT_SHU_ID, "chengdu", local_server.world_graph, 10000, 10000, "GOVERNOR_GENERAL"
	)
	var _t_han_shu: Dictionary = local_server.diplomacy_engine.propose_and_sign_treaty(
		"fac_han", "fac_shu", "ALLIANCE", 30, local_server.clock
	)

	# Give starter manors healthy liquidity so AI bots & player can trade and march right away
	for pid_k: String in [player_id, BOT_WEI_ID, BOT_SHU_ID]:
		if local_server.manors.has(pid_k):
			var mv: Variant = local_server.manors[pid_k]
			if mv is ManorState:
				var m: ManorState = mv
				var _ag: int = m.add_resource("GRAIN", 1500)
				var _ac: int = m.add_resource("COIN", 2000)
				var _aw: int = m.add_resource("WOOD", 500)
				var _ai: int = m.add_resource("IRON", 300)

	# Ensure subscriptions include global macro, manor, xuchang node market, and fac_han
	var _s_glob: bool = local_server.interest_manager.subscribe(local_peer_id, DtoSchemas.CHAN_GLOBAL_MACRO)
	var _s_manor: bool = local_server.interest_manager.subscribe(local_peer_id, DtoSchemas.CHAN_MANOR + ":manor_" + player_id)
	var _s_node: bool = local_server.interest_manager.subscribe(local_peer_id, DtoSchemas.CHAN_NODE + ":xuchang")
	var _s_fac: bool = local_server.interest_manager.subscribe(local_peer_id, DtoSchemas.CHAN_FACTION + ":fac_han")
	var _on_p1: Dictionary = local_server.set_player_online(player_id, true)

	# Seed initial chronicle inbox decision so Tab 3 Inbox is immediately interactive
	var _dec_init: Dictionary = local_server.chronicle_inbox.enqueue_decision(
		player_id,
		"IMPERIAL_LEVY",
		["PAY_LEVY", "REFUSE_LEVY"],
		"PAY_LEVY",
		local_server.clock.current_tick_id + SimClock.TICKS_PER_DAY,
		{"note": "허창 군량 조달 칙서"}
	)

	# Advance to morning daytime (진시, tick 8) so bots execute initial orders/caravans
	# and manor pawns are visibly engaged in active daytime work
	var drained: Array[Dictionary] = []
	for _i: int in range(7):
		var step_msgs: Array[Dictionary] = step_local_tick()
		for sm: Dictionary in step_msgs:
			drained.append(sm)

	# Ensure at least one initial full MSG_TICK_DELTA is available for frame-0 client hydration
	var init_delta: Dictionary = build_initial_delta_for_player()
	if not init_delta.is_empty():
		drained.append(init_delta)

	return {
		"ok": true,
		"tick_id": local_server.clock.current_tick_id,
		"state_crc32": local_server.state_crc32,
		"initial_messages": drained
	}


func build_initial_delta_for_player() -> Dictionary:
	if not is_local_mode():
		return {}
	local_server.interest_manager.reset_peer_cache(local_peer_id)
	var srv_state: Dictionary = {
		"clock": local_server.clock,
		"state_crc32": local_server.state_crc32,
		"world_graph": local_server.world_graph,
		"army_manager": local_server.army_manager,
		"regional_market": local_server.regional_market,
		"faction_manager": local_server.faction_manager,
		"diplomacy": local_server.diplomacy_engine,
		"siege_resolver": local_server.siege_resolver,
		"manors": local_server.manors
	}
	return local_server.interest_manager.build_tick_delta_for_peer(local_peer_id, srv_state, [])


func _submit_bot_envelope(bot_peer: String, bot_id: String, cmd_type: String, args: Dictionary) -> void:
	if not is_local_mode():
		return
	var seq: int = _next_bot_seq(bot_id)
	var env: Dictionary = _make_envelope(bot_id, seq, local_server.clock.current_tick_id, cmd_type, args)
	var _sent: bool = local_server.transport.client_send_envelope(bot_peer, env)


func _count_bot_active_expeditions(bot_id: String) -> int:
	if not is_local_mode():
		return 0
	var count: int = 0
	for eid: String in local_server.army_manager.get_entity_ids():
		var ent: Dictionary = local_server.army_manager.get_entity(eid)
		if str(ent.get("owner_player_id", "")) == bot_id:
			count += 1
	return count


func _run_bot_ai_macro_actions() -> void:
	if not is_local_mode():
		return
	var cur_tick: int = local_server.clock.current_tick_id
	var macro_idx: int = local_server.clock.get_macro_tick_id()

	# Deterministic market orders at xuchang so BID/ASK match and prices move genuinely
	var comm_pool: Array[String] = ["GRAIN", "IRON", "WOOD", "WEAPONS"]
	var comm_idx: int = DeterministicRNG.roll_range(local_server.world_seed, cur_tick, 2001, 11, 0, comm_pool.size() - 1)
	var comm: String = comm_pool[comm_idx]
	var base_p: int = local_server.regional_market.get_node_price_bp("xuchang", comm)
	var spread: int = DeterministicRNG.roll_range(local_server.world_seed, cur_tick, 2002, 22, 0, 100)
	var qty: int = DeterministicRNG.roll_range(local_server.world_seed, cur_tick, 2003, 33, 10, 25)

	var wei_manor: ManorState = local_server.manors.get(BOT_WEI_ID, null)
	if wei_manor != null and wei_manor.get_resource(comm) >= qty:
		_submit_bot_envelope(BOT_WEI_PEER, BOT_WEI_ID, "CMD_PLACE_MARKET_ORDER", {
			"node_id": "xuchang",
			"commodity": comm,
			"side": "ASK",
			"price_bp": clampi(base_p - 25 + spread, 200, 50000),
			"quantity": qty
		})

	var shu_manor: ManorState = local_server.manors.get(BOT_SHU_ID, null)
	if shu_manor != null and shu_manor.get_resource("COIN") >= 150:
		_submit_bot_envelope(BOT_SHU_PEER, BOT_SHU_ID, "CMD_PLACE_MARKET_ORDER", {
			"node_id": "xuchang",
			"commodity": comm,
			"side": "BID",
			"price_bp": clampi(base_p + 75 + spread, 200, 50000),
			"quantity": qty
		})

	# Deterministic expeditions (CARAVAN / ARMY) along valid WorldGraph paths
	if wei_manor != null and _count_bot_active_expeditions(BOT_WEI_ID) < 2 and wei_manor.household_troops >= 100 and wei_manor.get_resource("GRAIN") >= 150:
		var wei_targets: Array[String] = ["xuchang", "chenliu", "jianye", "luoyang"]
		var wt_idx: int = DeterministicRNG.roll_range(local_server.world_seed, cur_tick, 3001, 41, 0, wei_targets.size() - 1)
		var w_target: String = wei_targets[wt_idx]
		var w_path: Array[String] = local_server.world_graph.find_path(wei_manor.host_node_id, w_target)
		if not w_path.is_empty():
			var w_ut: String = "CARAVAN" if (macro_idx % 2 == 0) else "ARMY"
			_submit_bot_envelope(BOT_WEI_PEER, BOT_WEI_ID, "CMD_DISPATCH_EXPEDITION", {
				"target_node_id": w_target,
				"path_edge_ids": w_path,
				"troop_count": 60,
				"carried_grain": 100,
				"unit_type": w_ut,
				"officer_ids": [],
				"cargo": {"IRON": 10} if w_ut == "CARAVAN" else {}
			})

	if shu_manor != null and _count_bot_active_expeditions(BOT_SHU_ID) < 2 and shu_manor.household_troops >= 100 and shu_manor.get_resource("GRAIN") >= 150:
		var shu_targets: Array[String] = ["xiangyang", "changan", "nanyang", "xuchang"]
		var st_idx: int = DeterministicRNG.roll_range(local_server.world_seed, cur_tick, 3002, 42, 0, shu_targets.size() - 1)
		var s_target: String = shu_targets[st_idx]
		var s_path: Array[String] = local_server.world_graph.find_path(shu_manor.host_node_id, s_target)
		if not s_path.is_empty():
			var s_ut: String = "CARAVAN" if (macro_idx % 2 == 1) else "ARMY"
			_submit_bot_envelope(BOT_SHU_PEER, BOT_SHU_ID, "CMD_DISPATCH_EXPEDITION", {
				"target_node_id": s_target,
				"path_edge_ids": s_path,
				"troop_count": 60,
				"carried_grain": 100,
				"unit_type": s_ut,
				"officer_ids": [],
				"cargo": {"GRAIN": 40} if s_ut == "CARAVAN" else {}
			})

	# Occasional manor upgrade, banquet, or coalition rally
	var act_roll: int = DeterministicRNG.roll_range(local_server.world_seed, cur_tick, 4001, 51, 0, 9)
	if act_roll <= 2 and wei_manor != null:
		var b_pool: Array[String] = ["MILITARY_FARM", "GRANARY_VAULT", "BARRACKS_DRILL", "WATCHTOWER_WALL"]
		var b_id: String = b_pool[macro_idx % b_pool.size()]
		var lvl: int = wei_manor.get_building_level(b_id)
		if lvl < 5 and wei_manor.get_resource("WOOD") >= 120 * lvl and wei_manor.get_resource("COIN") >= 180 * lvl:
			_submit_bot_envelope(BOT_WEI_PEER, BOT_WEI_ID, "CMD_BUILD_OR_UPGRADE", {"building_id": b_id})
	elif act_roll == 3 and shu_manor != null and shu_manor.get_resource("HERBS_WINE") >= 10 and shu_manor.get_resource("GRAIN") >= 20:
		_submit_bot_envelope(BOT_SHU_PEER, BOT_SHU_ID, "CMD_HOST_BANQUET", {
			"host_pawn_id": BOT_SHU_ID + "_avatar",
			"wine_cost": 10,
			"grain_cost": 20
		})
	elif macro_idx == 2:
		_submit_bot_envelope(BOT_SHU_PEER, BOT_SHU_ID, "CMD_CREATE_COALITION_RALLY", {
			"target_node_id": "hulao_pass",
			"troop_count": 200,
			"morale_bp": 8500
		})

	# Drain bot-only outbound queues so loopback buffers don't grow unbounded
	var _d1: Array[Dictionary] = local_server.transport.client_drain_incoming(BOT_WEI_PEER)
	var _d2: Array[Dictionary] = local_server.transport.client_drain_incoming(BOT_SHU_PEER)


func step_local_tick() -> Array[Dictionary]:
	if not is_local_mode():
		return []
	var step_res: Dictionary = local_server.step_micro_tick()
	if _to_bool(step_res.get("macro_tick", false), false):
		_run_bot_ai_macro_actions()
	return local_server.transport.client_drain_incoming(local_peer_id)


func build_local_ui_hydration() -> Dictionary:
	if not is_local_mode():
		return {}
	var manor_patch: Dictionary = {}
	if local_server.manors.has(player_id):
		var mv: Variant = local_server.manors[player_id]
		if mv is ManorState:
			var m: ManorState = mv
			var pawns_cfg: Dictionary = {}
			for p: PawnEntity in m.pawns:
				pawns_cfg[p.pawn_id] = {
					"name": p.name,
					"courtesy_name": p.courtesy_name,
					"epithet": p.epithet,
					"is_avatar": p.is_avatar,
					"origin_archetype": p.origin_archetype,
					"stats": p.stats.duplicate(true),
					"traits": p.traits.duplicate(),
					"x": p.grid_x,
					"y": p.grid_y,
					"job": p.current_job,
					"progress_pm": p.job_progress_pm,
					"state": p.state,
					"health_state": p.health_state,
					"food_bp": p.get_need("FOOD"),
					"rest_bp": p.get_need("REST"),
					"morale_bp": p.get_need("MORALE"),
					"loyalty_bp": p.get_need("LOYALTY"),
					"mood": p.mood,
					"mental_state": p.mental_state,
					"work_priorities": p.work_priorities.duplicate(true),
					"daily_schedule": p.daily_schedule.duplicate()
				}
			var stock: Dictionary = {}
			for rk: String in DtoSchemas.RESOURCE_KEYS:
				stock[rk] = m.get_resource(rk)
			manor_patch = {
				"manor_id": m.manor_id,
				"host_node_id": m.host_node_id,
				"meta": {
					"lod": m.current_lod,
					"wall_hp": m.wall_hp,
					"household_troops": m.household_troops,
					"truce_shield_until_tick": m.truce_shield_until_tick
				},
				"stockpile": stock,
				"buildings": m.buildings.duplicate(true),
				"standing_doctrine": m.standing_doctrine.duplicate(true),
				"tile_zone_map": m.tile_zone_map.duplicate(),
				"pawns": pawns_cfg
			}

	var prof: Dictionary = local_server.faction_manager.get_player_profile(player_id)
	var fid: String = str(prof.get("faction_id", ""))
	var fac: Dictionary = local_server.faction_manager.get_faction(fid) if not fid.is_empty() else {}
	var pending_inbox: Array[Dictionary] = local_server.chronicle_inbox.get_pending_decisions_for_player(player_id)

	var st_id: String = local_server.storyteller.persona_id if local_server.storyteller != null else "ST_SIMA_QIAN"
	var court_patch: Dictionary = {
		"player_profile": prof.duplicate(true),
		"faction": fac.duplicate(true),
		"inbox_decisions": pending_inbox,
		"storyteller": st_id
	}

	return {
		"tick_id": local_server.clock.current_tick_id,
		"season": local_server.clock.get_season(),
		"state_crc32": local_server.state_crc32,
		"manor": manor_patch,
		"court": court_patch
	}


func connect_remote_ws(url: String, p_player_id: String = "player_01", p_display_name: String = "조자룡") -> Error:
	stop()
	var clean_url: String = url.strip_edges()
	if clean_url.is_empty():
		return ERR_INVALID_PARAMETER
	player_id = p_player_id if not p_player_id.is_empty() else "player_01"
	display_name = p_display_name if not p_display_name.is_empty() else "조자룡"
	ws_url = clean_url
	ws_transport = NetworkTransport.new(NetworkTransport.MODE_WEBSOCKET)
	var err: Error = ws_transport.connect_websocket(clean_url)
	if err != OK:
		ws_transport.close()
		ws_transport = null
		ws_url = ""
		return err
	mode = MODE_REMOTE_WS
	_ws_was_open = false
	_ws_handshake_sent = false
	return OK


func send_command_envelope(envelope: Dictionary) -> bool:
	if mode == MODE_LOCAL_DEMO and is_local_mode():
		var env_seq: int = _to_int(envelope.get("cmd_seq", 0), 0)
		var prev_srv_seq: int = _to_int(local_server.command_validator.last_accepted_seq.get(player_id, 0), 0)
		var fixed_env: Dictionary = envelope.duplicate(true)
		if env_seq <= prev_srv_seq:
			fixed_env["cmd_seq"] = prev_srv_seq + 1
		var _sent: bool = local_server.transport.client_send_envelope(local_peer_id, fixed_env)
		return _sent

	if mode == MODE_REMOTE_WS and is_remote_connected():
		var env_seq: int = _to_int(envelope.get("cmd_seq", 0), 0)
		var next_seq: int = maxi(_remote_cmd_seq + 1, env_seq)
		_remote_cmd_seq = next_seq
		var fixed_ws_env: Dictionary = envelope.duplicate(true)
		fixed_ws_env["cmd_seq"] = next_seq
		return ws_transport.client_send_envelope(player_id, fixed_ws_env)
	return false


func poll_incoming() -> Array[Dictionary]:
	if mode == MODE_LOCAL_DEMO and is_local_mode():
		return local_server.transport.client_drain_incoming(local_peer_id)

	if mode == MODE_REMOTE_WS and ws_transport != null:
		ws_transport.poll()
		var is_open_now: bool = ws_transport.is_ws_client_open()
		if is_open_now and not _ws_was_open:
			_ws_was_open = true
			if not _ws_handshake_sent:
				_ws_handshake_sent = true
				var hello_msg: Dictionary = {
					"v": 1,
					"msg_type": "MSG_WS_HELLO",
					"player_id": player_id,
					"display_name": display_name
				}
				var _ok_hello: bool = ws_transport.client_send_envelope(player_id, hello_msg)
		elif not is_open_now:
			_ws_was_open = false
		var incoming_ws: Array[Dictionary] = ws_transport.client_drain_incoming(player_id)
		for msg: Dictionary in incoming_ws:
			if str(msg.get("msg_type", "")) == "MSG_WS_WELCOME":
				var server_last_seq: int = _to_int(msg.get("last_accepted_seq", 0), 0)
				_remote_cmd_seq = maxi(_remote_cmd_seq, server_last_seq)
				_remote_client_tick = _to_int(msg.get("tick_id", _remote_client_tick), _remote_client_tick)
		return incoming_ws

	return []
