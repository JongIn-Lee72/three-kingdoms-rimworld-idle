class_name DiplomacyTreatyEngine
extends RefCounted

const TREATY_TYPES: Array[String] = [
	"ALLIANCE",
	"NON_AGGRESSION",
	"TRIBUTE",
	"MILITARY_ACCESS"
]

const OATHBREAKER_DURATION_TICKS: int = 360  # 15 in-game days (15 * 24 ticks)
const OATHBREAKER_TRUST_PENALTY_BP: int = 2500
const OATHBREAKER_LOYALTY_PENALTY_BP: int = 1500

var treaties: Dictionary = {}
var diplomatic_trust_bp: Dictionary = {}
var oathbreaker_until_tick: Dictionary = {}
var chronicles: Array[Dictionary] = []
var _next_treaty_seq: int = 1


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
	treaties.clear()
	diplomatic_trust_bp.clear()
	oathbreaker_until_tick.clear()
	chronicles.clear()
	_next_treaty_seq = 1


func get_treaty_ids() -> Array[String]:
	var ids: Array[String] = []
	for k: Variant in treaties.keys():
		ids.append(str(k))
	ids.sort()
	return ids


func get_treaty(treaty_id: String) -> Dictionary:
	var v: Variant = treaties.get(treaty_id, {})
	if v is Dictionary:
		var d: Dictionary = v
		return d.duplicate(true)
	return {}


func get_faction_trust_bp(faction_id: String) -> int:
	return clampi(_to_int(diplomatic_trust_bp.get(faction_id, 10000), 10000), 0, 10000)


func is_oathbreaker(faction_id: String, tick_id: int) -> bool:
	return _to_int(oathbreaker_until_tick.get(faction_id, 0), 0) > tick_id


func propose_and_sign_treaty(
	faction_a_id: String,
	faction_b_id: String,
	treaty_type: String,
	duration_days: int,
	clock: SimClock,
	tribute_coin_per_day: int = 0,
	tribute_grain_per_day: int = 0
) -> Dictionary:
	if faction_a_id.is_empty() or faction_b_id.is_empty() or faction_a_id == faction_b_id:
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Invalid faction IDs"}
	if not TREATY_TYPES.has(treaty_type):
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Invalid treaty_type: " + treaty_type}
	if duration_days <= 0 or clock == null:
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "duration_days must be > 0 and clock required"}

	if not diplomatic_trust_bp.has(faction_a_id):
		diplomatic_trust_bp[faction_a_id] = 10000
	if not diplomatic_trust_bp.has(faction_b_id):
		diplomatic_trust_bp[faction_b_id] = 10000

	var tid: String = "treaty_%06d" % _next_treaty_seq
	_next_treaty_seq += 1

	var start_tick: int = clock.current_tick_id
	var expires_tick: int = start_tick + duration_days * SimClock.TICKS_PER_DAY
	var rec: Dictionary = {
		"treaty_id": tid,
		"faction_a_id": faction_a_id,
		"faction_b_id": faction_b_id,
		"treaty_type": treaty_type,
		"start_tick": start_tick,
		"expires_tick": expires_tick,
		"tribute_coin_per_day": maxi(0, tribute_coin_per_day),
		"tribute_grain_per_day": maxi(0, tribute_grain_per_day),
		"status": "ACTIVE",
		"broken_by_faction_id": ""
	}
	treaties[tid] = rec
	chronicles.append({
		"tick_id": start_tick,
		"event": "TREATY_SIGNED",
		"treaty_id": tid,
		"treaty_type": treaty_type,
		"faction_a_id": faction_a_id,
		"faction_b_id": faction_b_id
	})
	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"treaty_id": tid,
		"treaty": rec.duplicate(true)
	}


