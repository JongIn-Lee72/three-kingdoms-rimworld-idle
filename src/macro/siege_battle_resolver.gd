class_name SiegeBattleResolver
extends RefCounted

const BASE_SIEGE_MERIT_POOL: int = 2000

var rallies: Dictionary = {}
var siege_history: Array[Dictionary] = []
var _next_rally_seq: int = 1


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
	rallies.clear()
	siege_history.clear()
	_next_rally_seq = 1


func get_rally_ids() -> Array[String]:
	var ids: Array[String] = []
	for k: Variant in rallies.keys():
		ids.append(str(k))
	ids.sort()
	return ids


func get_rally(rally_id: String) -> Dictionary:
	var v: Variant = rallies.get(rally_id, {})
	if v is Dictionary:
		var d: Dictionary = v
		return d.duplicate(true)
	return {}


func create_coalition_rally(
	leader_faction_id: String,
	target_node_id: String,
	leader_army: Dictionary,
	clock: SimClock = null
) -> Dictionary:
	if leader_faction_id.is_empty() or target_node_id.is_empty():
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Missing leader_faction_id or target_node_id"}

	var troops: int = maxi(0, _to_int(leader_army.get("troop_count", 0), 0))
	if troops <= 0:
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Leader army must have troop_count > 0"}

	var rid: String = "rally_%06d" % _next_rally_seq
	_next_rally_seq += 1

	var clean_army: Dictionary = leader_army.duplicate(true)
	clean_army["faction_id"] = leader_faction_id

	var rec: Dictionary = {
		"rally_id": rid,
		"leader_faction_id": leader_faction_id,
		"target_node_id": target_node_id,
		"created_tick": clock.current_tick_id if clock != null else 0,
		"status": "RALLYING",
		"participants": [clean_army]
	}
	rallies[rid] = rec
	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"rally_id": rid,
		"rally": rec.duplicate(true)
	}


func join_coalition_rally(
	rally_id: String,
	ally_army: Dictionary,
	diplomacy: DiplomacyTreatyEngine = null,
	clock: SimClock = null
) -> Dictionary:
	if not rallies.has(rally_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown rally_id"}
	var rally: Dictionary = rallies[rally_id]
	if str(rally.get("status", "")) != "RALLYING":
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Rally is not open"}

	var ally_fid: String = str(ally_army.get("faction_id", ""))
	var leader_fid: String = str(rally.get("leader_faction_id", ""))
	if ally_fid.is_empty():
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "ally_army missing faction_id"}

	var tick_id: int = clock.current_tick_id if clock != null else -1
	if ally_fid != leader_fid and diplomacy != null:
		if not diplomacy.are_allied(leader_fid, ally_fid, tick_id):
			return {"ok": false, "error_code": DtoSchemas.ERR_ROLE_PERMISSION, "reason": "Participant must be allied or same faction"}

	var troops: int = maxi(0, _to_int(ally_army.get("troop_count", 0), 0))
	if troops <= 0:
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Ally army must have troop_count > 0"}

	var parts_var: Variant = rally.get("participants", [])
	var parts: Array = parts_var if parts_var is Array else []
	parts.append(ally_army.duplicate(true))
	rally["participants"] = parts

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"rally_id": rally_id,
		"participant_count": parts.size()
	}


