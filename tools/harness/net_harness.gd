extends SceneTree

const DEFAULT_SEED: int = 18401
const DEFAULT_LOOPBACK_TICKS: int = 48
const DEFAULT_SERVER_TICKS: int = 24
const WS_CONNECT_TIMEOUT_MS: int = 15000
const WS_SERVER_WAIT_TIMEOUT_MS: int = 15000
const WS_CLIENT_WAIT_TIMEOUT_MS: int = 15000
const ALLOWED_BOTS: Array[String] = ["lord_A", "ally_B", "raider_C"]

var _wal_logger: WALLogger = null
var _wal_write_count: int = 0
var _wal_errors: Array[String] = []
var _checkpoint_snap_path: String = ""
var _checkpoint_db_path: String = ""
var _checkpoint_count: int = 0
var _checkpoint_errors: Array[String] = []


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


static func _as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		var d: Dictionary = v
		return d
	return {}


static func _as_array(v: Variant) -> Array:
	if v is Array:
		var a: Array = v
		return a
	return []


static func _resolve_path(path: String) -> String:
	if path.is_empty():
		return ""
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.begins_with("/"):
		return path
	return ProjectSettings.globalize_path("res://").path_join(path)


static func _remove_file_if_exists(path: String) -> void:
	var resolved: String = _resolve_path(path)
	if not resolved.is_empty() and FileAccess.file_exists(resolved):
		var _err: Error = DirAccess.remove_absolute(resolved)


static func _write_json_report(out_path: String, report: Dictionary) -> void:
	var resolved: String = _resolve_path(out_path)
	if resolved.is_empty():
		return
	var parent_dir: String = resolved.get_base_dir()
	if not parent_dir.is_empty():
		var _mk_err: Error = DirAccess.make_dir_recursive_absolute(parent_dir)
	var f: FileAccess = FileAccess.open(resolved, FileAccess.WRITE)
	if f == null:
		printerr("[net_harness] ERROR: Unable to write report to " + resolved)
		return
	var _ok_w: bool = f.store_string(JSON.stringify(report, "  ") + "\n")
	f.flush()
	f.close()


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var mode: String = "loopback"
	var world_seed: int = DEFAULT_SEED
	var ticks: int = -1
	var db_path: String = "saves/world_state.db"
	var wal_path: String = "saves/wal_commands.jsonl"
	var snap_path: String = "saves/world_snapshot.json"
	var port: int = 0
	var bot_id: String = "lord_A"
	var expected_clients: int = 3
	var out_path: String = "reports/net_smoke_report.json"

	for arg: String in args:
		if arg.begins_with("--mode="):
			mode = arg.substr(7)
		elif arg.begins_with("--seed="):
			world_seed = arg.substr(7).to_int()
		elif arg.begins_with("--ticks="):
			ticks = maxi(1, arg.substr(8).to_int())
		elif arg.begins_with("--db="):
			db_path = arg.substr(5)
		elif arg.begins_with("--wal="):
			wal_path = arg.substr(6)
		elif arg.begins_with("--snapshot="):
			snap_path = arg.substr(11)
		elif arg.begins_with("--port="):
			port = arg.substr(7).to_int()
		elif arg.begins_with("--bot="):
			bot_id = arg.substr(6)
		elif arg.begins_with("--expected-clients="):
			expected_clients = maxi(1, arg.substr(19).to_int())
		elif arg.begins_with("--out="):
			out_path = arg.substr(6)

	var exit_code: int = 1
	if mode == "loopback":
		var target_ticks: int = ticks if ticks > 0 else DEFAULT_LOOPBACK_TICKS
		exit_code = _run_loopback_mode(world_seed, target_ticks, db_path, wal_path, snap_path, out_path)
	elif mode == "server":
		var target_ticks_srv: int = ticks if ticks > 0 else DEFAULT_SERVER_TICKS
		exit_code = _run_server_mode(world_seed, target_ticks_srv, port, expected_clients, db_path, wal_path, snap_path, out_path)
	elif mode == "client":
		exit_code = _run_client_mode(port, bot_id, out_path)
	else:
		printerr("[net_harness] ERROR: Unknown --mode=" + mode)
		exit_code = 1

	quit(exit_code)


func _on_wal_record(rec: Dictionary) -> void:
	if _wal_logger == null or not _wal_logger.is_open():
		return
	var payload_d: Dictionary = _as_dict(rec.get("payload", {}))
	var res: Dictionary = _wal_logger.append_record(
		_to_int(rec.get("tick_id", 0), 0),
		_to_int(rec.get("cmd_seq", 0), 0),
		str(rec.get("player_id", "")),
		str(rec.get("cmd_type", "")),
		payload_d
	)
	if _to_bool(res.get("ok", false), false):
		_wal_write_count += 1
	else:
		_wal_errors.append("WAL append failed: " + str(res.get("reason", "unknown")))


func _on_daily_checkpoint(srv: AuthoritativeServer) -> void:
	if not _checkpoint_snap_path.is_empty():
		var snap_res: Dictionary = SnapshotSerializer.save_atomic_snapshot(
			_checkpoint_snap_path,
			srv.to_deterministic_hash_dict()
		)
		if not _to_bool(snap_res.get("ok", false), false):
			_checkpoint_errors.append("Snapshot save failed: " + str(snap_res.get("reason", "unknown")))
	if not _checkpoint_db_path.is_empty():
		var sql_res: Dictionary = SQLiteBridge.sync_world_checkpoint(
			_checkpoint_db_path,
			_export_server_relational_snapshot(srv)
		)
		if not _to_bool(sql_res.get("ok", false), false):
			_checkpoint_errors.append("SQLite checkpoint failed: " + str(sql_res.get("reason", "unknown")))
	_checkpoint_count += 1


static func _export_server_relational_snapshot(srv: AuthoritativeServer) -> Dictionary:
	var rel: Dictionary = srv.export_relational_snapshot()
	var wm_arr: Array = _as_array(rel.get("world_meta", []))
	if not wm_arr.is_empty():
		var wm0: Dictionary = _as_dict(wm_arr[0])
		if not wm0.is_empty():
			rel["world_meta"] = wm0
			rel["world_id"] = wm0.get("world_id", srv.world_id)
			rel["world_seed"] = wm0.get("world_seed", srv.world_seed)
			rel["current_tick_id"] = wm0.get("current_tick_id", srv.clock.current_tick_id)
			rel["current_day_id"] = wm0.get("current_day_id", srv.clock.get_day_id())
			rel["season"] = wm0.get("season", srv.clock.get_season())
			rel["storyteller_id"] = wm0.get("storyteller_id", "SIMA_QIAN")
			rel["state_crc32"] = wm0.get("state_crc32", srv.state_crc32)
	return rel


