class_name TestCharacterCreationEngine
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


func _assert_avatar_and_retainer_invariants(res: Dictionary, label: String) -> void:
	assert_true(_as_bool(res.get("ok", false)), "%s creation must succeed" % label)
	assert_eq(res.get("error_code", ""), DtoSchemas.ERR_OK, "%s error_code == OK" % label)

	var base_v: Variant = res.get("base_stats_320", {})
	assert_true(base_v is Dictionary, "%s base_stats_320 must be Dictionary" % label)
	if base_v is Dictionary:
		var bs: Dictionary = base_v
		var base_sum: int = 0
		for sk: String in DtoSchemas.STAT_KEYS:
			var val: int = _as_int(bs.get(sk, 0))
			assert_in_range(val, DtoSchemas.STAT_MIN_BASE, DtoSchemas.STAT_MAX_BASE, "%s base stat %s in [35,85]" % [label, sk])
			base_sum += val
		assert_eq(base_sum, DtoSchemas.TOTAL_STAT_BUDGET, "%s base stats sum must strictly equal 320" % label)

	var av_v: Variant = res.get("avatar", null)
	assert_true(av_v is PawnEntity, "%s avatar must be PawnEntity" % label)
	var ret_v: Variant = res.get("retainer", null)
	assert_true(ret_v is PawnEntity, "%s retainer must be PawnEntity" % label)
	var man_v: Variant = res.get("manor", null)
	assert_true(man_v is ManorState, "%s manor must be ManorState" % label)

	if av_v is PawnEntity and ret_v is PawnEntity:
		var av: PawnEntity = av_v
		var ret: PawnEntity = ret_v

		# Origin-boosted stats capped at 95
		var lowest_stat: String = "LEA"
		var lowest_val: int = 999
		for sk: String in DtoSchemas.STAT_KEYS:
			var av_s: int = av.get_stat(sk)
			assert_in_range(av_s, 35, 95, "%s avatar %s after origin bonus <= 95" % [label, sk])
			if av_s < lowest_val:
				lowest_val = av_s
				lowest_stat = sk

		# Passion 3-pt budget invariant
		var passion_pts: int = 0
		for sk: String in DtoSchemas.STAT_KEYS:
			var pm: int = av.get_passion_pm(sk)
			if pm == PawnEntity.PASSION_DOUBLE_PM:
				passion_pts += 2
			elif pm == PawnEntity.PASSION_SINGLE_PM:
				passion_pts += 1
		assert_eq(passion_pts, DtoSchemas.PASSION_BUDGET, "%s avatar passion budget must equal 3" % label)

		# Light / Shadow trait balance invariant
		var shadow_cnt: int = 0
		var net_cost: int = 0
		for tr: String in av.traits:
			var idx: int = DtoSchemas.TRAIT_IDS.find(tr)
			assert_gte(idx, 0, "%s trait %s must be valid" % [label, tr])
			if DtoSchemas.TRAIT_SHADOW_POOL.has(idx):
				shadow_cnt += 1
			net_cost += SealedTokenCodec.TRAIT_COSTS[idx]
		assert_gte(shadow_cnt, 1, "%s avatar must have >= 1 shadow trait" % label)
		assert_in_range(net_cost, -1, 1, "%s avatar trait net cost must be in [-1, 1]" % label)

		# Initial schedule (12 slots), work priorities (7 domains), Opening Thought (+4..+5)
		assert_eq(av.daily_schedule.size(), 12, "%s avatar has 12 ShiChen schedule slots" % label)
		for dk: String in PawnEntity.WORK_DOMAINS:
			assert_in_range(av.get_work_priority(dk), 1, 4, "%s work priority %s in 1..4" % [label, dk])
		assert_true(av.has_thought("OPENING_DESTINY"), "%s avatar has OPENING_DESTINY thought" % label)
		var open_delta: int = 0
		for th: Dictionary in av.thoughts:
			if str(th.get("id", "")) == "OPENING_DESTINY":
				open_delta = _as_int(th.get("mood_delta", 0))
		assert_in_range(open_delta, 4, 5, "%s Opening Thought delta within guardrail (+4..+5)" % label)

		# Complementary starter retainer invariants
		assert_eq(_as_int(res.get("retainer_affinity", 0)), 40, "%s starter retainer affinity == 40" % label)
		assert_eq(ret.get_passion_pm(lowest_stat), PawnEntity.PASSION_DOUBLE_PM, "%s retainer double passion covers avatar lowest stat (%s)" % [label, lowest_stat])
		assert_gte(ret.get_stat(lowest_stat), 78, "%s retainer specializes in avatar lowest stat (%s)" % [label, lowest_stat])
		assert_true(ret.has_thought("SWORN_BOND_AFFINITY_40"), "%s retainer has sworn bond affinity thought" % label)


