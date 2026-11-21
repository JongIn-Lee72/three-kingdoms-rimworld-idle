class_name TestSocialBanquetService
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


func test_directed_affinity_graph_and_sworn_siblings_combat_bonus() -> void:
	var svc: SocialBanquetService = SocialBanquetService.new()

	# Directed asymmetry & [-100, +100] clamping
	assert_eq(svc.set_affinity("liu", "guan", 150), 100, "Upper clamp to +100")
	assert_eq(svc.set_affinity("guan", "liu", -150), -100, "Lower clamp to -100")
	assert_eq(svc.get_affinity("liu", "guan"), 100, "Directed edge liu->guan == 100")
	assert_eq(svc.get_affinity("guan", "liu"), -100, "Directed edge guan->liu == -100 (asymmetric)")
	assert_eq(svc.set_affinity("liu", "liu", 50), 0, "Self-affinity returns 0")

	# Mutual >= 75 required for SWORN_SIBLING
	var _s1: int = svc.set_affinity("guan", "liu", 74)
	var fail_sworn: Dictionary = svc.form_sworn_siblings("liu", "guan")
	assert_false(_as_bool(fail_sworn.get("ok", true), true), "Asymmetric 100 vs 74 fails sworn sibling check")
	assert_eq(svc.get_joint_combat_bonus_pm(["liu", "guan"]), 0, "Non-siblings get 0 joint combat bonus")

	var _s2: int = svc.adjust_affinity("guan", "liu", 1)  # 74 -> 75
	assert_eq(svc.get_affinity("guan", "liu"), 75, "Adjusted affinity reaches 75")
	var ok_sworn: Dictionary = svc.form_sworn_siblings("liu", "guan")
	assert_true(_as_bool(ok_sworn.get("ok", false), false), "Mutual >= 75 succeeds")
	assert_eq(_as_int(ok_sworn.get("joint_combat_bonus_pm", 0), 0), 150, "Joint bonus is 150 pm (+15%)")
	assert_true(svc.are_sworn_siblings("liu", "guan"), "are_sworn_siblings true")
	assert_eq(svc.get_joint_combat_bonus_pm(["liu"]), 0, "Single officer gets 0 bonus")
	assert_eq(svc.get_joint_combat_bonus_pm(["zhang", "liu", "guan"]), 150, "Sworn pair in roster yields +150 pm")

	# Relation tags validation
	assert_true(svc.add_relation_tag("liu", "zhang", "BENEFACTOR"), "Valid relation tag added")
	assert_false(svc.add_relation_tag("liu", "zhang", "INVALID_TAG"), "Invalid relation tag rejected")
	assert_eq(svc.get_relations("liu", "zhang").size(), 1, "Only valid tag stored")


