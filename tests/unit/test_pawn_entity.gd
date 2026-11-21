class_name TestPawnEntity
extends HarnessTestCase


func _as_int(v: Variant, fallback: int = 0) -> int:
	if v is int:
		var iv: int = v
		return iv
	if v is float:
		var fv: float = v
		return int(fv)
	return fallback


func _make_pawn(p_id: String = "p_test", p_name: String = "TestPawn") -> PawnEntity:
	var p: PawnEntity = PawnEntity.new(p_id, p_name, false)
	p.manor_id = "manor_01"
	p.owner_player_id = "player_01"
	return p


func test_five_stats_bounds_and_effective_modifiers() -> void:
	var p: PawnEntity = _make_pawn()
	assert_eq(PawnEntity.STAT_KEYS.size(), 5, "Must define 5 canonical stats")
	for sk: String in PawnEntity.STAT_KEYS:
		p.set_stat(sk, 0)
		assert_eq(p.get_stat(sk), 1, "%s lower bound must clamp to 1" % sk)
		p.set_stat(sk, 999)
		assert_eq(p.get_stat(sk), 120, "%s upper bound must clamp to 120" % sk)

	p.set_stat("INVALID_STAT", 99)
	assert_false(p.stats.has("INVALID_STAT"), "Unknown stat key must be ignored")

	p.set_stat("MAR", 70)
	p.set_stat("LEA", 60)
	p.set_stat("INT", 65)
	p.traits = ["T_FIERCE", "T_CHIVALROUS"]
	# T_FIERCE: MAR +8, INT -6; T_CHIVALROUS: CHA +5, MAR +3 => MAR = 70 + 11 = 81, INT = 59
	assert_eq(p.get_effective_stat("MAR"), 81, "Effective MAR stacks T_FIERCE (+8) and T_CHIVALROUS (+3)")
	assert_eq(p.get_effective_stat("INT"), 59, "Effective INT applies T_FIERCE (-6)")

	# AWAKENED_VALOR adds +15 MAR and +10 LEA, still clamped at 120
	p.mental_state = "AWAKENED_VALOR"
	assert_eq(p.get_effective_stat("MAR"), 96, "AWAKENED_VALOR adds +15 MAR")
	assert_eq(p.get_effective_stat("LEA"), 70, "AWAKENED_VALOR adds +10 LEA")

	p.set_stat("MAR", 115)
	assert_eq(p.get_effective_stat("MAR"), 120, "Effective stat must clamp at 120")
	p.set_stat("INT", 2)
	assert_eq(p.get_effective_stat("INT"), 1, "Effective stat must clamp at minimum 1")


func test_passion_xp_growth_and_level_up_progression() -> void:
	assert_eq(PawnEntity.PASSION_DULL_PM, 750, "Dull passion must be 750 pm")
	assert_eq(PawnEntity.PASSION_NORMAL_PM, 1000, "Normal passion must be 1000 pm")
	assert_eq(PawnEntity.PASSION_SINGLE_PM, 1250, "Single passion must be 1250 pm")
	assert_eq(PawnEntity.PASSION_DOUBLE_PM, 1500, "Double passion must be 1500 pm")

	# Verify xp_required_for_next curve
	assert_eq(PawnEntity.xp_required_for_next(50), 100, "XP required at stat 50 must be 100")
	assert_eq(PawnEntity.xp_required_for_next(1), 50, "XP required at very low stat floors at 50")
	assert_gt(PawnEntity.xp_required_for_next(80), PawnEntity.xp_required_for_next(60), "Higher stat requires more XP")
	assert_eq(PawnEntity.xp_required_for_next(120), 999999999, "Stat 120 is capped")

	var p_dull: PawnEntity = _make_pawn("p_dull")
	var p_norm: PawnEntity = _make_pawn("p_norm")
	var p_single: PawnEntity = _make_pawn("p_single")
	var p_double: PawnEntity = _make_pawn("p_double")

	var group: Array[PawnEntity] = [p_dull, p_norm, p_single, p_double]
	var pms: Array[int] = [750, 1000, 1250, 1500]
	for idx: int in range(4):
		var pawn: PawnEntity = group[idx]
		pawn.set_stat("MAR", 50)
		pawn.mood = 50
		pawn.set_passion_pm("MAR", pms[idx])
		var _lvl: bool = pawn.add_stat_xp("MAR", 40)

	assert_eq(_as_int(p_dull.stat_xp.get("MAR", 0)), 30, "750 pm * 40 base XP == 30")
	assert_eq(_as_int(p_norm.stat_xp.get("MAR", 0)), 40, "1000 pm * 40 base XP == 40")
	assert_eq(_as_int(p_single.stat_xp.get("MAR", 0)), 50, "1250 pm * 40 base XP == 50")
	assert_eq(_as_int(p_double.stat_xp.get("MAR", 0)), 60, "1500 pm * 40 base XP == 60")

	# Invalid passion pm rejected
	p_norm.set_passion_pm("MAR", 999)
	assert_eq(p_norm.get_passion_pm("MAR"), 1000, "Invalid passion pm must be ignored")

	# Mood > 50 bonus & multi-level progression
	p_double.mood = 90  # mood_bonus_pm = 1000 + 5 * 40 = 1200; 1500*1200/1000 = 1800 pm
	var leveled: bool = p_double.add_stat_xp("MAR", 200)
	assert_true(leveled, "Adding enough XP must trigger level up")
	assert_gt(p_double.get_stat("MAR"), 50, "MAR stat must increase on level up")

	# At 120 cap, add_stat_xp returns false
	p_double.set_stat("MAR", 120)
	assert_false(p_double.add_stat_xp("MAR", 5000), "Cannot level beyond 120")
	assert_false(p_double.add_stat_xp("MAR", 0), "Zero XP cannot level up")
	assert_false(p_double.add_stat_xp("BAD_STAT", 500), "Invalid stat key returns false")


