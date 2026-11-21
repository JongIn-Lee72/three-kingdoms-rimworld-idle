class_name TestSiegeBattleResolver
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


func _make_siege_world() -> WorldGraph:
	return WorldGraph.new({
		"nodes": [
			{
				"node_id": "n_luoyang",
				"name_ko": "Luoyang",
				"province": "SI_LI",
				"owner_faction_id": "f_dong",
				"governor_player_id": "gov_dong",
				"fortification_hp": 1200,
				"max_fortification_hp": 5000
			},
			{
				"node_id": "n_strong",
				"name_ko": "Stronghold",
				"province": "SI_LI",
				"owner_faction_id": "f_dong",
				"governor_player_id": "gov_dong",
				"fortification_hp": 5000,
				"max_fortification_hp": 5000
			}
		],
		"edges": [
			{"edge_id": "e_1", "from_node": "n_luoyang", "to_node": "n_strong", "travel_macro_ticks": 1}
		]
	}, false)


func test_coalition_rally_alliance_gate_and_3_phase_siege_victory() -> void:
	var wg: WorldGraph = _make_siege_world()
	var clk: SimClock = SimClock.new(100)

	var mgr: FactionManager = FactionManager.new()
	var _fa: Dictionary = mgr.create_faction("f_liu", "Liu", "p_liu", "n_luoyang", wg)
	var _ok_restore: bool = wg.set_node_owner("n_luoyang", "f_dong", "gov_dong")
	var _fb: Dictionary = mgr.create_faction("f_sun", "Sun", "p_sun", "n_strong", wg)
	var _ok_restore2: bool = wg.set_node_owner("n_strong", "f_dong", "gov_dong")

	var dip: DiplomacyTreatyEngine = DiplomacyTreatyEngine.new()
	var _t: Dictionary = dip.propose_and_sign_treaty("f_liu", "f_sun", "ALLIANCE", 10, clk)

	var soc: SocialBanquetService = SocialBanquetService.new()
	var _a1: int = soc.set_affinity("off_liu", "off_guan", 90)
	var _a2: int = soc.set_affinity("off_guan", "off_liu", 90)
	var _sw: Dictionary = soc.form_sworn_siblings("off_liu", "off_guan")

	var resolver: SiegeBattleResolver = SiegeBattleResolver.new()

	# Invalid rally creation rejected
	var bad_rally: Dictionary = resolver.create_coalition_rally("f_liu", "n_luoyang", {"troop_count": 0}, clk)
	assert_false(_as_bool(bad_rally.get("ok", true), true), "0-troop coalition rally rejected")

	var leader_army: Dictionary = {
		"owner_player_id": "p_liu",
		"troop_count": 3000,
		"morale_bp": 9000,
		"gear_pm": 1300,
		"troop_composition": {"SIEGE_ENGINE": 10},
		"officers": [
			{"pawn_id": "off_guan", "MAR": 97, "LEA": 95, "INT": 80, "traits": ["T_CHIVALROUS"]},
			{"pawn_id": "off_liu", "MAR": 75, "LEA": 88, "INT": 82, "traits": []}
		]
	}
	var ral_res: Dictionary = resolver.create_coalition_rally("f_liu", "n_luoyang", leader_army, clk)
	assert_true(_as_bool(ral_res.get("ok", false), false), "Coalition rally created")
	var rid: String = str(ral_res.get("rally_id", ""))

	# Non-allied faction rejected
	var non_ally_army: Dictionary = {"faction_id": "f_yuan", "owner_player_id": "p_yuan", "troop_count": 1000}
	var rej_join: Dictionary = resolver.join_coalition_rally(rid, non_ally_army, dip, clk)
	assert_false(_as_bool(rej_join.get("ok", true), true), "Non-allied faction rejected from coalition rally")
	assert_eq(str(rej_join.get("error_code", "")), DtoSchemas.ERR_ROLE_PERMISSION, "Returns ERR_ROLE_PERMISSION")

	# Allied faction joins
	var ally_army: Dictionary = {
		"faction_id": "f_sun",
		"owner_player_id": "p_sun",
		"troop_count": 1000,
		"morale_bp": 9000,
		"gear_pm": 1200,
		"officers": [{"pawn_id": "off_sun", "MAR": 88, "LEA": 90, "INT": 76}]
	}
	var ok_join: Dictionary = resolver.join_coalition_rally(rid, ally_army, dip, clk)
	assert_true(_as_bool(ok_join.get("ok", false), false), "Allied faction joined coalition rally")
	assert_eq(_as_int(ok_join.get("participant_count", 0), 0), 2, "Rally has 2 participants")

	var defender_army: Dictionary = {
		"troop_count": 1200,
		"morale_bp": 6500,
		"gear_pm": 1000,
		"officers": [{"pawn_id": "off_def", "MAR": 60, "LEA": 60, "INT": 55}]
	}
	var siege_res: Dictionary = resolver.resolve_coalition_siege(rid, "n_luoyang", defender_army, wg, soc, clk, 18401, mgr)
	assert_true(_as_bool(siege_res.get("ok", false), false), "3-phase coalition siege resolved")
	assert_true(_as_bool(siege_res.get("attacker_won", false), false), "4000 coalition with Sworn Sibling +15% and siege engines defeats 1200 garrison")
	assert_eq(_as_int(siege_res.get("sibling_joint_bonus_pm", 0), 0), 150, "Sworn Sibling +150 pm (+15%) bonus applied")

	var p1: Dictionary = _as_dict(siege_res.get("phase1_bombardment", {}))
	assert_true(_as_bool(p1.get("wall_breached", false), false), "Wall breached in Phase 1")
	assert_eq(_as_int(p1.get("remaining_wall_hp", -1), -1), 0, "Remaining wall HP is 0")

	var p2: Dictionary = _as_dict(siege_res.get("phase2_duel", {}))
	var duel: Dictionary = _as_dict(p2.get("duel", {}))
	assert_in_range(_as_array(duel.get("bouts", [])).size(), 1, 5, "Phase 2 duel resolved in 1..5 bouts")

	var p3: Dictionary = _as_dict(siege_res.get("phase3_battle", {}))
	assert_eq(str(p3.get("winner", "")), "A", "Phase 3 auto-battle won by attacker A")

	# Node ownership flipped & governor cleared
	var node_after: Dictionary = wg.get_node("n_luoyang")
	assert_eq(str(node_after.get("owner_faction_id", "")), "f_liu", "Node ownership flipped to rally leader f_liu")
	assert_eq(str(node_after.get("governor_player_id", "")), "", "Governor cleared on conquest")

	# Proportional war_merit payout (3000/4000 = 1500, 1000/4000 = 500)
	var shares: Dictionary = _as_dict(siege_res.get("merit_shares", {}))
	assert_eq(_as_int(shares.get("p_liu", 0), 0), 1500, "p_liu receives 75% share (1500 merit)")
	assert_eq(_as_int(shares.get("p_sun", 0), 0), 500, "p_sun receives 25% share (500 merit)")
	assert_eq(_as_int(mgr.get_player_profile("p_liu").get("war_merit", 0), 0), 1500, "p_liu FactionManager war_merit updated")

	# Cannot re-resolve already resolved rally
	var re_res: Dictionary = resolver.resolve_coalition_siege(rid, "n_luoyang", defender_army, wg, soc, clk, 18401, mgr)
	assert_false(_as_bool(re_res.get("ok", true), true), "Already resolved rally cannot be re-resolved")


