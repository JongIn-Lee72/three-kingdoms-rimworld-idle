class_name DtoSchemas
extends RefCounted

# Fixed-point scale & game budget constants
const SCALE_PERMILLE: int = 1000
const SCALE_BP: int = 10000
const TOTAL_STAT_BUDGET: int = 320
const STAT_MIN_BASE: int = 35
const STAT_MAX_BASE: int = 85
const STAT_MAX_EFFECTIVE: int = 120
const PASSION_BUDGET: int = 3
const MAX_COMMAND_BYTES: int = 4096
const MANOR_GRID_SIZE: int = 32
const MAX_RETAINERS: int = 12

# Canonical attribute, resource, commodity, trait, and rank domains
const STAT_KEYS: Array[String] = ["LEA", "MAR", "INT", "POL", "CHA"]
const RESOURCE_KEYS: Array[String] = [
	"GRAIN", "COIN", "WOOD", "IRON", "HORSES", "HERBS_WINE", "WEAPONS", "MERIT_PRESTIGE"
]
const MARKET_COMMODITIES: Array[String] = [
	"GRAIN", "IRON", "WOOD", "HORSES", "WEAPONS", "HERBS_WINE"
]
const TRAIT_IDS: Array[String] = [
	"T_CHIVALROUS",
	"T_AMBITIOUS",
	"T_CAUTIOUS",
	"T_DRINKER",
	"T_MYSTIC",
	"T_UNSELFISH",
	"T_GREEDY",
	"T_FIERCE",
	"T_AGRARIAN",
	"T_SCHOLAR"
]
const TRAIT_LIGHT_POOL: Array[int] = [0, 4, 5, 8, 9]
const TRAIT_SHADOW_POOL: Array[int] = [1, 2, 3, 6, 7]
const TRAIT_NONE_SENTINEL: int = 10

const ORIGIN_ARCHETYPES: Array[String] = [
	"ORIGIN_FALLEN_ROYAL",
	"ORIGIN_FRONTIER_OFFICER",
	"ORIGIN_PURE_SCHOLAR",
	"ORIGIN_CHIVALROUS_HERO",
	"ORIGIN_AGRARIAN_GENTRY"
]
const CREATION_MODES: Array[String] = [
	"INTERVIEW_ONLY",
	"FUSION_INTERVIEW",
	"AI_DIRECT_WITH_CONFIRM"
]
const ROLE_TIERS: Array[String] = [
	"FREE_OFFICER",
	"FACTION_OFFICER",
	"GOVERNOR",
	"LORD"
]
const COURT_RANKS: Array[String] = [
	"NONE",
	"RANK_9", "RANK_8", "RANK_7", "RANK_6", "RANK_5",
	"RANK_4", "RANK_3", "RANK_2", "RANK_1", "SOVEREIGN"
]
const ROYAL_RANKS: Array[String] = [
	"PREFECT", "GOVERNOR_GENERAL", "DUKE", "KING", "EMPEROR"
]
const SEASONS: Array[String] = ["SPRING", "SUMMER", "AUTUMN", "WINTER"]
const STORYTELLERS: Array[String] = ["SIMA_QIAN", "DONG_ZHUO", "WEN_JING"]

const COERCION_FLAGS: Array[String] = [
	"R0_CLEAN",
	"R1_MILD_STEERING",
	"R2_STAT_COERCION",
	"R3_PROMPT_INJECTION"
]
const IMPORT_AUDIT_STATUSES: Array[String] = [
	"NONE",
	"VERIFIED_CLEAN",
	"DOWNGRADED_ANOMALY",
	"REJECTED_COERCION",
	"FALLBACK_INTERVIEW"
]
const CHALLENGE_STATUSES: Array[String] = [
	"ISSUED",
	"CONSUMED",
	"EXPIRED",
	"REVOKED_TAMPER"
]

# Network interest channels
const CHAN_GLOBAL_MACRO: String = "CHAN_GLOBAL_MACRO"
const CHAN_FACTION: String = "CHAN_FACTION"
const CHAN_NODE: String = "CHAN_NODE"
const CHAN_MANOR: String = "CHAN_MANOR"
const INTEREST_CHANNELS: Array[String] = [
	CHAN_GLOBAL_MACRO, CHAN_FACTION, CHAN_NODE, CHAN_MANOR
]

# Protocol message types
const MSG_CMD_RECEIPT: String = "MSG_CMD_RECEIPT"
const MSG_TICK_DELTA: String = "MSG_TICK_DELTA"
const MSG_PERSONA_CHALLENGE: String = "MSG_PERSONA_CHALLENGE"
const MSG_OFFLINE_CHRONICLE_DIGEST: String = "MSG_OFFLINE_CHRONICLE_DIGEST"

