class_name StorytellerEngine
extends RefCounted

const PERSONAS: Array[String] = ["ST_SIMA_QIAN", "ST_DONG_ZHUO", "ST_WEN_JING"]
const ADAPTATION_MIN_BP: int = 400
const ADAPTATION_MAX_BP: int = 1500
const ADAPTATION_DEFAULT_BP: int = 1000

const EVENT_STORYTELLER_THREAT: String = "STORYTELLER_THREAT_EVENT"
const EVENT_STORYTELLER_OPPORTUNITY: String = "STORYTELLER_OPPORTUNITY_EVENT"

const LN2_PM: int = 693

var persona_id: String = "ST_SIMA_QIAN"
var era_scale_bp: int = 1000
var player_adaptation_bp: Dictionary = {}
var event_log: Array[Dictionary] = []


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


func _init(p_persona_id: String = "ST_SIMA_QIAN", p_era_scale_bp: int = 1000) -> void:
	persona_id = normalize_persona_id(p_persona_id)
	era_scale_bp = clampi(p_era_scale_bp, 500, 2000)
	player_adaptation_bp.clear()
	event_log.clear()


static func normalize_persona_id(raw_id: String) -> String:
	match raw_id:
		"ST_SIMA_QIAN", "SIMA_QIAN":
			return "ST_SIMA_QIAN"
		"ST_DONG_ZHUO", "DONG_ZHUO":
			return "ST_DONG_ZHUO"
		"ST_WEN_JING", "WEN_JING":
			return "ST_WEN_JING"
		_:
			return "ST_SIMA_QIAN"


# Deterministic integer natural log approximation: round(ln(x_pm / 1000.0) * 1000)
# Valid and strictly monotonic for x_pm >= 1000
static func ln_pm(x_pm: int) -> int:
	if x_pm <= 1000:
		return 0
	var v_pm: int = x_pm
	var k: int = 0
	while v_pm >= 2000:
		@warning_ignore("integer_division")
		v_pm = v_pm / 2
		k += 1

	# For m = v_pm in [1000, 1999], let u = (m - 1000) * 1000 / (m + 1000) in [0, 333]
	# ln(m / 1000) = 2 * (u + u^3 / 3 + u^5 / 5)
	@warning_ignore("integer_division")
	var u: int = ((v_pm - 1000) * 1000) / (v_pm + 1000)
	@warning_ignore("integer_division")
	var u2: int = (u * u) / 1000
	@warning_ignore("integer_division")
	var u3: int = (u2 * u) / 1000
	@warning_ignore("integer_division")
	var u5: int = (u3 * u2) / 1000
	@warning_ignore("integer_division")
	var ln_rem_pm: int = 2 * (u + u3 / 3 + u5 / 5)
	return k * LN2_PM + ln_rem_pm


# Threat formula (F-35):
# T_i = (100 * ln(1 + W / 1000) + 25 * N_retainers + 0.15 * N_troops) * (adaptation_bp / 1000) * (persona_bp / 1000) * (era_bp / 1000)
func calc_threat_score(
	wealth: int,
	retainers: int,
	troops: int,
	adaptation_bp: int = ADAPTATION_DEFAULT_BP
) -> int:
	var w_safe: int = maxi(0, wealth)
	var r_safe: int = maxi(0, retainers)
	var t_safe: int = maxi(0, troops)
	var adapt: int = clampi(adaptation_bp, ADAPTATION_MIN_BP, ADAPTATION_MAX_BP)

	# 1 + W / 1000 in permille = 1000 + W
	var ln_term_pm: int = ln_pm(1000 + w_safe)
	@warning_ignore("integer_division")
	var wealth_score: int = (100 * ln_term_pm) / 1000
	var retainer_score: int = 25 * r_safe
	@warning_ignore("integer_division")
	var troop_score: int = (15 * t_safe) / 100
	var base_score: int = wealth_score + retainer_score + troop_score

	var persona_bp: int = 1000
	if persona_id == "ST_DONG_ZHUO":
		persona_bp = 1200
	elif persona_id == "ST_WEN_JING":
		persona_bp = 650

	@warning_ignore("integer_division")
	var s1: int = (base_score * adapt) / 1000
	@warning_ignore("integer_division")
	var s2: int = (s1 * persona_bp) / 1000
	@warning_ignore("integer_division")
	var s3: int = (s2 * era_scale_bp) / 1000
	return maxi(10, s3)