func test_all_ten_traits_and_modifiers() -> void:
	assert_eq(DtoSchemas.TRAIT_IDS.size(), 10, "Canonical domain defines 10 traits")
	for tid: String in DtoSchemas.TRAIT_IDS:
		assert_has_key(PawnEntity.TRAIT_STAT_MODS, tid, "TRAIT_STAT_MODS must define %s" % tid)

	var p_unselfish: PawnEntity = _make_pawn("u")
	p_unselfish.traits = ["T_UNSELFISH"]
	assert_eq(p_unselfish.get_stipend_multiplier_pm(), 500, "T_UNSELFISH stipend == 0.5x (500 pm)")
	assert_true(p_unselfish.immune_to_bribery(), "T_UNSELFISH must be immune to bribery")
	assert_false(p_unselfish.needs_wine(), "T_UNSELFISH does not need wine")

	var p_greedy: PawnEntity = _make_pawn("g")
	p_greedy.traits = ["T_GREEDY"]
	assert_eq(p_greedy.get_stipend_multiplier_pm(), 2000, "T_GREEDY stipend == 2.0x (2000 pm)")
	assert_false(p_greedy.immune_to_bribery(), "T_GREEDY is not immune to bribery")

	var p_chiv: PawnEntity = _make_pawn("c")
	p_chiv.traits = ["T_CHIVALROUS"]
	assert_eq(p_chiv.get_stipend_multiplier_pm(), 800, "T_CHIVALROUS stipend == 800 pm")
	assert_true(p_chiv.refuses_assassination(), "T_CHIVALROUS refuses assassination")

	var p_amb: PawnEntity = _make_pawn("a")
	p_amb.traits = ["T_AMBITIOUS"]
	assert_eq(p_amb.get_stipend_multiplier_pm(), 1300, "T_AMBITIOUS stipend == 1300 pm")
	assert_eq(p_amb.get_ambition_drift_mult_pm(), 1750, "T_AMBITIOUS ambition drift == 1750 pm")

	var p_cautious: PawnEntity = _make_pawn("cau")
	p_cautious.traits = ["T_CAUTIOUS"]
	assert_true(p_cautious.refuses_reckless_duel(), "T_CAUTIOUS refuses reckless duel")
	assert_eq(p_cautious.get_retreat_threshold_bonus_bp(), 1500, "T_CAUTIOUS retreat bonus == +1500 bp")

	var p_fierce: PawnEntity = _make_pawn("f")
	p_fierce.traits = ["T_FIERCE"]
	assert_eq(p_fierce.get_retreat_threshold_bonus_bp(), -1500, "T_FIERCE retreat bonus == -1500 bp")

	var p_drinker: PawnEntity = _make_pawn("d")
	p_drinker.traits = ["T_DRINKER"]
	assert_true(p_drinker.needs_wine(), "T_DRINKER needs wine")

	var p_agrarian: PawnEntity = _make_pawn("ag")
	p_agrarian.traits = ["T_AGRARIAN"]
	assert_eq(p_agrarian.get_work_efficiency_pm("AGRICULTURE"), 1350, "T_AGRARIAN gives 1350 pm on AGRICULTURE")
	assert_eq(p_agrarian.get_work_efficiency_pm("PATROL"), 1000, "T_AGRARIAN neutral on PATROL")

	var p_mystic: PawnEntity = _make_pawn("my")
	p_mystic.traits = ["T_MYSTIC"]
	assert_eq(p_mystic.get_work_efficiency_pm("RESEARCH"), 1350, "T_MYSTIC gives 1350 pm on RESEARCH")

	var p_scholar: PawnEntity = _make_pawn("sc")
	p_scholar.traits = ["T_SCHOLAR"]
	p_scholar.set_stat("INT", 60)
	p_scholar.set_stat("CHA", 60)
	p_scholar.set_stat("MAR", 60)
	assert_eq(p_scholar.get_effective_stat("INT"), 64, "T_SCHOLAR gives +4 INT")
	assert_eq(p_scholar.get_effective_stat("CHA"), 67, "T_SCHOLAR gives +7 CHA")
	assert_eq(p_scholar.get_effective_stat("MAR"), 52, "T_SCHOLAR gives -8 MAR")


