class_name SocialBanquetService
extends RefCounted

const RELATION_TAGS: Array[String] = [
	"SWORN_SIBLING",
	"SPOUSE",
	"MENTOR",
	"BENEFACTOR",
	"NEMESIS"
]

const SWORN_SIBLING_MIN_AFFINITY: int = 75
const SWORN_SIBLING_JOINT_BONUS_PM: int = 150

var affinity_graph: Dictionary = {}
var relation_tags: Dictionary = {}
var banquet_history: Array[Dictionary] = []


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


static func _edge_key(from_id: String, to_id: String) -> String:
	return from_id + "->" + to_id


static func _extract_string_array(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		var arr: Array = raw
		for item: Variant in arr:
			var s: String = str(item)
			if not s.is_empty() and not out.has(s):
				out.append(s)
	return out


func _init() -> void:
	affinity_graph.clear()
	relation_tags.clear()
	banquet_history.clear()


func get_affinity(from_id: String, to_id: String) -> int:
	return clampi(_to_int(affinity_graph.get(_edge_key(from_id, to_id), 0), 0), -100, 100)


func set_affinity(from_id: String, to_id: String, value: int) -> int:
	if from_id.is_empty() or to_id.is_empty() or from_id == to_id:
		return 0
	var clamped: int = clampi(value, -100, 100)
	affinity_graph[_edge_key(from_id, to_id)] = clamped
	return clamped


func adjust_affinity(from_id: String, to_id: String, delta: int) -> int:
	if from_id.is_empty() or to_id.is_empty() or from_id == to_id:
		return 0
	var updated: int = clampi(get_affinity(from_id, to_id) + delta, -100, 100)
	affinity_graph[_edge_key(from_id, to_id)] = updated
	return updated


func get_relations(from_id: String, to_id: String) -> Array[String]:
	var key: String = _edge_key(from_id, to_id)
	return _extract_string_array(relation_tags.get(key, []))


func add_relation_tag(from_id: String, to_id: String, tag: String) -> bool:
	if from_id.is_empty() or to_id.is_empty() or from_id == to_id:
		return false
	if not RELATION_TAGS.has(tag):
		return false
	var key: String = _edge_key(from_id, to_id)
	var list: Array[String] = get_relations(from_id, to_id)
	if not list.has(tag):
		list.append(tag)
		relation_tags[key] = list
	return true


func are_sworn_siblings(id_a: String, id_b: String) -> bool:
	if id_a.is_empty() or id_b.is_empty() or id_a == id_b:
		return false
	return get_relations(id_a, id_b).has("SWORN_SIBLING") and get_relations(id_b, id_a).has("SWORN_SIBLING")


func form_sworn_siblings(id_a: String, id_b: String) -> Dictionary:
	if id_a.is_empty() or id_b.is_empty() or id_a == id_b:
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Invalid officer IDs"}

	var aff_ab: int = get_affinity(id_a, id_b)
	var aff_ba: int = get_affinity(id_b, id_a)
	if aff_ab < SWORN_SIBLING_MIN_AFFINITY or aff_ba < SWORN_SIBLING_MIN_AFFINITY:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "Mutual affinity must be >= 75 to form SWORN_SIBLING",
			"affinity_ab": aff_ab,
			"affinity_ba": aff_ba
		}

	var _t1: bool = add_relation_tag(id_a, id_b, "SWORN_SIBLING")
	var _t2: bool = add_relation_tag(id_b, id_a, "SWORN_SIBLING")
	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"id_a": id_a,
		"id_b": id_b,
		"affinity_ab": aff_ab,
		"affinity_ba": aff_ba,
		"joint_combat_bonus_pm": SWORN_SIBLING_JOINT_BONUS_PM
	}


func get_joint_combat_bonus_pm(officer_ids: Array) -> int:
	var clean_ids: Array[String] = []
	for item: Variant in officer_ids:
		var oid: String = str(item)
		if not oid.is_empty() and not clean_ids.has(oid):
			clean_ids.append(oid)
	if clean_ids.size() < 2:
		return 0

	for i: int in range(clean_ids.size()):
		for j: int in range(i + 1, clean_ids.size()):
			if are_sworn_siblings(clean_ids[i], clean_ids[j]):
				return SWORN_SIBLING_JOINT_BONUS_PM
	return 0


