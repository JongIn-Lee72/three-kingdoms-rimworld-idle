class_name WorldGraph
extends RefCounted

const UNIT_TYPES: Array[String] = [
	"SPEAR_SHIELD",
	"LONGBOW",
	"REPEATING_CROSSBOW",
	"LIGHT_CAVALRY",
	"HEAVY_CATAPHRACT",
	"SIEGE_ENGINE"
]

const DEFAULT_UNIT_SPECS: Dictionary = {
	"SPEAR_SHIELD": {
		"unit_type_id": "SPEAR_SHIELD",
		"tier": 1,
		"promotion_requirements": {"iron": 100, "wood": 50},
		"atk_pm": 1000,
		"def_pm": 1300,
		"speed_pm": 900,
		"siege_pm": 800,
		"grain_upkeep_pm": 100
	},
	"LONGBOW": {
		"unit_type_id": "LONGBOW",
		"tier": 1,
		"promotion_requirements": {"iron": 120, "wood": 150},
		"atk_pm": 1300,
		"def_pm": 800,
		"speed_pm": 950,
		"siege_pm": 900,
		"grain_upkeep_pm": 110
	},
	"REPEATING_CROSSBOW": {
		"unit_type_id": "REPEATING_CROSSBOW",
		"tier": 2,
		"promotion_requirements": {"iron": 250, "wood": 200, "silk": 50},
		"atk_pm": 1500,
		"def_pm": 900,
		"speed_pm": 1000,
		"siege_pm": 1000,
		"grain_upkeep_pm": 130
	},
	"LIGHT_CAVALRY": {
		"unit_type_id": "LIGHT_CAVALRY",
		"tier": 1,
		"promotion_requirements": {"iron": 150, "horse": 100},
		"atk_pm": 1200,
		"def_pm": 950,
		"speed_pm": 1500,
		"siege_pm": 700,
		"grain_upkeep_pm": 150
	},
	"HEAVY_CATAPHRACT": {
		"unit_type_id": "HEAVY_CATAPHRACT",
		"tier": 2,
		"promotion_requirements": {"iron": 400, "horse": 200, "silk": 100},
		"atk_pm": 1800,
		"def_pm": 1700,
		"speed_pm": 1300,
		"siege_pm": 1200,
		"grain_upkeep_pm": 220
	},
	"SIEGE_ENGINE": {
		"unit_type_id": "SIEGE_ENGINE",
		"tier": 2,
		"promotion_requirements": {"iron": 500, "wood": 600, "stone": 400},
		"atk_pm": 800,
		"def_pm": 700,
		"speed_pm": 500,
		"siege_pm": 2500,
		"grain_upkeep_pm": 200
	}
}

var nodes: Dictionary = {}
var edges: Dictionary = {}
var unit_specs: Dictionary = {}
var manor_troop_compositions: Dictionary = {}


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


func _init(map_data: Dictionary = {}, load_default_if_empty: bool = true) -> void:
	_reset_default_unit_specs()
	if not map_data.is_empty():
		var _ok: bool = load_from_dict(map_data)
	elif load_default_if_empty:
		var _ok_def: bool = load_default_map()


func _reset_default_unit_specs() -> void:
	unit_specs.clear()
	for ut: String in UNIT_TYPES:
		var spec_var: Variant = DEFAULT_UNIT_SPECS.get(ut, {})
		if spec_var is Dictionary:
			var spec_d: Dictionary = spec_var
			unit_specs[ut] = spec_d.duplicate(true)


func load_default_map(path: String = "res://data/macro_map_3k.json") -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null:
		return false
	var norm: Variant = DtoSchemas.normalize_json_ints(parsed)
	if not (norm is Dictionary):
		return false
	var map_dict: Dictionary = norm
	return load_from_dict(map_dict)


static func load_from_json_file(path: String = "res://data/macro_map_3k.json") -> WorldGraph:
	var wg: WorldGraph = WorldGraph.new({}, false)
	var _ok: bool = wg.load_default_map(path)
	return wg


