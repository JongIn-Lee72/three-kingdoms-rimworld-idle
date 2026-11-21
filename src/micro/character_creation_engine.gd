class_name CharacterCreationEngine
extends RefCounted

const ORIGIN_DATA: Dictionary = {
	"ORIGIN_FALLEN_ROYAL": {
		"name_kr": "몰락 황족",
		"stat_bonus": {"CHA": 8, "POL": 4},
		"resources": {"GRAIN": 1500, "COIN": 1000, "WOOD": 300, "IRON": 150, "HORSES": 10, "HERBS_WINE": 100, "WEAPONS": 40, "MERIT_PRESTIGE": 300},
		"troops": 300,
		"forced_trait": "",
		"retainer_trait": "T_CHIVALROUS",
		"farm_level": 1,
		"granary_level": 1
	},
	"ORIGIN_FRONTIER_OFFICER": {
		"name_kr": "변방 무관",
		"stat_bonus": {"LEA": 7, "MAR": 7},
		"resources": {"GRAIN": 1200, "COIN": 600, "WOOD": 250, "IRON": 250, "HORSES": 50, "HERBS_WINE": 80, "WEAPONS": 80, "MERIT_PRESTIGE": 100},
		"troops": 500,
		"forced_trait": "",
		"retainer_trait": "T_FIERCE",
		"farm_level": 1,
		"granary_level": 1
	},
	"ORIGIN_PURE_SCHOLAR": {
		"name_kr": "청류 명사",
		"stat_bonus": {"INT": 8, "POL": 6},
		"resources": {"GRAIN": 1500, "COIN": 1200, "WOOD": 300, "IRON": 150, "HORSES": 10, "HERBS_WINE": 120, "WEAPONS": 30, "MERIT_PRESTIGE": 200},
		"troops": 200,
		"forced_trait": "",
		"retainer_trait": "T_SCHOLAR",
		"farm_level": 1,
		"granary_level": 1
	},
	"ORIGIN_CHIVALROUS_HERO": {
		"name_kr": "의협 호걸",
		"stat_bonus": {"MAR": 6, "CHA": 6},
		"resources": {"GRAIN": 1000, "COIN": 800, "WOOD": 250, "IRON": 200, "HORSES": 20, "HERBS_WINE": 100, "WEAPONS": 60, "MERIT_PRESTIGE": 150},
		"troops": 400,
		"forced_trait": "T_CHIVALROUS",
		"retainer_trait": "T_CAUTIOUS",
		"farm_level": 1,
		"granary_level": 1
	},
	"ORIGIN_AGRARIAN_GENTRY": {
		"name_kr": "둔전 호족",
		"stat_bonus": {"POL": 8, "LEA": 4},
		"resources": {"GRAIN": 3000, "COIN": 2000, "WOOD": 500, "IRON": 500, "HORSES": 20, "HERBS_WINE": 150, "WEAPONS": 50, "MERIT_PRESTIGE": 100},
		"troops": 300,
		"forced_trait": "T_AGRARIAN",
		"retainer_trait": "T_AGRARIAN",
		"farm_level": 2,
		"granary_level": 2
	}
}

const STARTING_PROVINCES: Dictionary = {
	"YOU_ZHOU": "jixian",
	"JI_ZHOU": "ye",
	"YU_ZHOU": "xuchang",
	"YAN_ZHOU": "puyang",
	"XU_ZHOU": "xiapi",
	"JING_ZHOU": "xiangyang",
	"YANG_ZHOU": "jianye",
	"YI_ZHOU": "chengdu",
	"YONG_LIANG": "changan"
}

const RHYTHM_SCHEDULES: Dictionary = {
	"EARLY_DISCIPLINE": [
		"SLEEP", "SLEEP", "SLEEP", "DRILL",
		"WORK", "WORK", "WORK", "WORK",
		"WORK", "RECREATION", "ANYTHING", "SLEEP"
	],
	"NIGHT_OWL": [
		"WORK", "SLEEP", "SLEEP", "SLEEP",
		"ANYTHING", "WORK", "WORK", "WORK",
		"RECREATION", "WORK", "WORK", "WORK"
	],
	"MARTIAL_DRILL": [
		"SLEEP", "SLEEP", "SLEEP", "DRILL",
		"DRILL", "DRILL", "WORK", "WORK",
		"WORK", "RECREATION", "ANYTHING", "SLEEP"
	],
	"SOCIAL_BANQUET": [
		"SLEEP", "SLEEP", "SLEEP", "ANYTHING",
		"WORK", "WORK", "WORK", "RECREATION",
		"WORK", "RECREATION", "RECREATION", "SLEEP"
	]
}

