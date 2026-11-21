class_name ManorSimulator
extends RefCounted

const MACRO_STEPS: int = 6

const SEASON_AGRI_MULT_PM: Dictionary = {
	"SPRING": 1200,
	"SUMMER": 1000,
	"AUTUMN": 1500,
	"WINTER": 200
}

const JOB_BASE_WORK_PM: Dictionary = {
	"LOGISTICS": 250,
	"PATROL": 250,
	"AGRICULTURE": 250,
	"TRAINING": 250,
	"CRAFTING": 250,
	"RESEARCH": 250,
	"DIPLOMACY": 250
}

const JOB_PRIMARY_STAT: Dictionary = {
	"LOGISTICS": "POL",
	"PATROL": "LEA",
	"AGRICULTURE": "POL",
	"TRAINING": "MAR",
	"CRAFTING": "MAR",
	"RESEARCH": "INT",
	"DIPLOMACY": "CHA"
}

const JOB_SECONDARY_STAT: Dictionary = {
	"LOGISTICS": "LEA",
	"PATROL": "MAR",
	"AGRICULTURE": "LEA",
	"TRAINING": "LEA",
	"CRAFTING": "POL",
	"RESEARCH": "POL",
	"DIPLOMACY": "INT"
}

const JOB_TARGET_ZONE: Dictionary = {
	"LOGISTICS": "ZONE_STOCKPILE",
	"PATROL": "ZONE_DEFENSE_LINE",
	"AGRICULTURE": "ZONE_FARMLAND",
	"TRAINING": "ZONE_BARRACKS",
	"CRAFTING": "ZONE_WORKSHOP",
	"RESEARCH": "ZONE_RESIDENCE",
	"DIPLOMACY": "ZONE_RESIDENCE",
	"SLEEP_IN_QUARTERS": "ZONE_RESIDENCE",
	"ATTEND_BANQUET_OR_RECREATION": "ZONE_RESIDENCE",
	"MARTIAL_DRILL_TRAINING": "ZONE_BARRACKS",
	"INFIRMARY_CARE": "ZONE_INFIRMARY",
	"EMERGENCY_EAT": "ZONE_STOCKPILE",
	"RAID_DEFENSE": "ZONE_DEFENSE_LINE",
	"IDLE_STUDY_OR_GUARD": "ZONE_DEFENSE_LINE"
}


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


static func promote_to_lod0(manor: ManorState) -> void:
	if manor != null:
		manor.current_lod = 0


static func demote_to_lod1(manor: ManorState) -> void:
	if manor != null and not manor.raid_defense_active:
		manor.current_lod = 1


static func _has_domain_task(manor: ManorState, domain: String) -> bool:
	match domain:
		"LOGISTICS":
			return manor.wall_hp < manor.max_wall_hp or true
		"PATROL":
			return true
		"AGRICULTURE":
			return true
		"TRAINING":
			return manor.household_troops > 0 or true
		"CRAFTING":
			return (manor.get_resource("IRON") >= 10 and manor.get_resource("WOOD") >= 5) or not manor.crafting_queue.is_empty()
		"RESEARCH":
			return not manor.active_research_id.is_empty()
		"DIPLOMACY":
			return true
		_:
			return false


static func select_next_job(pawn: PawnEntity, manor: ManorState, clock: SimClock) -> String:
	if pawn.state == "ON_EXPEDITION" or pawn.state == "CAPTURED":
		return "NONE_EXTERNAL"
	if pawn.is_in_mental_break():
		return pawn.mental_state
	if manor.raid_defense_active:
		return "RAID_DEFENSE"

	# Emergency self-preservation overrides
	if pawn.health_state == "SEVERE_WOUND" or pawn.state == "WOUNDED":
		return "INFIRMARY_CARE"
	if pawn.get_need("FOOD") < 1500 and manor.get_resource("GRAIN") > 0:
		return "EMERGENCY_EAT"
	if pawn.get_need("REST") < 1000:
		return "SLEEP_IN_QUARTERS"

	var shichen_slot: String = pawn.get_schedule_activity(clock.get_shichen_index())
	if shichen_slot == "SLEEP" and pawn.get_need("REST") < 9000:
		return "SLEEP_IN_QUARTERS"
	if shichen_slot == "RECREATION" and pawn.get_need("MORALE") < 8500:
		return "ATTEND_BANQUET_OR_RECREATION"
	if shichen_slot == "DRILL":
		return "MARTIAL_DRILL_TRAINING"

	# 7-domain 1->4 left-to-right priority tie-breaker
	for prio: int in [1, 2, 3, 4]:
		for domain: String in PawnEntity.WORK_DOMAINS:
			if pawn.get_work_priority(domain) == prio:
				if _has_domain_task(manor, domain):
					return domain

	return "IDLE_STUDY_OR_GUARD"


