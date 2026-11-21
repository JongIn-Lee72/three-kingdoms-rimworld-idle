extends SceneTree

const CORE_REQUIRED_FILES: Array[String] = [
	"res://data/schemas/world_state_schema.sql",
	"res://data/persona_seal_rules.json",
	"res://data/assets_manifest.json"
]

const OPTIONAL_FUTURE_FILES: Array[String] = [
	"res://data/macro_map_3k.json",
	"res://data/officers_catalog.json",
	"res://data/interview_questions.json",
	"res://data/items_buildings.json",
	"res://data/storytellers.json"
]


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


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var strict_mode: bool = false
	var require_all: bool = false
	for arg: String in args:
		if arg == "--strict":
			strict_mode = true
		elif arg == "--require-all":
			require_all = true
			strict_mode = true

	var errors: Array[String] = []
	var checked_json: Array[String] = []

	var json_files: Array[String] = []
	_collect_json_files("res://data", json_files)
	json_files.sort()

	for path: String in json_files:
		var parsed: Variant = _load_and_parse_json(path, errors)
		if parsed != null:
			checked_json.append(path)

	if strict_mode:
		for req_path: String in CORE_REQUIRED_FILES:
			if not FileAccess.file_exists(req_path):
				errors.append("Missing required core data file: " + req_path)

		_validate_sql_schema("res://data/schemas/world_state_schema.sql", errors)
		_validate_persona_seal_rules("res://data/persona_seal_rules.json", errors)
		_validate_assets_manifest("res://data/assets_manifest.json", errors)

		for opt_path: String in OPTIONAL_FUTURE_FILES:
			if FileAccess.file_exists(opt_path):
				_validate_optional_file(opt_path, errors)
			elif require_all:
				errors.append("Missing required milestone data file (--require-all): " + opt_path)

	if not errors.is_empty():
		for err_msg: String in errors:
			printerr("[validate_data] ERROR: " + err_msg)
		quit(1)
		return

	print("[validate_data] OK: Validated %d JSON file(s) and SQL schema (strict=%s, require_all=%s)." % [
		checked_json.size(), str(strict_mode), str(require_all)
	])
	quit(0)


