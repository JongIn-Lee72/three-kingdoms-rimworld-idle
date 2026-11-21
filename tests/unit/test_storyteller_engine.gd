class_name TestStorytellerEngine
extends HarnessTestCase


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


func _make_story_manor(player_id: String = "p_story") -> ManorState:
	var manor: ManorState = ManorState.new("manor_story", player_id)
	manor.host_node_id = "xuchang"
	manor.household_troops = 300
	manor.set_resource("GRAIN", 3000)
	manor.set_resource("COIN", 2000)
	manor.set_resource("IRON", 500)
	var r1: PawnEntity = PawnEntity.new("ret_1", "Retainer One", false)
	var _a1: bool = manor.add_pawn(r1)
	return manor


func test_all_three_personas_and_relative_threat_pacing() -> void:
	assert_eq(StorytellerEngine.PERSONAS, ["ST_SIMA_QIAN", "ST_DONG_ZHUO", "ST_WEN_JING"], "Canonical 3 personas")
	assert_eq(StorytellerEngine.normalize_persona_id("SIMA_QIAN"), "ST_SIMA_QIAN", "Alias SIMA_QIAN normalized")
	assert_eq(StorytellerEngine.normalize_persona_id("DONG_ZHUO"), "ST_DONG_ZHUO", "Alias DONG_ZHUO normalized")
	assert_eq(StorytellerEngine.normalize_persona_id("WEN_JING"), "ST_WEN_JING", "Alias WEN_JING normalized")
	assert_eq(StorytellerEngine.normalize_persona_id("UNKNOWN_ST"), "ST_SIMA_QIAN", "Invalid persona falls back to ST_SIMA_QIAN")

	var st_sima: StorytellerEngine = StorytellerEngine.new("ST_SIMA_QIAN", 1000)
	var st_dong: StorytellerEngine = StorytellerEngine.new("ST_DONG_ZHUO", 1000)
	var st_wen: StorytellerEngine = StorytellerEngine.new("ST_WEN_JING", 1000)

	var t_sima: int = st_sima.calc_threat_score(50000, 4, 500, 1000)
	var t_dong: int = st_dong.calc_threat_score(50000, 4, 500, 1000)
	var t_wen: int = st_wen.calc_threat_score(50000, 4, 500, 1000)

	assert_lt(t_wen, t_sima, "ST_WEN_JING threat score < ST_SIMA_QIAN")
	assert_lt(t_sima, t_dong, "ST_SIMA_QIAN threat score < ST_DONG_ZHUO")

	# ST_SIMA_QIAN 6-day cycle: days 4 and 5 (day_id % 6 >= 4) must NEVER emit THREAT
	var manor: ManorState = _make_story_manor("p_sima_cycle")
	var pstate: Dictionary = {"player_id": "p_sima_cycle"}
	for day_off: int in [4, 5, 10, 11]:
		var clk_calm: SimClock = SimClock.new(day_off * SimClock.DAILY_SETTLEMENT_TICK)
		for seed_v: int in [101, 202, 303, 404, 505]:
			var ev_sum: Dictionary = st_sima.evaluate_daily_storyteller(pstate, manor, clk_calm, seed_v, null)
			assert_ne(str(ev_sum.get("category", "")), "THREAT", "ST_SIMA_QIAN day %d must suppress THREAT" % day_off)

	# Compare threat frequency over 40 days between ST_DONG_ZHUO and ST_WEN_JING
	var dong_threats: int = 0
	var wen_threats: int = 0
	for d: int in range(40):
		var clk_d: SimClock = SimClock.new(d * SimClock.DAILY_SETTLEMENT_TICK)
		var sd: Dictionary = st_dong.evaluate_daily_storyteller({"player_id": "p_cmp"}, manor, clk_d, 777, null)
		var sw: Dictionary = st_wen.evaluate_daily_storyteller({"player_id": "p_cmp"}, manor, clk_d, 777, null)
		if str(sd.get("category", "")) == "THREAT":
			dong_threats += 1
		if str(sw.get("category", "")) == "THREAT":
			wen_threats += 1

	assert_gt(dong_threats, wen_threats, "ST_DONG_ZHUO triggers more threats than ST_WEN_JING over 40 days")


