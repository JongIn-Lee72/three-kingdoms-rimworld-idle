class_name EspionageService
extends RefCounted

const TURNCOAT_LOYALTY_THRESHOLD_BP: int = 4000
const POACH_LOYALTY_THRESHOLD_BP: int = 6000
const UPRISING_MIN_TROOPS: int = 2000
const UPRISING_COIN_COST: int = 5000
const TURNCOAT_MORALE_SHOCK_BP: int = -3000

var operations_log: Array[Dictionary] = []
var turncoat_pacts: Dictionary = {}
var _next_op_seq: int = 1


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


static func _extract_string_array(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		var arr: Array = raw
		for item: Variant in arr:
			var s: String = str(item)
			if not s.is_empty():
				out.append(s)
	return out


func _init() -> void:
	operations_log.clear()
	turncoat_pacts.clear()
	_next_op_seq = 1


func _record_op(op_type: String, tick_id: int, details: Dictionary) -> void:
	var rec: Dictionary = {
		"op_id": _next_op_seq,
		"op_type": op_type,
		"tick_id": tick_id,
		"details": details.duplicate(true)
	}
	_next_op_seq += 1
	operations_log.append(rec)


func execute_sow_discord(
	agent_pawn: PawnEntity,
	target_pawn: PawnEntity,
	clock: SimClock,
	world_seed: int
) -> Dictionary:
	if agent_pawn == null or target_pawn == null or clock == null:
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Null pawn or clock"}

	var tick_id: int = clock.current_tick_id
	if target_pawn.immune_to_bribery() or target_pawn.has_trait("T_UNSELFISH"):
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "Target has T_UNSELFISH and is immune to discord/bribery",
			"blocked_by": "T_UNSELFISH"
		}
	if target_pawn.offline_bribe_immune_until_tick > tick_id:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "Target is under offline bribe immunity",
			"blocked_by": "OFFLINE_IMMUNITY",
			"immune_until_tick": target_pawn.offline_bribe_immune_until_tick
		}

	var agent_int: int = agent_pawn.get_effective_stat("INT")
	var agent_cha: int = agent_pawn.get_effective_stat("CHA")
	var target_int: int = target_pawn.get_effective_stat("INT")

	var success_bp: int = clampi(5000 + (agent_int - target_int) * 200, 1500, 9500)
	var pair_hash: int = StateHasher.crc32_bytes((agent_pawn.pawn_id + ":" + target_pawn.pawn_id).to_utf8_buffer())
	var roll_bp: int = DeterministicRNG.roll_bp(world_seed, tick_id, pair_hash, 7101)
	var succeeded: bool = roll_bp < success_bp

	var loyalty_drop: int = 0
	if succeeded:
		loyalty_drop = maxi(250, (agent_int + agent_cha - target_int) * 12)
		target_pawn.add_need("LOYALTY", -loyalty_drop)
		target_pawn.add_thought("DISCORD_SUSPICION", -6, 24)

	var res: Dictionary = {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"succeeded": succeeded,
		"success_bp": success_bp,
		"roll_bp": roll_bp,
		"loyalty_drop": loyalty_drop,
		"target_loyalty_bp": target_pawn.get_need("LOYALTY")
	}
	_record_op("SOW_DISCORD", tick_id, res)
	return res