static func _make_envelope(player_id: String, cmd_seq: int, client_tick: int, cmd_type: String, cmd_args: Dictionary) -> Dictionary:
	return {
		"v": 1,
		"cmd_seq": cmd_seq,
		"client_tick": client_tick,
		"player_id": player_id,
		"cmd_type": cmd_type,
		"args": cmd_args
	}


static func _encode_token_from_challenge(challenge_msg: Dictionary, slots: Array[int]) -> String:
	if slots.size() != 16:
		return ""
	var cid: String = str(challenge_msg.get("challenge_id", ""))
	var cb_arr: Array = _as_array(challenge_msg.get("codebook", []))
	if cid.length() != 6 or cb_arr.size() != 31:
		return ""
	var chars: Array[String] = []
	for item: Variant in cb_arr:
		chars.append(str(item))
	var s1: int = _to_int(challenge_msg.get("init_s1", 0), 0)
	var s2: int = _to_int(challenge_msg.get("init_s2", 0), 0)
	for val: int in slots:
		if val < 0 or val >= 31:
			return ""
		s1 = (s1 + val) % 31
		s2 = (s2 + s1) % 31
	var seg1: String = ""
	for i: int in range(0, 6):
		seg1 += chars[slots[i]]
	var seg2: String = ""
	for i: int in range(6, 12):
		seg2 += chars[slots[i]]
	var seg3: String = ""
	for i: int in range(12, 16):
		seg3 += chars[slots[i]]
	var chk: String = chars[s1] + chars[s2]
	return "TK3K2-%s-%s-%s-%s-%s" % [cid, seg1, seg2, seg3, chk]


func _init_persistence(srv: AuthoritativeServer, db_path: String, wal_path: String, snap_path: String, errors: Array[String]) -> void:
	_remove_file_if_exists(wal_path)
	_remove_file_if_exists(snap_path)
	_remove_file_if_exists(snap_path + ".tmp")
	_remove_file_if_exists(db_path)
	_remove_file_if_exists(db_path + "-wal")
	_remove_file_if_exists(db_path + "-shm")

	_wal_logger = WALLogger.new()
	_wal_write_count = 0
	_wal_errors.clear()
	var wal_res: Dictionary = _wal_logger.open_wal(wal_path)
	if not _to_bool(wal_res.get("ok", false), false):
		errors.append("Failed to open WAL: " + str(wal_res.get("reason", "")))

	var db_res: Dictionary = SQLiteBridge.init_database(db_path)
	if not _to_bool(db_res.get("ok", false), false):
		errors.append("Failed to init SQLite DB: " + str(db_res.get("reason", "")))

	_checkpoint_snap_path = snap_path
	_checkpoint_db_path = db_path
	_checkpoint_count = 0
	_checkpoint_errors.clear()
	srv.attach_persistence_handlers(Callable(self, "_on_wal_record"), Callable(self, "_on_daily_checkpoint"))


func _assert_cond(cond: bool, msg: String, errors: Array[String], checks: Array[String]) -> void:
	if cond:
		checks.append(msg)
	else:
		errors.append(msg)


