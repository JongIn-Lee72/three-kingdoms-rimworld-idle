class_name TestSimClock
extends HarnessTestCase


func test_cadence_constants() -> void:
	assert_eq(SimClock.MICRO_TICK, 1, "MICRO_TICK must be 1")
	assert_eq(SimClock.MACRO_TICK, 6, "MACRO_TICK must be 6")
	assert_eq(SimClock.DAILY_SETTLEMENT_TICK, 24, "DAILY_SETTLEMENT_TICK must be 24")
	assert_eq(SimClock.CHALLENGE_TTL_TICKS, 900, "CHALLENGE_TTL_TICKS must be 900")
	assert_eq(SimClock.SHICHEN_PER_DAY, 12, "SHICHEN_PER_DAY must be 12")
	assert_eq(SimClock.TICKS_PER_SHICHEN, 2, "TICKS_PER_SHICHEN must be 2")
	assert_eq(SimClock.DAYS_PER_SEASON, 30, "DAYS_PER_SEASON must be 30")
	assert_eq(SimClock.SEASONS_PER_YEAR, 4, "SEASONS_PER_YEAR must be 4")
	assert_eq(SimClock.TICKS_PER_DAY, 24, "TICKS_PER_DAY must be 24")
	assert_eq(SimClock.TICKS_PER_SEASON, 720, "TICKS_PER_SEASON must be 720")


func test_zero_and_negative_initialization() -> void:
	var clock_zero: SimClock = SimClock.new()
	assert_eq(clock_zero.current_tick_id, 0, "Default clock starts at tick 0")
	assert_false(clock_zero.is_macro_tick(), "is_macro_tick must be false at tick 0")
	assert_false(clock_zero.is_daily_settlement_tick(), "is_daily_settlement_tick must be false at tick 0")
	assert_eq(clock_zero.get_macro_tick_id(), 0, "macro_tick_id is 0 at tick 0")
	assert_eq(clock_zero.get_day_id(), 0, "day_id is 0 at tick 0")
	assert_eq(clock_zero.get_year(), 1, "year starts at 1")

	var clock_neg: SimClock = SimClock.new(-42)
	assert_eq(clock_neg.current_tick_id, 0, "Negative initial_tick must clamp to 0")

	var after_zero: int = clock_neg.advance(0)
	var after_neg: int = clock_neg.advance(-10)
	assert_eq(after_zero, 0, "advance(0) must not alter tick")
	assert_eq(after_neg, 0, "advance(-10) must not move tick backwards")


func test_macro_and_daily_settlement_multiples() -> void:
	var clock: SimClock = SimClock.new(0)
	var macro_hits: Array[int] = []
	var daily_hits: Array[int] = []

	for _step: int in range(72):
		var t: int = clock.step_micro()
		if clock.is_macro_tick():
			macro_hits.append(t)
		if clock.is_daily_settlement_tick():
			daily_hits.append(t)

	var expected_macro: Array[int] = [6, 12, 18, 24, 30, 36, 42, 48, 54, 60, 66, 72]
	var expected_daily: Array[int] = [24, 48, 72]
	assert_eq(macro_hits, expected_macro, "Macro ticks trigger strictly at positive multiples of 6")
	assert_eq(daily_hits, expected_daily, "Daily settlement ticks trigger strictly at positive multiples of 24")
	assert_eq(clock.get_macro_tick_id(), 12, "At tick 72, macro_tick_id == 12")
	assert_eq(clock.get_day_id(), 3, "At tick 72, day_id == 3")


