class_name TestSimEventBus
extends HarnessTestCase

var _received_specific: Array[Dictionary] = []
var _received_wildcard: Array[Dictionary] = []
var _reentrant_bus: SimEventBus = null
var _reentrant_captured: Array[Dictionary] = []
var _reentrant_triggered: bool = false


func before_each() -> void:
	_received_specific.clear()
	_received_wildcard.clear()
	_reentrant_bus = null
	_reentrant_captured.clear()
	_reentrant_triggered = false


func _on_specific(ev: Dictionary) -> void:
	_received_specific.append(ev)


func _on_wildcard(ev: Dictionary) -> void:
	_received_wildcard.append(ev)


func _on_reentrant(ev: Dictionary) -> void:
	_reentrant_captured.append(ev)
	if not _reentrant_triggered and _reentrant_bus != null:
		_reentrant_triggered = true
		var _s1: int = _reentrant_bus.emit("REENTRANT_SAME_TICK", {"tag": "inner_same"}, 5)
		var _s2: int = _reentrant_bus.emit("REENTRANT_NEXT_TICK", {"tag": "inner_next"}, 6)


func test_fifo_ordering_by_tick_id_then_seq_id() -> void:
	var bus: SimEventBus = SimEventBus.new()
	var s1: int = bus.emit(SimEventBus.EVENT_TAX_COLLECTED, {"order": "t10_first"}, 10)
	var s2: int = bus.emit(SimEventBus.EVENT_CARAVAN_ARRIVED, {"order": "t5_first"}, 5)
	var s3: int = bus.emit(SimEventBus.EVENT_CARAVAN_ARRIVED, {"order": "t5_second"}, 5)
	var s4: int = bus.emit(SimEventBus.EVENT_SEASON_CHANGED, {"tick_id": 7, "order": "t7_from_payload"}, -1)
	var s5: int = bus.emit(SimEventBus.EVENT_STIPEND_DISTRIBUTED, {"order": "t5_third"}, 5)

	assert_eq([s1, s2, s3, s4, s5], [1, 2, 3, 4, 5], "seq_id must increment monotonically from 1")
	assert_eq(bus.peek_pending_count(), 5, "All 5 emitted events queued")

	var drained_7: Array[Dictionary] = bus.drain_for_tick(7)
	assert_eq(drained_7.size(), 4, "drain_for_tick(7) drains tick 5 (x3) and tick 7 (x1)")
	assert_eq(bus.peek_pending_count(), 1, "Tick 10 event remains pending")

	var seq_order: Array[int] = []
	for ev: Dictionary in drained_7:
		var seq_v: Variant = ev.get("seq_id", 0)
		if seq_v is int:
			var seq_i: int = seq_v
			seq_order.append(seq_i)
	assert_eq(seq_order, [2, 3, 5, 4], "Events ordered by (tick_id, seq_id) FIFO")

	var drained_rest: Array[Dictionary] = bus.drain_all()
	assert_eq(drained_rest.size(), 1, "drain_all drains remaining tick 10 event")
	assert_eq(drained_rest[0].get("seq_id", 0), 1, "Remaining event is seq_id 1")
	assert_eq(bus.peek_pending_count(), 0, "Queue empty after drain_all")


