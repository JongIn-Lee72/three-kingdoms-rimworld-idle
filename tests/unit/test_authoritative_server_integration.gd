class_name TestAuthoritativeServerIntegration
extends HarnessTestCase

const TEST_WAL_PATH: String = "/tmp/test_m5_srv_wal.log"
const TEST_SNAP_PATH: String = "/tmp/test_m5_srv_snap.json"
const TEST_DB_PATH: String = "/tmp/test_m5_server.db"

var _wal_ref: WALLogger = null
var _snap_saved_count: int = 0
var _sqlite_sync_ok: bool = false


func _as_bool(v: Variant, fallback: bool = false) -> bool:
	if v is bool:
		var bv: bool = v
		return bv
	return fallback


func _as_int(v: Variant, fallback: int = 0) -> int:
	if v is int:
		var iv: int = v
		return iv
	if v is float:
		var fv: float = v
		return int(fv)
	return fallback


func _as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		var d: Dictionary = v
		return d
	return {}


func _as_array(v: Variant) -> Array:
	if v is Array:
		var a: Array = v
		return a
	return []


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		var _err: Error = DirAccess.remove_absolute(path)


func after_each() -> void:
	_wal_ref = null
	_snap_saved_count = 0
	_sqlite_sync_ok = false
	_remove_if_exists(TEST_WAL_PATH)
	_remove_if_exists(TEST_SNAP_PATH)
	_remove_if_exists(TEST_SNAP_PATH + ".tmp")
	_remove_if_exists(TEST_DB_PATH)
	_remove_if_exists(TEST_DB_PATH + "-wal")
	_remove_if_exists(TEST_DB_PATH + "-shm")


func _send_cmd(srv: AuthoritativeServer, peer_id: String, player_id: String, seq: int, cmd_type: String, args: Dictionary) -> bool:
	var env: Dictionary = {
		"v": 1,
		"cmd_seq": seq,
		"client_tick": srv.clock.current_tick_id,
		"player_id": player_id,
		"cmd_type": cmd_type,
		"args": args
	}
	return srv.transport.client_send_envelope(peer_id, env)


func _on_wal_record(rec: Dictionary) -> void:
	if _wal_ref != null and _wal_ref.is_open():
		var payload_d: Dictionary = _as_dict(rec.get("payload", {}))
		var _app: Dictionary = _wal_ref.append_record(
			_as_int(rec.get("tick_id", 0), 0),
			_as_int(rec.get("cmd_seq", 0), 0),
			str(rec.get("player_id", "")),
			str(rec.get("cmd_type", "")),
			payload_d
		)


func _on_daily_checkpoint(srv: AuthoritativeServer) -> void:
	var snap_state: Dictionary = srv.to_deterministic_hash_dict()
	var s_res: Dictionary = SnapshotSerializer.save_atomic_snapshot(TEST_SNAP_PATH, snap_state)
	if _as_bool(s_res.get("ok", false), false):
		_snap_saved_count += 1
	var sql_res: Dictionary = SQLiteBridge.sync_world_checkpoint(TEST_DB_PATH, srv.export_relational_snapshot())
	if _as_bool(sql_res.get("ok", false), false):
		_sqlite_sync_ok = true