static func _compute_domain_rate_pm(pawn: PawnEntity, manor: ManorState, domain: String, clock: SimClock) -> int:
	var base_pm: int = _to_int(JOB_BASE_WORK_PM.get(domain, 200), 200)
	var primary_key: String = str(JOB_PRIMARY_STAT.get(domain, "POL"))
	var secondary_key: String = str(JOB_SECONDARY_STAT.get(domain, "LEA"))
	var primary_stat: int = pawn.get_effective_stat(primary_key)
	var secondary_stat: int = pawn.get_effective_stat(secondary_key)

	@warning_ignore("integer_division")
	var stat_mult_pm: int = 1000 + ((primary_stat * 7 + secondary_stat * 3) / 10) * 10

	var mood_mult_pm: int = 850 + pawn.mood * 3
	if manor.ration_quality == "FEAST":
		mood_mult_pm += 100

	var fac_mult_pm: int = manor.get_facility_mult_pm(domain)
	var eff_pm: int = pawn.get_work_efficiency_pm(domain)
	var weather_mult_pm: int = 1000
	if domain == "AGRICULTURE":
		weather_mult_pm = _to_int(SEASON_AGRI_MULT_PM.get(clock.get_season(), 1000), 1000)

	# Integer scaling: base_pm * stat_mult * mood_mult * fac_mult * eff * weather / 10^15
	# Divide sequentially in pairs to avoid int64 overflow while preserving precision
	@warning_ignore("integer_division")
	var step1: int = (base_pm * stat_mult_pm) / 1000
	@warning_ignore("integer_division")
	var step2: int = (step1 * mood_mult_pm) / 1000
	@warning_ignore("integer_division")
	var step3: int = (step2 * fac_mult_pm) / 1000
	@warning_ignore("integer_division")
	var step4: int = (step3 * eff_pm) / 1000
	@warning_ignore("integer_division")
	var step5: int = (step4 * weather_mult_pm) / 1000
	return maxi(50, step5)


static func _compute_pawn_domain_weights_pm(pawn: PawnEntity, manor: ManorState) -> Dictionary:
	# Derives normalized active work domain shares from the 1..4 priority matrix (total = 1000 pm)
	var raw_scores: Dictionary = {}
	var total_score: int = 0
	for idx: int in range(PawnEntity.WORK_DOMAINS.size()):
		var domain: String = PawnEntity.WORK_DOMAINS[idx]
		var prio: int = pawn.get_work_priority(domain)
		if prio >= 1 and prio <= 4 and _has_domain_task(manor, domain):
			# Priority 1 dominates, left-to-right tie-break bias
			var weight: int = (5 - prio) * (5 - prio) * 10 + (7 - idx)
			raw_scores[domain] = weight
			total_score += weight

	var weights_pm: Dictionary = {}
	if total_score <= 0:
		weights_pm["IDLE_STUDY_OR_GUARD"] = 1000
		return weights_pm

	var assigned_sum: int = 0
	var first_domain: String = ""
	for domain: String in PawnEntity.WORK_DOMAINS:
		if raw_scores.has(domain):
			if first_domain.is_empty():
				first_domain = domain
			@warning_ignore("integer_division")
			var share: int = (_to_int(raw_scores[domain], 0) * 1000) / total_score
			weights_pm[domain] = share
			assigned_sum += share

	if not first_domain.is_empty() and assigned_sum < 1000:
		weights_pm[first_domain] = _to_int(weights_pm.get(first_domain, 0), 0) + (1000 - assigned_sum)
	return weights_pm


