class_name TestBattleEngine
extends HarnessTestCase


func _as_int(v: Variant, fallback: int = 0) -> int:
	if v is int:
		var iv: int = v
		return iv
	if v is float:
		var fv: float = v
		return int(fv)
	return fallback


func _as_bool(v: Variant, fallback: bool = false) -> bool:
	if v is bool:
		var bv: bool = v
		return bv
	return fallback


func _as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		var d: Dictionary = v
		return d
	return {}


func _as_array(v: Variant) -> Array:
	if v is Array:
		var arr: Array = v
		return arr
	return []


func test_pow_085_pm_strict_monotonicity_and_elite_vs_militia() -> void:
	assert_eq(BattleEngine.pow_085_pm(-5), 0, "pow_085_pm negative clamps to 0")
	assert_eq(BattleEngine.pow_085_pm(0), 0, "pow_085_pm(0) == 0")
	assert_eq(BattleEngine.pow_085_pm(1), 1000, "pow_085_pm(1) == 1000")
	assert_eq(BattleEngine.pow_085_pm(1000), 354813, "pow_085_pm(1000) matches breakpoint")

	# Strict monotonicity across dense small values and interpolated/extrapolated intervals
	var prev: int = BattleEngine.pow_085_pm(0)
	for n: int in range(1, 60):
		var cur: int = BattleEngine.pow_085_pm(n)
		assert_gt(cur, prev, "pow_085_pm strictly increasing at n=%d" % n)
		prev = cur

	var samples: Array[int] = [99, 100, 101, 599, 600, 601, 999, 1000, 1001, 1799, 1800, 1801, 99999, 100000, 120000]
	var prev_s: int = BattleEngine.pow_085_pm(98)
	for s: int in samples:
		var cur_s: int = BattleEngine.pow_085_pm(s)
		assert_gt(cur_s, prev_s, "pow_085_pm strictly increasing at sample n=%d" % s)
		prev_s = cur_s

	# Sublinear diminishing returns (Lanchester N^0.85): 2000 units < 2 * 1000 units
	assert_lt(BattleEngine.pow_085_pm(2000), 2 * BattleEngine.pow_085_pm(1000), "N^0.85 is strictly sublinear")

	# 1000 elite (MAR=96, LEA=94, gear=1500, morale=9500) vs 1800 militia (MAR=55, LEA=50, gear=1000, morale=6000)
	var elite_army: Dictionary = {
		"troop_count": 1000,
		"gear_pm": 1500,
		"morale_bp": 9500,
		"officers": [{"pawn_id": "off_elite", "MAR": 96, "LEA": 94, "INT": 82, "traits": ["T_FIERCE"]}],
		"standing_doctrine": {"stance": "AGGRESSIVE", "formation": "WEDGE", "retreat_troop_bp": 1500, "retreat_morale_bp": 1500}
	}
	var militia_army: Dictionary = {
		"troop_count": 1800,
		"gear_pm": 1000,
		"morale_bp": 6000,
		"officers": [{"pawn_id": "off_militia", "MAR": 55, "LEA": 50, "INT": 50}],
		"standing_doctrine": {"stance": "BALANCED", "formation": "SHIELD_WALL", "retreat_troop_bp": 2500, "retreat_morale_bp": 2000}
	}
	var clk: SimClock = SimClock.new(24)
	var replay1: Dictionary = BattleEngine.resolve_auto_battle(elite_army, militia_army, "CLEAR", "PLAINS", clk, 1001)
	var replay2: Dictionary = BattleEngine.resolve_auto_battle(elite_army, militia_army, "CLEAR", "PLAINS", clk, 1001)

	assert_eq(str(replay1.get("winner", "")), "A", "1000 elite must defeat 1800 militia")
	assert_gt(_as_int(replay1.get("remaining_troops_a", 0), 0), 0, "Elite side retains surviving troops")
	assert_eq(StateHasher.sha256_dict(replay1), StateHasher.sha256_dict(replay2), "Battle replay is strictly deterministic")


