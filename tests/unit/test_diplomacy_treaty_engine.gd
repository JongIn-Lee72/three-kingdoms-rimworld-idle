class_name TestDiplomacyTreatyEngine
extends HarnessTestCase


func _as_int(v: Variant, fallback: int = 0) -> int:
	if v is int:
		var iv: int = v
		return iv
	if v is float:
		var fv: float = v
		return int(fv)
	return fallback


func _as_bool(v: Variant, fallback: bool = false) -> bool:
	if v is bool:
		var bv: bool = v
		return bv
	return fallback


func _as_array(v: Variant) -> Array:
	if v is Array:
		var a: Array = v
		return a
	return []


func _make_world_and_factions() -> Dictionary:
	var wg: WorldGraph = WorldGraph.new({
		"nodes": [
			{"node_id": "n_a", "name_ko": "A", "province": "YU_ZHOU", "security_bp": 7000, "bandit_pressure_bp": 200},
			{"node_id": "n_b", "name_ko": "B", "province": "YU_ZHOU", "security_bp": 7000, "bandit_pressure_bp": 200},
			{"node_id": "n_c", "name_ko": "C", "province": "YU_ZHOU", "security_bp": 7000, "bandit_pressure_bp": 200}
		],
		"edges": []
	}, false)
	var mgr: FactionManager = FactionManager.new()
	var _fa: Dictionary = mgr.create_faction("f_a", "Alpha", "lord_a", "n_a", wg, 3000, 3000)
	var _fb: Dictionary = mgr.create_faction("f_b", "Beta", "lord_b", "n_b", wg, 1000, 1000)
	var _fc: Dictionary = mgr.create_faction("f_c", "Gamma", "lord_c", "n_c", wg, 2000, 2000)
	return {"wg": wg, "mgr": mgr}


func test_treaty_signing_queries_tribute_settlement_and_expiry() -> void:
	var env: Dictionary = _make_world_and_factions()
	var v_mgr: Variant = env["mgr"]
	var mgr: FactionManager = v_mgr
	var eng: DiplomacyTreatyEngine = DiplomacyTreatyEngine.new()
	var clk: SimClock = SimClock.new(24)

	# Validation rejections
	var bad_self: Dictionary = eng.propose_and_sign_treaty("f_a", "f_a", "ALLIANCE", 5, clk)
	assert_false(_as_bool(bad_self.get("ok", true), true), "Self-treaty rejected")
	var bad_type: Dictionary = eng.propose_and_sign_treaty("f_a", "f_b", "VASSALAGE", 5, clk)
	assert_false(_as_bool(bad_type.get("ok", true), true), "Invalid treaty type rejected")
	var bad_dur: Dictionary = eng.propose_and_sign_treaty("f_a", "f_b", "ALLIANCE", 0, clk)
	assert_false(_as_bool(bad_dur.get("ok", true), true), "Zero duration rejected")

	# Sign all 4 canonical treaty types
	var t_all: Dictionary = eng.propose_and_sign_treaty("f_a", "f_b", "ALLIANCE", 10, clk)
	assert_true(_as_bool(t_all.get("ok", false), false), "ALLIANCE signed")
	var t_na: Dictionary = eng.propose_and_sign_treaty("f_b", "f_c", "NON_AGGRESSION", 5, clk)
	assert_true(_as_bool(t_na.get("ok", false), false), "NON_AGGRESSION signed")
	var t_acc: Dictionary = eng.propose_and_sign_treaty("f_a", "f_c", "MILITARY_ACCESS", 5, clk)
	assert_true(_as_bool(t_acc.get("ok", false), false), "MILITARY_ACCESS signed")
	var t_trib: Dictionary = eng.propose_and_sign_treaty("f_a", "f_b", "TRIBUTE", 2, clk, 400, 500)
	assert_true(_as_bool(t_trib.get("ok", false), false), "TRIBUTE signed (2 days = 48 ticks)")

	assert_true(eng.are_allied("f_a", "f_b", 24), "f_a and f_b are allied")
	assert_false(eng.are_allied("f_a", "f_c", 24), "MILITARY_ACCESS does not imply ALLIANCE")
	assert_true(eng.has_non_aggression("f_a", "f_b", 24), "ALLIANCE implies non-aggression")
	assert_true(eng.has_non_aggression("f_b", "f_c", 24), "NON_AGGRESSION active between f_b and f_c")

	# Day 1 tribute settlement (tick 48 < expires_tick 72)
	clk.advance(24)
	var ev1: Array[Dictionary] = eng.settle_daily_treaties(mgr, clk)
	assert_eq(ev1.size(), 1, "1 TRIBUTE_PAID event on day 1")
	assert_eq(str(ev1[0].get("type", "")), "TRIBUTE_PAID", "Event type is TRIBUTE_PAID")
	assert_eq(_as_int(mgr.get_faction("f_a").get("treasury_coin", 0), 0), 2600, "f_a paid 400 coin")
	assert_eq(_as_int(mgr.get_faction("f_a").get("treasury_grain", 0), 0), 2500, "f_a paid 500 grain")
	assert_eq(_as_int(mgr.get_faction("f_b").get("treasury_coin", 0), 0), 1400, "f_b received 400 coin")
	assert_eq(_as_int(mgr.get_faction("f_b").get("treasury_grain", 0), 0), 1500, "f_b received 500 grain")

	# Day 2 (tick 72 == expires_tick 72) -> treaty expires
	clk.advance(24)
	var ev2: Array[Dictionary] = eng.settle_daily_treaties(mgr, clk)
	assert_eq(ev2.size(), 1, "1 TREATY_EXPIRED event when tick >= expires_tick")
	assert_eq(str(ev2[0].get("type", "")), "TREATY_EXPIRED", "Tribute treaty expired")
	assert_eq(str(eng.get_treaty(str(t_trib.get("treaty_id", ""))).get("status", "")), "EXPIRED", "Treaty status updated to EXPIRED")

	# Tribute default when payer treasury insufficient
	var t_big: Dictionary = eng.propose_and_sign_treaty("f_b", "f_c", "TRIBUTE", 3, clk, 99999, 0)
	assert_true(_as_bool(t_big.get("ok", false), false), "Large tribute treaty signed")
	clk.advance(24)
	var ev3: Array[Dictionary] = eng.settle_daily_treaties(mgr, clk)
	assert_eq(str(ev3[0].get("type", "")), "TRIBUTE_DEFAULTED", "Insolvent payer triggers TRIBUTE_DEFAULTED")


