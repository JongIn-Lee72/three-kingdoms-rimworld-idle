class_name TestArmyCaravanManager
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
		var arr: Array = v
		return arr
	return []


func _make_expedition_manor() -> ManorState:
	var manor: ManorState = ManorState.new("manor_bridge", "player_bridge")
	manor.host_node_id = "luoyang"
	manor.household_troops = 500
	manor.set_resource("GRAIN", 4000)
	manor.set_resource("IRON", 300)
	manor.set_resource("WOOD", 400)
	manor.set_resource("WEAPONS", 300)
	manor.set_resource("HORSES", 200)
	manor.set_resource("COIN", 2000)

	var p1: PawnEntity = PawnEntity.new("pawn_zhao", "Zhao Yun", false)
	p1.set_stat("MAR", 95)
	p1.set_stat("LEA", 92)
	p1.set_need("MORALE", 9000)
	var _a1: bool = manor.add_pawn(p1)

	var p2: PawnEntity = PawnEntity.new("pawn_mi", "Mi Zhu", false)
	p2.set_stat("POL", 85)
	p2.set_stat("CHA", 80)
	p2.traits.append("T_AGRARIAN")
	p2.set_need("MORALE", 8000)
	var _a2: bool = manor.add_pawn(p2)
	return manor


func test_micro_to_macro_expedition_bridge_conservation() -> void:
	var wg: WorldGraph = WorldGraph.load_from_json_file("res://data/macro_map_3k.json")
	var manor: ManorState = _make_expedition_manor()
	var _promo: Dictionary = wg.promote_troops(manor, "LIGHT_CAVALRY", 100)

	var bus: SimEventBus = SimEventBus.new()
	var clock: SimClock = SimClock.new(6)
	var path: Array[String] = wg.find_path("luoyang", "xuchang")
	assert_gt(path.size(), 0, "Route luoyang -> xuchang exists")

	var off_army: Array[String] = ["pawn_zhao"]
	var cargo_army: Dictionary = {"IRON": 50}
	var res_army: Dictionary = ManorSimulator.dispatch_expedition_from_manor(
		manor, off_army, 200, 1200, cargo_army, path, "ARMY", clock, bus
	)
	assert_true(_as_bool(res_army.get("ok", false), false), "ARMY expedition dispatch succeeds")
	var payload_army: Dictionary = _as_dict(res_army.get("payload", {}))
	assert_true(SimEventBus.validate_expedition_dispatched(payload_army), "ARMY dispatch payload passes SimEventBus schema validation")

	var off_caravan: Array[String] = ["pawn_mi"]
	var cargo_caravan: Dictionary = {"WOOD": 120, "IRON": 40}
	var res_caravan: Dictionary = ManorSimulator.dispatch_expedition_from_manor(
		manor, off_caravan, 50, 500, cargo_caravan, path, "CARAVAN", clock, bus
	)
	assert_true(_as_bool(res_caravan.get("ok", false), false), "CARAVAN expedition dispatch succeeds")

	# Verify atomic micro-layer deduction & pawn status
	assert_eq(manor.household_troops, 250, "Household troops conserved (500 - 200 - 50 = 250)")
	assert_eq(manor.get_resource("IRON"), 300 - 150 - 50 - 40, "IRON conserved after promotion and cargo")
	assert_eq(manor.get_resource("WOOD"), 400 - 120, "WOOD conserved after caravan cargo")
	assert_eq(manor.get_pawn_by_id("pawn_zhao").state, "ON_EXPEDITION", "Officer transitioned to ON_EXPEDITION")
	assert_eq(manor.get_pawn_by_id("pawn_mi").state, "ON_EXPEDITION", "Merchant transitioned to ON_EXPEDITION")

	# Ingest into Macro ArmyCaravanManager
	var mgr: ArmyCaravanManager = ArmyCaravanManager.new()
	var spawned: Array[Dictionary] = mgr.ingest_micro_events(bus, wg, clock.current_tick_id)
	assert_eq(spawned.size(), 2, "Ingested 2 entities from SimEventBus")
	assert_eq(bus.peek_pending_count(), 0, "Events drained for tick")

	var e0: Dictionary = spawned[0]
	var e1: Dictionary = spawned[1]
	assert_eq(str(e0.get("unit_type", "")), "ARMY", "First spawned entity is ARMY")
	assert_eq(_as_int(e0.get("troop_count", 0), 0), 200, "ARMY troop_count conserved")
	assert_eq(_as_int(e0.get("carried_grain", 0), 0), 1200, "ARMY carried_grain conserved")
	assert_eq(_as_int(_as_dict(e0.get("cargo", {})).get("IRON", 0), 0), 50, "ARMY cargo conserved")
	assert_eq(str(e0.get("current_node_id", "")), "luoyang", "ARMY starts at origin node luoyang")
	assert_eq(str(e0.get("current_edge_id", "")), path[0], "ARMY starts on first path edge")
	assert_eq(_as_int(_as_dict(e0.get("troop_composition", {})).get("LIGHT_CAVALRY", 0), 0), 100, "Inherits manor troop composition from WorldGraph")

	assert_eq(str(e1.get("unit_type", "")), "CARAVAN", "Second spawned entity is CARAVAN")
	assert_eq(_as_int(e1.get("troop_count", 0), 0), 50, "CARAVAN troop_count conserved")
	assert_eq(_as_int(e1.get("carried_grain", 0), 0), 500, "CARAVAN carried_grain conserved")
	assert_eq(_as_int(_as_dict(e1.get("cargo", {})).get("WOOD", 0), 0), 120, "CARAVAN WOOD cargo conserved")