static func _apply_job_completion(
	pawn: PawnEntity,
	manor: ManorState,
	domain: String,
	world_seed: int,
	tick_id: int
) -> void:
	manor.jobs_completed += 1
	var primary_stat: String = str(JOB_PRIMARY_STAT.get(domain, "POL"))
	var _lvl: bool = pawn.add_stat_xp(primary_stat, 18)

	match domain:
		"AGRICULTURE":
			var grain_gain: int = 24 + manor.get_building_level("MILITARY_FARM") * 8
			if manor.unlocked_techs.has("DOUBLE_CROPPING"):
				grain_gain += 8
			if manor.unlocked_techs.has("WATER_WHEEL"):
				grain_gain += 6
			var _g: int = manor.add_resource("GRAIN", grain_gain)
			var _w: int = manor.add_resource("WOOD", 6)
			var _i: int = manor.add_resource("IRON", 4)
			if manor.get_building_level("HORSE_PASTURE") >= 1 and (manor.jobs_completed % 4) == 0:
				var _h: int = manor.add_resource("HORSES", 1)
		"LOGISTICS":
			var _c: int = manor.add_resource("COIN", 12)
			if manor.wall_hp < manor.max_wall_hp and manor.try_spend_resource("WOOD", 5):
				manor.wall_hp = mini(manor.max_wall_hp, manor.wall_hp + 60)
		"PATROL":
			var _m: int = manor.add_resource("MERIT_PRESTIGE", 3)
			var _c2: int = manor.add_resource("COIN", 8)
		"TRAINING":
			manor.troop_training_pm = mini(1000, manor.troop_training_pm + 5)
			var _lvl2: bool = pawn.add_stat_xp("LEA", 10)
		"CRAFTING":
			if manor.get_resource("IRON") >= 10 and manor.get_resource("WOOD") >= 5:
				var _s1: bool = manor.try_spend_resource("IRON", 10)
				var _s2: bool = manor.try_spend_resource("WOOD", 5)
				var skill: int = pawn.get_effective_stat("MAR") + pawn.get_effective_stat("POL")
				var roll_q: int = DeterministicRNG.roll_range(world_seed, tick_id, pawn.get_entity_hash_id(), 5101, 0, 99)
				var tier_idx: int = 1  # NORMAL
				if skill >= 165 and roll_q >= 70:
					tier_idx = 4
				elif skill >= 140 and roll_q >= 55:
					tier_idx = 3
				elif skill >= 115 and roll_q >= 40:
					tier_idx = 2
				elif roll_q < 12:
					tier_idx = 0
				if pawn.mental_state == "AWAKENED_FORGING":
					tier_idx = mini(5, tier_idx + 2)
					pawn.mental_state = "NORMAL"
					pawn.mental_state_ticks = 0
				var tier_name: String = ManorState.GEAR_TIERS[tier_idx]
				manor.crafted_gear_counts[tier_name] = _to_int(manor.crafted_gear_counts.get(tier_name, 0), 0) + 1
				var _wep: int = manor.add_resource("WEAPONS", 2)
			else:
				var _hw: int = manor.add_resource("HERBS_WINE", 4)
		"RESEARCH":
			if not manor.active_research_id.is_empty():
				var cur_p: int = _to_int(manor.research_progress_pm.get(manor.active_research_id, 0), 0) + 250
				if cur_p >= 1000:
					if not manor.unlocked_techs.has(manor.active_research_id):
						manor.unlocked_techs.append(manor.active_research_id)
					manor.research_progress_pm[manor.active_research_id] = 1000
					manor.recompute_building_derived_caps()
					_advance_next_research(manor)
				else:
					manor.research_progress_pm[manor.active_research_id] = cur_p
			var _hw2: int = manor.add_resource("HERBS_WINE", 3)
		"DIPLOMACY":
			var _mp: int = manor.add_resource("MERIT_PRESTIGE", 5)
			var _cn: int = manor.add_resource("COIN", 10)
			if pawn.mental_state == "AWAKENED_HEARTS":
				var _mp2: int = manor.add_resource("MERIT_PRESTIGE", 10)
				pawn.mental_state = "NORMAL"
				pawn.mental_state_ticks = 0