func _aggregate_coalition_army(
	participants: Array,
	social_service: SocialBanquetService
) -> Dictionary:
	var total_troops: int = 0
	var weighted_morale: int = 0
	var weighted_gear: int = 0
	var siege_engines: int = 0
	var all_officers: Array[Dictionary] = []
	var officer_ids: Array[String] = []
	var best_lead: Dictionary = {}
	var best_score: int = -1

	for p_item: Variant in participants:
		if not (p_item is Dictionary):
			continue
		var army: Dictionary = p_item
		var tc: int = maxi(0, _to_int(army.get("troop_count", 0), 0))
		if tc <= 0:
			continue
		total_troops += tc
		weighted_morale += clampi(_to_int(army.get("morale_bp", 8000), 8000), 0, 10000) * tc
		weighted_gear += clampi(_to_int(army.get("gear_pm", 1000), 1000), 700, 2000) * tc

		var comp_var: Variant = army.get("troop_composition", {})
		if comp_var is Dictionary:
			var comp: Dictionary = comp_var
			siege_engines += maxi(0, _to_int(comp.get("SIEGE_ENGINE", 0), 0))

		var off_var: Variant = army.get("officers", [])
		if off_var is Array:
			var oa: Array = off_var
			for o_item: Variant in oa:
				if o_item is Dictionary:
					var od: Dictionary = o_item
					all_officers.append(od.duplicate(true))
					var oid: String = str(od.get("pawn_id", od.get("officer_id", "")))
					if not oid.is_empty() and not officer_ids.has(oid):
						officer_ids.append(oid)
					var mar_v: int = _to_int(od.get("MAR", od.get("martial", 60)), 60)
					var lea_v: int = _to_int(od.get("LEA", od.get("leadership", 60)), 60)
					if mar_v + lea_v > best_score:
						best_score = mar_v + lea_v
						best_lead = od.duplicate(true)

	var avg_morale: int = 8000
	var avg_gear: int = 1000
	if total_troops > 0:
		@warning_ignore("integer_division")
		avg_morale = weighted_morale / total_troops
		@warning_ignore("integer_division")
		avg_gear = weighted_gear / total_troops

	var sibling_bonus_pm: int = 0
	if social_service != null:
		sibling_bonus_pm = social_service.get_joint_combat_bonus_pm(officer_ids)

	var unit_atk_pm: int = 1000 + sibling_bonus_pm
	var ordered_officers: Array[Dictionary] = []
	if not best_lead.is_empty():
		ordered_officers.append(best_lead)
	for od: Dictionary in all_officers:
		if ordered_officers.is_empty() or str(od.get("pawn_id", od.get("officer_id", ""))) != str(best_lead.get("pawn_id", best_lead.get("officer_id", ""))):
			ordered_officers.append(od)

	return {
		"troop_count": total_troops,
		"morale_bp": avg_morale,
		"gear_pm": avg_gear,
		"unit_atk_pm": unit_atk_pm,
		"siege_engine_count": siege_engines,
		"sibling_bonus_pm": sibling_bonus_pm,
		"officers": ordered_officers,
		"lead_officer": best_lead
	}


