class_name TestPersistenceEngine
extends HarnessTestCase

const TEST_WAL_PATH: String = "/tmp/test_m5_wal.log"
const TEST_SNAP_PATH: String = "/tmp/test_m5_snapshot.json"
const TEST_DB_PATH: String = "/tmp/test_m5_world.db"


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
	_remove_if_exists(TEST_WAL_PATH)
	_remove_if_exists(TEST_SNAP_PATH)
	_remove_if_exists(TEST_SNAP_PATH + ".tmp")
	_remove_if_exists(TEST_DB_PATH)
	_remove_if_exists(TEST_DB_PATH + "-wal")
	_remove_if_exists(TEST_DB_PATH + "-shm")


func test_wal_logger_append_read_crc_corrupt_after_tick_and_truncate() -> void:
	_remove_if_exists(TEST_WAL_PATH)
	var wal: WALLogger = WALLogger.new()

	# Invalid empty path rejected
	var bad_open: Dictionary = wal.open_wal("")
	assert_false(_as_bool(bad_open.get("ok", true), true), "Empty WAL path must fail")
	assert_eq(str(bad_open.get("error_code", "")), DtoSchemas.ERR_SCHEMA, "Empty WAL path returns ERR_SCHEMA")

	# Append before open rejected
	var pre_append: Dictionary = wal.append_record(1, 1, "p1", "CMD_SET_DOCTRINE", {"a": 1})
	assert_false(_as_bool(pre_append.get("ok", true), true), "Append before open must fail")

	var open_res: Dictionary = wal.open_wal(TEST_WAL_PATH)
	assert_true(_as_bool(open_res.get("ok", false), false), "open_wal succeeds")
	assert_true(wal.is_open(), "WAL reports is_open == true")

	# Non-deterministic float payload rejected
	var float_res: Dictionary = wal.append_record(1, 1, "p1", "CMD_SET_DOCTRINE", {"bad_float": 1.25})
	assert_false(_as_bool(float_res.get("ok", true), true), "Float payload rejected in WAL")
	assert_eq(str(float_res.get("error_code", "")), DtoSchemas.ERR_SCHEMA, "Float payload returns ERR_SCHEMA")

	# Append 3 canonical records at ticks 2, 5, 9
	var r1: Dictionary = wal.append_record(2, 1, "lord_a", "CMD_BUILD_OR_UPGRADE", {"building_id": "MILITARY_FARM"})
	var r2: Dictionary = wal.append_record(5, 2, "lord_a", "CMD_SET_WORK_PRIORITY", {"domain": "AGRICULTURE", "priority": 1})
	var r3: Dictionary = wal.append_record(9, 3, "ally_b", "CMD_PLACE_MARKET_ORDER", {"commodity": "GRAIN", "qty": 100})
	assert_true(_as_bool(r1.get("ok", false), false), "Record 1 appended")
	assert_true(_as_bool(r2.get("ok", false), false), "Record 2 appended")
	assert_true(_as_bool(r3.get("ok", false), false), "Record 3 appended")
	assert_gt(_as_int(r1.get("crc32", 0), 0), 0, "Record 1 crc32 > 0")

	# Read all records back
	var read_all: Dictionary = wal.read_records()
	assert_true(_as_bool(read_all.get("ok", false), false), "read_records succeeds")
	assert_eq(_as_int(read_all.get("corrupted_count", -1), -1), 0, "0 corrupted lines initially")
	var recs: Array = _as_array(read_all.get("records", []))
	assert_eq(recs.size(), 3, "Read back 3 canonical WAL records")

	# after_tick filtering
	var read_after_5: Dictionary = wal.read_records("", 5)
	var after_recs: Array = _as_array(read_after_5.get("records", []))
	assert_eq(after_recs.size(), 1, "after_tick=5 returns only tick 9 record")
	if not after_recs.is_empty():
		var rec9: Dictionary = _as_dict(after_recs[0])
		assert_eq(_as_int(rec9.get("tick_id", 0), 0), 9, "Filtered record has tick_id == 9")
		assert_eq(str(rec9.get("player_id", "")), "ally_b", "Filtered record player_id matches")

	# Append corrupted JSON line + tampered CRC32 line directly to WAL file
	var f_read: FileAccess = FileAccess.open(TEST_WAL_PATH, FileAccess.READ)
	var existing_txt: String = f_read.get_as_text() if f_read != null else ""
	if f_read != null:
		f_read.close()
	var tampered_rec: String = StateHasher.canonical_json({
		"tick_id": 12,
		"cmd_seq": 4,
		"player_id": "raider_c",
		"cmd_type": "CMD_SET_DOCTRINE",
		"payload": {"hacked": true},
		"crc32": 123456789
	})
	var f_write: FileAccess = FileAccess.open(TEST_WAL_PATH, FileAccess.WRITE)
	assert_not_null(f_write, "Opened WAL for corruption injection")
	if f_write != null:
		var _ok_w: bool = f_write.store_string(existing_txt + "{broken_json_line\n" + tampered_rec + "\n")
		f_write.flush()
		f_write.close()

	var read_corrupt: Dictionary = wal.read_records()
	assert_true(_as_bool(read_corrupt.get("ok", false), false), "read_records handles corrupted lines cleanly")
	assert_eq(_as_int(read_corrupt.get("corrupted_count", 0), 0), 2, "Detected 2 corrupted WAL lines (bad JSON + bad CRC32)")
	var valid_after_corrupt: Array = _as_array(read_corrupt.get("records", []))
	assert_eq(valid_after_corrupt.size(), 3, "Valid 3 records still recovered cleanly")

	# Truncate WAL
	var trunc_ok: bool = wal.truncate_wal()
	assert_true(trunc_ok, "truncate_wal succeeds")
	var read_empty: Dictionary = wal.read_records()
	assert_eq(_as_array(read_empty.get("records", [])).size(), 0, "WAL empty after truncate")
	assert_eq(_as_int(read_empty.get("corrupted_count", -1), -1), 0, "0 corrupted lines after truncate")