static func _advance_next_research(manor: ManorState) -> void:
	for branch_key: Variant in ManorState.TECH_BRANCHES.keys():
		var list_var: Variant = ManorState.TECH_BRANCHES[branch_key]
		if list_var is Array:
			var arr: Array = list_var
			for t_item: Variant in arr:
				var tid: String = str(t_item)
				if not manor.unlocked_techs.has(tid):
					manor.active_research_id = tid
					return
	manor.active_research_id = ""


static func _consume_food_and_wine(pawn: PawnEntity, manor: ManorState, ticks_elapsed: int) -> void:
	# Food consumption when hungry (< 3500 bp)
	if pawn.get_need("FOOD") < 3500 and manor.get_resource("GRAIN") > 0:
		var cost: int = 12
		if manor.ration_quality == "COARSE":
			cost = 8
			pawn.add_thought("RATION_COARSE", -5, 24)
		elif manor.ration_quality == "FEAST":
			cost = 18
			pawn.add_thought("RATION_FEAST", 10, 24)
		var actual_cost: int = mini(cost, manor.get_resource("GRAIN"))
		var _ok: bool = manor.try_spend_resource("GRAIN", actual_cost)
		pawn.add_need("FOOD", 5000)

	# Heavy Drinker wine need every 48 ticks
	if pawn.needs_wine():
		pawn.ticks_since_wine += ticks_elapsed
		if pawn.ticks_since_wine >= 48:
			if manor.wine_policy_enabled and manor.try_spend_resource("HERBS_WINE", 4):
				pawn.ticks_since_wine = 0
				pawn.remove_thought("WINE_WITHDRAWAL")
				pawn.add_thought("WINE_SPIRIT", 5, 24)
			else:
				pawn.add_thought("WINE_WITHDRAWAL", -12, 24)


static func _step_pawn_needs_and_health(
	pawn: PawnEntity,
	manor: ManorState,
	job: String,
	ticks_elapsed: int
) -> void:
	if pawn.state == "ON_EXPEDITION" or pawn.state == "CAPTURED":
		return

	var food_drain: int = 400
	var rest_drain: int = 320
	var morale_drain: int = 250

	if job == "SLEEP_IN_QUARTERS":
		@warning_ignore("integer_division")
		var rest_gain: int = (900 * manor.get_quarters_rest_mult_pm()) / 1000
		pawn.add_need("REST", rest_gain * ticks_elapsed)
		food_drain = 200
	else:
		pawn.add_need("REST", -rest_drain * ticks_elapsed)

	if job == "ATTEND_BANQUET_OR_RECREATION":
		var morale_gain: int = 600 + pawn.get_effective_stat("CHA") * 4
		if pawn.has_trait("T_MYSTIC"):
			@warning_ignore("integer_division")
			morale_gain = (morale_gain * 1500) / 1000
		if manor.wine_policy_enabled and manor.try_spend_resource("HERBS_WINE", 2):
			morale_gain += 250
		pawn.add_need("MORALE", morale_gain * ticks_elapsed)
	else:
		pawn.add_need("MORALE", -morale_drain * ticks_elapsed)

	if job == "INFIRMARY_CARE" and (pawn.health_state == "LIGHT_WOUND" or pawn.health_state == "SEVERE_WOUND"):
		var heal_step: int = 250 * ticks_elapsed
		if manor.try_spend_resource("HERBS_WINE", 2 * ticks_elapsed):
			heal_step += 250 * ticks_elapsed
		pawn.wound_recovery_pm += heal_step
		if pawn.wound_recovery_pm >= 1000:
			pawn.wound_recovery_pm = 0
			if pawn.health_state == "SEVERE_WOUND":
				pawn.health_state = "LIGHT_WOUND"
				pawn.state = "IN_MANOR"
			else:
				pawn.health_state = "HEALTHY"
				pawn.state = "IN_MANOR"

	pawn.add_need("FOOD", -food_drain * ticks_elapsed)
	_consume_food_and_wine(pawn, manor, ticks_elapsed)

	# Loyalty & Ambition gentle drift
	var target_loyalty: int = clampi(6000 + pawn.get_effective_stat("CHA") * 30, 3000, 9500)
	var cur_loy: int = pawn.get_need("LOYALTY")
	if cur_loy < target_loyalty:
		pawn.add_need("LOYALTY", mini(50 * ticks_elapsed, target_loyalty - cur_loy))
	elif cur_loy > target_loyalty:
		pawn.add_need("LOYALTY", -mini(50 * ticks_elapsed, cur_loy - target_loyalty))

	var rank_gap: int = maxi(0, pawn.expected_rank - pawn.current_rank)
	var target_amb: int = clampi(10000 - rank_gap * 2000, 0, 10000)
	var amb_rate: int = 40 * ticks_elapsed
	@warning_ignore("integer_division")
	amb_rate = (amb_rate * pawn.get_ambition_drift_mult_pm()) / 1000
	var cur_amb: int = pawn.get_need("AMBITION")
	if cur_amb > target_amb:
		pawn.add_need("AMBITION", -mini(amb_rate, cur_amb - target_amb))
	elif cur_amb < target_amb:
		pawn.add_need("AMBITION", mini(amb_rate, target_amb - cur_amb))