# 6-Stage CommandValidator error codes
const ERR_OK: String = "OK"
const ERR_SCHEMA: String = "ERR_SCHEMA"
const ERR_UNAUTHORIZED: String = "ERR_UNAUTHORIZED"
const ERR_RATE_LIMITED: String = "ERR_RATE_LIMITED"
const ERR_ROLE_PERMISSION: String = "ERR_ROLE_PERMISSION"
const ERR_INSUFFICIENT_RESOURCE: String = "ERR_INSUFFICIENT_RESOURCE"
const ERR_INVALID_STATE: String = "ERR_INVALID_STATE"

# SealedTokenCodec (TK3K2) canonical 10 error codes
const ERR_PLAINTEXT_JSON_FORBIDDEN: String = "ERR_PLAINTEXT_JSON_FORBIDDEN"
const ERR_TOKEN_FORMAT: String = "ERR_TOKEN_FORMAT"
const ERR_TOKEN_TAMPERED: String = "ERR_TOKEN_TAMPERED"
const ERR_TOKEN_DOMAIN: String = "ERR_TOKEN_DOMAIN"
const ERR_CHALLENGE_UNKNOWN: String = "ERR_CHALLENGE_UNKNOWN"
const ERR_CHALLENGE_OWNERSHIP: String = "ERR_CHALLENGE_OWNERSHIP"
const ERR_CHALLENGE_EXPIRED: String = "ERR_CHALLENGE_EXPIRED"
const ERR_CHALLENGE_REPLAYED: String = "ERR_CHALLENGE_REPLAYED"
const ERR_CHALLENGE_COOLDOWN: String = "ERR_CHALLENGE_COOLDOWN"
const ERR_COERCION_REJECTED: String = "ERR_COERCION_REJECTED"


static func _ok_result() -> Dictionary:
	return {"ok": true, "error_code": ERR_OK, "reason": ""}


static func _err_result(code: String, reason: String) -> Dictionary:
	return {"ok": false, "error_code": code, "reason": reason}


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


# JSON.parse_string() / JSON.parse() in Godot 4 parses JSON numbers as TYPE_FLOAT.
# Wire deserializers should call normalize_json_ints() before passing payloads into validators.
static func normalize_json_ints(value: Variant) -> Variant:
	if value is float:
		var f: float = value
		if is_finite(f) and f == floor(f) and f >= -9007199254740992.0 and f <= 9007199254740992.0:
			return int(f)
		return f
	if value is Array:
		var src_arr: Array = value
		var out_arr: Array = []
		for item: Variant in src_arr:
			out_arr.append(normalize_json_ints(item))
		return out_arr
	if value is Dictionary:
		var src_dict: Dictionary = value
		var out_dict: Dictionary = {}
		for k: Variant in src_dict.keys():
			out_dict[k] = normalize_json_ints(src_dict[k])
		return out_dict
	return value


static func _is_nonempty_string(val: Variant) -> bool:
	if not (val is String):
		return false
	var s: String = val
	return not s.is_empty()


static func _is_int_ge(val: Variant, min_v: int) -> bool:
	if not (val is int):
		return false
	var iv: int = val
	return iv >= min_v


static func validate_command_envelope(env: Dictionary) -> Dictionary:
	var required: Array[String] = ["v", "cmd_seq", "client_tick", "player_id", "cmd_type", "args"]
	for key: String in required:
		if not env.has(key):
			return _err_result(ERR_SCHEMA, "Missing CommandEnvelope key: " + key)
	if not (env["v"] is int) or _to_int(env["v"], -1) != 1:
		return _err_result(ERR_SCHEMA, "CommandEnvelope.v must be integer 1")
	if not _is_int_ge(env["cmd_seq"], 0):
		return _err_result(ERR_SCHEMA, "CommandEnvelope.cmd_seq must be int >= 0")
	if not _is_int_ge(env["client_tick"], 0):
		return _err_result(ERR_SCHEMA, "CommandEnvelope.client_tick must be int >= 0")
	if not _is_nonempty_string(env["player_id"]):
		return _err_result(ERR_SCHEMA, "CommandEnvelope.player_id must be non-empty String")
	if not _is_nonempty_string(env["cmd_type"]):
		return _err_result(ERR_SCHEMA, "CommandEnvelope.cmd_type must be non-empty String")
	if not (env["args"] is Dictionary):
		return _err_result(ERR_SCHEMA, "CommandEnvelope.args must be Dictionary")
	if StateHasher.has_floats(env):
		return _err_result(ERR_SCHEMA, "CommandEnvelope must not contain float values")
	var byte_size: int = StateHasher.canonical_json(env).to_utf8_buffer().size()
	if byte_size > MAX_COMMAND_BYTES:
		return _err_result(ERR_SCHEMA, "CommandEnvelope exceeds MAX_COMMAND_BYTES (4096)")
	return _ok_result()


