class_name ChronicleInboxService
extends RefCounted

const CATEGORY_STIPEND: String = "STIPEND"
const CATEGORY_MISSION: String = "MISSION"
const CATEGORY_PAWN_EVENT: String = "PAWN_EVENT"
const CATEGORY_BATTLE_REPLAY: String = "BATTLE_REPLAY"
const CATEGORY_YIELD_SNAPSHOT: String = "YIELD_SNAPSHOT"

var offline_baselines: Dictionary = {}   # player_id -> {"tick": int, "resources": Dictionary}
var offline_logs: Dictionary = {}        # player_id -> Array[Dictionary]
var decisions: Dictionary = {}           # decision_id -> Dictionary
var _next_decision_seq: int = 1


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
	offline_baselines.clear()
	offline_logs.clear()
	decisions.clear()
	_next_decision_seq = 1


func mark_player_offline(player_id: String, tick_id: int, current_resources: Dictionary) -> void:
	if player_id.is_empty():
		return
	var res_copy: Dictionary = {}
	for rk: String in DtoSchemas.RESOURCE_KEYS:
		res_copy[rk] = maxi(0, _to_int(current_resources.get(rk, 0), 0))
	offline_baselines[player_id] = {
		"tick_id": maxi(0, tick_id),
		"resources": res_copy
	}
	if not offline_logs.has(player_id):
		var empty_arr: Array[Dictionary] = []
		offline_logs[player_id] = empty_arr


func record_offline_event(player_id: String, category: String, payload: Dictionary) -> void:
	if player_id.is_empty() or category.is_empty():
		return
	if not offline_logs.has(player_id):
		var empty_arr: Array[Dictionary] = []
		offline_logs[player_id] = empty_arr
	var logs_var: Variant = offline_logs[player_id]
	if logs_var is Array:
		var logs: Array = logs_var
		logs.append({
			"category": category,
			"payload": payload.duplicate(true)
		})


func build_reconnect_gazette(
	player_id: String,
	from_tick: int,
	to_tick: int,
	current_resources: Dictionary
) -> Dictionary:
	var resolved_from: int = maxi(0, from_tick)
	var resolved_to: int = maxi(resolved_from, to_tick)

	var base_res: Dictionary = {}
	if offline_baselines.has(player_id):
		var bv: Variant = offline_baselines[player_id]
		if bv is Dictionary:
			var bd: Dictionary = bv
			var br_v: Variant = bd.get("resources", {})
			if br_v is Dictionary:
				base_res = br_v

	var net_yields: Dictionary = {}
	for rk: String in DtoSchemas.RESOURCE_KEYS:
		var cur_v: int = maxi(0, _to_int(current_resources.get(rk, 0), 0))
		var base_v: int = maxi(0, _to_int(base_res.get(rk, cur_v), cur_v))
		var delta: int = cur_v - base_v
		if delta != 0:
			net_yields[rk] = delta

	var stipends_received: Dictionary = {"COIN": 0, "GRAIN": 0, "count": 0}
	var completed_missions: Array[Dictionary] = []
	var pawn_events: Array[Dictionary] = []
	var battle_replays: Array[Dictionary] = []

	var logs_var: Variant = offline_logs.get(player_id, [])
	if logs_var is Array:
		var logs: Array = logs_var
		for item: Variant in logs:
			if not (item is Dictionary):
				continue
			var entry: Dictionary = item
			var cat: String = str(entry.get("category", ""))
			var p_v: Variant = entry.get("payload", {})
			var pd: Dictionary = p_v if p_v is Dictionary else {}
			var ev_tick: int = _to_int(pd.get("tick_id", resolved_to), resolved_to)
			if ev_tick < resolved_from or ev_tick > resolved_to:
				continue
			match cat:
				CATEGORY_STIPEND:
					stipends_received["COIN"] = _to_int(stipends_received["COIN"], 0) + _to_int(pd.get("coin", 0), 0)
					stipends_received["GRAIN"] = _to_int(stipends_received["GRAIN"], 0) + _to_int(pd.get("grain", 0), 0)
					stipends_received["count"] = _to_int(stipends_received["count"], 0) + 1
				CATEGORY_MISSION:
					completed_missions.append(pd.duplicate(true))
				CATEGORY_PAWN_EVENT:
					pawn_events.append(pd.duplicate(true))
				CATEGORY_BATTLE_REPLAY:
					battle_replays.append(pd.duplicate(true))

	var digest: Dictionary = {
		"v": 1,
		"msg_type": DtoSchemas.MSG_OFFLINE_CHRONICLE_DIGEST,
		"player_id": player_id,
		"from_tick": resolved_from,
		"to_tick": resolved_to,
		"net_yields": net_yields,
		"stipends_received": stipends_received,
		"completed_missions": completed_missions,
		"pawn_events": pawn_events,
		"battle_replays": battle_replays
	}
	# Clear consumed offline buffer & update baseline after reconnect digest generation
	var empty_logs: Array[Dictionary] = []
	offline_logs[player_id] = empty_logs
	var _er: bool = offline_baselines.erase(player_id)
	return digest


func enqueue_decision(
	player_id: String,
	event_type: String,
	options: Array,
	default_option: String,
	deadline_tick: int,
	payload: Dictionary = {}
) -> Dictionary:
	if player_id.is_empty() or event_type.is_empty():
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Missing player_id or event_type"}
	var clean_opts: Array[String] = _extract_string_array(options)
	if clean_opts.is_empty():
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Decision options must be non-empty"}
	var resolved_default: String = default_option if clean_opts.has(default_option) else clean_opts[0]

	var did: String = "dec_%06d" % _next_decision_seq
	_next_decision_seq += 1
	var rec: Dictionary = {
		"decision_id": did,
		"player_id": player_id,
		"event_type": event_type,
		"options": clean_opts,
		"default_option": resolved_default,
		"deadline_tick": maxi(0, deadline_tick),
		"payload": payload.duplicate(true),
		"status": "PENDING",
		"chosen_option": "",
		"resolved_tick": -1,
		"resolution_mode": ""
	}
	decisions[did] = rec
	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"decision_id": did,
		"decision": rec.duplicate(true)
	}


