class_name TestEspionageService
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


func _make_test_world_graph() -> WorldGraph:
	var nodes: Array[Dictionary] = [
		{"node_id": "n_cap", "name_ko": "Capital", "province": "YU_ZHOU", "owner_faction_id": "NEUTRAL"},
		{"node_id": "n_gov", "name_ko": "Governed", "province": "YU_ZHOU", "owner_faction_id": "NEUTRAL"},
		{"node_id": "n_yt", "name_ko": "Turban", "province": "YU_ZHOU", "owner_faction_id": "YELLOW_TURBAN"},
		{"node_id": "n_enemy", "name_ko": "Enemy", "province": "YU_ZHOU", "owner_faction_id": "f_rival"}
	]
	var edges: Array[Dictionary] = [
		{"edge_id": "e_1", "from_node": "n_cap", "to_node": "n_gov", "travel_macro_ticks": 1}
	]
	return WorldGraph.new({"nodes": nodes, "edges": edges}, false)


func test_sow_discord_int_vs_int_and_immunity_guards() -> void:
	var svc: EspionageService = EspionageService.new()
	var clk: SimClock = SimClock.new(100)

	var agent: PawnEntity = PawnEntity.new("agent_jia", "Jia Xu", true)
	agent.set_stat("INT", 98)
	agent.set_stat("CHA", 75)

	var target_unself: PawnEntity = PawnEntity.new("target_u", "Lu Su", false)
	target_unself.traits = ["T_UNSELFISH"]
	var res_u: Dictionary = svc.execute_sow_discord(agent, target_unself, clk, 18401)
	assert_false(_as_bool(res_u.get("ok", true), true), "T_UNSELFISH blocks OP_SOW_DISCORD")
	assert_eq(str(res_u.get("blocked_by", "")), "T_UNSELFISH", "blocked_by reports T_UNSELFISH")

	var target_offline: PawnEntity = PawnEntity.new("target_o", "Offline", false)
	target_offline.offline_bribe_immune_until_tick = 101
	var res_o: Dictionary = svc.execute_sow_discord(agent, target_offline, clk, 18401)
	assert_false(_as_bool(res_o.get("ok", true), true), "offline_bribe_immune_until_tick > tick_id blocks OP_SOW_DISCORD")
	assert_eq(str(res_o.get("blocked_by", "")), "OFFLINE_IMMUNITY", "blocked_by reports OFFLINE_IMMUNITY")

	# Boundary: offline_bribe_immune_until_tick == tick_id is no longer immune
	target_offline.offline_bribe_immune_until_tick = 100
	target_offline.set_stat("INT", 45)
	target_offline.set_need("LOYALTY", 8000)

	var res_high_int: Dictionary = svc.execute_sow_discord(agent, target_offline, clk, 18401)
	assert_true(_as_bool(res_high_int.get("ok", false), false), "Discord executes after immunity expires")
	assert_eq(_as_int(res_high_int.get("success_bp", 0), 0), 9500, "INT advantage clamps success_bp to 9500")

	var low_int_agent: PawnEntity = PawnEntity.new("agent_low", "LowInt", true)
	low_int_agent.set_stat("INT", 40)
	var smart_target: PawnEntity = PawnEntity.new("target_smart", "Zhuge", false)
	smart_target.set_stat("INT", 99)
	var res_low_int: Dictionary = svc.execute_sow_discord(low_int_agent, smart_target, clk, 18401)
	assert_eq(_as_int(res_low_int.get("success_bp", 0), 0), 1500, "INT disadvantage clamps success_bp to 1500")

	# Find a deterministic tick where sow_discord succeeds and verify loyalty drop + thought
	var saw_success: bool = false
	for t: int in range(100, 120):
		target_offline.set_need("LOYALTY", 8000)
		var c_t: SimClock = SimClock.new(t)
		var r: Dictionary = svc.execute_sow_discord(agent, target_offline, c_t, 18401)
		if _as_bool(r.get("succeeded", false), false):
			saw_success = true
			assert_gt(_as_int(r.get("loyalty_drop", 0), 0), 0, "Successful discord drops loyalty")
			assert_lt(target_offline.get_need("LOYALTY"), 8000, "Target LOYALTY reduced")
			assert_true(target_offline.has_thought("DISCORD_SUSPICION"), "Target receives DISCORD_SUSPICION thought")
			break
	assert_true(saw_success, "OP_SOW_DISCORD succeeds deterministically within 20 ticks at 95% chance")