func _has_active_treaty_of_type(faction_a_id: String, faction_b_id: String, treaty_type: String, tick_id: int = -1) -> bool:
	for tid: String in get_treaty_ids():
		var tv: Variant = treaties[tid]
		if not (tv is Dictionary):
			continue
		var td: Dictionary = tv
		if str(td.get("status", "")) != "ACTIVE":
			continue
		if str(td.get("treaty_type", "")) != treaty_type:
			continue
		if tick_id >= 0 and _to_int(td.get("expires_tick", 0), 0) <= tick_id:
			continue
		var fa: String = str(td.get("faction_a_id", ""))
		var fb: String = str(td.get("faction_b_id", ""))
		if (fa == faction_a_id and fb == faction_b_id) or (fa == faction_b_id and fb == faction_a_id):
			return true
	return false


func are_allied(faction_a_id: String, faction_b_id: String, tick_id: int = -1) -> bool:
	if faction_a_id.is_empty() or faction_b_id.is_empty():
		return false
	if faction_a_id == faction_b_id:
		return true
	return _has_active_treaty_of_type(faction_a_id, faction_b_id, "ALLIANCE", tick_id)


func has_non_aggression(faction_a_id: String, faction_b_id: String, tick_id: int = -1) -> bool:
	if faction_a_id.is_empty() or faction_b_id.is_empty():
		return false
	if faction_a_id == faction_b_id:
		return true
	if _has_active_treaty_of_type(faction_a_id, faction_b_id, "ALLIANCE", tick_id):
		return true
	return _has_active_treaty_of_type(faction_a_id, faction_b_id, "NON_AGGRESSION", tick_id)


func settle_daily_treaties(faction_mgr: FactionManager, clock: SimClock) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if clock == null:
		return events

	var tick_id: int = clock.current_tick_id
	for tid: String in get_treaty_ids():
		var tv: Variant = treaties[tid]
		if not (tv is Dictionary):
			continue
		var td: Dictionary = tv
		if str(td.get("status", "")) != "ACTIVE":
			continue

		var exp_tick: int = _to_int(td.get("expires_tick", 0), 0)
		if tick_id >= exp_tick:
			td["status"] = "EXPIRED"
			events.append({
				"type": "TREATY_EXPIRED",
				"treaty_id": tid,
				"treaty_type": str(td.get("treaty_type", "")),
				"tick_id": tick_id
			})
			continue

		if str(td.get("treaty_type", "")) == "TRIBUTE" and faction_mgr != null:
			var payer_id: String = str(td.get("faction_a_id", ""))
			var receiver_id: String = str(td.get("faction_b_id", ""))
			var coin_amt: int = _to_int(td.get("tribute_coin_per_day", 0), 0)
			var grain_amt: int = _to_int(td.get("tribute_grain_per_day", 0), 0)
			if coin_amt > 0 or grain_amt > 0:
				var pay_res: Dictionary = faction_mgr.adjust_faction_treasury(payer_id, -coin_amt, -grain_amt, 0)
				if _to_bool(pay_res.get("ok", false), false):
					var _rec_res: Dictionary = faction_mgr.adjust_faction_treasury(receiver_id, coin_amt, grain_amt, 0)
					events.append({
						"type": "TRIBUTE_PAID",
						"treaty_id": tid,
						"payer_faction_id": payer_id,
						"receiver_faction_id": receiver_id,
						"coin": coin_amt,
						"grain": grain_amt,
						"tick_id": tick_id
					})
				else:
					events.append({
						"type": "TRIBUTE_DEFAULTED",
						"treaty_id": tid,
						"payer_faction_id": payer_id,
						"receiver_faction_id": receiver_id,
						"tick_id": tick_id
					})

	return events


