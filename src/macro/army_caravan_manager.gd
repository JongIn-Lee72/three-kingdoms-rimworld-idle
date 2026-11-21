class_name ArmyCaravanManager
extends RefCounted

const ENTITY_TYPES: Array[String] = ["ARMY", "CARAVAN", "RAID_PARTY", "COALITION_FORCE"]
const EVENT_ARMY_ARRIVED: String = "ARMY_ARRIVED"
const EVENT_EDGE_AMBUSHED: String = "EDGE_AMBUSHED"
const EVENT_SUPPLY_STARVATION: String = "SUPPLY_STARVATION"

var entities: Dictionary = {}
var _next_entity_seq: int = 1


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


func _init() -> void:
	entities.clear()
	_next_entity_seq = 1


func get_entity_ids() -> Array[String]:
	var ids: Array[String] = []
	for k: Variant in entities.keys():
		ids.append(str(k))
	ids.sort()
	return ids


func get_entity(entity_id: String) -> Dictionary:
	var v: Variant = entities.get(entity_id, {})
	if v is Dictionary:
		var d: Dictionary = v
		return d.duplicate(true)
	return {}


func has_entity(entity_id: String) -> bool:
	return entities.has(entity_id)


func remove_entity(entity_id: String) -> bool:
	return entities.erase(entity_id)


func spawn_entity(spec: Dictionary, world_graph: WorldGraph = null) -> Dictionary:
	var ut: String = str(spec.get("unit_type", "ARMY"))
	if not ENTITY_TYPES.has(ut):
		ut = "ARMY"

	var eid: String = str(spec.get("entity_id", ""))
	if eid.is_empty():
		var prefix: String = ut.to_lower()
		eid = "%s_%06d" % [prefix, _next_entity_seq]
		_next_entity_seq += 1

	var path_ids: Array[String] = []
	var raw_path: Variant = spec.get("path_edge_ids", [])
	if raw_path is Array:
		var p_arr: Array = raw_path
		for item: Variant in p_arr:
			var es: String = str(item)
			if not es.is_empty():
				path_ids.append(es)

	var arrived_flag: bool = _to_bool(spec.get("arrived", false), false)
	var cur_node: String = str(spec.get("current_node_id", spec.get("origin_node_id", "")))
	var cur_edge: String = str(spec.get("current_edge_id", ""))
	if cur_edge.is_empty() and not arrived_flag and not spec.has("current_edge_id") and not path_ids.is_empty():
		cur_edge = path_ids[0]
	var edge_progress: int = clampi(_to_int(spec.get("edge_progress_pm", 0), 0), 0, 1000)

	if world_graph != null and not cur_edge.is_empty() and not cur_node.is_empty():
		var next_n: String = world_graph.get_other_endpoint(cur_edge, cur_node)
		if next_n.is_empty():
			# If path starts from a different node or edge invalid, keep as provided
			pass

	var officers_clean: Array[Dictionary] = []
	var off_var: Variant = spec.get("officers", [])
	if off_var is Array:
		var off_arr: Array = off_var
		for o_item: Variant in off_arr:
			if o_item is Dictionary:
				var od: Dictionary = o_item
				officers_clean.append(od.duplicate(true))

	var cargo_clean: Dictionary = {}
	var cargo_var: Variant = spec.get("cargo", {})
	if cargo_var is Dictionary:
		var cd: Dictionary = cargo_var
		for ck: Variant in cd.keys():
			var amt: int = maxi(0, _to_int(cd[ck], 0))
			if amt > 0:
				cargo_clean[str(ck)] = amt

	var comp_clean: Dictionary = {}
	var comp_var: Variant = spec.get("troop_composition", {})
	if comp_var is Dictionary:
		var cpd: Dictionary = comp_var
		for tk: Variant in cpd.keys():
			var t_amt: int = maxi(0, _to_int(cpd[tk], 0))
			if t_amt > 0:
				comp_clean[str(tk)] = t_amt

	var doctrine_clean: Dictionary = ManorState.DEFAULT_DOCTRINE.duplicate(true)
	var doc_var: Variant = spec.get("standing_doctrine", {})
	if doc_var is Dictionary:
		var dd: Dictionary = doc_var
		for dk: Variant in dd.keys():
			doctrine_clean[str(dk)] = dd[dk]

	var rec: Dictionary = {
		"entity_id": eid,
		"owner_player_id": str(spec.get("owner_player_id", spec.get("player_id", ""))),
		"faction_id": str(spec.get("faction_id", "NEUTRAL")),
		"unit_type": ut,
		"current_node_id": cur_node,
		"current_edge_id": cur_edge,
		"edge_progress_pm": edge_progress,
		"path_edge_ids": path_ids,
		"path_index": maxi(0, _to_int(spec.get("path_index", 0), 0)),
		"troop_count": maxi(0, _to_int(spec.get("troop_count", 0), 0)),
		"troop_composition": comp_clean,
		"morale_bp": clampi(_to_int(spec.get("morale_bp", 8000), 8000), 0, 10000),
		"carried_grain": maxi(0, _to_int(spec.get("carried_grain", 0), 0)),
		"carried_coin": maxi(0, _to_int(spec.get("carried_coin", 0), 0)),
		"cargo": cargo_clean,
		"officers": officers_clean,
		"standing_doctrine": doctrine_clean,
		"target_manor_id": str(spec.get("target_manor_id", "")),
		"target_node_id": str(spec.get("target_node_id", "")),
		"source_manor_id": str(spec.get("source_manor_id", spec.get("manor_id", ""))),
		"arrived": _to_bool(spec.get("arrived", false), false),
		"status": str(spec.get("status", "MARCHING" if not cur_edge.is_empty() else "STATIONED"))
	}
	entities[eid] = rec
	return rec.duplicate(true)