func load_from_dict(data: Dictionary) -> bool:
	nodes.clear()
	edges.clear()
	_reset_default_unit_specs()

	var nodes_var: Variant = data.get("nodes", [])
	if nodes_var is Array:
		var nodes_arr: Array = nodes_var
		for item: Variant in nodes_arr:
			if item is Dictionary:
				var nd: Dictionary = item
				_ingest_node_dict(nd)
	elif nodes_var is Dictionary:
		var nodes_dict: Dictionary = nodes_var
		for k: Variant in nodes_dict.keys():
			var item_v: Variant = nodes_dict[k]
			if item_v is Dictionary:
				var nd: Dictionary = item_v
				if not nd.has("node_id"):
					nd = nd.duplicate(true)
					nd["node_id"] = str(k)
				_ingest_node_dict(nd)

	var edges_var: Variant = data.get("edges", [])
	if edges_var is Array:
		var edges_arr: Array = edges_var
		for item: Variant in edges_arr:
			if item is Dictionary:
				var ed: Dictionary = item
				_ingest_edge_dict(ed)
	elif edges_var is Dictionary:
		var edges_dict: Dictionary = edges_var
		for k: Variant in edges_dict.keys():
			var item_v: Variant = edges_dict[k]
			if item_v is Dictionary:
				var ed: Dictionary = item_v
				if not ed.has("edge_id"):
					ed = ed.duplicate(true)
					ed["edge_id"] = str(k)
				_ingest_edge_dict(ed)

	var units_var: Variant = data.get("unit_types", [])
	if units_var is Array:
		var units_arr: Array = units_var
		for item: Variant in units_arr:
			if item is Dictionary:
				var ud: Dictionary = item
				_ingest_unit_spec(ud)
	elif units_var is Dictionary:
		var units_dict: Dictionary = units_var
		for k: Variant in units_dict.keys():
			var item_v: Variant = units_dict[k]
			if item_v is Dictionary:
				var ud: Dictionary = item_v
				if not ud.has("unit_type_id"):
					ud = ud.duplicate(true)
					ud["unit_type_id"] = str(k)
				_ingest_unit_spec(ud)

	manor_troop_compositions.clear()
	var comp_var: Variant = data.get("manor_troop_compositions", {})
	if comp_var is Dictionary:
		var comp_dict: Dictionary = comp_var
		for mid_v: Variant in comp_dict.keys():
			var mid: String = str(mid_v)
			var c_v: Variant = comp_dict[mid_v]
			if c_v is Dictionary:
				var cd: Dictionary = c_v
				var clean_comp: Dictionary = {}
				for ut: String in UNIT_TYPES:
					clean_comp[ut] = maxi(0, _to_int(cd.get(ut, 0), 0))
				manor_troop_compositions[mid] = clean_comp

	return not nodes.is_empty()


func _ingest_node_dict(nd: Dictionary) -> void:
	var nid: String = str(nd.get("node_id", ""))
	if nid.is_empty():
		return
	var max_hp: int = maxi(1, _to_int(nd.get("max_fortification_hp", nd.get("fortification_hp", 5000)), 5000))
	var cur_hp: int = clampi(_to_int(nd.get("fortification_hp", max_hp), max_hp), 0, max_hp)
	var grain_p: int = clampi(_to_int(nd.get("grain_price_bp", nd.get("base_grain_price_bp", 1000)), 1000), 100, 100000)
	var iron_p: int = clampi(_to_int(nd.get("iron_price_bp", nd.get("base_iron_price_bp", 2000)), 2000), 100, 100000)

	var reserves_clean: Dictionary = {}
	var res_var: Variant = nd.get("amm_reserves", {})
	if res_var is Dictionary:
		var rd: Dictionary = res_var
		for rk: Variant in rd.keys():
			reserves_clean[str(rk)] = maxi(0, _to_int(rd[rk], 0))

	nodes[nid] = {
		"node_id": nid,
		"name_ko": str(nd.get("name_ko", nid)),
		"province": str(nd.get("province", "")),
		"node_tier": str(nd.get("node_tier", "COUNTY")),
		"is_starter_county": _to_bool(nd.get("is_starter_county", false), false),
		"x": _to_int(nd.get("x", 0), 0),
		"y": _to_int(nd.get("y", 0), 0),
		"owner_faction_id": str(nd.get("owner_faction_id", "NEUTRAL")),
		"governor_player_id": str(nd.get("governor_player_id", "")),
		"fortification_hp": cur_hp,
		"max_fortification_hp": max_hp,
		"security_bp": clampi(_to_int(nd.get("security_bp", nd.get("public_order_bp", 7000)), 7000), 0, 10000),
		"bandit_pressure_bp": clampi(_to_int(nd.get("bandit_pressure_bp", 200), 200), 0, 10000),
		"tax_rate_bp": clampi(_to_int(nd.get("tax_rate_bp", 1000), 1000), 500, 5000),
		"treasury_grain": maxi(0, _to_int(nd.get("treasury_grain", 0), 0)),
		"treasury_coin": maxi(0, _to_int(nd.get("treasury_coin", 0), 0)),
		"grain_price_bp": grain_p,
		"iron_price_bp": iron_p,
		"base_grain_price_bp": clampi(_to_int(nd.get("base_grain_price_bp", grain_p), grain_p), 100, 100000),
		"base_iron_price_bp": clampi(_to_int(nd.get("base_iron_price_bp", iron_p), iron_p), 100, 100000),
		"amm_reserves": reserves_clean
	}


