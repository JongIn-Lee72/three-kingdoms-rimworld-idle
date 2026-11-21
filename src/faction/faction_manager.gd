class_name FactionManager
extends RefCounted

const COURT_RANKS_ORDERED: Array[String] = [
	"NONE",
	"RANK_9", "RANK_8", "RANK_7", "RANK_6", "RANK_5",
	"RANK_4", "RANK_3", "RANK_2", "RANK_1", "SOVEREIGN"
]

const ROYAL_RANKS_ORDERED: Array[String] = [
	"GOVERNOR_INSPECTOR",
	"PROVINCE_GOVERNOR",
	"DUKE",
	"KING",
	"EMPEROR"
]

const MISSION_TYPES: Array[String] = [
	"BORDER_PATROL",
	"GRAIN_ESCORT",
	"FARM_RECLAMATION",
	"BANDIT_SUPPRESSION",
	"TALENT_RECRUITMENT"
]

const RANK_SPECS: Dictionary = {
	"NONE": {"tier": 0, "merit": 0, "coin": 0, "grain": 0, "troop_cap": 0},
	"RANK_9": {"tier": 1, "merit": 0, "coin": 100, "grain": 200, "troop_cap": 1000},
	"RANK_8": {"tier": 2, "merit": 500, "coin": 180, "grain": 350, "troop_cap": 2000},
	"RANK_7": {"tier": 3, "merit": 1500, "coin": 320, "grain": 600, "troop_cap": 3500},
	"RANK_6": {"tier": 4, "merit": 3500, "coin": 550, "grain": 1000, "troop_cap": 5000},
	"RANK_5": {"tier": 5, "merit": 7000, "coin": 900, "grain": 1800, "troop_cap": 8000},
	"RANK_4": {"tier": 6, "merit": 12000, "coin": 1400, "grain": 2800, "troop_cap": 11000},
	"RANK_3": {"tier": 7, "merit": 20000, "coin": 2200, "grain": 4200, "troop_cap": 15000},
	"RANK_2": {"tier": 8, "merit": 32000, "coin": 3500, "grain": 6500, "troop_cap": 20000},
	"RANK_1": {"tier": 9, "merit": 50000, "coin": 5500, "grain": 10000, "troop_cap": 30000},
	"SOVEREIGN": {"tier": 10, "merit": 0, "coin": 0, "grain": 0, "troop_cap": 50000}
}

const ROYAL_RANK_REQS: Dictionary = {
	"PROVINCE_GOVERNOR": {"prestige": 500, "min_nodes": 2},
	"DUKE": {"prestige": 1500, "min_nodes": 4},
	"KING": {"prestige": 3500, "min_nodes": 7},
	"EMPEROR": {"prestige": 7000, "min_nodes": 10}
}

var factions: Dictionary = {}
var players: Dictionary = {}
var missions: Dictionary = {}
var proposals: Dictionary = {}
var _next_mission_seq: int = 1
var _next_proposal_seq: int = 1


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


static func _rank_tier(court_rank: String) -> int:
	var spec_var: Variant = RANK_SPECS.get(court_rank, null)
	if spec_var is Dictionary:
		var spec: Dictionary = spec_var
		return _to_int(spec.get("tier", 0), 0)
	return 0


static func _royal_rank_index(royal_rank: String) -> int:
	if royal_rank == "PREFECT":
		return 0
	if royal_rank == "GOVERNOR_GENERAL":
		return 1
	var idx: int = ROYAL_RANKS_ORDERED.find(royal_rank)
	return idx if idx >= 0 else 0


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
	factions.clear()
	players.clear()
	missions.clear()
	proposals.clear()
	_next_mission_seq = 1
	_next_proposal_seq = 1


func has_faction(faction_id: String) -> bool:
	return factions.has(faction_id)


func get_faction_ids() -> Array[String]:
	var ids: Array[String] = []
	for k: Variant in factions.keys():
		ids.append(str(k))
	ids.sort()
	return ids


func get_faction(faction_id: String) -> Dictionary:
	var v: Variant = factions.get(faction_id, {})
	if v is Dictionary:
		var d: Dictionary = v
		return d.duplicate(true)
	return {}


func has_player(player_id: String) -> bool:
	return players.has(player_id)


func get_player_ids() -> Array[String]:
	var ids: Array[String] = []
	for k: Variant in players.keys():
		ids.append(str(k))
	ids.sort()
	return ids


func get_player_profile(player_id: String) -> Dictionary:
	var v: Variant = players.get(player_id, {})
	if v is Dictionary:
		var d: Dictionary = v
		return d.duplicate(true)
	return {}


func register_player(player_id: String, initial_profile: Dictionary = {}) -> Dictionary:
	if player_id.is_empty():
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Empty player_id"}
	if players.has(player_id):
		return get_player_profile(player_id)

	var rt: String = str(initial_profile.get("role_tier", "FREE_OFFICER"))
	if not DtoSchemas.ROLE_TIERS.has(rt):
		rt = "FREE_OFFICER"
	var cr: String = str(initial_profile.get("court_rank", "NONE"))
	if not COURT_RANKS_ORDERED.has(cr):
		cr = "NONE"

	var default_prefs: Array[String] = ["BORDER_PATROL", "GRAIN_ESCORT", "FARM_RECLAMATION", "BANDIT_SUPPRESSION"]
	var prefs: Array[String] = default_prefs
	if initial_profile.has("auto_mission_prefs"):
		prefs = _extract_string_array(initial_profile.get("auto_mission_prefs", []))

	var gov_nodes: Array[String] = _extract_string_array(initial_profile.get("governed_node_ids", []))
	var vice_nodes: Array[String] = _extract_string_array(initial_profile.get("viceroy_node_ids", []))

	var rec: Dictionary = {
		"player_id": player_id,
		"role_tier": rt,
		"faction_id": str(initial_profile.get("faction_id", "")),
		"court_rank": cr,
		"war_merit": maxi(0, _to_int(initial_profile.get("war_merit", 0), 0)),
		"governed_node_ids": gov_nodes,
		"viceroy_node_ids": vice_nodes,
		"is_viceroy": _to_bool(initial_profile.get("is_viceroy", false), false),
		"auto_mission_prefs": prefs
	}
	players[player_id] = rec
	return rec.duplicate(true)