func test_snapshot_serializer_atomic_save_load_tamper_and_crash_recovery() -> void:
	_remove_if_exists(TEST_SNAP_PATH)
	_remove_if_exists(TEST_WAL_PATH)

	var world_state: Dictionary = {
		"world_id": "world_test_m5",
		"world_seed": 18401,
		"current_tick_id": 24,
		"manors": [{"manor_id": "manor_a", "grain": 1500}],
		"factions": [{"faction_id": "fac_a", "prestige": 250}]
	}

	var save_res: Dictionary = SnapshotSerializer.save_atomic_snapshot(TEST_SNAP_PATH, world_state)
	assert_true(_as_bool(save_res.get("ok", false), false), "save_atomic_snapshot succeeds")
	assert_false(FileAccess.file_exists(TEST_SNAP_PATH + ".tmp"), "Atomic rename leaves no .tmp file")
	assert_eq(_as_int(save_res.get("snapshot_tick_id", -1), -1), 24, "snapshot_tick_id == 24")

	var load_res: Dictionary = SnapshotSerializer.load_snapshot(TEST_SNAP_PATH)
	assert_true(_as_bool(load_res.get("ok", false), false), "load_snapshot succeeds")
	assert_eq(_as_int(load_res.get("state_crc32", 0), 0), _as_int(save_res.get("state_crc32", -1), -1), "state_crc32 matches")
	assert_eq(str(load_res.get("state_sha256", "")), str(save_res.get("state_sha256", "x")), "state_sha256 matches")

	# Crash recovery combines snapshot at tick 24 with WAL tail (ticks > 24 only)
	var wal: WALLogger = WALLogger.new()
	var _wo: Dictionary = wal.open_wal(TEST_WAL_PATH)
	var _a1: Dictionary = wal.append_record(10, 1, "lord_a", "CMD_SET_DOCTRINE", {"old": 1})
	var _a2: Dictionary = wal.append_record(24, 2, "lord_a", "CMD_SET_DOCTRINE", {"at_snap": 1})
	var _a3: Dictionary = wal.append_record(25, 3, "lord_a", "CMD_BUILD_OR_UPGRADE", {"building_id": "BARRACKS_DRILL"})
	var _a4: Dictionary = wal.append_record(31, 4, "ally_b", "CMD_PLACE_MARKET_ORDER", {"qty": 50})

	var recov: Dictionary = SnapshotSerializer.load_for_crash_recovery(TEST_SNAP_PATH, TEST_WAL_PATH, wal)
	assert_true(_as_bool(recov.get("ok", false), false), "load_for_crash_recovery succeeds")
	assert_true(_as_bool(recov.get("has_snapshot", false), false), "has_snapshot == true")
	assert_eq(_as_int(recov.get("snapshot_tick_id", -1), -1), 24, "recovery snapshot_tick_id == 24")
	var replay: Array = _as_array(recov.get("replay_records", []))
	assert_eq(replay.size(), 2, "Only WAL records strictly after tick 24 (ticks 25 and 31) included in replay tail")
	if replay.size() == 2:
		assert_eq(_as_int(_as_dict(replay[0]).get("tick_id", 0), 0), 25, "First replay record is tick 25")
		assert_eq(_as_int(_as_dict(replay[1]).get("tick_id", 0), 0), 31, "Second replay record is tick 31")

	# Tampered snapshot detection
	var f_snap: FileAccess = FileAccess.open(TEST_SNAP_PATH, FileAccess.READ)
	var snap_txt: String = f_snap.get_as_text() if f_snap != null else ""
	if f_snap != null:
		f_snap.close()
	var tampered_txt: String = snap_txt.replace("1500", "999999")
	var f_tamper: FileAccess = FileAccess.open(TEST_SNAP_PATH, FileAccess.WRITE)
	if f_tamper != null:
		var _ok_t: bool = f_tamper.store_string(tampered_txt)
		f_tamper.flush()
		f_tamper.close()

	var bad_load: Dictionary = SnapshotSerializer.load_snapshot(TEST_SNAP_PATH)
	assert_false(_as_bool(bad_load.get("ok", true), true), "Tampered snapshot rejected")
	assert_eq(str(bad_load.get("error_code", "")), DtoSchemas.ERR_TOKEN_TAMPERED, "Tampered snapshot returns ERR_TOKEN_TAMPERED")


