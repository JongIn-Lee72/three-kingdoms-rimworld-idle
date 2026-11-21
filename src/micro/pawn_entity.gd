class_name PawnEntity
extends RefCounted

const STAT_KEYS: Array[String] = ["LEA", "MAR", "INT", "POL", "CHA"]
const NEED_KEYS: Array[String] = ["FOOD", "REST", "MORALE", "LOYALTY", "AMBITION"]
const WORK_DOMAINS: Array[String] = [
	"LOGISTICS",
	"PATROL",
	"AGRICULTURE",
	"TRAINING",
	"CRAFTING",
	"RESEARCH",
	"DIPLOMACY"
]
const SHICHEN_ACTIVITIES: Array[String] = [
	"WORK",
	"DRILL",
	"RECREATION",
	"SLEEP",
	"ANYTHING"
]
const PAWN_STATES: Array[String] = [
	"IN_MANOR",
	"ON_EXPEDITION",
	"WOUNDED",
	"CAPTURED"
]
const HEALTH_STATES: Array[String] = [
	"HEALTHY",
	"LIGHT_WOUND",
	"SEVERE_WOUND",
	"SCARRED"
]
const MENTAL_STATES: Array[String] = [
	"NORMAL",
	"BREAK_MINOR_BINGE",
	"BREAK_MINOR_SECLUSION",
	"BREAK_MAJOR_CHARGE",
	"BREAK_MAJOR_EMBEZZLE",
	"BREAK_EXTREME_DESERTION",
	"BREAK_EXTREME_MUTINY",
	"CATHARSIS",
	"AWAKENED_STRATAGEM",
	"AWAKENED_VALOR",
	"AWAKENED_FORGING",
	"AWAKENED_HEARTS"
]
const AWAKENED_STATES: Array[String] = [
	"AWAKENED_STRATAGEM",
	"AWAKENED_VALOR",
	"AWAKENED_FORGING",
	"AWAKENED_HEARTS"
]

const PASSION_DULL_PM: int = 750
const PASSION_NORMAL_PM: int = 1000
const PASSION_SINGLE_PM: int = 1250
const PASSION_DOUBLE_PM: int = 1500

const CATHARSIS_MOOD_BONUS: int = 35
const CATHARSIS_DURATION_TICKS: int = 48
const AWAKENING_STREAK_REQUIRED: int = 12
const AWAKENING_DURATION_TICKS: int = 24
const HANGOVER_DURATION_TICKS: int = 12

# Trait stat bonuses/penalties (used in effective stat computation)
const TRAIT_STAT_MODS: Dictionary = {
	"T_CHIVALROUS": {"CHA": 5, "MAR": 3},
	"T_AMBITIOUS": {"LEA": 4, "POL": 4},
	"T_CAUTIOUS": {"INT": 5, "LEA": 3, "MAR": -3},
	"T_DRINKER": {"MAR": 5, "CHA": 4, "POL": -4},
	"T_MYSTIC": {"INT": 8, "MAR": -5},
	"T_UNSELFISH": {"POL": 5, "CHA": 5},
	"T_GREEDY": {"POL": 3, "CHA": -6},
	"T_FIERCE": {"MAR": 8, "INT": -6},
	"T_AGRARIAN": {"POL": 6, "LEA": 2},
	"T_SCHOLAR": {"INT": 4, "CHA": 7, "MAR": -8}
}

var pawn_id: String = ""
var owner_player_id: String = ""
var manor_id: String = ""
var name: String = ""
var courtesy_name: String = ""
var epithet: String = ""
var is_avatar: bool = false
var origin_archetype: String = "ORIGIN_CHIVALROUS_HERO"

var state: String = "IN_MANOR"
var health_state: String = "HEALTHY"
var wound_recovery_pm: int = 0
var scar_count: int = 0
var offline_bribe_immune_until_tick: int = 0