func create_faction(
	faction_id: String,
	faction_name: String,
	lord_player_id: String,
	capital_node_id: String,
	world_graph: WorldGraph = null,
	initial_grain: int = 5000,
	initial_coin: int = 5000,
	royal_rank: String = "GOVERNOR_INSPECTOR"
) -> Dictionary:
	if faction_id.is_empty() or faction_name.is_empty() or lord_player_id.is_empty() or capital_node_id.is_empty():
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Missing faction parameters"}
	if factions.has(faction_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Faction already exists"}
	if world_graph != null and not world_graph.has_node(capital_node_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown capital node"}

	var resolved_rr: String = royal_rank if ROYAL_RANKS_ORDERED.has(royal_rank) else "GOVERNOR_INSPECTOR"
	var fac: Dictionary = {
		"faction_id": faction_id,
		"name": faction_name,
		"lord_player_id": lord_player_id,
		"capital_node_id": capital_node_id,
		"treasury_grain": maxi(0, initial_grain),
		"treasury_coin": maxi(0, initial_coin),
		"prestige": 0,
		"royal_rank": resolved_rr,
		"oathbreaker_until_tick": 0,
		"diplomatic_trust_bp": 10000,
		"policy_sliders": {
			"tax_rate_bp": 1000,
			"conscription_bp": 1000,
			"stipend_budget_bp": 10000
		}
	}
	factions[faction_id] = fac

	if not players.has(lord_player_id):
		var _reg: Dictionary = register_player(lord_player_id)
	var lord_prof: Dictionary = players[lord_player_id]
	lord_prof["role_tier"] = "LORD"
	lord_prof["faction_id"] = faction_id
	lord_prof["court_rank"] = "SOVEREIGN"
	var g_nodes: Array[String] = _extract_string_array(lord_prof.get("governed_node_ids", []))
	if not g_nodes.has(capital_node_id):
		g_nodes.append(capital_node_id)
	lord_prof["governed_node_ids"] = g_nodes

	if world_graph != null:
		var _set_ok: bool = world_graph.set_node_owner(capital_node_id, faction_id, "")

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"faction": fac.duplicate(true)
	}


func get_faction_members(faction_id: String) -> Array[String]:
	var members: Array[String] = []
	for pid: String in get_player_ids():
		var p_var: Variant = players[pid]
		if p_var is Dictionary:
			var pd: Dictionary = p_var
			if str(pd.get("faction_id", "")) == faction_id:
				members.append(pid)
	return members


func count_faction_nodes(faction_id: String, world_graph: WorldGraph) -> int:
	if world_graph == null:
		return 0
	var count: int = 0
	for nid: String in world_graph.get_node_ids():
		var nd: Dictionary = world_graph.get_node(nid)
		if str(nd.get("owner_faction_id", "")) == faction_id:
			count += 1
	return count


func adjust_faction_treasury(faction_id: String, coin_delta: int, grain_delta: int, prestige_delta: int = 0) -> Dictionary:
	if not factions.has(faction_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown faction"}
	var fac: Dictionary = factions[faction_id]
	var cur_coin: int = _to_int(fac.get("treasury_coin", 0), 0)
	var cur_grain: int = _to_int(fac.get("treasury_grain", 0), 0)
	var cur_pres: int = _to_int(fac.get("prestige", 0), 0)
	if cur_coin + coin_delta < 0 or cur_grain + grain_delta < 0:
		return {"ok": false, "error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE, "reason": "Insufficient treasury"}
	fac["treasury_coin"] = maxi(0, cur_coin + coin_delta)
	fac["treasury_grain"] = maxi(0, cur_grain + grain_delta)
	fac["prestige"] = maxi(0, cur_pres + prestige_delta)
	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"treasury_coin": fac["treasury_coin"],
		"treasury_grain": fac["treasury_grain"],
		"prestige": fac["prestige"]
	}


func set_player_auto_mission_prefs(player_id: String, prefs: Array) -> Dictionary:
	if not players.has(player_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown player"}
	var clean_prefs: Array[String] = []
	for item: Variant in prefs:
		var ms: String = str(item)
		if MISSION_TYPES.has(ms) and not clean_prefs.has(ms):
			clean_prefs.append(ms)
	var prof: Dictionary = players[player_id]
	prof["auto_mission_prefs"] = clean_prefs
	return {"ok": true, "error_code": DtoSchemas.ERR_OK, "auto_mission_prefs": clean_prefs.duplicate()}


func enlist_officer(player_id: String, faction_id: String, initial_rank: String = "RANK_9") -> Dictionary:
	if player_id.is_empty() or not factions.has(faction_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown faction or player_id"}
	if not players.has(player_id):
		var _reg: Dictionary = register_player(player_id)
	var prof: Dictionary = players[player_id]
	var cur_role: String = str(prof.get("role_tier", "FREE_OFFICER"))
	var cur_fid: String = str(prof.get("faction_id", ""))
	if cur_role == "LORD" and not cur_fid.is_empty() and cur_fid != faction_id:
		return {"ok": false, "error_code": DtoSchemas.ERR_ROLE_PERMISSION, "reason": "Lord cannot enlist into another faction"}
	if not cur_fid.is_empty() and cur_fid != faction_id:
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Player already belongs to a faction"}

	var r_tier: int = _rank_tier(initial_rank)
	var rank_to_set: String = initial_rank if (r_tier >= 1 and r_tier <= 9) else "RANK_9"
	prof["role_tier"] = "FACTION_OFFICER"
	prof["faction_id"] = faction_id
	prof["court_rank"] = rank_to_set
	var empty_nodes: Array[String] = []
	prof["governed_node_ids"] = empty_nodes
	prof["viceroy_node_ids"] = empty_nodes.duplicate()
	prof["is_viceroy"] = false

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"player_id": player_id,
		"faction_id": faction_id,
		"role_tier": "FACTION_OFFICER",
		"court_rank": rank_to_set
	}


func get_rank_for_merit(war_merit: int) -> String:
	var best_rank: String = "RANK_9"
	for rk: String in ["RANK_9", "RANK_8", "RANK_7", "RANK_6", "RANK_5", "RANK_4", "RANK_3", "RANK_2", "RANK_1"]:
		var spec_var: Variant = RANK_SPECS.get(rk, {})
		if spec_var is Dictionary:
			var spec: Dictionary = spec_var
			if war_merit >= _to_int(spec.get("merit", 0), 0):
				best_rank = rk
	return best_rank


func get_troop_cap_for_rank(court_rank: String) -> int:
	var spec_var: Variant = RANK_SPECS.get(court_rank, {})
	if spec_var is Dictionary:
		var spec: Dictionary = spec_var
		return _to_int(spec.get("troop_cap", 0), 0)
	return 0


func award_merit_and_promote(player_id: String, merit_delta: int, pawn: PawnEntity = null) -> Dictionary:
	if not players.has(player_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown player"}
	if merit_delta < 0:
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "merit_delta must be >= 0"}

	var prof: Dictionary = players[player_id]
	var gain: int = merit_delta
	if pawn != null and pawn.has_trait("T_AMBITIOUS"):
		@warning_ignore("integer_division")
		gain = (merit_delta * 1150) / 1000

	var new_merit: int = _to_int(prof.get("war_merit", 0), 0) + gain
	prof["war_merit"] = new_merit

	var old_rank: String = str(prof.get("court_rank", "NONE"))
	var new_rank: String = old_rank
	var promoted: bool = false

	if str(prof.get("role_tier", "FREE_OFFICER")) != "FREE_OFFICER" and old_rank != "SOVEREIGN":
		var earned_rank: String = get_rank_for_merit(new_merit)
		if _rank_tier(earned_rank) > _rank_tier(old_rank):
			new_rank = earned_rank
			prof["court_rank"] = new_rank
			promoted = true

	if pawn != null:
		var tier_val: int = _rank_tier(new_rank)
		if tier_val >= 1 and tier_val <= 9:
			pawn.current_rank = tier_val

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"player_id": player_id,
		"merit_gain": gain,
		"war_merit": new_merit,
		"old_rank": old_rank,
		"new_rank": new_rank,
		"promoted": promoted
	}


func _resolve_pawn_for_player(player_id: String, officer_pawns: Variant) -> PawnEntity:
	var candidates: Array = []
	if officer_pawns is Dictionary:
		var pd: Dictionary = officer_pawns
		if pd.has(player_id):
			var direct_v: Variant = pd[player_id]
			if direct_v is PawnEntity:
				var direct_p: PawnEntity = direct_v
				return direct_p
		for k: Variant in pd.keys():
			candidates.append(pd[k])
	elif officer_pawns is Array:
		var pa: Array = officer_pawns
		for item: Variant in pa:
			candidates.append(item)

	for pv: Variant in candidates:
		if pv is PawnEntity:
			var p: PawnEntity = pv
			if p.pawn_id == player_id or (p.owner_player_id == player_id and p.is_avatar):
				return p
	for pv2: Variant in candidates:
		if pv2 is PawnEntity:
			var p2: PawnEntity = pv2
			if p2.owner_player_id == player_id:
				return p2
	return null


func _resolve_manor_for_player(player_id: String, manors: Variant) -> ManorState:
	var candidates: Array = []
	if manors is Dictionary:
		var md: Dictionary = manors
		if md.has(player_id):
			var direct_v: Variant = md[player_id]
			if direct_v is ManorState:
				var direct_m: ManorState = direct_v
				return direct_m
		for k: Variant in md.keys():
			candidates.append(md[k])
	elif manors is Array:
		var ma: Array = manors
		for item: Variant in ma:
			candidates.append(item)

	for mv: Variant in candidates:
		if mv is ManorState:
			var m: ManorState = mv
			if m.player_id == player_id:
				return m
	return null


func settle_daily_stipends(
	faction_id: String,
	officer_pawns: Variant = {},
	manors: Variant = {},
	clock: SimClock = null,
	event_bus: SimEventBus = null
) -> Dictionary:
	if not factions.has(faction_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown faction"}

	var fac: Dictionary = factions[faction_id]
	var sliders_var: Variant = fac.get("policy_sliders", {})
	var sliders: Dictionary = sliders_var if sliders_var is Dictionary else {}
	var budget_bp: int = clampi(_to_int(sliders.get("stipend_budget_bp", 10000), 10000), 0, 20000)

	var paid_officers: Array[String] = []
	var arrears_officers: Array[String] = []
	var total_coin_paid: int = 0
	var total_grain_paid: int = 0
	var bankrupt: bool = false

	for pid: String in get_faction_members(faction_id):
		var prof: Dictionary = players[pid]
		var crank: String = str(prof.get("court_rank", "NONE"))
		if crank == "NONE" or crank == "SOVEREIGN":
			continue

		var spec_var: Variant = RANK_SPECS.get(crank, {})
		var spec: Dictionary = spec_var if spec_var is Dictionary else {}
		var base_coin: int = _to_int(spec.get("coin", 0), 0)
		var base_grain: int = _to_int(spec.get("grain", 0), 0)

		var pawn: PawnEntity = _resolve_pawn_for_player(pid, officer_pawns)
		var mult_pm: int = pawn.get_stipend_multiplier_pm() if pawn != null else 1000

		@warning_ignore("integer_division")
		var coin_due: int = (base_coin * budget_bp * mult_pm) / 10000000
		@warning_ignore("integer_division")
		var grain_due: int = (base_grain * budget_bp * mult_pm) / 10000000

		var cur_coin: int = _to_int(fac.get("treasury_coin", 0), 0)
		var cur_grain: int = _to_int(fac.get("treasury_grain", 0), 0)

		if cur_coin >= coin_due and cur_grain >= grain_due:
			fac["treasury_coin"] = cur_coin - coin_due
			fac["treasury_grain"] = cur_grain - grain_due
			total_coin_paid += coin_due
			total_grain_paid += grain_due
			paid_officers.append(pid)

			var manor: ManorState = _resolve_manor_for_player(pid, manors)
			if manor != null:
				var _ac: int = manor.add_resource("COIN", coin_due)
				var _ag: int = manor.add_resource("GRAIN", grain_due)
			if pawn != null:
				pawn.add_need("LOYALTY", 100)
		else:
			bankrupt = true
			arrears_officers.append(pid)
			if pawn != null:
				pawn.add_need("LOYALTY", -800)
				pawn.add_thought("STIPEND_ARREARS", -15, 24)
				var _new_mood: int = pawn.step_mood(0, 1)

	var tick_id: int = clock.current_tick_id if clock != null else 0
	var summary: Dictionary = {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"faction_id": faction_id,
		"tick_id": tick_id,
		"paid_officers": paid_officers,
		"arrears_officers": arrears_officers,
		"total_coin_paid": total_coin_paid,
		"total_grain_paid": total_grain_paid,
		"bankrupt": bankrupt
	}
	if event_bus != null:
		var _seq: int = event_bus.emit(SimEventBus.EVENT_STIPEND_DISTRIBUTED, summary, tick_id)
	return summary


func post_mission(faction_id: String, mission_spec: Dictionary) -> Dictionary:
	if not factions.has(faction_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown faction"}
	var mtype: String = str(mission_spec.get("mission_type", "BORDER_PATROL"))
	if not MISSION_TYPES.has(mtype):
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Invalid mission_type: " + mtype}

	var mid: String = str(mission_spec.get("mission_id", ""))
	if mid.is_empty():
		mid = "mission_%06d" % _next_mission_seq
		_next_mission_seq += 1

	var min_rank: String = str(mission_spec.get("min_rank", "RANK_9"))
	if not COURT_RANKS_ORDERED.has(min_rank):
		min_rank = "RANK_9"

	var rec: Dictionary = {
		"mission_id": mid,
		"faction_id": faction_id,
		"mission_type": mtype,
		"node_id": str(mission_spec.get("node_id", "")),
		"reward_merit": maxi(0, _to_int(mission_spec.get("reward_merit", 200), 200)),
		"reward_coin": maxi(0, _to_int(mission_spec.get("reward_coin", 150), 150)),
		"reward_grain": maxi(0, _to_int(mission_spec.get("reward_grain", 100), 100)),
		"min_rank": min_rank,
		"status": "OPEN",
		"assigned_player_id": "",
		"completed_tick": -1
	}
	missions[mid] = rec
	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"mission_id": mid,
		"mission": rec.duplicate(true)
	}


func get_mission_ids() -> Array[String]:
	var ids: Array[String] = []
	for k: Variant in missions.keys():
		ids.append(str(k))
	ids.sort()
	return ids


func process_idle_mission_queue(
	faction_id: String,
	clock: SimClock,
	world_seed: int,
	manors: Variant = {},
	pawns: Variant = {}
) -> Array[Dictionary]:
	var completed: Array[Dictionary] = []
	if not factions.has(faction_id) or clock == null:
		return completed

	var tick_id: int = clock.current_tick_id
	var sorted_mids: Array[String] = get_mission_ids()

	for pid: String in get_faction_members(faction_id):
		var prof: Dictionary = players[pid]
		var rt: String = str(prof.get("role_tier", "FREE_OFFICER"))
		if rt == "FREE_OFFICER" or rt == "LORD":
			continue

		var pawn: PawnEntity = _resolve_pawn_for_player(pid, pawns)
		if pawn != null and (pawn.state == "CAPTURED" or pawn.is_in_mental_break()):
			continue

		var p_tier: int = _rank_tier(str(prof.get("court_rank", "RANK_9")))
		var prefs: Array[String] = _extract_string_array(prof.get("auto_mission_prefs", []))
		if prefs.is_empty():
			continue

		var chosen_mid: String = ""
		for pref_type: String in prefs:
			var candidates: Array[String] = []
			for mid: String in sorted_mids:
				var m_var: Variant = missions[mid]
				if not (m_var is Dictionary):
					continue
				var md: Dictionary = m_var
				if str(md.get("faction_id", "")) != faction_id:
					continue
				if str(md.get("status", "")) != "OPEN":
					continue
				if str(md.get("mission_type", "")) != pref_type:
					continue
				var req_tier: int = _rank_tier(str(md.get("min_rank", "RANK_9")))
				if p_tier < req_tier:
					continue
				candidates.append(mid)
			if not candidates.is_empty():
				var p_hash: int = StateHasher.crc32_bytes(pid.to_utf8_buffer())
				var pick_idx: int = DeterministicRNG.roll_range(
					world_seed, tick_id, p_hash, 6101, 0, candidates.size() - 1
				)
				chosen_mid = candidates[pick_idx]
				break

		if chosen_mid.is_empty():
			continue

		var chosen_m: Dictionary = missions[chosen_mid]
		chosen_m["status"] = "COMPLETED"
		chosen_m["assigned_player_id"] = pid
		chosen_m["completed_tick"] = tick_id

		var r_merit: int = _to_int(chosen_m.get("reward_merit", 0), 0)
		var r_coin: int = _to_int(chosen_m.get("reward_coin", 0), 0)
		var r_grain: int = _to_int(chosen_m.get("reward_grain", 0), 0)

		var promo_res: Dictionary = award_merit_and_promote(pid, r_merit, pawn)
		var manor: ManorState = _resolve_manor_for_player(pid, manors)
		if manor != null:
			var _ac: int = manor.add_resource("COIN", r_coin)
			var _ag: int = manor.add_resource("GRAIN", r_grain)

		completed.append({
			"mission_id": chosen_mid,
			"mission_type": str(chosen_m.get("mission_type", "")),
			"player_id": pid,
			"reward_merit": _to_int(promo_res.get("merit_gain", r_merit), r_merit),
			"reward_coin": r_coin,
			"reward_grain": r_grain,
			"promoted": _to_bool(promo_res.get("promoted", false), false),
			"new_rank": str(promo_res.get("new_rank", prof.get("court_rank", "RANK_9"))),
			"tick_id": tick_id
		})

	return completed


func generate_retainer_proposal(
	pawn: PawnEntity,
	manor: ManorState,
	clock: SimClock,
	world_seed: int
) -> Dictionary:
	if pawn == null or manor == null or clock == null:
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Null pawn/manor/clock"}

	var proposal_type: String = "AGRICULTURE_EXPANSION"
	var target_building: String = "MILITARY_FARM"
	var trait_basis: String = "DEFAULT"

	if pawn.has_trait("T_AGRARIAN"):
		proposal_type = "AGRICULTURE_EXPANSION"
		target_building = "MILITARY_FARM"
		trait_basis = "T_AGRARIAN"
	elif pawn.has_trait("T_CAUTIOUS"):
		proposal_type = "FORTIFY_WALLS"
		target_building = "WATCHTOWER_WALL"
		trait_basis = "T_CAUTIOUS"
	elif pawn.has_trait("T_MYSTIC"):
		proposal_type = "RESEARCH_STRATAGEM"
		target_building = "STUDY_PAVILION"
		trait_basis = "T_MYSTIC"
	elif pawn.has_trait("T_FIERCE"):
		proposal_type = "MILITARY_DRILL"
		target_building = "BARRACKS_DRILL"
		trait_basis = "T_FIERCE"
	elif pawn.has_trait("T_SCHOLAR"):
		proposal_type = "HOST_BANQUET_RECRUIT"
		target_building = "BANQUET_HALL"
		trait_basis = "T_SCHOLAR"
	else:
		var pool: Array[Array] = [
			["AGRICULTURE_EXPANSION", "MILITARY_FARM"],
			["FORTIFY_WALLS", "WATCHTOWER_WALL"],
			["MILITARY_DRILL", "BARRACKS_DRILL"],
			["RESEARCH_STRATAGEM", "STUDY_PAVILION"]
		]
		var idx: int = DeterministicRNG.roll_range(
			world_seed, clock.current_tick_id, pawn.get_entity_hash_id(), 6201, 0, pool.size() - 1
		)
		var entry: Array = pool[idx]
		proposal_type = str(entry[0])
		target_building = str(entry[1])

	var prop_id: String = "prop_%06d" % _next_proposal_seq
	_next_proposal_seq += 1

	var rec: Dictionary = {
		"proposal_id": prop_id,
		"pawn_id": pawn.pawn_id,
		"owner_player_id": pawn.owner_player_id,
		"manor_id": manor.manor_id,
		"proposal_type": proposal_type,
		"trait_basis": trait_basis,
		"target_building": target_building,
		"status": "PENDING",
		"created_tick": clock.current_tick_id
	}
	proposals[prop_id] = rec
	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"proposal_id": prop_id,
		"proposal": rec.duplicate(true)
	}


func adopt_proposal(proposal_id: String, pawn: PawnEntity, manor: ManorState = null) -> Dictionary:
	if not proposals.has(proposal_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown proposal"}
	var prop: Dictionary = proposals[proposal_id]
	if str(prop.get("status", "")) != "PENDING":
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Proposal already resolved"}
	if pawn == null:
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Null pawn"}

	prop["status"] = "ADOPTED"
	pawn.add_need("LOYALTY", 600)
	pawn.add_need("AMBITION", 1000)
	pawn.add_thought("PROPOSAL_ADOPTED", 6, 24)
	var _m: int = pawn.step_mood(0, 1)

	var applied_effects: Array[String] = []
	if manor != null:
		var target_bld: String = str(prop.get("target_building", "MAIN_HALL"))
		var upgraded: bool = manor.upgrade_building(target_bld)
		if upgraded:
			applied_effects.append("UPGRADED_" + target_bld)

		var ptype: String = str(prop.get("proposal_type", ""))
		match ptype:
			"AGRICULTURE_EXPANSION":
				var _g: int = manor.add_resource("GRAIN", 250)
				applied_effects.append("GRAIN_BONUS_250")
			"FORTIFY_WALLS":
				manor.wall_hp = mini(manor.max_wall_hp, manor.wall_hp + 300)
				manor.trap_power += 25
				manor.standing_doctrine["engagement_stance"] = "DEFENSIVE_HOLD"
				applied_effects.append("WALL_TRAP_FORTIFIED")
			"MILITARY_DRILL":
				manor.troop_training_pm = clampi(manor.troop_training_pm + 100, 0, 1000)
				manor.standing_doctrine["engagement_stance"] = "PREEMPTIVE_STRIKE"
				applied_effects.append("TRAINING_BOOSTED")
			"RESEARCH_STRATAGEM":
				var rid: String = manor.active_research_id
				if not rid.is_empty():
					var cur_prog: int = _to_int(manor.research_progress_pm.get(rid, 0), 0)
					manor.research_progress_pm[rid] = cur_prog + 250
				manor.standing_doctrine["stratagem_policy"] = "FIRE_OR_FLOOD"
				applied_effects.append("RESEARCH_BOOSTED")
			"HOST_BANQUET_RECRUIT":
				var _w: int = manor.add_resource("HERBS_WINE", 40)
				applied_effects.append("WINE_STOCKED_40")

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"proposal_id": proposal_id,
		"status": "ADOPTED",
		"loyalty_bp": pawn.get_need("LOYALTY"),
		"ambition_bp": pawn.get_need("AMBITION"),
		"effects": applied_effects
	}


func reject_proposal(proposal_id: String, pawn: PawnEntity) -> Dictionary:
	if not proposals.has(proposal_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown proposal"}
	var prop: Dictionary = proposals[proposal_id]
	if str(prop.get("status", "")) != "PENDING":
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Proposal already resolved"}
	if pawn == null:
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Null pawn"}

	prop["status"] = "REJECTED"
	pawn.add_need("LOYALTY", -300)
	pawn.add_need("AMBITION", -500)
	pawn.add_thought("PROPOSAL_REJECTED", -4, 12)
	var _m: int = pawn.step_mood(0, 1)

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"proposal_id": proposal_id,
		"status": "REJECTED",
		"loyalty_bp": pawn.get_need("LOYALTY"),
		"ambition_bp": pawn.get_need("AMBITION")
	}


func appoint_governor(
	lord_id: String,
	target_player_id: String,
	node_id: String,
	world_graph: WorldGraph
) -> Dictionary:
	if not players.has(lord_id) or not players.has(target_player_id) or world_graph == null:
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Invalid player or world_graph"}
	var lord_prof: Dictionary = players[lord_id]
	if str(lord_prof.get("role_tier", "")) != "LORD":
		return {"ok": false, "error_code": DtoSchemas.ERR_ROLE_PERMISSION, "reason": "Only LORD can appoint governor"}
	var fid: String = str(lord_prof.get("faction_id", ""))
	if fid.is_empty():
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Lord has no faction"}

	var target_prof: Dictionary = players[target_player_id]
	if str(target_prof.get("faction_id", "")) != fid:
		return {"ok": false, "error_code": DtoSchemas.ERR_ROLE_PERMISSION, "reason": "Target not in faction"}
	var t_tier: int = _rank_tier(str(target_prof.get("court_rank", "NONE")))
	if t_tier < _rank_tier("RANK_5"):
		return {"ok": false, "error_code": DtoSchemas.ERR_ROLE_PERMISSION, "reason": "Requires RANK_5 or higher"}

	if not world_graph.has_node(node_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown node_id"}
	var nd: Dictionary = world_graph.get_node(node_id)
	if str(nd.get("owner_faction_id", "")) != fid:
		return {"ok": false, "error_code": DtoSchemas.ERR_ROLE_PERMISSION, "reason": "Faction does not own node"}

	var prev_gov: String = str(nd.get("governor_player_id", ""))
	if not prev_gov.is_empty() and prev_gov != target_player_id and players.has(prev_gov):
		var prev_prof: Dictionary = players[prev_gov]
		var prev_nodes: Array[String] = _extract_string_array(prev_prof.get("governed_node_ids", []))
		prev_nodes.erase(node_id)
		prev_prof["governed_node_ids"] = prev_nodes

	var _ok_own: bool = world_graph.set_node_owner(node_id, fid, target_player_id)
	if str(target_prof.get("role_tier", "")) != "LORD":
		target_prof["role_tier"] = "GOVERNOR"
	var g_nodes: Array[String] = _extract_string_array(target_prof.get("governed_node_ids", []))
	if not g_nodes.has(node_id):
		g_nodes.append(node_id)
	target_prof["governed_node_ids"] = g_nodes

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"node_id": node_id,
		"governor_player_id": target_player_id,
		"role_tier": target_prof["role_tier"]
	}


func appoint_viceroy(
	lord_id: String,
	target_player_id: String,
	nodes_or_province: Variant,
	world_graph: WorldGraph
) -> Dictionary:
	if not players.has(lord_id) or not players.has(target_player_id) or world_graph == null:
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Invalid player or world_graph"}
	var lord_prof: Dictionary = players[lord_id]
	if str(lord_prof.get("role_tier", "")) != "LORD":
		return {"ok": false, "error_code": DtoSchemas.ERR_ROLE_PERMISSION, "reason": "Only LORD can appoint viceroy"}
	var fid: String = str(lord_prof.get("faction_id", ""))

	var target_prof: Dictionary = players[target_player_id]
	if str(target_prof.get("faction_id", "")) != fid:
		return {"ok": false, "error_code": DtoSchemas.ERR_ROLE_PERMISSION, "reason": "Target not in faction"}
	var t_tier: int = _rank_tier(str(target_prof.get("court_rank", "NONE")))
	if t_tier < _rank_tier("RANK_2"):
		return {"ok": false, "error_code": DtoSchemas.ERR_ROLE_PERMISSION, "reason": "Requires RANK_2 or higher"}

	var target_nodes: Array[String] = []
	if nodes_or_province is Array:
		var arr: Array = nodes_or_province
		for item: Variant in arr:
			var nid: String = str(item)
			if world_graph.has_node(nid) and str(world_graph.get_node(nid).get("owner_faction_id", "")) == fid:
				if not target_nodes.has(nid):
					target_nodes.append(nid)
	elif nodes_or_province is String:
		var s: String = nodes_or_province
		if world_graph.has_node(s):
			if str(world_graph.get_node(s).get("owner_faction_id", "")) == fid:
				target_nodes.append(s)
		else:
			for nid: String in world_graph.get_node_ids():
				var nd: Dictionary = world_graph.get_node(nid)
				if str(nd.get("owner_faction_id", "")) == fid and str(nd.get("province", "")) == s:
					target_nodes.append(nid)

	if target_nodes.is_empty():
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "No owned nodes specified for viceroy"}

	var g_nodes: Array[String] = _extract_string_array(target_prof.get("governed_node_ids", []))
	var v_nodes: Array[String] = _extract_string_array(target_prof.get("viceroy_node_ids", []))
	for nid: String in target_nodes:
		var _ok_set: bool = world_graph.set_node_owner(nid, fid, target_player_id)
		if not g_nodes.has(nid):
			g_nodes.append(nid)
		if not v_nodes.has(nid):
			v_nodes.append(nid)

	if str(target_prof.get("role_tier", "")) != "LORD":
		target_prof["role_tier"] = "GOVERNOR"
	target_prof["is_viceroy"] = true
	target_prof["governed_node_ids"] = g_nodes
	target_prof["viceroy_node_ids"] = v_nodes

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"viceroy_player_id": target_player_id,
		"node_ids": target_nodes,
		"role_tier": target_prof["role_tier"]
	}