func break_treaty(
	treaty_id: String,
	breaker_faction_id: String,
	faction_mgr: FactionManager,
	officer_pawns: Array = [],
	clock: SimClock = null
) -> Dictionary:
	if not treaties.has(treaty_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown treaty_id"}
	var td: Dictionary = treaties[treaty_id]
	if str(td.get("status", "")) != "ACTIVE":
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Treaty is not ACTIVE"}

	var fa: String = str(td.get("faction_a_id", ""))
	var fb: String = str(td.get("faction_b_id", ""))
	if breaker_faction_id != fa and breaker_faction_id != fb:
		return {"ok": false, "error_code": DtoSchemas.ERR_ROLE_PERMISSION, "reason": "Faction is not party to treaty"}

	var tick_id: int = clock.current_tick_id if clock != null else 0
	td["status"] = "BROKEN"
	td["broken_by_faction_id"] = breaker_faction_id

	var until_tick: int = tick_id + OATHBREAKER_DURATION_TICKS
	oathbreaker_until_tick[breaker_faction_id] = until_tick

	var cur_trust: int = get_faction_trust_bp(breaker_faction_id)
	var new_trust: int = maxi(0, cur_trust - OATHBREAKER_TRUST_PENALTY_BP)
	diplomatic_trust_bp[breaker_faction_id] = new_trust

	var member_ids: Array[String] = []
	if faction_mgr != null:
		if faction_mgr.has_faction(breaker_faction_id):
			var fac: Dictionary = faction_mgr.factions[breaker_faction_id]
			fac["oathbreaker_until_tick"] = until_tick
			fac["diplomatic_trust_bp"] = new_trust
		member_ids = faction_mgr.get_faction_members(breaker_faction_id)

	var affected_officers: Array[String] = []
	for p_item: Variant in officer_pawns:
		if p_item is PawnEntity:
			var pawn: PawnEntity = p_item
			var in_breaker: bool = member_ids.is_empty() or member_ids.has(pawn.owner_player_id) or member_ids.has(pawn.pawn_id)
			if not in_breaker:
				continue
			if pawn.has_trait("T_CHIVALROUS") or pawn.has_trait("T_UNSELFISH"):
				pawn.add_need("LOYALTY", -OATHBREAKER_LOYALTY_PENALTY_BP)
				pawn.add_thought("LORD_OATHBREAKER", -15, OATHBREAKER_DURATION_TICKS)
				affected_officers.append(pawn.pawn_id)

	chronicles.append({
		"tick_id": tick_id,
		"event": "TREATY_BROKEN_OATHBREAKER",
		"treaty_id": treaty_id,
		"breaker_faction_id": breaker_faction_id,
		"oathbreaker_until_tick": until_tick
	})

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"treaty_id": treaty_id,
		"breaker_faction_id": breaker_faction_id,
		"oathbreaker_until_tick": until_tick,
		"diplomatic_trust_bp": new_trust,
		"affected_officers": affected_officers
	}