var grid_x: int = 16
var grid_y: int = 16
var current_job: String = "IDLE_STUDY_OR_GUARD"
var job_progress_pm: int = 0

var stats: Dictionary = {
	"LEA": 64,
	"MAR": 64,
	"INT": 64,
	"POL": 64,
	"CHA": 64
}
var passions_pm: Dictionary = {
	"LEA": 1000,
	"MAR": 1000,
	"INT": 1000,
	"POL": 1000,
	"CHA": 1000
}
var stat_xp: Dictionary = {
	"LEA": 0,
	"MAR": 0,
	"INT": 0,
	"POL": 0,
	"CHA": 0
}
var stat_xp_rem: Dictionary = {
	"LEA": 0,
	"MAR": 0,
	"INT": 0,
	"POL": 0,
	"CHA": 0
}

var traits: Array[String] = []
var needs_bp: Dictionary = {
	"FOOD": 8000,
	"REST": 8000,
	"MORALE": 7500,
	"LOYALTY": 8000,
	"AMBITION": 8000
}
var expected_rank: int = 1
var current_rank: int = 1
var ticks_since_wine: int = 0

var mood: int = 55
var mood_target: int = 55
var thoughts: Array[Dictionary] = []

var mental_state: String = "NORMAL"
var mental_state_ticks: int = 0
var high_mood_streak_ticks: int = 0
var hangover_ticks: int = 0

var work_priorities: Dictionary = {
	"LOGISTICS": 2,
	"PATROL": 2,
	"AGRICULTURE": 1,
	"TRAINING": 3,
	"CRAFTING": 3,
	"RESEARCH": 3,
	"DIPLOMACY": 4
}
var daily_schedule: Array[String] = [
	"SLEEP", "SLEEP", "SLEEP", "DRILL",
	"WORK", "WORK", "WORK", "WORK",
	"WORK", "RECREATION", "ANYTHING", "SLEEP"
]


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


func _init(p_id: String = "", p_name: String = "Retainer", p_is_avatar: bool = false) -> void:
	pawn_id = p_id
	name = p_name
	is_avatar = p_is_avatar


func get_entity_hash_id() -> int:
	return StateHasher.crc32_bytes(pawn_id.to_utf8_buffer())


func get_stat(stat_key: String) -> int:
	return clampi(_to_int(stats.get(stat_key, 50), 50), 1, DtoSchemas.STAT_MAX_EFFECTIVE)


func set_stat(stat_key: String, value: int) -> void:
	if not STAT_KEYS.has(stat_key):
		return
	stats[stat_key] = clampi(value, 1, DtoSchemas.STAT_MAX_EFFECTIVE)


func get_effective_stat(stat_key: String) -> int:
	var val: int = get_stat(stat_key)
	for tr: String in traits:
		if TRAIT_STAT_MODS.has(tr):
			var mods_var: Variant = TRAIT_STAT_MODS[tr]
			if mods_var is Dictionary:
				var mods: Dictionary = mods_var
				val += _to_int(mods.get(stat_key, 0), 0)
	if mental_state == "AWAKENED_VALOR":
		if stat_key == "MAR":
			val += 15
		elif stat_key == "LEA":
			val += 10
	return clampi(val, 1, DtoSchemas.STAT_MAX_EFFECTIVE)


func get_passion_pm(stat_key: String) -> int:
	var pm: int = _to_int(passions_pm.get(stat_key, PASSION_NORMAL_PM), PASSION_NORMAL_PM)
	if pm != PASSION_DULL_PM and pm != PASSION_NORMAL_PM and pm != PASSION_SINGLE_PM and pm != PASSION_DOUBLE_PM:
		return PASSION_NORMAL_PM
	return pm


func set_passion_pm(stat_key: String, pm: int) -> void:
	if not STAT_KEYS.has(stat_key):
		return
	if pm == PASSION_DULL_PM or pm == PASSION_NORMAL_PM or pm == PASSION_SINGLE_PM or pm == PASSION_DOUBLE_PM:
		passions_pm[stat_key] = pm


