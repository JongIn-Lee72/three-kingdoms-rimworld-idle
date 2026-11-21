class_name TestManorSimulator
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


func _make_sim_manor() -> ManorState:
	var manor: ManorState = ManorState.new("manor_sim_test", "player_sim_test")
	manor.host_node_id = "xuchang"
	manor.household_troops = 400
	manor.set_resource("GRAIN", 2000)
	manor.set_resource("COIN", 1500)
	manor.set_resource("IRON", 500)
	manor.set_resource("WOOD", 500)
	manor.set_resource("WEAPONS", 100)
	manor.set_resource("HERBS_WINE", 200)

	var av: PawnEntity = PawnEntity.new("av_sim", "Sim_Lord", true)
	av.set_stat("LEA", 75)
	av.set_stat("MAR", 70)
	av.set_stat("INT", 65)
	av.set_stat("POL", 70)
	av.set_stat("CHA", 65)
	for i: int in range(12):
		av.set_schedule_activity(i, "WORK")
	var _ok1: bool = manor.add_pawn(av)
	return manor


func test_select_next_job_priority_tiebreaker_shichen_and_emergencies() -> void:
	var manor: ManorState = _make_sim_manor()
	var pawn: PawnEntity = manor.get_pawn_by_id("av_sim")
	assert_not_null(pawn, "Pawn exists")

	# All 7 domains set to priority 2 -> left-to-right tie-breaker selects LOGISTICS
	for dk: String in PawnEntity.WORK_DOMAINS:
		pawn.set_work_priority(dk, 2)
	var clk_work: SimClock = SimClock.new(8)  # ShiChen 4 = WORK
	assert_eq(ManorSimulator.select_next_job(pawn, manor, clk_work), "LOGISTICS", "Left-to-right tie-breaker picks LOGISTICS first")

	# Priority 1 on RESEARCH overrides Priority 2 on LOGISTICS
	pawn.set_work_priority("RESEARCH", 1)
	assert_eq(ManorSimulator.select_next_job(pawn, manor, clk_work), "RESEARCH", "Priority 1 beats Priority 2")

	# Both PATROL and AGRICULTURE set to Priority 1 -> PATROL precedes AGRICULTURE left-to-right
	pawn.set_work_priority("RESEARCH", 3)
	pawn.set_work_priority("AGRICULTURE", 1)
	pawn.set_work_priority("PATROL", 1)
	assert_eq(ManorSimulator.select_next_job(pawn, manor, clk_work), "PATROL", "Left-to-right Priority 1 picks PATROL before AGRICULTURE")

	# All domains disabled (priority 0) -> IDLE_STUDY_OR_GUARD
	for dk: String in PawnEntity.WORK_DOMAINS:
		pawn.set_work_priority(dk, 0)
	assert_eq(ManorSimulator.select_next_job(pawn, manor, clk_work), "IDLE_STUDY_OR_GUARD", "All priority 0 falls back to IDLE_STUDY_OR_GUARD")

	# 12-ShiChen schedule overrides
	pawn.set_work_priority("AGRICULTURE", 1)
	pawn.set_schedule_activity(0, "SLEEP")
	pawn.set_schedule_activity(3, "DRILL")
	pawn.set_schedule_activity(9, "RECREATION")

	pawn.set_need("REST", 5000)
	assert_eq(ManorSimulator.select_next_job(pawn, manor, SimClock.new(0)), "SLEEP_IN_QUARTERS", "SLEEP ShiChen schedules sleep when REST < 9000")
	pawn.set_need("REST", 9500)
	assert_eq(ManorSimulator.select_next_job(pawn, manor, SimClock.new(0)), "AGRICULTURE", "SLEEP ShiChen skipped when REST >= 9000")

	assert_eq(ManorSimulator.select_next_job(pawn, manor, SimClock.new(6)), "MARTIAL_DRILL_TRAINING", "DRILL ShiChen triggers MARTIAL_DRILL_TRAINING")

	pawn.set_need("MORALE", 5000)
	assert_eq(ManorSimulator.select_next_job(pawn, manor, SimClock.new(18)), "ATTEND_BANQUET_OR_RECREATION", "RECREATION ShiChen triggers banquet when MORALE < 8500")

	# Emergency overrides (priority order: WOUNDED/SEVERE_WOUND -> FOOD<1500 -> REST<1000)
	pawn.set_need("REST", 800)
	assert_eq(ManorSimulator.select_next_job(pawn, manor, clk_work), "SLEEP_IN_QUARTERS", "REST < 1000 triggers emergency sleep during WORK")

	pawn.set_need("FOOD", 1000)
	assert_eq(ManorSimulator.select_next_job(pawn, manor, clk_work), "EMERGENCY_EAT", "FOOD < 1500 overrides emergency sleep when GRAIN > 0")

	pawn.health_state = "SEVERE_WOUND"
	assert_eq(ManorSimulator.select_next_job(pawn, manor, clk_work), "INFIRMARY_CARE", "SEVERE_WOUND overrides emergency eat")

	# Raid defense & mental break & external state overrides
	pawn.health_state = "HEALTHY"
	manor.raid_defense_active = true
	assert_eq(ManorSimulator.select_next_job(pawn, manor, clk_work), "RAID_DEFENSE", "Active raid overrides normal work")
	manor.raid_defense_active = false

	pawn.trigger_mental_break("BREAK_MINOR_SECLUSION", 5)
	assert_eq(ManorSimulator.select_next_job(pawn, manor, clk_work), "BREAK_MINOR_SECLUSION", "Mental break returns break state")
	pawn.end_mental_break()

	pawn.state = "ON_EXPEDITION"
	assert_eq(ManorSimulator.select_next_job(pawn, manor, clk_work), "NONE_EXTERNAL", "ON_EXPEDITION pawn returns NONE_EXTERNAL")


