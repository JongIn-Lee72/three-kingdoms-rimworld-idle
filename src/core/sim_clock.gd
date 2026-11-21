class_name SimClock
extends RefCounted

const MICRO_TICK: int = 1
const MACRO_TICK: int = 6
const DAILY_SETTLEMENT_TICK: int = 24
const SHICHEN_PER_DAY: int = 12
const TICKS_PER_SHICHEN: int = 2
const DAYS_PER_SEASON: int = 30
const SEASONS_PER_YEAR: int = 4
const TICKS_PER_DAY: int = 24
const TICKS_PER_SEASON: int = 720
const CHALLENGE_TTL_TICKS: int = 900

const SEASONS: Array[String] = ["SPRING", "SUMMER", "AUTUMN", "WINTER"]
const SHICHEN_NAMES: Array[String] = [
	"자시", "축시", "인시", "묘시", "진시", "사시",
	"오시", "미시", "신시", "유시", "술시", "해시"
]

var current_tick_id: int = 0


func _init(initial_tick: int = 0) -> void:
	current_tick_id = maxi(0, initial_tick)


func advance(ticks: int = 1) -> int:
	if ticks > 0:
		current_tick_id += ticks
	return current_tick_id


func step_micro() -> int:
	return advance(MICRO_TICK)


func is_macro_tick() -> bool:
	return current_tick_id > 0 and (current_tick_id % MACRO_TICK) == 0


func is_daily_settlement_tick() -> bool:
	return current_tick_id > 0 and (current_tick_id % DAILY_SETTLEMENT_TICK) == 0


func get_macro_tick_id() -> int:
	@warning_ignore("integer_division")
	return current_tick_id / MACRO_TICK


func get_day_id() -> int:
	@warning_ignore("integer_division")
	return current_tick_id / DAILY_SETTLEMENT_TICK


func get_tick_of_day() -> int:
	return current_tick_id % DAILY_SETTLEMENT_TICK


func get_shichen_index() -> int:
	@warning_ignore("integer_division")
	return (current_tick_id % DAILY_SETTLEMENT_TICK) / TICKS_PER_SHICHEN


func get_shichen_name() -> String:
	return SHICHEN_NAMES[get_shichen_index()]


func get_season_index() -> int:
	@warning_ignore("integer_division")
	return (get_day_id() / DAYS_PER_SEASON) % SEASONS_PER_YEAR


func get_season() -> String:
	return SEASONS[get_season_index()]


func get_day_of_season() -> int:
	return get_day_id() % DAYS_PER_SEASON


func get_year() -> int:
	@warning_ignore("integer_division")
	return (get_day_id() / (DAYS_PER_SEASON * SEASONS_PER_YEAR)) + 1


func to_dict() -> Dictionary:
	return {
		"current_tick_id": current_tick_id,
		"macro_tick_id": get_macro_tick_id(),
		"day_id": get_day_id(),
		"shichen_index": get_shichen_index(),
		"season": get_season()
	}


static func from_dict(data: Dictionary) -> SimClock:
	var raw_var: Variant = data.get("current_tick_id", 0)
	var raw_tick: int = 0
	if raw_var is int:
		raw_tick = raw_var
	elif raw_var is float:
		var f_val: float = raw_var
		raw_tick = int(f_val)
	return SimClock.new(maxi(0, raw_tick))