static func _apply_mental_break_side_effects(pawn: PawnEntity, manor: ManorState) -> void:
	if pawn.mental_state == "BREAK_MINOR_BINGE":
		var _s: bool = manor.try_spend_resource("HERBS_WINE", mini(5, manor.get_resource("HERBS_WINE")))
		var _s2: bool = manor.try_spend_resource("GRAIN", mini(10, manor.get_resource("GRAIN")))
	elif pawn.mental_state == "BREAK_MAJOR_EMBEZZLE":
		@warning_ignore("integer_division")
		var embezzle_coin: int = manor.get_resource("COIN") / 10
		var _sc: bool = manor.try_spend_resource("COIN", embezzle_coin)


static func _move_pawn_toward_zone(pawn: PawnEntity, manor: ManorState, job: String) -> void:
	var zone_id: String = str(JOB_TARGET_ZONE.get(job, "ZONE_STOCKPILE"))
	var target: Vector2i = manor.get_zone_center(zone_id)
	if pawn.grid_x < target.x:
		pawn.grid_x += 1
	elif pawn.grid_x > target.x:
		pawn.grid_x -= 1
	if pawn.grid_y < target.y:
		pawn.grid_y += 1
	elif pawn.grid_y > target.y:
		pawn.grid_y -= 1


static func step_lod0_micro_tick(
	manor: ManorState,
	clock: SimClock,
	world_seed: int,
	_event_bus: SimEventBus = null
) -> void:
	if manor == null or clock == null:
		return
	var env_bonus: int = manor.get_building_level("BANQUET_HALL") - 1
	var tick_id: int = clock.current_tick_id

	for pawn: PawnEntity in manor.pawns:
		if pawn.state == "ON_EXPEDITION" or pawn.state == "CAPTURED":
			continue

		var job: String = select_next_job(pawn, manor, clock)
		pawn.current_job = job
		_move_pawn_toward_zone(pawn, manor, job)
		_step_pawn_needs_and_health(pawn, manor, job, 1)

		var evs: Array[String] = pawn.step_mental_and_awakening(world_seed, tick_id, env_bonus, 1)
		if pawn.is_in_mental_break():
			_apply_mental_break_side_effects(pawn, manor)
			continue
		if evs.has("BREAK_EXTREME_DESERTION") and not pawn.is_avatar:
			manor.add_resource("MERIT_PRESTIGE", 0)

		if PawnEntity.WORK_DOMAINS.has(job):
			var rate_pm: int = _compute_domain_rate_pm(pawn, manor, job, clock)
			var walk_pm: int = _to_int(ManorState.WALK_EFFICIENCY_PM.get(job, 880), 880)
			@warning_ignore("integer_division")
			var effective_rate_pm: int = (rate_pm * walk_pm) / 1000
			var carry_key: String = pawn.pawn_id + ":" + job
			var total_pm: int = manor.get_carry_pm(carry_key) + effective_rate_pm
			while total_pm >= 1000:
				total_pm -= 1000
				_apply_job_completion(pawn, manor, job, world_seed, tick_id)
			manor.set_carry_pm(carry_key, total_pm)
			pawn.job_progress_pm = total_pm
		elif job == "MARTIAL_DRILL_TRAINING":
			var _lvl_m: bool = pawn.add_stat_xp("MAR", 12)
			manor.troop_training_pm = mini(1000, manor.troop_training_pm + 2)

	# Daily household troop upkeep on daily settlement tick
	if clock.is_daily_settlement_tick() and manor.household_troops > 0:
		@warning_ignore("integer_division")
		var troop_grain: int = maxi(1, manor.household_troops / 10)
		var _ok_tg: bool = manor.try_spend_resource("GRAIN", mini(troop_grain, manor.get_resource("GRAIN")))