func test_lod0_vs_lod1_promotion_demotion_and_remainder_carry_parity() -> void:
	var manor0: ManorState = _make_sim_manor()
	var p0: PawnEntity = manor0.get_pawn_by_id("av_sim")
	p0.set_work_priority("AGRICULTURE", 1)
	p0.set_work_priority("LOGISTICS", 2)
	p0.set_work_priority("PATROL", 2)

	ManorSimulator.promote_to_lod0(manor0)
	assert_eq(manor0.current_lod, 0, "promote_to_lod0 sets current_lod = 0")

	manor0.raid_defense_active = true
	ManorSimulator.demote_to_lod1(manor0)
	assert_eq(manor0.current_lod, 0, "Cannot demote to LOD 1 while raid_defense_active")
	manor0.raid_defense_active = false
	ManorSimulator.demote_to_lod1(manor0)
	assert_eq(manor0.current_lod, 1, "demote_to_lod1 sets current_lod = 1 when peaceful")

	# Reset two identical manors to compare 120 ticks of LOD 0 vs LOD 1 with permille remainder carry
	manor0.current_lod = 0
	var manor1: ManorState = ManorState.from_dict(manor0.to_dict())
	manor1.current_lod = 1

	var clk0: SimClock = SimClock.new(0)
	var clk1: SimClock = SimClock.new(0)
	var bus0: SimEventBus = SimEventBus.new()
	var bus1: SimEventBus = SimEventBus.new()

	for _t: int in range(120):
		var _t0: int = clk0.step_micro()
		ManorSimulator.step_lod0_micro_tick(manor0, clk0, 18401, bus0)

		var _t1: int = clk1.step_micro()
		if clk1.is_macro_tick():
			ManorSimulator.step_lod1_macro_tick(manor1, clk1, 18401, bus1)

	assert_gt(manor0.jobs_completed, 0, "LOD 0 completed jobs")
	assert_gt(manor1.jobs_completed, 0, "LOD 1 completed jobs")
	assert_eq(manor0.jobs_completed, manor1.jobs_completed, "Permille remainder carry achieves exact job count parity over 120 ticks")
	assert_eq(manor0.get_resource("GRAIN"), manor1.get_resource("GRAIN"), "Permille remainder carry achieves exact GRAIN parity over 120 ticks")
	assert_eq(manor0.get_resource("WOOD"), manor1.get_resource("WOOD"), "Permille remainder carry achieves exact WOOD parity over 120 ticks")

	# Verify determinism across two identical LOD 1 runs
	var manor1_dup: ManorState = ManorState.from_dict(_make_sim_manor().to_dict())
	var p1_dup: PawnEntity = manor1_dup.get_pawn_by_id("av_sim")
	p1_dup.set_work_priority("AGRICULTURE", 1)
	p1_dup.set_work_priority("LOGISTICS", 2)
	p1_dup.set_work_priority("PATROL", 2)
	manor1_dup.current_lod = 1
	var clk1_dup: SimClock = SimClock.new(0)
	var bus1_dup: SimEventBus = SimEventBus.new()
	for _t: int in range(120):
		var _td: int = clk1_dup.step_micro()
		if clk1_dup.is_macro_tick():
			ManorSimulator.step_lod1_macro_tick(manor1_dup, clk1_dup, 18401, bus1_dup)
	assert_eq(StateHasher.sha256_dict(manor1.to_dict()), StateHasher.sha256_dict(manor1_dup.to_dict()), "LOD 1 simulation is 100% deterministic")