func execute_poach_retainer(
	agent_pawn: PawnEntity,
	target_pawn: PawnEntity,
	offer_coin: int,
	target_faction_mgr: FactionManager,
	clock: SimClock,
	world_seed: int,
	source_manor: ManorState = null,
	dest_manor: ManorState = null
) -> Dictionary:
	if agent_pawn == null or target_pawn == null or clock == null:
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Null pawn or clock"}
	if offer_coin < 0:
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "offer_coin must be >= 0"}

	var tick_id: int = clock.current_tick_id
	if target_pawn.immune_to_bribery() or target_pawn.has_trait("T_UNSELFISH"):
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "Target has T_UNSELFISH and is immune to bribery",
			"blocked_by": "T_UNSELFISH"
		}
	if target_pawn.offline_bribe_immune_until_tick > tick_id:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "Target is under offline bribe immunity",
			"blocked_by": "OFFLINE_IMMUNITY"
		}

	var cur_loyalty: int = target_pawn.get_need("LOYALTY")
	if cur_loyalty >= POACH_LOYALTY_THRESHOLD_BP:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "Target loyalty must be < 6000 bp to poach",
			"target_loyalty_bp": cur_loyalty
		}

	if dest_manor != null and dest_manor.get_resource("COIN") < offer_coin:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE,
			"reason": "Insufficient coin in destination manor"
		}

	var agent_cha: int = agent_pawn.get_effective_stat("CHA")
	var target_cha: int = target_pawn.get_effective_stat("CHA")
	@warning_ignore("integer_division")
	var bribe_bonus_bp: int = mini(3000, offer_coin / 2)
	if target_pawn.has_trait("T_GREEDY"):
		bribe_bonus_bp += 1500

	var success_bp: int = clampi(
		(POACH_LOYALTY_THRESHOLD_BP - cur_loyalty) + 25 * (agent_cha - target_cha) + bribe_bonus_bp,
		500,
		9000
	)
	var pair_hash: int = StateHasher.crc32_bytes((agent_pawn.pawn_id + ":" + target_pawn.pawn_id).to_utf8_buffer())
	var roll_bp: int = DeterministicRNG.roll_bp(world_seed, tick_id, pair_hash, 7201)
	var succeeded: bool = roll_bp < success_bp

	if dest_manor != null and offer_coin > 0:
		var _spent: bool = dest_manor.try_spend_resource("COIN", offer_coin)

	var new_owner: String = agent_pawn.owner_player_id
	if succeeded:
		if source_manor != null:
			var kept: Array[PawnEntity] = []
			for p: PawnEntity in source_manor.pawns:
				if p.pawn_id != target_pawn.pawn_id:
					kept.append(p)
			source_manor.pawns = kept

		if dest_manor != null:
			var _added: bool = dest_manor.add_pawn(target_pawn)
			new_owner = dest_manor.player_id
		else:
			target_pawn.owner_player_id = new_owner

		target_pawn.set_need("LOYALTY", 7000)
		target_pawn.add_thought("POACHED_NEW_LIEGE", 10, 24)

		if target_faction_mgr != null:
			var old_pid: String = target_pawn.pawn_id
			var agent_faction: String = ""
			if target_faction_mgr.has_player(new_owner):
				agent_faction = str(target_faction_mgr.get_player_profile(new_owner).get("faction_id", ""))
			if target_faction_mgr.has_player(old_pid) and not agent_faction.is_empty():
				var prof: Dictionary = target_faction_mgr.players[old_pid]
				prof["faction_id"] = agent_faction
				if str(prof.get("role_tier", "")) == "FREE_OFFICER":
					prof["role_tier"] = "FACTION_OFFICER"
					prof["court_rank"] = "RANK_9"

	var res: Dictionary = {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"succeeded": succeeded,
		"success_bp": success_bp,
		"roll_bp": roll_bp,
		"new_owner_player_id": new_owner if succeeded else target_pawn.owner_player_id,
		"target_pawn_id": target_pawn.pawn_id
	}
	_record_op("POACH_RETAINER", tick_id, res)
	return res


func register_turncoat_pact(officer_id: String, sponsor_faction_id: String, tick_id: int = 0) -> Dictionary:
	if officer_id.is_empty() or sponsor_faction_id.is_empty():
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Missing officer_id or sponsor_faction_id"}
	turncoat_pacts[officer_id] = {
		"officer_id": officer_id,
		"sponsor_faction_id": sponsor_faction_id,
		"created_tick": tick_id
	}
	return {"ok": true, "error_code": DtoSchemas.ERR_OK, "officer_id": officer_id, "sponsor_faction_id": sponsor_faction_id}