const RHYTHM_PRIORITIES: Dictionary = {
	"EARLY_DISCIPLINE": {
		"LOGISTICS": 1, "PATROL": 2, "AGRICULTURE": 1,
		"TRAINING": 3, "CRAFTING": 3, "RESEARCH": 3, "DIPLOMACY": 4
	},
	"NIGHT_OWL": {
		"LOGISTICS": 2, "PATROL": 3, "AGRICULTURE": 3,
		"TRAINING": 3, "CRAFTING": 2, "RESEARCH": 1, "DIPLOMACY": 2
	},
	"MARTIAL_DRILL": {
		"LOGISTICS": 2, "PATROL": 1, "AGRICULTURE": 3,
		"TRAINING": 1, "CRAFTING": 2, "RESEARCH": 4, "DIPLOMACY": 4
	},
	"SOCIAL_BANQUET": {
		"LOGISTICS": 2, "PATROL": 3, "AGRICULTURE": 2,
		"TRAINING": 3, "CRAFTING": 3, "RESEARCH": 3, "DIPLOMACY": 1
	}
}

const STANCE_DOCTRINES: Dictionary = {
	"AGGRESSIVE": {
		"engagement_stance": "PREEMPTIVE_STRIKE",
		"formation": "WEDGE_SPEAR",
		"supply_threshold_days": 5,
		"retreat_troop_bp": 2000,
		"retreat_morale_bp": 2000,
		"duel_policy": "ALWAYS_ACCEPT",
		"stratagem_policy": "FIRE_OR_FLOOD",
		"prisoner_policy": "RECRUIT_PERSUADE"
	},
	"CALCULATED": {
		"engagement_stance": "DEFENSIVE_HOLD",
		"formation": "CRANE_WING",
		"supply_threshold_days": 10,
		"retreat_troop_bp": 3000,
		"retreat_morale_bp": 2500,
		"duel_policy": "ACCEPT_IF_ADVANTAGE",
		"stratagem_policy": "AMBUSH_TRAP",
		"prisoner_policy": "RECRUIT_PERSUADE"
	},
	"DEFENSIVE_HOLD": {
		"engagement_stance": "DEFENSIVE_HOLD",
		"formation": "SQUARE_SHIELD",
		"supply_threshold_days": 15,
		"retreat_troop_bp": 5000,
		"retreat_morale_bp": 3000,
		"duel_policy": "DECLINE",
		"stratagem_policy": "PRESERVE_TROOPS",
		"prisoner_policy": "RANSOM"
	},
	"DIPLOMATIC_EVADE": {
		"engagement_stance": "EVADE_DISENGAGE",
		"formation": "SNAKE_COLUMN",
		"supply_threshold_days": 10,
		"retreat_troop_bp": 5000,
		"retreat_morale_bp": 3500,
		"duel_policy": "DECLINE",
		"stratagem_policy": "DISRUPT_CONFUSE",
		"prisoner_policy": "RELEASE_CHIVALROUS"
	}
}


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


static func _load_json_file(res_path: String) -> Variant:
	if not FileAccess.file_exists(res_path):
		return null
	var f: FileAccess = FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return null
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null:
		return null
	return DtoSchemas.normalize_json_ints(parsed)


static func load_interview_bank(res_path: String = "res://data/interview_questions.json") -> Dictionary:
	var raw: Variant = _load_json_file(res_path)
	if raw is Dictionary:
		var d: Dictionary = raw
		return d
	return _default_interview_bank()


static func load_officers_catalog(res_path: String = "res://data/officers_catalog.json") -> Array[Dictionary]:
	var raw: Variant = _load_json_file(res_path)
	var out: Array[Dictionary] = []
	if raw is Dictionary:
		var rd: Dictionary = raw
		var list_var: Variant = rd.get("officers", [])
		if list_var is Array:
			var arr: Array = list_var
			for item: Variant in arr:
				if item is Dictionary:
					var d: Dictionary = item
					out.append(d)
	elif raw is Array:
		var arr2: Array = raw
		for item2: Variant in arr2:
			if item2 is Dictionary:
				var d2: Dictionary = item2
				out.append(d2)
	return out


