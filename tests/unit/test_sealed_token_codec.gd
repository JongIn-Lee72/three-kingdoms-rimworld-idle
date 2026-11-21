class_name TestSealedTokenCodec
extends HarnessTestCase


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


func _make_challenge_record(cid: String, player_id: String, issued_tick: int = 100, ttl_tick: int = 1000) -> Dictionary:
	return {
		"challenge_id": cid,
		"account_id": "acc_" + player_id,
		"bound_player_id": player_id,
		"player_id": player_id,
		"issued_at_tick": issued_tick,
		"ttl_expires_tick": ttl_tick,
		"consumed_at_tick": null,
		"status": "ISSUED",
		"attempt_count": 0,
		"max_attempts": SealedTokenCodec.MAX_CHALLENGE_ATTEMPTS,
		"cooldown_until_tick": 0,
		"last_coercion_flag": "R0_CLEAN",
		"last_reject_reason": null
	}


func _sum_ints(arr: Array) -> int:
	var total: int = 0
	for item: Variant in arr:
		if item is int:
			var iv: int = item
			total += iv
	return total


func test_worked_example_tk3k2_roundtrip() -> void:
	var cid: String = "7R4M9P"
	var player_id: String = "player_demo_01"
	var worked_token: String = "TK3K2-7R4M9P-ME1KPF-AMXAV0-A00G-N4"
	var slots: Array[int] = [3, 18, 8, 26, 22, 14, 2, 3, 10, 2, 9, 1, 2, 1, 1, 0]

	var cipher: Dictionary = SealedTokenCodec.derive_session_cipher(cid, player_id)
	assert_eq(cipher.get("init_s1", -1), 30, "Worked example init_s1 must equal 30")
	assert_eq(cipher.get("init_s2", -1), 4, "Worked example init_s2 must equal 4")

	var encoded: String = SealedTokenCodec.encode_tk3k2(cid, player_id, slots)
	assert_eq(encoded, worked_token, "encode_tk3k2 must match GDD worked example token exactly")

	var store: Dictionary = {cid: _make_challenge_record(cid, player_id, 100, 1000)}
	var cooldowns: Dictionary = {}
	var strikes: Dictionary = {}
	var wrapped: String = "<<<TK3K_PERSONA_V2>>>\n%s\n<<<END_TK3K_PERSONA_V2>>>" % worked_token

	var res: Dictionary = SealedTokenCodec.decode_and_verify(
		wrapped, player_id, "AI_DIRECT_WITH_CONFIRM", 150, store, cooldowns, strikes
	)
	assert_true(_as_bool(res.get("ok", false)), "Worked example token must verify cleanly")
	assert_eq(res.get("error_code", ""), DtoSchemas.ERR_OK, "Worked example error_code == OK")

	var data_v: Variant = res.get("data", null)
	assert_true(data_v is Dictionary, "Verified result data must be Dictionary")
	if data_v is Dictionary:
		var data: Dictionary = data_v
		assert_eq(data.get("normalized_stats", []), [64, 52, 75, 70, 59], "Worked example stats == [64, 52, 75, 70, 59]")
		assert_eq(data.get("raw_weights", []), [74, 44, 98, 86, 62], "Worked example raw_weights == [74, 44, 98, 86, 62]")
		var stats_v: Variant = data.get("normalized_stats", [])
		if stats_v is Array:
			var stats_arr: Array = stats_v
			assert_eq(_sum_ints(stats_arr), 320, "Normalized stats sum must equal 320")
		assert_eq(data.get("ai_source", ""), "GEMINI", "ai_source == GEMINI")
		assert_eq(data.get("effective_mode", ""), "AI_DIRECT_WITH_CONFIRM", "effective_mode == AI_DIRECT_WITH_CONFIRM")
		assert_eq(data.get("import_audit_status", ""), "VERIFIED_CLEAN", "import_audit_status == VERIFIED_CLEAN")
		assert_eq(data.get("shadow_count", 0), 2, "shadow_count == 2")
		assert_eq(data.get("net_trait_cost", 99), -1, "net_trait_cost == -1")
		assert_eq(data.get("passion_alloc", {}), {2: 2, 3: 1}, "passion_alloc == {2: 2, 3: 1}")
		assert_eq(data.get("origin_hint", ""), "ORIGIN_PURE_SCHOLAR", "origin_hint matches")
		assert_eq(data.get("rhythm_code", ""), "NIGHT_OWL", "rhythm_code matches")
		assert_eq(data.get("stance_code", ""), "CALCULATED", "stance_code matches")
		assert_eq(data.get("coercion_flag", ""), "R0_CLEAN", "coercion_flag == R0_CLEAN")
		assert_eq(data.get("bonus_resources", {"bad": 1}), {}, "bonus_resources must be empty")

	var rec_v: Variant = store.get(cid, {})
	if rec_v is Dictionary:
		var rec: Dictionary = rec_v
		assert_eq(rec.get("status", ""), "CONSUMED", "Challenge record must transition to CONSUMED")
		assert_eq(rec.get("consumed_at_tick", -1), 150, "consumed_at_tick recorded")


