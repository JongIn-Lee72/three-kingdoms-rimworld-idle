class_name TestDtoSchemas
extends HarnessTestCase


func _as_bool(v: Variant, fallback: bool = false) -> bool:
	if v is bool:
		var bv: bool = v
		return bv
	return fallback


func _make_valid_codebook() -> Array[String]:
	var out: Array[String] = []
	var a31: String = "0123456789ABCDEFGHJKMNPQRSTVWXY"
	for i: int in range(a31.length()):
		out.append(a31.substr(i, 1))
	return out


func test_canonical_enum_and_constant_counts() -> void:
	assert_eq(DtoSchemas.RESOURCE_KEYS.size(), 8, "Must have 8 canonical resources")
	assert_eq(DtoSchemas.STAT_KEYS.size(), 5, "Must have 5 canonical stats")
	assert_eq(DtoSchemas.TRAIT_IDS.size(), 10, "Must have 10 canonical traits")
	assert_eq(DtoSchemas.TRAIT_LIGHT_POOL.size(), 5, "Must have 5 Light traits")
	assert_eq(DtoSchemas.TRAIT_SHADOW_POOL.size(), 5, "Must have 5 Shadow traits")
	assert_eq(DtoSchemas.TRAIT_NONE_SENTINEL, 10, "TRAIT_NONE_SENTINEL must be 10")
	assert_eq(DtoSchemas.ORIGIN_ARCHETYPES.size(), 5, "Must have 5 origin archetypes")
	assert_eq(DtoSchemas.CREATION_MODES.size(), 3, "Must have 3 creation modes")
	assert_eq(DtoSchemas.MARKET_COMMODITIES.size(), 6, "Must have 6 market commodities")
	assert_eq(DtoSchemas.ROLE_TIERS.size(), 4, "Must have 4 role tiers")
	assert_eq(DtoSchemas.COURT_RANKS.size(), 11, "Must have 11 court ranks")
	assert_eq(DtoSchemas.ROYAL_RANKS.size(), 5, "Must have 5 royal ranks")
	assert_eq(DtoSchemas.SEASONS.size(), 4, "Must have 4 seasons")
	assert_eq(DtoSchemas.STORYTELLERS.size(), 3, "Must have 3 storytellers")
	assert_eq(DtoSchemas.COERCION_FLAGS.size(), 4, "Must have 4 coercion flags")
	assert_eq(DtoSchemas.IMPORT_AUDIT_STATUSES.size(), 5, "Must have 5 import audit statuses")
	assert_eq(DtoSchemas.CHALLENGE_STATUSES.size(), 4, "Must have 4 challenge statuses")
	assert_eq(DtoSchemas.INTEREST_CHANNELS.size(), 4, "Must have 4 interest channels")

	# Verify Light + Shadow pools partition 0..9 cleanly without overlap
	var union_pool: Array[int] = []
	for idx: int in DtoSchemas.TRAIT_LIGHT_POOL:
		assert_false(DtoSchemas.TRAIT_SHADOW_POOL.has(idx), "Light and Shadow pools must be disjoint")
		union_pool.append(idx)
	for idx: int in DtoSchemas.TRAIT_SHADOW_POOL:
		union_pool.append(idx)
	union_pool.sort()
	assert_eq(union_pool, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "Light + Shadow pools must partition 0..9")

	# Verify all 10 canonical TK3K2 error codes exist and are distinct
	var tk3k2_codes: Array[String] = [
		DtoSchemas.ERR_PLAINTEXT_JSON_FORBIDDEN,
		DtoSchemas.ERR_TOKEN_FORMAT,
		DtoSchemas.ERR_TOKEN_TAMPERED,
		DtoSchemas.ERR_TOKEN_DOMAIN,
		DtoSchemas.ERR_CHALLENGE_UNKNOWN,
		DtoSchemas.ERR_CHALLENGE_OWNERSHIP,
		DtoSchemas.ERR_CHALLENGE_EXPIRED,
		DtoSchemas.ERR_CHALLENGE_REPLAYED,
		DtoSchemas.ERR_CHALLENGE_COOLDOWN,
		DtoSchemas.ERR_COERCION_REJECTED
	]
	var seen_codes: Dictionary = {}
	for c: String in tk3k2_codes:
		assert_false(c.is_empty(), "Error code must be non-empty")
		seen_codes[c] = true
	assert_eq(seen_codes.size(), 10, "All 10 TK3K2 error codes must be unique")