static func _default_interview_bank() -> Dictionary:
	return {
		"questions": [
			{
				"id": "Q1",
				"options": [
					{"stat_weights": {"LEA": 15, "INT": 10, "POL": 5}, "origin": "ORIGIN_FRONTIER_OFFICER"},
					{"stat_weights": {"MAR": 18, "LEA": 8}, "origin": "ORIGIN_CHIVALROUS_HERO"},
					{"stat_weights": {"CHA": 15, "INT": 10}, "origin": "ORIGIN_FALLEN_ROYAL"},
					{"stat_weights": {"POL": 16, "INT": 10}, "origin": "ORIGIN_AGRARIAN_GENTRY"}
				]
			},
			{
				"id": "Q2",
				"options": [
					{"stat_weights": {"CHA": 12, "MAR": 8}, "trait": "T_CHIVALROUS"},
					{"stat_weights": {"INT": 12, "LEA": 8}, "trait": "T_CAUTIOUS"},
					{"stat_weights": {"POL": 14, "LEA": 6}, "trait": "T_AGRARIAN"},
					{"stat_weights": {"MAR": 10, "POL": 10}, "trait": "T_AMBITIOUS"}
				]
			},
			{
				"id": "Q3",
				"options": [
					{"stat_weights": {"POL": 10, "CHA": 10}, "trait": "T_UNSELFISH"},
					{"stat_weights": {"INT": 14, "POL": 6}, "trait": "T_MYSTIC"},
					{"stat_weights": {"POL": 12, "MAR": 8}, "trait": "T_GREEDY"},
					{"stat_weights": {"CHA": 12, "INT": 8}, "trait": "T_SCHOLAR"}
				]
			},
			{
				"id": "Q4",
				"options": [
					{"stat_weights": {"MAR": 16, "LEA": 4}, "stance": "AGGRESSIVE", "trait": "T_FIERCE"},
					{"stat_weights": {"INT": 16, "LEA": 4}, "stance": "CALCULATED"},
					{"stat_weights": {"LEA": 16, "POL": 4}, "stance": "DEFENSIVE_HOLD"},
					{"stat_weights": {"CHA": 16, "POL": 4}, "stance": "DIPLOMATIC_EVADE"}
				]
			},
			{
				"id": "Q5",
				"options": [
					{"passion_votes": ["INT", "POL", "INT"]},
					{"passion_votes": ["MAR", "LEA", "MAR"]},
					{"passion_votes": ["POL", "LEA", "POL"]},
					{"passion_votes": ["CHA", "INT", "CHA"]}
				]
			},
			{
				"id": "Q6",
				"options": [
					{"trait": "T_AMBITIOUS"},
					{"trait": "T_DRINKER"},
					{"trait": "T_CAUTIOUS"},
					{"trait": "T_FIERCE"}
				]
			},
			{
				"id": "Q7",
				"options": [
					{"rhythm": "EARLY_DISCIPLINE"},
					{"rhythm": "NIGHT_OWL"},
					{"rhythm": "MARTIAL_DRILL"},
					{"rhythm": "SOCIAL_BANQUET"}
				]
			},
			{
				"id": "Q8",
				"options": [
					{"origin": "ORIGIN_AGRARIAN_GENTRY", "province": "YU_ZHOU"},
					{"origin": "ORIGIN_FRONTIER_OFFICER", "province": "YOU_ZHOU"},
					{"origin": "ORIGIN_PURE_SCHOLAR", "province": "JING_ZHOU"},
					{"origin": "ORIGIN_CHIVALROUS_HERO", "province": "XU_ZHOU"}
				]
			}
		]
	}


static func _compare_stat_weight_desc(a: int, b: int, weights: Array[int]) -> bool:
	var wa: int = weights[a]
	var wb: int = weights[b]
	if wa != wb:
		return wa > wb
	return a < b


static func _enforce_light_shadow_balance(trait_names: Array[String]) -> Array[String]:
	var indices: Array[int] = []
	for tn: String in trait_names:
		var idx: int = DtoSchemas.TRAIT_IDS.find(tn)
		if idx >= 0 and not indices.has(idx):
			indices.append(idx)
		if indices.size() >= 3:
			break

	if indices.is_empty():
		indices = [0, 2]
	elif indices.size() == 1:
		var first_idx: int = indices[0]
		if DtoSchemas.TRAIT_SHADOW_POOL.has(first_idx):
			indices.append(0)
		else:
			indices.append(2)

	var shadow_cnt: int = 0
	var net_cost: int = 0
	for idx: int in indices:
		if DtoSchemas.TRAIT_SHADOW_POOL.has(idx):
			shadow_cnt += 1
		net_cost += SealedTokenCodec.TRAIT_COSTS[idx]

	if shadow_cnt < 1:
		for cand_s: int in DtoSchemas.TRAIT_SHADOW_POOL:
			if not indices.has(cand_s):
				indices[indices.size() - 1] = cand_s
				break

	net_cost = 0
	for idx: int in indices:
		net_cost += SealedTokenCodec.TRAIT_COSTS[idx]

	if net_cost < -1:
		for cand_l: int in DtoSchemas.TRAIT_LIGHT_POOL:
			if not indices.has(cand_l):
				indices[0] = cand_l
				break
	elif net_cost > 1:
		for cand_s2: int in DtoSchemas.TRAIT_SHADOW_POOL:
			if not indices.has(cand_s2):
				indices[0] = cand_s2
				break

	var out: Array[String] = []
	for idx: int in indices:
		out.append(DtoSchemas.TRAIT_IDS[idx])
	return out