func test_adversarial_weight_normalization_320() -> void:
	var cases: Array[Array] = [
		[9999, 9999, 9999, 9999, 9999],
		[1000, 0, 0, 0, 0],
		[0, 0, 0, 0, 0],
		[-50, 1000, 1000, 0, 500],
		[200, 200, 200, 200, 200]
	]
	for w_arr: Array in cases:
		var typed_w: Array[int] = []
		for elem: Variant in w_arr:
			if elem is int:
				var iv: int = elem
				typed_w.append(iv)
		var stats: Array[int] = SealedTokenCodec.normalize_weights_320(typed_w)
		assert_eq(stats.size(), 5, "Must always output 5 stats")
		assert_eq(_sum_ints(stats), 320, "Normalized stat sum must strictly equal 320 for %s" % str(typed_w))
		for s: int in stats:
			assert_in_range(s, 35, 85, "Every normalized stat must lie in [35, 85]")

	assert_eq(
		SealedTokenCodec.normalize_weights_320([9999, 9999, 9999, 9999, 9999]),
		[64, 64, 64, 64, 64],
		"[9999]*5 normalizes to [64, 64, 64, 64, 64]"
	)
	assert_eq(
		SealedTokenCodec.normalize_weights_320([0, 0, 0, 0, 0]),
		[64, 64, 64, 64, 64],
		"[0]*5 normalizes to [64, 64, 64, 64, 64]"
	)
	var skewed: Array[int] = SealedTokenCodec.normalize_weights_320([1000, 0, 0, 0, 0])
	assert_eq(skewed[0], 85, "[1000,0,0,0,0] caps primary stat at 85")


func test_fletcher31_tamper_single_char_and_transposition() -> void:
	var cid: String = "7R4M9P"
	var player_id: String = "player_demo_01"
	var store: Dictionary = {cid: _make_challenge_record(cid, player_id, 100, 1000)}
	var cooldowns: Dictionary = {}
	var strikes: Dictionary = {}

	# 1-char substitution from GDD: K -> J
	var tampered_sub: String = "TK3K2-7R4M9P-ME1JPF-AMXAV0-A00G-N4"
	var r1: Dictionary = SealedTokenCodec.decode_and_verify(
		tampered_sub, player_id, "AI_DIRECT_WITH_CONFIRM", 110, store, cooldowns, strikes
	)
	assert_false(_as_bool(r1.get("ok", true), true), "Single-char tampered token must be rejected")
	assert_eq(r1.get("error_code", ""), DtoSchemas.ERR_TOKEN_TAMPERED, "Single-char corruption returns ERR_TOKEN_TAMPERED")

	# Adjacent transposition in SEG1: ME1KPF -> EM1KPF
	var tampered_trans: String = "TK3K2-7R4M9P-EM1KPF-AMXAV0-A00G-N4"
	var r2: Dictionary = SealedTokenCodec.decode_and_verify(
		tampered_trans, player_id, "AI_DIRECT_WITH_CONFIRM", 111, store, cooldowns, strikes
	)
	assert_false(_as_bool(r2.get("ok", true), true), "Adjacent transposition must be rejected")
	assert_eq(r2.get("error_code", ""), DtoSchemas.ERR_TOKEN_TAMPERED, "Adjacent transposition returns ERR_TOKEN_TAMPERED")

	var rec_v: Variant = store.get(cid, {})
	if rec_v is Dictionary:
		var rec: Dictionary = rec_v
		assert_eq(rec.get("attempt_count", 0), 2, "attempt_count incremented twice")
		assert_eq(rec.get("status", ""), "ISSUED", "Still ISSUED before max_attempts=3")


