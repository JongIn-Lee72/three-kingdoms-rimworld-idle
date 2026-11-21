class_name SnapshotSerializer
extends RefCounted


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


static func resolve_path(path: String) -> String:
	return WALLogger.resolve_path(path)


static func _extract_snapshot_tick_id(world_state: Dictionary) -> int:
	if world_state.has("current_tick_id"):
		return maxi(0, _to_int(world_state.get("current_tick_id", 0), 0))
	if world_state.has("tick_id"):
		return maxi(0, _to_int(world_state.get("tick_id", 0), 0))
	var clock_v: Variant = world_state.get("clock", null)
	if clock_v is Dictionary:
		var clock_d: Dictionary = clock_v
		return maxi(0, _to_int(clock_d.get("current_tick_id", 0), 0))
	var meta_v: Variant = world_state.get("world_meta", null)
	if meta_v is Dictionary:
		var meta_d: Dictionary = meta_v
		return maxi(0, _to_int(meta_d.get("current_tick_id", 0), 0))
	return 0


static func save_atomic_snapshot(snapshot_path: String, world_state: Dictionary) -> Dictionary:
	var resolved: String = resolve_path(snapshot_path)
	if resolved.is_empty():
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_SCHEMA,
			"reason": "Empty snapshot_path"
		}
	if not StateHasher.validate_deterministic_types(world_state):
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_SCHEMA,
			"reason": "world_state contains non-deterministic types"
		}

	var parent_dir: String = resolved.get_base_dir()
	if not parent_dir.is_empty():
		var mk_err: Error = DirAccess.make_dir_recursive_absolute(parent_dir)
		if mk_err != OK:
			return {
				"ok": false,
				"error_code": DtoSchemas.ERR_INVALID_STATE,
				"reason": "Failed to create snapshot directory: %s (err=%d)" % [parent_dir, int(mk_err)]
			}

	var clean_state: Dictionary = world_state.duplicate(true)
	var state_crc32: int = StateHasher.crc32_dict(clean_state)
	var state_sha256: String = StateHasher.sha256_dict(clean_state)
	var snap_tick: int = _extract_snapshot_tick_id(clean_state)

	var envelope: Dictionary = {
		"schema_version": "1.0",
		"snapshot_tick_id": snap_tick,
		"state_crc32": state_crc32,
		"state_sha256": state_sha256,
		"world_state": clean_state
	}
	var json_text: String = StateHasher.canonical_json(envelope) + "\n"

	var tmp_path: String = resolved + ".tmp"
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "Failed to open temporary snapshot file: " + tmp_path
		}
	var ok_write: bool = f.store_string(json_text)
	f.flush()
	f.close()
	if not ok_write:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "Failed to write temporary snapshot file: " + tmp_path
		}

	var ren_err: Error = DirAccess.rename_absolute(tmp_path, resolved)
	if ren_err != OK:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "Atomic rename failed (%s -> %s, err=%d)" % [tmp_path, resolved, int(ren_err)]
		}

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"reason": "",
		"snapshot_path": resolved,
		"snapshot_tick_id": snap_tick,
		"state_crc32": state_crc32,
		"state_sha256": state_sha256
	}


