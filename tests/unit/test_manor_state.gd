class_name TestManorState
extends HarnessTestCase


func _as_int(v: Variant, fallback: int = 0) -> int:
	if v is int:
		var iv: int = v
		return iv
	if v is float:
		var fv: float = v
		return int(fv)
	return fallback


func test_32x32_grid_and_8_zones() -> void:
	var manor: ManorState = ManorState.new("m_grid", "p_grid")
	assert_eq(ManorState.ZONE_TYPES.size(), 8, "Must define 8 canonical zone types")
	assert_eq(manor.zones.size(), 8, "Manor initializes 8 logical zones")
	assert_eq(manor.tile_zone_map.size(), 32 * 32, "32x32 grid must have exactly 1024 tiles")

	var seen_zones: Dictionary = {}
	for y: int in range(32):
		for x: int in range(32):
			var z: String = manor.get_tile_zone(x, y)
			assert_true(ManorState.ZONE_TYPES.has(z), "Tile (%d,%d) zone %s must be valid" % [x, y, z])
			seen_zones[z] = true

	for zt: String in ManorState.ZONE_TYPES:
		assert_has_key(seen_zones, zt, "All 8 zone types must appear on the 32x32 grid: %s" % zt)
		var center: Vector2i = manor.get_zone_center(zt)
		assert_in_range(center.x, 0, 31, "%s center x in [0,31]" % zt)
		assert_in_range(center.y, 0, 31, "%s center y in [0,31]" % zt)

	# Out-of-bounds query falls back safely
	assert_eq(manor.get_tile_zone(-1, -1), "ZONE_STOCKPILE", "Out of bounds returns ZONE_STOCKPILE")
	assert_eq(manor.get_tile_zone(99, 99), "ZONE_STOCKPILE", "Out of bounds returns ZONE_STOCKPILE")


func test_10_upgradable_buildings_and_derived_caps() -> void:
	var manor: ManorState = ManorState.new("m_bld", "p_bld")
	assert_eq(ManorState.BUILDING_IDS.size(), 10, "Must define 10 upgradable buildings")
	for bid: String in ManorState.BUILDING_IDS:
		assert_eq(manor.get_building_level(bid), 1, "%s initializes at Lv.1" % bid)

	# Insufficient resources blocks upgrade
	manor.set_resource("WOOD", 10)
	manor.set_resource("COIN", 10)
	assert_false(manor.upgrade_building("MAIN_HALL"), "Upgrade must fail without enough WOOD/COIN")
	assert_eq(manor.get_building_level("MAIN_HALL"), 1, "Level unchanged on failed upgrade")

	# Upgrade MAIN_HALL from Lv.1 to Lv.5 -> max retainers scales 4..12
	manor.set_resource("WOOD", 5000)
	manor.set_resource("COIN", 5000)
	assert_eq(manor.get_max_retainers(), 4, "Lv.1 MAIN_HALL allows 4 retainers")
	for expected_lvl: int in [2, 3, 4, 5]:
		assert_true(manor.upgrade_building("MAIN_HALL"), "Upgrade MAIN_HALL to Lv.%d" % expected_lvl)
		assert_eq(manor.get_building_level("MAIN_HALL"), expected_lvl, "MAIN_HALL is Lv.%d" % expected_lvl)
	assert_false(manor.upgrade_building("MAIN_HALL"), "Cannot upgrade beyond Lv.5")
	assert_eq(manor.get_max_retainers(), 12, "Lv.5 MAIN_HALL allows 12 retainers")

	# Unknown building rejected
	assert_false(manor.upgrade_building("NON_EXISTENT_BLDG"), "Unknown building cannot upgrade")

	# Watchtower & Barracks derived caps
	manor.set_building_level("WATCHTOWER_WALL", 5)
	assert_eq(manor.max_wall_hp, 6000, "Lv.5 WATCHTOWER_WALL max_wall_hp == 6000")
	assert_eq(manor.trap_power, 440, "Lv.5 WATCHTOWER_WALL trap_power == 440")
	manor.set_building_level("BARRACKS_DRILL", 5)
	assert_eq(manor.max_troops, 3000, "Lv.5 BARRACKS_DRILL max_troops == 3000")
	manor.set_building_level("QUARTERS", 5)
	assert_eq(manor.get_quarters_rest_mult_pm(), 1600, "Lv.5 QUARTERS rest mult == 1600 pm")
	manor.set_building_level("MILITARY_FARM", 5)
	assert_eq(manor.get_facility_mult_pm("AGRICULTURE"), 1480, "Lv.5 MILITARY_FARM facility mult == 1480 pm")


func test_8_resource_ledger_non_negativity_and_policies() -> void:
	var manor: ManorState = ManorState.new("m_eco", "p_eco")
	assert_eq(DtoSchemas.RESOURCE_KEYS.size(), 8, "Must track 8 canonical resources")

	for rk: String in DtoSchemas.RESOURCE_KEYS:
		manor.set_resource(rk, -999)
		assert_eq(manor.get_resource(rk), 0, "%s clamps negative set_resource to 0" % rk)
		var after_neg: int = manor.add_resource(rk, -50)
		assert_eq(after_neg, 0, "%s clamps add_resource floor at 0" % rk)
		var after_pos: int = manor.add_resource(rk, 250)
		assert_eq(after_pos, 250, "%s add_resource increases to 250" % rk)

	assert_false(manor.try_spend_resource("GRAIN", -10), "Negative spend must fail")
	assert_false(manor.try_spend_resource("GRAIN", 300), "Overspend must fail")
	assert_eq(manor.get_resource("GRAIN"), 250, "Failed spend leaves resource untouched")
	assert_true(manor.try_spend_resource("GRAIN", 100), "Valid spend succeeds")
	assert_eq(manor.get_resource("GRAIN"), 150, "Valid spend deducts exact amount")
	assert_false(manor.try_spend_resource("UNKNOWN_RES", 1), "Unknown resource spend fails")

	assert_eq(ManorState.RATION_POLICIES, ["COARSE", "STANDARD", "FEAST"], "3 ration policies defined")
	manor.ration_quality = "FEAST"
	manor.wine_policy_enabled = false
	assert_eq(manor.ration_quality, "FEAST", "Ration policy updated")
	assert_false(manor.wine_policy_enabled, "Wine policy toggled off")