func _run_loopback_mode(
	world_seed: int,
	target_ticks: int,
	db_path: String,
	wal_path: String,
	snap_path: String,
	out_path: String
) -> int:
	var errors: Array[String] = []
	var checks: Array[String] = []
	var effective_ticks: int = maxi(48, target_ticks)

	var srv: AuthoritativeServer = AuthoritativeServer.new(world_seed, "ST_SIMA_QIAN")
	var _lb: NetworkTransport = srv.transport.create_loopback()
	_init_persistence(srv, db_path, wal_path, snap_path, errors)

	var r_a: Dictionary = srv.register_session("peer_lord_A", "lord_A", "Lord_A")
	var r_b: Dictionary = srv.register_session("peer_ally_B", "ally_B", "Ally_B")
	var r_c: Dictionary = srv.register_session("peer_raider_C", "raider_C", "Raider_C")
	_assert_cond(_to_bool(r_a.get("ok", false), false), "lord_A loopback session registered", errors, checks)
	_assert_cond(_to_bool(r_b.get("ok", false), false), "ally_B loopback session registered", errors, checks)
	_assert_cond(_to_bool(r_c.get("ok", false), false), "raider_C loopback session registered", errors, checks)

	# -------------------------------------------------------------------------
	# Scenario 1: 2-Step Sealed Token & Character Creation (+ Plaintext Rejection)
	# -------------------------------------------------------------------------
	var _sa1: bool = srv.transport.client_send_envelope("peer_lord_A", _make_envelope(
		"lord_A", 1, srv.clock.current_tick_id, "CMD_REQUEST_PERSONA_CHALLENGE",
		{"account_id": "acc_lord_A", "nonce_salt": 101}
	))
	var _sb1: bool = srv.transport.client_send_envelope("peer_ally_B", _make_envelope(
		"ally_B", 1, srv.clock.current_tick_id, "CMD_CREATE_CHARACTER",
		{
			"avatar_name": "Ally_B",
			"creation_mode": "INTERVIEW_ONLY",
			"interview_answers": [1, 1, 0, 2, 1, 2, 0, 0],
			"province_override": "YU_ZHOU"
		}
	))
	var _sc1: bool = srv.transport.client_send_envelope("peer_raider_C", _make_envelope(
		"raider_C", 1, srv.clock.current_tick_id, "CMD_CREATE_CHARACTER",
		{
			"avatar_name": "Raider_C_Hacked",
			"creation_mode": "FUSION_INTERVIEW",
			"sealed_token_input": "{\"schema\":\"AI_PERSONA_EXPORT_V1\",\"persona_weights\":{\"LEA\":99,\"MAR\":99}}",
			"interview_answers": [0, 0, 0, 0, 0, 0, 0, 0],
			"province_override": "YONG_LIANG"
		}
	))

	var _t1: Dictionary = srv.step_micro_tick()
	var msgs_a1: Array[Dictionary] = srv.transport.client_drain_incoming("peer_lord_A")
	var msgs_b1: Array[Dictionary] = srv.transport.client_drain_incoming("peer_ally_B")
	var msgs_c1: Array[Dictionary] = srv.transport.client_drain_incoming("peer_raider_C")

	var challenge_msg: Dictionary = {}
	for m: Dictionary in msgs_a1:
		if str(m.get("msg_type", "")) == DtoSchemas.MSG_PERSONA_CHALLENGE:
			challenge_msg = m
	var v_chal: Dictionary = DtoSchemas.validate_persona_challenge(challenge_msg)
	_assert_cond(_to_bool(v_chal.get("ok", false), false), "lord_A received valid MSG_PERSONA_CHALLENGE", errors, checks)

	var ally_created_receipt: bool = false
	for m: Dictionary in msgs_b1:
		if str(m.get("msg_type", "")) == DtoSchemas.MSG_CMD_RECEIPT and str(m.get("status", "")) == "ACCEPTED":
			ally_created_receipt = true
	_assert_cond(ally_created_receipt, "ally_B INTERVIEW_ONLY character creation ACCEPTED", errors, checks)

	var raider_plaintext_rejected: bool = false
	for m: Dictionary in msgs_c1:
		if str(m.get("msg_type", "")) == DtoSchemas.MSG_CMD_RECEIPT:
			if str(m.get("status", "")) == "REJECTED" and str(m.get("error_code", "")) == DtoSchemas.ERR_PLAINTEXT_JSON_FORBIDDEN:
				raider_plaintext_rejected = true
	_assert_cond(raider_plaintext_rejected, "raider_C plaintext JSON rejected with ERR_PLAINTEXT_JSON_FORBIDDEN", errors, checks)

	var slots_a: Array[int] = [3, 18, 12, 22, 16, 14, 0, 2, 10, 0, 5, 2, 3, 0, 1, 0]
	var chal_id: String = str(challenge_msg.get("challenge_id", ""))
	var tok_from_cipher: String = _encode_token_from_challenge(challenge_msg, slots_a)
	var tok_from_codec: String = SealedTokenCodec.encode_tk3k2(chal_id, "lord_A", slots_a)
	_assert_cond(not tok_from_cipher.is_empty() and tok_from_cipher == tok_from_codec, "TK3K2 token encoded from server challenge cipher matches SealedTokenCodec", errors, checks)

	var _sa2: bool = srv.transport.client_send_envelope("peer_lord_A", _make_envelope(
		"lord_A", 2, srv.clock.current_tick_id, "CMD_CREATE_CHARACTER",
		{
			"avatar_name": "Lord_A",
			"creation_mode": "FUSION_INTERVIEW",
			"sealed_token_input": "<<<TK3K_PERSONA_V2>>>\n%s\n<<<END_TK3K_PERSONA_V2>>>" % tok_from_cipher,
			"interview_answers": [0, 0, 0, 1, 1, 0, 0, 0],
			"province_override": "YU_ZHOU"
		}
	))
	var _sc2: bool = srv.transport.client_send_envelope("peer_raider_C", _make_envelope(
		"raider_C", 2, srv.clock.current_tick_id, "CMD_CREATE_CHARACTER",
		{
			"avatar_name": "Raider_C",
			"creation_mode": "INTERVIEW_ONLY",
			"interview_answers": [2, 3, 1, 0, 2, 1, 2, 3],
			"province_override": "YONG_LIANG"
		}
	))
	var _t2: Dictionary = srv.step_micro_tick()
	var _da2: Array[Dictionary] = srv.transport.client_drain_incoming("peer_lord_A")
	var _dc2: Array[Dictionary] = srv.transport.client_drain_incoming("peer_raider_C")

	_assert_cond(srv.manors.has("lord_A") and srv.manors.has("ally_B") and srv.manors.has("raider_C"), "All 3 player manors created", errors, checks)
	var acct_a: Dictionary = _as_dict(srv.player_accounts.get("lord_A", {}))
	_assert_cond(str(acct_a.get("creation_mode", "")) == "FUSION_INTERVIEW" and str(acct_a.get("import_audit_status", "")) == "VERIFIED_CLEAN", "lord_A created via FUSION_INTERVIEW (VERIFIED_CLEAN)", errors, checks)

	# Establish factions for lord_A (Wei Sovereign) and ally_B (Allied Lord); keep raider_C as FREE_OFFICER
	var fac_wei_res: Dictionary = srv.faction_manager.create_faction("fac_wei", "Wei", "lord_A", "xuchang", srv.world_graph, 15000, 15000, "PREFECT")
	var fac_ally_res: Dictionary = srv.faction_manager.create_faction("fac_ally", "Allied_Commandery", "ally_B", "runan", srv.world_graph, 12000, 12000, "PREFECT")
	_assert_cond(_to_bool(fac_wei_res.get("ok", false), false) and _to_bool(fac_ally_res.get("ok", false), false), "Wei & Allied factions initialized", errors, checks)
	var _sub_fa: bool = srv.interest_manager.subscribe("peer_lord_A", DtoSchemas.CHAN_FACTION + ":fac_wei")
	var _sub_fb: bool = srv.interest_manager.subscribe("peer_ally_B", DtoSchemas.CHAN_FACTION + ":fac_ally")

	# -------------------------------------------------------------------------
	# Scenario 2: Cooperative Economic Interaction (xuchang Regional Market)
	# -------------------------------------------------------------------------
	var xuchang_before: Dictionary = srv.world_graph.get_node("xuchang")
	var price_before_bp: int = _to_int(xuchang_before.get("grain_price_bp", 1000), 1000)

	var _sa3: bool = srv.transport.client_send_envelope("peer_lord_A", _make_envelope(
		"lord_A", 3, srv.clock.current_tick_id, "CMD_PLACE_MARKET_ORDER",
		{"node_id": "xuchang", "commodity": "GRAIN", "side": "ASK", "price_bp": 1150, "quantity": 50}
	))
	var _sb2: bool = srv.transport.client_send_envelope("peer_ally_B", _make_envelope(
		"ally_B", 2, srv.clock.current_tick_id, "CMD_PLACE_MARKET_ORDER",
		{"node_id": "xuchang", "commodity": "GRAIN", "side": "BID", "price_bp": 1150, "quantity": 50}
	))

	# -------------------------------------------------------------------------
	# Scenario 4 (part): Adversarial Anti-Cheat Commands from raider_C
	# -------------------------------------------------------------------------
	var _sc3: bool = srv.transport.client_send_envelope("peer_raider_C", _make_envelope(
		"raider_C", 3, srv.clock.current_tick_id, "CMD_SET_WORK_PRIORITY",
		{"manor_id": "manor_lord_A", "pawn_id": "lord_A_avatar", "domain": "PATROL", "priority": 1}
	))
	var _sc4: bool = srv.transport.client_send_envelope("peer_raider_C", _make_envelope(
		"raider_C", 4, srv.clock.current_tick_id, "CMD_PROPOSE_OR_SIGN_TREATY",
		{"target_faction_id": "fac_wei", "treaty_type": "ALLIANCE", "duration_days": 5}
	))

	# -------------------------------------------------------------------------
	# Scenario 3: Military Coalition Interaction (ALLIANCE -> Rally -> 3-Phase Siege)
	# -------------------------------------------------------------------------
	var _sa4: bool = srv.transport.client_send_envelope("peer_lord_A", _make_envelope(
		"lord_A", 4, srv.clock.current_tick_id, "CMD_PROPOSE_OR_SIGN_TREATY",
		{"target_faction_id": "fac_ally", "treaty_type": "ALLIANCE", "duration_days": 10}
	))

	while srv.clock.current_tick_id < 6:
		var _sm: Dictionary = srv.step_micro_tick()

	var msgs_c3: Array[Dictionary] = srv.transport.client_drain_incoming("peer_raider_C")
	var got_unauth: bool = false
	var got_role_perm: bool = false
	for m: Dictionary in msgs_c3:
		if str(m.get("msg_type", "")) == DtoSchemas.MSG_CMD_RECEIPT and str(m.get("status", "")) == "REJECTED":
			var ec: String = str(m.get("error_code", ""))
			if ec == DtoSchemas.ERR_UNAUTHORIZED:
				got_unauth = true
			elif ec == DtoSchemas.ERR_ROLE_PERMISSION:
				got_role_perm = true
	_assert_cond(got_unauth, "raider_C cross-player command rejected with ERR_UNAUTHORIZED", errors, checks)
	_assert_cond(got_role_perm, "raider_C non-LORD treaty command rejected with ERR_ROLE_PERMISSION", errors, checks)

	var book_matched: bool = false
	for tr: Dictionary in srv.regional_market.trade_history:
		if str(tr.get("node_id", "")) == "xuchang" and str(tr.get("type", "")) == "BOOK_MATCH" and _to_int(tr.get("quantity", 0), 0) == 50:
			book_matched = true
	var xuchang_after: Dictionary = srv.world_graph.get_node("xuchang")
	var price_after_bp: int = _to_int(xuchang_after.get("grain_price_bp", 1000), 1000)
	_assert_cond(book_matched and price_after_bp != price_before_bp, "xuchang grain book matched & price updated (%d -> %d)" % [price_before_bp, price_after_bp], errors, checks)

	_assert_cond(srv.diplomacy_engine.are_allied("fac_wei", "fac_ally", srv.clock.current_tick_id), "ALLIANCE treaty active between fac_wei and fac_ally", errors, checks)

	var _sa5: bool = srv.transport.client_send_envelope("peer_lord_A", _make_envelope(
		"lord_A", 5, srv.clock.current_tick_id, "CMD_CREATE_COALITION_RALLY",
		{
			"target_node_id": "chenliu",
			"army": {
				"troop_count": 1200,
				"morale_bp": 9000,
				"gear_pm": 1100,
				"troop_composition": {"SIEGE_ENGINE": 10},
				"officers": [{"pawn_id": "lord_A_avatar", "MAR": 82, "LEA": 80}]
			}
		}
	))
	var _t7: Dictionary = srv.step_micro_tick()

	var rally_ids: Array[String] = srv.siege_resolver.get_rally_ids()
	_assert_cond(not rally_ids.is_empty(), "Coalition rally created", errors, checks)
	var rid: String = rally_ids[0] if not rally_ids.is_empty() else "rally_000001"

	var _sb3: bool = srv.transport.client_send_envelope("peer_ally_B", _make_envelope(
		"ally_B", 3, srv.clock.current_tick_id, "CMD_JOIN_COALITION_RALLY",
		{
			"rally_id": rid,
			"army": {
				"troop_count": 1000,
				"morale_bp": 8800,
				"gear_pm": 1050,
				"officers": [{"pawn_id": "ally_B_avatar", "MAR": 78, "LEA": 76}]
			}
		}
	))
	var _t8: Dictionary = srv.step_micro_tick()

	var _sa6: bool = srv.transport.client_send_envelope("peer_lord_A", _make_envelope(
		"lord_A", 6, srv.clock.current_tick_id, "CMD_EXECUTE_COALITION_SIEGE",
		{
			"rally_id": rid,
			"target_node_id": "chenliu",
			"defender_army": {"troop_count": 300, "morale_bp": 6000, "officers": [{"officer_id": "yt_def", "MAR": 52, "LEA": 52}]}
		}
	))
	var _t9: Dictionary = srv.step_micro_tick()

	var chenliu_owner: String = str(srv.world_graph.get_node("chenliu").get("owner_faction_id", ""))
	var merit_a: int = _to_int(srv.faction_manager.get_player_profile("lord_A").get("war_merit", 0), 0)
	var merit_b: int = _to_int(srv.faction_manager.get_player_profile("ally_B").get("war_merit", 0), 0)
	_assert_cond(chenliu_owner == "fac_wei" and merit_a > 0 and merit_b > 0, "Coalition siege captured chenliu and distributed war_merit (A=%d, B=%d)" % [merit_a, merit_b], errors, checks)

	# -------------------------------------------------------------------------
	# Scenario 5: Offline Protection & Reconnect Gazette (F-38 & F-39)
	# -------------------------------------------------------------------------
	var off_res: Dictionary = srv.set_player_online("ally_B", false)
	var manor_b_v: Variant = srv.manors.get("ally_B", null)
	var manor_b_lod_off: int = -1
	if manor_b_v is ManorState:
		var mb: ManorState = manor_b_v
		manor_b_lod_off = mb.current_lod
	_assert_cond(_to_bool(off_res.get("ok", false), false) and manor_b_lod_off == 1, "ally_B went offline and manor demoted to LOD 1", errors, checks)

	var enq_res: Dictionary = srv.chronicle_inbox.enqueue_decision(
		"ally_B",
		"IMPERIAL_LEVY",
		["PAY_LEVY", "REFUSE_LEVY"],
		"PAY_LEVY",
		24,
		{"note": "Imperial levy deadline at first daily settlement"}
	)
	var dec_id: String = str(enq_res.get("decision_id", ""))
	_assert_cond(_to_bool(enq_res.get("ok", false), false) and not dec_id.is_empty(), "Async inbox decision enqueued for offline ally_B", errors, checks)

	while srv.clock.current_tick_id < effective_ticks:
		var _step_d: Dictionary = srv.step_micro_tick()

	var dec_after: Dictionary = srv.chronicle_inbox.get_decision(dec_id)
	_assert_cond(
		str(dec_after.get("status", "")) == "EXPIRED_DEFAULT" and str(dec_after.get("resolution_mode", "")) == "TIMEOUT_FALLBACK",
		"Offline async decision auto-resolved via TIMEOUT_FALLBACK at deadline_tick",
		errors,
		checks
	)
	_assert_cond(_checkpoint_count >= 2, "Executed >= 2 DAILY_SETTLEMENT_TICK persistence checkpoints (%d)" % _checkpoint_count, errors, checks)

	# Drain ally_B queue before reconnect so we isolate reconnect gazette delivery
	var _drain_b_pre: Array[Dictionary] = srv.transport.client_drain_incoming("peer_ally_B")
	var recon_res: Dictionary = srv.set_player_online("ally_B", true)
	var gazette: Dictionary = _as_dict(recon_res.get("gazette", {}))
	var vg: Dictionary = DtoSchemas.validate_offline_chronicle_digest(gazette)
	_assert_cond(_to_bool(vg.get("ok", false), false), "Reconnect gazette passes DtoSchemas.validate_offline_chronicle_digest", errors, checks)

	var msgs_b_recon: Array[Dictionary] = srv.transport.client_drain_incoming("peer_ally_B")
	var found_gazette_wire: bool = false
	for m: Dictionary in msgs_b_recon:
		if str(m.get("msg_type", "")) == DtoSchemas.MSG_OFFLINE_CHRONICLE_DIGEST:
			var vg2: Dictionary = DtoSchemas.validate_offline_chronicle_digest(m)
			if _to_bool(vg2.get("ok", false), false):
				found_gazette_wire = true
	_assert_cond(found_gazette_wire, "Schema-valid MSG_OFFLINE_CHRONICLE_DIGEST received over transport on reconnect", errors, checks)

	# Sync final relational checkpoint & atomic snapshot
	var final_snap_res: Dictionary = SnapshotSerializer.save_atomic_snapshot(snap_path, srv.to_deterministic_hash_dict())
	_assert_cond(_to_bool(final_snap_res.get("ok", false), false), "Final atomic world snapshot saved", errors, checks)

	var final_sql_res: Dictionary = SQLiteBridge.sync_world_checkpoint(db_path, _export_server_relational_snapshot(srv))
	_assert_cond(_to_bool(final_sql_res.get("ok", false), false), "Final SQLite relational checkpoint synced: " + str(final_sql_res.get("reason", "")), errors, checks)

	var int_res: Dictionary = SQLiteBridge.verify_integrity(db_path)
	_assert_cond(_to_bool(int_res.get("ok", false), false), "SQLiteBridge.verify_integrity passed", errors, checks)

	var wal_check: Dictionary = _wal_logger.read_records()
	_assert_cond(_to_bool(wal_check.get("ok", false), false) and _to_int(wal_check.get("corrupted_count", -1), -1) == 0, "WAL read cleanly with 0 corrupted records", errors, checks)

	for we: String in _wal_errors:
		errors.append(we)
	for ce: String in _checkpoint_errors:
		errors.append(ce)

	var report: Dictionary = {
		"schema_version": "1.0",
		"mode": "loopback",
		"world_seed": world_seed,
		"final_tick_id": srv.clock.current_tick_id,
		"state_crc32": srv.state_crc32,
		"daily_checkpoints": _checkpoint_count,
		"wal_records_written": _wal_write_count,
		"db_path": _resolve_path(db_path),
		"wal_path": _resolve_path(wal_path),
		"snapshot_path": _resolve_path(snap_path),
		"passed_checks": checks,
		"errors": errors,
		"overall_passed": errors.is_empty()
	}
	_write_json_report(out_path, report)

	if errors.is_empty():
		print("[net_harness:loopback] PASS ticks=%d crc32=%d checks=%d" % [srv.clock.current_tick_id, srv.state_crc32, checks.size()])
		return 0
	for e: String in errors:
		printerr("[net_harness:loopback] FAIL: " + e)
	return 1