func _ingest_edge_dict(ed: Dictionary) -> void:
	var eid: String = str(ed.get("edge_id", ""))
	var from_n: String = str(ed.get("from_node", ed.get("from_node_id", "")))
	var to_n: String = str(ed.get("to_node", ed.get("to_node_id", "")))
	if eid.is_empty() or from_n.is_empty() or to_n.is_empty():
		return
	edges[eid] = {
		"edge_id": eid,
		"from_node": from_n,
		"to_node": to_n,
		"terrain_type": str(ed.get("terrain_type", "HIGHWAY")),
		"travel_macro_ticks": maxi(1, _to_int(ed.get("travel_macro_ticks", 1), 1)),
		"ambush_risk_bp": clampi(_to_int(ed.get("ambush_risk_bp", 100), 100), 0, 10000),
		"supply_drain_pm": maxi(0, _to_int(ed.get("supply_drain_pm", 100), 100))
	}


func _ingest_unit_spec(ud: Dictionary) -> void:
	var uid: String = str(ud.get("unit_type_id", ""))
	if uid.is_empty() or not UNIT_TYPES.has(uid):
		return
	var req_clean: Dictionary = {}
	var req_var: Variant = ud.get("promotion_requirements", {})
	if req_var is Dictionary:
		var rd: Dictionary = req_var
		for rk: Variant in rd.keys():
			req_clean[str(rk)] = maxi(0, _to_int(rd[rk], 0))
	unit_specs[uid] = {
		"unit_type_id": uid,
		"tier": clampi(_to_int(ud.get("tier", 1), 1), 1, 2),
		"promotion_requirements": req_clean,
		"atk_pm": maxi(100, _to_int(ud.get("atk_pm", 1000), 1000)),
		"def_pm": maxi(100, _to_int(ud.get("def_pm", 1000), 1000)),
		"speed_pm": maxi(100, _to_int(ud.get("speed_pm", 1000), 1000)),
		"siege_pm": maxi(100, _to_int(ud.get("siege_pm", 1000), 1000)),
		"grain_upkeep_pm": maxi(10, _to_int(ud.get("grain_upkeep_pm", 100), 100))
	}


const NODE_ID_ALIASES: Dictionary = {
	"ye": "ye_county",
	"jixian": "jicheng",
	"puyang": "chenliu"
}


static func map_known_node_alias(node_id: String) -> String:
	var clean: String = node_id.strip_edges()
	return str(NODE_ID_ALIASES.get(clean, clean))


static func resolve_node_alias(node_id: String, wg: WorldGraph = null) -> String:
	var clean: String = map_known_node_alias(node_id)
	if clean.is_empty():
		return "xuchang"
	if wg != null and wg.has_node(clean):
		return clean
	if wg != null and not wg.has_node(clean):
		return "xuchang" if wg.has_node("xuchang") else (wg.get_node_ids()[0] if not wg.get_node_ids().is_empty() else clean)
	return clean


func has_node(node_id: String) -> bool:
	return nodes.has(node_id)


func get_node(node_id: String) -> Dictionary:
	var v: Variant = nodes.get(node_id, {})
	if v is Dictionary:
		var d: Dictionary = v
		return d.duplicate(true)
	return {}