func test_shichen_12_index_and_names() -> void:
	assert_eq(SimClock.SHICHEN_NAMES.size(), 12, "Must define 12 ShiChen names")
	var clock: SimClock = SimClock.new(0)
	for tick: int in range(24):
		var c: SimClock = SimClock.new(tick)
		@warning_ignore("integer_division")
		var expected_idx: int = tick / 2
		assert_eq(c.get_shichen_index(), expected_idx, "Tick %d shichen index" % tick)
		assert_eq(c.get_tick_of_day(), tick, "Tick %d tick_of_day" % tick)
		assert_eq(c.get_shichen_name(), SimClock.SHICHEN_NAMES[expected_idx], "Tick %d shichen name" % tick)

	var next_day: SimClock = SimClock.new(24)
	assert_eq(next_day.get_shichen_index(), 0, "Tick 24 wraps to ShiChen index 0")
	assert_eq(next_day.get_shichen_name(), "자시", "Tick 24 wraps to 자시")
	assert_eq(clock.get_shichen_name(), "자시", "Tick 0 starts at 자시")

	var noon: SimClock = SimClock.new(12)
	assert_eq(noon.get_shichen_index(), 6, "Tick 12 is ShiChen index 6")
	assert_eq(noon.get_shichen_name(), "오시", "Tick 12 is 오시")


func test_four_season_and_year_cycle() -> void:
	assert_eq(SimClock.SEASONS.size(), 4, "Must define 4 seasons")

	var spring_end: SimClock = SimClock.new(719)
	assert_eq(spring_end.get_season_index(), 0, "Tick 719 is still SPRING index 0")
	assert_eq(spring_end.get_season(), "SPRING", "Tick 719 season is SPRING")
	assert_eq(spring_end.get_day_of_season(), 29, "Tick 719 is day 29 of SPRING")
	assert_eq(spring_end.get_year(), 1, "Tick 719 is year 1")

	var summer_start: SimClock = SimClock.new(720)
	assert_eq(summer_start.get_season_index(), 1, "Tick 720 is SUMMER index 1")
	assert_eq(summer_start.get_season(), "SUMMER", "Tick 720 season is SUMMER")
	assert_eq(summer_start.get_day_of_season(), 0, "Tick 720 resets day_of_season to 0")

	var autumn_start: SimClock = SimClock.new(1440)
	assert_eq(autumn_start.get_season_index(), 2, "Tick 1440 is AUTUMN index 2")
	assert_eq(autumn_start.get_season(), "AUTUMN", "Tick 1440 season is AUTUMN")

	var winter_start: SimClock = SimClock.new(2160)
	assert_eq(winter_start.get_season_index(), 3, "Tick 2160 is WINTER index 3")
	assert_eq(winter_start.get_season(), "WINTER", "Tick 2160 season is WINTER")

	var year2_spring: SimClock = SimClock.new(2880)
	assert_eq(year2_spring.get_season_index(), 0, "Tick 2880 wraps to SPRING index 0")
	assert_eq(year2_spring.get_season(), "SPRING", "Tick 2880 wraps to SPRING")
	assert_eq(year2_spring.get_year(), 2, "Tick 2880 advances to year 2")


func test_to_dict_from_dict_roundtrip() -> void:
	var sample_ticks: Array[int] = [0, 17, 720, 1453, 2885]
	for t: int in sample_ticks:
		var orig: SimClock = SimClock.new(t)
		var serialized: Dictionary = orig.to_dict()
		assert_has_key(serialized, "current_tick_id", "to_dict must have current_tick_id")
		assert_has_key(serialized, "macro_tick_id", "to_dict must have macro_tick_id")
		assert_has_key(serialized, "day_id", "to_dict must have day_id")
		assert_has_key(serialized, "shichen_index", "to_dict must have shichen_index")
		assert_has_key(serialized, "season", "to_dict must have season")

		var restored: SimClock = SimClock.from_dict(serialized)
		assert_eq(restored.current_tick_id, orig.current_tick_id, "Restored tick matches at %d" % t)
		assert_eq(restored.to_dict(), serialized, "Exact to_dict/from_dict roundtrip at %d" % t)

	var json_float_clock: SimClock = SimClock.from_dict({"current_tick_id": 42.0})
	assert_eq(json_float_clock.current_tick_id, 42, "from_dict handles JSON float numbers")

	var neg_clock: SimClock = SimClock.from_dict({"current_tick_id": -99})
	assert_eq(neg_clock.current_tick_id, 0, "from_dict clamps negative tick to 0")

	var empty_clock: SimClock = SimClock.from_dict({})
	assert_eq(empty_clock.current_tick_id, 0, "from_dict defaults missing tick to 0")