func test_end_to_end_3_player_shared_world_persistence_and_roundtrip() -> void:
	_remove_if_exists(TEST_WAL_PATH)
	_remove_if_exists(TEST_SNAP_PATH)
	_remove_if_exists(TEST_DB_PATH)

	var srv: AuthoritativeServer = AuthoritativeServer.new(18401, "ST_SIMA_QIAN")
	_wal_ref = WALLogger.new()
	var wal_open: Dictionary = _wal_ref.open_wal(TEST_WAL_PATH)
	assert_true(_as_bool(wal_open.get("ok", false), false), "WAL opened for server")
	var init_db: Dictionary = SQLiteBridge.init_database(TEST_DB_PATH)
	assert_true(_as_bool(init_db.get("ok", false), false), "SQLite DB initialized for server")
	srv.attach_persistence_handlers(Callable(self, "_on_wal_record"), Callable(self, "_on_daily_checkpoint"))

	# Register 3 peers: lord_A, ally_B, raider_C
	var r_a: Dictionary = srv.register_session("peer_a", "lord_A", "Lord A")
	var r_b: Dictionary = srv.register_session("peer_b", "ally_B", "Ally B")
	var r_c: Dictionary = srv.register_session("peer_c", "raider_C", "Raider C")
	assert_true(_as_bool(r_a.get("ok", false), false), "lord_A session registered")
	assert_true(_as_bool(r_b.get("ok", false), false), "ally_B session registered")
	assert_true(_as_bool(r_c.get("ok", false), false), "raider_C session registered")

	# Step 1: 2-step character creation
	# lord_A & ally_B use FUSION_INTERVIEW with TK3K2 sealed token via CMD_REQUEST_PERSONA_CHALLENGE -> CMD_CREATE_CHARACTER
	# raider_C uses INTERVIEW_ONLY
	assert_true(_send_cmd(srv, "peer_a", "lord_A", 1, "CMD_REQUEST_PERSONA_CHALLENGE", {"account_id": "acc_a", "nonce_salt": 11}), "lord_A challenge request sent")
	assert_true(_send_cmd(srv, "peer_b", "ally_B", 1, "CMD_REQUEST_PERSONA_CHALLENGE", {"account_id": "acc_b", "nonce_salt": 22}), "ally_B challenge request sent")
	assert_true(_send_cmd(srv, "peer_c", "raider_C", 1, "CMD_CREATE_CHARACTER", {
		"avatar_name": "Raider_C",
		"creation_mode": "INTERVIEW_ONLY",
		"interview_answers": [1, 3, 2, 0, 1, 3, 2, 1],
		"province_override": "JI_ZHOU"
	}), "raider_C INTERVIEW_ONLY create sent")

	var _t1: Dictionary = srv.step_micro_tick()
	var msgs_a1: Array[Dictionary] = srv.transport.client_drain_incoming("peer_a")
	var msgs_b1: Array[Dictionary] = srv.transport.client_drain_incoming("peer_b")
	var _msgs_c1: Array[Dictionary] = srv.transport.client_drain_incoming("peer_c")

	var chal_a_id: String = ""
	for m: Dictionary in msgs_a1:
		if str(m.get("msg_type", "")) == DtoSchemas.MSG_PERSONA_CHALLENGE:
			var vc_a: Dictionary = DtoSchemas.validate_persona_challenge(m)
			assert_true(_as_bool(vc_a.get("ok", false), false), "lord_A challenge passes schema check")
			chal_a_id = str(m.get("challenge_id", ""))
	assert_false(chal_a_id.is_empty(), "lord_A received challenge_id")

	var chal_b_id: String = ""
	for m: Dictionary in msgs_b1:
		if str(m.get("msg_type", "")) == DtoSchemas.MSG_PERSONA_CHALLENGE:
			chal_b_id = str(m.get("challenge_id", ""))
	assert_false(chal_b_id.is_empty(), "ally_B received challenge_id")

	var slots_a: Array[int] = [3, 18, 12, 22, 16, 14, 0, 2, 10, 0, 5, 2, 3, 0, 1, 0]
	var slots_b: Array[int] = [2, 14, 20, 12, 16, 18, 1, 0, 10, 4, 8, 1, 1, 2, 0, 0]
	var tok_a: String = SealedTokenCodec.encode_tk3k2(chal_a_id, "lord_A", slots_a)
	var tok_b: String = SealedTokenCodec.encode_tk3k2(chal_b_id, "ally_B", slots_b)
	assert_contains(tok_a, "TK3K2-", "Encoded lord_A TK3K2 sealed token")
	assert_contains(tok_b, "TK3K2-", "Encoded ally_B TK3K2 sealed token")

	assert_true(_send_cmd(srv, "peer_a", "lord_A", 2, "CMD_CREATE_CHARACTER", {
		"avatar_name": "Lord_A",
		"creation_mode": "FUSION_INTERVIEW",
		"sealed_token_input": "<<<TK3K_PERSONA_V2>>>\n%s\n<<<END_TK3K_PERSONA_V2>>>" % tok_a,
		"interview_answers": [0, 0, 0, 1, 1, 0, 0, 0],
		"province_override": "YU_ZHOU"
	}), "lord_A FUSION_INTERVIEW create sent")
	assert_true(_send_cmd(srv, "peer_b", "ally_B", 2, "CMD_CREATE_CHARACTER", {
		"avatar_name": "Ally_B",
		"creation_mode": "FUSION_INTERVIEW",
		"sealed_token_input": "<<<TK3K_PERSONA_V2>>>\n%s\n<<<END_TK3K_PERSONA_V2>>>" % tok_b,
		"interview_answers": [1, 1, 1, 0, 1, 1, 2, 0],
		"province_override": "YU_ZHOU"
	}), "ally_B FUSION_INTERVIEW create sent")

	var _t2: Dictionary = srv.step_micro_tick()
	var _da2: Array[Dictionary] = srv.transport.client_drain_incoming("peer_a")
	var _db2: Array[Dictionary] = srv.transport.client_drain_incoming("peer_b")

	assert_true(srv.manors.has("lord_A"), "lord_A manor created")
	assert_true(srv.manors.has("ally_B"), "ally_B manor created")
	assert_true(srv.manors.has("raider_C"), "raider_C manor created")
	var acct_a: Dictionary = _as_dict(srv.player_accounts.get("lord_A", {}))
	var acct_c: Dictionary = _as_dict(srv.player_accounts.get("raider_C", {}))
	assert_eq(str(acct_a.get("creation_mode", "")), "FUSION_INTERVIEW", "lord_A creation_mode == FUSION_INTERVIEW")
	assert_eq(str(acct_a.get("import_audit_status", "")), "VERIFIED_CLEAN", "lord_A import_audit_status == VERIFIED_CLEAN")
	assert_eq(str(acct_c.get("creation_mode", "")), "INTERVIEW_ONLY", "raider_C creation_mode == INTERVIEW_ONLY")

	# Step 2: Establish faction_A (lord_A = LORD, ally_B = FACTION_OFFICER/GOVERNOR) and faction_C (raider_C)
	var fac_a_res: Dictionary = srv.faction_manager.create_faction("fac_A", "Faction A", "lord_A", "xuchang", srv.world_graph, 15000, 15000, "PREFECT")
	assert_true(_as_bool(fac_a_res.get("ok", false), false), "fac_A created")
	assert_true(_send_cmd(srv, "peer_b", "ally_B", 3, "CMD_ENLIST_FACTION", {"faction_id": "fac_A", "initial_rank": "RANK_5"}), "ally_B enlist sent")
	var _fac_c_res: Dictionary = srv.faction_manager.create_faction("fac_C", "Faction C", "raider_C", "ye_city", srv.world_graph, 8000, 8000, "PREFECT")
	var _t3: Dictionary = srv.step_micro_tick()

	var _sub_a_fac: bool = srv.interest_manager.subscribe("peer_a", DtoSchemas.CHAN_FACTION + ":fac_A")
	var _sub_b_fac: bool = srv.interest_manager.subscribe("peer_b", DtoSchemas.CHAN_FACTION + ":fac_A")

	# Step 3: Shared market trade at xuchang (lord_A ASK 50 GRAIN @ 1100, ally_B BID 50 GRAIN @ 1100)
	var m_a: ManorState = srv.manors["lord_A"]
	var m_b: ManorState = srv.manors["ally_B"]
	var _gb: int = m_a.add_resource("GRAIN", 500)
	var _cb: int = m_b.add_resource("COIN", 500)
	assert_true(_send_cmd(srv, "peer_a", "lord_A", 3, "CMD_PLACE_MARKET_ORDER", {
		"node_id": "xuchang",
		"commodity": "GRAIN",
		"side": "ASK",
		"price_bp": 1100,
		"quantity": 50
	}), "lord_A ASK order sent")
	assert_true(_send_cmd(srv, "peer_b", "ally_B", 4, "CMD_PLACE_MARKET_ORDER", {
		"node_id": "xuchang",
		"commodity": "GRAIN",
		"side": "BID",
		"price_bp": 1100,
		"quantity": 50
	}), "ally_B BID order sent")

	# Step 4: Adversarial raider_C unauthorized / cheat commands (must be rejected & logged)
	assert_true(_send_cmd(srv, "peer_c", "raider_C", 2, "CMD_SET_WORK_PRIORITY", {
		"manor_id": "manor_lord_A",
		"pawn_id": "lord_A_avatar",
		"domain": "PATROL",
		"priority": 1
	}), "raider_C cross-manor cheat command sent")
	assert_true(_send_cmd(srv, "peer_c", "raider_C", 3, "CMD_SET_NODE_POLICY", {
		"node_id": "xuchang",
		"tax_rate_bp": 1500,
		"defense_budget": 100
	}), "raider_C unauthorized node policy command sent")

	# Step 5: Coalition rally & siege against YELLOW_TURBAN node "chenliu"
	assert_true(_send_cmd(srv, "peer_a", "lord_A", 4, "CMD_CREATE_COALITION_RALLY", {
		"target_node_id": "chenliu",
		"army": {
			"troop_count": 1200,
			"morale_bp": 9000,
			"gear_pm": 1100,
			"troop_composition": {"SIEGE_ENGINE": 10},
			"officers": [{"pawn_id": "lord_A_avatar", "MAR": 80, "LEA": 80}]
		}
	}), "lord_A create coalition rally sent")

	# Step past MACRO_TICK=6 so orders match and rally is created
	while srv.clock.current_tick_id < 6:
		var _sm: Dictionary = srv.step_micro_tick()

	# Verify market trade matched at macro tick 6
	assert_gt(srv.regional_market.trade_history.size(), 0, "Shared market executed trade at MACRO_TICK")
	var book_matched: bool = false
	for tr_rec: Dictionary in srv.regional_market.trade_history:
		if str(tr_rec.get("type", "")) == "BOOK_MATCH" and _as_int(tr_rec.get("quantity", 0), 0) == 50:
			book_matched = true
	assert_true(book_matched, "lord_A ASK matched with ally_B BID via BOOK_MATCH")

	# ally_B joins rally_000001 and lord_A executes siege
	var rally_ids: Array[String] = srv.siege_resolver.get_rally_ids()
	assert_eq(rally_ids.size(), 1, "1 coalition rally created")
	var rid: String = rally_ids[0] if not rally_ids.is_empty() else "rally_000001"
	assert_true(_send_cmd(srv, "peer_b", "ally_B", 5, "CMD_JOIN_COALITION_RALLY", {
		"rally_id": rid,
		"army": {
			"troop_count": 1000,
			"morale_bp": 8800,
			"gear_pm": 1050,
			"officers": [{"pawn_id": "ally_B_avatar", "MAR": 78, "LEA": 75}]
		}
	}), "ally_B join rally sent")
	var _t7: Dictionary = srv.step_micro_tick()

	assert_true(_send_cmd(srv, "peer_a", "lord_A", 5, "CMD_EXECUTE_COALITION_SIEGE", {
		"rally_id": rid,
		"target_node_id": "chenliu",
		"defender_army": {"troop_count": 300, "morale_bp": 6000, "officers": [{"officer_id": "def_1", "MAR": 55, "LEA": 55}]}
	}), "lord_A execute coalition siege sent")
	var _t8: Dictionary = srv.step_micro_tick()

	assert_eq(srv.siege_resolver.siege_history.size(), 1, "Coalition siege resolved and recorded")
	assert_eq(str(srv.world_graph.get_node("chenliu").get("owner_faction_id", "")), "fac_A", "chenliu captured by fac_A")
	assert_gt(_as_int(srv.faction_manager.get_player_profile("ally_B").get("war_merit", 0), 0), 0, "ally_B earned coalition war_merit")

	# Step 6: Take ally_B offline, advance through DAILY_SETTLEMENT_TICK (tick 24+), then reconnect
	var _off_res: Dictionary = srv.set_player_online("ally_B", false)
	assert_eq(m_b.current_lod, 1, "Offline peaceful ally_B demoted to LOD 1")

	while srv.clock.current_tick_id < 26:
		var _sd: Dictionary = srv.step_micro_tick()

	assert_gte(_snap_saved_count, 1, "Daily settlement hook saved >= 1 atomic snapshot")
	assert_true(_sqlite_sync_ok, "Daily settlement hook synced SQLite checkpoint")

	# Reconnect ally_B and verify MSG_OFFLINE_CHRONICLE_DIGEST delivery
	var _drain_b_before: Array[Dictionary] = srv.transport.client_drain_incoming("peer_b")
	var recon_res: Dictionary = srv.set_player_online("ally_B", true)
	assert_true(_as_bool(recon_res.get("ok", false), false), "ally_B reconnected")
	assert_eq(m_b.current_lod, 0, "Reconnected ally_B promoted back to LOD 0")
	var gazette: Dictionary = _as_dict(recon_res.get("gazette", {}))
	var vg: Dictionary = DtoSchemas.validate_offline_chronicle_digest(gazette)
	assert_true(_as_bool(vg.get("ok", false), false), "Reconnect gazette passes DtoSchemas.validate_offline_chronicle_digest")
	var msgs_b_recon: Array[Dictionary] = srv.transport.client_drain_incoming("peer_b")
	var found_digest_pkt: bool = false
	for pkt: Dictionary in msgs_b_recon:
		if str(pkt.get("msg_type", "")) == DtoSchemas.MSG_OFFLINE_CHRONICLE_DIGEST:
			found_digest_pkt = true
	assert_true(found_digest_pkt, "MSG_OFFLINE_CHRONICLE_DIGEST delivered over transport on reconnect")

	# Verify WAL records, SQLite integrity, and BOTH ACCEPTED + REJECTED in command_audit_log
	var wal_check: Dictionary = _wal_ref.read_records()
	assert_true(_as_bool(wal_check.get("ok", false), false), "WAL read succeeds")
	assert_eq(_as_int(wal_check.get("corrupted_count", -1), -1), 0, "0 corrupted WAL lines")
	assert_gte(_as_array(wal_check.get("records", [])).size(), 7, "WAL captured all accepted server commands")

	var int_res: Dictionary = SQLiteBridge.verify_integrity(TEST_DB_PATH)
	assert_true(_as_bool(int_res.get("ok", false), false), "SQLite verify_integrity passes: " + str(int_res.get("reason", "")))
	assert_eq(_as_array(int_res.get("foreign_key_violations", [])).size(), 0, "0 FK violations in server DB")

	var counts_res: Dictionary = SQLiteBridge.query_table_counts(TEST_DB_PATH)
	var counts: Dictionary = _as_dict(counts_res.get("counts", {}))
	assert_gte(_as_int(counts.get("players", 0), 0), 3, "SQLite players >= 3")
	assert_gte(_as_int(counts.get("manors", 0), 0), 3, "SQLite manors >= 3")
	assert_gte(_as_int(counts.get("market_orders", 0), 0), 2, "SQLite market_orders >= 2")
	assert_gte(_as_int(counts.get("command_audit_log", 0), 0), 9, "SQLite command_audit_log populated")

	var accepted_cnt: int = 0
	var rejected_cnt: int = 0
	for al: Dictionary in srv.command_validator.audit_log:
		var st: String = str(al.get("status", ""))
		if st == "ACCEPTED":
			accepted_cnt += 1
		elif st == "REJECTED":
			rejected_cnt += 1
	assert_gt(accepted_cnt, 0, "command_audit_log contains ACCEPTED records")
	assert_gte(rejected_cnt, 2, "command_audit_log contains REJECTED records from raider_C")

	# Verify deterministic to_dict() / from_dict() round-trip
	var srv_dict: Dictionary = srv.to_dict()
	var restored: AuthoritativeServer = AuthoritativeServer.from_dict(srv_dict)
	assert_eq(restored.compute_state_crc32(), srv.compute_state_crc32(), "AuthoritativeServer to_dict/from_dict preserves exact state_crc32")
	assert_eq(restored.clock.current_tick_id, srv.clock.current_tick_id, "Restored clock tick matches")

	# Step both original and restored forward 6 more ticks and assert identical CRC32
	for _i: int in range(6):
		var _s1: Dictionary = srv.step_micro_tick()
		var _s2: Dictionary = restored.step_micro_tick()
	assert_eq(restored.compute_state_crc32(), srv.compute_state_crc32(), "Restored server steps identically to original server")