func resign_from_faction(
	player_id: String,
	faction_mgr: FactionManager,
	world_graph: WorldGraph = null
) -> Dictionary:
	if player_id.is_empty() or faction_mgr == null or not faction_mgr.has_player(player_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown player or FactionManager"}

	var prof: Dictionary = faction_mgr.players[player_id]
	var old_faction_id: String = str(prof.get("faction_id", ""))
	if old_faction_id.is_empty() or str(prof.get("role_tier", "")) == "FREE_OFFICER":
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Player is already a FREE_OFFICER"}

	var old_rank: String = str(prof.get("court_rank", "NONE"))
	if str(prof.get("role_tier", "")) == "LORD":
		return {"ok": false, "error_code": DtoSchemas.ERR_ROLE_PERMISSION, "reason": "Lord cannot resign directly without abdication"}

	if world_graph != null:
		var gov_nodes: Array[String] = _extract_string_array(prof.get("governed_node_ids", []))
		for nid: String in gov_nodes:
			if world_graph.has_node(nid):
				var nd: Dictionary = world_graph.get_node(nid)
				if str(nd.get("governor_player_id", "")) == player_id:
					var _ok_clr: bool = world_graph.set_node_owner(nid, str(nd.get("owner_faction_id", old_faction_id)), "")

	prof["role_tier"] = "FREE_OFFICER"
	prof["faction_id"] = ""
	prof["court_rank"] = "NONE"
	var empty_nodes: Array[String] = []
	prof["governed_node_ids"] = empty_nodes
	prof["viceroy_node_ids"] = empty_nodes.duplicate()
	prof["is_viceroy"] = false

	var res: Dictionary = {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"player_id": player_id,
		"old_faction_id": old_faction_id,
		"old_court_rank": old_rank,
		"role_tier": "FREE_OFFICER"
	}
	_record_op("RESIGN", 0, res)
	return res


func trigger_battlefield_turncoat(
	officer_pawn: PawnEntity,
	battle_ctx: Dictionary
) -> Dictionary:
	if officer_pawn == null:
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Null officer_pawn"}
	if officer_pawn.has_trait("T_UNSELFISH"):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "T_UNSELFISH officer refuses turncoat"}

	var loyalty_bp: int = officer_pawn.get_need("LOYALTY")
	if loyalty_bp >= TURNCOAT_LOYALTY_THRESHOLD_BP:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "Loyalty must be < 4000 bp for battlefield turncoat",
			"loyalty_bp": loyalty_bp
		}

	var cur_morale: int = _to_int(battle_ctx.get("defender_morale_bp", battle_ctx.get("morale_bp", 7500)), 7500)
	var new_morale: int = clampi(cur_morale + TURNCOAT_MORALE_SHOCK_BP, 0, 10000)
	if battle_ctx.has("defender_morale_bp"):
		battle_ctx["defender_morale_bp"] = new_morale
	else:
		battle_ctx["morale_bp"] = new_morale

	var defect_troops: int = maxi(0, _to_int(battle_ctx.get("officer_troops", 0), 0))
	if defect_troops > 0 and battle_ctx.has("defender_troops"):
		var d_troops: int = _to_int(battle_ctx.get("defender_troops", 0), 0)
		var transferred: int = mini(d_troops, defect_troops)
		battle_ctx["defender_troops"] = d_troops - transferred
		battle_ctx["attacker_troops"] = _to_int(battle_ctx.get("attacker_troops", 0), 0) + transferred

	battle_ctx["turncoat_triggered"] = true
	battle_ctx["turncoat_officer_id"] = officer_pawn.pawn_id
	battle_ctx["morale_shock_bp"] = TURNCOAT_MORALE_SHOCK_BP

	var new_fid: String = str(battle_ctx.get("sponsor_faction_id", ""))
	if new_fid.is_empty() and turncoat_pacts.has(officer_pawn.pawn_id):
		var pact_v: Variant = turncoat_pacts[officer_pawn.pawn_id]
		if pact_v is Dictionary:
			var pact: Dictionary = pact_v
			new_fid = str(pact.get("sponsor_faction_id", ""))

	var new_owner: String = str(battle_ctx.get("new_owner_player_id", ""))
	if not new_owner.is_empty():
		officer_pawn.owner_player_id = new_owner
	officer_pawn.set_need("LOYALTY", 6000)
	officer_pawn.add_thought("TURNCOAT_STIGMA", -10, 168)

	var res: Dictionary = {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"officer_id": officer_pawn.pawn_id,
		"morale_shock_bp": TURNCOAT_MORALE_SHOCK_BP,
		"new_morale_bp": new_morale,
		"sponsor_faction_id": new_fid,
		"stigma_ticks": 168
	}
	_record_op("BATTLEFIELD_TURNCOAT", _to_int(battle_ctx.get("tick_id", 0), 0), res)
	return res