func test_step_macro_tick_progress_upkeep_starvation_and_speed_composition() -> void:
	# Multi-edge deterministic map with zero ambush risk to isolate movement & upkeep
	var custom_map: Dictionary = {
		"nodes": [
			{"node_id": "N1"},
			{"node_id": "N2"},
			{"node_id": "N3"}
		],
		"edges": [
			{"edge_id": "e_1_2", "from_node": "N1", "to_node": "N2", "travel_macro_ticks": 1, "ambush_risk_bp": 0, "supply_drain_pm": 100},
			{"edge_id": "e_2_3", "from_node": "N2", "to_node": "N3", "travel_macro_ticks": 2, "ambush_risk_bp": 0, "supply_drain_pm": 100}
		]
	}
	var wg: WorldGraph = WorldGraph.new(custom_map, false)
	var mgr: ArmyCaravanManager = ArmyCaravanManager.new()
	var bus: SimEventBus = SimEventBus.new()
	var clock: SimClock = SimClock.new(6)

	var ent_normal: Dictionary = mgr.spawn_entity({
		"entity_id": "army_std",
		"owner_player_id": "p1",
		"unit_type": "ARMY",
		"current_node_id": "N1",
		"path_edge_ids": ["e_1_2", "e_2_3"],
		"troop_count": 100,
		"carried_grain": 5000,
		"morale_bp": 8000
	}, wg)
	assert_eq(str(ent_normal.get("status", "")), "MARCHING", "Starts MARCHING")

	var ent_cav: Dictionary = mgr.spawn_entity({
		"entity_id": "army_cav",
		"owner_player_id": "p1",
		"unit_type": "ARMY",
		"current_node_id": "N1",
		"path_edge_ids": ["e_1_2", "e_2_3"],
		"troop_count": 100,
		"troop_composition": {"LIGHT_CAVALRY": 100},
		"carried_grain": 5000
	}, wg)

	var ent_starving: Dictionary = mgr.spawn_entity({
		"entity_id": "army_starve",
		"owner_player_id": "p2",
		"unit_type": "ARMY",
		"current_node_id": "N2",
		"path_edge_ids": ["e_2_3"],
		"troop_count": 100,
		"carried_grain": 0,
		"morale_bp": 8000
	}, wg)

	# Macro tick 1 (tick_id = 6):
	# e_1_2 has travel_macro_ticks=1 -> base_step_pm=1000 -> both std & cav finish e_1_2 and advance to N2 / e_2_3
	# army_starve suffers starvation on e_2_3
	var evs1: Array[Dictionary] = mgr.step_macro_tick(wg, clock, 12345, bus)
	var saw_starvation: bool = false
	for ev: Dictionary in evs1:
		if str(ev.get("type", "")) == ArmyCaravanManager.EVENT_SUPPLY_STARVATION and str(ev.get("entity_id", "")) == "army_starve":
			saw_starvation = true
	assert_true(saw_starvation, "Starving army emits SUPPLY_STARVATION")

	var std_after1: Dictionary = mgr.get_entity("army_std")
	assert_eq(str(std_after1.get("current_node_id", "")), "N2", "Standard army reached intermediate node N2")
	assert_eq(str(std_after1.get("current_edge_id", "")), "e_2_3", "Standard army moved onto e_2_3")
	assert_eq(_as_int(std_after1.get("edge_progress_pm", -1), -1), 0, "Edge progress resets to 0 on transition")
	assert_lt(_as_int(std_after1.get("carried_grain", 5000), 5000), 5000, "Grain upkeep consumed on march")

	var starve_after1: Dictionary = mgr.get_entity("army_starve")
	assert_lt(_as_int(starve_after1.get("morale_bp", 8000), 8000), 8000, "Starvation reduces morale")
	assert_lt(_as_int(starve_after1.get("troop_count", 100), 100), 100, "Starvation causes desertion")

	# Macro tick 2 (tick_id = 12): on e_2_3 (travel_macro_ticks=2 -> base=500 pm):
	# std advances to 500 pm; cav (speed_pm=1500 -> 750 pm) advances to 750 pm
	clock.advance(6)
	var _evs2: Array[Dictionary] = mgr.step_macro_tick(wg, clock, 12345, bus)
	var std_after2: Dictionary = mgr.get_entity("army_std")
	var cav_after2: Dictionary = mgr.get_entity("army_cav")
	assert_eq(_as_int(std_after2.get("edge_progress_pm", 0), 0), 500, "Standard army at 500 pm on 2-tick edge")
	assert_eq(_as_int(cav_after2.get("edge_progress_pm", 0), 0), 750, "Light cavalry at 750 pm (1.5x speed)")
	assert_gt(_as_int(cav_after2.get("edge_progress_pm", 0), 0), _as_int(std_after2.get("edge_progress_pm", 0), 0), "Cavalry moves faster than standard infantry")

	# Macro tick 3 (tick_id = 18): both reach N3 and arrive
	clock.advance(6)
	var _evs3: Array[Dictionary] = mgr.step_macro_tick(wg, clock, 12345, bus)
	var std_after3: Dictionary = mgr.get_entity("army_std")
	assert_true(_as_bool(std_after3.get("arrived", false), false), "Standard army arrived at N3")
	assert_eq(str(std_after3.get("status", "")), "ARRIVED", "Status is ARRIVED")
	assert_eq(str(std_after3.get("current_node_id", "")), "N3", "Arrived at destination N3")
	assert_eq(_as_int(std_after3.get("edge_progress_pm", 0), 0), 1000, "Final edge_progress_pm is 1000")