func test_needs_clamping_thoughts_and_smooth_mood_interpolation() -> void:
	var p: PawnEntity = _make_pawn()
	for nk: String in PawnEntity.NEED_KEYS:
		p.set_need(nk, -500)
		assert_eq(p.get_need(nk), 0, "%s clamps lower bound to 0" % nk)
		p.set_need(nk, 15000)
		assert_eq(p.get_need(nk), 10000, "%s clamps upper bound to 10000" % nk)

	p.add_need("FOOD", -3000)
	assert_eq(p.get_need("FOOD"), 7000, "add_need subtracts accurately")
	p.set_need("BAD_NEED", 100)
	assert_false(p.needs_bp.has("BAD_NEED"), "Unknown need key ignored")

	# Timed Thoughts
	p.add_thought("T_POSITIVE", 15, 2)
	p.add_thought("", 10, 5)
	p.add_thought("T_ZERO", 10, 0)
	assert_true(p.has_thought("T_POSITIVE"), "Valid thought added")
	assert_false(p.has_thought(""), "Empty thought id rejected")
	assert_false(p.has_thought("T_ZERO"), "Non-positive duration thought rejected")
	assert_eq(p.compute_thoughts_mood_delta(), 15, "Thoughts delta == 15")

	# Overwriting thought updates duration/delta rather than duplicating
	p.add_thought("T_POSITIVE", 20, 3)
	assert_eq(p.thoughts.size(), 1, "Updating thought must not duplicate entry")
	assert_eq(p.compute_thoughts_mood_delta(), 20, "Updated thought delta == 20")

	p.tick_thoughts()
	assert_true(p.has_thought("T_POSITIVE"), "Thought remains after 1 tick (2 left)")
	p.tick_thoughts()
	p.tick_thoughts()
	assert_false(p.has_thought("T_POSITIVE"), "Thought expires after 3 ticks")

	# Smooth Mood interpolation: max delta 4 per tick
	p.set_need("FOOD", 500)       # -25
	p.set_need("REST", 500)       # -20
	p.set_need("MORALE", 500)     # -15
	p.set_need("AMBITION", 500)   # -18 -> total needs delta = -78 -> target mood = 0
	p.mood = 60
	var m1: int = p.step_mood(0, 1)
	assert_eq(p.mood_target, 0, "Target mood clamped to 0")
	assert_eq(m1, 56, "Mood must drop by at most 4 per tick (60 -> 56)")
	var m2: int = p.step_mood(0, 1)
	assert_eq(m2, 52, "Second tick drops by 4 (56 -> 52)")

	# Positive interpolation bounded by +4 per tick
	p.set_need("FOOD", 9500)      # +8
	p.set_need("REST", 9500)      # +6
	p.set_need("MORALE", 9500)    # +10
	p.set_need("AMBITION", 9000)  # 0 -> target = 74
	p.mood = 52
	var m3: int = p.step_mood(0, 1)
	assert_eq(p.mood_target, 74, "Target mood computed from positive needs")
	assert_eq(m3, 56, "Mood must rise by at most 4 per tick (52 -> 56)")


