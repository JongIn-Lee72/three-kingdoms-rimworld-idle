class_name ManorState
extends RefCounted

const ZONE_TYPES: Array[String] = [
	"ZONE_FARMLAND",
	"ZONE_STOCKPILE",
	"ZONE_HIDDEN_VAULT",
	"ZONE_BARRACKS",
	"ZONE_WORKSHOP",
	"ZONE_RESIDENCE",
	"ZONE_INFIRMARY",
	"ZONE_DEFENSE_LINE"
]

const BUILDING_IDS: Array[String] = [
	"MAIN_HALL",
	"QUARTERS",
	"MILITARY_FARM",
	"GRANARY_VAULT",
	"HORSE_PASTURE",
	"SMITHY_ARMORY",
	"BARRACKS_DRILL",
	"STUDY_PAVILION",
	"BANQUET_HALL",
	"WATCHTOWER_WALL"
]

const RATION_POLICIES: Array[String] = ["COARSE", "STANDARD", "FEAST"]
const GEAR_TIERS: Array[String] = [
	"POOR",
	"NORMAL",
	"GOOD",
	"EXCELLENT",
	"MASTERWORK",
	"LEGENDARY"
]
const GEAR_TIER_MULT_PM: Dictionary = {
	"POOR": 800,
	"NORMAL": 1000,
	"GOOD": 1150,
	"EXCELLENT": 1300,
	"MASTERWORK": 1500,
	"LEGENDARY": 1800
}

const TECH_BRANCHES: Dictionary = {
	"DOMESTIC": ["DOUBLE_CROPPING", "WATER_WHEEL", "DEEP_VAULT"],
	"MILITARY": ["FORMATIONS_CORE", "REPEATING_CROSSBOW", "HEAVY_CATAPHRACT"],
	"STRATAGEM": ["FIRE_ATTACK", "FLOOD_TACTICS", "TREBUCHET_NET"]
}

const WALK_EFFICIENCY_PM: Dictionary = {
	"LOGISTICS": 880,
	"PATROL": 900,
	"AGRICULTURE": 850,
	"TRAINING": 900,
	"CRAFTING": 870,
	"RESEARCH": 920,
	"DIPLOMACY": 900,
	"IDLE_STUDY_OR_GUARD": 920
}

const DEFAULT_DOCTRINE: Dictionary = {
	"engagement_stance": "DEFENSIVE_HOLD",
	"formation": "SQUARE_SHIELD",
	"supply_threshold_days": 10,
	"retreat_troop_bp": 3000,
	"retreat_morale_bp": 2500,
	"duel_policy": "ACCEPT_IF_ADVANTAGE",
	"stratagem_policy": "FIRE_OR_FLOOD",
	"prisoner_policy": "RECRUIT_PERSUADE",
	"evacuate_on_overwhelm": true,
	"auto_market_replenish": true,
	"auto_medical_triage": true
}

var manor_id: String = ""
var player_id: String = ""
var host_node_id: String = "xuchang"
var starting_province: String = "YU_ZHOU"
var current_lod: int = 1

# 8-Resource Economy Ledger (all >= 0 int64)
var resources: Dictionary = {
	"GRAIN": 1500,
	"COIN": 1000,
	"WOOD": 400,
	"IRON": 250,
	"HORSES": 20,
	"HERBS_WINE": 150,
	"WEAPONS": 50,
	"MERIT_PRESTIGE": 0
}

var ration_quality: String = "STANDARD"
var wine_policy_enabled: bool = true

var buildings: Dictionary = {
	"MAIN_HALL": 1,
	"QUARTERS": 1,
	"MILITARY_FARM": 1,
	"GRANARY_VAULT": 1,
	"HORSE_PASTURE": 1,
	"SMITHY_ARMORY": 1,
	"BARRACKS_DRILL": 1,
	"STUDY_PAVILION": 1,
	"BANQUET_HALL": 1,
	"WATCHTOWER_WALL": 1
}

# 8 logical zone footprints on the 32x32 grid
var zones: Array[Dictionary] = []
# Compact deterministic 32x32 zone index map (1024 entries: 0..7)
var tile_zone_map: PackedInt32Array = PackedInt32Array()

var pawns: Array[PawnEntity] = []
var household_troops: int = 300
var troop_training_pm: int = 500
var max_troops: int = 1000

var wall_hp: int = 2000
var max_wall_hp: int = 2000
var trap_power: int = 120
var vault_protected_bp: int = 4000
var truce_shield_until_tick: int = 0
var standing_doctrine: Dictionary = DEFAULT_DOCTRINE.duplicate(true)