func test_interview_bank_and_interview_only_mode() -> void:
	var bank: Dictionary = CharacterCreationEngine.load_interview_bank()
	var q_var: Variant = bank.get("questions", [])
	assert_true(q_var is Array, "Interview bank questions must be Array")
	if q_var is Array:
		var qs: Array = q_var
		assert_eq(qs.size(), 8, "data/interview_questions.json must contain 8 scenes")

	var store: Dictionary = {}
	var cooldowns: Dictionary = {}
	var strikes: Dictionary = {}
	var params: Dictionary = {
		"player_id": "p_iv_only",
		"avatar_name": "Han_Xin_Demo",
		"creation_mode": "INTERVIEW_ONLY",
		"interview_answers": [0, 1, 2, 0, 1, 2, 3, 1],
		"origin_override": "ORIGIN_AGRARIAN_GENTRY",
		"province_override": "JI_ZHOU"
	}
	var res: Dictionary = CharacterCreationEngine.create_character_and_manor(
		params, store, cooldowns, strikes, 18401, 10
	)
	assert_eq(res.get("creation_mode", ""), "INTERVIEW_ONLY", "Effective mode must be INTERVIEW_ONLY")
	assert_eq(res.get("import_audit_status", ""), "NONE", "Interview-only audit status == NONE")
	_assert_avatar_and_retainer_invariants(res, "INTERVIEW_ONLY")

	var man_v: Variant = res.get("manor", null)
	if man_v is ManorState:
		var manor: ManorState = man_v
		assert_eq(manor.starting_province, "JI_ZHOU", "Province override applied")
		assert_eq(manor.host_node_id, "ye", "JI_ZHOU maps to ye host node")
		assert_eq(manor.get_building_level("MILITARY_FARM"), 2, "ORIGIN_AGRARIAN_GENTRY starts with Lv.2 farm")
		assert_eq(manor.get_building_level("GRANARY_VAULT"), 2, "ORIGIN_AGRARIAN_GENTRY starts with Lv.2 granary")
		assert_eq(manor.pawns.size(), 2, "Manor starts with 1 avatar + 1 starter retainer")


func test_fusion_interview_and_ai_direct_with_confirm_and_fine_tuning() -> void:
	var store: Dictionary = {}
	var cooldowns: Dictionary = {}
	var strikes: Dictionary = {}

	# Issue valid challenge for FUSION_INTERVIEW (40% AI + 60% 5-scene interview)
	var player_fusion: String = "p_fusion"
	var ch1: Dictionary = CharacterCreationEngine.create_character_and_manor(
		{
			"player_id": player_fusion,
			"creation_mode": "INTERVIEW_ONLY",
			"interview_answers": [0, 0, 0, 0, 0]
		},
		store, cooldowns, strikes, 18401, 50
	)
	assert_true(_as_bool(ch1.get("ok", false)), "Sanity setup ok")

	var issued_f: Dictionary = SealedTokenCodec.issue_challenge("acc_f", player_fusion, 100, store, cooldowns, 18401, 1)
	assert_true(_as_bool(issued_f.get("ok", false)), "Challenge issued for fusion")
	var f_data_v: Variant = issued_f.get("data", {})
	var cid_f: String = ""
	if f_data_v is Dictionary:
		var f_data: Dictionary = f_data_v
		cid_f = str(f_data.get("challenge_id", ""))

	var slots_f: Array[int] = [3, 25, 10, 18, 12, 8, 0, 2, 10, 4, 9, 2, 1, 2, 0, 0]
	var tok_f: String = SealedTokenCodec.encode_tk3k2(cid_f, player_fusion, slots_f)
	var wrapped_f: String = "<<<TK3K_PERSONA_V2>>>\n%s\n<<<END_TK3K_PERSONA_V2>>>\n<<<TK3K_LORE_V2>>>\ncourtesy_name: 자룡\nepithet: 창해의 별\n<<<END_TK3K_LORE_V2>>>" % tok_f

	var fusion_res: Dictionary = CharacterCreationEngine.create_character_and_manor(
		{
			"player_id": player_fusion,
			"avatar_name": "Zhao_Long",
			"creation_mode": "FUSION_INTERVIEW",
			"sealed_token_input": wrapped_f,
			"interview_answers": [1, 2, 0, 3, 2],
			"fine_tuning": {
				"stat_shift": {"from": "CHA", "to": "LEA", "amount": 5},
				"passion_swap": {"from": "LEA", "to": "POL"}
			}
		},
		store, cooldowns, strikes, 18401, 120
	)
	assert_eq(fusion_res.get("creation_mode", ""), "FUSION_INTERVIEW", "Mode must be FUSION_INTERVIEW")
	assert_eq(fusion_res.get("import_audit_status", ""), "VERIFIED_CLEAN", "Clean token verified")
	_assert_avatar_and_retainer_invariants(fusion_res, "FUSION_INTERVIEW")

	var av_f_v: Variant = fusion_res.get("avatar", null)
	if av_f_v is PawnEntity:
		var av_f: PawnEntity = av_f_v
		assert_eq(av_f.courtesy_name, "자룡", "Sanitized lore courtesy_name applied")
		assert_eq(av_f.epithet, "창해의 별", "Sanitized lore epithet applied")

	# AI_DIRECT_WITH_CONFIRM mode using clean TK3K2 token
	var player_direct: String = "p_direct"
	var issued_d: Dictionary = SealedTokenCodec.issue_challenge("acc_d", player_direct, 200, store, cooldowns, 18401, 2)
	assert_true(_as_bool(issued_d.get("ok", false)), "Challenge issued for direct mode")
	var d_data_v: Variant = issued_d.get("data", {})
	var cid_d: String = ""
	if d_data_v is Dictionary:
		var d_data: Dictionary = d_data_v
		cid_d = str(d_data.get("challenge_id", ""))

	var slots_d: Array[int] = [2, 16, 22, 14, 12, 10, 1, 0, 10, 0, 5, 1, 3, 2, 0, 0]
	var tok_d: String = SealedTokenCodec.encode_tk3k2(cid_d, player_direct, slots_d)
	var direct_res: Dictionary = CharacterCreationEngine.create_character_and_manor(
		{
			"player_id": player_direct,
			"avatar_name": "Direct_Hero",
			"creation_mode": "AI_DIRECT_WITH_CONFIRM",
			"sealed_token_input": tok_d,
			"interview_answers": [0, 0, 0, 0, 0, 0, 0, 0]
		},
		store, cooldowns, strikes, 18401, 220
	)
	assert_eq(direct_res.get("creation_mode", ""), "AI_DIRECT_WITH_CONFIRM", "Mode must be AI_DIRECT_WITH_CONFIRM")
	_assert_avatar_and_retainer_invariants(direct_res, "AI_DIRECT_WITH_CONFIRM")

	# Verify standing doctrine matches STANCE_CODE 0 (AGGRESSIVE)
	var man_d_v: Variant = direct_res.get("manor", null)
	if man_d_v is ManorState:
		var man_d: ManorState = man_d_v
		assert_eq(man_d.standing_doctrine.get("engagement_stance", ""), "PREEMPTIVE_STRIKE", "AGGRESSIVE stance sets PREEMPTIVE_STRIKE doctrine")