func test_siege_defeat_and_supply_interdiction_caravan_vs_escort() -> void:
	var wg: WorldGraph = _make_siege_world()
	var clk: SimClock = SimClock.new(200)
	var resolver: SiegeBattleResolver = SiegeBattleResolver.new()

	# Weak attacker fails against strong fortified garrison
	var weak_ral: Dictionary = resolver.create_coalition_rally("f_liu", "n_strong", {
		"owner_player_id": "p_weak",
		"troop_count": 300,
		"morale_bp": 6000,
		"gear_pm": 900,
		"officers": [{"pawn_id": "off_w", "MAR": 45, "LEA": 45, "INT": 45}]
	}, clk)
	var rid: String = str(weak_ral.get("rally_id", ""))
	var strong_def: Dictionary = {
		"troop_count": 5000,
		"morale_bp": 9500,
		"gear_pm": 1400,
		"officers": [{"pawn_id": "off_lu_bu", "MAR": 100, "LEA": 95, "INT": 60, "traits": ["T_FIERCE"]}]
	}
	var def_res: Dictionary = resolver.resolve_coalition_siege(rid, "n_strong", strong_def, wg, null, clk, 18401, null)
	assert_true(_as_bool(def_res.get("ok", false), false), "Defeat siege resolves cleanly")
	assert_false(_as_bool(def_res.get("attacker_won", true), true), "Attacker loses against strong garrison")
	assert_eq(str(wg.get_node("n_strong").get("owner_faction_id", "")), "f_dong", "Node ownership unchanged on defeat")
	assert_eq(_as_int(_as_dict(def_res.get("merit_shares", {})).get("p_weak", 0), 0), 400, "Consolation merit pool 400 awarded")

	# Supply interdiction: raider wins vs weak escort -> 60% loot
	var caravan1: Dictionary = {"caravan_id": "car_1", "carried_grain": 1000, "carried_coin": 500}
	var raider_win: Dictionary = resolver.resolve_supply_interdiction(
		{"troop_count": 1500, "morale_bp": 9000, "gear_pm": 1300, "officers": [{"pawn_id": "r1", "MAR": 85, "LEA": 85}]},
		caravan1,
		{"troop_count": 200, "morale_bp": 6000, "gear_pm": 900, "officers": [{"pawn_id": "e1", "MAR": 50, "LEA": 50}]},
		clk,
		18401
	)
	assert_true(_as_bool(raider_win.get("ok", false), false), "Interdiction resolved")
	assert_true(_as_bool(raider_win.get("raider_won", false), false), "Strong raider defeats weak escort")
	assert_eq(_as_int(raider_win.get("looted_grain", 0), 0), 600, "Raider loots 60% grain (600)")
	assert_eq(_as_int(raider_win.get("looted_coin", 0), 0), 300, "Raider loots 60% coin (300)")
	assert_eq(_as_int(caravan1.get("carried_grain", 0), 0), 400, "Caravan retains 400 grain")
	assert_eq(_as_int(caravan1.get("carried_coin", 0), 0), 200, "Caravan retains 200 coin")
	assert_true(_as_bool(caravan1.get("interdicted", false), false), "Caravan marked interdicted")

	# Supply interdiction: strong escort wins -> bounty coin & merit, 0 loot
	var caravan2: Dictionary = {"caravan_id": "car_2", "carried_grain": 1000, "carried_coin": 500}
	var escort_win: Dictionary = resolver.resolve_supply_interdiction(
		{"troop_count": 400, "morale_bp": 5500, "gear_pm": 900, "officers": [{"pawn_id": "r2", "MAR": 45, "LEA": 45}]},
		caravan2,
		{"troop_count": 2500, "morale_bp": 9500, "gear_pm": 1400, "officers": [{"pawn_id": "e2", "MAR": 95, "LEA": 95}]},
		clk,
		18401
	)
	assert_false(_as_bool(escort_win.get("raider_won", true), true), "Strong escort repels weak raider")
	assert_eq(_as_int(escort_win.get("looted_grain", -1), -1), 0, "No grain looted when escort wins")
	assert_eq(_as_int(escort_win.get("escort_bounty_coin", 0), 0), 200, "Escort bounty coin == 400/2 == 200")
	assert_eq(_as_int(escort_win.get("escort_bounty_merit", 0), 0), 150, "Escort bounty merit == max(150, 400/4) == 150")
	assert_false(_as_bool(caravan2.get("interdicted", true), true), "Caravan not interdicted")

	# Null clock rejected
	var null_clk: Dictionary = resolver.resolve_supply_interdiction({"troop_count": 100}, caravan2, {"troop_count": 100}, null, 18401)
	assert_false(_as_bool(null_clk.get("ok", true), true), "Null clock rejected")