static func update_adaptation(current_bp: int, outcome: String) -> int:
	var cur: int = clampi(current_bp, ADAPTATION_MIN_BP, ADAPTATION_MAX_BP)
	match outcome:
		"PROSPERITY", "PEACEFUL_DAY", "VICTORY":
			cur += 30
		"MAJOR_LOSS", "DEFEAT", "RAID_BREACHED", "MENTAL_BREAK_EXTREME":
			cur -= 250
		"MINOR_LOSS", "LIGHT_SETBACK":
			cur -= 100
		_:
			pass
	return clampi(cur, ADAPTATION_MIN_BP, ADAPTATION_MAX_BP)


func get_player_adaptation(player_id: String) -> int:
	return clampi(_to_int(player_adaptation_bp.get(player_id, ADAPTATION_DEFAULT_BP), ADAPTATION_DEFAULT_BP), ADAPTATION_MIN_BP, ADAPTATION_MAX_BP)


func set_player_adaptation(player_id: String, value_bp: int) -> void:
	if player_id.is_empty():
		return
	player_adaptation_bp[player_id] = clampi(value_bp, ADAPTATION_MIN_BP, ADAPTATION_MAX_BP)


func record_player_outcome(player_id: String, outcome: String) -> int:
	var updated: int = update_adaptation(get_player_adaptation(player_id), outcome)
	set_player_adaptation(player_id, updated)
	return updated


static func compute_manor_wealth(manor: ManorState) -> int:
	if manor == null:
		return 0
	var w_res: int = 0
	w_res += manor.get_resource("GRAIN")
	w_res += manor.get_resource("COIN") * 2
	w_res += manor.get_resource("WOOD")
	w_res += manor.get_resource("IRON") * 3
	w_res += manor.get_resource("HORSES") * 10
	w_res += manor.get_resource("HERBS_WINE") * 4
	w_res += manor.get_resource("WEAPONS") * 6

	var w_bld: int = 0
	for bid: String in ManorState.BUILDING_IDS:
		w_bld += manor.get_building_level(bid) * 300
	@warning_ignore("integer_division")
	var w_bld_half: int = w_bld / 2

	var w_troops: int = manor.household_troops * 4
	var w_officers: int = manor.pawns.size() * 400
	return w_res + w_bld_half + w_troops + w_officers


