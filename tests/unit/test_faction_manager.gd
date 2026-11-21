class_name TestFactionManager
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


func _as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		var d: Dictionary = v
		return d
	return {}


func _as_array(v: Variant) -> Array:
	if v is Array:
		var a: Array = v
		return a
	return []


func _make_test_world_graph() -> WorldGraph:
	var nodes: Array[Dictionary] = []
	for i: int in range(1, 12):
		nodes.append({
			"node_id": "n_%02d" % i,
			"name_ko": "Node %02d" % i,
			"province": "YU_ZHOU" if i <= 5 else "YAN_ZHOU",
			"node_tier": "COUNTY",
			"owner_faction_id": "NEUTRAL",
			"fortification_hp": 3000,
			"max_fortification_hp": 5000
		})
	var edges: Array[Dictionary] = [
		{"edge_id": "e_1_2", "from_node": "n_01", "to_node": "n_02", "travel_macro_ticks": 1}
	]
	return WorldGraph.new({"nodes": nodes, "edges": edges}, false)


func test_4_tier_hierarchy_and_9_rank_merit_ladder_with_ambitious_bonus() -> void:
	var wg: WorldGraph = _make_test_world_graph()
	var mgr: FactionManager = FactionManager.new()

	var bad_reg: Dictionary = mgr.register_player("")
	assert_false(_as_bool(bad_reg.get("ok", true), true), "Empty player_id rejected")
	assert_eq(str(bad_reg.get("error_code", "")), DtoSchemas.ERR_SCHEMA, "Empty player_id returns ERR_SCHEMA")

	var free_prof: Dictionary = mgr.register_player("free_01")
	assert_eq(str(free_prof.get("role_tier", "")), "FREE_OFFICER", "Default role_tier is FREE_OFFICER")
	assert_eq(str(free_prof.get("court_rank", "")), "NONE", "Default court_rank is NONE")

	var bad_fac: Dictionary = mgr.create_faction("f_bad", "Bad", "lord_a", "missing_node", wg)
	assert_false(_as_bool(bad_fac.get("ok", true), true), "Unknown capital node rejected")

	var fac_res: Dictionary = mgr.create_faction("f_wei", "Wei", "lord_cao", "n_01", wg, 10000, 10000)
	assert_true(_as_bool(fac_res.get("ok", false), false), "Faction created")
	var lord_prof: Dictionary = mgr.get_player_profile("lord_cao")
	assert_eq(str(lord_prof.get("role_tier", "")), "LORD", "Founder becomes LORD")
	assert_eq(str(lord_prof.get("court_rank", "")), "SOVEREIGN", "Founder rank is SOVEREIGN")
	assert_eq(str(wg.get_node("n_01").get("owner_faction_id", "")), "f_wei", "Capital node owned by faction")

	var dup_fac: Dictionary = mgr.create_faction("f_wei", "Wei2", "lord_cao", "n_02", wg)
	assert_false(_as_bool(dup_fac.get("ok", true), true), "Duplicate faction_id rejected")

	# Merit thresholds & troop caps across all 9 ranks
	assert_eq(mgr.get_rank_for_merit(0), "RANK_9", "0 merit -> RANK_9")
	assert_eq(mgr.get_rank_for_merit(499), "RANK_9", "499 merit -> RANK_9")
	assert_eq(mgr.get_rank_for_merit(500), "RANK_8", "500 merit -> RANK_8")
	assert_eq(mgr.get_rank_for_merit(1500), "RANK_7", "1500 merit -> RANK_7")
	assert_eq(mgr.get_rank_for_merit(3500), "RANK_6", "3500 merit -> RANK_6")
	assert_eq(mgr.get_rank_for_merit(7000), "RANK_5", "7000 merit -> RANK_5")
	assert_eq(mgr.get_rank_for_merit(12000), "RANK_4", "12000 merit -> RANK_4")
	assert_eq(mgr.get_rank_for_merit(20000), "RANK_3", "20000 merit -> RANK_3")
	assert_eq(mgr.get_rank_for_merit(32000), "RANK_2", "32000 merit -> RANK_2")
	assert_eq(mgr.get_rank_for_merit(50000), "RANK_1", "50000 merit -> RANK_1")
	assert_eq(mgr.get_troop_cap_for_rank("RANK_9"), 1000, "RANK_9 troop cap 1000")
	assert_eq(mgr.get_troop_cap_for_rank("RANK_5"), 8000, "RANK_5 troop cap 8000")
	assert_eq(mgr.get_troop_cap_for_rank("RANK_1"), 30000, "RANK_1 troop cap 30000")
	assert_eq(mgr.get_troop_cap_for_rank("SOVEREIGN"), 50000, "SOVEREIGN troop cap 50000")

	# Enlist officer & verify T_AMBITIOUS +15% merit gain
	var enl_lord: Dictionary = mgr.enlist_officer("lord_cao", "f_other")
	assert_false(_as_bool(enl_lord.get("ok", true), true), "Lord cannot enlist into unknown/other faction")
	var enl_ok: Dictionary = mgr.enlist_officer("off_amb", "f_wei")
	assert_true(_as_bool(enl_ok.get("ok", false), false), "Officer enlisted")
	assert_eq(str(enl_ok.get("role_tier", "")), "FACTION_OFFICER", "Role tier is FACTION_OFFICER")

	var amb_pawn: PawnEntity = PawnEntity.new("off_amb", "Ambitious", true)
	amb_pawn.owner_player_id = "off_amb"
	amb_pawn.traits = ["T_AMBITIOUS"]

	var m1: Dictionary = mgr.award_merit_and_promote("off_amb", 1000, amb_pawn)
	assert_true(_as_bool(m1.get("ok", false), false), "Merit awarded")
	assert_eq(_as_int(m1.get("merit_gain", 0), 0), 1150, "T_AMBITIOUS grants +15% merit (1000 -> 1150)")
	assert_eq(str(m1.get("new_rank", "")), "RANK_8", "Promoted to RANK_8 at 1150 merit")
	assert_true(_as_bool(m1.get("promoted", false), false), "Promoted flag true")
	assert_eq(amb_pawn.current_rank, 2, "Pawn current_rank updated to tier 2")

	# Reach RANK_1 at 50000
	var m2: Dictionary = mgr.award_merit_and_promote("off_amb", 43000, amb_pawn)
	assert_eq(_as_int(m2.get("war_merit", 0), 0), 1150 + 49450, "Cumulative T_AMBITIOUS merit exact")
	assert_eq(str(m2.get("new_rank", "")), "RANK_1", "Promoted to RANK_1")
	assert_eq(amb_pawn.current_rank, 9, "Pawn current_rank updated to tier 9")

	# FREE_OFFICER accumulates merit without promotion; negative delta rejected
	var m_free: Dictionary = mgr.award_merit_and_promote("free_01", 2000)
	assert_eq(str(m_free.get("new_rank", "")), "NONE", "FREE_OFFICER stays at NONE rank")
	assert_false(_as_bool(m_free.get("promoted", true), true), "FREE_OFFICER not promoted")
	var m_neg: Dictionary = mgr.award_merit_and_promote("free_01", -10)
	assert_false(_as_bool(m_neg.get("ok", true), true), "Negative merit_delta rejected")
	assert_eq(str(m_neg.get("error_code", "")), DtoSchemas.ERR_SCHEMA, "Negative merit returns ERR_SCHEMA")


