class_name SimEventBus
extends RefCounted

const EVENT_MICRO_TO_MACRO_EXPEDITION_DISPATCHED: String = "MICRO_TO_MACRO_EXPEDITION_DISPATCHED"
const EVENT_MACRO_TO_MICRO_RAID_INCOMING: String = "MACRO_TO_MICRO_RAID_INCOMING"
const EVENT_CARAVAN_ARRIVED: String = "CARAVAN_ARRIVED"
const EVENT_TAX_COLLECTED: String = "TAX_COLLECTED"
const EVENT_STIPEND_DISTRIBUTED: String = "STIPEND_DISTRIBUTED"
const EVENT_SEASON_CHANGED: String = "SEASON_CHANGED"

var _next_seq_id: int = 1
var _queue: Array[Dictionary] = []
var _subscribers: Dictionary = {}


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


func subscribe(event_type: String, callback: Callable) -> void:
	if event_type.is_empty() or not callback.is_valid():
		return
	var list: Array = []
	var existing_var: Variant = _subscribers.get(event_type, null)
	if existing_var is Array:
		list = existing_var
	for existing: Variant in list:
		if existing is Callable:
			var cb: Callable = existing
			if cb == callback:
				return
	list.append(callback)
	_subscribers[event_type] = list


func unsubscribe(event_type: String, callback: Callable) -> void:
	if not _subscribers.has(event_type):
		return
	var existing_var: Variant = _subscribers[event_type]
	if not (existing_var is Array):
		return
	var list: Array = existing_var
	var kept: Array = []
	for existing: Variant in list:
		if existing is Callable:
			var cb: Callable = existing
			if cb == callback:
				continue
		kept.append(existing)
	if kept.is_empty():
		var _erased: bool = _subscribers.erase(event_type)
	else:
		_subscribers[event_type] = kept


func emit(event_type: String, payload: Dictionary, tick_id: int = -1) -> int:
	var resolved_tick: int = tick_id
	if resolved_tick < 0:
		resolved_tick = maxi(0, _to_int(payload.get("tick_id", 0), 0))
	var seq_id: int = _next_seq_id
	_next_seq_id += 1
	var record: Dictionary = {
		"seq_id": seq_id,
		"event": event_type,
		"tick_id": resolved_tick,
		"payload": payload.duplicate(true)
	}
	_queue.append(record)
	return seq_id


func peek_pending_count() -> int:
	return _queue.size()


func clear() -> void:
	_queue.clear()


func drain_for_tick(tick_id: int) -> Array[Dictionary]:
	var batch: Array[Dictionary] = []
	var remaining: Array[Dictionary] = []
	for ev: Dictionary in _queue:
		if _to_int(ev.get("tick_id", 0), 0) <= tick_id:
			batch.append(ev)
		else:
			remaining.append(ev)
	_queue = remaining
	batch.sort_custom(Callable(SimEventBus, "_compare_events"))
	_dispatch_batch(batch)
	return batch


func drain_all() -> Array[Dictionary]:
	var batch: Array[Dictionary] = _queue.duplicate()
	_queue.clear()
	batch.sort_custom(Callable(SimEventBus, "_compare_events"))
	_dispatch_batch(batch)
	return batch


func _dispatch_batch(batch: Array[Dictionary]) -> void:
	for ev: Dictionary in batch:
		var ev_type: String = str(ev.get("event", ""))
		if _subscribers.has(ev_type):
			var sub_var: Variant = _subscribers[ev_type]
			if sub_var is Array:
				var raw_list: Array = sub_var
				var listeners: Array = raw_list.duplicate()
				for cb_var: Variant in listeners:
					if cb_var is Callable:
						var cb: Callable = cb_var
						if cb.is_valid():
							cb.call(ev)
		if _subscribers.has("*"):
			var wild_var: Variant = _subscribers["*"]
			if wild_var is Array:
				var raw_wild: Array = wild_var
				var wildcards: Array = raw_wild.duplicate()
				for wcb_var: Variant in wildcards:
					if wcb_var is Callable:
						var wcb: Callable = wcb_var
						if wcb.is_valid():
							wcb.call(ev)


static func _compare_events(a: Dictionary, b: Dictionary) -> bool:
	var ta: int = _to_int(a.get("tick_id", 0), 0)
	var tb: int = _to_int(b.get("tick_id", 0), 0)
	if ta != tb:
		return ta < tb
	return _to_int(a.get("seq_id", 0), 0) < _to_int(b.get("seq_id", 0), 0)


func to_dict() -> Dictionary:
	return {
		"next_seq_id": _next_seq_id,
		"queue": _queue.duplicate(true)
	}


static func from_dict(data: Dictionary) -> SimEventBus:
	var bus: SimEventBus = SimEventBus.new()
	bus._next_seq_id = maxi(1, _to_int(data.get("next_seq_id", 1), 1))
	var raw_q: Variant = data.get("queue", [])
	if raw_q is Array:
		var q_arr: Array = raw_q
		for item: Variant in q_arr:
			if item is Dictionary:
				var d_item: Dictionary = item
				bus._queue.append(d_item.duplicate(true))
	return bus


static func validate_expedition_dispatched(payload: Dictionary) -> bool:
	var required: Array[String] = [
		"tick_id", "player_id", "manor_id", "origin_node_id",
		"unit_type", "officers", "troop_count", "morale_bp",
		"carried_grain", "cargo", "path_edge_ids", "standing_doctrine"
	]
	for key: String in required:
		if not payload.has(key):
			return false
	var tick_v: Variant = payload["tick_id"]
	if not (tick_v is int) or _to_int(tick_v, -1) < 0:
		return false
	for sk: String in ["player_id", "manor_id", "origin_node_id"]:
		var sv: Variant = payload[sk]
		if not (sv is String) or str(sv).is_empty():
			return false
	var ut_v: Variant = payload["unit_type"]
	if not (ut_v is String):
		return false
	var unit_type: String = str(ut_v)
	if unit_type != "ARMY" and unit_type != "CARAVAN":
		return false
	if not (payload["officers"] is Array):
		return false
	var tc_v: Variant = payload["troop_count"]
	if not (tc_v is int) or _to_int(tc_v, 0) <= 0:
		return false
	var mbp_v: Variant = payload["morale_bp"]
	var mbp: int = _to_int(mbp_v, -1)
	if not (mbp_v is int) or mbp < 0 or mbp > 10000:
		return false
	var cg_v: Variant = payload["carried_grain"]
	if not (cg_v is int) or _to_int(cg_v, -1) < 0:
		return false
	if not (payload["cargo"] is Dictionary):
		return false
	var edges_v: Variant = payload["path_edge_ids"]
	if not (edges_v is Array):
		return false
	var edges: Array = edges_v
	if edges.is_empty():
		return false
	if not (payload["standing_doctrine"] is Dictionary):
		return false
	return true


static func validate_raid_incoming(payload: Dictionary) -> bool:
	var required: Array[String] = [
		"tick_id", "target_manor_id", "host_node_id",
		"attacker_entity_id", "attacker_owner_id", "attacker_power", "promote_to_lod0"
	]
	for key: String in required:
		if not payload.has(key):
			return false
	var tick_v: Variant = payload["tick_id"]
	if not (tick_v is int) or _to_int(tick_v, -1) < 0:
		return false
	for str_key: String in ["target_manor_id", "host_node_id", "attacker_entity_id", "attacker_owner_id"]:
		var sv: Variant = payload[str_key]
		if not (sv is String) or str(sv).is_empty():
			return false
	if not (payload["attacker_power"] is Dictionary):
		return false
	if not (payload["promote_to_lod0"] is bool):
		return false
	return true