func set_node_local_policy(
	governor_id: String,
	node_id: String,
	tax_rate_bp: int,
	defense_budget: int,
	world_graph: WorldGraph
) -> Dictionary:
	if tax_rate_bp < 500 or tax_rate_bp > 2500:
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "tax_rate_bp must be in [500, 2500]"}
	if defense_budget < 0:
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "defense_budget must be >= 0"}
	if world_graph == null or not world_graph.has_node(node_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown node_id"}
	if not players.has(governor_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown governor_id"}

	var nd: Dictionary = world_graph.get_node(node_id)
	var owner_fid: String = str(nd.get("owner_faction_id", ""))
	var gov_prof: Dictionary = players[governor_id]
	var gov_fid: String = str(gov_prof.get("faction_id", ""))
	if owner_fid.is_empty() or gov_fid != owner_fid:
		return {"ok": false, "error_code": DtoSchemas.ERR_ROLE_PERMISSION, "reason": "Not in node owning faction"}

	var g_nodes: Array[String] = _extract_string_array(gov_prof.get("governed_node_ids", []))
	var is_lord: bool = str(gov_prof.get("role_tier", "")) == "LORD"
	var is_assigned_gov: bool = str(nd.get("governor_player_id", "")) == governor_id or g_nodes.has(node_id)
	if not is_lord and not is_assigned_gov:
		return {"ok": false, "error_code": DtoSchemas.ERR_ROLE_PERMISSION, "reason": "Player is not governor of node"}

	if defense_budget > 0 and factions.has(owner_fid):
		var fac: Dictionary = factions[owner_fid]
		var cur_coin: int = _to_int(fac.get("treasury_coin", 0), 0)
		if cur_coin < defense_budget:
			return {"ok": false, "error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE, "reason": "Insufficient faction coin for defense_budget"}
		fac["treasury_coin"] = cur_coin - defense_budget
		var _new_hp: int = world_graph.repair_fortification(node_id, defense_budget)

	var _ok_tax: bool = world_graph.set_node_tax_rate(node_id, tax_rate_bp)
	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"node_id": node_id,
		"tax_rate_bp": tax_rate_bp,
		"defense_budget": defense_budget,
		"fortification_hp": _to_int(world_graph.get_node(node_id).get("fortification_hp", 0), 0)
	}


func set_lord_policy_sliders(
	lord_id: String,
	tax_rate_bp: int,
	conscription_bp: int,
	stipend_budget_bp: int
) -> Dictionary:
	if not players.has(lord_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown lord_id"}
	var prof: Dictionary = players[lord_id]
	if str(prof.get("role_tier", "")) != "LORD":
		return {"ok": false, "error_code": DtoSchemas.ERR_ROLE_PERMISSION, "reason": "Only LORD can set policy sliders"}
	var fid: String = str(prof.get("faction_id", ""))
	if not factions.has(fid):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Lord has no faction"}

	if tax_rate_bp < 500 or tax_rate_bp > 5000 or conscription_bp < 0 or conscription_bp > 5000 or stipend_budget_bp < 0 or stipend_budget_bp > 20000:
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Slider out of bounds"}

	var fac: Dictionary = factions[fid]
	var new_sliders: Dictionary = {
		"tax_rate_bp": tax_rate_bp,
		"conscription_bp": conscription_bp,
		"stipend_budget_bp": stipend_budget_bp
	}
	fac["policy_sliders"] = new_sliders
	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"faction_id": fid,
		"policy_sliders": new_sliders.duplicate(true)
	}


func try_ascend_royal_rank(lord_id: String, world_graph: WorldGraph = null) -> Dictionary:
	if not players.has(lord_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown lord_id"}
	var prof: Dictionary = players[lord_id]
	if str(prof.get("role_tier", "")) != "LORD":
		return {"ok": false, "error_code": DtoSchemas.ERR_ROLE_PERMISSION, "reason": "Only LORD can ascend royal rank"}
	var fid: String = str(prof.get("faction_id", ""))
	if not factions.has(fid):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Lord has no faction"}

	var fac: Dictionary = factions[fid]
	var cur_rank: String = str(fac.get("royal_rank", "GOVERNOR_INSPECTOR"))
	var cur_idx: int = _royal_rank_index(cur_rank)
	if cur_idx >= ROYAL_RANKS_ORDERED.size() - 1:
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Already EMPEROR"}

	var next_rank: String = ROYAL_RANKS_ORDERED[cur_idx + 1]
	var req_var: Variant = ROYAL_RANK_REQS.get(next_rank, {})
	var req: Dictionary = req_var if req_var is Dictionary else {}
	var req_prestige: int = _to_int(req.get("prestige", 0), 0)
	var req_nodes: int = _to_int(req.get("min_nodes", 1), 1)

	var cur_prestige: int = _to_int(fac.get("prestige", 0), 0)
	if cur_prestige < req_prestige:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE,
			"reason": "Insufficient prestige",
			"required_prestige": req_prestige,
			"current_prestige": cur_prestige
		}

	if world_graph != null:
		var owned_nodes: int = count_faction_nodes(fid, world_graph)
		if owned_nodes < req_nodes:
			return {
				"ok": false,
				"error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE,
				"reason": "Insufficient owned nodes",
				"required_nodes": req_nodes,
				"owned_nodes": owned_nodes
			}

	fac["royal_rank"] = next_rank
	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"faction_id": fid,
		"old_rank": cur_rank,
		"new_rank": next_rank
	}


func to_dict() -> Dictionary:
	var fac_arr: Array[Dictionary] = []
	for fid: String in get_faction_ids():
		fac_arr.append(get_faction(fid))

	var ply_arr: Array[Dictionary] = []
	for pid: String in get_player_ids():
		ply_arr.append(get_player_profile(pid))

	var mis_arr: Array[Dictionary] = []
	for mid: String in get_mission_ids():
		var mv: Variant = missions[mid]
		if mv is Dictionary:
			var md: Dictionary = mv
			mis_arr.append(md.duplicate(true))

	var pids: Array[String] = []
	for k: Variant in proposals.keys():
		pids.append(str(k))
	pids.sort()
	var prop_arr: Array[Dictionary] = []
	for prid: String in pids:
		var pv: Variant = proposals[prid]
		if pv is Dictionary:
			var prd: Dictionary = pv
			prop_arr.append(prd.duplicate(true))

	return {
		"next_mission_seq": _next_mission_seq,
		"next_proposal_seq": _next_proposal_seq,
		"factions": fac_arr,
		"players": ply_arr,
		"missions": mis_arr,
		"proposals": prop_arr
	}


static func from_dict(data: Dictionary) -> FactionManager:
	var mgr: FactionManager = FactionManager.new()
	mgr._next_mission_seq = maxi(1, _to_int(data.get("next_mission_seq", 1), 1))
	mgr._next_proposal_seq = maxi(1, _to_int(data.get("next_proposal_seq", 1), 1))

	var fac_var: Variant = data.get("factions", [])
	if fac_var is Array:
		var fa: Array = fac_var
		for item: Variant in fa:
			if item is Dictionary:
				var fd: Dictionary = item
				var fid: String = str(fd.get("faction_id", ""))
				if fid.is_empty():
					continue
				var sl_var: Variant = fd.get("policy_sliders", {})
				var sld: Dictionary = sl_var if sl_var is Dictionary else {}
				mgr.factions[fid] = {
					"faction_id": fid,
					"name": str(fd.get("name", fid)),
					"lord_player_id": str(fd.get("lord_player_id", "")),
					"capital_node_id": str(fd.get("capital_node_id", "")),
					"treasury_grain": maxi(0, _to_int(fd.get("treasury_grain", 0), 0)),
					"treasury_coin": maxi(0, _to_int(fd.get("treasury_coin", 0), 0)),
					"prestige": maxi(0, _to_int(fd.get("prestige", 0), 0)),
					"royal_rank": str(fd.get("royal_rank", "GOVERNOR_INSPECTOR")),
					"oathbreaker_until_tick": maxi(0, _to_int(fd.get("oathbreaker_until_tick", 0), 0)),
					"diplomatic_trust_bp": clampi(_to_int(fd.get("diplomatic_trust_bp", 10000), 10000), 0, 10000),
					"policy_sliders": {
						"tax_rate_bp": clampi(_to_int(sld.get("tax_rate_bp", 1000), 1000), 500, 5000),
						"conscription_bp": clampi(_to_int(sld.get("conscription_bp", 1000), 1000), 0, 5000),
						"stipend_budget_bp": clampi(_to_int(sld.get("stipend_budget_bp", 10000), 10000), 0, 20000)
					}
				}

	var ply_var: Variant = data.get("players", [])
	if ply_var is Array:
		var pa: Array = ply_var
		for item: Variant in pa:
			if item is Dictionary:
				var pd: Dictionary = item
				var pid: String = str(pd.get("player_id", ""))
				if not pid.is_empty():
					var _reg: Dictionary = mgr.register_player(pid, pd)

	var mis_var: Variant = data.get("missions", [])
	if mis_var is Array:
		var ma: Array = mis_var
		for item: Variant in ma:
			if item is Dictionary:
				var md: Dictionary = item
				var mid: String = str(md.get("mission_id", ""))
				if not mid.is_empty():
					mgr.missions[mid] = md.duplicate(true)

	var prop_var: Variant = data.get("proposals", [])
	if prop_var is Array:
		var pra: Array = prop_var
		for item: Variant in pra:
			if item is Dictionary:
				var prd: Dictionary = item
				var prid: String = str(prd.get("proposal_id", ""))
				if not prid.is_empty():
					mgr.proposals[prid] = prd.duplicate(true)

	return mgr