static func _score_interview_answers(
	answers: Array[int],
	interview_bank: Dictionary
) -> Dictionary:
	var stat_weights: Array[int] = [50, 50, 50, 50, 50]
	var passion_scores: Array[int] = [0, 0, 0, 0, 0]
	var candidate_traits: Array[String] = []
	var origin: String = "ORIGIN_CHIVALROUS_HERO"
	var rhythm: String = "EARLY_DISCIPLINE"
	var stance: String = "CALCULATED"
	var province: String = "YU_ZHOU"

	var q_list_var: Variant = interview_bank.get("questions", [])
	var q_list: Array = []
	if q_list_var is Array:
		q_list = q_list_var
	if q_list.is_empty():
		var fallback: Dictionary = _default_interview_bank()
		var fq_var: Variant = fallback.get("questions", [])
		if fq_var is Array:
			q_list = fq_var

	for qi: int in range(q_list.size()):
		var q_var: Variant = q_list[qi]
		if not (q_var is Dictionary):
			continue
		var qd: Dictionary = q_var
		var opts_var: Variant = qd.get("options", [])
		if not (opts_var is Array):
			continue
		var opts: Array = opts_var
		if opts.is_empty():
			continue
		var chosen_idx: int = 0
		if qi < answers.size():
			chosen_idx = clampi(answers[qi], 0, opts.size() - 1)
		var opt_var: Variant = opts[chosen_idx]
		if not (opt_var is Dictionary):
			continue
		var opt: Dictionary = opt_var

		var sw_var: Variant = opt.get("stat_weights", {})
		if sw_var is Dictionary:
			var sw: Dictionary = sw_var
			for si: int in range(5):
				var sk: String = DtoSchemas.STAT_KEYS[si]
				stat_weights[si] += _to_int(sw.get(sk, 0), 0)

		var pv_var: Variant = opt.get("passion_votes", [])
		if pv_var is Array:
			var pv: Array = pv_var
			for p_item: Variant in pv:
				var si_p: int = DtoSchemas.STAT_KEYS.find(str(p_item))
				if si_p >= 0:
					passion_scores[si_p] += 1

		var tr_str: String = str(opt.get("trait", ""))
		if DtoSchemas.TRAIT_IDS.has(tr_str) and not candidate_traits.has(tr_str):
			candidate_traits.append(tr_str)

		var org_str: String = str(opt.get("origin", ""))
		if DtoSchemas.ORIGIN_ARCHETYPES.has(org_str):
			origin = org_str

		var rhy_str: String = str(opt.get("rhythm", ""))
		if RHYTHM_SCHEDULES.has(rhy_str):
			rhythm = rhy_str

		var sta_str: String = str(opt.get("stance", ""))
		if STANCE_DOCTRINES.has(sta_str):
			stance = sta_str

		var prov_str: String = str(opt.get("province", ""))
		if STARTING_PROVINCES.has(prov_str):
			province = prov_str

	# Ensure top passion slots get votes from top stat weights if interview was short (5-scene fusion)
	for si: int in range(5):
		passion_scores[si] += stat_weights[si] / 10

	return {
		"stat_weights": stat_weights,
		"passion_scores": passion_scores,
		"traits": _enforce_light_shadow_balance(candidate_traits),
		"origin": origin,
		"rhythm": rhythm,
		"stance": stance,
		"province": province
	}


static func _allocate_passions(
	passion_scores: Array[int],
	ai_passion_alloc: Dictionary,
	use_ai_direct: bool
) -> Dictionary:
	var out: Dictionary = {}
	for sk: String in DtoSchemas.STAT_KEYS:
		out[sk] = PawnEntity.PASSION_NORMAL_PM

	if use_ai_direct and not ai_passion_alloc.is_empty():
		var used_pts: int = 0
		for k_var: Variant in ai_passion_alloc.keys():
			var idx: int = _to_int(k_var, -1)
			var pts: int = _to_int(ai_passion_alloc[k_var], 0)
			if idx >= 0 and idx < 5 and pts >= 1 and used_pts + pts <= DtoSchemas.PASSION_BUDGET:
				var sk: String = DtoSchemas.STAT_KEYS[idx]
				out[sk] = PawnEntity.PASSION_DOUBLE_PM if pts >= 2 else PawnEntity.PASSION_SINGLE_PM
				used_pts += pts
		if used_pts == DtoSchemas.PASSION_BUDGET:
			return out

	var order: Array[int] = [0, 1, 2, 3, 4]
	order.sort_custom(Callable(CharacterCreationEngine, "_compare_stat_weight_desc").bind(passion_scores))
	out[DtoSchemas.STAT_KEYS[order[0]]] = PawnEntity.PASSION_DOUBLE_PM
	out[DtoSchemas.STAT_KEYS[order[1]]] = PawnEntity.PASSION_SINGLE_PM
	return out