func get_node_ids() -> Array[String]:
	var ids: Array[String] = []
	for k: Variant in nodes.keys():
		ids.append(str(k))
	ids.sort()
	return ids


func has_edge(edge_id: String) -> bool:
	return edges.has(edge_id)


func get_edge(edge_id: String) -> Dictionary:
	var v: Variant = edges.get(edge_id, {})
	if v is Dictionary:
		var d: Dictionary = v
		return d.duplicate(true)
	return {}


func get_edge_ids() -> Array[String]:
	var ids: Array[String] = []
	for k: Variant in edges.keys():
		ids.append(str(k))
	ids.sort()
	return ids


func get_other_endpoint(edge_id: String, current_node_id: String) -> String:
	var v: Variant = edges.get(edge_id, null)
	if not (v is Dictionary):
		return ""
	var ed: Dictionary = v
	var f_node: String = str(ed.get("from_node", ""))
	var t_node: String = str(ed.get("to_node", ""))
	if f_node == current_node_id:
		return t_node
	if t_node == current_node_id:
		return f_node
	return ""


func get_adjacent_edges(node_id: String) -> Array[Dictionary]:
	var adj: Array[Dictionary] = []
	var eids: Array[String] = get_edge_ids()
	for eid: String in eids:
		var ed_var: Variant = edges[eid]
		if ed_var is Dictionary:
			var ed: Dictionary = ed_var
			if str(ed.get("from_node", "")) == node_id or str(ed.get("to_node", "")) == node_id:
				adj.append(ed.duplicate(true))
	return adj


func set_node_owner(node_id: String, faction_id: String, governor_player_id: String = "") -> bool:
	if not nodes.has(node_id):
		return false
	var nd: Dictionary = nodes[node_id]
	nd["owner_faction_id"] = faction_id
	nd["governor_player_id"] = governor_player_id
	return true


func set_node_tax_rate(node_id: String, tax_rate_bp: int) -> bool:
	if not nodes.has(node_id):
		return false
	var nd: Dictionary = nodes[node_id]
	nd["tax_rate_bp"] = clampi(tax_rate_bp, 500, 5000)
	return true


func adjust_node_security(node_id: String, delta_bp: int) -> int:
	if not nodes.has(node_id):
		return 0
	var nd: Dictionary = nodes[node_id]
	var cur: int = _to_int(nd.get("security_bp", 7000), 7000)
	var updated: int = clampi(cur + delta_bp, 0, 10000)
	nd["security_bp"] = updated
	return updated


func damage_fortification(node_id: String, damage: int) -> int:
	if not nodes.has(node_id) or damage < 0:
		return 0
	var nd: Dictionary = nodes[node_id]
	var cur: int = _to_int(nd.get("fortification_hp", 0), 0)
	var updated: int = maxi(0, cur - damage)
	nd["fortification_hp"] = updated
	return updated


func repair_fortification(node_id: String, amount: int) -> int:
	if not nodes.has(node_id) or amount < 0:
		return 0
	var nd: Dictionary = nodes[node_id]
	var cur: int = _to_int(nd.get("fortification_hp", 0), 0)
	var max_hp: int = maxi(1, _to_int(nd.get("max_fortification_hp", 5000), 5000))
	var updated: int = mini(max_hp, cur + amount)
	nd["fortification_hp"] = updated
	return updated


func update_node_prices(node_id: String, grain_price_bp: int, iron_price_bp: int) -> void:
	if not nodes.has(node_id):
		return
	var nd: Dictionary = nodes[node_id]
	nd["grain_price_bp"] = clampi(grain_price_bp, 100, 100000)
	nd["iron_price_bp"] = clampi(iron_price_bp, 100, 100000)