func test_host_banquet_resources_drinker_and_scholar_attraction() -> void:
	var svc: SocialBanquetService = SocialBanquetService.new()
	var manor: ManorState = ManorState.new("man_banq", "lord_liu")
	manor.set_resource("HERBS_WINE", 40)
	manor.set_resource("GRAIN", 100)
	var _up: bool = manor.upgrade_building("BANQUET_HALL")  # lvl 2

	var host: PawnEntity = PawnEntity.new("liu_bei", "Liu Bei", true)
	host.set_stat("CHA", 90)
	host.traits = ["T_SCHOLAR"]
	host.origin_archetype = "ORIGIN_CHIVALROUS_HERO"
	host.set_need("MORALE", 5000)

	var drinker_guest: PawnEntity = PawnEntity.new("zhang_fei", "Zhang Fei", false)
	drinker_guest.traits = ["T_DRINKER"]
	drinker_guest.ticks_since_wine = 48
	drinker_guest.set_need("MORALE", 4000)
	drinker_guest.set_need("FOOD", 3000)

	var clk: SimClock = SimClock.new(20)

	# Insufficient resource checks
	var no_wine: Dictionary = svc.host_banquet(manor, host, [drinker_guest], 41, 10, clk, 18401)
	assert_false(_as_bool(no_wine.get("ok", true), true), "Insufficient HERBS_WINE rejected")
	var no_grain: Dictionary = svc.host_banquet(manor, host, [drinker_guest], 10, 101, clk, 18401)
	assert_false(_as_bool(no_grain.get("ok", true), true), "Insufficient GRAIN rejected")
	var neg_cost: Dictionary = svc.host_banquet(manor, host, [drinker_guest], -1, 10, clk, 18401)
	assert_false(_as_bool(neg_cost.get("ok", true), true), "Negative wine_cost rejected")

	# Valid banquet with wine_cost = 25, grain_cost = 60
	var bq: Dictionary = svc.host_banquet(manor, host, [drinker_guest], 25, 60, clk, 18401)
	assert_true(_as_bool(bq.get("ok", false), false), "Banquet hosted")
	assert_eq(manor.get_resource("HERBS_WINE"), 15, "Consumed 25 HERBS_WINE (40 -> 15)")
	assert_eq(manor.get_resource("GRAIN"), 40, "Consumed 60 GRAIN (100 -> 40)")

	assert_gt(drinker_guest.get_need("MORALE"), 4000, "Guest MORALE restored")
	assert_eq(drinker_guest.get_need("FOOD"), 4500, "Guest FOOD increased by +1500")
	assert_eq(drinker_guest.ticks_since_wine, 0, "T_DRINKER ticks_since_wine reset to 0")
	assert_true(drinker_guest.has_thought("DRINKER_HIGH_SPIRITS"), "T_DRINKER receives DRINKER_HIGH_SPIRITS")
	assert_true(drinker_guest.has_thought("GRAND_BANQUET"), "Participant receives GRAND_BANQUET")
	assert_eq(svc.get_affinity("liu_bei", "zhang_fei"), 15, "Affinity gained 10 + min(15, 25/5) = 15")
	assert_eq(svc.get_affinity("zhang_fei", "liu_bei"), 15, "Mutual affinity gained 15")

	# Verify T_SCHOLAR boosts recruit_chance_bp over non-scholar host
	var plain_host: PawnEntity = PawnEntity.new("plain", "Plain", true)
	plain_host.set_stat("CHA", 90)
	manor.set_resource("HERBS_WINE", 500)
	manor.set_resource("GRAIN", 500)
	var bq_plain: Dictionary = svc.host_banquet(manor, plain_host, [], 5, 10, clk, 18401)
	assert_gt(_as_int(bq.get("recruit_chance_bp", 0), 0), _as_int(bq_plain.get("recruit_chance_bp", 0), 0), "T_SCHOLAR + origin yields higher recruit_chance_bp")

	# Verify deterministic wandering talent attraction across ticks
	var saw_wanderer: bool = false
	for t: int in range(20, 40):
		var c_t: SimClock = SimClock.new(t)
		var r: Dictionary = svc.host_banquet(manor, host, [], 5, 5, c_t, 18401)
		if _as_bool(r.get("talent_attracted", false), false):
			saw_wanderer = true
			var wt: Dictionary = _as_dict(r.get("wandering_talent", {}))
			assert_false(str(wt.get("pawn_id", "")).is_empty(), "Wandering talent pawn_id generated")
			assert_eq(_as_int(wt.get("initial_affinity", 0), 0), 40, "Wandering talent starts at 40 initial_affinity")
			break
	assert_true(saw_wanderer, "Wandering talent attracted within 20 deterministic ticks")

	# Zero wine banquet does not trigger DRINKER_HIGH_SPIRITS
	var dry_drinker: PawnEntity = PawnEntity.new("dry_d", "DryDrinker", false)
	dry_drinker.traits = ["T_DRINKER"]
	var _dry_bq: Dictionary = svc.host_banquet(manor, plain_host, [dry_drinker], 0, 10, clk, 18401)
	assert_false(dry_drinker.has_thought("DRINKER_HIGH_SPIRITS"), "Zero-wine banquet does not trigger DRINKER_HIGH_SPIRITS")

	# Serialization parity
	var snap: Dictionary = svc.to_dict()
	assert_false(StateHasher.has_floats(snap), "SocialBanquetService.to_dict() has no floats")
	var restored: SocialBanquetService = SocialBanquetService.from_dict(snap)
	assert_eq(StateHasher.sha256_dict(snap), StateHasher.sha256_dict(restored.to_dict()), "SocialBanquetService SHA-256 round-trip parity")