static func xp_required_for_next(current_stat: int) -> int:
	if current_stat >= DtoSchemas.STAT_MAX_EFFECTIVE:
		return 999999999
	# Deterministic integer approximation of max(50, floor(100 * 1.12^(S - 50)))
	var scale: int = 1000000
	var val_scaled: int = 100 * scale
	if current_stat > 50:
		var steps: int = current_stat - 50
		for _i: int in range(steps):
			@warning_ignore("integer_division")
			val_scaled = (val_scaled * 112) / 100
			if val_scaled > 1000000 * scale:
				val_scaled = 1000000 * scale
				break
	elif current_stat < 50:
		var steps_down: int = 50 - current_stat
		for _i: int in range(steps_down):
			@warning_ignore("integer_division")
			val_scaled = (val_scaled * 100) / 112
	@warning_ignore("integer_division")
	var req: int = val_scaled / scale
	return maxi(50, req)


func add_stat_xp(stat_key: String, base_xp: int) -> bool:
	if base_xp <= 0 or not STAT_KEYS.has(stat_key):
		return false
	var cur_stat: int = get_stat(stat_key)
	if cur_stat >= DtoSchemas.STAT_MAX_EFFECTIVE:
		return false

	var alpha_pm: int = get_passion_pm(stat_key)
	var mood_bonus_pm: int = 1000 + 5 * maxi(0, mood - 50)
	var prev_rem: int = _to_int(stat_xp_rem.get(stat_key, 0), 0)
	var num: int = base_xp * alpha_pm * mood_bonus_pm + prev_rem
	@warning_ignore("integer_division")
	var gain: int = num / 1000000
	stat_xp_rem[stat_key] = num % 1000000
	if gain <= 0:
		return false

	var total_xp: int = _to_int(stat_xp.get(stat_key, 0), 0) + gain
	var leveled: bool = false
	var req: int = xp_required_for_next(cur_stat)
	while total_xp >= req and cur_stat < DtoSchemas.STAT_MAX_EFFECTIVE:
		total_xp -= req
		cur_stat += 1
		stats[stat_key] = cur_stat
		leveled = true
		req = xp_required_for_next(cur_stat)
	stat_xp[stat_key] = total_xp
	return leveled


func has_trait(trait_id: String) -> bool:
	return traits.has(trait_id)


func get_stipend_multiplier_pm() -> int:
	var mult_pm: int = 1000
	if has_trait("T_CHIVALROUS"):
		@warning_ignore("integer_division")
		mult_pm = (mult_pm * 800) / 1000
	if has_trait("T_AMBITIOUS"):
		@warning_ignore("integer_division")
		mult_pm = (mult_pm * 1300) / 1000
	if has_trait("T_UNSELFISH"):
		@warning_ignore("integer_division")
		mult_pm = (mult_pm * 500) / 1000
	if has_trait("T_GREEDY"):
		@warning_ignore("integer_division")
		mult_pm = (mult_pm * 2000) / 1000
	return maxi(100, mult_pm)