func test_sqlite_bridge_all_10_tables_integrity_and_sql_quote_injection() -> void:
	_remove_if_exists(TEST_DB_PATH)

	# SQL injection quote escaping verification
	var malicious: String = "O'Reilly'); DROP TABLE players; --"
	var quoted: String = SQLiteBridge.sql_quote(malicious)
	assert_eq(quoted, "'O''Reilly''); DROP TABLE players; --'", "sql_quote escapes single quotes properly")
	assert_eq(SQLiteBridge.sql_quote("a" + String.chr(0) + "b"), "'ab'", "sql_quote strips NUL bytes")

	var init_res: Dictionary = SQLiteBridge.init_database(TEST_DB_PATH)
	assert_true(_as_bool(init_res.get("ok", false), false), "SQLiteBridge.init_database succeeds: " + str(init_res.get("reason", "")))

	var world_export: Dictionary = {
		"world_meta": {
			"world_id": "world_m5_sql",
			"world_seed": 18401,
			"current_tick_id": 24,
			"current_day_id": 1,
			"season": "SPRING",
			"storyteller_id": "SIMA_QIAN",
			"state_crc32": 987654,
			"updated_at_utc": "tick_24"
		},
		"factions": [
			{
				"faction_id": "fac_wei",
				"name": "Wei's Vanguard",
				"lord_player_id": "lord_a",
				"capital_node_id": "xuchang",
				"royal_rank": "PREFECT",
				"treasury_grain": 5000,
				"treasury_coin": 5000,
				"imperial_edicts": 1,
				"prestige": 100,
				"oathbreaker_until_tick": 0
			}
		],
		"macro_nodes": [
			{
				"node_id": "xuchang",
				"name": "Xuchang",
				"province": "YU_ZHOU",
				"node_tier": "COMMANDERY_CITY",
				"owner_faction_id": "fac_wei",
				"governor_player_id": "lord_a",
				"fortification_hp": 7500,
				"max_fortification_hp": 7500,
				"public_order_bp": 8000,
				"bandit_pressure_bp": 150,
				"tax_rate_bp": 1200,
				"treasury_grain": 1000,
				"treasury_coin": 1200,
				"grain_price_bp": 1000,
				"iron_price_bp": 2000
			}
		],
		"persona_import_challenges": [
			{
				"challenge_id": "7R4M9P",
				"account_id": "acc_lord_a",
				"bound_player_id": "lord_a",
				"nonce": "nonce_7R4M9P_01",
				"session_salt": "salt_1234",
				"cipher_key_hint": "ABCD",
				"issued_at_tick": 1,
				"ttl_expires_tick": 901,
				"consumed_at_tick": 2,
				"status": "CONSUMED",
				"attempt_count": 0,
				"max_attempts": 3,
				"cooldown_until_tick": 0,
				"last_coercion_flag": "R0_CLEAN",
				"last_reject_reason": null
			}
		],
		"players": [
			{
				"player_id": "lord_a",
				"display_name": malicious,
				"auth_token_hash": "hash_a",
				"origin_archetype": "ORIGIN_CHIVALROUS_HERO",
				"creation_mode": "FUSION_INTERVIEW",
				"persona_profile_json": "{\"name\":\"Cao\"}",
				"persona_challenge_id": "7R4M9P",
				"import_audit_status": "VERIFIED_CLEAN",
				"coercion_flag": "R0_CLEAN",
				"role_tier": "LORD",
				"faction_id": "fac_wei",
				"court_rank": "SOVEREIGN",
				"war_merit": 500,
				"host_node_id": "xuchang",
				"manor_id": "manor_lord_a",
				"is_online": 1,
				"last_seen_tick": 24,
				"truce_shield_until_tick": 0,
				"adaptation_factor_bp": 1000
			}
		],
		"manors": [
			{
				"manor_id": "manor_lord_a",
				"player_id": "lord_a",
				"host_node_id": "xuchang",
				"current_lod": 0,
				"grain_stock": 1500,
				"coin_stock": 1000,
				"iron_stock": 250,
				"wood_stock": 400,
				"horse_stock": 20,
				"herbs_wine_stock": 150,
				"weapon_stock": 50,
				"household_troops": 400,
				"vault_protected_bp": 4500,
				"wall_hp": 2000,
				"standing_doctrine_json": "{\"stance\":\"DEFENSIVE_HOLD\"}",
				"grid_zones_json": "[]"
			}
		],
		"pawns_officers": [
			{
				"pawn_id": "lord_a_avatar",
				"owner_player_id": "lord_a",
				"manor_id": "manor_lord_a",
				"name": "Lord A",
				"is_avatar": 1,
				"state": "IN_MANOR",
				"health_state": "HEALTHY",
				"leadership": 72,
				"martial": 70,
				"intelligence": 65,
				"politics": 60,
				"charisma": 68,
				"food_need_bp": 8000,
				"rest_need_bp": 8000,
				"morale_bp": 8200,
				"loyalty_bp": 9000,
				"ambition_bp": 5000,
				"mood": 65,
				"mental_state": "NORMAL",
				"traits_json": "[\"T_CHIVALROUS\",\"T_CAUTIOUS\"]",
				"work_priorities_json": "{\"PATROL\":1}",
				"daily_schedule_json": "[\"WORK\"]"
			}
		],
		"armies_caravans": [
			{
				"entity_id": "army_000001",
				"owner_player_id": "lord_a",
				"faction_id": "fac_wei",
				"unit_type": "ARMY",
				"current_node_id": "xuchang",
				"current_edge_id": "",
				"edge_progress_pm": 0,
				"troop_count": 200,
				"morale_bp": 8000,
				"carried_grain": 100,
				"carried_coin": 50,
				"cargo_json": "{}",
				"doctrine_json": "{}"
			}
		],
		"market_orders": [
			{
				"order_id": "ord_000001",
				"node_id": "xuchang",
				"player_id": "lord_a",
				"commodity": "GRAIN",
				"side": "ASK",
				"price_bp": 1100,
				"quantity": 100,
				"filled_quantity": 0,
				"created_tick": 12,
				"status": "OPEN"
			}
		],
		"command_audit_log": [
			{
				"tick_id": 12,
				"player_id": "lord_a",
				"cmd_type": "CMD_PLACE_MARKET_ORDER",
				"status": "ACCEPTED",
				"reject_reason": null,
				"payload_json": "{\"qty\":100}"
			},
			{
				"tick_id": 13,
				"player_id": "raider_c",
				"cmd_type": "CMD_SET_NODE_POLICY",
				"status": "REJECTED",
				"reject_reason": "ERR_ROLE_PERMISSION:Requires GOVERNOR",
				"payload_json": "{\"node_id\":\"xuchang\"}"
			}
		]
	}

	var sync_res: Dictionary = SQLiteBridge.sync_world_checkpoint(TEST_DB_PATH, world_export)
	assert_true(_as_bool(sync_res.get("ok", false), false), "sync_world_checkpoint succeeds: " + str(sync_res.get("reason", "")))

	var counts_res: Dictionary = SQLiteBridge.query_table_counts(TEST_DB_PATH)
	assert_true(_as_bool(counts_res.get("ok", false), false), "query_table_counts succeeds")
	var counts: Dictionary = _as_dict(counts_res.get("counts", {}))
	assert_eq(counts.size(), 10, "All 10 canonical tables present in counts")
	for tbl: String in SQLiteBridge.CANONICAL_TABLES:
		assert_gte(_as_int(counts.get(tbl, 0), 0), 1, "Table %s populated >= 1 row" % tbl)
	assert_eq(_as_int(counts.get("command_audit_log", 0), 0), 2, "command_audit_log has 2 rows")

	var int_res: Dictionary = SQLiteBridge.verify_integrity(TEST_DB_PATH)
	assert_true(_as_bool(int_res.get("ok", false), false), "verify_integrity passes: " + str(int_res.get("reason", "")))
	assert_true(_as_bool(int_res.get("integrity_ok", false), false), "PRAGMA integrity_check == ok")
	assert_eq(_as_array(int_res.get("foreign_key_violations", [])).size(), 0, "0 foreign_key_check violations")
