class_name WALLogger
extends RefCounted

var _wal_path: String = ""
var _is_open: bool = false


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


static func resolve_path(path: String) -> String:
	if path.is_empty():
		return ""
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.begins_with("/"):
		return path
	return ProjectSettings.globalize_path("res://").path_join(path)


static func _compute_record_crc32(
	tick_id: int,
	cmd_seq: int,
	player_id: String,
	cmd_type: String,
	payload: Dictionary
) -> int:
	var body: Dictionary = {
		"tick_id": tick_id,
		"cmd_seq": cmd_seq,
		"player_id": player_id,
		"cmd_type": cmd_type,
		"payload": payload
	}
	return StateHasher.crc32_dict(body)


func get_wal_path() -> String:
	return _wal_path


func is_open() -> bool:
	return _is_open


func open_wal(wal_path: String) -> Dictionary:
	var resolved: String = resolve_path(wal_path)
	if resolved.is_empty():
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_SCHEMA,
			"reason": "Empty wal_path",
			"wal_path": ""
		}

	var parent_dir: String = resolved.get_base_dir()
	if not parent_dir.is_empty():
		var mk_err: Error = DirAccess.make_dir_recursive_absolute(parent_dir)
		if mk_err != OK:
			return {
				"ok": false,
				"error_code": DtoSchemas.ERR_INVALID_STATE,
				"reason": "Failed to create WAL directory: %s (err=%d)" % [parent_dir, int(mk_err)],
				"wal_path": resolved
			}

	var f: FileAccess = null
	if FileAccess.file_exists(resolved):
		f = FileAccess.open(resolved, FileAccess.READ_WRITE)
	else:
		f = FileAccess.open(resolved, FileAccess.WRITE)

	if f == null:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "Failed to open WAL file: " + resolved,
			"wal_path": resolved
		}
	f.flush()
	f.close()

	_wal_path = resolved
	_is_open = true
	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"reason": "",
		"wal_path": resolved
	}


func append_record(
	tick_id: int,
	cmd_seq: int,
	player_id: String,
	cmd_type: String,
	payload: Dictionary
) -> Dictionary:
	if not _is_open or _wal_path.is_empty():
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "WAL is not open"
		}
	if tick_id < 0 or cmd_seq < 0 or player_id.is_empty() or cmd_type.is_empty():
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_SCHEMA,
			"reason": "Invalid WAL record header fields"
		}
	if not StateHasher.validate_deterministic_types(payload):
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_SCHEMA,
			"reason": "WAL payload contains non-deterministic types (floats or unsupported objects)"
		}

	var payload_copy: Dictionary = payload.duplicate(true)
	var crc32: int = _compute_record_crc32(tick_id, cmd_seq, player_id, cmd_type, payload_copy)
	var record: Dictionary = {
		"tick_id": tick_id,
		"cmd_seq": cmd_seq,
		"player_id": player_id,
		"cmd_type": cmd_type,
		"payload": payload_copy,
		"crc32": crc32
	}
	var line: String = StateHasher.canonical_json(record)

	var f: FileAccess = null
	if FileAccess.file_exists(_wal_path):
		f = FileAccess.open(_wal_path, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(_wal_path, FileAccess.WRITE)

	if f == null:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "Failed to open WAL for append: " + _wal_path
		}

	var ok_write: bool = f.store_string(line + "\n")
	f.flush()
	f.close()

	if not ok_write:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "Failed to write WAL record"
		}

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"record": record,
		"crc32": crc32,
		"wal_path": _wal_path
	}