static func validate_cmd_receipt(msg: Dictionary) -> Dictionary:
	var required: Array[String] = ["v", "msg_type", "cmd_seq", "status", "error_code", "exec_tick_id"]
	for key: String in required:
		if not msg.has(key):
			return _err_result(ERR_SCHEMA, "Missing MSG_CMD_RECEIPT key: " + key)
	if not (msg["v"] is int) or _to_int(msg["v"], -1) != 1:
		return _err_result(ERR_SCHEMA, "MSG_CMD_RECEIPT.v must be integer 1")
	if not (msg["msg_type"] is String) or str(msg["msg_type"]) != MSG_CMD_RECEIPT:
		return _err_result(ERR_SCHEMA, "MSG_CMD_RECEIPT.msg_type mismatch")
	if not _is_int_ge(msg["cmd_seq"], 0):
		return _err_result(ERR_SCHEMA, "MSG_CMD_RECEIPT.cmd_seq must be int >= 0")
	if not (msg["status"] is String):
		return _err_result(ERR_SCHEMA, "MSG_CMD_RECEIPT.status must be String")
	var status: String = str(msg["status"])
	if status != "ACCEPTED" and status != "REJECTED":
		return _err_result(ERR_SCHEMA, "MSG_CMD_RECEIPT.status must be ACCEPTED or REJECTED")
	if not (msg["error_code"] is String):
		return _err_result(ERR_SCHEMA, "MSG_CMD_RECEIPT.error_code must be String")
	var err_code: String = str(msg["error_code"])
	if status == "ACCEPTED" and err_code != "" and err_code != ERR_OK:
		return _err_result(ERR_SCHEMA, "ACCEPTED receipt must have empty or OK error_code")
	if status == "REJECTED" and (err_code.is_empty() or err_code == ERR_OK):
		return _err_result(ERR_SCHEMA, "REJECTED receipt must specify non-OK error_code")
	if not _is_int_ge(msg["exec_tick_id"], 0):
		return _err_result(ERR_SCHEMA, "MSG_CMD_RECEIPT.exec_tick_id must be int >= 0")
	return _ok_result()


static func validate_tick_delta(msg: Dictionary) -> Dictionary:
	var required: Array[String] = [
		"v", "msg_type", "tick_id", "macro_tick_id", "day_id",
		"season", "state_crc32", "channels", "events"
	]
	for key: String in required:
		if not msg.has(key):
			return _err_result(ERR_SCHEMA, "Missing MSG_TICK_DELTA key: " + key)
	if not (msg["v"] is int) or _to_int(msg["v"], -1) != 1:
		return _err_result(ERR_SCHEMA, "MSG_TICK_DELTA.v must be integer 1")
	if not (msg["msg_type"] is String) or str(msg["msg_type"]) != MSG_TICK_DELTA:
		return _err_result(ERR_SCHEMA, "MSG_TICK_DELTA.msg_type mismatch")
	for int_key: String in ["tick_id", "macro_tick_id", "day_id", "state_crc32"]:
		if not _is_int_ge(msg[int_key], 0):
			return _err_result(ERR_SCHEMA, "MSG_TICK_DELTA." + int_key + " must be int >= 0")
	if not (msg["season"] is String) or not SEASONS.has(str(msg["season"])):
		return _err_result(ERR_SCHEMA, "MSG_TICK_DELTA.season invalid")
	if not (msg["channels"] is Dictionary):
		return _err_result(ERR_SCHEMA, "MSG_TICK_DELTA.channels must be Dictionary")
	if not (msg["events"] is Array):
		return _err_result(ERR_SCHEMA, "MSG_TICK_DELTA.events must be Array")
	return _ok_result()