var crafting_queue: Array[Dictionary] = []
var crafted_gear_counts: Dictionary = {
	"POOR": 0,
	"NORMAL": 0,
	"GOOD": 0,
	"EXCELLENT": 0,
	"MASTERWORK": 0,
	"LEGENDARY": 0
}

var active_research_id: String = "DOUBLE_CROPPING"
var research_progress_pm: Dictionary = {}
var unlocked_techs: Array[String] = []

# Exact permille remainder carries for LOD 0 / LOD 1 parity & fractional rate integration
var lod_remainder_carry: Dictionary = {}
var jobs_completed: int = 0
var raid_defense_active: bool = false
var raid_history: Array[Dictionary] = []


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


func _init(p_manor_id: String = "manor_01", p_player_id: String = "player_01") -> void:
	manor_id = p_manor_id
	player_id = p_player_id
	_init_default_grid_and_zones()
	recompute_building_derived_caps()


func _init_default_grid_and_zones() -> void:
	zones = [
		{"id": "ZONE_DEFENSE_LINE", "x": 0, "y": 0, "w": 32, "h": 4},
		{"id": "ZONE_FARMLAND", "x": 0, "y": 4, "w": 16, "h": 12},
		{"id": "ZONE_STOCKPILE", "x": 16, "y": 4, "w": 10, "h": 8},
		{"id": "ZONE_HIDDEN_VAULT", "x": 26, "y": 4, "w": 6, "h": 8},
		{"id": "ZONE_BARRACKS", "x": 0, "y": 16, "w": 16, "h": 8},
		{"id": "ZONE_WORKSHOP", "x": 16, "y": 12, "w": 16, "h": 8},
		{"id": "ZONE_RESIDENCE", "x": 0, "y": 24, "w": 20, "h": 8},
		{"id": "ZONE_INFIRMARY", "x": 20, "y": 20, "w": 12, "h": 12}
	]
	var map: PackedInt32Array = PackedInt32Array()
	var _err: int = map.resize(DtoSchemas.MANOR_GRID_SIZE * DtoSchemas.MANOR_GRID_SIZE)
	for y: int in range(DtoSchemas.MANOR_GRID_SIZE):
		for x: int in range(DtoSchemas.MANOR_GRID_SIZE):
			var z_idx: int = 1  # ZONE_STOCKPILE default
			for zi: int in range(zones.size()):
				var z: Dictionary = zones[zi]
				var zx: int = _to_int(z.get("x", 0), 0)
				var zy: int = _to_int(z.get("y", 0), 0)
				var zw: int = _to_int(z.get("w", 0), 0)
				var zh: int = _to_int(z.get("h", 0), 0)
				if x >= zx and x < zx + zw and y >= zy and y < zy + zh:
					z_idx = ZONE_TYPES.find(str(z.get("id", "ZONE_STOCKPILE")))
					if z_idx < 0:
						z_idx = 1
					break
			map[y * DtoSchemas.MANOR_GRID_SIZE + x] = z_idx
	tile_zone_map = map


func get_tile_zone(x: int, y: int) -> String:
	if x < 0 or x >= DtoSchemas.MANOR_GRID_SIZE or y < 0 or y >= DtoSchemas.MANOR_GRID_SIZE:
		return "ZONE_STOCKPILE"
	var idx: int = y * DtoSchemas.MANOR_GRID_SIZE + x
	if idx < 0 or idx >= tile_zone_map.size():
		return "ZONE_STOCKPILE"
	var z_idx: int = tile_zone_map[idx]
	if z_idx < 0 or z_idx >= ZONE_TYPES.size():
		return "ZONE_STOCKPILE"
	return ZONE_TYPES[z_idx]


func get_zone_center(zone_id: String) -> Vector2i:
	for z: Dictionary in zones:
		if str(z.get("id", "")) == zone_id:
			var zx: int = _to_int(z.get("x", 0), 0)
			var zy: int = _to_int(z.get("y", 0), 0)
			@warning_ignore("integer_division")
			var cx: int = zx + _to_int(z.get("w", 2), 2) / 2
			@warning_ignore("integer_division")
			var cy: int = zy + _to_int(z.get("h", 2), 2) / 2
			return Vector2i(
				clampi(cx, 0, DtoSchemas.MANOR_GRID_SIZE - 1),
				clampi(cy, 0, DtoSchemas.MANOR_GRID_SIZE - 1)
			)
	return Vector2i(16, 16)


func get_resource(res_key: String) -> int:
	return maxi(0, _to_int(resources.get(res_key, 0), 0))