static func load_snapshot(snapshot_path: String) -> Dictionary:
	var resolved: String = resolve_path(snapshot_path)
	if resolved.is_empty():
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_SCHEMA,
			"reason": "Empty snapshot_path",
			"world_state": {},
			"state_crc32": 0,
			"state_sha256": ""
		}
	if not FileAccess.file_exists(resolved):
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "Snapshot file does not exist: " + resolved,
			"world_state": {},
			"state_crc32": 0,
			"state_sha256": ""
		}

	var f: FileAccess = FileAccess.open(resolved, FileAccess.READ)
	if f == null:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "Failed to open snapshot file: " + resolved,
			"world_state": {},
			"state_crc32": 0,
			"state_sha256": ""
		}
	var txt: String = f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_SCHEMA,
			"reason": "Corrupted snapshot JSON",
			"world_state": {},
			"state_crc32": 0,
			"state_sha256": ""
		}
	var norm: Variant = DtoSchemas.normalize_json_ints(parsed)
	if not (norm is Dictionary):
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_SCHEMA,
			"reason": "Snapshot root must be Dictionary",
			"world_state": {},
			"state_crc32": 0,
			"state_sha256": ""
		}

	var env: Dictionary = norm
	if not env.has("world_state") or not env.has("state_crc32") or not env.has("state_sha256"):
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_SCHEMA,
			"reason": "Snapshot envelope missing required integrity fields",
			"world_state": {},
			"state_crc32": 0,
			"state_sha256": ""
		}

	var ws_v: Variant = env["world_state"]
	var crc_v: Variant = env["state_crc32"]
	var sha_v: Variant = env["state_sha256"]
	if not (ws_v is Dictionary) or not (crc_v is int) or not (sha_v is String):
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_SCHEMA,
			"reason": "Snapshot envelope field types invalid",
			"world_state": {},
			"state_crc32": 0,
			"state_sha256": ""
		}

	var world_state: Dictionary = ws_v
	var stored_crc: int = _to_int(crc_v, -1)
	var stored_sha: String = str(sha_v)

	if not StateHasher.validate_deterministic_types(world_state):
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_SCHEMA,
			"reason": "Snapshot world_state contains non-deterministic types",
			"world_state": {},
			"state_crc32": 0,
			"state_sha256": ""
		}

	var actual_crc: int = StateHasher.crc32_dict(world_state)
	var actual_sha: String = StateHasher.sha256_dict(world_state)
	if stored_crc != actual_crc or stored_sha != actual_sha:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_TOKEN_TAMPERED,
			"reason": "Snapshot integrity mismatch (CRC32/SHA-256 verification failed)",
			"world_state": {},
			"state_crc32": actual_crc,
			"state_sha256": actual_sha
		}

	var snap_tick: int = _to_int(env.get("snapshot_tick_id", _extract_snapshot_tick_id(world_state)), 0)
	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"reason": "",
		"snapshot_tick_id": snap_tick,
		"world_state": world_state,
		"state_crc32": actual_crc,
		"state_sha256": actual_sha
	}


static func load_for_crash_recovery(
	snapshot_path: String,
	wal_path: String,
	wal_logger: WALLogger = null
) -> Dictionary:
	var has_snapshot: bool = FileAccess.file_exists(resolve_path(snapshot_path))
	var world_state: Dictionary = {}
	var snap_tick_id: int = -1
	var snap_crc: int = 0
	var snap_sha: String = ""

	if has_snapshot:
		var snap_res: Dictionary = load_snapshot(snapshot_path)
		if not _to_bool(snap_res.get("ok", false), false):
			return {
				"ok": false,
				"error_code": str(snap_res.get("error_code", DtoSchemas.ERR_INVALID_STATE)),
				"reason": str(snap_res.get("reason", "Failed to load snapshot")),
				"snapshot_tick_id": -1,
				"world_state": {},
				"replay_records": [],
				"corrupted_wal_count": 0
			}
		var ws_v: Variant = snap_res.get("world_state", {})
		if ws_v is Dictionary:
			world_state = ws_v
		snap_tick_id = _to_int(snap_res.get("snapshot_tick_id", _extract_snapshot_tick_id(world_state)), 0)
		snap_crc = _to_int(snap_res.get("state_crc32", 0), 0)
		snap_sha = str(snap_res.get("state_sha256", ""))

	var reader: WALLogger = wal_logger if wal_logger != null else WALLogger.new()
	var wal_res: Dictionary = reader.read_records(wal_path, snap_tick_id)
	if not _to_bool(wal_res.get("ok", false), false):
		return {
			"ok": false,
			"error_code": str(wal_res.get("error_code", DtoSchemas.ERR_INVALID_STATE)),
			"reason": str(wal_res.get("reason", "Failed to read WAL")),
			"snapshot_tick_id": snap_tick_id,
			"world_state": world_state,
			"replay_records": [],
			"corrupted_wal_count": _to_int(wal_res.get("corrupted_count", 0), 0)
		}

	var replay_records: Array[Dictionary] = []
	var rec_v: Variant = wal_res.get("records", [])
	if rec_v is Array:
		var rec_arr: Array = rec_v
		for item: Variant in rec_arr:
			if item is Dictionary:
				var d: Dictionary = item
				replay_records.append(d)

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"reason": "",
		"has_snapshot": has_snapshot,
		"snapshot_tick_id": snap_tick_id,
		"state_crc32": snap_crc,
		"state_sha256": snap_sha,
		"world_state": world_state,
		"replay_records": replay_records,
		"corrupted_wal_count": _to_int(wal_res.get("corrupted_count", 0), 0),
		"corrupted_wal_lines": wal_res.get("corrupted_lines", [])
	}