func test_subscribe_unsubscribe_and_wildcard() -> void:
	var bus: SimEventBus = SimEventBus.new()
	var cb_spec: Callable = Callable(self, "_on_specific")
	var cb_wild: Callable = Callable(self, "_on_wildcard")

	bus.subscribe(SimEventBus.EVENT_TAX_COLLECTED, cb_spec)
	bus.subscribe(SimEventBus.EVENT_TAX_COLLECTED, cb_spec) # duplicate subscribe ignored
	bus.subscribe("*", cb_wild)

	var mut_payload: Dictionary = {"amount": 100}
	var _s1: int = bus.emit(SimEventBus.EVENT_TAX_COLLECTED, mut_payload, 1)
	mut_payload["amount"] = 999 # verify payload was deep-copied on emit
	var _s2: int = bus.emit(SimEventBus.EVENT_CARAVAN_ARRIVED, {"amount": 50}, 1)

	var _d1: Array[Dictionary] = bus.drain_for_tick(1)
	assert_eq(_received_specific.size(), 1, "Specific subscriber invoked once (no duplicate delivery)")
	assert_eq(_received_wildcard.size(), 2, "Wildcard subscriber receives both events")
	var spec_payload_v: Variant = _received_specific[0].get("payload", {})
	if spec_payload_v is Dictionary:
		var spec_payload: Dictionary = spec_payload_v
		assert_eq(spec_payload.get("amount", 0), 100, "Emitted payload must be deep-copied at emit time")

	bus.unsubscribe(SimEventBus.EVENT_TAX_COLLECTED, cb_spec)
	var _s3: int = bus.emit(SimEventBus.EVENT_TAX_COLLECTED, {"amount": 200}, 2)
	var _d2: Array[Dictionary] = bus.drain_for_tick(2)
	assert_eq(_received_specific.size(), 1, "Unsubscribed specific callback no longer receives events")
	assert_eq(_received_wildcard.size(), 3, "Wildcard still receives tick 2 event")


func test_reentrant_emit_during_drain_for_tick() -> void:
	_reentrant_bus = SimEventBus.new()
	_reentrant_bus.subscribe("TRIGGER", Callable(self, "_on_reentrant"))
	_reentrant_bus.subscribe("*", Callable(self, "_on_wildcard"))

	var _s_init: int = _reentrant_bus.emit("TRIGGER", {"tag": "outer"}, 5)
	var first_batch: Array[Dictionary] = _reentrant_bus.drain_for_tick(5)

	assert_eq(first_batch.size(), 1, "Outer drain_for_tick(5) only returns snapshot taken before dispatch")
	assert_eq(_reentrant_captured.size(), 1, "Trigger handler ran once without recursion loop")
	assert_eq(_reentrant_bus.peek_pending_count(), 2, "Re-entrantly emitted events stay queued for next drain")

	var second_batch: Array[Dictionary] = _reentrant_bus.drain_for_tick(5)
	assert_eq(second_batch.size(), 1, "Second drain_for_tick(5) picks up re-entrant tick 5 event")
	assert_eq(second_batch[0].get("event", ""), "REENTRANT_SAME_TICK", "Second batch contains REENTRANT_SAME_TICK")
	assert_eq(_reentrant_bus.peek_pending_count(), 1, "Tick 6 re-entrant event remains queued")

	var third_batch: Array[Dictionary] = _reentrant_bus.drain_for_tick(6)
	assert_eq(third_batch.size(), 1, "drain_for_tick(6) picks up REENTRANT_NEXT_TICK")
	assert_eq(_received_wildcard.size(), 3, "All 3 events observed cleanly across drains")


func test_to_dict_from_dict_roundtrip_and_clear() -> void:
	var bus: SimEventBus = SimEventBus.new()
	var _s1: int = bus.emit(SimEventBus.EVENT_CARAVAN_ARRIVED, {"id": "c1"}, 12)
	var _s2: int = bus.emit(SimEventBus.EVENT_SEASON_CHANGED, {"season": "SUMMER"}, 24)

	var snapshot: Dictionary = bus.to_dict()
	var restored: SimEventBus = SimEventBus.from_dict(snapshot)
	assert_eq(restored.peek_pending_count(), 2, "Restored bus preserves 2 queued events")

	var s3: int = restored.emit(SimEventBus.EVENT_TAX_COLLECTED, {"coin": 50}, 30)
	assert_eq(s3, 3, "Restored bus continues seq_id monotonically at 3")

	var drained: Array[Dictionary] = restored.drain_all()
	assert_eq(drained.size(), 3, "Restored bus drains all 3 events")

	restored.clear()
	assert_eq(restored.peek_pending_count(), 0, "clear() empties queue")