func _count_audit_statuses(srv: AuthoritativeServer) -> Dictionary:
	var acc: int = 0
	var rej: int = 0
	for al: Dictionary in srv.command_validator.audit_log:
		var st: String = str(al.get("status", ""))
		if st == "ACCEPTED":
			acc += 1
		elif st == "REJECTED":
			rej += 1
	return {"accepted": acc, "rejected": rej}


func _run_server_mode(
	world_seed: int,
	target_ticks: int,
	port: int,
	expected_clients: int,
	db_path: String,
	wal_path: String,
	snap_path: String,
	out_path: String
) -> int:
	var errors: Array[String] = []
	var checks: Array[String] = []
	var effective_ticks: int = maxi(24, target_ticks)

	if port <= 0 or port > 65535:
		printerr("[net_harness:server] ERROR: Invalid --port=%d" % port)
		return 1

	var srv: AuthoritativeServer = AuthoritativeServer.new(world_seed, "ST_SIMA_QIAN")
	var listen_err: Error = srv.transport.listen_websocket(port, "127.0.0.1")
	if listen_err != OK:
		printerr("[net_harness:server] ERROR: Failed to listen WebSocket on 127.0.0.1:%d (err=%d)" % [port, int(listen_err)])
		return 1

	_init_persistence(srv, db_path, wal_path, snap_path, errors)
	print("[net_harness:server] Listening on ws://127.0.0.1:%d expected_clients=%d" % [port, expected_clients])

	var start_ms: int = Time.get_ticks_msec()
	var factions_seeded: bool = false

	while true:
		srv.transport.poll()
		var incoming: Array[Dictionary] = srv.transport.server_drain_incoming()
		for pkt: Dictionary in incoming:
			var pkey: String = str(pkt.get("peer_id", pkt.get("peer_key", "")))
			var raw_utf8: String = str(pkt.get("raw_utf8", ""))
			if not srv.sessions_by_peer.has(pkey):
				var parsed: Variant = JSON.parse_string(raw_utf8)
				if parsed is Dictionary:
					var pd: Dictionary = parsed
					var candidate_pid: String = str(pd.get("player_id", ""))
					if ALLOWED_BOTS.has(candidate_pid) and not srv.peer_by_player.has(candidate_pid):
						var _reg: Dictionary = srv.register_session(pkey, candidate_pid, candidate_pid)
			var _sub: Dictionary = srv.submit_raw_command(pkey, raw_utf8)

		if not srv._pending_commands.is_empty():
			var _st: Dictionary = srv.step_micro_tick()
			if not factions_seeded and srv.manors.has("lord_A") and srv.manors.has("ally_B"):
				if not srv.faction_manager.has_faction("fac_wei"):
					var _fw: Dictionary = srv.faction_manager.create_faction("fac_wei", "Wei", "lord_A", "xuchang", srv.world_graph, 15000, 15000, "PREFECT")
				if not srv.faction_manager.has_faction("fac_ally"):
					var _fa: Dictionary = srv.faction_manager.create_faction("fac_ally", "Allied_Commandery", "ally_B", "runan", srv.world_graph, 12000, 12000, "PREFECT")
				factions_seeded = true

		var audit_counts: Dictionary = _count_audit_statuses(srv)
		var scenario_ready: bool = (
			srv.sessions_by_peer.size() >= expected_clients
			and srv.manors.size() >= 3
			and srv.regional_market.orders.size() >= 2
			and _to_int(audit_counts.get("rejected", 0), 0) >= 3
			and _to_int(audit_counts.get("accepted", 0), 0) >= 5
		)
		if scenario_ready:
			break

		if Time.get_ticks_msec() - start_ms > WS_SERVER_WAIT_TIMEOUT_MS:
			errors.append("Timed out waiting for %d WebSocket clients & scenario commands (sessions=%d manors=%d orders=%d)" % [
				expected_clients, srv.sessions_by_peer.size(), srv.manors.size(), srv.regional_market.orders.size()
			])
			break

		OS.delay_msec(10)

	# Advance remaining ticks through at least effective_ticks (24+) so market matches and daily settlement runs
	while srv.clock.current_tick_id < effective_ticks:
		srv.transport.poll()
		var _extra_in: Array[Dictionary] = srv.transport.server_drain_incoming()
		for pkt2: Dictionary in _extra_in:
			var pkey2: String = str(pkt2.get("peer_id", pkt2.get("peer_key", "")))
			var _sub2: Dictionary = srv.submit_raw_command(pkey2, str(pkt2.get("raw_utf8", "")))
		var _tick_res: Dictionary = srv.step_micro_tick()
		srv.transport.poll()

	# Pump WebSocket frames briefly so clients receive final MSG_TICK_DELTA
	for _p: int in range(25):
		srv.transport.poll()
		OS.delay_msec(15)

	var final_snap: Dictionary = SnapshotSerializer.save_atomic_snapshot(snap_path, srv.to_deterministic_hash_dict())
	_assert_cond(_to_bool(final_snap.get("ok", false), false), "Server saved atomic snapshot", errors, checks)

	var final_sql: Dictionary = SQLiteBridge.sync_world_checkpoint(db_path, _export_server_relational_snapshot(srv))
	_assert_cond(_to_bool(final_sql.get("ok", false), false), "Server synced SQLite checkpoint", errors, checks)

	var int_res: Dictionary = SQLiteBridge.verify_integrity(db_path)
	_assert_cond(_to_bool(int_res.get("ok", false), false), "Server SQLite integrity check passed", errors, checks)

	var final_audits: Dictionary = _count_audit_statuses(srv)
	_assert_cond(_to_int(final_audits.get("accepted", 0), 0) >= 5, "Server audit_log accepted >= 5", errors, checks)
	_assert_cond(_to_int(final_audits.get("rejected", 0), 0) >= 2, "Server audit_log rejected >= 2", errors, checks)

	for we: String in _wal_errors:
		errors.append(we)
	for ce: String in _checkpoint_errors:
		errors.append(ce)

	var report: Dictionary = {
		"schema_version": "1.0",
		"mode": "server",
		"port": port,
		"world_seed": world_seed,
		"final_tick_id": srv.clock.current_tick_id,
		"state_crc32": srv.state_crc32,
		"connected_peers": srv.sessions_by_peer.size(),
		"manors_count": srv.manors.size(),
		"market_orders_count": srv.regional_market.orders.size(),
		"audit_counts": final_audits,
		"db_path": _resolve_path(db_path),
		"passed_checks": checks,
		"errors": errors,
		"overall_passed": errors.is_empty()
	}
	_write_json_report(out_path, report)
	srv.transport.close()

	if errors.is_empty():
		print("[net_harness:server] PASS ticks=%d peers=%d crc32=%d" % [srv.clock.current_tick_id, srv.sessions_by_peer.size(), srv.state_crc32])
		return 0
	for e: String in errors:
		printerr("[net_harness:server] FAIL: " + e)
	return 1


