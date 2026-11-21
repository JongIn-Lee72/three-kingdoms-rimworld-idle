class_name TestInterestDeltaAndChronicle
extends HarnessTestCase


func _as_bool(v: Variant, fallback: bool = false) -> bool:
	if v is bool:
		var bv: bool = v
		return bv
	return fallback


func _as_int(v: Variant, fallback: int = 0) -> int:
	if v is int:
		var iv: int = v
		return iv
	if v is float:
		var fv: float = v
		return int(fv)
	return fallback


func _as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		var d: Dictionary = v
		return d
	return {}


func _as_array(v: Variant) -> Array:
	if v is Array:
		var a: Array = v
		return a
	return []


func test_interest_delta_4_channels_lod_promotion_and_dirty_bit_empty_delta() -> void:
	var wg: WorldGraph = WorldGraph.new({}, true)
	var acm: ArmyCaravanManager = ArmyCaravanManager.new()
	var rm: RegionalMarket = RegionalMarket.new(wg)
	var fm: FactionManager = FactionManager.new()
	var dte: DiplomacyTreatyEngine = DiplomacyTreatyEngine.new()
	var sbr: SiegeBattleResolver = SiegeBattleResolver.new()

	var _fc: Dictionary = fm.create_faction("fac_shu", "Shu", "lord_a", "xuchang", wg, 5000, 5000, "PREFECT")

	var manor_a: ManorState = ManorState.new("manor_lord_a", "lord_a")
	manor_a.host_node_id = "xuchang"
	manor_a.current_lod = 1
	var p_a: PawnEntity = PawnEntity.new("lord_a_avatar", "Liu Bei", true)
	p_a.owner_player_id = "lord_a"
	var _pa_ok: bool = manor_a.add_pawn(p_a)

	var manor_b: ManorState = ManorState.new("manor_ally_b", "ally_b")
	manor_b.host_node_id = "luoyang"
	manor_b.current_lod = 0
	var p_b: PawnEntity = PawnEntity.new("ally_b_avatar", "Guan Yu", true)
	p_b.owner_player_id = "ally_b"
	var _pb_ok: bool = manor_b.add_pawn(p_b)

	var manors: Dictionary = {"lord_a": manor_a, "ally_b": manor_b}
	var clock: SimClock = SimClock.new(6)

	var idm: InterestDeltaManager = InterestDeltaManager.new()
	idm.register_peer("peer_a", [
		DtoSchemas.CHAN_GLOBAL_MACRO,
		DtoSchemas.CHAN_FACTION + ":fac_shu",
		DtoSchemas.CHAN_NODE + ":xuchang",
		DtoSchemas.CHAN_MANOR + ":manor_lord_a"
	])

	var subs: Array[String] = idm.get_subscriptions("peer_a")
	assert_eq(subs.size(), 4, "All 4 interest channels subscribed")
	assert_true(subs.has(DtoSchemas.CHAN_GLOBAL_MACRO), "Has CHAN_GLOBAL_MACRO")
	assert_true(subs.has(DtoSchemas.CHAN_FACTION + ":fac_shu"), "Has CHAN_FACTION:fac_shu")
	assert_true(subs.has(DtoSchemas.CHAN_NODE + ":xuchang"), "Has CHAN_NODE:xuchang")
	assert_true(subs.has(DtoSchemas.CHAN_MANOR + ":manor_lord_a"), "Has CHAN_MANOR:manor_lord_a")

	# Auto-promote subscribed manor to LOD 0 and demote unobserved peaceful manor to LOD 1
	idm.sync_manor_lods(manors, {"lord_a": false, "ally_b": false})
	assert_eq(manor_a.current_lod, 0, "Observed/subscribed manor_lord_a promoted to LOD 0")
	assert_eq(manor_b.current_lod, 1, "Unobserved peaceful manor_ally_b demoted to LOD 1")

	var server_state: Dictionary = {
		"clock": clock,
		"state_crc32": 123456,
		"world_graph": wg,
		"army_manager": acm,
		"regional_market": rm,
		"faction_manager": fm,
		"diplomacy": dte,
		"siege_resolver": sbr,
		"manors": manors
	}

	# Tick 1: initial delta emits all 4 populated channels and passes schema validator
	var delta1: Dictionary = idm.build_tick_delta_for_peer("peer_a", server_state)
	var v1: Dictionary = DtoSchemas.validate_tick_delta(delta1)
	assert_true(_as_bool(v1.get("ok", false), false), "Tick 1 delta passes DtoSchemas.validate_tick_delta")
	var chans1: Dictionary = _as_dict(delta1.get("channels", {}))
	assert_true(chans1.has(DtoSchemas.CHAN_GLOBAL_MACRO), "Tick 1 includes CHAN_GLOBAL_MACRO")
	assert_true(chans1.has(DtoSchemas.CHAN_FACTION + ":fac_shu"), "Tick 1 includes CHAN_FACTION:fac_shu")
	assert_true(chans1.has(DtoSchemas.CHAN_NODE + ":xuchang"), "Tick 1 includes CHAN_NODE:xuchang")
	assert_true(chans1.has(DtoSchemas.CHAN_MANOR + ":manor_lord_a"), "Tick 1 includes CHAN_MANOR:manor_lord_a")

	# Tick 2 (unchanged state): dirty-bit delta MUST emit empty channels!
	var delta2: Dictionary = idm.build_tick_delta_for_peer("peer_a", server_state)
	var chans2: Dictionary = _as_dict(delta2.get("channels", {}))
	assert_eq(chans2.size(), 0, "Unchanged tick 2 emits empty channel delta")

	# Tick 3: mutate only manor_lord_a GRAIN stock -> only CHAN_MANOR:manor_lord_a emits changed field
	var _g: int = manor_a.add_resource("GRAIN", 250)
	var delta3: Dictionary = idm.build_tick_delta_for_peer("peer_a", server_state)
	var chans3: Dictionary = _as_dict(delta3.get("channels", {}))
	assert_eq(chans3.size(), 1, "Only modified channel emitted on tick 3")
	var m_delta: Dictionary = _as_dict(chans3.get(DtoSchemas.CHAN_MANOR + ":manor_lord_a", {}))
	var u_stock: Dictionary = _as_dict(m_delta.get("u_stockpile", {}))
	assert_eq(_as_int(u_stock.get("GRAIN", 0), 0), manor_a.get_resource("GRAIN"), "Changed GRAIN stock emitted in u_stockpile")
	assert_false(u_stock.has("COIN"), "Unchanged COIN omitted from dirty-bit delta")