func find_path(from_node_id: String, to_node_id: String) -> Array[String]:
	var result: Array[String] = []
	if from_node_id.is_empty() or to_node_id.is_empty():
		return result
	if not nodes.has(from_node_id) or not nodes.has(to_node_id):
		return result
	if from_node_id == to_node_id:
		return result

	var sorted_eids: Array[String] = get_edge_ids()
	var dist: Dictionary = {}
	var hops: Dictionary = {}
	var path_edges: Dictionary = {}
	var visited: Dictionary = {}

	dist[from_node_id] = 0
	hops[from_node_id] = 0
	var empty_path: Array[String] = []
	path_edges[from_node_id] = empty_path

	while true:
		var best_node: String = ""
		var best_dist: int = 9223372036854775807
		var best_hops: int = 9223372036854775807
		var best_path: Array[String] = []

		var candidate_nodes: Array[String] = []
		for k: Variant in dist.keys():
			var nk: String = str(k)
			if not visited.has(nk):
				candidate_nodes.append(nk)
		candidate_nodes.sort()

		for nid: String in candidate_nodes:
			var d: int = _to_int(dist[nid], 9223372036854775807)
			var h: int = _to_int(hops[nid], 9223372036854775807)
			var p_var: Variant = path_edges[nid]
			var p_arr: Array[String] = []
			if p_var is Array:
				var raw_p: Array = p_var
				for pe: Variant in raw_p:
					p_arr.append(str(pe))
			if best_node.is_empty() or _is_better_state(d, h, p_arr, best_dist, best_hops, best_path):
				best_node = nid
				best_dist = d
				best_hops = h
				best_path = p_arr

		if best_node.is_empty():
			break
		if best_node == to_node_id:
			return best_path

		visited[best_node] = true

		# Relax outgoing and bidirectional edges in deterministic sorted order
		# Forward edges (from_node == best_node) are considered before reverse edges if same target
		for pass_rev: int in [0, 1]:
			for eid: String in sorted_eids:
				var ed_var: Variant = edges[eid]
				if not (ed_var is Dictionary):
					continue
				var ed: Dictionary = ed_var
				var fn: String = str(ed.get("from_node", ""))
				var tn: String = str(ed.get("to_node", ""))
				var neighbor: String = ""
				if pass_rev == 0 and fn == best_node:
					neighbor = tn
				elif pass_rev == 1 and tn == best_node:
					neighbor = fn
				if neighbor.is_empty() or visited.has(neighbor) or not nodes.has(neighbor):
					continue

				var weight: int = maxi(1, _to_int(ed.get("travel_macro_ticks", 1), 1))
				var cand_dist: int = best_dist + weight
				var cand_hops: int = best_hops + 1
				var cand_path: Array[String] = best_path.duplicate()
				cand_path.append(eid)

				if not dist.has(neighbor):
					dist[neighbor] = cand_dist
					hops[neighbor] = cand_hops
					path_edges[neighbor] = cand_path
				else:
					var cur_d: int = _to_int(dist[neighbor], 9223372036854775807)
					var cur_h: int = _to_int(hops[neighbor], 9223372036854775807)
					var cur_p: Array[String] = []
					var cur_pv: Variant = path_edges[neighbor]
					if cur_pv is Array:
						var raw_cp: Array = cur_pv
						for ce: Variant in raw_cp:
							cur_p.append(str(ce))
					if _is_better_state(cand_dist, cand_hops, cand_path, cur_d, cur_h, cur_p):
						dist[neighbor] = cand_dist
						hops[neighbor] = cand_hops
						path_edges[neighbor] = cand_path

	return result


static func _is_better_state(
	d1: int, h1: int, p1: Array[String],
	d2: int, h2: int, p2: Array[String]
) -> bool:
	if d1 != d2:
		return d1 < d2
	if h1 != h2:
		return h1 < h2
	var n: int = mini(p1.size(), p2.size())
	for i: int in range(n):
		if p1[i] != p2[i]:
			return p1[i] < p2[i]
	return p1.size() < p2.size()


func get_unit_spec(unit_type: String) -> Dictionary:
	var v: Variant = unit_specs.get(unit_type, {})
	if v is Dictionary:
		var d: Dictionary = v
		return d.duplicate(true)
	return {}


func get_manor_troop_composition(manor_id: String) -> Dictionary:
	var out: Dictionary = {}
	var v: Variant = manor_troop_compositions.get(manor_id, {})
	var src: Dictionary = v if v is Dictionary else {}
	for ut: String in UNIT_TYPES:
		out[ut] = maxi(0, _to_int(src.get(ut, 0), 0))
	return out


func get_manor_total_promoted(manor_id: String) -> int:
	var comp: Dictionary = get_manor_troop_composition(manor_id)
	var total: int = 0
	for ut: String in UNIT_TYPES:
		total += _to_int(comp.get(ut, 0), 0)
	return total