func set_resource(res_key: String, amount: int) -> void:
	if not DtoSchemas.RESOURCE_KEYS.has(res_key):
		return
	resources[res_key] = maxi(0, amount)


func add_resource(res_key: String, delta: int) -> int:
	if not DtoSchemas.RESOURCE_KEYS.has(res_key):
		return 0
	var cur: int = get_resource(res_key)
	var updated: int = maxi(0, cur + delta)
	resources[res_key] = updated
	return updated


func try_spend_resource(res_key: String, amount: int) -> bool:
	if amount < 0 or not DtoSchemas.RESOURCE_KEYS.has(res_key):
		return false
	var cur: int = get_resource(res_key)
	if cur < amount:
		return false
	resources[res_key] = cur - amount
	return true


func get_building_level(building_id: String) -> int:
	return clampi(_to_int(buildings.get(building_id, 1), 1), 1, 5)


func set_building_level(building_id: String, level: int) -> void:
	if not BUILDING_IDS.has(building_id):
		return
	buildings[building_id] = clampi(level, 1, 5)
	recompute_building_derived_caps()


func upgrade_building(building_id: String) -> bool:
	if not BUILDING_IDS.has(building_id):
		return false
	var cur_lvl: int = get_building_level(building_id)
	if cur_lvl >= 5:
		return false
	var wood_cost: int = 120 * cur_lvl
	var coin_cost: int = 180 * cur_lvl
	if get_resource("WOOD") < wood_cost or get_resource("COIN") < coin_cost:
		return false
	var _w: bool = try_spend_resource("WOOD", wood_cost)
	var _c: bool = try_spend_resource("COIN", coin_cost)
	buildings[building_id] = cur_lvl + 1
	recompute_building_derived_caps()
	return true


func recompute_building_derived_caps() -> void:
	var gv_lvl: int = get_building_level("GRANARY_VAULT")
	var base_vault: int = 4000 + (gv_lvl - 1) * 500
	if unlocked_techs.has("DEEP_VAULT"):
		base_vault += 500
	vault_protected_bp = clampi(base_vault, 4000, 6500)

	var wt_lvl: int = get_building_level("WATCHTOWER_WALL")
	var new_max_wall: int = 2000 + (wt_lvl - 1) * 1000
	max_wall_hp = new_max_wall
	wall_hp = clampi(wall_hp, 0, max_wall_hp)
	trap_power = 120 + (wt_lvl - 1) * 80

	var br_lvl: int = get_building_level("BARRACKS_DRILL")
	max_troops = clampi(1000 + (br_lvl - 1) * 500, 1000, 3000)
	household_troops = clampi(household_troops, 0, max_troops)


func get_max_retainers() -> int:
	var mh_lvl: int = get_building_level("MAIN_HALL")
	return clampi(4 + (mh_lvl - 1) * 2, 4, DtoSchemas.MAX_RETAINERS)


func get_quarters_rest_mult_pm() -> int:
	var q_lvl: int = get_building_level("QUARTERS")
	return 1000 + (q_lvl - 1) * 150


func get_facility_mult_pm(domain: String) -> int:
	var lvl: int = 1
	match domain:
		"AGRICULTURE":
			lvl = get_building_level("MILITARY_FARM")
		"CRAFTING":
			lvl = get_building_level("SMITHY_ARMORY")
		"TRAINING":
			lvl = get_building_level("BARRACKS_DRILL")
		"RESEARCH":
			lvl = get_building_level("STUDY_PAVILION")
		"DIPLOMACY":
			lvl = get_building_level("BANQUET_HALL")
		"PATROL":
			lvl = get_building_level("WATCHTOWER_WALL")
		"LOGISTICS":
			lvl = get_building_level("GRANARY_VAULT")
		_:
			lvl = get_building_level("MAIN_HALL")
	return 1000 + (lvl - 1) * 120


func get_pawn_by_id(p_id: String) -> PawnEntity:
	for p: PawnEntity in pawns:
		if p.pawn_id == p_id:
			return p
	return null


func get_retainer_count() -> int:
	var cnt: int = 0
	for p: PawnEntity in pawns:
		if not p.is_avatar:
			cnt += 1
	return cnt


func add_pawn(pawn: PawnEntity) -> bool:
	if pawn == null or pawn.pawn_id.is_empty():
		return false
	if get_pawn_by_id(pawn.pawn_id) != null:
		return false
	if not pawn.is_avatar and get_retainer_count() >= DtoSchemas.MAX_RETAINERS:
		return false
	pawn.manor_id = manor_id
	pawn.owner_player_id = player_id
	pawns.append(pawn)
	return true