func test_daily_stipend_trait_multipliers_and_bankruptcy_arrears() -> void:
	var wg: WorldGraph = _make_test_world_graph()
	var mgr: FactionManager = FactionManager.new()
	var _f: Dictionary = mgr.create_faction("f_han", "Han", "lord_h", "n_01", wg, 5000, 5000)
	var _e1: Dictionary = mgr.enlist_officer("off_unself", "f_han", "RANK_9")
	var _e2: Dictionary = mgr.enlist_officer("off_greedy", "f_han", "RANK_9")
	var _e3: Dictionary = mgr.enlist_officer("off_norm", "f_han", "RANK_9")

	var p_unself: PawnEntity = PawnEntity.new("off_unself", "Unselfish", true)
	p_unself.owner_player_id = "off_unself"
	p_unself.traits = ["T_UNSELFISH"]
	p_unself.set_need("LOYALTY", 7000)

	var p_greedy: PawnEntity = PawnEntity.new("off_greedy", "Greedy", true)
	p_greedy.owner_player_id = "off_greedy"
	p_greedy.traits = ["T_GREEDY"]
	p_greedy.set_need("LOYALTY", 7000)

	var p_norm: PawnEntity = PawnEntity.new("off_norm", "Normal", true)
	p_norm.owner_player_id = "off_norm"
	p_norm.set_need("LOYALTY", 7000)

	var m_unself: ManorState = ManorState.new("man_u", "off_unself")
	m_unself.set_resource("COIN", 0)
	m_unself.set_resource("GRAIN", 0)
	var m_greedy: ManorState = ManorState.new("man_g", "off_greedy")
	m_greedy.set_resource("COIN", 0)
	m_greedy.set_resource("GRAIN", 0)
	var m_norm: ManorState = ManorState.new("man_n", "off_norm")
	m_norm.set_resource("COIN", 0)
	m_norm.set_resource("GRAIN", 0)

	var pawns: Dictionary = {"off_unself": p_unself, "off_greedy": p_greedy, "off_norm": p_norm}
	var manors: Dictionary = {"off_unself": m_unself, "off_greedy": m_greedy, "off_norm": m_norm}
	var clk: SimClock = SimClock.new(24)
	var bus: SimEventBus = SimEventBus.new()

	var pay_res: Dictionary = mgr.settle_daily_stipends("f_han", pawns, manors, clk, bus)
	assert_true(_as_bool(pay_res.get("ok", false), false), "Stipend settlement succeeds")
	assert_false(_as_bool(pay_res.get("bankrupt", true), true), "Not bankrupt with 5000 treasury")
	# RANK_9 base = 100 coin, 200 grain -> T_UNSELFISH (0.5x) = 50/100, T_GREEDY (2.0x) = 200/400, normal = 100/200
	assert_eq(m_unself.get_resource("COIN"), 50, "T_UNSELFISH receives 0.5x coin (50)")
	assert_eq(m_unself.get_resource("GRAIN"), 100, "T_UNSELFISH receives 0.5x grain (100)")
	assert_eq(m_greedy.get_resource("COIN"), 200, "T_GREEDY receives 2.0x coin (200)")
	assert_eq(m_greedy.get_resource("GRAIN"), 400, "T_GREEDY receives 2.0x grain (400)")
	assert_eq(m_norm.get_resource("COIN"), 100, "Normal receives 1.0x coin (100)")
	assert_eq(m_norm.get_resource("GRAIN"), 200, "Normal receives 1.0x grain (200)")
	assert_eq(_as_int(pay_res.get("total_coin_paid", 0), 0), 350, "Total coin paid == 350")
	assert_eq(_as_int(pay_res.get("total_grain_paid", 0), 0), 700, "Total grain paid == 700")
	assert_eq(p_norm.get_need("LOYALTY"), 7100, "Paid officer gains +100 LOYALTY")
	assert_eq(bus.peek_pending_count(), 1, "SimEventBus emitted EVENT_STIPEND_DISTRIBUTED")

	# Drain treasury to force bankruptcy arrears
	var fac: Dictionary = mgr.get_faction("f_han")
	var rem_coin: int = _as_int(fac.get("treasury_coin", 0), 0)
	var rem_grain: int = _as_int(fac.get("treasury_grain", 0), 0)
	var _adj: Dictionary = mgr.adjust_faction_treasury("f_han", -rem_coin, -rem_grain, 0)

	clk.advance(24)
	var arr_res: Dictionary = mgr.settle_daily_stipends("f_han", pawns, manors, clk, bus)
	assert_true(_as_bool(arr_res.get("bankrupt", false), false), "Bankrupt flag set when treasury empty")
	var arrears: Array = _as_array(arr_res.get("arrears_officers", []))
	assert_eq(arrears.size(), 3, "All 3 salaried officers in arrears")
	assert_eq(p_norm.get_need("LOYALTY"), 6300, "Arrears applies -800 LOYALTY penalty (7100 -> 6300)")
	assert_true(p_norm.has_thought("STIPEND_ARREARS"), "Arrears applies STIPEND_ARREARS thought")