func declare_governor_rebellion(
	governor_id: String,
	node_id: String,
	new_faction_id: String,
	faction_mgr: FactionManager,
	world_graph: WorldGraph,
	new_faction_name: String = ""
) -> Dictionary:
	if governor_id.is_empty() or node_id.is_empty() or new_faction_id.is_empty():
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Missing rebellion parameters"}
	if faction_mgr == null or world_graph == null:
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Null manager or graph"}
	if not faction_mgr.has_player(governor_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown governor_id"}
	if not world_graph.has_node(node_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown node_id"}
	if faction_mgr.has_faction(new_faction_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Target faction_id already exists"}

	var prof: Dictionary = faction_mgr.players[governor_id]
	var old_fid: String = str(prof.get("faction_id", ""))
	var nd: Dictionary = world_graph.get_node(node_id)
	var gov_nodes: Array[String] = _extract_string_array(prof.get("governed_node_ids", []))
	var governs_node: bool = str(nd.get("governor_player_id", "")) == governor_id or gov_nodes.has(node_id)
	if not governs_node:
		return {"ok": false, "error_code": DtoSchemas.ERR_ROLE_PERMISSION, "reason": "Player does not govern target node"}

	var tier: int = FactionManager._rank_tier(str(prof.get("court_rank", "NONE")))
	if tier < FactionManager._rank_tier("RANK_5"):
		return {"ok": false, "error_code": DtoSchemas.ERR_ROLE_PERMISSION, "reason": "Governor rebellion requires RANK_5+"}

	var resolved_name: String = new_faction_name if not new_faction_name.is_empty() else (new_faction_id + "_rebellion")
	var create_res: Dictionary = faction_mgr.create_faction(
		new_faction_id,
		resolved_name,
		governor_id,
		node_id,
		world_graph,
		2500,
		2500,
		"GOVERNOR_INSPECTOR"
	)
	if not _to_bool(create_res.get("ok", false), false):
		return create_res

	var flipped_nodes: Array[String] = [node_id]
	for g_nid: String in gov_nodes:
		if g_nid != node_id and world_graph.has_node(g_nid):
			var g_nd: Dictionary = world_graph.get_node(g_nid)
			if str(g_nd.get("owner_faction_id", "")) == old_fid:
				var _ok_f: bool = world_graph.set_node_owner(g_nid, new_faction_id, "")
				flipped_nodes.append(g_nid)

	var updated_prof: Dictionary = faction_mgr.players[governor_id]
	updated_prof["governed_node_ids"] = flipped_nodes

	var res: Dictionary = {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"governor_id": governor_id,
		"old_faction_id": old_fid,
		"new_faction_id": new_faction_id,
		"flipped_nodes": flipped_nodes
	}
	_record_op("GOVERNOR_REBELLION", 0, res)
	return res


func raise_free_officer_uprising(
	player_id: String,
	manor: ManorState,
	node_id: String,
	new_faction_id: String,
	faction_mgr: FactionManager,
	world_graph: WorldGraph,
	new_faction_name: String = ""
) -> Dictionary:
	if player_id.is_empty() or node_id.is_empty() or new_faction_id.is_empty():
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Missing uprising parameters"}
	if manor == null or faction_mgr == null or world_graph == null:
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Null manor/faction_mgr/world_graph"}
	if not world_graph.has_node(node_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown node_id"}
	if faction_mgr.has_faction(new_faction_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Faction already exists"}

	if not faction_mgr.has_player(player_id):
		var _reg: Dictionary = faction_mgr.register_player(player_id)
	var prof: Dictionary = faction_mgr.players[player_id]
	if str(prof.get("role_tier", "FREE_OFFICER")) != "FREE_OFFICER":
		return {"ok": false, "error_code": DtoSchemas.ERR_ROLE_PERMISSION, "reason": "Only FREE_OFFICER can raise free uprising"}

	if manor.household_troops < UPRISING_MIN_TROOPS:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE,
			"reason": "Requires household_troops >= 2000",
			"current_troops": manor.household_troops
		}
	if manor.get_resource("COIN") < UPRISING_COIN_COST:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE,
			"reason": "Requires COIN >= 5000",
			"current_coin": manor.get_resource("COIN")
		}

	var nd: Dictionary = world_graph.get_node(node_id)
	var cur_owner: String = str(nd.get("owner_faction_id", "NEUTRAL"))
	if cur_owner != "NEUTRAL" and cur_owner != "YELLOW_TURBAN" and not cur_owner.is_empty():
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "Node must be NEUTRAL or YELLOW_TURBAN for free officer uprising",
			"current_owner": cur_owner
		}

	# Atomic deduction + faction creation
	var spent: bool = manor.try_spend_resource("COIN", UPRISING_COIN_COST)
	if not spent:
		return {"ok": false, "error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE, "reason": "Failed to spend 5000 COIN"}

	var resolved_name: String = new_faction_name if not new_faction_name.is_empty() else (player_id + "_banner")
	var create_res: Dictionary = faction_mgr.create_faction(
		new_faction_id,
		resolved_name,
		player_id,
		node_id,
		world_graph,
		manor.get_resource("GRAIN"),
		UPRISING_COIN_COST,
		"GOVERNOR_INSPECTOR"
	)
	if not _to_bool(create_res.get("ok", false), false):
		var _refund: int = manor.add_resource("COIN", UPRISING_COIN_COST)
		return create_res

	var res: Dictionary = {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"player_id": player_id,
		"new_faction_id": new_faction_id,
		"capital_node_id": node_id,
		"coin_spent": UPRISING_COIN_COST,
		"remaining_manor_coin": manor.get_resource("COIN")
	}
	_record_op("FREE_OFFICER_UPRISING", 0, res)
	return res


func to_dict() -> Dictionary:
	var logs_copy: Array[Dictionary] = []
	for op: Dictionary in operations_log:
		logs_copy.append(op.duplicate(true))

	var pacts_copy: Dictionary = {}
	var pkeys: Array[String] = []
	for k: Variant in turncoat_pacts.keys():
		pkeys.append(str(k))
	pkeys.sort()
	for pk: String in pkeys:
		var pv: Variant = turncoat_pacts[pk]
		if pv is Dictionary:
			var pd: Dictionary = pv
			pacts_copy[pk] = pd.duplicate(true)

	return {
		"next_op_seq": _next_op_seq,
		"operations_log": logs_copy,
		"turncoat_pacts": pacts_copy
	}


static func from_dict(data: Dictionary) -> EspionageService:
	var svc: EspionageService = EspionageService.new()
	svc._next_op_seq = maxi(1, _to_int(data.get("next_op_seq", 1), 1))

	var log_var: Variant = data.get("operations_log", [])
	if log_var is Array:
		var la: Array = log_var
		for item: Variant in la:
			if item is Dictionary:
				var ld: Dictionary = item
				svc.operations_log.append(ld.duplicate(true))

	var pacts_var: Variant = data.get("turncoat_pacts", {})
	if pacts_var is Dictionary:
		var pd: Dictionary = pacts_var
		for k: Variant in pd.keys():
			var pv: Variant = pd[k]
			if pv is Dictionary:
				var pact_d: Dictionary = pv
				svc.turncoat_pacts[str(k)] = pact_d.duplicate(true)

	return svc