func get_work_efficiency_pm(domain: String) -> int:
	var eff_pm: int = 1000
	if health_state == "LIGHT_WOUND":
		@warning_ignore("integer_division")
		eff_pm = (eff_pm * 850) / 1000
	elif health_state == "SEVERE_WOUND":
		@warning_ignore("integer_division")
		eff_pm = (eff_pm * 550) / 1000

	var food_bp: int = get_need("FOOD")
	if food_bp < 1500:
		@warning_ignore("integer_division")
		eff_pm = (eff_pm * 700) / 1000

	var rest_bp: int = get_need("REST")
	if rest_bp < 1500:
		@warning_ignore("integer_division")
		eff_pm = (eff_pm * 600) / 1000
	elif rest_bp <= 3000:
		@warning_ignore("integer_division")
		eff_pm = (eff_pm * 850) / 1000

	if hangover_ticks > 0:
		@warning_ignore("integer_division")
		eff_pm = (eff_pm * 750) / 1000

	if domain == "RESEARCH" and has_trait("T_MYSTIC"):
		@warning_ignore("integer_division")
		eff_pm = (eff_pm * 1350) / 1000
	if domain == "AGRICULTURE" and has_trait("T_AGRARIAN"):
		@warning_ignore("integer_division")
		eff_pm = (eff_pm * 1350) / 1000
	if domain == "RESEARCH" and origin_archetype == "ORIGIN_PURE_SCHOLAR":
		@warning_ignore("integer_division")
		eff_pm = (eff_pm * 1150) / 1000
	if domain == "RESEARCH" and mental_state == "AWAKENED_STRATAGEM":
		@warning_ignore("integer_division")
		eff_pm = (eff_pm * 2500) / 1000

	return maxi(100, eff_pm)


func get_ambition_drift_mult_pm() -> int:
	return 1750 if has_trait("T_AMBITIOUS") else 1000


func get_retreat_threshold_bonus_bp() -> int:
	var bonus: int = 0
	if has_trait("T_CAUTIOUS"):
		bonus += 1500
	if has_trait("T_FIERCE"):
		bonus -= 1500
	return bonus


func needs_wine() -> bool:
	return has_trait("T_DRINKER")


func refuses_assassination() -> bool:
	return has_trait("T_CHIVALROUS")


func refuses_reckless_duel() -> bool:
	return has_trait("T_CAUTIOUS")


func immune_to_bribery() -> bool:
	return has_trait("T_UNSELFISH")


func is_in_mental_break() -> bool:
	return mental_state.begins_with("BREAK_")


func is_awakened() -> bool:
	return AWAKENED_STATES.has(mental_state)


func get_need(need_key: String) -> int:
	return clampi(_to_int(needs_bp.get(need_key, 5000), 5000), 0, DtoSchemas.SCALE_BP)


func set_need(need_key: String, val: int) -> void:
	if not NEED_KEYS.has(need_key):
		return
	needs_bp[need_key] = clampi(val, 0, DtoSchemas.SCALE_BP)


func add_need(need_key: String, delta: int) -> void:
	set_need(need_key, get_need(need_key) + delta)


func get_work_priority(domain: String) -> int:
	return clampi(_to_int(work_priorities.get(domain, 0), 0), 0, 4)


func set_work_priority(domain: String, priority: int) -> void:
	if not WORK_DOMAINS.has(domain):
		return
	work_priorities[domain] = clampi(priority, 0, 4)


func get_schedule_activity(shichen_idx: int) -> String:
	var idx: int = clampi(shichen_idx, 0, 11)
	if idx < daily_schedule.size():
		return daily_schedule[idx]
	return "ANYTHING"


func set_schedule_activity(shichen_idx: int, activity: String) -> void:
	if shichen_idx < 0 or shichen_idx >= 12:
		return
	if not SHICHEN_ACTIVITIES.has(activity):
		return
	while daily_schedule.size() < 12:
		daily_schedule.append("ANYTHING")
	daily_schedule[shichen_idx] = activity


func add_thought(thought_id: String, mood_delta: int, remaining_ticks: int) -> void:
	if thought_id.is_empty() or remaining_ticks <= 0:
		return
	for i: int in range(thoughts.size()):
		var entry: Dictionary = thoughts[i]
		if str(entry.get("id", "")) == thought_id:
			thoughts[i] = {
				"id": thought_id,
				"mood_delta": mood_delta,
				"remaining_ticks": remaining_ticks
			}
			return
	thoughts.append({
		"id": thought_id,
		"mood_delta": mood_delta,
		"remaining_ticks": remaining_ticks
	})