func test_mission_board_idle_auto_queue_and_retainer_proposals() -> void:
	var wg: WorldGraph = _make_test_world_graph()
	var mgr: FactionManager = FactionManager.new()
	var _f: Dictionary = mgr.create_faction("f_shu", "Shu", "lord_liu", "n_01", wg, 5000, 5000)
	var _e1: Dictionary = mgr.enlist_officer("off_1", "f_shu", "RANK_9")
	var _e2: Dictionary = mgr.enlist_officer("off_cap", "f_shu", "RANK_9")
	var _reg_free: Dictionary = mgr.register_player("free_idle")

	var _prefs_res: Dictionary = mgr.set_player_auto_mission_prefs("off_1", ["BANDIT_SUPPRESSION", "BORDER_PATROL"])
	var bad_m: Dictionary = mgr.post_mission("f_shu", {"mission_type": "BOGUS_MISSION"})
	assert_false(_as_bool(bad_m.get("ok", true), true), "Invalid mission_type rejected")

	var m_patrol: Dictionary = mgr.post_mission("f_shu", {
		"mission_type": "BORDER_PATROL",
		"node_id": "n_01",
		"reward_merit": 500,
		"reward_coin": 250,
		"reward_grain": 300,
		"min_rank": "RANK_9"
	})
	assert_true(_as_bool(m_patrol.get("ok", false), false), "BORDER_PATROL mission posted")
	var m_bandit_high: Dictionary = mgr.post_mission("f_shu", {
		"mission_type": "BANDIT_SUPPRESSION",
		"node_id": "n_01",
		"reward_merit": 2000,
		"min_rank": "RANK_5"
	})
	assert_true(_as_bool(m_bandit_high.get("ok", false), false), "High-rank BANDIT_SUPPRESSION posted")

	var p1: PawnEntity = PawnEntity.new("off_1", "Guan", true)
	p1.owner_player_id = "off_1"
	p1.traits = ["T_AGRARIAN"]
	var p_cap: PawnEntity = PawnEntity.new("off_cap", "Captured", true)
	p_cap.owner_player_id = "off_cap"
	p_cap.state = "CAPTURED"

	var man1: ManorState = ManorState.new("man_1", "off_1")
	man1.set_resource("COIN", 100)
	man1.set_resource("GRAIN", 100)

	var clk: SimClock = SimClock.new(12)
	var completed: Array[Dictionary] = mgr.process_idle_mission_queue(
		"f_shu",
		clk,
		18401,
		{"off_1": man1},
		{"off_1": p1, "off_cap": p_cap}
	)
	assert_eq(completed.size(), 1, "Only eligible active officer completes 1 mission (captured & free & lord skipped)")
	assert_eq(str(completed[0].get("player_id", "")), "off_1", "off_1 completed mission")
	assert_eq(str(completed[0].get("mission_type", "")), "BORDER_PATROL", "Skipped RANK_5 BANDIT_SUPPRESSION and picked eligible BORDER_PATROL")
	assert_true(_as_bool(completed[0].get("promoted", false), false), "500 merit promotes RANK_9 -> RANK_8")
	assert_eq(man1.get_resource("COIN"), 350, "Manor received +250 COIN reward")
	assert_eq(man1.get_resource("GRAIN"), 400, "Manor received +300 GRAIN reward")

	# Retainer Proposals (F-29)
	var prop_res: Dictionary = mgr.generate_retainer_proposal(p1, man1, clk, 18401)
	assert_true(_as_bool(prop_res.get("ok", false), false), "Retainer proposal generated")
	var prop: Dictionary = _as_dict(prop_res.get("proposal", {}))
	assert_eq(str(prop.get("proposal_type", "")), "AGRICULTURE_EXPANSION", "T_AGRARIAN proposes AGRICULTURE_EXPANSION")
	assert_eq(str(prop.get("target_building", "")), "MILITARY_FARM", "Target building MILITARY_FARM")

	var pid_prop: String = str(prop_res.get("proposal_id", ""))
	var l_before: int = p1.get_need("LOYALTY")
	var a_before: int = p1.get_need("AMBITION")
	var adopt_res: Dictionary = mgr.adopt_proposal(pid_prop, p1, man1)
	assert_true(_as_bool(adopt_res.get("ok", false), false), "Proposal adopted")
	assert_eq(p1.get_need("LOYALTY"), mini(10000, l_before + 600), "Adopt adds +600 LOYALTY")
	assert_eq(p1.get_need("AMBITION"), mini(10000, a_before + 1000), "Adopt adds +1000 AMBITION")
	assert_eq(man1.get_building_level("MILITARY_FARM"), 2, "Adopt upgrades MILITARY_FARM to lvl 2")
	assert_eq(man1.get_resource("GRAIN"), 650, "AGRICULTURE_EXPANSION adds +250 GRAIN")
	assert_true(p1.has_thought("PROPOSAL_ADOPTED"), "Adopt grants PROPOSAL_ADOPTED thought")

	var re_adopt: Dictionary = mgr.adopt_proposal(pid_prop, p1, man1)
	assert_false(_as_bool(re_adopt.get("ok", true), true), "Already-resolved proposal cannot be re-adopted")

	var p_caut: PawnEntity = PawnEntity.new("off_caut", "Cautious", false)
	p_caut.owner_player_id = "off_1"
	p_caut.traits = ["T_CAUTIOUS"]
	var prop2_res: Dictionary = mgr.generate_retainer_proposal(p_caut, man1, clk, 18401)
	assert_eq(str(_as_dict(prop2_res.get("proposal", {})).get("proposal_type", "")), "FORTIFY_WALLS", "T_CAUTIOUS proposes FORTIFY_WALLS")
	var rej_res: Dictionary = mgr.reject_proposal(str(prop2_res.get("proposal_id", "")), p_caut)
	assert_true(_as_bool(rej_res.get("ok", false), false), "Proposal rejected")
	assert_eq(p_caut.get_need("LOYALTY"), 7700, "Reject deducts -300 LOYALTY")
	assert_eq(p_caut.get_need("AMBITION"), 7500, "Reject deducts -500 AMBITION")
	assert_true(p_caut.has_thought("PROPOSAL_REJECTED"), "Reject grants PROPOSAL_REJECTED thought")