func test_plaintext_json_rejection_zero_bypass() -> void:
	var store: Dictionary = {}
	var cooldowns: Dictionary = {}
	var strikes: Dictionary = {}

	var forbidden_inputs: Array[String] = [
		"{\"LEA\": 99, \"MAR\": 99}",
		"AI_PERSONA_EXPORT_V1: LEA=90",
		"persona_weights = [90, 90, 90, 90, 90]",
		"\"lea\": 95, \"mar\": 95",
		"TK3K2-AAAAAA-BBBBBB-CCCCCC-DDDD-EE {smuggled}"
	]
	for bad_input: String in forbidden_inputs:
		for mode: String in ["FUSION_INTERVIEW", "AI_DIRECT_WITH_CONFIRM"]:
			var res: Dictionary = CharacterCreationEngine.create_character_and_manor(
				{
					"player_id": "p_attacker",
					"creation_mode": mode,
					"sealed_token_input": bad_input
				},
				store, cooldowns, strikes, 18401, 300
			)
			assert_false(_as_bool(res.get("ok", true)), "Plaintext JSON/smuggling must fail in %s: %s" % [mode, bad_input])
			assert_eq(res.get("error_code", ""), DtoSchemas.ERR_PLAINTEXT_JSON_FORBIDDEN, "Must return ERR_PLAINTEXT_JSON_FORBIDDEN for: %s" % bad_input)


func test_deterministic_creation_same_inputs_same_hash() -> void:
	var store1: Dictionary = {}
	var store2: Dictionary = {}
	var params: Dictionary = {
		"player_id": "p_det_01",
		"avatar_name": "Det_Hero",
		"creation_mode": "INTERVIEW_ONLY",
		"interview_answers": [2, 3, 1, 0, 2, 1, 2, 3],
		"fine_tuning": {"stat_shift": {"from": "MAR", "to": "INT", "amount": 4}}
	}
	var r1: Dictionary = CharacterCreationEngine.create_character_and_manor(params, store1, {}, {}, 18401, 0)
	var r2: Dictionary = CharacterCreationEngine.create_character_and_manor(params, store2, {}, {}, 18401, 0)

	var m1_v: Variant = r1.get("manor", null)
	var m2_v: Variant = r2.get("manor", null)
	assert_true(m1_v is ManorState and m2_v is ManorState, "Both runs produce ManorState")
	if m1_v is ManorState and m2_v is ManorState:
		var m1: ManorState = m1_v
		var m2: ManorState = m2_v
		assert_eq(StateHasher.sha256_dict(m1.to_dict()), StateHasher.sha256_dict(m2.to_dict()), "Deterministic creation SHA256 must match")