func get_decision(decision_id: String) -> Dictionary:
	var v: Variant = decisions.get(decision_id, {})
	if v is Dictionary:
		var d: Dictionary = v
		return d.duplicate(true)
	return {}


func get_pending_decisions_for_player(player_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dids: Array[String] = []
	for k: Variant in decisions.keys():
		dids.append(str(k))
	dids.sort()
	for did: String in dids:
		var dv: Variant = decisions[did]
		if dv is Dictionary:
			var dd: Dictionary = dv
			if str(dd.get("player_id", "")) == player_id and str(dd.get("status", "")) == "PENDING":
				out.append(dd.duplicate(true))
	return out


func submit_decision(
	player_id: String,
	decision_id: String,
	chosen_option: String,
	tick_id: int
) -> Dictionary:
	if not decisions.has(decision_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown decision_id"}
	var dec: Dictionary = decisions[decision_id]
	if str(dec.get("player_id", "")) != player_id:
		return {"ok": false, "error_code": DtoSchemas.ERR_UNAUTHORIZED, "reason": "Decision belongs to another player"}
	if str(dec.get("status", "")) != "PENDING":
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Decision already resolved"}

	var opts: Array[String] = _extract_string_array(dec.get("options", []))
	if not opts.has(chosen_option):
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Invalid chosen_option: " + chosen_option}

	dec["status"] = "RESOLVED"
	dec["chosen_option"] = chosen_option
	dec["resolved_tick"] = maxi(0, tick_id)
	dec["resolution_mode"] = "PLAYER_CHOICE"

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"decision_id": decision_id,
		"chosen_option": chosen_option,
		"decision": dec.duplicate(true)
	}


func process_expired_decisions(tick_id: int) -> Array[Dictionary]:
	var expired_resolved: Array[Dictionary] = []
	var dids: Array[String] = []
	for k: Variant in decisions.keys():
		dids.append(str(k))
	dids.sort()
	for did: String in dids:
		var dec: Dictionary = decisions[did]
		if str(dec.get("status", "")) != "PENDING":
			continue
		var deadline: int = _to_int(dec.get("deadline_tick", 0), 0)
		if tick_id >= deadline:
			var fallback: String = str(dec.get("default_option", ""))
			dec["status"] = "EXPIRED_DEFAULT"
			dec["chosen_option"] = fallback
			dec["resolved_tick"] = maxi(0, tick_id)
			dec["resolution_mode"] = "TIMEOUT_FALLBACK"
			expired_resolved.append(dec.duplicate(true))
	return expired_resolved


func to_dict() -> Dictionary:
	var base_copy: Dictionary = {}
	var bkeys: Array[String] = []
	for k: Variant in offline_baselines.keys():
		bkeys.append(str(k))
	bkeys.sort()
	for bk: String in bkeys:
		var bv: Variant = offline_baselines[bk]
		if bv is Dictionary:
			var bd: Dictionary = bv
			base_copy[bk] = bd.duplicate(true)

	var logs_copy: Dictionary = {}
	var lkeys: Array[String] = []
	for k: Variant in offline_logs.keys():
		lkeys.append(str(k))
	lkeys.sort()
	for lk: String in lkeys:
		var lv: Variant = offline_logs[lk]
		if lv is Array:
			var la: Array = lv
			var arr_c: Array[Dictionary] = []
			for item: Variant in la:
				if item is Dictionary:
					var d: Dictionary = item
					arr_c.append(d.duplicate(true))
			logs_copy[lk] = arr_c

	var dec_arr: Array[Dictionary] = []
	var dkeys: Array[String] = []
	for k: Variant in decisions.keys():
		dkeys.append(str(k))
	dkeys.sort()
	for dk: String in dkeys:
		dec_arr.append(get_decision(dk))

	return {
		"next_decision_seq": _next_decision_seq,
		"offline_baselines": base_copy,
		"offline_logs": logs_copy,
		"decisions": dec_arr
	}


static func from_dict(data: Dictionary) -> ChronicleInboxService:
	var svc: ChronicleInboxService = ChronicleInboxService.new()
	svc._next_decision_seq = maxi(1, _to_int(data.get("next_decision_seq", 1), 1))

	var base_v: Variant = data.get("offline_baselines", {})
	if base_v is Dictionary:
		var bd: Dictionary = base_v
		for k: Variant in bd.keys():
			var item_v: Variant = bd[k]
			if item_v is Dictionary:
				var d: Dictionary = item_v
				svc.offline_baselines[str(k)] = d.duplicate(true)

	var logs_v: Variant = data.get("offline_logs", {})
	if logs_v is Dictionary:
		var ld: Dictionary = logs_v
		for k: Variant in ld.keys():
			var item_v: Variant = ld[k]
			if item_v is Array:
				var la: Array = item_v
				var arr_c: Array[Dictionary] = []
				for entry: Variant in la:
					if entry is Dictionary:
						var ed: Dictionary = entry
						arr_c.append(ed.duplicate(true))
				svc.offline_logs[str(k)] = arr_c

	var dec_v: Variant = data.get("decisions", [])
	if dec_v is Array:
		var da: Array = dec_v
		for item: Variant in da:
			if item is Dictionary:
				var dd: Dictionary = item
				var did: String = str(dd.get("decision_id", ""))
				if not did.is_empty():
					svc.decisions[did] = dd.duplicate(true)

	return svc