func test_governor_viceroy_delegation_local_policy_and_royal_ascension() -> void:
	var wg: WorldGraph = _make_test_world_graph()
	var mgr: FactionManager = FactionManager.new()
	var _f: Dictionary = mgr.create_faction("f_wu", "Wu", "lord_sun", "n_01", wg, 10000, 10000)
	for i: int in range(2, 11):
		var _ok_own: bool = wg.set_node_owner("n_%02d" % i, "f_wu", "")

	var _e_low: Dictionary = mgr.enlist_officer("off_r6", "f_wu", "RANK_6")
	var _e_gov: Dictionary = mgr.enlist_officer("off_r5", "f_wu", "RANK_5")
	var _e_vice: Dictionary = mgr.enlist_officer("off_r2", "f_wu", "RANK_2")
	var _e_r3: Dictionary = mgr.enlist_officer("off_r3", "f_wu", "RANK_3")

	# Governor delegation requires RANK_5+ and LORD caller
	var bad_gov_rank: Dictionary = mgr.appoint_governor("lord_sun", "off_r6", "n_02", wg)
	assert_false(_as_bool(bad_gov_rank.get("ok", true), true), "RANK_6 cannot be appointed governor")
	assert_eq(str(bad_gov_rank.get("error_code", "")), DtoSchemas.ERR_ROLE_PERMISSION, "RANK_6 returns ERR_ROLE_PERMISSION")

	var bad_caller: Dictionary = mgr.appoint_governor("off_r5", "off_r5", "n_02", wg)
	assert_false(_as_bool(bad_caller.get("ok", true), true), "Non-LORD cannot appoint governor")

	var ok_gov: Dictionary = mgr.appoint_governor("lord_sun", "off_r5", "n_02", wg)
	assert_true(_as_bool(ok_gov.get("ok", false), false), "RANK_5 appointed governor")
	assert_eq(str(ok_gov.get("role_tier", "")), "GOVERNOR", "Role tier upgraded to GOVERNOR")
	assert_eq(str(wg.get_node("n_02").get("governor_player_id", "")), "off_r5", "Node governor updated in WorldGraph")

	# Local policy tax_rate_bp bounds [500, 2500]
	var bad_tax_lo: Dictionary = mgr.set_node_local_policy("off_r5", "n_02", 499, 0, wg)
	assert_false(_as_bool(bad_tax_lo.get("ok", true), true), "tax_rate_bp < 500 rejected")
	var bad_tax_hi: Dictionary = mgr.set_node_local_policy("off_r5", "n_02", 2501, 0, wg)
	assert_false(_as_bool(bad_tax_hi.get("ok", true), true), "tax_rate_bp > 2500 rejected")
	var bad_unassigned: Dictionary = mgr.set_node_local_policy("off_r5", "n_03", 1500, 0, wg)
	assert_false(_as_bool(bad_unassigned.get("ok", true), true), "Unassigned officer cannot set policy on n_03")

	var ok_pol: Dictionary = mgr.set_node_local_policy("off_r5", "n_02", 2500, 500, wg)
	assert_true(_as_bool(ok_pol.get("ok", false), false), "Governor sets local tax 2500 bp and defense budget 500")
	assert_eq(_as_int(wg.get_node("n_02").get("tax_rate_bp", 0), 0), 2500, "Node tax updated to 2500")
	assert_eq(_as_int(wg.get_node("n_02").get("fortification_hp", 0), 0), 3500, "Defense budget repaired wall 3000 -> 3500")
	assert_eq(_as_int(mgr.get_faction("f_wu").get("treasury_coin", 0), 0), 9500, "Treasury deducted 500 coin")

	# Viceroy delegation requires RANK_2+
	var bad_vice: Dictionary = mgr.appoint_viceroy("lord_sun", "off_r3", "YAN_ZHOU", wg)
	assert_false(_as_bool(bad_vice.get("ok", true), true), "RANK_3 cannot be appointed viceroy")
	var ok_vice: Dictionary = mgr.appoint_viceroy("lord_sun", "off_r2", "YAN_ZHOU", wg)
	assert_true(_as_bool(ok_vice.get("ok", false), false), "RANK_2 appointed viceroy of YAN_ZHOU")
	var v_nodes: Array = _as_array(ok_vice.get("node_ids", []))
	assert_eq(v_nodes.size(), 5, "YAN_ZHOU has 5 owned nodes (n_06..n_10)")
	assert_true(_as_bool(mgr.get_player_profile("off_r2").get("is_viceroy", false), false), "is_viceroy flag set")

	# Lord policy sliders & bounds
	var bad_sl: Dictionary = mgr.set_lord_policy_sliders("off_r5", 1500, 1500, 10000)
	assert_false(_as_bool(bad_sl.get("ok", true), true), "Non-LORD cannot set policy sliders")
	var bad_sl_oob: Dictionary = mgr.set_lord_policy_sliders("lord_sun", 5001, 1500, 10000)
	assert_false(_as_bool(bad_sl_oob.get("ok", true), true), "Out-of-bounds tax slider rejected")
	var ok_sl: Dictionary = mgr.set_lord_policy_sliders("lord_sun", 2200, 2500, 15000)
	assert_true(_as_bool(ok_sl.get("ok", false), false), "Lord policy sliders updated")

	# Royal rank ascension ladder
	var fail_asc: Dictionary = mgr.try_ascend_royal_rank("lord_sun", wg)
	assert_false(_as_bool(fail_asc.get("ok", true), true), "Ascension fails with 0 prestige")
	assert_eq(str(fail_asc.get("error_code", "")), DtoSchemas.ERR_INSUFFICIENT_RESOURCE, "Insufficient prestige returns ERR_INSUFFICIENT_RESOURCE")

	var _p_add: Dictionary = mgr.adjust_faction_treasury("f_wu", 0, 0, 7500)
	for expected_rank: String in ["PROVINCE_GOVERNOR", "DUKE", "KING", "EMPEROR"]:
		var asc: Dictionary = mgr.try_ascend_royal_rank("lord_sun", wg)
		assert_true(_as_bool(asc.get("ok", false), false), "Ascended to " + expected_rank)
		assert_eq(str(asc.get("new_rank", "")), expected_rank, "New rank matches " + expected_rank)

	var already_emp: Dictionary = mgr.try_ascend_royal_rank("lord_sun", wg)
	assert_false(_as_bool(already_emp.get("ok", true), true), "Cannot ascend past EMPEROR")