func test_mental_break_tiers_and_guardrail2_catharsis() -> void:
	# Guardrail #2: immediate +35 Mood Catharsis buffer on end_mental_break()
	var p: PawnEntity = _make_pawn("p_brk")
	p.mood = 25
	p.trigger_mental_break("BREAK_MINOR_BINGE", 1)
	assert_true(p.is_in_mental_break(), "Pawn must be in mental break state")

	p.end_mental_break(0)
	assert_false(p.is_in_mental_break(), "Pawn exits mental break on end_mental_break")
	assert_eq(p.mental_state, "CATHARSIS", "Mental state transitions to CATHARSIS")
	assert_eq(p.mental_state_ticks, 48, "Catharsis duration must be 48 ticks")
	assert_true(p.has_thought("CATHARSIS"), "CATHARSIS thought must be immediately added")
	assert_eq(p.hangover_ticks, 12, "Ending BREAK_MINOR_BINGE applies 12-tick hangover")
	assert_eq(p.get_work_efficiency_pm("AGRICULTURE"), 750, "Hangover reduces work efficiency to 750 pm")

	var catharsis_delta: int = 0
	for entry: Dictionary in p.thoughts:
		if str(entry.get("id", "")) == "CATHARSIS":
			catharsis_delta = _as_int(entry.get("mood_delta", 0))
	assert_eq(catharsis_delta, 35, "Guardrail #2: Catharsis thought must grant immediate +35 Mood")
	assert_gte(p.mood_target, 85, "Immediate mood_target reflects +35 Catharsis bonus")

	# Verify no break triggers while in CATHARSIS or ON_EXPEDITION
	p.mood = 5
	for t: int in range(1, 10):
		var evs_cath: Array[String] = p.step_mental_and_awakening(18401, t, -50, 1)
		assert_false(p.is_in_mental_break(), "Cannot trigger mental break during CATHARSIS")
		assert_eq(evs_cath.size(), 0, "No break event during active CATHARSIS")

	# Verify break classification tiers: Minor (<35), Major (<20), Extreme (<10)
	var saw_minor: bool = false
	var saw_major: bool = false
	var saw_extreme_mutiny: bool = false
	var saw_extreme_desert: bool = false

	for seed_offset: int in range(1, 80):
		var pm: PawnEntity = _make_pawn("minor_%d" % seed_offset)
		pm.mood = 28
		pm.set_need("FOOD", 2000)
		pm.set_need("REST", 2000)
		pm.set_need("MORALE", 2000)
		var evs: Array[String] = pm.step_mental_and_awakening(18401 + seed_offset, 100 + seed_offset, -10, 1)
		if not evs.is_empty():
			var ev_name: String = evs[0]
			if ev_name == "BREAK_MINOR_BINGE" or ev_name == "BREAK_MINOR_SECLUSION":
				saw_minor = true
				break

	for seed_offset: int in range(1, 80):
		var pmaj: PawnEntity = _make_pawn("major_%d" % seed_offset)
		pmaj.mood = 15
		pmaj.set_need("FOOD", 1000)
		pmaj.set_need("REST", 1000)
		var evs: Array[String] = pmaj.step_mental_and_awakening(28401 + seed_offset, 200 + seed_offset, -20, 1)
		if not evs.is_empty():
			var ev_name: String = evs[0]
			if ev_name == "BREAK_MAJOR_CHARGE" or ev_name == "BREAK_MAJOR_EMBEZZLE":
				saw_major = true
				break

	for seed_offset: int in range(1, 80):
		var pext: PawnEntity = _make_pawn("ext_%d" % seed_offset)
		pext.mood = 5
		pext.set_need("FOOD", 500)
		pext.set_need("REST", 500)
		pext.set_need("LOYALTY", 1000)
		var evs: Array[String] = pext.step_mental_and_awakening(38401 + seed_offset, 300 + seed_offset, -30, 1)
		if not evs.is_empty():
			if evs[0] == "BREAK_EXTREME_MUTINY":
				saw_extreme_mutiny = true
			elif evs[0] == "BREAK_EXTREME_DESERTION":
				saw_extreme_desert = true
		if saw_extreme_mutiny and saw_extreme_desert:
			break

	assert_true(saw_minor, "Mood < 35 must trigger Minor mental break tier")
	assert_true(saw_major, "Mood < 20 must trigger Major mental break tier")
	assert_true(saw_extreme_mutiny, "Mood < 10 with low loyalty must trigger BREAK_EXTREME_MUTINY")
	assert_true(saw_extreme_desert, "Mood < 10 must trigger BREAK_EXTREME_DESERTION")

	# External pawn (ON_EXPEDITION) never enters manor mental break
	var p_ext_state: PawnEntity = _make_pawn("p_away")
	p_ext_state.state = "ON_EXPEDITION"
	p_ext_state.mood = 2
	p_ext_state.set_need("FOOD", 0)
	for t: int in range(1, 30):
		var _evs_away: Array[String] = p_ext_state.step_mental_and_awakening(18401, t, -40, 1)
		assert_false(p_ext_state.is_in_mental_break(), "ON_EXPEDITION pawn must not trigger manor mental break")