func test_logarithmic_wealth_dampening_and_adaptation_bounds() -> void:
	# Verify ln_pm monotonicity and base properties
	assert_eq(StorytellerEngine.ln_pm(500), 0, "ln_pm <= 1000 returns 0")
	assert_eq(StorytellerEngine.ln_pm(1000), 0, "ln_pm(1000) == 0")
	var prev_ln: int = 0
	for x_pm: int in [1200, 1500, 2000, 4000, 10000, 100000, 1000000]:
		var cur_ln: int = StorytellerEngine.ln_pm(x_pm)
		assert_gt(cur_ln, prev_ln, "ln_pm strictly increasing at x_pm=%d" % x_pm)
		prev_ln = cur_ln

	var st: StorytellerEngine = StorytellerEngine.new("ST_SIMA_QIAN", 1000)

	# 10x wealth increases threat by < 3x across scales
	var t_1x: int = st.calc_threat_score(10000, 0, 0, 1000)
	var t_10x: int = st.calc_threat_score(100000, 0, 0, 1000)
	var t_100x: int = st.calc_threat_score(1000000, 0, 0, 1000)
	assert_gt(t_10x, t_1x, "10x wealth strictly increases threat")
	assert_lt(t_10x, t_1x * 3, "10x wealth (10k -> 100k) increases threat by < 3x")
	assert_gt(t_100x, t_10x, "100x wealth strictly increases threat over 10x")
	assert_lt(t_100x, t_10x * 3, "10x wealth (100k -> 1M) increases threat by < 3x")

	# With retainers and troops included, 10x wealth still increases threat < 3x
	var tc_1x: int = st.calc_threat_score(20000, 4, 300, 1000)
	var tc_10x: int = st.calc_threat_score(200000, 4, 300, 1000)
	assert_gt(tc_10x, tc_1x, "10x wealth with troops/retainers increases threat")
	assert_lt(tc_10x, tc_1x * 3, "10x wealth with troops/retainers increases threat < 3x")

	# Adaptation factor bounds [400, 1500] bp
	st.set_player_adaptation("p_bounds", 100)
	assert_eq(st.get_player_adaptation("p_bounds"), 400, "Adaptation lower bound clamped at 400 bp")
	st.set_player_adaptation("p_bounds", 3000)
	assert_eq(st.get_player_adaptation("p_bounds"), 1500, "Adaptation upper bound clamped at 1500 bp")

	# Repeated victories cap at 1500; repeated defeats floor at 400
	var a_val: int = 1000
	for _i: int in range(30):
		a_val = StorytellerEngine.update_adaptation(a_val, "VICTORY")
	assert_eq(a_val, 1500, "Repeated victories cap adaptation at 1500 bp")
	for _j: int in range(10):
		a_val = StorytellerEngine.update_adaptation(a_val, "DEFEAT")
	assert_eq(a_val, 400, "Repeated defeats floor adaptation at 400 bp")

	# defeat_drop strictly lowers threat score
	st.set_player_adaptation("p_drop", 1000)
	var t_before_defeat: int = st.calc_threat_score(50000, 4, 400, st.get_player_adaptation("p_drop"))
	var a_after_defeat: int = st.record_player_outcome("p_drop", "DEFEAT")
	assert_eq(a_after_defeat, 750, "DEFEAT drops adaptation from 1000 to 750 bp")
	var t_after_defeat: int = st.calc_threat_score(50000, 4, 400, a_after_defeat)
	assert_lt(t_after_defeat, t_before_defeat, "defeat_drop strictly lowers threat score")


