class_name TestWorldGraph
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


func _make_rich_manor(manor_id: String = "manor_promo", troops: int = 100) -> ManorState:
	var manor: ManorState = ManorState.new(manor_id, "player_promo")
	manor.household_troops = troops
	manor.set_resource("GRAIN", 5000)
	manor.set_resource("COIN", 5000)
	manor.set_resource("WOOD", 5000)
	manor.set_resource("IRON", 5000)
	manor.set_resource("HORSES", 5000)
	manor.set_resource("HERBS_WINE", 1000)
	manor.set_resource("WEAPONS", 5000)
	return manor


func test_load_macro_map_3k_nodes_provinces_edges_and_unit_types() -> void:
	var wg: WorldGraph = WorldGraph.load_from_json_file("res://data/macro_map_3k.json")
	var node_ids: Array[String] = wg.get_node_ids()
	var edge_ids: Array[String] = wg.get_edge_ids()

	assert_eq(node_ids.size(), 15, "macro_map_3k.json must load exactly 15 nodes")
	assert_gte(edge_ids.size(), 22, "macro_map_3k.json must load at least 22 edges")
	assert_eq(wg.unit_specs.size(), 6, "Must have 6 canonical unit types")

	var provinces: Dictionary = {}
	var starter_count: int = 0
	for nid: String in node_ids:
		assert_true(wg.has_node(nid), "has_node true for " + nid)
		var nd: Dictionary = wg.get_node(nid)
		var prov: String = str(nd.get("province", ""))
		assert_false(prov.is_empty(), "Node province non-empty for " + nid)
		provinces[prov] = true
		if _as_bool(nd.get("is_starter_county", false), false):
			starter_count += 1
		assert_gt(_as_int(nd.get("max_fortification_hp", 0), 0), 0, "max_fortification_hp > 0 for " + nid)
		var amm: Dictionary = _as_dict(nd.get("amm_reserves", {}))
		assert_gt(_as_int(amm.get("grain", 0), 0), 0, "AMM grain reserve > 0 for " + nid)

	assert_eq(provinces.size(), 9, "15 nodes must span 9 unique provinces")
	assert_eq(starter_count, 5, "Should have 5 starter counties")

	for ut: String in WorldGraph.UNIT_TYPES:
		var spec: Dictionary = wg.get_unit_spec(ut)
		assert_eq(str(spec.get("unit_type_id", "")), ut, "Unit spec present for " + ut)
		assert_gt(_as_int(spec.get("speed_pm", 0), 0), 0, "Unit speed_pm > 0 for " + ut)

	for eid: String in edge_ids:
		assert_true(wg.has_edge(eid), "has_edge true for " + eid)
		var ed: Dictionary = wg.get_edge(eid)
		var fn: String = str(ed.get("from_node", ""))
		var tn: String = str(ed.get("to_node", ""))
		assert_true(wg.has_node(fn), "Edge from_node exists: " + fn)
		assert_true(wg.has_node(tn), "Edge to_node exists: " + tn)
		assert_eq(wg.get_other_endpoint(eid, fn), tn, "get_other_endpoint forward")
		assert_eq(wg.get_other_endpoint(eid, tn), fn, "get_other_endpoint reverse")

	assert_eq(wg.get_other_endpoint("non_existent_edge", "luoyang"), "", "Unknown edge returns empty")
	assert_eq(wg.get_other_endpoint(edge_ids[0], "non_existent_node"), "", "Non-endpoint returns empty")