func test_determinism_and_to_dict_from_dict_sha256_parity() -> void:
	var wg1: WorldGraph = _make_siege_world()
	var wg2: WorldGraph = _make_siege_world()
	var clk: SimClock = SimClock.new(100)
	var r1: SiegeBattleResolver = SiegeBattleResolver.new()
	var r2: SiegeBattleResolver = SiegeBattleResolver.new()

	var army: Dictionary = {
		"owner_player_id": "p_1",
		"troop_count": 2000,
		"morale_bp": 8500,
		"gear_pm": 1100,
		"officers": [{"pawn_id": "off_1", "MAR": 85, "LEA": 82, "INT": 70}]
	}
	var def: Dictionary = {
		"troop_count": 1500,
		"morale_bp": 8000,
		"gear_pm": 1000,
		"officers": [{"pawn_id": "off_d", "MAR": 75, "LEA": 75, "INT": 65}]
	}

	var c1: Dictionary = r1.create_coalition_rally("f_liu", "n_luoyang", army, clk)
	var c2: Dictionary = r2.create_coalition_rally("f_liu", "n_luoyang", army, clk)
	var s1: Dictionary = r1.resolve_coalition_siege(str(c1.get("rally_id", "")), "n_luoyang", def, wg1, null, clk, 99103, null)
	var s2: Dictionary = r2.resolve_coalition_siege(str(c2.get("rally_id", "")), "n_luoyang", def, wg2, null, clk, 99103, null)

	assert_eq(StateHasher.sha256_dict(s1), StateHasher.sha256_dict(s2), "Identical seeds produce identical siege summary SHA-256")
	var snap1: Dictionary = r1.to_dict()
	assert_false(StateHasher.has_floats(snap1), "SiegeBattleResolver.to_dict() contains no floats")
	var restored: SiegeBattleResolver = SiegeBattleResolver.from_dict(snap1)
	assert_eq(StateHasher.sha256_dict(snap1), StateHasher.sha256_dict(restored.to_dict()), "Round-trip SHA-256 parity")