func evaluate_daily_storyteller(
	player_state: Dictionary,
	manor: ManorState,
	clock: SimClock,
	world_seed: int,
	event_bus: SimEventBus
) -> Dictionary:
	var pid: String = str(player_state.get("player_id", manor.player_id if manor != null else "player_01"))
	var tick_id: int = clock.current_tick_id if clock != null else 0
	var day_id: int = clock.get_day_id() if clock != null else 0
	var season: String = clock.get_season() if clock != null else "SPRING"

	var adapt_bp: int = get_player_adaptation(pid)
	if player_state.has("adaptation_factor_bp"):
		adapt_bp = clampi(_to_int(player_state.get("adaptation_factor_bp", adapt_bp), adapt_bp), ADAPTATION_MIN_BP, ADAPTATION_MAX_BP)
		set_player_adaptation(pid, adapt_bp)

	var wealth: int = compute_manor_wealth(manor)
	var retainers: int = manor.get_retainer_count() if manor != null else _to_int(player_state.get("retainers", 1), 1)
	var troops: int = manor.household_troops if manor != null else _to_int(player_state.get("troops", 100), 100)
	var threat_score: int = calc_threat_score(wealth, retainers, troops, adapt_bp)

	var entity_hash: int = StateHasher.crc32_bytes(pid.to_utf8_buffer())
	var roll_bp: int = DeterministicRNG.roll_bp(world_seed, tick_id, entity_hash, 8301)

	# Persona pacing & probabilities (bp)
	var threat_prob_bp: int = 3000
	var opp_prob_bp: int = 3000
	var intensity_pm: int = 1000

	if persona_id == "ST_SIMA_QIAN":
		# 6-day cycle: days 0..3 ramp tension, days 4..5 guaranteed calm/opportunity window
		var phase_day: int = day_id % 6
		if phase_day >= 4:
			threat_prob_bp = 0
			opp_prob_bp = 7000
		else:
			threat_prob_bp = 2500 + phase_day * 1000
			opp_prob_bp = 2000
	elif persona_id == "ST_DONG_ZHUO":
		var chaos_roll: int = DeterministicRNG.roll_range(world_seed, tick_id, entity_hash, 8302, 500, 2200)
		intensity_pm = chaos_roll
		threat_prob_bp = 4200
		opp_prob_bp = 2800
	elif persona_id == "ST_WEN_JING":
		threat_prob_bp = 1500
		opp_prob_bp = 5400
		intensity_pm = 650

	# Truce shield suppresses hostile raids
	if manor != null and manor.is_truce_active(tick_id):
		threat_prob_bp = 0

	var chosen_category: String = "CALM"
	var event_code: String = "PEACEFUL_DAY"
	var event_payload: Dictionary = {
		"tick_id": tick_id,
		"day_id": day_id,
		"season": season,
		"player_id": pid,
		"manor_id": manor.manor_id if manor != null else "",
		"persona_id": persona_id,
		"threat_score": threat_score,
		"adaptation_bp": adapt_bp
	}

	if roll_bp < threat_prob_bp:
		chosen_category = "THREAT"
		var sub_r: int = DeterministicRNG.roll_range(world_seed, tick_id, entity_hash, 8303, 0, 2)
		if sub_r == 0:
			event_code = "YELLOW_TURBAN_RAID"
			@warning_ignore("integer_division")
			var raider_cnt: int = clampi((threat_score * intensity_pm) / 2500, 30, 1500)
			event_payload["raider_troops"] = raider_cnt
			event_payload["host_node_id"] = manor.host_node_id if manor != null else "ye_county"
		elif sub_r == 1:
			event_code = "LOCUST_FAMINE" if season == "SUMMER" else "BANDIT_EXTORTION"
			event_payload["grain_loss_bp"] = 1000
		else:
			event_code = "IMPERIAL_LEVY"
			event_payload["coin_demand"] = maxi(100, threat_score / 2)

		event_payload["event_code"] = event_code
		if event_bus != null:
			var _seq_t: int = event_bus.emit(EVENT_STORYTELLER_THREAT, event_payload, tick_id)
	elif roll_bp < threat_prob_bp + opp_prob_bp:
		chosen_category = "OPPORTUNITY"
		var sub_o: int = DeterministicRNG.roll_range(world_seed, tick_id, entity_hash, 8304, 0, 2)
		if sub_o == 0:
			event_code = "WANDERING_SAGE_VISIT"
		elif sub_o == 1:
			event_code = "WESTERN_CARAVAN_ARRIVAL"
			event_payload["bonus_coin"] = 250
		else:
			event_code = "BUMPER_HARVEST" if season == "AUTUMN" else "IMPERIAL_SECRET_EDICT"
			event_payload["bonus_grain"] = 300

		event_payload["event_code"] = event_code
		if event_bus != null:
			var _seq_o: int = event_bus.emit(EVENT_STORYTELLER_OPPORTUNITY, event_payload, tick_id)
	else:
		event_payload["event_code"] = "PEACEFUL_DAY"

	var summary: Dictionary = {
		"tick_id": tick_id,
		"day_id": day_id,
		"player_id": pid,
		"persona_id": persona_id,
		"category": chosen_category,
		"event_code": event_code,
		"threat_score": threat_score,
		"adaptation_bp": adapt_bp,
		"roll_bp": roll_bp,
		"payload": event_payload
	}
	event_log.append(summary)
	return summary


func to_dict() -> Dictionary:
	var adapt_copy: Dictionary = {}
	var pids: Array[String] = []
	for k: Variant in player_adaptation_bp.keys():
		pids.append(str(k))
	pids.sort()
	for pid: String in pids:
		adapt_copy[pid] = get_player_adaptation(pid)

	var log_copy: Array[Dictionary] = []
	for entry: Dictionary in event_log:
		log_copy.append(entry.duplicate(true))

	return {
		"persona_id": persona_id,
		"era_scale_bp": era_scale_bp,
		"player_adaptation_bp": adapt_copy,
		"event_log": log_copy
	}


static func from_dict(data: Dictionary) -> StorytellerEngine:
	var eng: StorytellerEngine = StorytellerEngine.new(
		str(data.get("persona_id", "ST_SIMA_QIAN")),
		_to_int(data.get("era_scale_bp", 1000), 1000)
	)
	var ad_var: Variant = data.get("player_adaptation_bp", {})
	if ad_var is Dictionary:
		var ad_d: Dictionary = ad_var
		for k: Variant in ad_d.keys():
			eng.set_player_adaptation(str(k), _to_int(ad_d[k], ADAPTATION_DEFAULT_BP))

	var log_var: Variant = data.get("event_log", [])
	if log_var is Array:
		var log_arr: Array = log_var
		for item: Variant in log_arr:
			if item is Dictionary:
				var ld: Dictionary = item
				eng.event_log.append(ld.duplicate(true))
	return eng