func test_plaintext_json_and_kv_smuggling_rejected() -> void:
	var store: Dictionary = {}
	var cooldowns: Dictionary = {}
	var payloads: Array[String] = [
		"{\"schema_version\": \"AI_PERSONA_EXPORT_V1\", \"lea\": 99}",
		"AI_PERSONA_EXPORT_V1",
		"persona_weights=99,99,99",
		"\"lea\": 95, \"mar\": 90",
		"\"INT\" : 85",
		"TK3K2-7R4M9P-ME1KPF-AMXAV0-A00G-N4 {extra}"
	]
	for p: String in payloads:
		var res: Dictionary = SealedTokenCodec.decode_and_verify(
			p, "player_demo_01", "AI_DIRECT_WITH_CONFIRM", 10, store, cooldowns
		)
		assert_false(_as_bool(res.get("ok", true), true), "Smuggled payload must fail: " + p)
		assert_eq(res.get("error_code", ""), DtoSchemas.ERR_PLAINTEXT_JSON_FORBIDDEN, "Expected ERR_PLAINTEXT_JSON_FORBIDDEN for: " + p)


func test_oversized_multi_envelope_and_format_rejection() -> void:
	var cid: String = "7R4M9P"
	var player_id: String = "player_demo_01"
	var token: String = "TK3K2-7R4M9P-ME1KPF-AMXAV0-A00G-N4"
	var store: Dictionary = {cid: _make_challenge_record(cid, player_id, 100, 1000)}
	var cooldowns: Dictionary = {}

	var oversized: String = token + " " + "A".repeat(4097 - token.length() - 1)
	assert_gt(oversized.to_utf8_buffer().size(), 4096, "Oversized test payload > 4096 bytes")
	var r_over: Dictionary = SealedTokenCodec.decode_and_verify(
		oversized, player_id, "AI_DIRECT_WITH_CONFIRM", 110, store, cooldowns
	)
	assert_eq(r_over.get("error_code", ""), DtoSchemas.ERR_TOKEN_FORMAT, ">4096B payload rejected with ERR_TOKEN_FORMAT")

	var multi_env: String = "<<<TK3K_PERSONA_V2>>>%s<<<END_TK3K_PERSONA_V2>>> <<<TK3K_PERSONA_V2>>>%s<<<END_TK3K_PERSONA_V2>>>" % [token, token]
	var r_multi: Dictionary = SealedTokenCodec.decode_and_verify(
		multi_env, player_id, "AI_DIRECT_WITH_CONFIRM", 110, store, cooldowns
	)
	assert_eq(r_multi.get("error_code", ""), DtoSchemas.ERR_TOKEN_FORMAT, "Multi-envelope rejected with ERR_TOKEN_FORMAT")

	var unmatched: String = "<<<TK3K_PERSONA_V2>>>" + token
	var r_unmatched: Dictionary = SealedTokenCodec.decode_and_verify(
		unmatched, player_id, "AI_DIRECT_WITH_CONFIRM", 110, store, cooldowns
	)
	assert_eq(r_unmatched.get("error_code", ""), DtoSchemas.ERR_TOKEN_FORMAT, "Unmatched envelope tag rejected")

	var invalid_b31: String = "TK3K2-7R4M9P-ME1IPF-AMXAV0-A00G-N4" # 'I' is excluded from Base31 A31
	var r_b31: Dictionary = SealedTokenCodec.decode_and_verify(
		invalid_b31, player_id, "AI_DIRECT_WITH_CONFIRM", 110, store, cooldowns
	)
	assert_eq(r_b31.get("error_code", ""), DtoSchemas.ERR_TOKEN_FORMAT, "Excluded Base31 char 'I' rejected with ERR_TOKEN_FORMAT")