func test_poach_retainer_threshold_guards_and_transfer() -> void:
	var svc: EspionageService = EspionageService.new()
	var mgr: FactionManager = FactionManager.new()
	var wg: WorldGraph = _make_test_world_graph()
	var _f1: Dictionary = mgr.create_faction("f_src", "Src", "lord_s", "n_cap", wg)
	var _f2: Dictionary = mgr.create_faction("f_dst", "Dst", "lord_d", "n_gov", wg)
	var _e: Dictionary = mgr.enlist_officer("target_ret", "f_src", "RANK_9")

	var agent: PawnEntity = PawnEntity.new("lord_d", "Recruiter", true)
	agent.owner_player_id = "lord_d"
	agent.set_stat("CHA", 92)

	var target: PawnEntity = PawnEntity.new("target_ret", "Defector", false)
	target.owner_player_id = "lord_s"
	target.set_stat("CHA", 50)
	target.traits = ["T_GREEDY"]

	var src_manor: ManorState = ManorState.new("man_s", "lord_s")
	var _add_p: bool = src_manor.add_pawn(target)
	var dst_manor: ManorState = ManorState.new("man_d", "lord_d")
	dst_manor.set_resource("COIN", 5000)

	var clk: SimClock = SimClock.new(50)

	# Loyalty >= 6000 blocked
	target.set_need("LOYALTY", 6000)
	var blocked_hi: Dictionary = svc.execute_poach_retainer(agent, target, 1000, mgr, clk, 18401, src_manor, dst_manor)
	assert_false(_as_bool(blocked_hi.get("ok", true), true), "loyalty_bp == 6000 blocks poaching")

	# Insufficient coin blocked
	target.set_need("LOYALTY", 3000)
	var blocked_coin: Dictionary = svc.execute_poach_retainer(agent, target, 9999, mgr, clk, 18401, src_manor, dst_manor)
	assert_false(_as_bool(blocked_coin.get("ok", true), true), "Insufficient coin blocked")
	assert_eq(str(blocked_coin.get("error_code", "")), DtoSchemas.ERR_INSUFFICIENT_RESOURCE, "Returns ERR_INSUFFICIENT_RESOURCE")

	# T_UNSELFISH blocked even when loyalty < 6000
	var unself: PawnEntity = PawnEntity.new("u_ret", "Pure", false)
	unself.set_need("LOYALTY", 1000)
	unself.traits = ["T_UNSELFISH"]
	var blocked_u: Dictionary = svc.execute_poach_retainer(agent, unself, 1000, mgr, clk, 18401, src_manor, dst_manor)
	assert_false(_as_bool(blocked_u.get("ok", true), true), "T_UNSELFISH blocks poaching")

	# Successful poach with loyalty < 6000
	var poached: bool = false
	for t: int in range(50, 70):
		var c_t: SimClock = SimClock.new(t)
		var res: Dictionary = svc.execute_poach_retainer(agent, target, 2000, mgr, c_t, 18401, src_manor, dst_manor)
		if _as_bool(res.get("succeeded", false), false):
			poached = true
			assert_eq(str(res.get("new_owner_player_id", "")), "lord_d", "New owner is destination manor player")
			assert_eq(target.owner_player_id, "lord_d", "Target pawn owner updated to lord_d")
			assert_eq(target.get_need("LOYALTY"), 7000, "Poached pawn loyalty reset to 7000")
			assert_true(target.has_thought("POACHED_NEW_LIEGE"), "Poached pawn gets POACHED_NEW_LIEGE thought")
			assert_eq(src_manor.pawns.size(), 0, "Removed from source manor")
			assert_eq(dst_manor.pawns.size(), 1, "Added to destination manor")
			assert_eq(str(mgr.get_player_profile("target_ret").get("faction_id", "")), "f_dst", "Faction profile updated to f_dst")
			break
	assert_true(poached, "Poach succeeds deterministically within 20 ticks at 90% chance")