func has_thought(thought_id: String) -> bool:
	for entry: Dictionary in thoughts:
		if str(entry.get("id", "")) == thought_id:
			return true
	return false


func remove_thought(thought_id: String) -> void:
	var kept: Array[Dictionary] = []
	for entry: Dictionary in thoughts:
		if str(entry.get("id", "")) != thought_id:
			kept.append(entry)
	thoughts = kept


func tick_thoughts() -> void:
	var kept: Array[Dictionary] = []
	for entry: Dictionary in thoughts:
		var rem: int = _to_int(entry.get("remaining_ticks", 0), 0) - 1
		if rem > 0:
			kept.append({
				"id": str(entry.get("id", "")),
				"mood_delta": _to_int(entry.get("mood_delta", 0), 0),
				"remaining_ticks": rem
			})
	thoughts = kept


func compute_needs_mood_delta() -> int:
	var delta: int = 0
	var food_bp: int = get_need("FOOD")
	if food_bp > 8500:
		delta += 8
	elif food_bp >= 1500 and food_bp <= 3000:
		delta -= 8
	elif food_bp < 1500:
		delta -= 25

	var rest_bp: int = get_need("REST")
	if rest_bp > 8500:
		delta += 6
	elif rest_bp >= 1500 and rest_bp <= 3000:
		delta -= 6
	elif rest_bp < 1500:
		delta -= 20

	var morale_bp: int = get_need("MORALE")
	if morale_bp > 8000:
		delta += 10
	elif morale_bp < 2500:
		delta -= 15

	var ambition_bp: int = get_need("AMBITION")
	if ambition_bp < 3000:
		delta -= 18

	return delta


func compute_thoughts_mood_delta() -> int:
	var delta: int = 0
	for entry: Dictionary in thoughts:
		delta += _to_int(entry.get("mood_delta", 0), 0)
	return delta


func compute_target_mood(env_bonus: int = 0) -> int:
	var raw_target: int = 50 + compute_needs_mood_delta() + compute_thoughts_mood_delta() + env_bonus
	return clampi(raw_target, 0, 100)


func step_mood(env_bonus: int = 0, ticks_elapsed: int = 1) -> int:
	mood_target = compute_target_mood(env_bonus)
	var max_step: int = 4 * maxi(1, ticks_elapsed)
	var diff: int = clampi(mood_target - mood, -max_step, max_step)
	mood = clampi(mood + diff, 0, 100)
	return mood


func trigger_mental_break(break_state: String, duration_ticks: int) -> void:
	if not MENTAL_STATES.has(break_state) or not break_state.begins_with("BREAK_"):
		return
	mental_state = break_state
	mental_state_ticks = maxi(1, duration_ticks)


func end_mental_break(env_bonus: int = 0) -> void:
	# Guardrail #2: IMMEDIATELY apply +35 Mood Catharsis buffer (CATHARSIS, 48 ticks)
	add_thought("CATHARSIS", CATHARSIS_MOOD_BONUS, CATHARSIS_DURATION_TICKS)
	if mental_state == "BREAK_MINOR_BINGE":
		hangover_ticks = HANGOVER_DURATION_TICKS
	mental_state = "CATHARSIS"
	mental_state_ticks = CATHARSIS_DURATION_TICKS
	mood_target = compute_target_mood(env_bonus)