func compute_promotion_costs(unit_type: String, count: int) -> Dictionary:
	if not UNIT_TYPES.has(unit_type) or count <= 0:
		return {}
	var spec: Dictionary = get_unit_spec(unit_type)
	var req_var: Variant = spec.get("promotion_requirements", {})
	var req: Dictionary = req_var if req_var is Dictionary else {}

	var costs: Dictionary = {
		"GRAIN": count,
		"WEAPONS": count
	}

	@warning_ignore("integer_division")
	var iron_need: int = (_to_int(req.get("iron", 0), 0) * count + 99) / 100
	if iron_need > 0:
		costs["IRON"] = iron_need

	@warning_ignore("integer_division")
	var wood_need: int = (_to_int(req.get("wood", 0), 0) * count + 99) / 100
	if wood_need > 0:
		costs["WOOD"] = wood_need

	@warning_ignore("integer_division")
	var horse_need: int = (_to_int(req.get("horse", 0), 0) * count + 99) / 100
	if unit_type == "LIGHT_CAVALRY" or unit_type == "HEAVY_CATAPHRACT":
		horse_need = maxi(count, horse_need)
	if horse_need > 0:
		costs["HORSES"] = horse_need

	@warning_ignore("integer_division")
	var coin_from_silk: int = (_to_int(req.get("silk", 0), 0) * count + 99) / 100
	@warning_ignore("integer_division")
	var coin_from_stone: int = (_to_int(req.get("stone", 0), 0) * count + 99) / 100
	var coin_need: int = coin_from_silk + coin_from_stone
	if coin_need > 0:
		costs["COIN"] = coin_need

	return costs


func promote_troops(manor: ManorState, unit_type: String, count: int) -> Dictionary:
	if manor == null:
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Null manor"}
	if not UNIT_TYPES.has(unit_type):
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Unknown unit_type: " + unit_type}
	if count <= 0:
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Count must be > 0"}

	var already_promoted: int = get_manor_total_promoted(manor.manor_id)
	if already_promoted + count > manor.household_troops:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE,
			"reason": "Not enough unpromoted household_troops",
			"available_troops": maxi(0, manor.household_troops - already_promoted),
			"requested": count
		}

	var costs: Dictionary = compute_promotion_costs(unit_type, count)
	for rk_var: Variant in costs.keys():
		var rk: String = str(rk_var)
		var req_amt: int = _to_int(costs[rk_var], 0)
		if manor.get_resource(rk) < req_amt:
			return {
				"ok": false,
				"error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE,
				"reason": "Insufficient resource: " + rk,
				"missing_resource": rk,
				"required": costs
			}

	for rk_var: Variant in costs.keys():
		var rk: String = str(rk_var)
		var req_amt: int = _to_int(costs[rk_var], 0)
		if req_amt > 0:
			var _spent: bool = manor.try_spend_resource(rk, req_amt)

	var comp: Dictionary = get_manor_troop_composition(manor.manor_id)
	comp[unit_type] = _to_int(comp.get(unit_type, 0), 0) + count
	manor_troop_compositions[manor.manor_id] = comp

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"manor_id": manor.manor_id,
		"unit_type": unit_type,
		"count": count,
		"costs": costs,
		"composition": comp.duplicate(true)
	}


func to_dict() -> Dictionary:
	var nodes_arr: Array[Dictionary] = []
	for nid: String in get_node_ids():
		nodes_arr.append(get_node(nid))

	var edges_arr: Array[Dictionary] = []
	for eid: String in get_edge_ids():
		edges_arr.append(get_edge(eid))

	var units_arr: Array[Dictionary] = []
	for ut: String in UNIT_TYPES:
		units_arr.append(get_unit_spec(ut))

	var comp_copy: Dictionary = {}
	var mids: Array[String] = []
	for k: Variant in manor_troop_compositions.keys():
		mids.append(str(k))
	mids.sort()
	for mid: String in mids:
		comp_copy[mid] = get_manor_troop_composition(mid)

	return {
		"nodes": nodes_arr,
		"edges": edges_arr,
		"unit_types": units_arr,
		"manor_troop_compositions": comp_copy
	}


static func from_dict(data: Dictionary) -> WorldGraph:
	return WorldGraph.new(data, false)