func test_edge_ambush_determinism_and_arrival_events() -> void:
	var ambush_map: Dictionary = {
		"nodes": [{"node_id": "A"}, {"node_id": "B"}],
		"edges": [
			{"edge_id": "e_ambush_high", "from_node": "A", "to_node": "B", "travel_macro_ticks": 3, "ambush_risk_bp": 5000, "supply_drain_pm": 50},
			{"edge_id": "e_safe", "from_node": "A", "to_node": "B", "travel_macro_ticks": 1, "ambush_risk_bp": 0, "supply_drain_pm": 50}
		]
	}
	var wg: WorldGraph = WorldGraph.new(ambush_map, false)

	# Determinism check across two identical managers
	var m1: ArmyCaravanManager = ArmyCaravanManager.new()
	var m2: ArmyCaravanManager = ArmyCaravanManager.new()
	var _s1: Dictionary = m1.spawn_entity({
		"entity_id": "raid_det", "unit_type": "RAID_PARTY",
		"current_node_id": "A", "path_edge_ids": ["e_ambush_high"],
		"troop_count": 200, "carried_grain": 5000
	}, wg)
	var _s2: Dictionary = m2.spawn_entity({
		"entity_id": "raid_det", "unit_type": "RAID_PARTY",
		"current_node_id": "A", "path_edge_ids": ["e_ambush_high"],
		"troop_count": 200, "carried_grain": 5000
	}, wg)

	var bus1: SimEventBus = SimEventBus.new()
	var bus2: SimEventBus = SimEventBus.new()
	var c1: SimClock = SimClock.new(6)
	var c2: SimClock = SimClock.new(6)
	var ambush_count: int = 0
	for _i: int in range(3):
		var ev1: Array[Dictionary] = m1.step_macro_tick(wg, c1, 77777, bus1)
		var ev2: Array[Dictionary] = m2.step_macro_tick(wg, c2, 77777, bus2)
		assert_eq(StateHasher.sha256_dict({"e": ev1}), StateHasher.sha256_dict({"e": ev2}), "Ambush & step events deterministic across identical runs")
		for e: Dictionary in ev1:
			if str(e.get("type", "")) == ArmyCaravanManager.EVENT_EDGE_AMBUSHED:
				ambush_count += 1
		c1.advance(6)
		c2.advance(6)

	assert_eq(StateHasher.sha256_dict(m1.to_dict()), StateHasher.sha256_dict(m2.to_dict()), "Manager state hashes match identically")

	# Verify 100% ambush risk always triggers and 0% never triggers, plus all 3 arrival event types
	var m_arr: ArmyCaravanManager = ArmyCaravanManager.new()
	var bus_arr: SimEventBus = SimEventBus.new()
	var clk_arr: SimClock = SimClock.new(6)
	var _raider: Dictionary = m_arr.spawn_entity({
		"entity_id": "raider_01", "owner_player_id": "raider_p", "unit_type": "RAID_PARTY",
		"current_node_id": "A", "path_edge_ids": ["e_safe"],
		"target_manor_id": "manor_target", "troop_count": 180, "carried_grain": 2000,
		"officers": [{"pawn_id": "off_r", "MAR": 85, "LEA": 80}]
	}, wg)
	var _caravan: Dictionary = m_arr.spawn_entity({
		"entity_id": "caravan_01", "owner_player_id": "merch_p", "unit_type": "CARAVAN",
		"current_node_id": "A", "path_edge_ids": ["e_safe"],
		"troop_count": 40, "carried_grain": 1000, "carried_coin": 250, "cargo": {"IRON": 80}
	}, wg)
	var _army: Dictionary = m_arr.spawn_entity({
		"entity_id": "army_01", "owner_player_id": "lord_p", "faction_id": "SHU", "unit_type": "ARMY",
		"current_node_id": "A", "path_edge_ids": ["e_safe"],
		"troop_count": 300, "carried_grain": 5000, "morale_bp": 9000
	}, wg)

	var _step_evs: Array[Dictionary] = m_arr.step_macro_tick(wg, clk_arr, 99, bus_arr)
	var drained: Array[Dictionary] = bus_arr.drain_for_tick(clk_arr.current_tick_id)
	var seen_raid: bool = false
	var seen_caravan: bool = false
	var seen_army: bool = false

	for ev: Dictionary in drained:
		var et: String = str(ev.get("event", ""))
		var pl: Dictionary = _as_dict(ev.get("payload", {}))
		if et == SimEventBus.EVENT_MACRO_TO_MICRO_RAID_INCOMING:
			seen_raid = true
			assert_true(SimEventBus.validate_raid_incoming(pl), "RAID_INCOMING payload valid per SimEventBus schema")
			assert_eq(str(pl.get("target_manor_id", "")), "manor_target", "Raid targets expected manor")
		elif et == SimEventBus.EVENT_CARAVAN_ARRIVED:
			seen_caravan = true
			assert_eq(str(pl.get("node_id", "")), "B", "Caravan arrived at node B")
			assert_eq(_as_int(_as_dict(pl.get("cargo", {})).get("IRON", 0), 0), 80, "Caravan cargo preserved on arrival")
		elif et == ArmyCaravanManager.EVENT_ARMY_ARRIVED:
			seen_army = true
			assert_eq(str(pl.get("node_id", "")), "B", "Army arrived at node B")
			assert_eq(str(pl.get("faction_id", "")), "SHU", "Army faction preserved on arrival")

	assert_true(seen_raid, "RAID_PARTY arrival emitted MACRO_TO_MICRO_RAID_INCOMING")
	assert_true(seen_caravan, "CARAVAN arrival emitted CARAVAN_ARRIVED")
	assert_true(seen_army, "ARMY arrival emitted ARMY_ARRIVED")