static func step_lod1_macro_tick(
	manor: ManorState,
	clock: SimClock,
	world_seed: int,
	_event_bus: SimEventBus = null
) -> void:
	# Guardrail #3: Permille remainder carry/quantization in LOD 1 rate integration
	# so 6 LOD 0 ticks and 1 LOD 1 macro tick achieve tight/exact parity on peaceful yields.
	if manor == null or clock == null:
		return
	var env_bonus: int = manor.get_building_level("BANQUET_HALL") - 1
	var tick_id: int = clock.current_tick_id
	var start_tick: int = maxi(1, tick_id - MACRO_STEPS + 1)

	for pawn: PawnEntity in manor.pawns:
		if pawn.state == "ON_EXPEDITION" or pawn.state == "CAPTURED":
			continue

		var domain_accum_pm: Dictionary = {}
		for offset: int in range(MACRO_STEPS):
			var sub_tick: int = start_tick + offset
			var sub_clock: SimClock = SimClock.new(sub_tick)
			var job: String = select_next_job(pawn, manor, sub_clock)
			pawn.current_job = job
			_step_pawn_needs_and_health(pawn, manor, job, 1)

			var _evs: Array[String] = pawn.step_mental_and_awakening(world_seed, sub_tick, env_bonus, 1)
			if pawn.is_in_mental_break():
				_apply_mental_break_side_effects(pawn, manor)
				continue

			if PawnEntity.WORK_DOMAINS.has(job):
				var rate_pm: int = _compute_domain_rate_pm(pawn, manor, job, sub_clock)
				var walk_pm: int = _to_int(ManorState.WALK_EFFICIENCY_PM.get(job, 880), 880)
				@warning_ignore("integer_division")
				var effective_rate_pm: int = (rate_pm * walk_pm) / 1000
				domain_accum_pm[job] = _to_int(domain_accum_pm.get(job, 0), 0) + effective_rate_pm
			elif job == "MARTIAL_DRILL_TRAINING":
				var _lvl_m: bool = pawn.add_stat_xp("MAR", 12)
				manor.troop_training_pm = mini(1000, manor.troop_training_pm + 2)

			if sub_clock.is_daily_settlement_tick() and manor.household_troops > 0:
				@warning_ignore("integer_division")
				var troop_grain: int = maxi(1, manor.household_troops / 10)
				var _ok_tg: bool = manor.try_spend_resource("GRAIN", mini(troop_grain, manor.get_resource("GRAIN")))

		# Flush accumulated macro-tick work deltas through permille remainder carry
		for dk: Variant in domain_accum_pm.keys():
			var domain: String = str(dk)
			var delta_pm: int = _to_int(domain_accum_pm[dk], 0)
			if delta_pm <= 0:
				continue
			var carry_key: String = pawn.pawn_id + ":" + domain
			var total_pm: int = manor.get_carry_pm(carry_key) + delta_pm
			while total_pm >= 1000:
				total_pm -= 1000
				_apply_job_completion(pawn, manor, domain, world_seed, tick_id)
			manor.set_carry_pm(carry_key, total_pm)
			pawn.job_progress_pm = total_pm