func resolve_coalition_siege(
	rally_id: String,
	target_node_id: String,
	defender_army: Dictionary,
	world_graph: WorldGraph,
	social_service: SocialBanquetService,
	clock: SimClock,
	world_seed: int,
	faction_mgr: FactionManager = null
) -> Dictionary:
	if not rallies.has(rally_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown rally_id"}
	if world_graph == null or not world_graph.has_node(target_node_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown target_node_id"}

	var rally: Dictionary = rallies[rally_id]
	if str(rally.get("status", "")) != "RALLYING":
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Rally already resolved"}

	var parts_var: Variant = rally.get("participants", [])
	var participants: Array = parts_var if parts_var is Array else []
	if participants.is_empty():
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Rally has no participants"}

	var tick_id: int = clock.current_tick_id if clock != null else 0
	var agg: Dictionary = _aggregate_coalition_army(participants, social_service)
	var total_atk_troops: int = _to_int(agg.get("troop_count", 0), 0)
	if total_atk_troops <= 0:
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Coalition has 0 troops"}

	var node_before: Dictionary = world_graph.get_node(target_node_id)
	var start_wall_hp: int = maxi(0, _to_int(node_before.get("fortification_hp", 0), 0))
	var old_owner_fid: String = str(node_before.get("owner_faction_id", "NEUTRAL"))

	# Phase 1: Wall Bombardment (SIEGE_ENGINE grants strong fortification damage bonus)
	var siege_cnt: int = _to_int(agg.get("siege_engine_count", 0), 0)
	@warning_ignore("integer_division")
	var base_bombard: int = (total_atk_troops / 2) + siege_cnt * 20
	var siege_mult_pm: int = 2500 if siege_cnt > 0 else 1000
	@warning_ignore("integer_division")
	var wall_damage: int = maxi(100, (base_bombard * siege_mult_pm) / 1000)
	var remaining_wall_hp: int = world_graph.damage_fortification(target_node_id, wall_damage)
	var wall_breached: bool = remaining_wall_hp == 0

	var phase1: Dictionary = {
		"initial_wall_hp": start_wall_hp,
		"siege_engine_count": siege_cnt,
		"wall_damage": wall_damage,
		"remaining_wall_hp": remaining_wall_hp,
		"wall_breached": wall_breached
	}

	# Phase 2: Gate Breach & 5-Bout Duel
	var lead_atk: Dictionary = {}
	var la_var: Variant = agg.get("lead_officer", {})
	if la_var is Dictionary:
		lead_atk = la_var
	var lead_def: Dictionary = BattleEngine._get_lead_officer(defender_army)
	var duel_res: Dictionary = BattleEngine.resolve_officer_duel(lead_atk, lead_def, world_seed, tick_id, 901)

	var atk_morale: int = clampi(
		_to_int(agg.get("morale_bp", 8000), 8000) + _to_int(duel_res.get("morale_swing_a_bp", 0), 0),
		0,
		10000
	)
	var def_morale: int = clampi(
		_to_int(defender_army.get("morale_bp", 8000), 8000) + _to_int(duel_res.get("morale_swing_b_bp", 0), 0),
		0,
		10000
	)

	var phase2: Dictionary = {
		"duel": duel_res,
		"attacker_morale_after_bp": atk_morale,
		"defender_morale_after_bp": def_morale
	}

	# Phase 3: Inner Keep Occupation (via BattleEngine.resolve_auto_battle)
	var atk_battle_army: Dictionary = {
		"troop_count": total_atk_troops,
		"morale_bp": atk_morale,
		"gear_pm": _to_int(agg.get("gear_pm", 1000), 1000),
		"unit_atk_pm": _to_int(agg.get("unit_atk_pm", 1000), 1000),
		"officers": agg.get("officers", [])
	}
	var def_battle_army: Dictionary = defender_army.duplicate(true)
	def_battle_army["morale_bp"] = def_morale
	def_battle_army["wall_hp"] = remaining_wall_hp

	var weather: String = "CLEAR"
	var battle_res: Dictionary = BattleEngine.resolve_auto_battle(
		atk_battle_army,
		def_battle_army,
		weather,
		"CITY",
		clock,
		world_seed
	)

	var attacker_won: bool = str(battle_res.get("winner", "B")) == "A"
	var leader_fid: String = str(rally.get("leader_faction_id", ""))
	if attacker_won:
		var _ok_flip: bool = world_graph.set_node_owner(target_node_id, leader_fid, "")
		rally["status"] = "VICTORY"
	else:
		rally["status"] = "DEFEAT"

	# Proportional war_merit distribution across coalition participants
	var merit_pool: int = BASE_SIEGE_MERIT_POOL if attacker_won else 400
	var merit_shares: Dictionary = {}
	var merit_rem: int = merit_pool

	for i: int in range(participants.size()):
		var p_item: Variant = participants[i]
		if not (p_item is Dictionary):
			continue
		var p_army: Dictionary = p_item
		var p_id: String = str(p_army.get("owner_player_id", p_army.get("player_id", p_army.get("faction_id", "part_%d" % i))))
		var p_troops: int = maxi(0, _to_int(p_army.get("troop_count", 0), 0))
		@warning_ignore("integer_division")
		var share: int = (merit_pool * p_troops) / maxi(1, total_atk_troops)
		if i == participants.size() - 1:
			share = merit_rem
		else:
			merit_rem = maxi(0, merit_rem - share)

		merit_shares[p_id] = _to_int(merit_shares.get(p_id, 0), 0) + share
		if faction_mgr != null and faction_mgr.has_player(p_id):
			var _pm: Dictionary = faction_mgr.award_merit_and_promote(p_id, share)

	var summary: Dictionary = {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"rally_id": rally_id,
		"target_node_id": target_node_id,
		"tick_id": tick_id,
		"attacker_won": attacker_won,
		"old_owner_faction_id": old_owner_fid,
		"new_owner_faction_id": leader_fid if attacker_won else old_owner_fid,
		"sibling_joint_bonus_pm": _to_int(agg.get("sibling_bonus_pm", 0), 0),
		"phase1_bombardment": phase1,
		"phase2_duel": phase2,
		"phase3_battle": battle_res,
		"merit_shares": merit_shares
	}
	siege_history.append(summary.duplicate(true))
	return summary


func resolve_supply_interdiction(
	raider_army: Dictionary,
	caravan: Dictionary,
	escort_army: Dictionary,
	clock: SimClock,
	world_seed: int
) -> Dictionary:
	if clock == null:
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Null clock"}

	var escort_troops: int = maxi(0, _to_int(escort_army.get("troop_count", 0), 0))
	var raider_won: bool = true
	var battle_res: Dictionary = {}

	if escort_troops > 0:
		battle_res = BattleEngine.resolve_auto_battle(
			raider_army,
			escort_army,
			"CLEAR",
			"HIGHWAY",
			clock,
			world_seed
		)
		raider_won = str(battle_res.get("winner", "B")) == "A"

	var looted_grain: int = 0
	var looted_coin: int = 0
	var escort_bounty_coin: int = 0
	var escort_bounty_merit: int = 0

	var c_grain: int = maxi(0, _to_int(caravan.get("carried_grain", 0), 0))
	var c_coin: int = maxi(0, _to_int(caravan.get("carried_coin", 0), 0))

	if raider_won:
		@warning_ignore("integer_division")
		looted_grain = (c_grain * 600) / 1000
		@warning_ignore("integer_division")
		looted_coin = (c_coin * 600) / 1000
		caravan["carried_grain"] = c_grain - looted_grain
		caravan["carried_coin"] = c_coin - looted_coin
		caravan["interdicted"] = true
	else:
		var raider_troops: int = maxi(100, _to_int(raider_army.get("troop_count", 100), 100))
		@warning_ignore("integer_division")
		escort_bounty_coin = maxi(100, raider_troops / 2)
		@warning_ignore("integer_division")
		escort_bounty_merit = maxi(150, raider_troops / 4)
		caravan["interdicted"] = false

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"tick_id": clock.current_tick_id,
		"raider_won": raider_won,
		"looted_grain": looted_grain,
		"looted_coin": looted_coin,
		"escort_bounty_coin": escort_bounty_coin,
		"escort_bounty_merit": escort_bounty_merit,
		"battle": battle_res
	}


func to_dict() -> Dictionary:
	var ral_arr: Array[Dictionary] = []
	for rid: String in get_rally_ids():
		ral_arr.append(get_rally(rid))

	var hist_copy: Array[Dictionary] = []
	for sh: Dictionary in siege_history:
		hist_copy.append(sh.duplicate(true))

	return {
		"next_rally_seq": _next_rally_seq,
		"rallies": ral_arr,
		"siege_history": hist_copy
	}


static func from_dict(data: Dictionary) -> SiegeBattleResolver:
	var res: SiegeBattleResolver = SiegeBattleResolver.new()
	res._next_rally_seq = maxi(1, _to_int(data.get("next_rally_seq", 1), 1))

	var ral_var: Variant = data.get("rallies", [])
	if ral_var is Array:
		var ra: Array = ral_var
		for item: Variant in ra:
			if item is Dictionary:
				var rd: Dictionary = item
				var rid: String = str(rd.get("rally_id", ""))
				if not rid.is_empty():
					res.rallies[rid] = rd.duplicate(true)

	var hist_var: Variant = data.get("siege_history", [])
	if hist_var is Array:
		var ha: Array = hist_var
		for item: Variant in ha:
			if item is Dictionary:
				var hd: Dictionary = item
				res.siege_history.append(hd.duplicate(true))

	return res