func test_evaluate_daily_storyteller_event_bus_truce_and_round_trip() -> void:
	var st1: StorytellerEngine = StorytellerEngine.new("ST_DONG_ZHUO", 1100)
	var st2: StorytellerEngine = StorytellerEngine.new("ST_DONG_ZHUO", 1100)
	var manor: ManorState = _make_story_manor("p_ev")
	var bus1: SimEventBus = SimEventBus.new()
	var bus2: SimEventBus = SimEventBus.new()

	var saw_threat_bus: bool = false
	var saw_opp_bus: bool = false
	for d: int in range(25):
		var clk: SimClock = SimClock.new(d * SimClock.DAILY_SETTLEMENT_TICK)
		var sum1: Dictionary = st1.evaluate_daily_storyteller({"player_id": "p_ev"}, manor, clk, 31415, bus1)
		var sum2: Dictionary = st2.evaluate_daily_storyteller({"player_id": "p_ev"}, manor, clk, 31415, bus2)
		assert_eq(StateHasher.sha256_dict(sum1), StateHasher.sha256_dict(sum2), "Daily storyteller evaluation deterministic at day %d" % d)

	var drained1: Array[Dictionary] = bus1.drain_all()
	var drained2: Array[Dictionary] = bus2.drain_all()
	assert_eq(StateHasher.sha256_dict({"q": drained1}), StateHasher.sha256_dict({"q": drained2}), "Emitted SimEventBus batches identical")

	for ev: Dictionary in drained1:
		var et: String = str(ev.get("event", ""))
		var pl: Dictionary = _as_dict(ev.get("payload", {}))
		if et == StorytellerEngine.EVENT_STORYTELLER_THREAT:
			saw_threat_bus = true
			assert_eq(str(pl.get("persona_id", "")), "ST_DONG_ZHUO", "Threat payload includes persona_id")
			assert_gt(_as_int(pl.get("threat_score", 0), 0), 0, "Threat payload includes positive threat_score")
		elif et == StorytellerEngine.EVENT_STORYTELLER_OPPORTUNITY:
			saw_opp_bus = true
			assert_false(str(pl.get("event_code", "")).is_empty(), "Opportunity payload includes event_code")

	assert_true(saw_threat_bus, "Emitted at least one STORYTELLER_THREAT_EVENT onto SimEventBus")
	assert_true(saw_opp_bus, "Emitted at least one STORYTELLER_OPPORTUNITY_EVENT onto SimEventBus")

	# Truce shield suppresses THREAT events
	manor.truce_shield_until_tick = 10000
	var bus_truce: SimEventBus = SimEventBus.new()
	for d_truce: int in range(15):
		var clk_t: SimClock = SimClock.new(d_truce * SimClock.DAILY_SETTLEMENT_TICK)
		var sum_t: Dictionary = st1.evaluate_daily_storyteller({"player_id": "p_ev"}, manor, clk_t, 31415, bus_truce)
		assert_ne(str(sum_t.get("category", "")), "THREAT", "Truce shield suppresses THREAT at day %d" % d_truce)
	for ev_t: Dictionary in bus_truce.drain_all():
		assert_ne(str(ev_t.get("event", "")), StorytellerEngine.EVENT_STORYTELLER_THREAT, "No THREAT event emitted during truce")

	# Round-trip to_dict / from_dict & zero-float check
	var d1: Dictionary = st1.to_dict()
	assert_false(StateHasher.has_floats(d1), "StorytellerEngine.to_dict() must contain zero floats")
	assert_true(StateHasher.validate_deterministic_types(d1), "StorytellerEngine.to_dict() uses deterministic types")

	var st_restored: StorytellerEngine = StorytellerEngine.from_dict(d1)
	var d2: Dictionary = st_restored.to_dict()
	assert_eq(StateHasher.sha256_dict(d1), StateHasher.sha256_dict(d2), "StorytellerEngine to_dict/from_dict SHA-256 parity")