static func resolve_manor_raid_defense(
	manor: ManorState,
	raid_payload: Dictionary,
	clock: SimClock,
	world_seed: int,
	is_owner_online: bool
) -> Dictionary:
	if manor == null or clock == null:
		return {"ok": false, "breached": false}

	var tick_id: int = clock.current_tick_id
	if manor.is_truce_active(tick_id):
		return {
			"ok": true,
			"repelled": true,
			"breached": false,
			"truce_blocked": true,
			"looted": {}
		}

	# Immediately promote to LOD 0 upon incoming raid
	promote_to_lod0(manor)
	manor.raid_defense_active = true

	var atk_power_var: Variant = raid_payload.get("attacker_power", {})
	var atk_power_dict: Dictionary = atk_power_var if atk_power_var is Dictionary else {}
	var atk_troops: int = maxi(1, _to_int(atk_power_dict.get("troop_count", 150), 150))
	var atk_martial: int = _to_int(atk_power_dict.get("lead_martial", 70), 70)
	var atk_lea: int = _to_int(atk_power_dict.get("lead_leadership", 70), 70)
	var siege_bonus_bp: int = _to_int(atk_power_dict.get("siege_bonus_bp", 1000), 1000)
	@warning_ignore("integer_division")
	var attacker_score: int = (atk_troops * (100 + atk_martial + atk_lea / 2) * siege_bonus_bp) / 100000

	# Defense score: Palisade wall + Watchtower traps + PATROL pawns + Household troops
	var patrol_power: int = 0
	var defenders: Array[PawnEntity] = []
	for p: PawnEntity in manor.pawns:
		if p.state == "IN_MANOR" and p.health_state != "SEVERE_WOUND":
			defenders.append(p)
			var p_mult: int = 2 if p.get_work_priority("PATROL") <= 2 else 1
			patrol_power += (p.get_effective_stat("LEA") + p.get_effective_stat("MAR")) * p_mult

	var watchtower_lvl: int = manor.get_building_level("WATCHTOWER_WALL")
	var defense_score: int = manor.household_troops + patrol_power + manor.trap_power + (manor.wall_hp / 5) + watchtower_lvl * 120
	var rng_mod: int = DeterministicRNG.roll_range(world_seed, tick_id, StateHasher.crc32_bytes(manor.manor_id.to_utf8_buffer()), 7701, -40, 40)
	defense_score = maxi(1, defense_score + rng_mod)

	var breached: bool = attacker_score > defense_score
	var wall_dmg: int = mini(manor.wall_hp, maxi(50, attacker_score / 2))
	manor.wall_hp = maxi(0, manor.wall_hp - wall_dmg)

	var troop_loss: int = mini(manor.household_troops, maxi(10, atk_troops / 5))
	manor.household_troops = maxi(0, manor.household_troops - troop_loss)

	var looted: Dictionary = {}
	if breached:
		# Hidden Vault protection: vault_protected_bp (4000..6500 bp) is untouchable
		var stealable_bp: int = DtoSchemas.SCALE_BP - manor.vault_protected_bp
		for rk: String in ["GRAIN", "COIN", "IRON", "WOOD", "WEAPONS"]:
			var stock: int = manor.get_resource(rk)
			@warning_ignore("integer_division")
			var max_loot: int = (stock * stealable_bp) / DtoSchemas.SCALE_BP
			@warning_ignore("integer_division")
			var actual_loot: int = mini(max_loot, max_loot / 2)
			if actual_loot > 0:
				var _spent: bool = manor.try_spend_resource(rk, actual_loot)
				looted[rk] = actual_loot

		# Offline Sworn Retainer Non-Permadeath & 5-day (120 ticks) Bribe Immunity
		for p: PawnEntity in defenders:
			if not is_owner_online:
				p.health_state = "SEVERE_WOUND"
				p.state = "WOUNDED"
				p.wound_recovery_pm = 0
				p.offline_bribe_immune_until_tick = tick_id + 120
			else:
				p.health_state = "LIGHT_WOUND"
			p.add_thought("MANOR_RAID_BREACHED", -8, 24)

		# Post-Raid Imperial Truce Shield (720 ticks)
		manor.truce_shield_until_tick = tick_id + 720
	else:
		for p: PawnEntity in defenders:
			p.add_thought("RAID_REPELLED", 8, 24)
			var _xp: bool = p.add_stat_xp("LEA", 15)

	manor.raid_defense_active = false
	var summary: Dictionary = {
		"tick_id": tick_id,
		"attacker_entity_id": str(raid_payload.get("attacker_entity_id", "")),
		"attacker_score": attacker_score,
		"defense_score": defense_score,
		"breached": breached,
		"wall_damage": wall_dmg,
		"troop_loss": troop_loss,
		"looted": looted,
		"truce_shield_until_tick": manor.truce_shield_until_tick
	}
	manor.raid_history.append(summary)
	return summary