func queue_crafting_order(item_type: String, count: int = 1) -> void:
	if count <= 0:
		return
	crafting_queue.append({
		"item_type": item_type,
		"remaining": count,
		"progress_pm": 0
	})


func get_carry_pm(key: String) -> int:
	return _to_int(lod_remainder_carry.get(key, 0), 0)


func set_carry_pm(key: String, val: int) -> void:
	lod_remainder_carry[key] = val


func is_truce_active(tick_id: int) -> bool:
	return tick_id < truce_shield_until_tick


func to_dict() -> Dictionary:
	var res_copy: Dictionary = {}
	for rk: String in DtoSchemas.RESOURCE_KEYS:
		res_copy[rk] = get_resource(rk)

	var bld_copy: Dictionary = {}
	for bk: String in BUILDING_IDS:
		bld_copy[bk] = get_building_level(bk)

	var pawns_arr: Array[Dictionary] = []
	for p: PawnEntity in pawns:
		pawns_arr.append(p.to_dict())

	var zones_copy: Array[Dictionary] = []
	for z: Dictionary in zones:
		zones_copy.append(z.duplicate(true))

	var tmap_arr: Array[int] = []
	for tv: int in tile_zone_map:
		tmap_arr.append(tv)

	var gear_copy: Dictionary = {}
	for gk: String in GEAR_TIERS:
		gear_copy[gk] = maxi(0, _to_int(crafted_gear_counts.get(gk, 0), 0))

	var rprog_copy: Dictionary = {}
	for rk_t: Variant in research_progress_pm.keys():
		rprog_copy[str(rk_t)] = maxi(0, _to_int(research_progress_pm[rk_t], 0))

	var carry_copy: Dictionary = {}
	for ck: Variant in lod_remainder_carry.keys():
		carry_copy[str(ck)] = _to_int(lod_remainder_carry[ck], 0)

	var cqueue_copy: Array[Dictionary] = []
	for cq: Dictionary in crafting_queue:
		cqueue_copy.append(cq.duplicate(true))

	var rhist_copy: Array[Dictionary] = []
	for rh: Dictionary in raid_history:
		rhist_copy.append(rh.duplicate(true))

	var u_techs: Array[String] = []
	for ut: String in unlocked_techs:
		u_techs.append(ut)

	return {
		"manor_id": manor_id,
		"player_id": player_id,
		"host_node_id": host_node_id,
		"starting_province": starting_province,
		"current_lod": current_lod,
		"resources": res_copy,
		"ration_quality": ration_quality,
		"wine_policy_enabled": wine_policy_enabled,
		"buildings": bld_copy,
		"zones": zones_copy,
		"tile_zone_map": tmap_arr,
		"pawns": pawns_arr,
		"household_troops": household_troops,
		"troop_training_pm": troop_training_pm,
		"max_troops": max_troops,
		"wall_hp": wall_hp,
		"max_wall_hp": max_wall_hp,
		"trap_power": trap_power,
		"vault_protected_bp": vault_protected_bp,
		"truce_shield_until_tick": truce_shield_until_tick,
		"standing_doctrine": standing_doctrine.duplicate(true),
		"crafting_queue": cqueue_copy,
		"crafted_gear_counts": gear_copy,
		"active_research_id": active_research_id,
		"research_progress_pm": rprog_copy,
		"unlocked_techs": u_techs,
		"lod_remainder_carry": carry_copy,
		"jobs_completed": jobs_completed,
		"raid_defense_active": raid_defense_active,
		"raid_history": rhist_copy
	}