func test_validate_expedition_dispatched_positive_and_negative() -> void:
	var valid_army: Dictionary = {
		"tick_id": 120,
		"player_id": "lord_A",
		"manor_id": "manor_01",
		"origin_node_id": "node_luoyang",
		"unit_type": "ARMY",
		"officers": ["off_01"],
		"troop_count": 500,
		"morale_bp": 8000,
		"carried_grain": 1200,
		"cargo": {"WEAPONS": 50},
		"path_edge_ids": ["edge_1", "edge_2"],
		"standing_doctrine": {"aggression": "BALANCED"}
	}
	assert_true(SimEventBus.validate_expedition_dispatched(valid_army), "Valid ARMY expedition passes")

	var valid_caravan: Dictionary = valid_army.duplicate(true)
	valid_caravan["unit_type"] = "CARAVAN"
	valid_caravan["carried_grain"] = 0
	valid_caravan["morale_bp"] = 0
	assert_true(SimEventBus.validate_expedition_dispatched(valid_caravan), "Valid CARAVAN expedition passes")

	var missing_key: Dictionary = valid_army.duplicate(true)
	var _erased: bool = missing_key.erase("standing_doctrine")
	assert_false(SimEventBus.validate_expedition_dispatched(missing_key), "Missing standing_doctrine fails")

	var bad_unit: Dictionary = valid_army.duplicate(true)
	bad_unit["unit_type"] = "NAVY"
	assert_false(SimEventBus.validate_expedition_dispatched(bad_unit), "Invalid unit_type fails")

	var zero_troops: Dictionary = valid_army.duplicate(true)
	zero_troops["troop_count"] = 0
	assert_false(SimEventBus.validate_expedition_dispatched(zero_troops), "troop_count <= 0 fails")

	var bad_morale: Dictionary = valid_army.duplicate(true)
	bad_morale["morale_bp"] = 10001
	assert_false(SimEventBus.validate_expedition_dispatched(bad_morale), "morale_bp > 10000 fails")

	var neg_grain: Dictionary = valid_army.duplicate(true)
	neg_grain["carried_grain"] = -1
	assert_false(SimEventBus.validate_expedition_dispatched(neg_grain), "carried_grain < 0 fails")

	var empty_path: Dictionary = valid_army.duplicate(true)
	empty_path["path_edge_ids"] = []
	assert_false(SimEventBus.validate_expedition_dispatched(empty_path), "Empty path_edge_ids fails")

	var empty_player: Dictionary = valid_army.duplicate(true)
	empty_player["player_id"] = ""
	assert_false(SimEventBus.validate_expedition_dispatched(empty_player), "Empty player_id fails")

	var float_tick: Dictionary = valid_army.duplicate(true)
	float_tick["tick_id"] = 120.0
	assert_false(SimEventBus.validate_expedition_dispatched(float_tick), "Float tick_id fails")


func test_validate_raid_incoming_positive_and_negative() -> void:
	var valid_raid: Dictionary = {
		"tick_id": 240,
		"target_manor_id": "manor_01",
		"host_node_id": "node_xuchang",
		"attacker_entity_id": "army_99",
		"attacker_owner_id": "lord_C",
		"attacker_power": {"troop_count": 300, "atk_bp": 4500},
		"promote_to_lod0": true
	}
	assert_true(SimEventBus.validate_raid_incoming(valid_raid), "Valid raid_incoming passes")

	var missing_field: Dictionary = valid_raid.duplicate(true)
	var _erased: bool = missing_field.erase("promote_to_lod0")
	assert_false(SimEventBus.validate_raid_incoming(missing_field), "Missing promote_to_lod0 fails")

	var neg_tick: Dictionary = valid_raid.duplicate(true)
	neg_tick["tick_id"] = -1
	assert_false(SimEventBus.validate_raid_incoming(neg_tick), "Negative tick_id fails")

	var empty_owner: Dictionary = valid_raid.duplicate(true)
	empty_owner["attacker_owner_id"] = ""
	assert_false(SimEventBus.validate_raid_incoming(empty_owner), "Empty attacker_owner_id fails")

	var bad_power: Dictionary = valid_raid.duplicate(true)
	bad_power["attacker_power"] = 300
	assert_false(SimEventBus.validate_raid_incoming(bad_power), "Non-Dictionary attacker_power fails")

	var bad_promote: Dictionary = valid_raid.duplicate(true)
	bad_promote["promote_to_lod0"] = 1
	assert_false(SimEventBus.validate_raid_incoming(bad_promote), "Non-bool promote_to_lod0 fails")