func test_resign_battlefield_turncoat_and_governor_rebellion() -> void:
	var svc: EspionageService = EspionageService.new()
	var mgr: FactionManager = FactionManager.new()
	var wg: WorldGraph = _make_test_world_graph()
	var _f: Dictionary = mgr.create_faction("f_cao", "Cao", "lord_c", "n_cap", wg)
	var _ok_own: bool = wg.set_node_owner("n_gov", "f_cao", "")
	var _e1: Dictionary = mgr.enlist_officer("gov_a", "f_cao", "RANK_5")
	var _e2: Dictionary = mgr.enlist_officer("gov_b", "f_cao", "RANK_5")
	var _e3: Dictionary = mgr.enlist_officer("off_r6", "f_cao", "RANK_6")

	var _ap1: Dictionary = mgr.appoint_governor("lord_c", "gov_a", "n_gov", wg)

	# Lord cannot resign directly
	var bad_resign: Dictionary = svc.resign_from_faction("lord_c", mgr, wg)
	assert_false(_as_bool(bad_resign.get("ok", true), true), "LORD cannot resign directly")
	assert_eq(str(bad_resign.get("error_code", "")), DtoSchemas.ERR_ROLE_PERMISSION, "Returns ERR_ROLE_PERMISSION")

	# Governor resigns -> becomes FREE_OFFICER and clears governor on node while preserving faction ownership
	var ok_resign: Dictionary = svc.resign_from_faction("gov_a", mgr, wg)
	assert_true(_as_bool(ok_resign.get("ok", false), false), "Governor resigned cleanly")
	assert_eq(str(ok_resign.get("role_tier", "")), "FREE_OFFICER", "Resigned officer becomes FREE_OFFICER")
	assert_eq(str(wg.get_node("n_gov").get("governor_player_id", "")), "", "Node governor cleared on resign")
	assert_eq(str(wg.get_node("n_gov").get("owner_faction_id", "")), "f_cao", "Faction retains node ownership on resign")

	# Re-appoint gov_b and test declare_governor_rebellion
	var _ap2: Dictionary = mgr.appoint_governor("lord_c", "gov_b", "n_gov", wg)
	var bad_reb_non_gov: Dictionary = svc.declare_governor_rebellion("off_r6", "n_gov", "f_reb", mgr, wg)
	assert_false(_as_bool(bad_reb_non_gov.get("ok", true), true), "Non-governor cannot declare governor rebellion")

	var ok_reb: Dictionary = svc.declare_governor_rebellion("gov_b", "n_gov", "f_reb", mgr, wg, "Rebel Banner")
	assert_true(_as_bool(ok_reb.get("ok", false), false), "Governor rebellion succeeded")
	assert_eq(str(wg.get_node("n_gov").get("owner_faction_id", "")), "f_reb", "Rebellion flips governed node ownership")
	assert_eq(str(mgr.get_player_profile("gov_b").get("role_tier", "")), "LORD", "Rebel governor becomes LORD")
	assert_eq(str(mgr.get_player_profile("gov_b").get("faction_id", "")), "f_reb", "Rebel governor moves to new faction")

	# Battlefield turncoat (< 4000 loyalty_bp)
	var _pact: Dictionary = svc.register_turncoat_pact("off_tc", "f_reb", 10)
	var tc_pawn: PawnEntity = PawnEntity.new("off_tc", "Turncoat", false)
	tc_pawn.set_need("LOYALTY", 4000)
	var ctx_fail: Dictionary = {"defender_morale_bp": 8000}
	var tc_hi: Dictionary = svc.trigger_battlefield_turncoat(tc_pawn, ctx_fail)
	assert_false(_as_bool(tc_hi.get("ok", true), true), "loyalty_bp == 4000 rejects battlefield turncoat")

	tc_pawn.set_need("LOYALTY", 3999)
	var ctx_ok: Dictionary = {
		"tick_id": 120,
		"defender_morale_bp": 7500,
		"defender_troops": 3000,
		"attacker_troops": 2000,
		"officer_troops": 800
	}
	var tc_res: Dictionary = svc.trigger_battlefield_turncoat(tc_pawn, ctx_ok)
	assert_true(_as_bool(tc_res.get("ok", false), false), "Battlefield turncoat triggered at loyalty 3999")
	assert_eq(_as_int(ctx_ok.get("defender_morale_bp", 0), 0), 4500, "Morale shock -3000 applied (7500 -> 4500)")
	assert_eq(_as_int(ctx_ok.get("defender_troops", 0), 0), 2200, "800 defecting troops subtracted from defender")
	assert_eq(_as_int(ctx_ok.get("attacker_troops", 0), 0), 2800, "800 defecting troops added to attacker")
	assert_eq(str(tc_res.get("sponsor_faction_id", "")), "f_reb", "Sponsor faction resolved from pact")
	assert_true(tc_pawn.has_thought("TURNCOAT_STIGMA"), "Turncoat receives TURNCOAT_STIGMA thought")