static func validate_persona_challenge(msg: Dictionary) -> Dictionary:
	var required: Array[String] = [
		"v", "msg_type", "challenge_id", "issued_at_tick",
		"ttl_expires_tick", "codebook", "init_s1", "init_s2", "prompt_text"
	]
	for key: String in required:
		if not msg.has(key):
			return _err_result(ERR_SCHEMA, "Missing MSG_PERSONA_CHALLENGE key: " + key)
	if not (msg["v"] is int) or _to_int(msg["v"], -1) != 1:
		return _err_result(ERR_SCHEMA, "MSG_PERSONA_CHALLENGE.v must be integer 1")
	if not (msg["msg_type"] is String) or str(msg["msg_type"]) != MSG_PERSONA_CHALLENGE:
		return _err_result(ERR_SCHEMA, "MSG_PERSONA_CHALLENGE.msg_type mismatch")
	var cid_v: Variant = msg["challenge_id"]
	if not (cid_v is String):
		return _err_result(ERR_SCHEMA, "MSG_PERSONA_CHALLENGE.challenge_id must be 6-char String")
	var cid_s: String = cid_v
	if cid_s.length() != 6:
		return _err_result(ERR_SCHEMA, "MSG_PERSONA_CHALLENGE.challenge_id must be 6-char String")
	if not _is_int_ge(msg["issued_at_tick"], 0):
		return _err_result(ERR_SCHEMA, "MSG_PERSONA_CHALLENGE.issued_at_tick must be int >= 0")
	if not (msg["ttl_expires_tick"] is int) or _to_int(msg["ttl_expires_tick"], -1) <= _to_int(msg["issued_at_tick"], 0):
		return _err_result(ERR_SCHEMA, "MSG_PERSONA_CHALLENGE.ttl_expires_tick must be > issued_at_tick")
	var cb_v: Variant = msg["codebook"]
	if not (cb_v is Array):
		return _err_result(ERR_SCHEMA, "MSG_PERSONA_CHALLENGE.codebook must be Array")
	var cb: Array = cb_v
	if cb.size() != 31:
		return _err_result(ERR_SCHEMA, "MSG_PERSONA_CHALLENGE.codebook must have length 31")
	var seen: Dictionary = {}
	for ch_var: Variant in cb:
		if not (ch_var is String):
			return _err_result(ERR_SCHEMA, "MSG_PERSONA_CHALLENGE.codebook entries must be String")
		var ch: String = str(ch_var)
		if ch.length() != 1 or seen.has(ch):
			return _err_result(ERR_SCHEMA, "MSG_PERSONA_CHALLENGE.codebook must have 31 unique single chars")
		seen[ch] = true
	for s_key: String in ["init_s1", "init_s2"]:
		var sv: Variant = msg[s_key]
		var si: int = _to_int(sv, -1)
		if not (sv is int) or si < 0 or si > 30:
			return _err_result(ERR_SCHEMA, "MSG_PERSONA_CHALLENGE." + s_key + " must be in 0..30")
	if not _is_nonempty_string(msg["prompt_text"]):
		return _err_result(ERR_SCHEMA, "MSG_PERSONA_CHALLENGE.prompt_text must be non-empty String")
	return _ok_result()


static func validate_offline_chronicle_digest(msg: Dictionary) -> Dictionary:
	var required: Array[String] = [
		"v", "msg_type", "player_id", "from_tick", "to_tick",
		"net_yields", "stipends_received", "completed_missions",
		"pawn_events", "battle_replays"
	]
	for key: String in required:
		if not msg.has(key):
			return _err_result(ERR_SCHEMA, "Missing MSG_OFFLINE_CHRONICLE_DIGEST key: " + key)
	if not (msg["v"] is int) or _to_int(msg["v"], -1) != 1:
		return _err_result(ERR_SCHEMA, "MSG_OFFLINE_CHRONICLE_DIGEST.v must be integer 1")
	if not (msg["msg_type"] is String) or str(msg["msg_type"]) != MSG_OFFLINE_CHRONICLE_DIGEST:
		return _err_result(ERR_SCHEMA, "MSG_OFFLINE_CHRONICLE_DIGEST.msg_type mismatch")
	if not _is_nonempty_string(msg["player_id"]):
		return _err_result(ERR_SCHEMA, "MSG_OFFLINE_CHRONICLE_DIGEST.player_id must be non-empty String")
	if not _is_int_ge(msg["from_tick"], 0):
		return _err_result(ERR_SCHEMA, "MSG_OFFLINE_CHRONICLE_DIGEST.from_tick must be int >= 0")
	if not (msg["to_tick"] is int) or _to_int(msg["to_tick"], -1) < _to_int(msg["from_tick"], 0):
		return _err_result(ERR_SCHEMA, "MSG_OFFLINE_CHRONICLE_DIGEST.to_tick must be >= from_tick")
	for dict_key: String in ["net_yields", "stipends_received"]:
		if not (msg[dict_key] is Dictionary):
			return _err_result(ERR_SCHEMA, "MSG_OFFLINE_CHRONICLE_DIGEST." + dict_key + " must be Dictionary")
	for arr_key: String in ["completed_missions", "pawn_events", "battle_replays"]:
		if not (msg[arr_key] is Array):
			return _err_result(ERR_SCHEMA, "MSG_OFFLINE_CHRONICLE_DIGEST." + arr_key + " must be Array")
	return _ok_result()