func test_dijkstra_find_path_connectivity_and_deterministic_tie_breaking() -> void:
	var wg: WorldGraph = WorldGraph.load_from_json_file("res://data/macro_map_3k.json")
	var node_ids: Array[String] = wg.get_node_ids()

	# Verify full graph connectivity across all 15x15 ordered pairs
	for src: String in node_ids:
		assert_eq(wg.find_path(src, src).size(), 0, "Self path is empty for " + src)
		for dst: String in node_ids:
			if src == dst:
				continue
			var path: Array[String] = wg.find_path(src, dst)
			assert_gt(path.size(), 0, "Path must exist between %s and %s" % [src, dst])
			var cur: String = src
			var total_ticks: int = 0
			for eid: String in path:
				var ed: Dictionary = wg.get_edge(eid)
				total_ticks += _as_int(ed.get("travel_macro_ticks", 0), 0)
				cur = wg.get_other_endpoint(eid, cur)
				assert_false(cur.is_empty(), "Path edge %s must connect from current node" % eid)
			assert_eq(cur, dst, "Path from %s must terminate at %s" % [src, dst])
			assert_gt(total_ticks, 0, "Total path cost > 0")

	# Distant route sanity & determinism
	var p_ji_cheng1: Array[String] = wg.find_path("jicheng", "chengdu")
	var p_ji_cheng2: Array[String] = wg.find_path("jicheng", "chengdu")
	assert_eq(p_ji_cheng1, p_ji_cheng2, "Repeated find_path must be identical")
	assert_gte(p_ji_cheng1.size(), 4, "jicheng -> chengdu requires multiple hops")

	# Boundary/invalid node checks
	assert_eq(wg.find_path("", "luoyang").size(), 0, "Empty source returns empty")
	assert_eq(wg.find_path("luoyang", "").size(), 0, "Empty dest returns empty")
	assert_eq(wg.find_path("luoyang", "atlantis").size(), 0, "Unknown node returns empty")

	# Custom graph for deterministic tie-breaking:
	# 1) Fewer hops wins when total travel_macro_ticks is equal (2 ticks, 1 hop vs 2 hops)
	# 2) Lexicographically smaller edge_id wins when distance and hops are equal
	var custom_a: Dictionary = {
		"nodes": [
			{"node_id": "A"},
			{"node_id": "B1"},
			{"node_id": "B2"},
			{"node_id": "C"}
		],
		"edges": [
			{"edge_id": "e_hop_z", "from_node": "A", "to_node": "B2", "travel_macro_ticks": 2},
			{"edge_id": "e_hop_y", "from_node": "B2", "to_node": "C", "travel_macro_ticks": 2},
			{"edge_id": "e_mid_b", "from_node": "A", "to_node": "B1", "travel_macro_ticks": 2},
			{"edge_id": "e_mid_c", "from_node": "B1", "to_node": "C", "travel_macro_ticks": 2},
			{"edge_id": "e_direct_4", "from_node": "A", "to_node": "C", "travel_macro_ticks": 4}
		]
	}
	var custom_b: Dictionary = {
		"nodes": [
			{"node_id": "C"},
			{"node_id": "B2"},
			{"node_id": "B1"},
			{"node_id": "A"}
		],
		"edges": [
			{"edge_id": "e_direct_4", "from_node": "A", "to_node": "C", "travel_macro_ticks": 4},
			{"edge_id": "e_mid_c", "from_node": "B1", "to_node": "C", "travel_macro_ticks": 2},
			{"edge_id": "e_mid_b", "from_node": "A", "to_node": "B1", "travel_macro_ticks": 2},
			{"edge_id": "e_hop_y", "from_node": "B2", "to_node": "C", "travel_macro_ticks": 2},
			{"edge_id": "e_hop_z", "from_node": "A", "to_node": "B2", "travel_macro_ticks": 2}
		]
	}
	var wg_ca: WorldGraph = WorldGraph.new(custom_a, false)
	var wg_cb: WorldGraph = WorldGraph.new(custom_b, false)
	var path_ca: Array[String] = wg_ca.find_path("A", "C")
	var path_cb: Array[String] = wg_cb.find_path("A", "C")
	assert_eq(path_ca, ["e_direct_4"], "Equal cost (4) prefers 1-hop path over 2-hop paths")
	assert_eq(path_ca, path_cb, "Tie-break result is independent of input order")

	# Remove direct edge to test lexicographical path tie-break among equal-cost equal-hop paths
	var custom_lex_a: Dictionary = {
		"nodes": [{"node_id": "A"}, {"node_id": "B1"}, {"node_id": "B2"}, {"node_id": "C"}],
		"edges": [
			{"edge_id": "e_z1", "from_node": "A", "to_node": "B2", "travel_macro_ticks": 2},
			{"edge_id": "e_z2", "from_node": "B2", "to_node": "C", "travel_macro_ticks": 2},
			{"edge_id": "e_a1", "from_node": "A", "to_node": "B1", "travel_macro_ticks": 2},
			{"edge_id": "e_a2", "from_node": "B1", "to_node": "C", "travel_macro_ticks": 2}
		]
	}
	var wg_lex: WorldGraph = WorldGraph.new(custom_lex_a, false)
	assert_eq(wg_lex.find_path("A", "C"), ["e_a1", "e_a2"], "Equal cost & hops selects lexicographically smallest edge sequence")