func test_resolve_manor_raid_defense_vault_non_permadeath_and_truce() -> void:
	var manor: ManorState = _make_sim_manor()
	manor.current_lod = 1
	manor.household_troops = 100
	manor.wall_hp = 500
	manor.set_building_level("GRANARY_VAULT", 5)  # vault_protected_bp == 6000 (60% untouchable)
	manor.set_resource("GRAIN", 1000)
	manor.set_resource("COIN", 1000)
	manor.set_resource("IRON", 1000)
	manor.set_resource("WOOD", 1000)
	manor.set_resource("WEAPONS", 1000)

	var clk: SimClock = SimClock.new(500)
	var overwhelming_raid: Dictionary = {
		"attacker_entity_id": "raider_01",
		"attacker_power": {
			"troop_count": 2000,
			"lead_martial": 95,
			"lead_leadership": 95,
			"siege_bonus_bp": 1500
		}
	}

	var res: Dictionary = ManorSimulator.resolve_manor_raid_defense(
		manor, overwhelming_raid, clk, 18401, false
	)
	assert_true(_as_bool(res.get("breached", false)), "Overwhelming raid must breach manor")
	assert_eq(manor.current_lod, 0, "Incoming raid promotes manor to LOD 0")
	assert_false(manor.raid_defense_active, "raid_defense_active cleared after resolution")

	# Hidden Vault protection: vault_protected_bp = 6000 -> stealable = 4000 -> max_loot = 400 -> actual = 200
	# Guaranteed at least 60% (600) remains untouched
	for rk: String in ["GRAIN", "COIN", "IRON", "WOOD", "WEAPONS"]:
		assert_gte(manor.get_resource(rk), 600, "Hidden Vault must protect >= 60%% of %s" % rk)

	# Offline non-permadeath & 120-tick bribe immunity
	var av: PawnEntity = manor.get_pawn_by_id("av_sim")
	assert_eq(av.health_state, "SEVERE_WOUND", "Offline breached defender takes SEVERE_WOUND (non-permadeath)")
	assert_eq(av.state, "WOUNDED", "Offline breached defender transitions to WOUNDED")
	assert_eq(av.offline_bribe_immune_until_tick, 500 + 120, "Offline defender gets 120-tick bribe immunity")

	# 720-tick Post-Raid Truce Shield
	assert_eq(manor.truce_shield_until_tick, 500 + 720, "Breach activates 720-tick Post-Raid Truce Shield")
	assert_true(manor.is_truce_active(1219), "Truce active at tick 1219")

	# Follow-up raid while truce is active is blocked with zero loot
	var res_truce: Dictionary = ManorSimulator.resolve_manor_raid_defense(
		manor, overwhelming_raid, SimClock.new(600), 18401, false
	)
	assert_true(_as_bool(res_truce.get("truce_blocked", false)), "Follow-up raid during truce must be blocked")
	assert_false(_as_bool(res_truce.get("breached", true)), "Truce-blocked raid cannot breach")
	assert_eq(res_truce.get("looted", {"bad": 1}), {}, "Truce-blocked raid loots nothing")

	# Verify INFIRMARY_CARE recovers SEVERE_WOUND -> LIGHT_WOUND -> HEALTHY
	av.wound_recovery_pm = 0
	for _step: int in range(6):
		ManorSimulator.step_lod0_micro_tick(manor, SimClock.new(601), 18401, null)
	assert_ne(av.health_state, "SEVERE_WOUND", "INFIRMARY_CARE heals SEVERE_WOUND over ticks")