func test_challenge_unknown_ownership_expired_and_replay() -> void:
	var cid: String = "7R4M9P"
	var player_id: String = "player_demo_01"
	var token: String = "TK3K2-7R4M9P-ME1KPF-AMXAV0-A00G-N4"
	var cooldowns: Dictionary = {}

	# Unknown challenge
	var r_unk: Dictionary = SealedTokenCodec.decode_and_verify(
		token, player_id, "AI_DIRECT_WITH_CONFIRM", 110, {}, cooldowns
	)
	assert_eq(r_unk.get("error_code", ""), DtoSchemas.ERR_CHALLENGE_UNKNOWN, "Unknown challenge_id rejected")

	# Ownership mismatch
	var store_own: Dictionary = {cid: _make_challenge_record(cid, player_id, 100, 1000)}
	var r_own: Dictionary = SealedTokenCodec.decode_and_verify(
		token, "attacker_99", "AI_DIRECT_WITH_CONFIRM", 110, store_own, cooldowns
	)
	assert_eq(r_own.get("error_code", ""), DtoSchemas.ERR_CHALLENGE_OWNERSHIP, "Different player_id rejected with ERR_CHALLENGE_OWNERSHIP")

	# Already EXPIRED status even if current_tick <= ttl_expires_tick
	var exp_rec: Dictionary = _make_challenge_record(cid, player_id, 100, 1000)
	exp_rec["status"] = "EXPIRED"
	var store_exp_status: Dictionary = {cid: exp_rec}
	var r_exp_status: Dictionary = SealedTokenCodec.decode_and_verify(
		token, player_id, "AI_DIRECT_WITH_CONFIRM", 150, store_exp_status, cooldowns
	)
	assert_eq(r_exp_status.get("error_code", ""), DtoSchemas.ERR_CHALLENGE_EXPIRED, "Persisted EXPIRED status rejected")

	# TTL elapsed
	var store_ttl: Dictionary = {cid: _make_challenge_record(cid, player_id, 100, 1000)}
	var r_ttl: Dictionary = SealedTokenCodec.decode_and_verify(
		token, player_id, "AI_DIRECT_WITH_CONFIRM", 1001, store_ttl, cooldowns
	)
	assert_eq(r_ttl.get("error_code", ""), DtoSchemas.ERR_CHALLENGE_EXPIRED, "current_tick > ttl_expires_tick rejected")
	var ttl_rec_v: Variant = store_ttl.get(cid, {})
	if ttl_rec_v is Dictionary:
		var ttl_rec: Dictionary = ttl_rec_v
		assert_eq(ttl_rec.get("status", ""), "EXPIRED", "Expired challenge status persisted")

	# Replay after consumption
	var store_rep: Dictionary = {cid: _make_challenge_record(cid, player_id, 100, 1000)}
	var r_first: Dictionary = SealedTokenCodec.decode_and_verify(
		token, player_id, "AI_DIRECT_WITH_CONFIRM", 150, store_rep, cooldowns
	)
	assert_true(_as_bool(r_first.get("ok", false)), "First submission succeeds")
	var r_replay: Dictionary = SealedTokenCodec.decode_and_verify(
		token, player_id, "AI_DIRECT_WITH_CONFIRM", 151, store_rep, cooldowns
	)
	assert_eq(r_replay.get("error_code", ""), DtoSchemas.ERR_CHALLENGE_REPLAYED, "Second submission rejected as ERR_CHALLENGE_REPLAYED")