func read_records(wal_path: String = "", after_tick: int = -1) -> Dictionary:
	var target: String = resolve_path(wal_path) if not wal_path.is_empty() else _wal_path
	if target.is_empty():
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_SCHEMA,
			"reason": "Empty wal_path",
			"records": [],
			"corrupted_count": 0,
			"corrupted_lines": []
		}
	if not FileAccess.file_exists(target):
		return {
			"ok": true,
			"error_code": DtoSchemas.ERR_OK,
			"reason": "",
			"records": [],
			"corrupted_count": 0,
			"corrupted_lines": [],
			"total_lines": 0
		}

	var f: FileAccess = FileAccess.open(target, FileAccess.READ)
	if f == null:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "Failed to open WAL for read: " + target,
			"records": [],
			"corrupted_count": 0,
			"corrupted_lines": []
		}

	var records: Array[Dictionary] = []
	var corrupted_lines: Array[int] = []
	var corrupted_count: int = 0
	var line_no: int = 0

	while not f.eof_reached():
		var raw_line: String = f.get_line()
		var trimmed: String = raw_line.strip_edges()
		if trimmed.is_empty():
			continue
		line_no += 1

		var parsed: Variant = JSON.parse_string(trimmed)
		if parsed == null:
			corrupted_count += 1
			corrupted_lines.append(line_no)
			continue
		var norm: Variant = DtoSchemas.normalize_json_ints(parsed)
		if not (norm is Dictionary):
			corrupted_count += 1
			corrupted_lines.append(line_no)
			continue

		var rec: Dictionary = norm
		if not rec.has("tick_id") or not rec.has("cmd_seq") or not rec.has("player_id") or not rec.has("cmd_type") or not rec.has("payload") or not rec.has("crc32"):
			corrupted_count += 1
			corrupted_lines.append(line_no)
			continue

		var tick_v: Variant = rec["tick_id"]
		var seq_v: Variant = rec["cmd_seq"]
		var pid_v: Variant = rec["player_id"]
		var ctype_v: Variant = rec["cmd_type"]
		var payload_v: Variant = rec["payload"]
		var crc_v: Variant = rec["crc32"]

		if not (tick_v is int) or not (seq_v is int) or not (pid_v is String) or not (ctype_v is String) or not (payload_v is Dictionary) or not (crc_v is int):
			corrupted_count += 1
			corrupted_lines.append(line_no)
			continue

		var tick_id: int = _to_int(tick_v, -1)
		var cmd_seq: int = _to_int(seq_v, -1)
		var player_id: String = str(pid_v)
		var cmd_type: String = str(ctype_v)
		var payload: Dictionary = payload_v
		var stored_crc: int = _to_int(crc_v, -1)

		if tick_id < 0 or cmd_seq < 0 or player_id.is_empty() or cmd_type.is_empty():
			corrupted_count += 1
			corrupted_lines.append(line_no)
			continue

		if not StateHasher.validate_deterministic_types(payload):
			corrupted_count += 1
			corrupted_lines.append(line_no)
			continue

		var expected_crc: int = _compute_record_crc32(tick_id, cmd_seq, player_id, cmd_type, payload)
		if stored_crc != expected_crc:
			corrupted_count += 1
			corrupted_lines.append(line_no)
			continue

		if tick_id > after_tick:
			records.append({
				"tick_id": tick_id,
				"cmd_seq": cmd_seq,
				"player_id": player_id,
				"cmd_type": cmd_type,
				"payload": payload.duplicate(true),
				"crc32": stored_crc
			})

	f.close()
	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"reason": "",
		"records": records,
		"corrupted_count": corrupted_count,
		"corrupted_lines": corrupted_lines,
		"total_lines": line_no
	}


func truncate_wal(wal_path: String = "") -> bool:
	var target: String = resolve_path(wal_path) if not wal_path.is_empty() else _wal_path
	if target.is_empty():
		return false

	var parent_dir: String = target.get_base_dir()
	if not parent_dir.is_empty():
		var mk_err: Error = DirAccess.make_dir_recursive_absolute(parent_dir)
		if mk_err != OK:
			return false

	var f: FileAccess = FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		return false
	var ok_write: bool = f.store_string("")
	f.flush()
	f.close()
	return ok_write