func test_promote_troops_atomic_deduction_and_rejections() -> void:
	var wg: WorldGraph = WorldGraph.load_from_json_file("res://data/macro_map_3k.json")
	var manor: ManorState = _make_rich_manor("manor_p1", 100)

	# 1. SPEAR_SHIELD (count=10): GRAIN=10, WEAPONS=10, IRON=10, WOOD=5
	var g0: int = manor.get_resource("GRAIN")
	var w0: int = manor.get_resource("WEAPONS")
	var i0: int = manor.get_resource("IRON")
	var wd0: int = manor.get_resource("WOOD")
	var res_spear: Dictionary = wg.promote_troops(manor, "SPEAR_SHIELD", 10)
	assert_true(_as_bool(res_spear.get("ok", false), false), "SPEAR_SHIELD promotion succeeds")
	assert_eq(manor.get_resource("GRAIN"), g0 - 10, "SPEAR_SHIELD deducts 10 GRAIN")
	assert_eq(manor.get_resource("WEAPONS"), w0 - 10, "SPEAR_SHIELD deducts 10 WEAPONS")
	assert_eq(manor.get_resource("IRON"), i0 - 10, "SPEAR_SHIELD deducts 10 IRON")
	assert_eq(manor.get_resource("WOOD"), wd0 - 5, "SPEAR_SHIELD deducts 5 WOOD")

	# 2. LIGHT_CAVALRY (count=10): GRAIN=10, WEAPONS=10, IRON=15, HORSES=10
	var h1: int = manor.get_resource("HORSES")
	var i1: int = manor.get_resource("IRON")
	var res_lc: Dictionary = wg.promote_troops(manor, "LIGHT_CAVALRY", 10)
	assert_true(_as_bool(res_lc.get("ok", false), false), "LIGHT_CAVALRY promotion succeeds")
	assert_eq(manor.get_resource("HORSES"), h1 - 10, "LIGHT_CAVALRY deducts 10 HORSES")
	assert_eq(manor.get_resource("IRON"), i1 - 15, "LIGHT_CAVALRY deducts 15 IRON")

	# 3. HEAVY_CATAPHRACT (count=10): GRAIN=10, WEAPONS=10, IRON=40, HORSES=20, COIN=10
	var c2: int = manor.get_resource("COIN")
	var h2: int = manor.get_resource("HORSES")
	var i2: int = manor.get_resource("IRON")
	var res_hc: Dictionary = wg.promote_troops(manor, "HEAVY_CATAPHRACT", 10)
	assert_true(_as_bool(res_hc.get("ok", false), false), "HEAVY_CATAPHRACT promotion succeeds")
	assert_eq(manor.get_resource("IRON"), i2 - 40, "HEAVY_CATAPHRACT deducts 40 IRON")
	assert_eq(manor.get_resource("HORSES"), h2 - 20, "HEAVY_CATAPHRACT deducts 20 HORSES")
	assert_eq(manor.get_resource("COIN"), c2 - 10, "HEAVY_CATAPHRACT deducts 10 COIN")

	# 4. SIEGE_ENGINE (count=10): GRAIN=10, WEAPONS=10, IRON=50, WOOD=60, COIN=40
	var c3: int = manor.get_resource("COIN")
	var wd3: int = manor.get_resource("WOOD")
	var i3: int = manor.get_resource("IRON")
	var res_se: Dictionary = wg.promote_troops(manor, "SIEGE_ENGINE", 10)
	assert_true(_as_bool(res_se.get("ok", false), false), "SIEGE_ENGINE promotion succeeds")
	assert_eq(manor.get_resource("IRON"), i3 - 50, "SIEGE_ENGINE deducts 50 IRON")
	assert_eq(manor.get_resource("WOOD"), wd3 - 60, "SIEGE_ENGINE deducts 60 WOOD")
	assert_eq(manor.get_resource("COIN"), c3 - 40, "SIEGE_ENGINE deducts 40 COIN")

	assert_eq(wg.get_manor_total_promoted(manor.manor_id), 40, "Total promoted troops == 40")
	var comp: Dictionary = wg.get_manor_troop_composition(manor.manor_id)
	assert_eq(_as_int(comp.get("SPEAR_SHIELD", 0), 0), 10, "10 SPEAR_SHIELD recorded")
	assert_eq(_as_int(comp.get("LIGHT_CAVALRY", 0), 0), 10, "10 LIGHT_CAVALRY recorded")
	assert_eq(_as_int(comp.get("HEAVY_CATAPHRACT", 0), 0), 10, "10 HEAVY_CATAPHRACT recorded")
	assert_eq(_as_int(comp.get("SIEGE_ENGINE", 0), 0), 10, "10 SIEGE_ENGINE recorded")

	# Rejection 1: Insufficient unpromoted household troops (60 remaining, ask 61)
	var snap_grain: int = manor.get_resource("GRAIN")
	var snap_iron: int = manor.get_resource("IRON")
	var res_over_troops: Dictionary = wg.promote_troops(manor, "SPEAR_SHIELD", 61)
	assert_false(_as_bool(res_over_troops.get("ok", true), true), "Reject promotion exceeding unpromoted troops")
	assert_eq(str(res_over_troops.get("error_code", "")), DtoSchemas.ERR_INSUFFICIENT_RESOURCE, "Over troops returns ERR_INSUFFICIENT_RESOURCE")
	assert_eq(manor.get_resource("GRAIN"), snap_grain, "Atomic failure must not deduct GRAIN")
	assert_eq(manor.get_resource("IRON"), snap_iron, "Atomic failure must not deduct IRON")

	# Rejection 2: Insufficient HORSES for cavalry (atomic check)
	manor.set_resource("HORSES", 5)
	var snap_weapons: int = manor.get_resource("WEAPONS")
	var snap_iron_cav: int = manor.get_resource("IRON")
	var res_no_horses: Dictionary = wg.promote_troops(manor, "HEAVY_CATAPHRACT", 10)
	assert_false(_as_bool(res_no_horses.get("ok", true), true), "Reject HEAVY_CATAPHRACT with insufficient HORSES")
	assert_eq(str(res_no_horses.get("missing_resource", "")), "HORSES", "Missing resource identified as HORSES")
	assert_eq(manor.get_resource("WEAPONS"), snap_weapons, "Failed promotion leaves WEAPONS untouched")
	assert_eq(manor.get_resource("IRON"), snap_iron_cav, "Failed promotion leaves IRON untouched")
	assert_eq(manor.get_resource("HORSES"), 5, "Failed promotion leaves HORSES untouched")

	# Rejection 3: Insufficient WEAPONS (gear)
	manor.set_resource("WEAPONS", 3)
	var snap_wood_gear: int = manor.get_resource("WOOD")
	var res_no_gear: Dictionary = wg.promote_troops(manor, "SPEAR_SHIELD", 5)
	assert_false(_as_bool(res_no_gear.get("ok", true), true), "Reject promotion with insufficient WEAPONS")
	assert_eq(str(res_no_gear.get("missing_resource", "")), "WEAPONS", "Missing resource identified as WEAPONS")
	assert_eq(manor.get_resource("WOOD"), snap_wood_gear, "Failed promotion leaves WOOD untouched")
	assert_eq(wg.get_manor_total_promoted(manor.manor_id), 40, "Promoted total remains 40 after failures")

	# Rejection 4: Invalid inputs (null manor, unknown unit type, non-positive count)
	var res_null: Dictionary = wg.promote_troops(null, "SPEAR_SHIELD", 5)
	assert_false(_as_bool(res_null.get("ok", true), true), "Null manor rejected")
	var res_bad_ut: Dictionary = wg.promote_troops(manor, "DRAGON_RIDERS", 5)
	assert_false(_as_bool(res_bad_ut.get("ok", true), true), "Unknown unit_type rejected")
	assert_eq(str(res_bad_ut.get("error_code", "")), DtoSchemas.ERR_SCHEMA, "Unknown unit_type returns ERR_SCHEMA")
	var res_zero: Dictionary = wg.promote_troops(manor, "SPEAR_SHIELD", 0)
	assert_false(_as_bool(res_zero.get("ok", true), true), "Zero count rejected")