func test_officer_duel_5_bouts_traits_morale_and_capture() -> void:
	var fierce_off: Dictionary = {"pawn_id": "lu_bu", "MAR": 90, "weapon_pm": 1200, "traits": ["T_FIERCE", "T_DRINKER"]}
	var cautious_off: Dictionary = {"pawn_id": "cautious_gen", "MAR": 90, "weapon_pm": 1200, "traits": ["T_CAUTIOUS"]}

	var d1: Dictionary = BattleEngine.resolve_officer_duel(fierce_off, cautious_off, 5555, 10, 1)
	var d2: Dictionary = BattleEngine.resolve_officer_duel(fierce_off, cautious_off, 5555, 10, 1)
	assert_eq(StateHasher.sha256_dict(d1), StateHasher.sha256_dict(d2), "Duel outcome strictly deterministic")

	var bouts: Array = _as_array(d1.get("bouts", []))
	assert_in_range(bouts.size(), 1, 5, "Duel resolves in 1..5 bouts")

	# Verify trait hooks give decisive advantage over equal-MAR T_CAUTIOUS opponent
	var fierce_wins: int = 0
	var saw_captured: bool = false
	var saw_not_captured: bool = false
	var saw_severe_or_light: bool = false

	for salt: int in range(1, 35):
		var res: Dictionary = BattleEngine.resolve_officer_duel(fierce_off, cautious_off, 9001, 24, salt)
		var w_side: String = str(res.get("winner_side", ""))
		if w_side == "A":
			fierce_wins += 1
			assert_eq(_as_int(res.get("morale_swing_a_bp", 0), 0), 1800, "Winner gains +1800 morale_bp")
			assert_eq(_as_int(res.get("morale_swing_b_bp", 0), 0), -1800, "Loser suffers -1800 morale_bp")
			var inj: String = str(res.get("loser_injury", ""))
			if inj == "SEVERE_WOUND" or inj == "LIGHT_WOUND":
				saw_severe_or_light = true
			if _as_bool(res.get("loser_captured", false), false):
				saw_captured = true
			else:
				saw_not_captured = true

	assert_gt(fierce_wins, 25, "T_FIERCE+T_DRINKER (+18 score) dominates T_CAUTIOUS (-4 score) at equal MAR")
	assert_true(saw_severe_or_light, "Loser receives LIGHT_WOUND or SEVERE_WOUND")
	assert_true(saw_captured, "Capture roll succeeds within 35 salts")
	assert_true(saw_not_captured, "Capture is probabilistic, not guaranteed")


func test_stratagems_weather_and_counter_stratagem() -> void:
	var high_int_a: Dictionary = {"pawn_id": "zhou_yu", "INT": 96, "traits": ["T_MYSTIC"]}
	var low_int_b: Dictionary = {"pawn_id": "cai_mao", "INT": 60}
	var high_int_def: Dictionary = {"pawn_id": "zhuge_liang", "INT": 100}
	var mid_int_atk: Dictionary = {"pawn_id": "cao_ren", "INT": 70}

	# FIRE_ATTACK blocked by RAIN
	var fire_rain: Dictionary = BattleEngine.resolve_stratagem(high_int_a, low_int_b, "FIRE_ATTACK", "RAIN", "PLAINS", 100, 12, 1)
	assert_eq(str(fire_rain.get("outcome", "")), "BLOCKED_BY_WEATHER", "FIRE_ATTACK blocked in RAIN")
	assert_false(_as_bool(fire_rain.get("success", true), true), "Blocked FIRE_ATTACK success == false")
	assert_eq(_as_int(fire_rain.get("power_pm", 0), 0), 1000, "Blocked FIRE_ATTACK power_pm == 1000")

	# FIRE_ATTACK + WINDY -> boosted power_pm = 1500 on success
	var saw_fire_windy_success: bool = false
	for s: int in range(1, 15):
		var sr: Dictionary = BattleEngine.resolve_stratagem(high_int_a, low_int_b, "FIRE_ATTACK", "WINDY", "PLAINS", 100, 12, s)
		if _as_bool(sr.get("success", false), false):
			saw_fire_windy_success = true
			assert_eq(_as_int(sr.get("power_pm", 0), 0), 1500, "FIRE_ATTACK+WINDY yields power_pm 1500")
			assert_eq(_as_int(sr.get("morale_hit_target_bp", 0), 0), -900, "Successful stratagem hits target morale by -900")
			break
	assert_true(saw_fire_windy_success, "High INT + WINDY succeeds FIRE_ATTACK")

	# FLOOD + RAIN + WATERWAY -> boosted power_pm = 1600 on success
	var saw_flood_rain_success: bool = false
	for s: int in range(1, 15):
		var sr_f: Dictionary = BattleEngine.resolve_stratagem(high_int_a, low_int_b, "FLOOD", "RAIN", "WATERWAY", 200, 18, s)
		if _as_bool(sr_f.get("success", false), false):
			saw_flood_rain_success = true
			assert_eq(_as_int(sr_f.get("power_pm", 0), 0), 1600, "FLOOD+RAIN yields power_pm 1600")
			break
	assert_true(saw_flood_rain_success, "FLOOD+RAIN+WATERWAY succeeds")

	# INT Counter-stratagem: defender INT >= attacker INT + 10 and roll_bp >= 8500
	var saw_counter: bool = false
	for s: int in range(1, 80):
		var sr_c: Dictionary = BattleEngine.resolve_stratagem(mid_int_atk, high_int_def, "FIRE_ATTACK", "CLEAR", "PLAINS", 300, 24, s)
		if str(sr_c.get("outcome", "")) == "COUNTER_STRATAGEM":
			saw_counter = true
			assert_true(_as_bool(sr_c.get("countered", false), false), "Countered flag is true")
			assert_false(_as_bool(sr_c.get("success", true), true), "Countered stratagem success is false")
			assert_eq(_as_int(sr_c.get("morale_hit_attacker_bp", 0), 0), -600, "Counter-stratagem penalizes attacker morale by -600")
			break
	assert_true(saw_counter, "Defender with +30 INT triggers COUNTER_STRATAGEM within 80 rolls")