func ingest_micro_events(event_bus: SimEventBus, world_graph: WorldGraph, tick_id: int) -> Array[Dictionary]:
	var spawned: Array[Dictionary] = []
	if event_bus == null:
		return spawned

	var batch: Array[Dictionary] = event_bus.drain_for_tick(tick_id)
	for ev: Dictionary in batch:
		var ev_type: String = str(ev.get("event", ""))
		if ev_type != SimEventBus.EVENT_MICRO_TO_MACRO_EXPEDITION_DISPATCHED:
			continue
		var payload_var: Variant = ev.get("payload", {})
		if not (payload_var is Dictionary):
			continue
		var payload: Dictionary = payload_var
		if not SimEventBus.validate_expedition_dispatched(payload):
			continue

		var path_ids: Array[String] = []
		var raw_p: Variant = payload.get("path_edge_ids", [])
		if raw_p is Array:
			var pa: Array = raw_p
			for item: Variant in pa:
				path_ids.append(str(item))

		var origin_node: String = str(payload.get("origin_node_id", ""))
		var first_edge: String = path_ids[0] if not path_ids.is_empty() else ""
		var troop_cnt: int = _to_int(payload.get("troop_count", 0), 0)
		var comp: Dictionary = {}
		var comp_var: Variant = payload.get("troop_composition", {})
		if comp_var is Dictionary:
			comp = comp_var
		if comp.is_empty() and world_graph != null:
			var m_id: String = str(payload.get("manor_id", ""))
			if not m_id.is_empty():
				comp = world_graph.get_manor_troop_composition(m_id)

		var spec: Dictionary = {
			"owner_player_id": str(payload.get("player_id", "")),
			"faction_id": str(payload.get("faction_id", "NEUTRAL")),
			"unit_type": str(payload.get("unit_type", "ARMY")),
			"current_node_id": origin_node,
			"current_edge_id": first_edge,
			"edge_progress_pm": 0,
			"path_edge_ids": path_ids,
			"path_index": 0,
			"troop_count": troop_cnt,
			"troop_composition": comp,
			"morale_bp": _to_int(payload.get("morale_bp", 8500), 8500),
			"carried_grain": _to_int(payload.get("carried_grain", 0), 0),
			"carried_coin": _to_int(payload.get("carried_coin", 0), 0),
			"cargo": payload.get("cargo", {}),
			"officers": payload.get("officers", []),
			"standing_doctrine": payload.get("standing_doctrine", {}),
			"target_manor_id": str(payload.get("target_manor_id", "")),
			"target_node_id": str(payload.get("target_node_id", "")),
			"source_manor_id": str(payload.get("manor_id", ""))
		}
		var created: Dictionary = spawn_entity(spec, world_graph)
		spawned.append(created)
	return spawned