func test_node_mutations_canonical_round_trip_sha256_and_zero_floats() -> void:
	var wg: WorldGraph = WorldGraph.load_from_json_file("res://data/macro_map_3k.json")
	var manor: ManorState = _make_rich_manor("manor_rt", 50)
	var _promo: Dictionary = wg.promote_troops(manor, "LONGBOW", 15)

	assert_true(wg.set_node_owner("luoyang", "WEI", "p_cao"), "set_node_owner succeeds")
	assert_false(wg.set_node_owner("unknown_node", "WEI", "p_cao"), "set_node_owner rejects unknown node")
	assert_true(wg.set_node_tax_rate("luoyang", 9999), "set_node_tax_rate clamps and succeeds")
	assert_eq(_as_int(wg.get_node("luoyang").get("tax_rate_bp", 0), 0), 5000, "tax_rate_bp clamped at 5000")
	assert_eq(wg.adjust_node_security("luoyang", -500), 8500, "adjust_node_security reduces security")
	assert_eq(wg.damage_fortification("luoyang", 2500), 7500, "damage_fortification reduces HP")
	assert_eq(wg.repair_fortification("luoyang", 10000), 10000, "repair_fortification caps at max_fortification_hp")
	wg.update_node_prices("luoyang", 1250, 2400)

	var d1: Dictionary = wg.to_dict()
	assert_false(StateHasher.has_floats(d1), "WorldGraph.to_dict() must contain zero floats")
	assert_true(StateHasher.validate_deterministic_types(d1), "WorldGraph.to_dict() uses only deterministic types")

	var sha1: String = StateHasher.sha256_dict(d1)
	var wg2: WorldGraph = WorldGraph.from_dict(d1)
	var d2: Dictionary = wg2.to_dict()
	assert_false(StateHasher.has_floats(d2), "Restored WorldGraph.to_dict() must contain zero floats")
	var sha2: String = StateHasher.sha256_dict(d2)

	assert_eq(sha1, sha2, "WorldGraph to_dict/from_dict SHA-256 parity must be exact")
	assert_eq(str(wg2.get_node("luoyang").get("owner_faction_id", "")), "WEI", "Owner preserved across round-trip")
	assert_eq(_as_int(wg2.get_node("luoyang").get("grain_price_bp", 0), 0), 1250, "Grain price preserved")
	assert_eq(_as_int(wg2.get_manor_troop_composition("manor_rt").get("LONGBOW", 0), 0), 15, "Troop composition preserved")