func test_gear_tiers_tech_tree_retainer_cap_vault_and_roundtrip() -> void:
	var manor: ManorState = ManorState.new("m_cap", "p_cap")

	# 6 Quality Tiers (800..1800)
	assert_eq(ManorState.GEAR_TIERS.size(), 6, "Must define 6 gear quality tiers")
	assert_eq(_as_int(ManorState.GEAR_TIER_MULT_PM.get("POOR", 0)), 800, "POOR == 800 pm")
	assert_eq(_as_int(ManorState.GEAR_TIER_MULT_PM.get("NORMAL", 0)), 1000, "NORMAL == 1000 pm")
	assert_eq(_as_int(ManorState.GEAR_TIER_MULT_PM.get("GOOD", 0)), 1150, "GOOD == 1150 pm")
	assert_eq(_as_int(ManorState.GEAR_TIER_MULT_PM.get("EXCELLENT", 0)), 1300, "EXCELLENT == 1300 pm")
	assert_eq(_as_int(ManorState.GEAR_TIER_MULT_PM.get("MASTERWORK", 0)), 1500, "MASTERWORK == 1500 pm")
	assert_eq(_as_int(ManorState.GEAR_TIER_MULT_PM.get("LEGENDARY", 0)), 1800, "LEGENDARY == 1800 pm")

	manor.queue_crafting_order("HALBERD", 0)
	assert_eq(manor.crafting_queue.size(), 0, "Zero-count crafting order ignored")
	manor.queue_crafting_order("HALBERD", 3)
	assert_eq(manor.crafting_queue.size(), 1, "Valid crafting order queued")

	# 3-branch Tech Research Tree
	assert_eq(ManorState.TECH_BRANCHES.keys().size(), 3, "Must define 3 tech branches")
	assert_has_key(ManorState.TECH_BRANCHES, "DOMESTIC", "DOMESTIC branch exists")
	assert_has_key(ManorState.TECH_BRANCHES, "MILITARY", "MILITARY branch exists")
	assert_has_key(ManorState.TECH_BRANCHES, "STRATAGEM", "STRATAGEM branch exists")

	# Hidden Vault (4000..6500 bp)
	assert_eq(manor.vault_protected_bp, 4000, "Lv.1 GRANARY_VAULT protects 4000 bp")
	manor.set_building_level("GRANARY_VAULT", 5)
	assert_eq(manor.vault_protected_bp, 6000, "Lv.5 GRANARY_VAULT protects 6000 bp")
	manor.unlocked_techs.append("DEEP_VAULT")
	manor.recompute_building_derived_caps()
	assert_eq(manor.vault_protected_bp, 6500, "Lv.5 GRANARY_VAULT + DEEP_VAULT protects 6500 bp")

	# Up to 12 retainers cap (+1 avatar allowed without consuming retainer slots)
	var av: PawnEntity = PawnEntity.new("av_01", "Lord_Avatar", true)
	assert_true(manor.add_pawn(av), "Avatar added")
	assert_false(manor.add_pawn(av), "Duplicate pawn_id rejected")
	for i: int in range(12):
		var ret: PawnEntity = PawnEntity.new("ret_%02d" % i, "Ret_%d" % i, false)
		assert_true(manor.add_pawn(ret), "Retainer %d/12 must be added" % (i + 1))
	assert_eq(manor.get_retainer_count(), 12, "Retainer count == 12")
	var ret_13: PawnEntity = PawnEntity.new("ret_13", "Overflow_Retainer", false)
	assert_false(manor.add_pawn(ret_13), "13th retainer must be rejected at MAX_RETAINERS=12 cap")

	# Truce shield & serialization round-trip
	manor.truce_shield_until_tick = 1000
	assert_true(manor.is_truce_active(999), "Truce active before expiry")
	assert_false(manor.is_truce_active(1000), "Truce expires at exact boundary tick")

	manor.set_carry_pm("av_01:AGRICULTURE", 450)
	var dict_snap: Dictionary = manor.to_dict()
	assert_true(StateHasher.validate_deterministic_types(dict_snap), "ManorState.to_dict() uses only deterministic types")
	assert_false(StateHasher.has_floats(dict_snap), "ManorState.to_dict() contains zero floats")

	var restored: ManorState = ManorState.from_dict(dict_snap)
	assert_eq(StateHasher.sha256_dict(restored.to_dict()), StateHasher.sha256_dict(dict_snap), "ManorState round-trip SHA256 identical")
	assert_eq(restored.get_retainer_count(), 12, "Restored retainer count == 12")
	assert_eq(restored.vault_protected_bp, 6500, "Restored vault_protected_bp == 6500")
	assert_eq(restored.get_carry_pm("av_01:AGRICULTURE"), 450, "Restored remainder carry == 450")
