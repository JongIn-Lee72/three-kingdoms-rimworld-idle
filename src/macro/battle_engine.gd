class_name BattleEngine
extends RefCounted

const STANCES: Array[String] = ["AGGRESSIVE", "BALANCED", "CONSERVATIVE"]
const FORMATIONS: Array[String] = ["WEDGE", "SHIELD_WALL", "CRESCENT", "AMBUSH_LINE"]
const DUEL_POLICIES: Array[String] = ["ALWAYS", "ONLY_IF_ADVANTAGED", "NEVER"]
const PRISONER_POLICIES: Array[String] = ["RELEASE", "RECRUIT", "RANSOM", "EXECUTE"]
const STRATAGEM_TYPES: Array[String] = ["FIRE_ATTACK", "FLOOD", "AMBUSH", "CONFUSION"]
const WEATHER_TYPES: Array[String] = ["CLEAR", "WINDY", "RAIN", "FOG", "SNOW"]
const TERRAIN_TYPES: Array[String] = ["PLAINS", "HIGHWAY", "MOUNTAIN", "MOUNTAIN_PATH", "WATERWAY", "CITY"]

const MAX_ROUNDS: int = 12

# Piecewise-linear breakpoints (n, round(n^0.85 * 1000))
const POW085_BREAKPOINTS: Array[Array] = [
	[0, 0],
	[1, 1000],
	[2, 1803],
	[5, 3928],
	[10, 7079],
	[25, 15426],
	[50, 27807],
	[100, 50119],
	[200, 90347],
	[400, 162865],
	[600, 229873],
	[800, 293572],
	[1000, 354813],
	[1200, 414180],
	[1500, 500450],
	[1800, 584160],
	[2000, 638807],
	[3000, 901674],
	[5000, 1393215],
	[10000, 2511886],
	[20000, 4528093],
	[50000, 9867017],
	[100000, 17782794]
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


# Deterministic integer N^0.85 * 1000 approximation (strictly monotonic for n >= 0)
static func pow_085_pm(n: int) -> int:
	if n <= 0:
		return 0
	if n == 1:
		return 1000

	var last_idx: int = POW085_BREAKPOINTS.size() - 1
	var max_n: int = _to_int(POW085_BREAKPOINTS[last_idx][0], 100000)
	if n >= max_n:
		var max_val: int = _to_int(POW085_BREAKPOINTS[last_idx][1], 17782794)
		var prev_n: int = _to_int(POW085_BREAKPOINTS[last_idx - 1][0], 50000)
		var prev_val: int = _to_int(POW085_BREAKPOINTS[last_idx - 1][1], 9867017)
		var slope_num: int = max_val - prev_val
		var slope_den: int = max_n - prev_n
		@warning_ignore("integer_division")
		return max_val + ((n - max_n) * slope_num) / slope_den

	var lo: int = 0
	var hi: int = last_idx
	while lo + 1 < hi:
		@warning_ignore("integer_division")
		var mid: int = (lo + hi) / 2
		var mid_n: int = _to_int(POW085_BREAKPOINTS[mid][0], 0)
		if mid_n <= n:
			lo = mid
		else:
			hi = mid

	var n0: int = _to_int(POW085_BREAKPOINTS[lo][0], 0)
	var v0: int = _to_int(POW085_BREAKPOINTS[lo][1], 0)
	var n1: int = _to_int(POW085_BREAKPOINTS[hi][0], 1)
	var v1: int = _to_int(POW085_BREAKPOINTS[hi][1], 1000)
	if n == n0:
		return v0
	var dn: int = n1 - n0
	var dv: int = v1 - v0
	@warning_ignore("integer_division")
	var interp: int = v0 + ((n - n0) * dv) / dn
	return maxi(v0 + (n - n0), interp)


static func isqrt_int(n: int) -> int:
	if n <= 0:
		return 0
	var lo: int = 1
	var hi: int = mini(n, 3037000499)
	var ans: int = 1
	while lo <= hi:
		@warning_ignore("integer_division")
		var mid: int = lo + (hi - lo) / 2
		if mid <= n / mid:
			ans = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return ans


static func parse_doctrine(raw_doctrine: Dictionary) -> Dictionary:
	var raw_stance: String = str(raw_doctrine.get("engagement_stance", raw_doctrine.get("stance", "BALANCED")))
	var stance: String = "BALANCED"
	match raw_stance:
		"AGGRESSIVE", "PREEMPTIVE_STRIKE":
			stance = "AGGRESSIVE"
		"CONSERVATIVE", "DEFENSIVE_HOLD", "EVADE_ENGAGEMENT":
			stance = "CONSERVATIVE"
		_:
			stance = "BALANCED"

	var raw_form: String = str(raw_doctrine.get("formation", "SHIELD_WALL"))
	var formation: String = "SHIELD_WALL"
	match raw_form:
		"WEDGE", "ARROW_WEDGE":
			formation = "WEDGE"
		"CRESCENT", "CRANE_WING":
			formation = "CRESCENT"
		"AMBUSH_LINE", "LONG_SNAKE":
			formation = "AMBUSH_LINE"
		"SHIELD_WALL", "SQUARE_SHIELD", "FISH_SCALE":
			formation = "SHIELD_WALL"
		_:
			formation = "SHIELD_WALL"

	var raw_duel: String = str(raw_doctrine.get("duel_policy", "ONLY_IF_ADVANTAGED"))
	var duel_policy: String = "ONLY_IF_ADVANTAGED"
	match raw_duel:
		"ALWAYS", "ACCEPT_ALWAYS":
			duel_policy = "ALWAYS"
		"NEVER", "DECLINE_ALL":
			duel_policy = "NEVER"
		"ONLY_IF_ADVANTAGED", "ACCEPT_IF_ADVANTAGE":
			duel_policy = "ONLY_IF_ADVANTAGED"
		_:
			duel_policy = "ONLY_IF_ADVANTAGED"

	var raw_prisoner: String = str(raw_doctrine.get("prisoner_policy", "RECRUIT"))
	var prisoner_policy: String = "RECRUIT"
	match raw_prisoner:
		"RELEASE", "RELEASE_ALL":
			prisoner_policy = "RELEASE"
		"RANSOM", "RANSOM_RELEASE":
			prisoner_policy = "RANSOM"
		"EXECUTE", "ESCORT_TO_LORD":
			prisoner_policy = "EXECUTE"
		"RECRUIT", "RECRUIT_PERSUADE":
			prisoner_policy = "RECRUIT"
		_:
			prisoner_policy = "RECRUIT"

	var stratagem_enabled: bool = true
	if raw_doctrine.has("stratagem_enabled"):
		stratagem_enabled = _to_bool(raw_doctrine.get("stratagem_enabled", true), true)
	elif str(raw_doctrine.get("stratagem_policy", "")) == "NONE":
		stratagem_enabled = false

	return {
		"stance": stance,
		"formation": formation,
		"retreat_troop_bp": clampi(_to_int(raw_doctrine.get("retreat_troop_bp", 3000), 3000), 0, 9500),
		"retreat_morale_bp": clampi(_to_int(raw_doctrine.get("retreat_morale_bp", 2500), 2500), 0, 9500),
		"duel_policy": duel_policy,
		"stratagem_enabled": stratagem_enabled,
		"stratagem_policy": str(raw_doctrine.get("stratagem_policy", "FIRE_OR_FLOOD")),
		"prisoner_policy": prisoner_policy
	}


static func _extract_officer_stat(officer: Dictionary, key: String, fallback: int = 60) -> int:
	if officer.has(key):
		return clampi(_to_int(officer.get(key, fallback), fallback), 1, 120)
	match key:
		"MAR":
			return clampi(_to_int(officer.get("martial", fallback), fallback), 1, 120)
		"LEA":
			return clampi(_to_int(officer.get("leadership", fallback), fallback), 1, 120)
		"INT":
			return clampi(_to_int(officer.get("intelligence", fallback), fallback), 1, 120)
		"POL":
			return clampi(_to_int(officer.get("politics", fallback), fallback), 1, 120)
		"CHA":
			return clampi(_to_int(officer.get("charisma", fallback), fallback), 1, 120)
	return fallback


static func _officer_traits(officer: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var tv: Variant = officer.get("traits", [])
	if tv is Array:
		var arr: Array = tv
		for item: Variant in arr:
			out.append(str(item))
	return out


static func _get_lead_officer(army: Dictionary) -> Dictionary:
	var off_var: Variant = army.get("officers", [])
	if off_var is Array:
		var arr: Array = off_var
		if not arr.is_empty():
			var first_v: Variant = arr[0]
			if first_v is Dictionary:
				var d: Dictionary = first_v
				return d
	return {
		"pawn_id": str(army.get("lead_officer_id", "officer_default")),
		"MAR": _to_int(army.get("MAR", army.get("martial", 60)), 60),
		"LEA": _to_int(army.get("LEA", army.get("leadership", 60)), 60),
		"INT": _to_int(army.get("INT", army.get("intelligence", 60)), 60),
		"traits": army.get("traits", [])
	}


static func resolve_officer_duel(
	officer_a: Dictionary,
	officer_b: Dictionary,
	world_seed: int,
	tick_id: int,
	salt: int = 1
) -> Dictionary:
	var id_a: String = str(officer_a.get("pawn_id", officer_a.get("officer_id", "officer_a")))
	var id_b: String = str(officer_b.get("pawn_id", officer_b.get("officer_id", "officer_b")))
	var mar_a: int = _extract_officer_stat(officer_a, "MAR", 60)
	var mar_b: int = _extract_officer_stat(officer_b, "MAR", 60)
	var gear_a_pm: int = clampi(_to_int(officer_a.get("weapon_pm", officer_a.get("gear_pm", 1000)), 1000), 800, 1800)
	var gear_b_pm: int = clampi(_to_int(officer_b.get("weapon_pm", officer_b.get("gear_pm", 1000)), 1000), 800, 1800)
	var traits_a: Array[String] = _officer_traits(officer_a)
	var traits_b: Array[String] = _officer_traits(officer_b)

	var bonus_a: int = 0
	if traits_a.has("T_FIERCE"):
		bonus_a += 10
	if traits_a.has("T_DRINKER"):
		bonus_a += 8
	if traits_a.has("T_CAUTIOUS"):
		bonus_a -= 4

	var bonus_b: int = 0
	if traits_b.has("T_FIERCE"):
		bonus_b += 10
	if traits_b.has("T_DRINKER"):
		bonus_b += 8
	if traits_b.has("T_CAUTIOUS"):
		bonus_b -= 4

	var hp_a: int = 100
	var hp_b: int = 100
	var bouts: Array[Dictionary] = []
	var entity_hash: int = StateHasher.crc32_bytes((id_a + ":" + id_b).to_utf8_buffer())
	var winner_side: String = "DRAW"

	for bout_idx: int in range(1, 6):
		var roll_a: int = DeterministicRNG.roll_range(world_seed, tick_id, entity_hash, salt * 100 + bout_idx * 2, 0, 15)
		var roll_b: int = DeterministicRNG.roll_range(world_seed, tick_id, entity_hash, salt * 100 + bout_idx * 2 + 1, 0, 15)
		@warning_ignore("integer_division")
		var score_a: int = (mar_a * gear_a_pm) / 1000 + bonus_a + roll_a
		@warning_ignore("integer_division")
		var score_b: int = (mar_b * gear_b_pm) / 1000 + bonus_b + roll_b

		var dmg_to_b: int = 0
		var dmg_to_a: int = 0
		var bout_winner: String = "DRAW"
		if score_a > score_b:
			bout_winner = "A"
			dmg_to_b = clampi(14 + (score_a - score_b) / 2, 10, 45)
			hp_b = maxi(0, hp_b - dmg_to_b)
		elif score_b > score_a:
			bout_winner = "B"
			dmg_to_a = clampi(14 + (score_b - score_a) / 2, 10, 45)
			hp_a = maxi(0, hp_a - dmg_to_a)
		else:
			dmg_to_a = 8
			dmg_to_b = 8
			hp_a = maxi(0, hp_a - 8)
			hp_b = maxi(0, hp_b - 8)

		bouts.append({
			"bout": bout_idx,
			"score_a": score_a,
			"score_b": score_b,
			"dmg_to_a": dmg_to_a,
			"dmg_to_b": dmg_to_b,
			"hp_a_after": hp_a,
			"hp_b_after": hp_b,
			"winner": bout_winner
		})

		if hp_a <= 0 or hp_b <= 0:
			break

	if hp_a > hp_b:
		winner_side = "A"
	elif hp_b > hp_a:
		winner_side = "B"
	else:
		winner_side = "DRAW"

	var morale_swing_a_bp: int = 0
	var morale_swing_b_bp: int = 0
	var loser_injury: String = "HEALTHY"
	var loser_captured: bool = false

	if winner_side == "A":
		morale_swing_a_bp = 1800
		morale_swing_b_bp = -1800
		var cap_roll: int = DeterministicRNG.roll_bp(world_seed, tick_id, entity_hash, salt * 100 + 99)
		if hp_b == 0:
			loser_injury = "SEVERE_WOUND"
			loser_captured = cap_roll < 3500
		else:
			loser_injury = "LIGHT_WOUND"
			loser_captured = cap_roll < 1000
	elif winner_side == "B":
		morale_swing_a_bp = -1800
		morale_swing_b_bp = 1800
		var cap_roll_b: int = DeterministicRNG.roll_bp(world_seed, tick_id, entity_hash, salt * 100 + 99)
		if hp_a == 0:
			loser_injury = "SEVERE_WOUND"
			loser_captured = cap_roll_b < 3500
		else:
			loser_injury = "LIGHT_WOUND"
			loser_captured = cap_roll_b < 1000

	return {
		"officer_a_id": id_a,
		"officer_b_id": id_b,
		"bouts": bouts,
		"winner_side": winner_side,
		"winner_id": id_a if winner_side == "A" else (id_b if winner_side == "B" else ""),
		"hp_a": hp_a,
		"hp_b": hp_b,
		"morale_swing_a_bp": morale_swing_a_bp,
		"morale_swing_b_bp": morale_swing_b_bp,
		"loser_injury": loser_injury,
		"loser_captured": loser_captured
	}


static func resolve_stratagem(
	attacker_officer: Dictionary,
	defender_officer: Dictionary,
	stratagem_type: String,
	weather: String,
	terrain: String,
	world_seed: int,
	tick_id: int,
	salt: int = 1
) -> Dictionary:
	var stype: String = stratagem_type if STRATAGEM_TYPES.has(stratagem_type) else "FIRE_ATTACK"
	var int_a: int = _extract_officer_stat(attacker_officer, "INT", 60)
	var int_b: int = _extract_officer_stat(defender_officer, "INT", 60)
	var traits_a: Array[String] = _officer_traits(attacker_officer)
	var traits_b: Array[String] = _officer_traits(defender_officer)

	if stype == "FIRE_ATTACK" and weather == "RAIN":
		return {
			"stratagem": stype,
			"weather": weather,
			"outcome": "BLOCKED_BY_WEATHER",
			"success": false,
			"countered": false,
			"power_pm": 1000,
			"morale_hit_target_bp": 0,
			"morale_hit_attacker_bp": 0
		}

	var base_bp: int = 5000
	var weather_bonus_bp: int = 0
	var power_pm: int = 1350

	if stype == "FIRE_ATTACK":
		if weather == "WINDY":
			weather_bonus_bp = 1500
			power_pm = 1500
	elif stype == "FLOOD":
		if weather == "RAIN":
			weather_bonus_bp = 2000
			power_pm = 1600
		if terrain == "WATERWAY":
			weather_bonus_bp += 1000
	elif stype == "AMBUSH":
		if weather == "FOG":
			weather_bonus_bp = 2500
		if terrain == "MOUNTAIN" or terrain == "MOUNTAIN_PATH":
			weather_bonus_bp += 1500
			power_pm = 1450
	elif stype == "CONFUSION":
		base_bp = 5500
		power_pm = 1250

	var trait_bonus_bp: int = 0
	if traits_a.has("T_MYSTIC"):
		trait_bonus_bp += 1200
	if traits_b.has("T_CAUTIOUS"):
		trait_bonus_bp -= 1500

	var success_bp: int = clampi(
		base_bp + (int_a - int_b) * 150 + weather_bonus_bp + trait_bonus_bp,
		500,
		9500
	)

	var hash_id: int = StateHasher.crc32_bytes((
		str(attacker_officer.get("pawn_id", "a")) + ":" + str(defender_officer.get("pawn_id", "b")) + ":" + stype
	).to_utf8_buffer())
	var roll_bp: int = DeterministicRNG.roll_bp(world_seed, tick_id, hash_id, salt)

	# Counter-stratagem check when defender INT >= attacker INT + 10 and roll in bottom 15% (i.e. >= 8500)
	var countered: bool = false
	if int_b >= int_a + 10 and roll_bp >= 8500:
		countered = true
		return {
			"stratagem": stype,
			"weather": weather,
			"outcome": "COUNTER_STRATAGEM",
			"success": false,
			"countered": true,
			"success_bp": success_bp,
			"roll_bp": roll_bp,
			"power_pm": 1000,
			"morale_hit_target_bp": 0,
			"morale_hit_attacker_bp": -600
		}

	var succeeded: bool = roll_bp < success_bp
	return {
		"stratagem": stype,
		"weather": weather,
		"outcome": "SUCCESS" if succeeded else "FAILED",
		"success": succeeded,
		"countered": false,
		"success_bp": success_bp,
		"roll_bp": roll_bp,
		"power_pm": power_pm if succeeded else 1000,
		"morale_hit_target_bp": -900 if succeeded else 0,
		"morale_hit_attacker_bp": 0
	}


static func _compute_army_atk_score(army: Dictionary, doc: Dictionary) -> int:
	var n: int = maxi(0, _to_int(army.get("troop_count", 0), 0))
	if n <= 0:
		return 0
	var n085_pm: int = pow_085_pm(n)
	var lead: Dictionary = _get_lead_officer(army)
	var mar: int = _extract_officer_stat(lead, "MAR", 60)
	var lea: int = _extract_officer_stat(lead, "LEA", 60)
	var gear_pm: int = clampi(_to_int(army.get("gear_pm", 1000), 1000), 700, 2000)
	var morale_bp: int = clampi(_to_int(army.get("morale_bp", 7500), 7500), 0, 10000)

	# (1 + (MAR + 0.5 * LEA) / 100) in permille -> 1000 + mar*10 + lea*5
	var stat_mult_pm: int = 1000 + mar * 10 + lea * 5
	# (0.6 + 0.00004 * MoraleBP) in permille -> 600 + (morale_bp * 40) / 1000
	@warning_ignore("integer_division")
	var morale_mult_pm: int = 600 + (morale_bp * 40) / 1000

	var stance: String = str(doc.get("stance", "BALANCED"))
	var form: String = str(doc.get("formation", "SHIELD_WALL"))
	var doc_mult_pm: int = 1000
	if stance == "AGGRESSIVE":
		doc_mult_pm += 150
	if form == "WEDGE":
		doc_mult_pm += 250
	elif form == "CRESCENT":
		doc_mult_pm += 150

	var u_atk_pm: int = clampi(_to_int(army.get("unit_atk_pm", 1000), 1000), 500, 2200)

	@warning_ignore("integer_division")
	var s1: int = (n085_pm * u_atk_pm) / 1000
	@warning_ignore("integer_division")
	var s2: int = (s1 * stat_mult_pm) / 1000
	@warning_ignore("integer_division")
	var s3: int = (s2 * gear_pm) / 1000
	@warning_ignore("integer_division")
	var s4: int = (s3 * morale_mult_pm) / 1000
	@warning_ignore("integer_division")
	var s5: int = (s4 * doc_mult_pm) / 1000
	return maxi(1, s5)


static func _compute_army_def_score(army: Dictionary, doc: Dictionary, terrain: String) -> int:
	var n: int = maxi(0, _to_int(army.get("troop_count", 0), 0))
	if n <= 0:
		return 0
	var n085_pm: int = pow_085_pm(n)
	var lead: Dictionary = _get_lead_officer(army)
	var mar: int = _extract_officer_stat(lead, "MAR", 60)
	var lea: int = _extract_officer_stat(lead, "LEA", 60)
	var gear_pm: int = clampi(_to_int(army.get("gear_pm", 1000), 1000), 700, 2000)

	var stat_mult_pm: int = 1000 + lea * 10 + mar * 3
	var morale_bp: int = clampi(_to_int(army.get("morale_bp", 7500), 7500), 0, 10000)
	@warning_ignore("integer_division")
	var morale_mult_pm: int = 600 + (morale_bp * 40) / 1000
	var form: String = str(doc.get("formation", "SHIELD_WALL"))
	var stance: String = str(doc.get("stance", "BALANCED"))
	var form_mult_pm: int = 1000
	if form == "SHIELD_WALL":
		form_mult_pm += 350
	elif form == "WEDGE":
		form_mult_pm -= 150
	if stance == "CONSERVATIVE":
		form_mult_pm += 150

	var terrain_mult_pm: int = 1000
	if terrain == "MOUNTAIN" or terrain == "MOUNTAIN_PATH":
		terrain_mult_pm = 1200
	elif terrain == "CITY":
		terrain_mult_pm = 1300

	var wall_hp: int = maxi(0, _to_int(army.get("wall_hp", 0), 0))
	@warning_ignore("integer_division")
	var wall_mult_pm: int = 1000 + wall_hp / 5

	var u_def_pm: int = clampi(_to_int(army.get("unit_def_pm", 1000), 1000), 500, 2200)

	@warning_ignore("integer_division")
	var s1: int = (n085_pm * u_def_pm) / 1000
	@warning_ignore("integer_division")
	var s2: int = (s1 * stat_mult_pm) / 1000
	@warning_ignore("integer_division")
	var s3: int = (s2 * gear_pm) / 1000
	@warning_ignore("integer_division")
	var s4: int = (s3 * morale_mult_pm) / 1000
	@warning_ignore("integer_division")
	var s5: int = (s4 * form_mult_pm) / 1000
	@warning_ignore("integer_division")
	var s6: int = (s5 * terrain_mult_pm) / 1000
	@warning_ignore("integer_division")
	var s7: int = (s6 * wall_mult_pm) / 1000
	return maxi(1, s7)


static func _should_accept_duel(doc: Dictionary, self_mar: int, opp_mar: int) -> bool:
	var pol: String = str(doc.get("duel_policy", "ONLY_IF_ADVANTAGED"))
	if pol == "ALWAYS":
		return true
	if pol == "NEVER":
		return false
	return self_mar >= opp_mar - 5


static func resolve_auto_battle(
	army_a: Dictionary,
	army_b: Dictionary,
	weather: String,
	terrain: String,
	clock: SimClock,
	world_seed: int
) -> Dictionary:
	var tick_id: int = clock.current_tick_id if clock != null else 0
	var a_state: Dictionary = army_a.duplicate(true)
	var b_state: Dictionary = army_b.duplicate(true)

	var a_init_troops: int = maxi(1, _to_int(a_state.get("troop_count", 1), 1))
	var b_init_troops: int = maxi(1, _to_int(b_state.get("troop_count", 1), 1))
	a_state["troop_count"] = a_init_troops
	b_state["troop_count"] = b_init_troops
	a_state["morale_bp"] = clampi(_to_int(a_state.get("morale_bp", 8000), 8000), 0, 10000)
	b_state["morale_bp"] = clampi(_to_int(b_state.get("morale_bp", 8000), 8000), 0, 10000)

	var doc_a_raw: Variant = a_state.get("standing_doctrine", {})
	var doc_a_dict: Dictionary = {}
	if doc_a_raw is Dictionary:
		doc_a_dict = doc_a_raw
	var doc_b_raw: Variant = b_state.get("standing_doctrine", {})
	var doc_b_dict: Dictionary = {}
	if doc_b_raw is Dictionary:
		doc_b_dict = doc_b_raw
	var doc_a: Dictionary = parse_doctrine(doc_a_dict)
	var doc_b: Dictionary = parse_doctrine(doc_b_dict)

	var lead_a: Dictionary = _get_lead_officer(a_state)
	var lead_b: Dictionary = _get_lead_officer(b_state)
	var mar_a: int = _extract_officer_stat(lead_a, "MAR", 60)
	var mar_b: int = _extract_officer_stat(lead_b, "MAR", 60)
	var lea_a: int = _extract_officer_stat(lead_a, "LEA", 60)
	var lea_b: int = _extract_officer_stat(lead_b, "LEA", 60)

	var rounds: Array[Dictionary] = []
	var duel_result: Dictionary = {}
	var duel_resolved: bool = false
	var winner: String = "DRAW"
	var victory_reason: String = "MAX_ROUNDS"
	var doctrine_triggers: Array[String] = []

	for r: int in range(1, MAX_ROUNDS + 1):
		var na: int = _to_int(a_state.get("troop_count", 0), 0)
		var nb: int = _to_int(b_state.get("troop_count", 0), 0)
		if na <= 0 or nb <= 0:
			break

		var round_entry: Dictionary = {
			"round": r,
			"start_troops_a": na,
			"start_troops_b": nb,
			"start_morale_a": _to_int(a_state["morale_bp"], 0),
			"start_morale_b": _to_int(b_state["morale_bp"], 0)
		}

		# Phase 1: Archery / Skirmish
		var atk_a: int = _compute_army_atk_score(a_state, doc_a)
		var def_a: int = _compute_army_def_score(a_state, doc_a, terrain)
		var atk_b: int = _compute_army_atk_score(b_state, doc_b)
		var def_b: int = _compute_army_def_score(b_state, doc_b, terrain)

		var bow_bonus_a_pm: int = 1200 if str(doc_a.get("formation", "")) == "CRESCENT" else 1000
		var bow_bonus_b_pm: int = 1200 if str(doc_b.get("formation", "")) == "CRESCENT" else 1000
		if weather == "RAIN":
			bow_bonus_a_pm = 750
			bow_bonus_b_pm = 750

		@warning_ignore("integer_division")
		var skirmish_loss_b: int = mini(nb, maxi(1, (25 * atk_a * bow_bonus_a_pm) / (maxi(1, def_b) * 1000)))
		@warning_ignore("integer_division")
		var skirmish_loss_a: int = mini(na, maxi(1, (25 * atk_b * bow_bonus_b_pm) / (maxi(1, def_a) * 1000)))

		# Phase 2: Duel (Round 1) & Stratagem
		var strat_a_pm: int = 1000
		var strat_b_pm: int = 1000
		if r == 1 and not duel_resolved:
			duel_resolved = true
			var acc_a: bool = _should_accept_duel(doc_a, mar_a, mar_b)
			var acc_b: bool = _should_accept_duel(doc_b, mar_b, mar_a)
			if acc_a and acc_b:
				duel_result = resolve_officer_duel(lead_a, lead_b, world_seed, tick_id, 501)
				a_state["morale_bp"] = clampi(_to_int(a_state["morale_bp"], 0) + _to_int(duel_result.get("morale_swing_a_bp", 0), 0), 0, 10000)
				b_state["morale_bp"] = clampi(_to_int(b_state["morale_bp"], 0) + _to_int(duel_result.get("morale_swing_b_bp", 0), 0), 0, 10000)
				round_entry["duel"] = duel_result
			else:
				if not acc_a:
					a_state["morale_bp"] = maxi(0, _to_int(a_state["morale_bp"], 0) - 400)
					doctrine_triggers.append("A_DECLINED_DUEL")
				if not acc_b:
					b_state["morale_bp"] = maxi(0, _to_int(b_state["morale_bp"], 0) - 400)
					doctrine_triggers.append("B_DECLINED_DUEL")
				round_entry["duel"] = {"skipped": true}

		var strat_events: Array[Dictionary] = []
		if r == 2 or r == 5:
			if _to_bool(doc_a.get("stratagem_enabled", true), true):
				var st_a: String = "FLOOD" if weather == "RAIN" else "FIRE_ATTACK"
				var sr_a: Dictionary = resolve_stratagem(lead_a, lead_b, st_a, weather, terrain, world_seed, tick_id, 600 + r)
				strat_a_pm = _to_int(sr_a.get("power_pm", 1000), 1000)
				b_state["morale_bp"] = clampi(_to_int(b_state["morale_bp"], 0) + _to_int(sr_a.get("morale_hit_target_bp", 0), 0), 0, 10000)
				a_state["morale_bp"] = clampi(_to_int(a_state["morale_bp"], 0) + _to_int(sr_a.get("morale_hit_attacker_bp", 0), 0), 0, 10000)
				strat_events.append({"side": "A", "result": sr_a})
			if _to_bool(doc_b.get("stratagem_enabled", true), true):
				var st_b: String = "AMBUSH" if terrain.begins_with("MOUNTAIN") else "CONFUSION"
				var sr_b: Dictionary = resolve_stratagem(lead_b, lead_a, st_b, weather, terrain, world_seed, tick_id, 700 + r)
				strat_b_pm = _to_int(sr_b.get("power_pm", 1000), 1000)
				a_state["morale_bp"] = clampi(_to_int(a_state["morale_bp"], 0) + _to_int(sr_b.get("morale_hit_target_bp", 0), 0), 0, 10000)
				b_state["morale_bp"] = clampi(_to_int(b_state["morale_bp"], 0) + _to_int(sr_b.get("morale_hit_attacker_bp", 0), 0), 0, 10000)
				strat_events.append({"side": "B", "result": sr_b})
		round_entry["stratagems"] = strat_events

		# Phase 3: Melee Clash (Symmetric battle_scale * Lanchester N^0.85 ATK/DEF ratio)
		@warning_ignore("integer_division")
		var battle_scale: int = maxi(10, isqrt_int(na * nb) / 8)
		@warning_ignore("integer_division")
		var melee_loss_b: int = ((battle_scale * atk_a * strat_a_pm) / (maxi(1, def_b) * 1000)) + 1
		@warning_ignore("integer_division")
		var melee_loss_a: int = ((battle_scale * atk_b * strat_b_pm) / (maxi(1, def_a) * 1000)) + 1

		var total_loss_b: int = mini(nb, skirmish_loss_b + melee_loss_b)
		var total_loss_a: int = mini(na, skirmish_loss_a + melee_loss_a)

		na = maxi(0, na - total_loss_a)
		nb = maxi(0, nb - total_loss_b)
		a_state["troop_count"] = na
		b_state["troop_count"] = nb

		# Phase 4: Morale drop & Doctrine retreat check
		@warning_ignore("integer_division")
		var morale_drop_a: int = (1500 * total_loss_a * 100) / (maxi(1, na + total_loss_a) * maxi(40, 70 + lea_a / 2))
		@warning_ignore("integer_division")
		var morale_drop_b: int = (1500 * total_loss_b * 100) / (maxi(1, nb + total_loss_b) * maxi(40, 70 + lea_b / 2))
		a_state["morale_bp"] = maxi(0, _to_int(a_state["morale_bp"], 0) - morale_drop_a)
		b_state["morale_bp"] = maxi(0, _to_int(b_state["morale_bp"], 0) - morale_drop_b)

		round_entry["casualties_a"] = total_loss_a
		round_entry["casualties_b"] = total_loss_b
		round_entry["end_troops_a"] = na
		round_entry["end_troops_b"] = nb
		round_entry["end_morale_a"] = a_state["morale_bp"]
		round_entry["end_morale_b"] = b_state["morale_bp"]

		@warning_ignore("integer_division")
		var ratio_a_bp: int = (na * 10000) / a_init_troops
		@warning_ignore("integer_division")
		var ratio_b_bp: int = (nb * 10000) / b_init_troops

		var a_retreat: bool = na <= 0 or ratio_a_bp <= _to_int(doc_a["retreat_troop_bp"], 3000) or _to_int(a_state["morale_bp"], 0) <= _to_int(doc_a["retreat_morale_bp"], 2500)
		var b_retreat: bool = nb <= 0 or ratio_b_bp <= _to_int(doc_b["retreat_troop_bp"], 3000) or _to_int(b_state["morale_bp"], 0) <= _to_int(doc_b["retreat_morale_bp"], 2500)

		round_entry["a_retreated"] = a_retreat
		round_entry["b_retreated"] = b_retreat
		rounds.append(round_entry)

		if a_retreat and not b_retreat:
			winner = "B"
			victory_reason = "A_ANNIHILATED" if na <= 0 else "A_DOCTRINE_RETREAT"
			if na > 0:
				doctrine_triggers.append("A_RETREAT_TRIGGERED")
			break
		elif b_retreat and not a_retreat:
			winner = "A"
			victory_reason = "B_ANNIHILATED" if nb <= 0 else "B_DOCTRINE_RETREAT"
			if nb > 0:
				doctrine_triggers.append("B_RETREAT_TRIGGERED")
			break
		elif a_retreat and b_retreat:
			if na > nb:
				winner = "A"
			elif nb > na:
				winner = "B"
			else:
				winner = "DRAW"
			victory_reason = "MUTUAL_RETREAT"
			break

	if winner == "DRAW" and victory_reason == "MAX_ROUNDS":
		var rem_a: int = _to_int(a_state["troop_count"], 0)
		var rem_b: int = _to_int(b_state["troop_count"], 0)
		if rem_a > rem_b:
			winner = "A"
		elif rem_b > rem_a:
			winner = "B"

	return {
		"schema_version": "BATTLE_REPLAY_V1",
		"tick_id": tick_id,
		"weather": weather,
		"terrain": terrain,
		"winner": winner,
		"victory_reason": victory_reason,
		"rounds_fought": rounds.size(),
		"initial_troops_a": a_init_troops,
		"initial_troops_b": b_init_troops,
		"remaining_troops_a": _to_int(a_state["troop_count"], 0),
		"remaining_troops_b": _to_int(b_state["troop_count"], 0),
		"final_morale_a_bp": _to_int(a_state["morale_bp"], 0),
		"final_morale_b_bp": _to_int(b_state["morale_bp"], 0),
		"duel_summary": duel_result,
		"doctrine_triggers": doctrine_triggers,
		"prisoner_outcome": doc_a.get("prisoner_policy", "RECRUIT") if winner == "A" else doc_b.get("prisoner_policy", "RECRUIT"),
		"rounds": rounds
	}