func _ws_wait_for_messages(
	tx: NetworkTransport,
	peer_id: String,
	received_all: Array[Dictionary],
	wait_ms: int = 50
) -> Array[Dictionary]:
	tx.poll()
	var fresh: Array[Dictionary] = tx.client_drain_incoming(peer_id)
	for msg: Dictionary in fresh:
		received_all.append(msg)
	if fresh.is_empty() and wait_ms > 0:
		OS.delay_msec(wait_ms)
	return fresh


func _run_client_mode(port: int, bot_id: String, out_path: String) -> int:
	var errors: Array[String] = []
	var checks: Array[String] = []

	if port <= 0 or port > 65535:
		printerr("[net_harness:client:%s] ERROR: Invalid --port=%d" % [bot_id, port])
		return 1
	if not ALLOWED_BOTS.has(bot_id):
		printerr("[net_harness:client:%s] ERROR: Unknown --bot=%s" % [bot_id, bot_id])
		return 1

	var tx: NetworkTransport = NetworkTransport.new(NetworkTransport.MODE_WEBSOCKET)
	var url: String = "ws://127.0.0.1:%d" % port
	var conn_err: Error = tx.connect_websocket(url)
	if conn_err != OK:
		printerr("[net_harness:client:%s] ERROR: connect_websocket failed (err=%d)" % [bot_id, int(conn_err)])
		return 1

	var conn_start: int = Time.get_ticks_msec()
	while not tx.is_ws_client_open():
		tx.poll()
		if Time.get_ticks_msec() - conn_start > WS_CONNECT_TIMEOUT_MS:
			errors.append("Timed out connecting to " + url)
			tx.close()
			_write_json_report(out_path, {"mode": "client", "bot_id": bot_id, "errors": errors, "overall_passed": false})
			return 1
		OS.delay_msec(10)

	checks.append("Connected to " + url)

	var inbox_all: Array[Dictionary] = []
	var receipts_by_seq: Dictionary = {}
	var tick_deltas_seen: int = 0
	var challenge_msg: Dictionary = {}

	var wait_start: int = Time.get_ticks_msec()

	if bot_id == "lord_A":
		var _s1: bool = tx.client_send_envelope(bot_id, _make_envelope(
			"lord_A", 1, 0, "CMD_REQUEST_PERSONA_CHALLENGE", {"account_id": "acc_lord_A", "nonce_salt": 101}
		))
		while challenge_msg.is_empty():
			var batch: Array[Dictionary] = _ws_wait_for_messages(tx, bot_id, inbox_all, 15)
			for m: Dictionary in batch:
				var mtype: String = str(m.get("msg_type", ""))
				if mtype == DtoSchemas.MSG_PERSONA_CHALLENGE:
					challenge_msg = m
				elif mtype == DtoSchemas.MSG_CMD_RECEIPT:
					receipts_by_seq[_to_int(m.get("cmd_seq", -1), -1)] = m
				elif mtype == DtoSchemas.MSG_TICK_DELTA:
					tick_deltas_seen += 1
			if Time.get_ticks_msec() - wait_start > WS_CLIENT_WAIT_TIMEOUT_MS:
				errors.append("lord_A timed out waiting for MSG_PERSONA_CHALLENGE")
				break

		if not challenge_msg.is_empty():
			var vc: Dictionary = DtoSchemas.validate_persona_challenge(challenge_msg)
			_assert_cond(_to_bool(vc.get("ok", false), false), "lord_A challenge valid", errors, checks)
			var slots_a: Array[int] = [3, 18, 12, 22, 16, 14, 0, 2, 10, 0, 5, 2, 3, 0, 1, 0]
			var tok_a: String = _encode_token_from_challenge(challenge_msg, slots_a)
			var _s2: bool = tx.client_send_envelope(bot_id, _make_envelope(
				"lord_A", 2, 1, "CMD_CREATE_CHARACTER",
				{
					"avatar_name": "Lord_A",
					"creation_mode": "FUSION_INTERVIEW",
					"sealed_token_input": "<<<TK3K_PERSONA_V2>>>\n%s\n<<<END_TK3K_PERSONA_V2>>>" % tok_a,
					"interview_answers": [0, 0, 0, 1, 1, 0, 0, 0],
					"province_override": "YU_ZHOU"
				}
			))
			var created_tick_a: int = -1
			var exec_tick_a: int = 999999
			while created_tick_a < exec_tick_a:
				var batch_a2: Array[Dictionary] = _ws_wait_for_messages(tx, bot_id, inbox_all, 15)
				for m: Dictionary in batch_a2:
					var mtype: String = str(m.get("msg_type", ""))
					if mtype == DtoSchemas.MSG_CMD_RECEIPT:
						receipts_by_seq[_to_int(m.get("cmd_seq", -1), -1)] = m
						if _to_int(m.get("cmd_seq", -1), -1) == 2:
							exec_tick_a = _to_int(m.get("exec_tick_id", 1), 1)
					elif mtype == DtoSchemas.MSG_TICK_DELTA:
						tick_deltas_seen += 1
						created_tick_a = maxi(created_tick_a, _to_int(m.get("tick_id", 0), 0))
				if Time.get_ticks_msec() - wait_start > WS_CLIENT_WAIT_TIMEOUT_MS:
					errors.append("lord_A timed out waiting for character creation tick")
					break
			var _s3: bool = tx.client_send_envelope(bot_id, _make_envelope(
				"lord_A", 3, maxi(1, created_tick_a), "CMD_PLACE_MARKET_ORDER",
				{"node_id": "xuchang", "commodity": "GRAIN", "side": "ASK", "price_bp": 1150, "quantity": 50}
			))

	elif bot_id == "ally_B":
		var _sb1: bool = tx.client_send_envelope(bot_id, _make_envelope(
			"ally_B", 1, 0, "CMD_CREATE_CHARACTER",
			{
				"avatar_name": "Ally_B",
				"creation_mode": "INTERVIEW_ONLY",
				"interview_answers": [1, 1, 0, 2, 1, 2, 0, 0],
				"province_override": "YU_ZHOU"
			}
		))
		var created_tick_b: int = -1
		var exec_tick_b: int = 999999
		while created_tick_b < exec_tick_b:
			var batch_b: Array[Dictionary] = _ws_wait_for_messages(tx, bot_id, inbox_all, 15)
			for m: Dictionary in batch_b:
				var mtype: String = str(m.get("msg_type", ""))
				if mtype == DtoSchemas.MSG_CMD_RECEIPT:
					receipts_by_seq[_to_int(m.get("cmd_seq", -1), -1)] = m
					if _to_int(m.get("cmd_seq", -1), -1) == 1:
						exec_tick_b = _to_int(m.get("exec_tick_id", 1), 1)
				elif mtype == DtoSchemas.MSG_TICK_DELTA:
					tick_deltas_seen += 1
					created_tick_b = maxi(created_tick_b, _to_int(m.get("tick_id", 0), 0))
			if Time.get_ticks_msec() - wait_start > WS_CLIENT_WAIT_TIMEOUT_MS:
				errors.append("ally_B timed out waiting for create tick")
				break
		var _sb2: bool = tx.client_send_envelope(bot_id, _make_envelope(
			"ally_B", 2, maxi(1, created_tick_b), "CMD_PLACE_MARKET_ORDER",
			{"node_id": "xuchang", "commodity": "GRAIN", "side": "BID", "price_bp": 1150, "quantity": 50}
		))

	elif bot_id == "raider_C":
		var _sc1: bool = tx.client_send_envelope(bot_id, _make_envelope(
			"raider_C", 1, 0, "CMD_CREATE_CHARACTER",
			{
				"avatar_name": "Raider_C_Hacked",
				"creation_mode": "FUSION_INTERVIEW",
				"sealed_token_input": "{\"schema\":\"AI_PERSONA_EXPORT_V1\",\"persona_weights\":{\"LEA\":99}}",
				"interview_answers": [0, 0, 0, 0, 0, 0, 0, 0],
				"province_override": "YONG_LIANG"
			}
		))
		var _sc2: bool = tx.client_send_envelope(bot_id, _make_envelope(
			"raider_C", 2, 0, "CMD_CREATE_CHARACTER",
			{
				"avatar_name": "Raider_C",
				"creation_mode": "INTERVIEW_ONLY",
				"interview_answers": [2, 3, 1, 0, 2, 1, 2, 3],
				"province_override": "YONG_LIANG"
			}
		))
		var _sc3: bool = tx.client_send_envelope(bot_id, _make_envelope(
			"raider_C", 3, 0, "CMD_SET_WORK_PRIORITY",
			{"manor_id": "manor_lord_A", "pawn_id": "lord_A_avatar", "domain": "PATROL", "priority": 1}
		))
		var _sc4: bool = tx.client_send_envelope(bot_id, _make_envelope(
			"raider_C", 4, 0, "CMD_PROPOSE_OR_SIGN_TREATY",
			{"target_faction_id": "fac_wei", "treaty_type": "ALLIANCE", "duration_days": 5}
		))

	var expected_seqs: Array[int] = [1, 2, 3, 4]
	if bot_id == "lord_A":
		expected_seqs = [1, 2, 3]
	elif bot_id == "ally_B":
		expected_seqs = [1, 2]

	while true:
		var batch_end: Array[Dictionary] = _ws_wait_for_messages(tx, bot_id, inbox_all, 15)
		for m: Dictionary in batch_end:
			var mtype: String = str(m.get("msg_type", ""))
			if mtype == DtoSchemas.MSG_CMD_RECEIPT:
				var vr: Dictionary = DtoSchemas.validate_cmd_receipt(m)
				if not _to_bool(vr.get("ok", false), false):
					errors.append("Invalid MSG_CMD_RECEIPT: " + str(vr.get("reason", "")))
				receipts_by_seq[_to_int(m.get("cmd_seq", -1), -1)] = m
			elif mtype == DtoSchemas.MSG_TICK_DELTA:
				var vd: Dictionary = DtoSchemas.validate_tick_delta(m)
				if not _to_bool(vd.get("ok", false), false):
					errors.append("Invalid MSG_TICK_DELTA: " + str(vd.get("reason", "")))
				tick_deltas_seen += 1

		var all_receipts_ok: bool = true
		for seq: int in expected_seqs:
			if not receipts_by_seq.has(seq):
				all_receipts_ok = false
				break
		if all_receipts_ok and tick_deltas_seen >= 1:
			break
		if Time.get_ticks_msec() - wait_start > WS_CLIENT_WAIT_TIMEOUT_MS:
			errors.append("Timed out waiting for receipts (%s) and MSG_TICK_DELTA (deltas=%d)" % [str(receipts_by_seq.keys()), tick_deltas_seen])
			break

	# Verify expected receipt outcomes per bot
	if bot_id == "lord_A":
		for seq: int in [1, 2, 3]:
			var r_d: Dictionary = _as_dict(receipts_by_seq.get(seq, {}))
			_assert_cond(str(r_d.get("status", "")) == "ACCEPTED", "lord_A seq=%d ACCEPTED" % seq, errors, checks)
	elif bot_id == "ally_B":
		for seq: int in [1, 2]:
			var r_d: Dictionary = _as_dict(receipts_by_seq.get(seq, {}))
			_assert_cond(str(r_d.get("status", "")) == "ACCEPTED", "ally_B seq=%d ACCEPTED" % seq, errors, checks)
	elif bot_id == "raider_C":
		var r1: Dictionary = _as_dict(receipts_by_seq.get(1, {}))
		var r2: Dictionary = _as_dict(receipts_by_seq.get(2, {}))
		var r3: Dictionary = _as_dict(receipts_by_seq.get(3, {}))
		var r4: Dictionary = _as_dict(receipts_by_seq.get(4, {}))
		_assert_cond(str(r1.get("status", "")) == "REJECTED" and str(r1.get("error_code", "")) == DtoSchemas.ERR_PLAINTEXT_JSON_FORBIDDEN, "raider_C seq=1 REJECTED (ERR_PLAINTEXT_JSON_FORBIDDEN)", errors, checks)
		_assert_cond(str(r2.get("status", "")) == "ACCEPTED", "raider_C seq=2 ACCEPTED (INTERVIEW_ONLY)", errors, checks)
		_assert_cond(str(r3.get("status", "")) == "REJECTED" and str(r3.get("error_code", "")) == DtoSchemas.ERR_UNAUTHORIZED, "raider_C seq=3 REJECTED (ERR_UNAUTHORIZED)", errors, checks)
		_assert_cond(str(r4.get("status", "")) == "REJECTED" and str(r4.get("error_code", "")) == DtoSchemas.ERR_ROLE_PERMISSION, "raider_C seq=4 REJECTED (ERR_ROLE_PERMISSION)", errors, checks)

	_assert_cond(tick_deltas_seen >= 1, "Received >= 1 schema-valid MSG_TICK_DELTA (%d)" % tick_deltas_seen, errors, checks)

	var report: Dictionary = {
		"schema_version": "1.0",
		"mode": "client",
		"bot_id": bot_id,
		"port": port,
		"tick_deltas_seen": tick_deltas_seen,
		"receipts_count": receipts_by_seq.size(),
		"passed_checks": checks,
		"errors": errors,
		"overall_passed": errors.is_empty()
	}
	_write_json_report(out_path, report)
	tx.close()

	if errors.is_empty():
		print("[net_harness:client:%s] PASS receipts=%d deltas=%d" % [bot_id, receipts_by_seq.size(), tick_deltas_seen])
		return 0
	for e: String in errors:
		printerr("[net_harness:client:%s] FAIL: " + e)
	return 1