func _compute_entity_speed_pm(ent: Dictionary, world_graph: WorldGraph, edge_dict: Dictionary) -> int:
	var travel_ticks: int = maxi(1, _to_int(edge_dict.get("travel_macro_ticks", 1), 1))
	@warning_ignore("integer_division")
	var base_step_pm: int = maxi(1, 1000 / travel_ticks)
	# Ensure exact ceiling if 1000 is not evenly divisible? Keep integer progress deterministic:
	# If travel_ticks == 3, 334 pm/tick reaches 1000 in 3 ticks; 1000 / 3 = 333 would take 4 ticks.
	if base_step_pm * travel_ticks < 1000:
		base_step_pm += 1

	var unit_speed_pm: int = 1000
	var comp_var: Variant = ent.get("troop_composition", {})
	if world_graph != null and comp_var is Dictionary:
		var comp: Dictionary = comp_var
		var total_comp: int = 0
		var weighted_speed: int = 0
		for ut_var: Variant in comp.keys():
			var ut_s: String = str(ut_var)
			var cnt: int = maxi(0, _to_int(comp[ut_var], 0))
			if cnt > 0:
				var uspec: Dictionary = world_graph.get_unit_spec(ut_s)
				var sp: int = _to_int(uspec.get("speed_pm", 1000), 1000)
				weighted_speed += sp * cnt
				total_comp += cnt
		if total_comp > 0:
			@warning_ignore("integer_division")
			unit_speed_pm = clampi(weighted_speed / total_comp, 500, 1500)

	@warning_ignore("integer_division")
	return maxi(50, (base_step_pm * unit_speed_pm) / 1000)


func _compute_grain_upkeep(ent: Dictionary, world_graph: WorldGraph, edge_dict: Dictionary) -> int:
	var troops: int = maxi(0, _to_int(ent.get("troop_count", 0), 0))
	if troops <= 0:
		return 0
	var base_upkeep: int = troops * 2
	var upkeep_pm: int = 100
	var comp_var: Variant = ent.get("troop_composition", {})
	if world_graph != null and comp_var is Dictionary:
		var comp: Dictionary = comp_var
		var total_c: int = 0
		var weighted_u: int = 0
		for ut_var: Variant in comp.keys():
			var cnt: int = maxi(0, _to_int(comp[ut_var], 0))
			if cnt > 0:
				var uspec: Dictionary = world_graph.get_unit_spec(str(ut_var))
				weighted_u += _to_int(uspec.get("grain_upkeep_pm", 100), 100) * cnt
				total_c += cnt
		if total_c > 0:
			@warning_ignore("integer_division")
			upkeep_pm = maxi(50, weighted_u / total_c)

	var drain_pm: int = _to_int(edge_dict.get("supply_drain_pm", 100), 100)
	var has_agrarian: bool = false
	var off_var: Variant = ent.get("officers", [])
	if off_var is Array:
		var off_arr: Array = off_var
		for o_item: Variant in off_arr:
			if o_item is Dictionary:
				var od: Dictionary = o_item
				var tr_var: Variant = od.get("traits", [])
				if tr_var is Array:
					var tr_arr: Array = tr_var
					for t: Variant in tr_arr:
						if str(t) == "T_AGRARIAN":
							has_agrarian = true
							break

	@warning_ignore("integer_division")
	var cost: int = (base_upkeep * upkeep_pm) / 100
	@warning_ignore("integer_division")
	cost = (cost * (1000 + drain_pm)) / 1000
	if has_agrarian:
		@warning_ignore("integer_division")
		cost = (cost * 850) / 1000
	return maxi(1, cost)


func _lead_officer_power(ent: Dictionary) -> Dictionary:
	var best_mar: int = 60
	var best_lea: int = 60
	var off_var: Variant = ent.get("officers", [])
	if off_var is Array:
		var off_arr: Array = off_var
		for o_item: Variant in off_arr:
			if o_item is Dictionary:
				var od: Dictionary = o_item
				var mar: int = _to_int(od.get("martial", od.get("MAR", 60)), 60)
				var lea: int = _to_int(od.get("leadership", od.get("LEA", 60)), 60)
				if mar > best_mar:
					best_mar = mar
				if lea > best_lea:
					best_lea = lea
	var comp_var: Variant = ent.get("troop_composition", {})
	var siege_bonus_bp: int = 1000
	if comp_var is Dictionary:
		var comp: Dictionary = comp_var
		if _to_int(comp.get("SIEGE_ENGINE", 0), 0) > 0:
			siege_bonus_bp = 1400
	return {
		"troop_count": maxi(1, _to_int(ent.get("troop_count", 1), 1)),
		"lead_martial": best_mar,
		"lead_leadership": best_lea,
		"siege_bonus_bp": siege_bonus_bp
	}