func test_escalating_tamper_cooldowns_300_900_3600() -> void:
	var player_id: String = "tamper_lord"
	var cooldowns: Dictionary = {}
	var strikes: Dictionary = {}
	var store: Dictionary = {}

	var expected_tiers: Array[int] = [300, 900, 3600]
	var tick: int = 100
	for tier_idx: int in range(3):
		var cid: String = "CD000%d" % tier_idx
		store[cid] = _make_challenge_record(cid, player_id, tick, tick + 900)
		var valid_tok: String = SealedTokenCodec.encode_tk3k2(
			cid, player_id, [3, 18, 8, 26, 22, 14, 2, 3, 10, 2, 9, 1, 2, 1, 1, 0]
		)
		# Corrupt last character deterministically
		var last_ch: String = valid_tok.substr(valid_tok.length() - 1, 1)
		var repl_ch: String = "0" if last_ch != "0" else "1"
		var bad_tok: String = valid_tok.substr(0, valid_tok.length() - 1) + repl_ch

		for _attempt: int in range(3):
			var r_bad: Dictionary = SealedTokenCodec.decode_and_verify(
				bad_tok, player_id, "AI_DIRECT_WITH_CONFIRM", tick, store, cooldowns, strikes
			)
			assert_eq(r_bad.get("error_code", ""), DtoSchemas.ERR_TOKEN_TAMPERED, "Tampered attempt returns ERR_TOKEN_TAMPERED")

		var expected_until: int = tick + expected_tiers[tier_idx]
		assert_eq(cooldowns.get(player_id, 0), expected_until, "Strike %d applies %d-tick cooldown" % [tier_idx + 1, expected_tiers[tier_idx]])

		var rec_v: Variant = store.get(cid, {})
		if rec_v is Dictionary:
			var rec: Dictionary = rec_v
			assert_eq(rec.get("status", ""), "REVOKED_TAMPER", "3rd tamper revokes challenge")

		var r_cd: Dictionary = SealedTokenCodec.decode_and_verify(
			valid_tok, player_id, "AI_DIRECT_WITH_CONFIRM", tick + 1, store, cooldowns, strikes
		)
		assert_eq(r_cd.get("error_code", ""), DtoSchemas.ERR_CHALLENGE_COOLDOWN, "Submission during cooldown rejected")

		var r_issue_cd: Dictionary = SealedTokenCodec.issue_challenge(
			"acc_" + player_id, player_id, tick + 1, store, cooldowns
		)
		assert_eq(r_issue_cd.get("error_code", ""), DtoSchemas.ERR_CHALLENGE_COOLDOWN, "Issuing challenge during cooldown rejected")

		tick = expected_until


func test_coercion_telemetry_r0_through_r3() -> void:
	var player_id: String = "coercion_tester"
	var cooldowns: Dictionary = {}
	var store: Dictionary = {}

	# R1_MILD_STEERING -> downgraded to FUSION_INTERVIEW with beta_ai = 2000
	var cid_r1: String = "C000R1"
	store[cid_r1] = _make_challenge_record(cid_r1, player_id, 100, 1000)
	var tok_r1: String = SealedTokenCodec.encode_tk3k2(
		cid_r1, player_id, [3, 18, 8, 26, 22, 14, 2, 3, 10, 2, 9, 1, 2, 1, 1, 1]
	)
	var res_r1: Dictionary = SealedTokenCodec.decode_and_verify(
		tok_r1, player_id, "AI_DIRECT_WITH_CONFIRM", 120, store, cooldowns
	)
	assert_true(_as_bool(res_r1.get("ok", false)), "R1 succeeds with downgrade")
	var d1_v: Variant = res_r1.get("data", null)
	if d1_v is Dictionary:
		var d1: Dictionary = d1_v
		assert_eq(d1.get("coercion_flag", ""), "R1_MILD_STEERING", "R1 flag recorded")
		assert_eq(d1.get("effective_mode", ""), "FUSION_INTERVIEW", "R1 forces FUSION_INTERVIEW")
		assert_eq(d1.get("beta_ai", -1), 2000, "R1 caps beta_ai at 2000")
		assert_eq(d1.get("import_audit_status", ""), "DOWNGRADED_ANOMALY", "R1 audit status is DOWNGRADED_ANOMALY")

	# R2_STAT_COERCION -> ERR_COERCION_REJECTED, no cooldown
	var cid_r2: String = "C000R2"
	store[cid_r2] = _make_challenge_record(cid_r2, player_id, 200, 1100)
	var tok_r2: String = SealedTokenCodec.encode_tk3k2(
		cid_r2, player_id, [3, 18, 8, 26, 22, 14, 2, 3, 10, 2, 9, 1, 2, 1, 1, 2]
	)
	var res_r2: Dictionary = SealedTokenCodec.decode_and_verify(
		tok_r2, player_id, "AI_DIRECT_WITH_CONFIRM", 220, store, cooldowns
	)
	assert_false(_as_bool(res_r2.get("ok", true), true), "R2 rejected")
	assert_eq(res_r2.get("error_code", ""), DtoSchemas.ERR_COERCION_REJECTED, "R2 returns ERR_COERCION_REJECTED")
	var d2_v: Variant = res_r2.get("data", null)
	if d2_v is Dictionary:
		var d2: Dictionary = d2_v
		assert_eq(d2.get("coercion_flag", ""), "R2_STAT_COERCION", "R2 flag reported")
		assert_eq(d2.get("forced_mode", ""), "INTERVIEW_ONLY", "R2 forces INTERVIEW_ONLY")
		assert_false(_as_bool(d2.get("cooldown_applied", true), true), "R2 does not apply account cooldown")

	# R3_PROMPT_INJECTION -> ERR_COERCION_REJECTED + 1800 tick cooldown
	var cid_r3: String = "C000R3"
	store[cid_r3] = _make_challenge_record(cid_r3, player_id, 300, 1200)
	var tok_r3: String = SealedTokenCodec.encode_tk3k2(
		cid_r3, player_id, [3, 18, 8, 26, 22, 14, 2, 3, 10, 2, 9, 1, 2, 1, 1, 3]
	)
	var res_r3: Dictionary = SealedTokenCodec.decode_and_verify(
		tok_r3, player_id, "AI_DIRECT_WITH_CONFIRM", 350, store, cooldowns
	)
	assert_false(_as_bool(res_r3.get("ok", true), true), "R3 rejected")
	assert_eq(res_r3.get("error_code", ""), DtoSchemas.ERR_COERCION_REJECTED, "R3 returns ERR_COERCION_REJECTED")
	assert_eq(cooldowns.get(player_id, 0), 350 + 1800, "R3 applies 1800-tick account cooldown")
	var d3_v: Variant = res_r3.get("data", null)
	if d3_v is Dictionary:
		var d3: Dictionary = d3_v
		assert_true(_as_bool(d3.get("cooldown_applied", false)), "R3 reports cooldown_applied == true")