func host_banquet(
	manor: ManorState,
	host_pawn: PawnEntity,
	guest_pawns: Array,
	wine_cost: int,
	grain_cost: int,
	clock: SimClock,
	world_seed: int
) -> Dictionary:
	if manor == null or host_pawn == null or clock == null:
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Null manor/host_pawn/clock"}
	if wine_cost < 0 or grain_cost < 0:
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Costs must be >= 0"}
	if manor.get_resource("HERBS_WINE") < wine_cost:
		return {"ok": false, "error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE, "reason": "Insufficient HERBS_WINE"}
	if manor.get_resource("GRAIN") < grain_cost:
		return {"ok": false, "error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE, "reason": "Insufficient GRAIN"}

	var _sw: bool = manor.try_spend_resource("HERBS_WINE", wine_cost)
	var _sg: bool = manor.try_spend_resource("GRAIN", grain_cost)

	var tick_id: int = clock.current_tick_id
	var hall_lvl: int = manor.get_building_level("BANQUET_HALL")
	var host_cha: int = host_pawn.get_effective_stat("CHA")
	@warning_ignore("integer_division")
	var morale_gain: int = 1200 + host_cha * 12 + (hall_lvl - 1) * 200
	var mood_bonus: int = 15 + (hall_lvl - 1) * 2

	var participants: Array[PawnEntity] = [host_pawn]
	for g_item: Variant in guest_pawns:
		if g_item is PawnEntity:
			var gp: PawnEntity = g_item
			if gp.pawn_id != host_pawn.pawn_id:
				participants.append(gp)

	var guest_ids: Array[String] = []
	var aff_gain_base: int = 10 + mini(15, wine_cost / 5)

	for p: PawnEntity in participants:
		p.add_need("MORALE", morale_gain)
		p.add_need("FOOD", 1500)
		p.add_thought("GRAND_BANQUET", mood_bonus, 24)
		if p.has_trait("T_DRINKER") and wine_cost > 0:
			p.ticks_since_wine = 0
			p.add_thought("DRINKER_HIGH_SPIRITS", 20, 24)
		var _m: int = p.step_mood(0, 1)

		if p.pawn_id != host_pawn.pawn_id:
			guest_ids.append(p.pawn_id)
			var _a1: int = adjust_affinity(host_pawn.pawn_id, p.pawn_id, aff_gain_base)
			var _a2: int = adjust_affinity(p.pawn_id, host_pawn.pawn_id, aff_gain_base)

	var recruit_bp: int = 2000 + (hall_lvl - 1) * 500 + host_cha * 15
	if host_pawn.has_trait("T_SCHOLAR"):
		@warning_ignore("integer_division")
		recruit_bp = (recruit_bp * 1400) / 1000
	if host_pawn.origin_archetype == "ORIGIN_CHIVALROUS_HERO":
		@warning_ignore("integer_division")
		recruit_bp = (recruit_bp * 1250) / 1000
	recruit_bp = clampi(recruit_bp, 500, 9000)

	var roll_rec: int = DeterministicRNG.roll_bp(world_seed, tick_id, host_pawn.get_entity_hash_id(), 8101)
	var talent_attracted: bool = roll_rec < recruit_bp
	var wandering_talent: Dictionary = {}
	if talent_attracted:
		var t_idx: int = DeterministicRNG.roll_range(world_seed, tick_id, host_pawn.get_entity_hash_id(), 8102, 1, 9999)
		wandering_talent = {
			"pawn_id": "wanderer_%04d_%04d" % [tick_id, t_idx],
			"initial_affinity": 40
		}

	var rec: Dictionary = {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"tick_id": tick_id,
		"manor_id": manor.manor_id,
		"host_pawn_id": host_pawn.pawn_id,
		"guest_ids": guest_ids,
		"wine_spent": wine_cost,
		"grain_spent": grain_cost,
		"morale_gain_bp": morale_gain,
		"mood_bonus": mood_bonus,
		"recruit_chance_bp": recruit_bp,
		"recruit_roll_bp": roll_rec,
		"talent_attracted": talent_attracted,
		"wandering_talent": wandering_talent
	}
	banquet_history.append(rec.duplicate(true))
	return rec


func to_dict() -> Dictionary:
	var aff_copy: Dictionary = {}
	var akeys: Array[String] = []
	for k: Variant in affinity_graph.keys():
		akeys.append(str(k))
	akeys.sort()
	for ak: String in akeys:
		aff_copy[ak] = clampi(_to_int(affinity_graph[ak], 0), -100, 100)

	var rel_copy: Dictionary = {}
	var rkeys: Array[String] = []
	for k: Variant in relation_tags.keys():
		rkeys.append(str(k))
	rkeys.sort()
	for rk: String in rkeys:
		rel_copy[rk] = _extract_string_array(relation_tags[rk])

	var hist_copy: Array[Dictionary] = []
	for bh: Dictionary in banquet_history:
		hist_copy.append(bh.duplicate(true))

	return {
		"affinity_graph": aff_copy,
		"relation_tags": rel_copy,
		"banquet_history": hist_copy
	}


static func from_dict(data: Dictionary) -> SocialBanquetService:
	var svc: SocialBanquetService = SocialBanquetService.new()

	var aff_var: Variant = data.get("affinity_graph", {})
	if aff_var is Dictionary:
		var ad: Dictionary = aff_var
		for k: Variant in ad.keys():
			svc.affinity_graph[str(k)] = clampi(_to_int(ad[k], 0), -100, 100)

	var rel_var: Variant = data.get("relation_tags", {})
	if rel_var is Dictionary:
		var rd: Dictionary = rel_var
		for k: Variant in rd.keys():
			var clean: Array[String] = []
			for tag: String in _extract_string_array(rd[k]):
				if RELATION_TAGS.has(tag):
					clean.append(tag)
			if not clean.is_empty():
				svc.relation_tags[str(k)] = clean

	var hist_var: Variant = data.get("banquet_history", [])
	if hist_var is Array:
		var ha: Array = hist_var
		for item: Variant in ha:
			if item is Dictionary:
				var hd: Dictionary = item
				svc.banquet_history.append(hd.duplicate(true))

	return svc