func _collect_json_files(dir_path: String, out_files: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	var _err: Error = dir.list_dir_begin()
	while true:
		var name: String = dir.get_next()
		if name.is_empty():
			break
		if name.begins_with("."):
			continue
		var full_path: String = dir_path.path_join(name)
		if dir.current_is_dir():
			_collect_json_files(full_path, out_files)
		elif name.ends_with(".json"):
			out_files.append(full_path)
	dir.list_dir_end()


func _load_and_parse_json(path: String, errors: Array[String]) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("JSON file does not exist: " + path)
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Failed to open JSON file: " + path)
		return null
	var content: String = file.get_as_text()
	file.close()
	if content.strip_edges().is_empty():
		errors.append("Empty JSON file: " + path)
		return null
	var parser: JSON = JSON.new()
	var err: Error = parser.parse(content)
	if err != OK:
		errors.append("JSON parse error in %s at line %d: %s" % [
			path, parser.get_error_line(), parser.get_error_message()
		])
		return null
	return parser.data


func _validate_sql_schema(path: String, errors: Array[String]) -> void:
	if not FileAccess.file_exists(path):
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Cannot open SQL schema: " + path)
		return
	var sql: String = file.get_as_text()
	file.close()
	var required_tables: Array[String] = [
		"world_meta", "factions", "macro_nodes", "persona_import_challenges",
		"players", "manors", "pawns_officers", "armies_caravans",
		"market_orders", "command_audit_log"
	]
	for tbl: String in required_tables:
		if not sql.contains("CREATE TABLE IF NOT EXISTS " + tbl):
			errors.append("SQL schema missing table DDL: " + tbl)
	if not sql.contains("PRAGMA foreign_keys = ON;"):
		errors.append("SQL schema missing PRAGMA foreign_keys = ON;")


func _validate_persona_seal_rules(path: String, errors: Array[String]) -> void:
	var parsed: Variant = _load_and_parse_json(path, errors)
	if not (parsed is Dictionary):
		errors.append("persona_seal_rules.json root must be a JSON Object")
		return
	var rules: Dictionary = parsed

	if str(rules.get("schema_version", "")) != "AI_PERSONA_TOKEN_V2":
		errors.append("persona_seal_rules.json schema_version must be AI_PERSONA_TOKEN_V2")
	if str(rules.get("token_prefix", "")) != "TK3K2":
		errors.append("persona_seal_rules.json token_prefix must be TK3K2")

	var alphabet: String = str(rules.get("alphabet_31", ""))
	if alphabet.length() != 31:
		errors.append("persona_seal_rules.json alphabet_31 must have length 31")
	else:
		var seen_chars: Dictionary = {}
		for i: int in range(alphabet.length()):
			var ch: String = alphabet.substr(i, 1)
			if seen_chars.has(ch):
				errors.append("persona_seal_rules.json alphabet_31 has duplicate character: " + ch)
			seen_chars[ch] = true

	if _to_int(rules.get("max_raw_input_bytes", 0), 0) != 4096:
		errors.append("persona_seal_rules.json max_raw_input_bytes must be 4096")

	var cp_var: Variant = rules.get("challenge_policy", null)
	if not (cp_var is Dictionary):
		errors.append("persona_seal_rules.json missing challenge_policy object")
	else:
		var cp: Dictionary = cp_var
		if _to_int(cp.get("ttl_ticks", 0), 0) != 900:
			errors.append("challenge_policy.ttl_ticks must be 900")
		if _to_int(cp.get("max_attempts", 0), 0) != 3:
			errors.append("challenge_policy.max_attempts must be 3")
		if _to_int(cp.get("r3_cooldown_ticks", 0), 0) != 1800:
			errors.append("challenge_policy.r3_cooldown_ticks must be 1800")

	var sb_var: Variant = rules.get("stat_budget", null)
	if not (sb_var is Dictionary):
		errors.append("persona_seal_rules.json missing stat_budget object")
	else:
		var sb: Dictionary = sb_var
		if _to_int(sb.get("total_budget", 0), 0) != 320:
			errors.append("stat_budget.total_budget must be 320")
		if _to_int(sb.get("min_stat", 0), 0) != 35:
			errors.append("stat_budget.min_stat must be 35")
		if _to_int(sb.get("max_stat", 0), 0) != 85:
			errors.append("stat_budget.max_stat must be 85")
		if _to_int(sb.get("passion_budget", 0), 0) != 3:
			errors.append("stat_budget.passion_budget must be 3")

	var traits_var: Variant = rules.get("traits", null)
	if not (traits_var is Array):
		errors.append("persona_seal_rules.json missing traits array")
	else:
		var traits: Array = traits_var
		if traits.size() != 10:
			errors.append("persona_seal_rules.json traits must contain exactly 10 entries")
		var light_count: int = 0
		var shadow_count: int = 0
		var seen_ids: Dictionary = {}
		for idx: int in range(traits.size()):
			var entry_var: Variant = traits[idx]
			if not (entry_var is Dictionary):
				errors.append("traits[%d] must be Object" % idx)
				continue
			var entry: Dictionary = entry_var
			var tid: String = str(entry.get("id", ""))
			if tid.is_empty() or seen_ids.has(tid):
				errors.append("Duplicate or empty trait id at index %d" % idx)
			seen_ids[tid] = true
			if _to_int(entry.get("index", -1), -1) != idx:
				errors.append("traits[%d].index mismatch" % idx)
			var pol: String = str(entry.get("polarity", ""))
			var cost: int = _to_int(entry.get("cost", 0), 0)
			if pol == "LIGHT" and cost == 1:
				light_count += 1
			elif pol == "SHADOW" and cost == -1:
				shadow_count += 1
			else:
				errors.append("traits[%d] invalid polarity/cost pair" % idx)
		if light_count != 5 or shadow_count != 5:
			errors.append("persona_seal_rules.json traits must partition into 5 LIGHT (+1) and 5 SHADOW (-1)")

	var sd_var: Variant = rules.get("slot_domains", null)
	if not (sd_var is Dictionary):
		errors.append("persona_seal_rules.json missing slot_domains")
	else:
		var sd: Dictionary = sd_var
		if not sd.has("risk_flags"):
			errors.append("slot_domains missing risk_flags (R0..R3)")
		else:
			var rf_var: Variant = sd["risk_flags"]
			if rf_var is Dictionary:
				var rf: Dictionary = rf_var
				var labels_var: Variant = rf.get("labels", [])
				if not (labels_var is Array):
					errors.append("slot_domains.risk_flags.labels must be Array")
				else:
					var labels: Array = labels_var
					if labels.size() != 4:
						errors.append("slot_domains.risk_flags.labels must have 4 entries (R0..R3)")

	var err_codes_var: Variant = rules.get("error_codes", null)
	if not (err_codes_var is Array):
		errors.append("persona_seal_rules.json error_codes must be Array")
	else:
		var err_codes: Array = err_codes_var
		if err_codes.size() != 10:
			errors.append("persona_seal_rules.json error_codes must contain all 10 TK3K2 error codes")


func _validate_optional_file(path: String, errors: Array[String]) -> void:
	var parsed: Variant = _load_and_parse_json(path, errors)
	if parsed == null:
		return
	if path.ends_with("macro_map_3k.json"):
		if not (parsed is Dictionary):
			errors.append("macro_map_3k.json must be Object")
		else:
			var mm: Dictionary = parsed
			if not mm.has("nodes") or not mm.has("edges"):
				errors.append("macro_map_3k.json must contain 'nodes' and 'edges'")
	elif path.ends_with("officers_catalog.json"):
		if not (parsed is Dictionary) and not (parsed is Array):
			errors.append("officers_catalog.json must be Object or Array")
	elif path.ends_with("interview_questions.json"):
		if not (parsed is Dictionary) and not (parsed is Array):
			errors.append("interview_questions.json must be Object or Array")
	elif path.ends_with("items_buildings.json"):
		if not (parsed is Dictionary):
			errors.append("items_buildings.json must be Object")
	elif path.ends_with("storytellers.json"):
		if not (parsed is Dictionary) and not (parsed is Array):
			errors.append("storytellers.json must be Object or Array")


func _validate_assets_manifest(path: String, errors: Array[String]) -> void:
	var parsed: Variant = _load_and_parse_json(path, errors)
	if not (parsed is Dictionary):
		errors.append("assets_manifest.json root must be a JSON Object")
		return
	var manifest: Dictionary = parsed

	if str(manifest.get("schema_version", "")) != "ASSETS_MANIFEST_V1":
		errors.append("assets_manifest.json schema_version must be ASSETS_MANIFEST_V1")

	var allowed_licenses: Array[String] = ["CC0-1.0", "Original-Project-CC0"]
	var assets_var: Variant = manifest.get("assets", null)
	if not (assets_var is Array):
		errors.append("assets_manifest.json missing assets array")
	else:
		var assets: Array = assets_var
		if assets.is_empty():
			errors.append("assets_manifest.json assets array must not be empty")
		for idx: int in range(assets.size()):
			var entry_var: Variant = assets[idx]
			if not (entry_var is Dictionary):
				errors.append("assets_manifest.json assets[%d] must be Object" % idx)
				continue
			var entry: Dictionary = entry_var
			var asset_path: String = str(entry.get("path", ""))
			if asset_path.is_empty():
				errors.append("assets_manifest.json assets[%d] missing path" % idx)
			elif not FileAccess.file_exists(asset_path):
				errors.append("assets_manifest.json missing asset file on disk: " + asset_path)
			var byte_count: int = _to_int(entry.get("bytes", 0), 0)
			if byte_count <= 0:
				errors.append("assets_manifest.json assets[%d] bytes must be > 0 (%s)" % [idx, asset_path])
			var license_str: String = str(entry.get("license", ""))
			if not allowed_licenses.has(license_str):
				errors.append("assets_manifest.json assets[%d] invalid license '%s' (%s)" % [idx, license_str, asset_path])

	var sfx_var: Variant = manifest.get("sfx_event_map", null)
	if not (sfx_var is Dictionary):
		errors.append("assets_manifest.json missing sfx_event_map object")
	else:
		var sfx_map: Dictionary = sfx_var
		if sfx_map.is_empty():
			errors.append("assets_manifest.json sfx_event_map must not be empty")
		for event_key_v: Variant in sfx_map.keys():
			var event_key: String = str(event_key_v)
			var sfx_path: String = str(sfx_map[event_key_v])
			if sfx_path.is_empty() or not FileAccess.file_exists(sfx_path):
				errors.append("assets_manifest.json sfx_event_map[%s] missing file on disk: %s" % [event_key, sfx_path])

	var bgm_var: Variant = manifest.get("bgm_tracks", null)
	if not (bgm_var is Dictionary):
		errors.append("assets_manifest.json missing bgm_tracks object")
	else:
		var bgm_map: Dictionary = bgm_var
		if bgm_map.is_empty():
			errors.append("assets_manifest.json bgm_tracks must not be empty")
		for track_key_v: Variant in bgm_map.keys():
			var track_key: String = str(track_key_v)
			var bgm_path: String = str(bgm_map[track_key_v])
			if bgm_path.is_empty() or not FileAccess.file_exists(bgm_path):
				errors.append("assets_manifest.json bgm_tracks[%s] missing file on disk: %s" % [track_key, bgm_path])