func step_macro_tick(
	world_graph: WorldGraph,
	clock: SimClock,
	world_seed: int,
	event_bus: SimEventBus
) -> Array[Dictionary]:
	var step_events: Array[Dictionary] = []
	if world_graph == null or clock == null:
		return step_events

	var tick_id: int = clock.current_tick_id
	var sorted_eids: Array[String] = get_entity_ids()

	for eid: String in sorted_eids:
		if not entities.has(eid):
			continue
		var ent: Dictionary = entities[eid]
		if _to_bool(ent.get("arrived", false), false):
			continue
		var cur_edge_id: String = str(ent.get("current_edge_id", ""))
		if cur_edge_id.is_empty() or not world_graph.has_edge(cur_edge_id):
			continue

		var edge_dict: Dictionary = world_graph.get_edge(cur_edge_id)
		var ent_hash: int = StateHasher.crc32_bytes(eid.to_utf8_buffer())

		# 1. Grain upkeep & starvation morale/attrition
		var upkeep: int = _compute_grain_upkeep(ent, world_graph, edge_dict)
		var cur_grain: int = maxi(0, _to_int(ent.get("carried_grain", 0), 0))
		if cur_grain >= upkeep:
			ent["carried_grain"] = cur_grain - upkeep
		else:
			ent["carried_grain"] = 0
			var cur_morale: int = _to_int(ent.get("morale_bp", 8000), 8000)
			ent["morale_bp"] = maxi(0, cur_morale - 1500)
			var cur_troops: int = _to_int(ent.get("troop_count", 0), 0)
			@warning_ignore("integer_division")
			var desert_loss: int = maxi(1, cur_troops / 20) if cur_troops > 0 else 0
			ent["troop_count"] = maxi(0, cur_troops - desert_loss)
			var starv_ev: Dictionary = {
				"type": EVENT_SUPPLY_STARVATION,
				"entity_id": eid,
				"tick_id": tick_id,
				"morale_bp": ent["morale_bp"],
				"troop_loss": desert_loss
			}
			step_events.append(starv_ev)
			if event_bus != null:
				var _s_seq: int = event_bus.emit(EVENT_SUPPLY_STARVATION, starv_ev, tick_id)

		# 2. Deterministic edge ambush check
		var ambush_bp: int = _to_int(edge_dict.get("ambush_risk_bp", 0), 0)
		if ambush_bp > 0 and _to_int(ent.get("troop_count", 0), 0) > 0:
			var roll_amb: int = DeterministicRNG.roll_bp(world_seed, tick_id, ent_hash, 4101)
			if roll_amb < ambush_bp:
				var troops_now: int = _to_int(ent.get("troop_count", 0), 0)
				@warning_ignore("integer_division")
				var amb_loss: int = maxi(1, troops_now / 25)
				ent["troop_count"] = maxi(0, troops_now - amb_loss)
				ent["morale_bp"] = maxi(0, _to_int(ent.get("morale_bp", 8000), 8000) - 400)
				var amb_ev: Dictionary = {
					"type": EVENT_EDGE_AMBUSHED,
					"entity_id": eid,
					"edge_id": cur_edge_id,
					"tick_id": tick_id,
					"troop_loss": amb_loss
				}
				step_events.append(amb_ev)
				if event_bus != null:
					var _a_seq: int = event_bus.emit(EVENT_EDGE_AMBUSHED, amb_ev, tick_id)

		# 3. Advance edge progress
		var speed_pm: int = _compute_entity_speed_pm(ent, world_graph, edge_dict)
		var new_progress: int = _to_int(ent.get("edge_progress_pm", 0), 0) + speed_pm

		if new_progress >= 1000:
			var cur_node: String = str(ent.get("current_node_id", ""))
			var dest_node: String = world_graph.get_other_endpoint(cur_edge_id, cur_node)
			if dest_node.is_empty():
				dest_node = str(edge_dict.get("to_node", ""))
			ent["current_node_id"] = dest_node

			var path_var: Variant = ent.get("path_edge_ids", [])
			var path_arr: Array[String] = []
			if path_var is Array:
				var raw_pa: Array = path_var
				for p_item: Variant in raw_pa:
					path_arr.append(str(p_item))

			var p_idx: int = _to_int(ent.get("path_index", 0), 0) + 1
			ent["path_index"] = p_idx
			if p_idx < path_arr.size():
				ent["current_edge_id"] = path_arr[p_idx]
				ent["edge_progress_pm"] = 0
			else:
				ent["current_edge_id"] = ""
				ent["edge_progress_pm"] = 1000
				ent["arrived"] = true
				ent["status"] = "ARRIVED"
				var arrival_evs: Array[Dictionary] = _emit_arrival_events(ent, dest_node, tick_id, event_bus)
				for aev: Dictionary in arrival_evs:
					step_events.append(aev)
		else:
			ent["edge_progress_pm"] = new_progress

	return step_events