func step_mental_and_awakening(
	world_seed: int,
	tick_id: int,
	env_bonus: int = 0,
	ticks_elapsed: int = 1
) -> Array[String]:
	var events: Array[String] = []
	var steps: int = maxi(1, ticks_elapsed)
	for _s: int in range(steps):
		tick_thoughts()
		if hangover_ticks > 0:
			hangover_ticks -= 1
	var _new_mood: int = step_mood(env_bonus, steps)

	if mental_state != "NORMAL":
		mental_state_ticks = maxi(0, mental_state_ticks - steps)
		if mental_state_ticks == 0:
			if is_in_mental_break():
				end_mental_break(env_bonus)
				events.append("MENTAL_BREAK_ENDED_CATHARSIS")
			else:
				mental_state = "NORMAL"
				events.append("MENTAL_STATE_NORMALIZED")
		return events

	# Normal state: check Heroic Awakening (Mood > 85 sustained >= 12 ticks)
	if mood > 85:
		high_mood_streak_ticks += steps
		if high_mood_streak_ticks >= AWAKENING_STREAK_REQUIRED:
			var roll_aw: int = DeterministicRNG.roll_bp(
				world_seed, tick_id, get_entity_hash_id(), 9101
			)
			var threshold: int = 2500
			if has_trait("T_MYSTIC"):
				threshold = 4000
			if roll_aw < threshold or high_mood_streak_ticks >= 24:
				var idx_roll: int = DeterministicRNG.roll_range(
					world_seed, tick_id, get_entity_hash_id(), 9102, 0, 99
				)
				var chosen_aw: String = AWAKENED_STATES[idx_roll % AWAKENED_STATES.size()]
				if has_trait("T_MYSTIC") and idx_roll < 50:
					chosen_aw = "AWAKENED_STRATAGEM"
				mental_state = chosen_aw
				mental_state_ticks = AWAKENING_DURATION_TICKS
				high_mood_streak_ticks = 0
				events.append(chosen_aw)
				return events
	else:
		high_mood_streak_ticks = 0

	# Mental Break check when Mood < 35 (cannot trigger during CATHARSIS)
	if mood < 35 and state == "IN_MANOR":
		var break_roll: int = DeterministicRNG.roll_bp(
			world_seed, tick_id, get_entity_hash_id(), 9201
		)
		var prob_bp: int = 0
		if mood < 10:
			prob_bp = 1667 * steps  # MTTH ~6 ticks
		elif mood < 20:
			prob_bp = 625 * steps   # MTTH ~16 ticks
		else:
			prob_bp = 278 * steps   # MTTH ~36 ticks

		if break_roll < mini(10000, prob_bp):
			var sub_roll: int = DeterministicRNG.roll_range(
				world_seed, tick_id, get_entity_hash_id(), 9202, 0, 99
			)
			var chosen_break: String = "BREAK_MINOR_SECLUSION"
			var dur: int = 16
			if mood < 10:
				if get_need("LOYALTY") < 2500 and sub_roll < 50:
					chosen_break = "BREAK_EXTREME_MUTINY"
					dur = 8
				else:
					chosen_break = "BREAK_EXTREME_DESERTION"
					dur = 6
			elif mood < 20:
				if has_trait("T_GREEDY") or sub_roll < 50:
					chosen_break = "BREAK_MAJOR_EMBEZZLE"
					dur = 8
				else:
					chosen_break = "BREAK_MAJOR_CHARGE"
					dur = 10
			else:
				if has_trait("T_DRINKER") or sub_roll < 50:
					chosen_break = "BREAK_MINOR_BINGE"
					dur = 12
				else:
					chosen_break = "BREAK_MINOR_SECLUSION"
					dur = 16
			trigger_mental_break(chosen_break, dur)
			events.append(chosen_break)

	return events