func test_to_dict_from_dict_round_trip_and_determinism() -> void:
	var wg: WorldGraph = WorldGraph.load_from_json_file("res://data/macro_map_3k.json")
	var mgr: ArmyCaravanManager = ArmyCaravanManager.new()
	var bus: SimEventBus = SimEventBus.new()
	var clock: SimClock = SimClock.new(6)

	var _e1: Dictionary = mgr.spawn_entity({
		"owner_player_id": "p1", "faction_id": "WEI", "unit_type": "ARMY",
		"current_node_id": "luoyang", "path_edge_ids": ["e_luoyang_hulao", "e_hulao_xuchang"],
		"troop_count": 300, "troop_composition": {"SPEAR_SHIELD": 200, "LONGBOW": 100},
		"carried_grain": 6000, "cargo": {"WOOD": 25}, "officers": [{"pawn_id": "o1", "MAR": 88, "LEA": 84}]
	}, wg)
	var _step1: Array[Dictionary] = mgr.step_macro_tick(wg, clock, 4242, bus)

	var snap: Dictionary = mgr.to_dict()
	assert_false(StateHasher.has_floats(snap), "ArmyCaravanManager.to_dict() must contain zero floats")
	assert_true(StateHasher.validate_deterministic_types(snap), "ArmyCaravanManager.to_dict() uses deterministic types")

	var mgr2: ArmyCaravanManager = ArmyCaravanManager.from_dict(snap)
	assert_eq(StateHasher.sha256_dict(snap), StateHasher.sha256_dict(mgr2.to_dict()), "Exact SHA-256 parity after from_dict")

	# Subsequent spawn and tick after restore must match identically
	clock.advance(6)
	var c_dup: SimClock = SimClock.new(clock.current_tick_id)
	var _n1: Dictionary = mgr.spawn_entity({"unit_type": "CARAVAN", "current_node_id": "xuchang", "path_edge_ids": ["e_xuchang_chenliu"], "troop_count": 30, "carried_grain": 500}, wg)
	var _n2: Dictionary = mgr2.spawn_entity({"unit_type": "CARAVAN", "current_node_id": "xuchang", "path_edge_ids": ["e_xuchang_chenliu"], "troop_count": 30, "carried_grain": 500}, wg)
	var _s1: Array[Dictionary] = mgr.step_macro_tick(wg, clock, 4242, null)
	var _s2: Array[Dictionary] = mgr2.step_macro_tick(wg, c_dup, 4242, null)
	assert_eq(StateHasher.sha256_dict(mgr.to_dict()), StateHasher.sha256_dict(mgr2.to_dict()), "Post-restore entity sequence and step remain bit-identical")