func fund_regional_insurgency(
	sponsor_faction_id: String,
	target_node_id: String,
	coin_amount: int,
	faction_mgr: FactionManager,
	world_graph: WorldGraph
) -> Dictionary:
	if coin_amount <= 0:
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "coin_amount must be > 0"}
	if faction_mgr == null or world_graph == null:
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Null manager or graph"}
	if not faction_mgr.has_faction(sponsor_faction_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown sponsor faction"}
	if not world_graph.has_node(target_node_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown target node"}

	var spend_res: Dictionary = faction_mgr.adjust_faction_treasury(sponsor_faction_id, -coin_amount, 0, 0)
	if not _to_bool(spend_res.get("ok", false), false):
		return spend_res

	var nd_ref: Dictionary = world_graph.nodes[target_node_id]
	@warning_ignore("integer_division")
	var bandit_gain_bp: int = clampi((coin_amount * 3) / 2, 100, 4000)
	@warning_ignore("integer_division")
	var sec_loss_bp: int = clampi(coin_amount, 100, 3500)

	var cur_bandit: int = _to_int(nd_ref.get("bandit_pressure_bp", 200), 200)
	var new_bandit: int = clampi(cur_bandit + bandit_gain_bp, 0, 10000)
	nd_ref["bandit_pressure_bp"] = new_bandit
	var new_sec: int = world_graph.adjust_node_security(target_node_id, -sec_loss_bp)

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"sponsor_faction_id": sponsor_faction_id,
		"target_node_id": target_node_id,
		"coin_spent": coin_amount,
		"bandit_pressure_bp": new_bandit,
		"security_bp": new_sec
	}


static func get_season_modifiers(season: String) -> Dictionary:
	match season:
		"SPRING":
			return {
				"season": "SPRING",
				"farming_pm": 1200,
				"march_speed_pm": 1000,
				"supply_drain_pm": 1000
			}
		"SUMMER":
			return {
				"season": "SUMMER",
				"farming_pm": 1000,
				"march_speed_pm": 950,
				"supply_drain_pm": 1150
			}
		"AUTUMN":
			return {
				"season": "AUTUMN",
				"farming_pm": 1500,
				"march_speed_pm": 1100,
				"supply_drain_pm": 900
			}
		"WINTER":
			return {
				"season": "WINTER",
				"farming_pm": 200,
				"march_speed_pm": 750,
				"supply_drain_pm": 2000
			}
		_:
			return {
				"season": "SPRING",
				"farming_pm": 1000,
				"march_speed_pm": 1000,
				"supply_drain_pm": 1000
			}


func to_dict() -> Dictionary:
	var tr_arr: Array[Dictionary] = []
	for tid: String in get_treaty_ids():
		tr_arr.append(get_treaty(tid))

	var trust_copy: Dictionary = {}
	var tkeys: Array[String] = []
	for k: Variant in diplomatic_trust_bp.keys():
		tkeys.append(str(k))
	tkeys.sort()
	for tk: String in tkeys:
		trust_copy[tk] = get_faction_trust_bp(tk)

	var ob_copy: Dictionary = {}
	var okeys: Array[String] = []
	for k: Variant in oathbreaker_until_tick.keys():
		okeys.append(str(k))
	okeys.sort()
	for ok: String in okeys:
		ob_copy[ok] = maxi(0, _to_int(oathbreaker_until_tick[ok], 0))

	var ch_copy: Array[Dictionary] = []
	for ch: Dictionary in chronicles:
		ch_copy.append(ch.duplicate(true))

	return {
		"next_treaty_seq": _next_treaty_seq,
		"treaties": tr_arr,
		"diplomatic_trust_bp": trust_copy,
		"oathbreaker_until_tick": ob_copy,
		"chronicles": ch_copy
	}


static func from_dict(data: Dictionary) -> DiplomacyTreatyEngine:
	var eng: DiplomacyTreatyEngine = DiplomacyTreatyEngine.new()
	eng._next_treaty_seq = maxi(1, _to_int(data.get("next_treaty_seq", 1), 1))

	var tr_var: Variant = data.get("treaties", [])
	if tr_var is Array:
		var ta: Array = tr_var
		for item: Variant in ta:
			if item is Dictionary:
				var td: Dictionary = item
				var tid: String = str(td.get("treaty_id", ""))
				if not tid.is_empty():
					eng.treaties[tid] = td.duplicate(true)

	var dt_var: Variant = data.get("diplomatic_trust_bp", {})
	if dt_var is Dictionary:
		var dtd: Dictionary = dt_var
		for k: Variant in dtd.keys():
			eng.diplomatic_trust_bp[str(k)] = clampi(_to_int(dtd[k], 10000), 0, 10000)

	var ob_var: Variant = data.get("oathbreaker_until_tick", {})
	if ob_var is Dictionary:
		var obd: Dictionary = ob_var
		for k: Variant in obd.keys():
			eng.oathbreaker_until_tick[str(k)] = maxi(0, _to_int(obd[k], 0))

	var ch_var: Variant = data.get("chronicles", [])
	if ch_var is Array:
		var ca: Array = ch_var
		for item: Variant in ca:
			if item is Dictionary:
				var cd: Dictionary = item
				eng.chronicles.append(cd.duplicate(true))

	return eng