func test_normalize_json_ints() -> void:
	var parsed: Variant = JSON.parse_string("{\"tick\": 42, \"nested\": [1, 2, {\"seq\": 99}], \"frac\": 3.25, \"flag\": true, \"nil\": null}")
	var normalized_v: Variant = DtoSchemas.normalize_json_ints(parsed)
	assert_true(normalized_v is Dictionary, "Normalized JSON root is Dictionary")
	if normalized_v is Dictionary:
		var norm: Dictionary = normalized_v
		assert_eq(typeof(norm.get("tick")), TYPE_INT, "JSON integer 42 normalized from float to TYPE_INT")
		assert_eq(norm.get("tick"), 42, "Normalized tick equals 42")
		assert_eq(typeof(norm.get("frac")), TYPE_FLOAT, "Fractional float 3.25 preserved as TYPE_FLOAT")
		assert_eq(typeof(norm.get("flag")), TYPE_BOOL, "Bool preserved")
		assert_eq(typeof(norm.get("nil")), TYPE_NIL, "Null preserved")
		var nested_v: Variant = norm.get("nested")
		assert_true(nested_v is Array, "Nested array preserved")
		if nested_v is Array:
			var nested: Array = nested_v
			assert_eq(typeof(nested[0]), TYPE_INT, "Array element normalized to TYPE_INT")
			var inner_v: Variant = nested[2]
			if inner_v is Dictionary:
				var inner: Dictionary = inner_v
				assert_eq(typeof(inner.get("seq")), TYPE_INT, "Deeply nested seq normalized to TYPE_INT")


func test_validate_command_envelope() -> void:
	var valid_env: Dictionary = {
		"v": 1,
		"cmd_seq": 0,
		"client_tick": 12,
		"player_id": "lord_A",
		"cmd_type": "CMD_SET_PRIORITY",
		"args": {"pawn_id": 1, "job": "FARM", "priority": 1}
	}
	var res_ok: Dictionary = DtoSchemas.validate_command_envelope(valid_env)
	assert_true(_as_bool(res_ok.get("ok", false)), "Valid CommandEnvelope passes")
	assert_eq(res_ok.get("error_code", ""), DtoSchemas.ERR_OK, "Valid CommandEnvelope error_code == OK")

	var bad_v: Dictionary = valid_env.duplicate(true)
	bad_v["v"] = 2
	assert_eq(DtoSchemas.validate_command_envelope(bad_v).get("error_code", ""), DtoSchemas.ERR_SCHEMA, "v != 1 fails")

	var missing: Dictionary = valid_env.duplicate(true)
	var _er: bool = missing.erase("args")
	assert_eq(DtoSchemas.validate_command_envelope(missing).get("error_code", ""), DtoSchemas.ERR_SCHEMA, "Missing args fails")

	var neg_seq: Dictionary = valid_env.duplicate(true)
	neg_seq["cmd_seq"] = -1
	assert_eq(DtoSchemas.validate_command_envelope(neg_seq).get("error_code", ""), DtoSchemas.ERR_SCHEMA, "Negative cmd_seq fails")

	var empty_pid: Dictionary = valid_env.duplicate(true)
	empty_pid["player_id"] = ""
	assert_eq(DtoSchemas.validate_command_envelope(empty_pid).get("error_code", ""), DtoSchemas.ERR_SCHEMA, "Empty player_id fails")

	var float_arg: Dictionary = valid_env.duplicate(true)
	float_arg["args"] = {"ratio": 0.5}
	assert_eq(DtoSchemas.validate_command_envelope(float_arg).get("error_code", ""), DtoSchemas.ERR_SCHEMA, "Float in args fails")

	var oversized: Dictionary = valid_env.duplicate(true)
	oversized["args"] = {"blob": "x".repeat(4100)}
	assert_eq(DtoSchemas.validate_command_envelope(oversized).get("error_code", ""), DtoSchemas.ERR_SCHEMA, ">4096B envelope fails")