func test_anomaly_heuristics_h1_h2_h3_and_domain_errors() -> void:
	var player_id: String = "heuristic_lord"
	var cooldowns: Dictionary = {}
	var store: Dictionary = {}

	# H1: All >= 28 -> DOWNGRADED_ANOMALY, beta_ai <= 2000, FUSION_INTERVIEW
	var cid_h1: String = "H1TEST"
	store[cid_h1] = _make_challenge_record(cid_h1, player_id, 100, 1000)
	var tok_h1: String = SealedTokenCodec.encode_tk3k2(
		cid_h1, player_id, [1, 29, 28, 30, 28, 29, 0, 1, 10, 0, 10, 1, 0, 0, 0, 0]
	)
	var r_h1: Dictionary = SealedTokenCodec.decode_and_verify(
		tok_h1, player_id, "AI_DIRECT_WITH_CONFIRM", 110, store, cooldowns
	)
	assert_true(_as_bool(r_h1.get("ok", false)), "H1 succeeds with downgrade")
	var dh1_v: Variant = r_h1.get("data", null)
	if dh1_v is Dictionary:
		var dh1: Dictionary = dh1_v
		assert_eq(dh1.get("import_audit_status", ""), "DOWNGRADED_ANOMALY", "H1 triggers DOWNGRADED_ANOMALY")
		assert_eq(dh1.get("effective_mode", ""), "FUSION_INTERVIEW", "H1 downgrades to FUSION_INTERVIEW")
		assert_lte(_as_int(dh1.get("beta_ai", 99999), 99999), 2000, "H1 caps beta_ai at 2000")

	# H2: Extreme bimodal ([29, 28, 2, 3, 15]) -> FUSION_INTERVIEW, beta_ai <= 4000, soft compressed raw_weights
	var cid_h2: String = "H2TEST"
	store[cid_h2] = _make_challenge_record(cid_h2, player_id, 100, 1000)
	var tok_h2: String = SealedTokenCodec.encode_tk3k2(
		cid_h2, player_id, [2, 29, 28, 2, 3, 15, 0, 1, 10, 0, 10, 1, 0, 0, 0, 0]
	)
	var r_h2: Dictionary = SealedTokenCodec.decode_and_verify(
		tok_h2, player_id, "AI_DIRECT_WITH_CONFIRM", 110, store, cooldowns
	)
	assert_true(_as_bool(r_h2.get("ok", false)), "H2 succeeds with soft compression")
	var dh2_v: Variant = r_h2.get("data", null)
	if dh2_v is Dictionary:
		var dh2: Dictionary = dh2_v
		assert_eq(dh2.get("import_audit_status", ""), "DOWNGRADED_ANOMALY", "H2 triggers DOWNGRADED_ANOMALY")
		assert_eq(dh2.get("effective_mode", ""), "FUSION_INTERVIEW", "H2 downgrades to FUSION_INTERVIEW")
		assert_lte(_as_int(dh2.get("beta_ai", 99999), 99999), 4000, "H2 caps beta_ai at 4000")
		var rw_v: Variant = dh2.get("raw_weights", [])
		if rw_v is Array:
			var rw_arr: Array = rw_v
			# Original raw weights for [29,28,2,3,15] are [107, 104, 26, 29, 65]; mean=66; compressed[0] = (850*107 + 150*66)/1000 = 100
			assert_eq(rw_arr[0], 100, "H2 compresses extreme high weight 107 -> 100")

	# H3a: All-Light traits [0, 4, 5] -> repaired so shadow_count >= 1 and net_cost in [-1, 1]
	var cid_h3a: String = "H3RGHT"
	store[cid_h3a] = _make_challenge_record(cid_h3a, player_id, 100, 1000)
	var tok_h3a: String = SealedTokenCodec.encode_tk3k2(
		cid_h3a, player_id, [1, 10, 20, 15, 12, 8, 0, 1, 10, 0, 4, 5, 0, 0, 0, 0]
	)
	var r_h3a: Dictionary = SealedTokenCodec.decode_and_verify(
		tok_h3a, player_id, "AI_DIRECT_WITH_CONFIRM", 110, store, cooldowns
	)
	assert_true(_as_bool(r_h3a.get("ok", false)), "H3 all-Light repaired cleanly")
	var dh3a_v: Variant = r_h3a.get("data", null)
	if dh3a_v is Dictionary:
		var dh3a: Dictionary = dh3a_v
		assert_eq(dh3a.get("import_audit_status", ""), "DOWNGRADED_ANOMALY", "All-Light triggers DOWNGRADED_ANOMALY")
		assert_gte(_as_int(dh3a.get("shadow_count", 0), 0), 1, "Repaired shadow_count >= 1")
		assert_in_range(_as_int(dh3a.get("net_trait_cost", 99), 99), -1, 1, "Repaired net_trait_cost in [-1, 1]")

	# H3b: All-Shadow traits [1, 2, 3] -> repaired so shadow_count >= 1 and net_cost in [-1, 1]
	var cid_h3b: String = "H3SHDW"
	store[cid_h3b] = _make_challenge_record(cid_h3b, player_id, 100, 1000)
	var tok_h3b: String = SealedTokenCodec.encode_tk3k2(
		cid_h3b, player_id, [1, 10, 20, 15, 12, 8, 0, 1, 10, 1, 2, 3, 0, 0, 0, 0]
	)
	var r_h3b: Dictionary = SealedTokenCodec.decode_and_verify(
		tok_h3b, player_id, "AI_DIRECT_WITH_CONFIRM", 110, store, cooldowns
	)
	assert_true(_as_bool(r_h3b.get("ok", false)), "H3 all-Shadow repaired cleanly")
	var dh3b_v: Variant = r_h3b.get("data", null)
	if dh3b_v is Dictionary:
		var dh3b: Dictionary = dh3b_v
		assert_eq(dh3b.get("import_audit_status", ""), "DOWNGRADED_ANOMALY", "All-Shadow triggers DOWNGRADED_ANOMALY")
		assert_gte(_as_int(dh3b.get("shadow_count", 0), 0), 1, "Repaired shadow_count >= 1")
		assert_in_range(_as_int(dh3b.get("net_trait_cost", 99), 99), -1, 1, "Repaired net_trait_cost in [-1, 1]")

	# Domain error: duplicate passion axis (p1 == p2 == 0) with valid Fletcher-31 checksum
	var cid_dom: String = "DAMERR"
	store[cid_dom] = _make_challenge_record(cid_dom, player_id, 100, 1000)
	var tok_dom: String = SealedTokenCodec.encode_tk3k2(
		cid_dom, player_id, [1, 10, 20, 15, 12, 8, 0, 0, 10, 0, 10, 1, 0, 0, 0, 0]
	)
	var r_dom: Dictionary = SealedTokenCodec.decode_and_verify(
		tok_dom, player_id, "AI_DIRECT_WITH_CONFIRM", 110, store, cooldowns
	)
	assert_eq(r_dom.get("error_code", ""), DtoSchemas.ERR_TOKEN_DOMAIN, "Duplicate passion axis fails with ERR_TOKEN_DOMAIN")