static func from_dict(data: Dictionary) -> ManorState:
	var m: ManorState = ManorState.new(
		str(data.get("manor_id", "manor_01")),
		str(data.get("player_id", "player_01"))
	)
	m.host_node_id = str(data.get("host_node_id", "xuchang"))
	m.starting_province = str(data.get("starting_province", "YU_ZHOU"))
	var lod_v: int = _to_int(data.get("current_lod", 1), 1)
	m.current_lod = 0 if lod_v == 0 else 1

	var res_var: Variant = data.get("resources", {})
	if res_var is Dictionary:
		var rd: Dictionary = res_var
		for rk: String in DtoSchemas.RESOURCE_KEYS:
			m.set_resource(rk, _to_int(rd.get(rk, 0), 0))

	var rq: String = str(data.get("ration_quality", "STANDARD"))
	m.ration_quality = rq if RATION_POLICIES.has(rq) else "STANDARD"
	m.wine_policy_enabled = _to_bool(data.get("wine_policy_enabled", true), true)

	var bld_var: Variant = data.get("buildings", {})
	if bld_var is Dictionary:
		var bd: Dictionary = bld_var
		for bk: String in BUILDING_IDS:
			m.buildings[bk] = clampi(_to_int(bd.get(bk, 1), 1), 1, 5)

	var z_var: Variant = data.get("zones", [])
	if z_var is Array:
		var za: Array = z_var
		if not za.is_empty():
			m.zones.clear()
			for item: Variant in za:
				if item is Dictionary:
					var zd: Dictionary = item
					m.zones.append(zd.duplicate(true))

	var tm_var: Variant = data.get("tile_zone_map", [])
	if tm_var is Array:
		var tma: Array = tm_var
		if tma.size() == DtoSchemas.MANOR_GRID_SIZE * DtoSchemas.MANOR_GRID_SIZE:
			var pmap: PackedInt32Array = PackedInt32Array()
			var _err: int = pmap.resize(tma.size())
			for i: int in range(tma.size()):
				pmap[i] = _to_int(tma[i], 1)
			m.tile_zone_map = pmap

	m.pawns.clear()
	var pawns_var: Variant = data.get("pawns", [])
	if pawns_var is Array:
		var pa: Array = pawns_var
		for item: Variant in pa:
			if item is Dictionary:
				var pd: Dictionary = item
				var p: PawnEntity = PawnEntity.from_dict(pd)
				m.pawns.append(p)

	m.household_troops = clampi(_to_int(data.get("household_troops", 0), 0), 0, 3000)
	m.troop_training_pm = clampi(_to_int(data.get("troop_training_pm", 500), 500), 0, 1000)

	m.unlocked_techs.clear()
	var ut_var: Variant = data.get("unlocked_techs", [])
	if ut_var is Array:
		var uta: Array = ut_var
		for item: Variant in uta:
			m.unlocked_techs.append(str(item))

	m.recompute_building_derived_caps()
	m.wall_hp = clampi(_to_int(data.get("wall_hp", m.max_wall_hp), m.max_wall_hp), 0, m.max_wall_hp)
	m.vault_protected_bp = clampi(_to_int(data.get("vault_protected_bp", m.vault_protected_bp), m.vault_protected_bp), 4000, 6500)
	m.truce_shield_until_tick = maxi(0, _to_int(data.get("truce_shield_until_tick", 0), 0))

	var sd_var: Variant = data.get("standing_doctrine", {})
	if sd_var is Dictionary:
		var sdd: Dictionary = sd_var
		m.standing_doctrine = DEFAULT_DOCTRINE.duplicate(true)
		for k: Variant in sdd.keys():
			m.standing_doctrine[str(k)] = sdd[k]

	m.crafting_queue.clear()
	var cq_var: Variant = data.get("crafting_queue", [])
	if cq_var is Array:
		var cqa: Array = cq_var
		for item: Variant in cqa:
			if item is Dictionary:
				var cqd: Dictionary = item
				m.crafting_queue.append(cqd.duplicate(true))

	var gc_var: Variant = data.get("crafted_gear_counts", {})
	if gc_var is Dictionary:
		var gcd: Dictionary = gc_var
		for gk: String in GEAR_TIERS:
			m.crafted_gear_counts[gk] = maxi(0, _to_int(gcd.get(gk, 0), 0))

	m.active_research_id = str(data.get("active_research_id", "DOUBLE_CROPPING"))
	m.research_progress_pm.clear()
	var rp_var: Variant = data.get("research_progress_pm", {})
	if rp_var is Dictionary:
		var rpd: Dictionary = rp_var
		for rk_t: Variant in rpd.keys():
			m.research_progress_pm[str(rk_t)] = maxi(0, _to_int(rpd[rk_t], 0))

	m.lod_remainder_carry.clear()
	var lc_var: Variant = data.get("lod_remainder_carry", {})
	if lc_var is Dictionary:
		var lcd: Dictionary = lc_var
		for ck: Variant in lcd.keys():
			m.lod_remainder_carry[str(ck)] = _to_int(lcd[ck], 0)

	m.jobs_completed = maxi(0, _to_int(data.get("jobs_completed", 0), 0))
	m.raid_defense_active = _to_bool(data.get("raid_defense_active", false), false)

	m.raid_history.clear()
	var rh_var: Variant = data.get("raid_history", [])
	if rh_var is Array:
		var rha: Array = rh_var
		for item: Variant in rha:
			if item is Dictionary:
				var rhd: Dictionary = item
				m.raid_history.append(rhd.duplicate(true))

	return m