func to_dict() -> Dictionary:
	var sorted_thoughts: Array[Dictionary] = []
	for t_entry: Dictionary in thoughts:
		sorted_thoughts.append({
			"id": str(t_entry.get("id", "")),
			"mood_delta": _to_int(t_entry.get("mood_delta", 0), 0),
			"remaining_ticks": _to_int(t_entry.get("remaining_ticks", 0), 0)
		})

	var stats_copy: Dictionary = {}
	for sk: String in STAT_KEYS:
		stats_copy[sk] = get_stat(sk)

	var passions_copy: Dictionary = {}
	for sk: String in STAT_KEYS:
		passions_copy[sk] = get_passion_pm(sk)

	var xp_copy: Dictionary = {}
	var xp_rem_copy: Dictionary = {}
	for sk: String in STAT_KEYS:
		xp_copy[sk] = _to_int(stat_xp.get(sk, 0), 0)
		xp_rem_copy[sk] = _to_int(stat_xp_rem.get(sk, 0), 0)

	var needs_copy: Dictionary = {}
	for nk: String in NEED_KEYS:
		needs_copy[nk] = get_need(nk)

	var prio_copy: Dictionary = {}
	for dk: String in WORK_DOMAINS:
		prio_copy[dk] = get_work_priority(dk)

	var sched_copy: Array[String] = []
	for i: int in range(12):
		sched_copy.append(get_schedule_activity(i))

	var traits_copy: Array[String] = []
	for tr: String in traits:
		traits_copy.append(tr)

	return {
		"pawn_id": pawn_id,
		"owner_player_id": owner_player_id,
		"manor_id": manor_id,
		"name": name,
		"courtesy_name": courtesy_name,
		"epithet": epithet,
		"is_avatar": is_avatar,
		"origin_archetype": origin_archetype,
		"state": state,
		"health_state": health_state,
		"wound_recovery_pm": wound_recovery_pm,
		"scar_count": scar_count,
		"offline_bribe_immune_until_tick": offline_bribe_immune_until_tick,
		"grid_x": grid_x,
		"grid_y": grid_y,
		"current_job": current_job,
		"job_progress_pm": job_progress_pm,
		"stats": stats_copy,
		"passions_pm": passions_copy,
		"stat_xp": xp_copy,
		"stat_xp_rem": xp_rem_copy,
		"traits": traits_copy,
		"needs_bp": needs_copy,
		"expected_rank": expected_rank,
		"current_rank": current_rank,
		"ticks_since_wine": ticks_since_wine,
		"mood": mood,
		"mood_target": mood_target,
		"thoughts": sorted_thoughts,
		"mental_state": mental_state,
		"mental_state_ticks": mental_state_ticks,
		"high_mood_streak_ticks": high_mood_streak_ticks,
		"hangover_ticks": hangover_ticks,
		"work_priorities": prio_copy,
		"daily_schedule": sched_copy
	}