func test_sanitize_lore_block_bounds_and_stripping() -> void:
	var long_hook: String = "A".repeat(160)
	var raw_lore: String = (
		"<<<TK3K_LORE_V2>>>\n"
		+ "courtesy_name: [b]Zilong_123456789[/b]\n"
		+ "epithet: [color=red]Dragon\u0007General_LongTag[/color]\n"
		+ "modern_background_tag: SystemsEngineerFromSeoulExtraChars\n"
		+ "motto: Never yield to tyranny even when outnumbered badly today\n"
		+ "backstory_hook: " + long_hook + "\n"
		+ "bonus_resources: 999999\n"
		+ "<<<END_TK3K_LORE_V2>>>"
	)
	var clean: Dictionary = SealedTokenCodec.sanitize_lore_block(raw_lore)
	assert_eq(clean.get("bonus_resources", -1), 0, "bonus_resources must strictly remain 0")
	assert_lte(str(clean.get("courtesy_name", "")).length(), 12, "courtesy_name capped at 12 chars")
	assert_lte(str(clean.get("epithet", "")).length(), 16, "epithet capped at 16 chars")
	assert_lte(str(clean.get("modern_background_tag", "")).length(), 20, "modern_background_tag capped at 20 chars")
	assert_lte(str(clean.get("motto", "")).length(), 40, "motto capped at 40 chars")
	assert_eq(str(clean.get("backstory_hook", "")).length(), 140, "backstory_hook capped at 140 chars")
	assert_false(str(clean.get("courtesy_name", "")).contains("[b]"), "BBCode tags stripped")
	assert_false(str(clean.get("epithet", "")).contains("\u0007"), "Control characters stripped")

	# Missing or duplicated lore blocks yield empty defaults with bonus_resources == 0
	var dup_lore: String = raw_lore + "\n" + raw_lore
	var clean_dup: Dictionary = SealedTokenCodec.sanitize_lore_block(dup_lore)
	assert_eq(clean_dup.get("courtesy_name", "bad"), "", "Duplicate lore blocks rejected cleanly")
	assert_eq(clean_dup.get("bonus_resources", -1), 0, "Duplicate lore blocks grant 0 bonus_resources")