func test_chronicle_inbox_offline_digest_f38_and_async_decision_timeout_f39() -> void:
	var cis: ChronicleInboxService = ChronicleInboxService.new()

	# F-38: Offline Chronicle Digest
	cis.mark_player_offline("lord_a", 10, {"GRAIN": 1000, "COIN": 500, "WOOD": 200})
	cis.record_offline_event("lord_a", ChronicleInboxService.CATEGORY_STIPEND, {"tick_id": 24, "coin": 180, "grain": 350})
	cis.record_offline_event("lord_a", ChronicleInboxService.CATEGORY_MISSION, {"tick_id": 24, "mission_id": "mis_001", "reward_coin": 120})
	cis.record_offline_event("lord_a", ChronicleInboxService.CATEGORY_BATTLE_REPLAY, {"tick_id": 30, "breached": false, "repelled": true})
	cis.record_offline_event("lord_a", ChronicleInboxService.CATEGORY_PAWN_EVENT, {"tick_id": 32, "pawn_id": "lord_a_avatar", "event": "BREAKTHROUGH"})
	# Out-of-window event (before from_tick=10) must be excluded
	cis.record_offline_event("lord_a", ChronicleInboxService.CATEGORY_MISSION, {"tick_id": 5, "mission_id": "old_mis"})

	var digest: Dictionary = cis.build_reconnect_gazette("lord_a", 10, 48, {"GRAIN": 1850, "COIN": 800, "WOOD": 200})
	var vd: Dictionary = DtoSchemas.validate_offline_chronicle_digest(digest)
	assert_true(_as_bool(vd.get("ok", false), false), "Offline digest passes DtoSchemas.validate_offline_chronicle_digest: " + str(vd.get("reason", "")))

	var net_yields: Dictionary = _as_dict(digest.get("net_yields", {}))
	assert_eq(_as_int(net_yields.get("GRAIN", 0), 0), 850, "Net GRAIN yield == +850")
	assert_eq(_as_int(net_yields.get("COIN", 0), 0), 300, "Net COIN yield == +300")
	assert_false(net_yields.has("WOOD"), "Zero-delta WOOD omitted from net_yields")

	var stipends: Dictionary = _as_dict(digest.get("stipends_received", {}))
	assert_eq(_as_int(stipends.get("COIN", 0), 0), 180, "Stipend COIN == 180")
	assert_eq(_as_int(stipends.get("GRAIN", 0), 0), 350, "Stipend GRAIN == 350")
	assert_eq(_as_int(stipends.get("count", 0), 0), 1, "Stipend count == 1")
	assert_eq(_as_array(digest.get("completed_missions", [])).size(), 1, "1 completed mission within [10,48]")
	assert_eq(_as_array(digest.get("battle_replays", [])).size(), 1, "1 battle replay within [10,48]")
	assert_eq(_as_array(digest.get("pawn_events", [])).size(), 1, "1 pawn event within [10,48]")

	# F-39: Async Event Decision Inbox (non-blocking timeout fallback)
	var enq1: Dictionary = cis.enqueue_decision("lord_a", "IMPERIAL_LEVY", ["PAY_LEVY", "REFUSE_LEVY"], "PAY_LEVY", 72, {"coin": 100})
	var enq2: Dictionary = cis.enqueue_decision("lord_a", "RETAINER_PROPOSAL", ["ADOPT", "REJECT"], "REJECT", 96, {"proposal_id": "prop_1"})
	assert_true(_as_bool(enq1.get("ok", false), false), "Decision 1 enqueued")
	assert_true(_as_bool(enq2.get("ok", false), false), "Decision 2 enqueued")
	var did1: String = str(enq1.get("decision_id", ""))
	var did2: String = str(enq2.get("decision_id", ""))
	assert_eq(cis.get_pending_decisions_for_player("lord_a").size(), 2, "2 pending decisions for lord_a")

	# Player explicitly submits decision 2 before deadline
	var sub_bad: Dictionary = cis.submit_decision("other_player", did2, "ADOPT", 50)
	assert_false(_as_bool(sub_bad.get("ok", true), true), "Unauthorized player cannot submit decision")
	var sub_ok: Dictionary = cis.submit_decision("lord_a", did2, "ADOPT", 50)
	assert_true(_as_bool(sub_ok.get("ok", false), false), "Player decision 2 accepted")
	assert_eq(str(cis.get_decision(did2).get("resolution_mode", "")), "PLAYER_CHOICE", "Decision 2 mode == PLAYER_CHOICE")

	# Before deadline_tick=72, decision 1 stays PENDING
	var exp_early: Array[Dictionary] = cis.process_expired_decisions(71)
	assert_eq(exp_early.size(), 0, "No decisions expired before deadline_tick 72")
	assert_eq(str(cis.get_decision(did1).get("status", "")), "PENDING", "Decision 1 still PENDING at tick 71")

	# At deadline_tick=72, decision 1 auto-applies default_option without blocking
	var exp_now: Array[Dictionary] = cis.process_expired_decisions(72)
	assert_eq(exp_now.size(), 1, "Decision 1 auto-resolved on deadline_tick=72")
	var d1_after: Dictionary = cis.get_decision(did1)
	assert_eq(str(d1_after.get("status", "")), "EXPIRED_DEFAULT", "Decision 1 status == EXPIRED_DEFAULT")
	assert_eq(str(d1_after.get("chosen_option", "")), "PAY_LEVY", "Decision 1 auto-applied default_option PAY_LEVY")
	assert_eq(str(d1_after.get("resolution_mode", "")), "TIMEOUT_FALLBACK", "Decision 1 resolution_mode == TIMEOUT_FALLBACK")
	assert_eq(cis.get_pending_decisions_for_player("lord_a").size(), 0, "0 pending decisions remain")