func test_raise_free_officer_uprising_requirements_and_atomic_deduction() -> void:
	var svc: EspionageService = EspionageService.new()
	var mgr: FactionManager = FactionManager.new()
	var wg: WorldGraph = _make_test_world_graph()
	var _reg: Dictionary = mgr.register_player("free_hero")

	var manor: ManorState = ManorState.new("man_hero", "free_hero")
	manor.household_troops = 1999
	manor.set_resource("COIN", 5000)
	manor.set_resource("GRAIN", 3000)

	var low_troops: Dictionary = svc.raise_free_officer_uprising("free_hero", manor, "n_yt", "f_hero", mgr, wg)
	assert_false(_as_bool(low_troops.get("ok", true), true), "Requires >= 2000 troops")
	assert_eq(manor.get_resource("COIN"), 5000, "Coin untouched on troop check failure")

	manor.household_troops = 2000
	manor.set_resource("COIN", 4999)
	var low_coin: Dictionary = svc.raise_free_officer_uprising("free_hero", manor, "n_yt", "f_hero", mgr, wg)
	assert_false(_as_bool(low_coin.get("ok", true), true), "Requires >= 5000 coin")
	assert_eq(manor.get_resource("COIN"), 4999, "Coin untouched on coin check failure")

	manor.set_resource("COIN", 6200)
	var non_neutral: Dictionary = svc.raise_free_officer_uprising("free_hero", manor, "n_enemy", "f_hero", mgr, wg)
	assert_false(_as_bool(non_neutral.get("ok", true), true), "Cannot raise free uprising on enemy faction-owned node")
	assert_eq(manor.get_resource("COIN"), 6200, "Coin untouched when node ownership gate fails")

	var ok_up: Dictionary = svc.raise_free_officer_uprising("free_hero", manor, "n_yt", "f_hero", mgr, wg, "Hero Banner")
	assert_true(_as_bool(ok_up.get("ok", false), false), "Uprising succeeds on YELLOW_TURBAN node")
	assert_eq(manor.get_resource("COIN"), 1200, "Atomically deducted 5000 COIN (6200 -> 1200)")
	assert_eq(str(wg.get_node("n_yt").get("owner_faction_id", "")), "f_hero", "Node flipped to new faction")
	assert_eq(str(mgr.get_player_profile("free_hero").get("role_tier", "")), "LORD", "Player promoted to LORD")

	# Serialization parity
	var snap: Dictionary = svc.to_dict()
	assert_false(StateHasher.has_floats(snap), "EspionageService.to_dict() has no floats")
	var restored: EspionageService = EspionageService.from_dict(snap)
	assert_eq(StateHasher.sha256_dict(snap), StateHasher.sha256_dict(restored.to_dict()), "EspionageService SHA-256 round-trip parity")