func test_validate_cmd_receipt() -> void:
	var accepted_ok: Dictionary = {
		"v": 1,
		"msg_type": DtoSchemas.MSG_CMD_RECEIPT,
		"cmd_seq": 5,
		"status": "ACCEPTED",
		"error_code": "OK",
		"exec_tick_id": 100
	}
	assert_true(_as_bool(DtoSchemas.validate_cmd_receipt(accepted_ok).get("ok", false)), "ACCEPTED with OK passes")

	var accepted_empty_code: Dictionary = accepted_ok.duplicate(true)
	accepted_empty_code["error_code"] = ""
	assert_true(_as_bool(DtoSchemas.validate_cmd_receipt(accepted_empty_code).get("ok", false)), "ACCEPTED with empty error_code passes")

	var rejected_ok: Dictionary = {
		"v": 1,
		"msg_type": DtoSchemas.MSG_CMD_RECEIPT,
		"cmd_seq": 6,
		"status": "REJECTED",
		"error_code": DtoSchemas.ERR_RATE_LIMITED,
		"exec_tick_id": 101
	}
	assert_true(_as_bool(DtoSchemas.validate_cmd_receipt(rejected_ok).get("ok", false)), "REJECTED with ERR_RATE_LIMITED passes")

	var bad_accepted: Dictionary = accepted_ok.duplicate(true)
	bad_accepted["error_code"] = DtoSchemas.ERR_SCHEMA
	assert_false(_as_bool(DtoSchemas.validate_cmd_receipt(bad_accepted).get("ok", true), true), "ACCEPTED with non-OK error_code fails")

	var bad_rejected: Dictionary = rejected_ok.duplicate(true)
	bad_rejected["error_code"] = "OK"
	assert_false(_as_bool(DtoSchemas.validate_cmd_receipt(bad_rejected).get("ok", true), true), "REJECTED with OK error_code fails")

	var bad_status: Dictionary = accepted_ok.duplicate(true)
	bad_status["status"] = "PENDING"
	assert_false(_as_bool(DtoSchemas.validate_cmd_receipt(bad_status).get("ok", true), true), "Invalid receipt status fails")

	var wrong_type: Dictionary = accepted_ok.duplicate(true)
	wrong_type["msg_type"] = DtoSchemas.MSG_TICK_DELTA
	assert_false(_as_bool(DtoSchemas.validate_cmd_receipt(wrong_type).get("ok", true), true), "Wrong msg_type fails")


func test_validate_tick_delta() -> void:
	var valid_delta: Dictionary = {
		"v": 1,
		"msg_type": DtoSchemas.MSG_TICK_DELTA,
		"tick_id": 24,
		"macro_tick_id": 4,
		"day_id": 1,
		"season": "SPRING",
		"state_crc32": 3421780262,
		"channels": {DtoSchemas.CHAN_MANOR: {}},
		"events": []
	}
	assert_true(_as_bool(DtoSchemas.validate_tick_delta(valid_delta).get("ok", false)), "Valid MSG_TICK_DELTA passes")

	var bad_season: Dictionary = valid_delta.duplicate(true)
	bad_season["season"] = "MONSOON"
	assert_false(_as_bool(DtoSchemas.validate_tick_delta(bad_season).get("ok", true), true), "Invalid season fails")

	var neg_crc: Dictionary = valid_delta.duplicate(true)
	neg_crc["state_crc32"] = -1
	assert_false(_as_bool(DtoSchemas.validate_tick_delta(neg_crc).get("ok", true), true), "Negative state_crc32 fails")

	var bad_channels: Dictionary = valid_delta.duplicate(true)
	bad_channels["channels"] = []
	assert_false(_as_bool(DtoSchemas.validate_tick_delta(bad_channels).get("ok", true), true), "Non-Dictionary channels fails")

	var bad_events: Dictionary = valid_delta.duplicate(true)
	bad_events["events"] = {}
	assert_false(_as_bool(DtoSchemas.validate_tick_delta(bad_events).get("ok", true), true), "Non-Array events fails")