func test_dispatch_expedition_from_manor_atomic_and_event_bus() -> void:
	var manor: ManorState = _make_sim_manor()
	var clk: SimClock = SimClock.new(300)
	var bus: SimEventBus = SimEventBus.new()

	var before_troops: int = manor.household_troops
	var before_grain: int = manor.get_resource("GRAIN")
	var before_weapons: int = manor.get_resource("WEAPONS")
	var av: PawnEntity = manor.get_pawn_by_id("av_sim")

	# Invalid / overspend cases must leave state untouched and emit nothing
	var fail_troops: Dictionary = ManorSimulator.dispatch_expedition_from_manor(
		manor, ["av_sim"], 9999, 100, {"WEAPONS": 10}, ["edge_01"], "ARMY", clk, bus
	)
	assert_false(_as_bool(fail_troops.get("ok", true)), "Overspending troops must fail")
	assert_eq(fail_troops.get("error_code", ""), DtoSchemas.ERR_INSUFFICIENT_RESOURCE, "Returns ERR_INSUFFICIENT_RESOURCE")
	assert_eq(manor.household_troops, before_troops, "Failed dispatch must not deduct troops")
	assert_eq(av.state, "IN_MANOR", "Failed dispatch must not change pawn state")
	assert_eq(bus.peek_pending_count(), 0, "Failed dispatch must not emit event")

	var fail_cargo: Dictionary = ManorSimulator.dispatch_expedition_from_manor(
		manor, ["av_sim"], 100, 100, {"WEAPONS": 9999}, ["edge_01"], "ARMY", clk, bus
	)
	assert_false(_as_bool(fail_cargo.get("ok", true)), "Overspending cargo must fail atomically")
	assert_eq(manor.household_troops, before_troops, "Troops intact after cargo failure")
	assert_eq(manor.get_resource("GRAIN"), before_grain, "Grain intact after cargo failure")

	var fail_edge: Dictionary = ManorSimulator.dispatch_expedition_from_manor(
		manor, ["av_sim"], 100, 100, {"WEAPONS": 10}, [], "ARMY", clk, bus
	)
	assert_false(_as_bool(fail_edge.get("ok", true)), "Empty path_edge_ids rejected")

	# Valid dispatch
	var ok_res: Dictionary = ManorSimulator.dispatch_expedition_from_manor(
		manor, ["av_sim"], 150, 300, {"WEAPONS": 25}, ["edge_xc_01", "edge_xc_02"], "ARMY", clk, bus
	)
	assert_true(_as_bool(ok_res.get("ok", false)), "Valid expedition dispatch succeeds")
	assert_eq(manor.household_troops, before_troops - 150, "Troops atomically deducted")
	assert_eq(manor.get_resource("GRAIN"), before_grain - 300, "Carried grain atomically deducted")
	assert_eq(manor.get_resource("WEAPONS"), before_weapons - 25, "Cargo atomically deducted")
	assert_eq(av.state, "ON_EXPEDITION", "Dispatched pawn transitions to ON_EXPEDITION")
	assert_eq(bus.peek_pending_count(), 1, "Exactly 1 event emitted on SimEventBus")

	var drained: Array[Dictionary] = bus.drain_for_tick(300)
	assert_eq(drained.size(), 1, "Event drained for tick 300")
	var ev: Dictionary = drained[0]
	assert_eq(ev.get("event", ""), SimEventBus.EVENT_MICRO_TO_MACRO_EXPEDITION_DISPATCHED, "Correct event constant emitted")
	var payload_v: Variant = ev.get("payload", {})
	assert_true(payload_v is Dictionary, "Payload is Dictionary")
	if payload_v is Dictionary:
		var payload: Dictionary = payload_v
		assert_true(SimEventBus.validate_expedition_dispatched(payload), "Payload passes SimEventBus.validate_expedition_dispatched")
		assert_eq(_as_int(payload.get("troop_count", 0)), 150, "Payload troop_count == 150")
		assert_eq(_as_int(payload.get("carried_grain", 0)), 300, "Payload carried_grain == 300")

	# Cannot dispatch pawn that is already ON_EXPEDITION
	var fail_dup: Dictionary = ManorSimulator.dispatch_expedition_from_manor(
		manor, ["av_sim"], 50, 50, {}, ["edge_01"], "ARMY", clk, bus
	)
	assert_false(_as_bool(fail_dup.get("ok", true)), "Cannot dispatch pawn already ON_EXPEDITION")
	assert_eq(fail_dup.get("error_code", ""), DtoSchemas.ERR_INVALID_STATE, "Returns ERR_INVALID_STATE")