static func dispatch_expedition_from_manor(
	manor: ManorState,
	officer_ids: Array[String],
	troop_count: int,
	carried_grain: int,
	cargo: Dictionary,
	path_edge_ids: Array[String],
	unit_type: String,
	clock: SimClock,
	event_bus: SimEventBus
) -> Dictionary:
	if manor == null or clock == null or event_bus == null:
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE}
	if unit_type != "ARMY" and unit_type != "CARAVAN":
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA}
	if troop_count <= 0 or troop_count > manor.household_troops:
		return {"ok": false, "error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE}
	if carried_grain < 0 or carried_grain > manor.get_resource("GRAIN"):
		return {"ok": false, "error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE}
	if path_edge_ids.is_empty():
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA}

	# Verify cargo availability & officer availability atomically BEFORE deducting anything
	for k_var: Variant in cargo.keys():
		var rk: String = str(k_var)
		var amt: int = _to_int(cargo[k_var], 0)
		if amt < 0 or not DtoSchemas.RESOURCE_KEYS.has(rk) or manor.get_resource(rk) < amt:
			return {"ok": false, "error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE}

	var selected_pawns: Array[PawnEntity] = []
	for oid: String in officer_ids:
		var p: PawnEntity = manor.get_pawn_by_id(oid)
		if p == null or p.state != "IN_MANOR":
			return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE}
		selected_pawns.append(p)

	# Atomic deduction & officer state transition
	manor.household_troops -= troop_count
	var _sg: bool = manor.try_spend_resource("GRAIN", carried_grain)
	var clean_cargo: Dictionary = {}
	for k_var: Variant in cargo.keys():
		var rk: String = str(k_var)
		var amt: int = _to_int(cargo[k_var], 0)
		if amt > 0:
			var _sc: bool = manor.try_spend_resource(rk, amt)
			clean_cargo[rk] = amt

	var officer_dtos: Array[Dictionary] = []
	var morale_sum: int = 0
	for p: PawnEntity in selected_pawns:
		p.state = "ON_EXPEDITION"
		morale_sum += p.get_need("MORALE")
		officer_dtos.append({
			"pawn_id": p.pawn_id,
			"leadership": p.get_effective_stat("LEA"),
			"martial": p.get_effective_stat("MAR"),
			"intelligence": p.get_effective_stat("INT"),
			"traits": p.traits.duplicate()
		})

	@warning_ignore("integer_division")
	var avg_morale: int = 8500 if selected_pawns.is_empty() else (morale_sum / selected_pawns.size())
	var payload: Dictionary = {
		"event": SimEventBus.EVENT_MICRO_TO_MACRO_EXPEDITION_DISPATCHED,
		"tick_id": clock.current_tick_id,
		"player_id": manor.player_id,
		"manor_id": manor.manor_id,
		"origin_node_id": manor.host_node_id,
		"unit_type": unit_type,
		"officers": officer_dtos,
		"troop_count": troop_count,
		"morale_bp": clampi(avg_morale, 0, 10000),
		"carried_grain": carried_grain,
		"cargo": clean_cargo,
		"path_edge_ids": path_edge_ids.duplicate(),
		"standing_doctrine": manor.standing_doctrine.duplicate(true)
	}
	var seq_id: int = event_bus.emit(
		SimEventBus.EVENT_MICRO_TO_MACRO_EXPEDITION_DISPATCHED,
		payload,
		clock.current_tick_id
	)
	return {"ok": true, "seq_id": seq_id, "payload": payload}