func test_validate_persona_challenge() -> void:
	var valid_challenge: Dictionary = {
		"v": 1,
		"msg_type": DtoSchemas.MSG_PERSONA_CHALLENGE,
		"challenge_id": "7R4M9P",
		"issued_at_tick": 100,
		"ttl_expires_tick": 1000,
		"codebook": _make_valid_codebook(),
		"init_s1": 30,
		"init_s2": 4,
		"prompt_text": "[SYSTEM_IMMUTABLE_CONTRACT]"
	}
	assert_true(_as_bool(DtoSchemas.validate_persona_challenge(valid_challenge).get("ok", false)), "Valid MSG_PERSONA_CHALLENGE passes")

	var bad_cid: Dictionary = valid_challenge.duplicate(true)
	bad_cid["challenge_id"] = "7R4M9"
	assert_false(_as_bool(DtoSchemas.validate_persona_challenge(bad_cid).get("ok", true), true), "5-char challenge_id fails")

	var bad_ttl: Dictionary = valid_challenge.duplicate(true)
	bad_ttl["ttl_expires_tick"] = 100
	assert_false(_as_bool(DtoSchemas.validate_persona_challenge(bad_ttl).get("ok", true), true), "ttl_expires_tick <= issued_at_tick fails")

	var short_cb: Dictionary = valid_challenge.duplicate(true)
	var cb_short: Array[String] = _make_valid_codebook()
	var _popped: Variant = cb_short.pop_back()
	short_cb["codebook"] = cb_short
	assert_false(_as_bool(DtoSchemas.validate_persona_challenge(short_cb).get("ok", true), true), "30-char codebook fails")

	var dup_cb: Dictionary = valid_challenge.duplicate(true)
	var cb_dup: Array[String] = _make_valid_codebook()
	cb_dup[30] = cb_dup[0]
	dup_cb["codebook"] = cb_dup
	assert_false(_as_bool(DtoSchemas.validate_persona_challenge(dup_cb).get("ok", true), true), "Duplicate codebook char fails")

	var bad_s1: Dictionary = valid_challenge.duplicate(true)
	bad_s1["init_s1"] = 31
	assert_false(_as_bool(DtoSchemas.validate_persona_challenge(bad_s1).get("ok", true), true), "init_s1 == 31 fails")

	var empty_prompt: Dictionary = valid_challenge.duplicate(true)
	empty_prompt["prompt_text"] = ""
	assert_false(_as_bool(DtoSchemas.validate_persona_challenge(empty_prompt).get("ok", true), true), "Empty prompt_text fails")


func test_validate_offline_chronicle_digest() -> void:
	var valid_digest: Dictionary = {
		"v": 1,
		"msg_type": DtoSchemas.MSG_OFFLINE_CHRONICLE_DIGEST,
		"player_id": "lord_A",
		"from_tick": 100,
		"to_tick": 500,
		"net_yields": {"GRAIN": 320, "COIN": 45},
		"stipends_received": {"COIN": 20},
		"completed_missions": ["mission_01"],
		"pawn_events": [],
		"battle_replays": []
	}
	assert_true(_as_bool(DtoSchemas.validate_offline_chronicle_digest(valid_digest).get("ok", false)), "Valid MSG_OFFLINE_CHRONICLE_DIGEST passes")

	var same_tick: Dictionary = valid_digest.duplicate(true)
	same_tick["to_tick"] = 100
	assert_true(_as_bool(DtoSchemas.validate_offline_chronicle_digest(same_tick).get("ok", false)), "to_tick == from_tick passes")

	var reversed_ticks: Dictionary = valid_digest.duplicate(true)
	reversed_ticks["to_tick"] = 99
	assert_false(_as_bool(DtoSchemas.validate_offline_chronicle_digest(reversed_ticks).get("ok", true), true), "to_tick < from_tick fails")

	var empty_pid: Dictionary = valid_digest.duplicate(true)
	empty_pid["player_id"] = ""
	assert_false(_as_bool(DtoSchemas.validate_offline_chronicle_digest(empty_pid).get("ok", true), true), "Empty player_id fails")

	var bad_yields: Dictionary = valid_digest.duplicate(true)
	bad_yields["net_yields"] = []
	assert_false(_as_bool(DtoSchemas.validate_offline_chronicle_digest(bad_yields).get("ok", true), true), "Non-Dictionary net_yields fails")

	var bad_replays: Dictionary = valid_digest.duplicate(true)
	bad_replays["battle_replays"] = {}
	assert_false(_as_bool(DtoSchemas.validate_offline_chronicle_digest(bad_replays).get("ok", true), true), "Non-Array battle_replays fails")