func test_issue_challenge_and_rate_limits() -> void:
	var store: Dictionary = {}
	var cooldowns: Dictionary = {}
	for i: int in range(3):
		var issued: Dictionary = SealedTokenCodec.issue_challenge("acc_1", "player_1", 100 + i, store, cooldowns)
		assert_true(_as_bool(issued.get("ok", false)), "Challenge %d within 15m limit succeeds" % i)
		var msg_v: Variant = issued.get("data", null)
		assert_true(msg_v is Dictionary, "Issued challenge data is Dictionary")
		if msg_v is Dictionary:
			var msg: Dictionary = msg_v
			var schema_res: Dictionary = DtoSchemas.validate_persona_challenge(msg)
			assert_true(_as_bool(schema_res.get("ok", false)), "Issued challenge conforms to MSG_PERSONA_CHALLENGE schema")

	var rate_limited: Dictionary = SealedTokenCodec.issue_challenge("acc_1", "player_1", 105, store, cooldowns)
	assert_false(_as_bool(rate_limited.get("ok", true), true), "4th challenge within 900 ticks rate-limited")
	assert_eq(rate_limited.get("error_code", ""), DtoSchemas.ERR_CHALLENGE_COOLDOWN, "Rate limit returns ERR_CHALLENGE_COOLDOWN")