func test_break_treaty_oathbreaker_penalty_and_insurgency() -> void:
	var env: Dictionary = _make_world_and_factions()
	var v_mgr: Variant = env["mgr"]
	var v_wg: Variant = env["wg"]
	var mgr: FactionManager = v_mgr
	var wg: WorldGraph = v_wg
	var eng: DiplomacyTreatyEngine = DiplomacyTreatyEngine.new()
	var clk: SimClock = SimClock.new(48)

	var _e1: Dictionary = mgr.enlist_officer("off_chiv", "f_a", "RANK_9")
	var _e2: Dictionary = mgr.enlist_officer("off_unself", "f_a", "RANK_9")
	var _e3: Dictionary = mgr.enlist_officer("off_greedy", "f_a", "RANK_9")
	var _e4: Dictionary = mgr.enlist_officer("off_beta_chiv", "f_b", "RANK_9")

	var p_chiv: PawnEntity = PawnEntity.new("off_chiv", "Chiv", true)
	p_chiv.owner_player_id = "off_chiv"
	p_chiv.traits = ["T_CHIVALROUS"]
	p_chiv.set_need("LOYALTY", 8000)

	var p_unself: PawnEntity = PawnEntity.new("off_unself", "Unself", true)
	p_unself.owner_player_id = "off_unself"
	p_unself.traits = ["T_UNSELFISH"]
	p_unself.set_need("LOYALTY", 8000)

	var p_greedy: PawnEntity = PawnEntity.new("off_greedy", "Greedy", true)
	p_greedy.owner_player_id = "off_greedy"
	p_greedy.traits = ["T_GREEDY"]
	p_greedy.set_need("LOYALTY", 8000)

	var p_beta: PawnEntity = PawnEntity.new("off_beta_chiv", "BetaChiv", true)
	p_beta.owner_player_id = "off_beta_chiv"
	p_beta.traits = ["T_CHIVALROUS"]
	p_beta.set_need("LOYALTY", 8000)

	var t_all: Dictionary = eng.propose_and_sign_treaty("f_a", "f_b", "ALLIANCE", 10, clk)
	var tid: String = str(t_all.get("treaty_id", ""))

	# Third party cannot break treaty
	var bad_brk: Dictionary = eng.break_treaty(tid, "f_c", mgr, [p_chiv, p_unself, p_greedy, p_beta], clk)
	assert_false(_as_bool(bad_brk.get("ok", true), true), "Non-party cannot break treaty")
	assert_eq(str(bad_brk.get("error_code", "")), DtoSchemas.ERR_ROLE_PERMISSION, "Returns ERR_ROLE_PERMISSION")

	var brk: Dictionary = eng.break_treaty(tid, "f_a", mgr, [p_chiv, p_unself, p_greedy, p_beta], clk)
	assert_true(_as_bool(brk.get("ok", false), false), "f_a breaks treaty")
	assert_eq(_as_int(brk.get("diplomatic_trust_bp", 0), 0), 7500, "Trust reduced by 2500 bp (10000 -> 7500)")
	assert_eq(eng.get_faction_trust_bp("f_a"), 7500, "Engine trust matches 7500")
	assert_eq(_as_int(mgr.get_faction("f_a").get("diplomatic_trust_bp", 0), 0), 7500, "FactionManager trust synced")
	assert_true(eng.is_oathbreaker("f_a", 48), "Oathbreaker active at tick 48")
	assert_true(eng.is_oathbreaker("f_a", 407), "Oathbreaker active at tick 407 (48 + 360 - 1)")
	assert_false(eng.is_oathbreaker("f_a", 408), "Oathbreaker expires at tick 408")
	assert_false(eng.are_allied("f_a", "f_b", 48), "Broken alliance no longer active")

	assert_eq(p_chiv.get_need("LOYALTY"), 6500, "T_CHIVALROUS officer loses 1500 loyalty")
	assert_true(p_chiv.has_thought("LORD_OATHBREAKER"), "T_CHIVALROUS receives LORD_OATHBREAKER thought")
	assert_eq(p_unself.get_need("LOYALTY"), 6500, "T_UNSELFISH officer loses 1500 loyalty")
	assert_eq(p_greedy.get_need("LOYALTY"), 8000, "T_GREEDY officer does not suffer oathbreaker loyalty hit")
	assert_eq(p_beta.get_need("LOYALTY"), 8000, "Rival faction officer unaffected by breaker's oathbreaker penalty")

	# Fund regional insurgency
	var bad_ins: Dictionary = eng.fund_regional_insurgency("f_a", "n_b", 0, mgr, wg)
	assert_false(_as_bool(bad_ins.get("ok", true), true), "coin_amount <= 0 rejected")
	var bad_ins_funds: Dictionary = eng.fund_regional_insurgency("f_a", "n_b", 99999, mgr, wg)
	assert_false(_as_bool(bad_ins_funds.get("ok", true), true), "Insufficient funds rejected")

	var ins: Dictionary = eng.fund_regional_insurgency("f_a", "n_b", 1000, mgr, wg)
	assert_true(_as_bool(ins.get("ok", false), false), "Insurgency funded with 1000 coin")
	assert_eq(_as_int(mgr.get_faction("f_a").get("treasury_coin", 0), 0), 2000, "Sponsor coin deducted (3000 -> 2000)")
	assert_eq(_as_int(wg.get_node("n_b").get("bandit_pressure_bp", 0), 0), 1700, "bandit_pressure_bp increased by 1500 (200 -> 1700)")
	assert_eq(_as_int(wg.get_node("n_b").get("security_bp", 0), 0), 6000, "security_bp decreased by 1000 (7000 -> 6000)")