func test_to_dict_from_dict_sha256_parity() -> void:
	var wg: WorldGraph = _make_test_world_graph()
	var mgr: FactionManager = FactionManager.new()
	var _f: Dictionary = mgr.create_faction("f_jin", "Jin", "lord_sima", "n_01", wg, 8000, 9000)
	var _e: Dictionary = mgr.enlist_officer("off_zhong", "f_jin", "RANK_7")
	var _m: Dictionary = mgr.award_merit_and_promote("off_zhong", 2200)
	var _pm: Dictionary = mgr.post_mission("f_jin", {"mission_type": "GRAIN_ESCORT", "node_id": "n_01"})
	var _sl: Dictionary = mgr.set_lord_policy_sliders("lord_sima", 1800, 1200, 12000)
	var pawn: PawnEntity = PawnEntity.new("off_zhong", "Zhong", true)
	var manor: ManorState = ManorState.new("man_z", "off_zhong")
	var _pr: Dictionary = mgr.generate_retainer_proposal(pawn, manor, SimClock.new(10), 4242)

	var dict_before: Dictionary = mgr.to_dict()
	assert_false(StateHasher.has_floats(dict_before), "FactionManager.to_dict() contains no floats")
	var restored: FactionManager = FactionManager.from_dict(dict_before)
	var dict_after: Dictionary = restored.to_dict()
	assert_eq(StateHasher.sha256_dict(dict_before), StateHasher.sha256_dict(dict_after), "Round-trip SHA-256 parity preserved")