static func from_dict(data: Dictionary) -> PawnEntity:
	var p: PawnEntity = PawnEntity.new(
		str(data.get("pawn_id", "")),
		str(data.get("name", "Retainer")),
		_to_bool(data.get("is_avatar", false), false)
	)
	p.owner_player_id = str(data.get("owner_player_id", ""))
	p.manor_id = str(data.get("manor_id", ""))
	p.courtesy_name = str(data.get("courtesy_name", ""))
	p.epithet = str(data.get("epithet", ""))
	p.origin_archetype = str(data.get("origin_archetype", "ORIGIN_CHIVALROUS_HERO"))

	var st: String = str(data.get("state", "IN_MANOR"))
	p.state = st if PAWN_STATES.has(st) else "IN_MANOR"

	var hs: String = str(data.get("health_state", "HEALTHY"))
	p.health_state = hs if HEALTH_STATES.has(hs) else "HEALTHY"
	p.wound_recovery_pm = clampi(_to_int(data.get("wound_recovery_pm", 0), 0), 0, 1000)
	p.scar_count = maxi(0, _to_int(data.get("scar_count", 0), 0))
	p.offline_bribe_immune_until_tick = maxi(0, _to_int(data.get("offline_bribe_immune_until_tick", 0), 0))

	p.grid_x = clampi(_to_int(data.get("grid_x", 16), 16), 0, DtoSchemas.MANOR_GRID_SIZE - 1)
	p.grid_y = clampi(_to_int(data.get("grid_y", 16), 16), 0, DtoSchemas.MANOR_GRID_SIZE - 1)
	p.current_job = str(data.get("current_job", "IDLE_STUDY_OR_GUARD"))
	p.job_progress_pm = clampi(_to_int(data.get("job_progress_pm", 0), 0), 0, 999)

	var stats_var: Variant = data.get("stats", {})
	if stats_var is Dictionary:
		var sd: Dictionary = stats_var
		for sk: String in STAT_KEYS:
			p.set_stat(sk, _to_int(sd.get(sk, 64), 64))

	var pass_var: Variant = data.get("passions_pm", {})
	if pass_var is Dictionary:
		var pd: Dictionary = pass_var
		for sk: String in STAT_KEYS:
			p.set_passion_pm(sk, _to_int(pd.get(sk, PASSION_NORMAL_PM), PASSION_NORMAL_PM))

	var xp_var: Variant = data.get("stat_xp", {})
	if xp_var is Dictionary:
		var xd: Dictionary = xp_var
		for sk: String in STAT_KEYS:
			p.stat_xp[sk] = maxi(0, _to_int(xd.get(sk, 0), 0))

	var xp_rem_var: Variant = data.get("stat_xp_rem", {})
	if xp_rem_var is Dictionary:
		var xrd: Dictionary = xp_rem_var
		for sk: String in STAT_KEYS:
			p.stat_xp_rem[sk] = maxi(0, _to_int(xrd.get(sk, 0), 0))

	p.traits.clear()
	var tr_var: Variant = data.get("traits", [])
	if tr_var is Array:
		var tr_arr: Array = tr_var
		for item: Variant in tr_arr:
			var ts: String = str(item)
			if DtoSchemas.TRAIT_IDS.has(ts) and not p.traits.has(ts):
				p.traits.append(ts)

	var needs_var: Variant = data.get("needs_bp", {})
	if needs_var is Dictionary:
		var nd: Dictionary = needs_var
		for nk: String in NEED_KEYS:
			p.set_need(nk, _to_int(nd.get(nk, 7500), 7500))

	p.expected_rank = clampi(_to_int(data.get("expected_rank", 1), 1), 1, 9)
	p.current_rank = clampi(_to_int(data.get("current_rank", 1), 1), 1, 9)
	p.ticks_since_wine = maxi(0, _to_int(data.get("ticks_since_wine", 0), 0))
	p.mood = clampi(_to_int(data.get("mood", 55), 55), 0, 100)
	p.mood_target = clampi(_to_int(data.get("mood_target", 55), 55), 0, 100)

	p.thoughts.clear()
	var th_var: Variant = data.get("thoughts", [])
	if th_var is Array:
		var th_arr: Array = th_var
		for item: Variant in th_arr:
			if item is Dictionary:
				var td: Dictionary = item
				p.add_thought(
					str(td.get("id", "")),
					_to_int(td.get("mood_delta", 0), 0),
					_to_int(td.get("remaining_ticks", 0), 0)
				)

	var ms: String = str(data.get("mental_state", "NORMAL"))
	p.mental_state = ms if MENTAL_STATES.has(ms) else "NORMAL"
	p.mental_state_ticks = maxi(0, _to_int(data.get("mental_state_ticks", 0), 0))
	p.high_mood_streak_ticks = maxi(0, _to_int(data.get("high_mood_streak_ticks", 0), 0))
	p.hangover_ticks = maxi(0, _to_int(data.get("hangover_ticks", 0), 0))

	var wp_var: Variant = data.get("work_priorities", {})
	if wp_var is Dictionary:
		var wpd: Dictionary = wp_var
		for dk: String in WORK_DOMAINS:
			p.set_work_priority(dk, _to_int(wpd.get(dk, 2), 2))

	var ds_var: Variant = data.get("daily_schedule", [])
	if ds_var is Array:
		var dsa: Array = ds_var
		for idx: int in range(mini(12, dsa.size())):
			p.set_schedule_activity(idx, str(dsa[idx]))

	return p