func _emit_arrival_events(
	ent: Dictionary,
	dest_node_id: String,
	tick_id: int,
	event_bus: SimEventBus
) -> Array[Dictionary]:
	var emitted: Array[Dictionary] = []
	var eid: String = str(ent.get("entity_id", ""))
	var ut: String = str(ent.get("unit_type", "ARMY"))
	var target_manor: String = str(ent.get("target_manor_id", ""))

	if ut == "RAID_PARTY" or not target_manor.is_empty():
		var resolved_manor: String = target_manor if not target_manor.is_empty() else "manor_" + dest_node_id
		var raid_payload: Dictionary = {
			"tick_id": tick_id,
			"target_manor_id": resolved_manor,
			"host_node_id": dest_node_id,
			"attacker_entity_id": eid,
			"attacker_owner_id": str(ent.get("owner_player_id", "raider")),
			"attacker_power": _lead_officer_power(ent),
			"promote_to_lod0": true
		}
		emitted.append({
			"type": SimEventBus.EVENT_MACRO_TO_MICRO_RAID_INCOMING,
			"payload": raid_payload
		})
		if event_bus != null:
			var _r_seq: int = event_bus.emit(
				SimEventBus.EVENT_MACRO_TO_MICRO_RAID_INCOMING,
				raid_payload,
				tick_id
			)
	elif ut == "CARAVAN":
		var cargo_val: Variant = ent.get("cargo", {})
		var cargo_dup: Dictionary = {}
		if cargo_val is Dictionary:
			var cargo_d: Dictionary = cargo_val
			cargo_dup = cargo_d.duplicate(true)
		var caravan_payload: Dictionary = {
			"tick_id": tick_id,
			"entity_id": eid,
			"owner_player_id": str(ent.get("owner_player_id", "")),
			"node_id": dest_node_id,
			"carried_grain": _to_int(ent.get("carried_grain", 0), 0),
			"carried_coin": _to_int(ent.get("carried_coin", 0), 0),
			"cargo": cargo_dup
		}
		emitted.append({
			"type": SimEventBus.EVENT_CARAVAN_ARRIVED,
			"payload": caravan_payload
		})
		if event_bus != null:
			var _c_seq: int = event_bus.emit(SimEventBus.EVENT_CARAVAN_ARRIVED, caravan_payload, tick_id)
	else:
		var army_payload: Dictionary = {
			"tick_id": tick_id,
			"entity_id": eid,
			"owner_player_id": str(ent.get("owner_player_id", "")),
			"faction_id": str(ent.get("faction_id", "NEUTRAL")),
			"unit_type": ut,
			"node_id": dest_node_id,
			"troop_count": _to_int(ent.get("troop_count", 0), 0),
			"morale_bp": _to_int(ent.get("morale_bp", 8000), 8000)
		}
		emitted.append({
			"type": EVENT_ARMY_ARRIVED,
			"payload": army_payload
		})
		if event_bus != null:
			var _m_seq: int = event_bus.emit(EVENT_ARMY_ARRIVED, army_payload, tick_id)

	return emitted


func to_dict() -> Dictionary:
	var ents_arr: Array[Dictionary] = []
	for eid: String in get_entity_ids():
		ents_arr.append(get_entity(eid))
	return {
		"next_entity_seq": _next_entity_seq,
		"entities": ents_arr
	}


static func from_dict(data: Dictionary) -> ArmyCaravanManager:
	var mgr: ArmyCaravanManager = ArmyCaravanManager.new()
	mgr._next_entity_seq = maxi(1, _to_int(data.get("next_entity_seq", 1), 1))
	var ents_var: Variant = data.get("entities", [])
	if ents_var is Array:
		var ents_arr: Array = ents_var
		for item: Variant in ents_arr:
			if item is Dictionary:
				var ed: Dictionary = item
				var _s: Dictionary = mgr.spawn_entity(ed)
	elif ents_var is Dictionary:
		var ents_dict: Dictionary = ents_var
		for k: Variant in ents_dict.keys():
			var v: Variant = ents_dict[k]
			if v is Dictionary:
				var ed: Dictionary = v
				var _s: Dictionary = mgr.spawn_entity(ed)
	return mgr