func test_heroic_awakening_and_wounds_and_serialization() -> void:
	var p: PawnEntity = _make_pawn("p_awake")
	p.set_need("FOOD", 9500)
	p.set_need("REST", 9500)
	p.set_need("MORALE", 9500)
	p.set_need("AMBITION", 9000)
	p.add_thought("VICTORY_GLORY", 25, 100)
	p.mood = 92

	# Before 12 ticks, cannot awaken
	for t: int in range(1, 12):
		var evs_early: Array[String] = p.step_mental_and_awakening(18401, t, 10, 1)
		assert_false(p.is_awakened(), "Cannot awaken before 12 sustained ticks (tick %d)" % t)
		assert_eq(evs_early.size(), 0, "No awakening event before 12 ticks")
	assert_eq(p.high_mood_streak_ticks, 11, "High mood streak tracked accurately")

	# Continue from tick 12 to 24 (guaranteed at streak >= 24)
	var awakened_event: String = ""
	for t: int in range(12, 26):
		var evs: Array[String] = p.step_mental_and_awakening(18401, t, 10, 1)
		if not evs.is_empty():
			awakened_event = evs[0]
			break

	assert_true(p.is_awakened(), "Sustained Mood > 85 for 12..24 ticks must trigger Heroic Awakening")
	assert_true(PawnEntity.AWAKENED_STATES.has(awakened_event), "Event must be a valid AWAKENED_* state")
	assert_eq(p.mental_state_ticks, 24, "Awakening lasts 24 ticks")
	assert_eq(p.high_mood_streak_ticks, 0, "Streak resets on awakening")

	# AWAKENED_STRATAGEM work efficiency boost
	p.mental_state = "AWAKENED_STRATAGEM"
	assert_eq(p.get_work_efficiency_pm("RESEARCH"), 2500, "AWAKENED_STRATAGEM boosts RESEARCH to 2500 pm")

	# Health/Wounds efficiency & serialization
	p.mental_state = "NORMAL"
	p.health_state = "LIGHT_WOUND"
	assert_eq(p.get_work_efficiency_pm("PATROL"), 850, "LIGHT_WOUND reduces work efficiency to 850 pm")
	p.health_state = "SEVERE_WOUND"
	assert_eq(p.get_work_efficiency_pm("PATROL"), 550, "SEVERE_WOUND reduces work efficiency to 550 pm")
	p.health_state = "SCARRED"
	p.scar_count = 1
	assert_eq(p.get_work_efficiency_pm("PATROL"), 1000, "SCARRED has 1000 pm base efficiency")

	p.set_work_priority("RESEARCH", 1)
	p.set_schedule_activity(5, "DRILL")
	p.offline_bribe_immune_until_tick = 420
	var d: Dictionary = p.to_dict()
	assert_true(StateHasher.validate_deterministic_types(d), "PawnEntity.to_dict() must contain only deterministic types")
	assert_false(StateHasher.has_floats(d), "PawnEntity.to_dict() must contain zero floats")

	var restored: PawnEntity = PawnEntity.from_dict(d)
	assert_eq(StateHasher.crc32_dict(restored.to_dict()), StateHasher.crc32_dict(d), "Round-trip CRC32 must match identically")
	assert_eq(restored.health_state, "SCARRED", "Health state preserved")
	assert_eq(restored.scar_count, 1, "Scar count preserved")
	assert_eq(restored.offline_bribe_immune_until_tick, 420, "Bribe immunity tick preserved")
	assert_eq(restored.get_schedule_activity(5), "DRILL", "Schedule preserved")
	assert_eq(restored.get_work_priority("RESEARCH"), 1, "Work priority preserved")