func test_standing_doctrines_orderly_retreat_and_float_free_replay_v1() -> void:
	# Side A has high retreat_troop_bp (9000 bp -> retreats as soon as troops <= 90%) and duel_policy NEVER
	var army_a: Dictionary = {
		"troop_count": 1000,
		"gear_pm": 1000,
		"morale_bp": 8000,
		"officers": [{"pawn_id": "gen_retreat", "MAR": 70, "LEA": 70, "INT": 70}],
		"standing_doctrine": {
			"engagement_stance": "DEFENSIVE_HOLD",
			"formation": "SQUARE_SHIELD",
			"retreat_troop_bp": 9000,
			"retreat_morale_bp": 1000,
			"duel_policy": "DECLINE_ALL",
			"stratagem_policy": "NONE",
			"prisoner_policy": "RANSOM_RELEASE"
		}
	}
	var army_b: Dictionary = {
		"troop_count": 1000,
		"gear_pm": 1100,
		"morale_bp": 8500,
		"officers": [{"pawn_id": "gen_push", "MAR": 82, "LEA": 80, "INT": 75}],
		"standing_doctrine": {
			"engagement_stance": "PREEMPTIVE_STRIKE",
			"formation": "ARROW_WEDGE",
			"retreat_troop_bp": 1000,
			"retreat_morale_bp": 1000,
			"duel_policy": "ACCEPT_ALWAYS",
			"prisoner_policy": "RANSOM_RELEASE"
		}
	}

	var clk: SimClock = SimClock.new(48)
	var replay: Dictionary = BattleEngine.resolve_auto_battle(army_a, army_b, "FOG", "MOUNTAIN_PATH", clk, 8888)

	assert_eq(str(replay.get("schema_version", "")), "BATTLE_REPLAY_V1", "Replay schema_version == BATTLE_REPLAY_V1")
	assert_false(StateHasher.has_floats(replay), "BATTLE_REPLAY_V1 must contain zero floats")
	assert_true(StateHasher.validate_deterministic_types(replay), "BATTLE_REPLAY_V1 uses strictly deterministic types")

	assert_eq(str(replay.get("winner", "")), "B", "Side B wins via A doctrine retreat")
	assert_eq(str(replay.get("victory_reason", "")), "A_DOCTRINE_RETREAT", "Orderly retreat triggered by retreat_troop_bp=9000")
	assert_gt(_as_int(replay.get("remaining_troops_a", 0), 0), 0, "Orderly retreat preserves surviving troops")
	assert_eq(str(replay.get("prisoner_outcome", "")), "RANSOM", "Winner prisoner policy normalized to RANSOM")

	var triggers: Array = _as_array(replay.get("doctrine_triggers", []))
	assert_true(triggers.has("A_DECLINED_DUEL"), "duel_policy NEVER records A_DECLINED_DUEL")
	assert_true(triggers.has("A_RETREAT_TRIGGERED"), "retreat_troop_bp records A_RETREAT_TRIGGERED")

	var rounds: Array = _as_array(replay.get("rounds", []))
	assert_eq(rounds.size(), _as_int(replay.get("rounds_fought", -1), -1), "rounds_fought matches rounds.size()")
	assert_gt(rounds.size(), 0, "At least 1 round fought")
	var r0: Dictionary = _as_dict(rounds[0])
	assert_true(_as_bool(_as_dict(r0.get("duel", {})).get("skipped", false), false), "Round 1 duel marked skipped when declined")