static func _apply_fine_tuning(
	base_stats: Dictionary,
	passions: Dictionary,
	fine_tuning: Dictionary
) -> void:
	# Standard pre-commit fine tuning: +-5 zero-sum stat shift preserving sum=320 & [35,85],
	# plus optional 1 passion swap.
	var shift_var: Variant = fine_tuning.get("stat_shift", {})
	if shift_var is Dictionary:
		var sd: Dictionary = shift_var
		var from_stat: String = str(sd.get("from", ""))
		var to_stat: String = str(sd.get("to", ""))
		var amount: int = clampi(_to_int(sd.get("amount", 0), 0), 0, 5)
		if amount > 0 and DtoSchemas.STAT_KEYS.has(from_stat) and DtoSchemas.STAT_KEYS.has(to_stat) and from_stat != to_stat:
			var cur_from: int = _to_int(base_stats.get(from_stat, 64), 64)
			var cur_to: int = _to_int(base_stats.get(to_stat, 64), 64)
			var max_movable: int = mini(amount, mini(cur_from - DtoSchemas.STAT_MIN_BASE, DtoSchemas.STAT_MAX_BASE - cur_to))
			if max_movable > 0:
				base_stats[from_stat] = cur_from - max_movable
				base_stats[to_stat] = cur_to + max_movable

	var pswap_var: Variant = fine_tuning.get("passion_swap", {})
	if pswap_var is Dictionary:
		var psd: Dictionary = pswap_var
		var from_p: String = str(psd.get("from", ""))
		var to_p: String = str(psd.get("to", ""))
		if DtoSchemas.STAT_KEYS.has(from_p) and DtoSchemas.STAT_KEYS.has(to_p) and from_p != to_p:
			var pm_from: int = _to_int(passions.get(from_p, PawnEntity.PASSION_NORMAL_PM), PawnEntity.PASSION_NORMAL_PM)
			var pm_to: int = _to_int(passions.get(to_p, PawnEntity.PASSION_NORMAL_PM), PawnEntity.PASSION_NORMAL_PM)
			if pm_from > PawnEntity.PASSION_NORMAL_PM and pm_to == PawnEntity.PASSION_NORMAL_PM:
				passions[from_p] = PawnEntity.PASSION_NORMAL_PM
				passions[to_p] = pm_from


static func _build_complementary_retainer(
	avatar: PawnEntity,
	origin_id: String,
	officers_catalog: Array[Dictionary],
	world_seed: int,
	tick_id: int
) -> PawnEntity:
	var lowest_stat: String = "MAR"
	var lowest_val: int = 999
	for sk: String in DtoSchemas.STAT_KEYS:
		var v: int = avatar.get_stat(sk)
		if v < lowest_val:
			lowest_val = v
			lowest_stat = sk

	var origin_info_var: Variant = ORIGIN_DATA.get(origin_id, {})
	var retainer_trait: String = "T_CAUTIOUS"
	if origin_info_var is Dictionary:
		var oid: Dictionary = origin_info_var
		retainer_trait = str(oid.get("retainer_trait", "T_CAUTIOUS"))
	if retainer_trait.is_empty():
		retainer_trait = "T_CAUTIOUS"

	var ret_name: String = "Zhao_Wei"
	for entry: Dictionary in officers_catalog:
		var best_key: String = str(entry.get("specialty_stat", ""))
		if best_key == lowest_stat:
			var cand_name: String = str(entry.get("name", ""))
			if not cand_name.is_empty():
				ret_name = cand_name
				break

	var ret: PawnEntity = PawnEntity.new(avatar.pawn_id + "_ret_01", ret_name, false)
	ret.origin_archetype = "ORIGIN_CHIVALROUS_HERO"
	var base_stats: Dictionary = {"LEA": 58, "MAR": 58, "INT": 58, "POL": 58, "CHA": 58}
	base_stats[lowest_stat] = 78
	var rem_diff: int = DtoSchemas.TOTAL_STAT_BUDGET - (58 * 4 + 78)
	if rem_diff > 0:
		base_stats["LEA"] = _to_int(base_stats["LEA"], 58) + rem_diff
	for sk: String in DtoSchemas.STAT_KEYS:
		ret.set_stat(sk, _to_int(base_stats[sk], 58))
	ret.set_passion_pm(lowest_stat, PawnEntity.PASSION_DOUBLE_PM)
	ret.traits = _enforce_light_shadow_balance([retainer_trait, "T_UNSELFISH"])
	ret.set_need("LOYALTY", 8000)
	ret.set_need("MORALE", 8000)
	ret.add_thought("SWORN_BOND_AFFINITY_40", 4, 72)

	# Copy schedule and invert/complement priority so lowest_stat domain is prioritized
	ret.daily_schedule = avatar.daily_schedule.duplicate()
	var domain_for_stat: String = "PATROL"
	match lowest_stat:
		"LEA":
			domain_for_stat = "PATROL"
		"MAR":
			domain_for_stat = "TRAINING"
		"INT":
			domain_for_stat = "RESEARCH"
		"POL":
			domain_for_stat = "AGRICULTURE"
		"CHA":
			domain_for_stat = "DIPLOMACY"
	ret.set_work_priority(domain_for_stat, 1)
	ret.set_work_priority("LOGISTICS", 2)
	var _roll: int = DeterministicRNG.roll_range(world_seed, tick_id, ret.get_entity_hash_id(), 101, 0, 99)
	return ret