func test_season_modifiers_and_to_dict_from_dict() -> void:
	var sp: Dictionary = DiplomacyTreatyEngine.get_season_modifiers("SPRING")
	var su: Dictionary = DiplomacyTreatyEngine.get_season_modifiers("SUMMER")
	var au: Dictionary = DiplomacyTreatyEngine.get_season_modifiers("AUTUMN")
	var wi: Dictionary = DiplomacyTreatyEngine.get_season_modifiers("WINTER")

	assert_eq(_as_int(sp.get("farming_pm", 0), 0), 1200, "SPRING farming_pm == 1200")
	assert_eq(_as_int(su.get("supply_drain_pm", 0), 0), 1150, "SUMMER supply_drain_pm == 1150")
	assert_eq(_as_int(au.get("farming_pm", 0), 0), 1500, "AUTUMN farming_pm == 1500")
	assert_eq(_as_int(au.get("march_speed_pm", 0), 0), 1100, "AUTUMN march_speed_pm == 1100")
	assert_eq(_as_int(wi.get("farming_pm", 0), 0), 200, "WINTER farming_pm == 200")
	assert_eq(_as_int(wi.get("march_speed_pm", 0), 0), 750, "WINTER march_speed_pm == 750")
	assert_eq(_as_int(wi.get("supply_drain_pm", 0), 0), 2000, "WINTER supply_drain_pm == 2000")

	var eng: DiplomacyTreatyEngine = DiplomacyTreatyEngine.new()
	var clk: SimClock = SimClock.new(24)
	var _t: Dictionary = eng.propose_and_sign_treaty("f_a", "f_b", "ALLIANCE", 5, clk)
	var _b: Dictionary = eng.break_treaty("treaty_000001", "f_a", null, [], clk)

	var snap: Dictionary = eng.to_dict()
	assert_false(StateHasher.has_floats(snap), "DiplomacyTreatyEngine.to_dict() contains no floats")
	var restored: DiplomacyTreatyEngine = DiplomacyTreatyEngine.from_dict(snap)
	assert_eq(StateHasher.sha256_dict(snap), StateHasher.sha256_dict(restored.to_dict()), "Round-trip SHA-256 parity")
	assert_true(restored.is_oathbreaker("f_a", 24), "Restored engine preserves oathbreaker status")
	assert_eq(restored.get_faction_trust_bp("f_a"), 7500, "Restored engine preserves trust_bp")