static func create_character_and_manor(
	params: Dictionary,
	challenge_store: Dictionary,
	account_cooldown_until: Dictionary,
	account_tamper_strikes: Dictionary,
	world_seed: int = 18401,
	current_tick: int = 0
) -> Dictionary:
	var player_id: String = str(params.get("player_id", "player_01"))
	var avatar_name: String = str(params.get("avatar_name", "Nameless_Hero"))
	var requested_mode: String = str(params.get("creation_mode", "INTERVIEW_ONLY"))
	if not DtoSchemas.CREATION_MODES.has(requested_mode):
		requested_mode = "INTERVIEW_ONLY"

	var raw_answers: Array[int] = []
	var ans_var: Variant = params.get("interview_answers", [])
	if ans_var is Array:
		var ans_arr: Array = ans_var
		for item: Variant in ans_arr:
			raw_answers.append(_to_int(item, 0))

	var interview_bank: Dictionary = {}
	var bank_var: Variant = params.get("interview_bank", null)
	if bank_var is Dictionary:
		interview_bank = bank_var
	else:
		interview_bank = load_interview_bank()

	var officers_catalog: Array[Dictionary] = []
	var cat_var: Variant = params.get("officers_catalog", null)
	if cat_var is Array:
		var carr: Array = cat_var
		for item: Variant in carr:
			if item is Dictionary:
				var d: Dictionary = item
				officers_catalog.append(d)
	else:
		officers_catalog = load_officers_catalog()

	var sealed_token_text: String = str(params.get("sealed_token_input", ""))
	var effective_mode: String = requested_mode
	var audit_status: String = "NONE"
	var coercion_flag: String = "R0_CLEAN"
	var challenge_id_used: String = ""
	var beta_ai: int = 0
	var decoded_ai: Dictionary = {}

	if requested_mode == "FUSION_INTERVIEW" or requested_mode == "AI_DIRECT_WITH_CONFIRM":
		var decode_res: Dictionary = SealedTokenCodec.decode_and_verify(
			sealed_token_text,
			player_id,
			requested_mode,
			current_tick,
			challenge_store,
			account_cooldown_until,
			account_tamper_strikes
		)
		if not _to_bool(decode_res.get("ok", false), false):
			var err_code: String = str(decode_res.get("error_code", DtoSchemas.ERR_TOKEN_FORMAT))
			var err_data_var: Variant = decode_res.get("data", null)
			return {
				"ok": false,
				"error_code": err_code,
				"data": err_data_var
			}
		var d_var: Variant = decode_res.get("data", {})
		if d_var is Dictionary:
			decoded_ai = d_var
		effective_mode = str(decoded_ai.get("effective_mode", requested_mode))
		audit_status = str(decoded_ai.get("import_audit_status", "VERIFIED_CLEAN"))
		coercion_flag = str(decoded_ai.get("coercion_flag", "R0_CLEAN"))
		challenge_id_used = str(decoded_ai.get("challenge_id", ""))
		beta_ai = _to_int(decoded_ai.get("beta_ai", 4000), 4000)

	var iv_data: Dictionary = _score_interview_answers(raw_answers, interview_bank)
	var iv_weights_var: Variant = iv_data.get("stat_weights", [50, 50, 50, 50, 50])
	var iv_weights: Array[int] = [50, 50, 50, 50, 50]
	if iv_weights_var is Array:
		var iwa: Array = iv_weights_var
		for i: int in range(mini(5, iwa.size())):
			iv_weights[i] = _to_int(iwa[i], 50)

	var blended_weights: Array[int] = [0, 0, 0, 0, 0]
	if beta_ai > 0 and not decoded_ai.is_empty():
		var ai_rw_var: Variant = decoded_ai.get("raw_weights", [60, 60, 60, 60, 60])
		var ai_rw: Array[int] = [60, 60, 60, 60, 60]
		if ai_rw_var is Array:
			var arwa: Array = ai_rw_var
			for i: int in range(mini(5, arwa.size())):
				ai_rw[i] = _to_int(arwa[i], 60)
		var beta_iv: int = DtoSchemas.SCALE_BP - beta_ai
		for i: int in range(5):
			@warning_ignore("integer_division")
			blended_weights[i] = (beta_ai * ai_rw[i] + beta_iv * iv_weights[i]) / DtoSchemas.SCALE_BP
	else:
		blended_weights = iv_weights.duplicate()

	var normalized_stats_arr: Array[int] = SealedTokenCodec.normalize_weights_320(blended_weights)
	var base_stats: Dictionary = {}
	for i: int in range(5):
		base_stats[DtoSchemas.STAT_KEYS[i]] = normalized_stats_arr[i]

	var iv_p_scores_var: Variant = iv_data.get("passion_scores", [1, 1, 1, 1, 1])
	var iv_p_scores: Array[int] = [1, 1, 1, 1, 1]
	if iv_p_scores_var is Array:
		var ipsa: Array = iv_p_scores_var
		for i: int in range(mini(5, ipsa.size())):
			iv_p_scores[i] = _to_int(ipsa[i], 1)

	var ai_p_alloc: Dictionary = {}
	var aipa_var: Variant = decoded_ai.get("passion_alloc", {})
	if aipa_var is Dictionary:
		ai_p_alloc = aipa_var

	var passions: Dictionary = _allocate_passions(
		iv_p_scores,
		ai_p_alloc,
		effective_mode == "AI_DIRECT_WITH_CONFIRM"
	)

	var fine_tuning: Dictionary = {}
	var ft_var: Variant = params.get("fine_tuning", {})
	if ft_var is Dictionary:
		fine_tuning = ft_var
	_apply_fine_tuning(base_stats, passions, fine_tuning)

	# Determine origin, traits, rhythm, stance, province
	var origin_id: String = str(params.get("origin_override", ""))
	if not DtoSchemas.ORIGIN_ARCHETYPES.has(origin_id):
		if not decoded_ai.is_empty() and effective_mode == "AI_DIRECT_WITH_CONFIRM":
			origin_id = str(decoded_ai.get("origin_hint", "ORIGIN_CHIVALROUS_HERO"))
		else:
			origin_id = str(iv_data.get("origin", "ORIGIN_CHIVALROUS_HERO"))
	if not DtoSchemas.ORIGIN_ARCHETYPES.has(origin_id):
		origin_id = "ORIGIN_CHIVALROUS_HERO"

	var province_id: String = str(params.get("province_override", ""))
	if not STARTING_PROVINCES.has(province_id):
		province_id = str(iv_data.get("province", "YU_ZHOU"))
	if not STARTING_PROVINCES.has(province_id):
		province_id = "YU_ZHOU"

	var rhythm_code: String = str(decoded_ai.get("rhythm_code", iv_data.get("rhythm", "EARLY_DISCIPLINE")))
	if not RHYTHM_SCHEDULES.has(rhythm_code):
		rhythm_code = "EARLY_DISCIPLINE"

	var stance_code: String = str(decoded_ai.get("stance_code", iv_data.get("stance", "CALCULATED")))
	if not STANCE_DOCTRINES.has(stance_code):
		stance_code = "CALCULATED"

	var raw_traits: Array[String] = []
	if not decoded_ai.is_empty():
		var dt_var: Variant = decoded_ai.get("traits", [])
		if dt_var is Array:
			var dta: Array = dt_var
			for t_item: Variant in dta:
				raw_traits.append(str(t_item))
	else:
		var ivt_var: Variant = iv_data.get("traits", [])
		if ivt_var is Array:
			var ivta: Array = ivt_var
			for t_item: Variant in ivta:
				raw_traits.append(str(t_item))

	var origin_dict_var: Variant = ORIGIN_DATA.get(origin_id, {})
	var origin_dict: Dictionary = {}
	if origin_dict_var is Dictionary:
		origin_dict = origin_dict_var

	var forced_trait: String = str(origin_dict.get("forced_trait", ""))
	if not forced_trait.is_empty() and not raw_traits.has(forced_trait):
		raw_traits.insert(0, forced_trait)
	var final_traits: Array[String] = _enforce_light_shadow_balance(raw_traits)

	# Build Avatar Pawn
	var avatar: PawnEntity = PawnEntity.new(player_id + "_avatar", avatar_name, true)
	avatar.owner_player_id = player_id
	avatar.origin_archetype = origin_id
	avatar.traits = final_traits

	var lore_dict: Dictionary = {}
	var lore_var: Variant = decoded_ai.get("lore", {})
	if lore_var is Dictionary:
		lore_dict = lore_var
	avatar.courtesy_name = str(lore_dict.get("courtesy_name", ""))
	avatar.epithet = str(lore_dict.get("epithet", "난세의 입세자"))

	# Apply origin stat bonuses (capped at 95 during creation)
	var ob_var: Variant = origin_dict.get("stat_bonus", {})
	var ob: Dictionary = ob_var if ob_var is Dictionary else {}
	for sk: String in DtoSchemas.STAT_KEYS:
		var b_val: int = _to_int(base_stats.get(sk, 64), 64)
		var bonus: int = _to_int(ob.get(sk, 0), 0)
		avatar.set_stat(sk, mini(95, b_val + bonus))
		avatar.set_passion_pm(sk, _to_int(passions.get(sk, PawnEntity.PASSION_NORMAL_PM), PawnEntity.PASSION_NORMAL_PM))

	# Seed initial schedule & work priorities
	var sched_var: Variant = RHYTHM_SCHEDULES.get(rhythm_code, [])
	if sched_var is Array:
		var sa: Array = sched_var
		for si: int in range(mini(12, sa.size())):
			avatar.set_schedule_activity(si, str(sa[si]))

	var prio_var: Variant = RHYTHM_PRIORITIES.get(rhythm_code, {})
	if prio_var is Dictionary:
		var pd: Dictionary = prio_var
		for dk: String in PawnEntity.WORK_DOMAINS:
			avatar.set_work_priority(dk, _to_int(pd.get(dk, 2), 2))

	# Opening Thought (+4 Mood, 72 ticks; within +-5 Mood guardrail)
	var opening_mood: int = 4
	if effective_mode == "FUSION_INTERVIEW" and not decoded_ai.is_empty():
		var iv_stance: String = str(iv_data.get("stance", stance_code))
		if iv_stance != stance_code:
			opening_mood = 5
	avatar.add_thought("OPENING_DESTINY", opening_mood, 72)
	var _m: int = avatar.step_mood(0, 1)

	# Build Personal Manor
	var manor: ManorState = ManorState.new("manor_" + player_id, player_id)
	manor.starting_province = province_id
	manor.host_node_id = str(STARTING_PROVINCES.get(province_id, "xuchang"))
	var doc_var: Variant = STANCE_DOCTRINES.get(stance_code, {})
	if doc_var is Dictionary:
		var dd: Dictionary = doc_var
		for dk_doc: Variant in dd.keys():
			manor.standing_doctrine[str(dk_doc)] = dd[dk_doc]

	# Apply origin resources & buildings (Zero bonus resources from Track B AI token: H4!)
	var ores_var: Variant = origin_dict.get("resources", {})
	if ores_var is Dictionary:
		var ores: Dictionary = ores_var
		for rk: String in DtoSchemas.RESOURCE_KEYS:
			manor.set_resource(rk, _to_int(ores.get(rk, 0), 0))
	manor.household_troops = _to_int(origin_dict.get("troops", 300), 300)
	manor.set_building_level("MILITARY_FARM", _to_int(origin_dict.get("farm_level", 1), 1))
	manor.set_building_level("GRANARY_VAULT", _to_int(origin_dict.get("granary_level", 1), 1))

	var _ok_av: bool = manor.add_pawn(avatar)
	var retainer: PawnEntity = _build_complementary_retainer(
		avatar, origin_id, officers_catalog, world_seed, current_tick
	)
	var _ok_ret: bool = manor.add_pawn(retainer)

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"creation_mode": effective_mode,
		"import_audit_status": audit_status,
		"coercion_flag": coercion_flag,
		"challenge_id": challenge_id_used,
		"base_stats_320": base_stats,
		"avatar": avatar,
		"retainer": retainer,
		"manor": manor,
		"retainer_affinity": 40
	}
