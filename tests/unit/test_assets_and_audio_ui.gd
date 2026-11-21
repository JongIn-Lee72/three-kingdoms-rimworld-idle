class_name TestAssetsAndAudioUI
extends HarnessTestCase

var _ui_nodes: Array[Node] = []


func _track_ui(node: Node) -> Node:
	if node != null and not _ui_nodes.has(node):
		_ui_nodes.append(node)
		var loop: MainLoop = Engine.get_main_loop()
		if loop is SceneTree:
			var st: SceneTree = loop
			if st.root != null and node.get_parent() == null:
				st.root.add_child(node)
	return node


func after_each() -> void:
	for i: int in range(_ui_nodes.size() - 1, -1, -1):
		var n: Node = _ui_nodes[i]
		if n != null and is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_ui_nodes.clear()


func _as_bool(v: Variant, fallback: bool = false) -> bool:
	if v is bool:
		var bv: bool = v
		return bv
	return fallback


func _as_int(v: Variant, fallback: int = 0) -> int:
	if v is int:
		var iv: int = v
		return iv
	if v is float:
		var fv: float = v
		return int(fv)
	return fallback


func test_asset_registry_cc0_tiles_sprites_backgrounds_and_theme() -> void:
	var reg: AssetRegistry = AssetRegistry.new()

	# 1. All 8 Manor zone tiles + default grass fallback -> non-null 16x16 AtlasTexture
	var zone_checks: Array[String] = []
	for zt: String in ManorState.ZONE_TYPES:
		zone_checks.append(zt)
	zone_checks.append("DEFAULT_GRASS_FALLBACK")
	assert_eq(zone_checks.size(), 9, "8 Manor zones + default grass tile checked")

	for zname: String in zone_checks:
		var ztex: Texture2D = reg.get_zone_tile(zname)
		assert_not_null(ztex, "Zone tile non-null for " + zname)
		assert_true(ztex is AtlasTexture, "Zone tile is AtlasTexture for " + zname)
		if ztex is AtlasTexture:
			var at: AtlasTexture = ztex
			assert_not_null(at.atlas, "Zone AtlasTexture has backing atlas for " + zname)
			assert_eq(at.region.size, Vector2(16, 16), "Zone tile region is 16x16 for " + zname)
		assert_eq(ztex.get_size(), Vector2(16, 16), "Zone tile get_size() is 16x16 for " + zname)

	# 2. All 8 resource icons -> non-null 16x16 AtlasTexture
	assert_eq(DtoSchemas.RESOURCE_KEYS.size(), 8, "DtoSchemas.RESOURCE_KEYS has 8 resources")
	for rk: String in DtoSchemas.RESOURCE_KEYS:
		var rtex: Texture2D = reg.get_resource_icon(rk)
		assert_not_null(rtex, "Resource icon non-null for " + rk)
		assert_true(rtex is AtlasTexture, "Resource icon is AtlasTexture for " + rk)
		assert_eq(rtex.get_size(), Vector2(16, 16), "Resource icon size is 16x16 for " + rk)

	# 3. Avatar & role pawn sprites
	var avatar_tex: Texture2D = reg.get_pawn_sprite(true, "")
	var scholar_tex: Texture2D = reg.get_pawn_sprite(false, "SCHOLAR")
	var martial_tex: Texture2D = reg.get_pawn_sprite(false, "GENERAL")
	var noble_tex: Texture2D = reg.get_pawn_sprite(false, "LORD")
	var rebel_tex: Texture2D = reg.get_pawn_sprite(false, "REBEL")
	var retainer_tex: Texture2D = reg.get_pawn_sprite(false, "LABORER")

	var pawn_sprites: Array[Texture2D] = [
		avatar_tex, scholar_tex, martial_tex, noble_tex, rebel_tex, retainer_tex
	]
	for idx: int in range(pawn_sprites.size()):
		var ptex: Texture2D = pawn_sprites[idx]
		assert_not_null(ptex, "Pawn sprite %d non-null" % idx)
		assert_true(ptex is AtlasTexture, "Pawn sprite %d is AtlasTexture" % idx)
		assert_eq(ptex.get_size(), Vector2(16, 16), "Pawn sprite %d is 16x16" % idx)
	assert_ne(avatar_tex, scholar_tex, "Avatar sprite distinct from scholar role sprite")
	assert_ne(scholar_tex, martial_tex, "Scholar sprite distinct from martial role sprite")
	assert_ne(noble_tex, rebel_tex, "Noble sprite distinct from rebel role sprite")

	# 4. Emotes: AWAKENED_VALOR, BREAK_MINOR_BINGE, raid active, normal == null
	var em_awakened: Texture2D = reg.get_emote_texture("AWAKENED_VALOR", false)
	var em_minor: Texture2D = reg.get_emote_texture("BREAK_MINOR_BINGE", false)
	var em_raid: Texture2D = reg.get_emote_texture("NORMAL", true)
	var em_major: Texture2D = reg.get_emote_texture("BREAK_MAJOR_BERSERK", false)
	var em_normal: Texture2D = reg.get_emote_texture("NORMAL", false)

	assert_not_null(em_awakened, "AWAKENED_VALOR emote non-null")
	assert_not_null(em_minor, "BREAK_MINOR_BINGE emote non-null")
	assert_not_null(em_raid, "Raid active emote non-null")
	assert_not_null(em_major, "Major mental break emote non-null")
	assert_eq(em_raid, em_major, "Raid active and major break share combat emote")
	assert_ne(em_awakened, em_minor, "Awakened emote distinct from minor break emote")
	assert_ne(em_awakened, em_raid, "Awakened emote distinct from combat emote")
	assert_null(em_normal, "NORMAL non-raid state returns null emote")

	# 5. All 4 macro node tiers
	var macro_tiers: Array[String] = ["CAPITAL", "CITY", "PASS", "COUNTY"]
	for tier: String in macro_tiers:
		var mtex: Texture2D = reg.get_macro_node_icon(tier)
		assert_not_null(mtex, "Macro node icon non-null for " + tier)
		assert_true(mtex is AtlasTexture, "Macro node icon is AtlasTexture for " + tier)
		assert_eq(mtex.get_size(), Vector2(16, 16), "Macro node icon size is 16x16 for " + tier)

	# 6. All 4 army unit types
	var unit_types: Array[String] = ["ARMY", "CARAVAN", "RAID_PARTY", "COALITION_FORCE"]
	for utype: String in unit_types:
		var utex: Texture2D = reg.get_army_icon(utype)
		assert_not_null(utex, "Army unit icon non-null for " + utype)
		assert_true(utex is AtlasTexture, "Army unit icon is AtlasTexture for " + utype)
		assert_eq(utex.get_size(), Vector2(16, 16), "Army unit icon size is 16x16 for " + utype)

	# 7. MAP_BG (1376x768) & CREST_BANNER (1376x768)
	var map_bg: Texture2D = reg.get_texture(AssetRegistry.MAP_BG)
	assert_not_null(map_bg, "MAP_BG texture loaded")
	if map_bg != null:
		assert_eq(map_bg.get_width(), 1376, "MAP_BG width == 1376")
		assert_eq(map_bg.get_height(), 768, "MAP_BG height == 768")

	var crest_banner: Texture2D = reg.get_texture(AssetRegistry.CREST_BANNER)
	assert_not_null(crest_banner, "CREST_BANNER texture loaded")
	if crest_banner != null:
		assert_eq(crest_banner.get_width(), 1376, "CREST_BANNER width == 1376")
		assert_eq(crest_banner.get_height(), 768, "CREST_BANNER height == 768")

	assert_null(reg.get_texture(""), "Empty texture path returns null")

	# 8. Gold/Slate 9-slice StyleBoxTexture panels
	var gold_sb: StyleBoxTexture = reg.build_panel_stylebox(true)
	var slate_sb: StyleBoxTexture = reg.build_panel_stylebox(false)
	assert_not_null(gold_sb, "Gold 9-slice StyleBoxTexture non-null")
	assert_not_null(slate_sb, "Slate 9-slice StyleBoxTexture non-null")
	assert_ne(gold_sb, slate_sb, "Gold and Slate StyleBoxTextures are distinct")
	assert_not_null(gold_sb.texture, "Gold StyleBoxTexture has border texture")
	assert_not_null(slate_sb.texture, "Slate StyleBoxTexture has border texture")
	assert_eq(gold_sb.texture_margin_left, 24.0, "Gold 9-slice left margin == 24.0")
	assert_eq(gold_sb.texture_margin_right, 24.0, "Gold 9-slice right margin == 24.0")
	assert_eq(gold_sb.modulate_color, AssetRegistry.COLOR_LACQUER_PANEL, "Gold panel uses COLOR_LACQUER_PANEL")
	assert_eq(slate_sb.modulate_color, AssetRegistry.COLOR_SLATE_PANEL, "Slate panel uses COLOR_SLATE_PANEL")

	# 9. Three Kingdoms Theme
	var built_theme: Theme = reg.build_three_kingdoms_theme()
	assert_not_null(built_theme, "build_three_kingdoms_theme() returns non-null Theme")
	assert_true(built_theme.has_stylebox("panel", "PanelContainer"), "Theme styles PanelContainer panel")
	assert_true(built_theme.has_stylebox("panel", "Panel"), "Theme styles Panel panel")
	assert_true(built_theme.has_stylebox("normal", "Button"), "Theme styles Button normal")
	assert_true(built_theme.has_stylebox("hover", "Button"), "Theme styles Button hover")
	assert_true(built_theme.has_stylebox("pressed", "Button"), "Theme styles Button pressed")
	assert_true(built_theme.has_stylebox("tab_selected", "TabContainer"), "Theme styles TabContainer tab_selected")
	assert_true(built_theme.has_color("font_color", "Label"), "Theme defines Label font_color")
	assert_true(built_theme.has_stylebox("normal", "LineEdit"), "Theme styles LineEdit normal")
	assert_true(built_theme.has_stylebox("normal", "TextEdit"), "Theme styles TextEdit normal")
	assert_eq(reg.build_three_kingdoms_theme(), built_theme, "Theme is cached on repeat build")

	var stats: Dictionary = reg.get_loaded_asset_stats()
	assert_true(_as_bool(stats.get("theme_built", false)), "Stats report theme_built == true")
	assert_gt(_as_int(stats.get("textures_cached", 0)), 0, "Stats report cached textures > 0")
	assert_gt(_as_int(stats.get("atlases_cached", 0)), 0, "Stats report cached atlases > 0")
	assert_eq(_as_int(stats.get("styleboxes_cached", 0)), 2, "Stats report 2 cached styleboxes")


func test_audio_manager_loads_cc0_bgm_and_16_sfx_with_mute_and_telemetry() -> void:
	var am: AudioManager = AudioManager.new()
	var _tracked: Node = _track_ui(am)

	assert_eq(am.get_loaded_bgm_count(), 1, "AudioManager preloads 1 BGM track")
	assert_eq(am.get_loaded_sfx_count(), 16, "AudioManager preloads all 16 SFX streams")
	assert_false(am.is_muted(), "AudioManager starts unmuted")

	assert_true(am.play_bgm("MAIN_THREE_KINGDOMS"), "play_bgm('MAIN_THREE_KINGDOMS') succeeds")
	assert_false(am.play_bgm("NONEXISTENT_BGM"), "play_bgm('NONEXISTENT_BGM') returns false")

	assert_true(am.play_sfx("UI_CLICK"), "play_sfx('UI_CLICK') returns true")
	assert_true(am.play_sfx("DUEL_CLASH"), "play_sfx('DUEL_CLASH') returns true")
	assert_true(am.play_sfx("COIN_TRADE"), "play_sfx('COIN_TRADE') returns true")
	assert_false(am.play_sfx("NONEXISTENT_EVENT"), "play_sfx('NONEXISTENT_EVENT') returns false")

	var events: Array[String] = am.get_played_events()
	assert_eq(events.size(), 3, "Only valid SFX events recorded in telemetry")
	assert_eq(events[0], "UI_CLICK", "1st recorded event is UI_CLICK")
	assert_eq(events[1], "DUEL_CLASH", "2nd recorded event is DUEL_CLASH")
	assert_eq(events[2], "COIN_TRADE", "3rd recorded event is COIN_TRADE")

	am.set_muted(true)
	assert_true(am.is_muted(), "set_muted(true) sets is_muted() == true")
	assert_true(am.play_bgm("MAIN_THREE_KINGDOMS"), "play_bgm while muted returns true safely")
	assert_true(am.play_sfx("GAZETTE_OPEN"), "play_sfx while muted records telemetry and returns true")

	am.set_muted(false)
	assert_false(am.is_muted(), "set_muted(false) restores is_muted() == false")
	am.stop_bgm()
	am.clear_played_events()
	assert_eq(am.get_played_events().size(), 0, "clear_played_events() empties telemetry buffer")


func test_upgraded_client_ui_canvases_audio_wiring_and_mute_toggle() -> void:
	var cc: ClientController = ClientController.new()
	var _tracked: Node = _track_ui(cc)

	assert_not_null(cc.theme, "ClientController applies Three Kingdoms theme")
	assert_not_null(cc.asset_registry, "ClientController owns AssetRegistry")
	assert_not_null(cc.audio_manager, "ClientController owns AudioManager")
	assert_not_null(cc._header_banner, "ClientController builds _header_banner")
	if cc._header_banner != null:
		assert_not_null(cc._header_banner.texture, "_header_banner has CREST_BANNER texture")

	assert_not_null(cc.manor_view, "ManorGridView instantiated")
	assert_not_null(cc.manor_view.get_canvas_node(), "manor_view.get_canvas_node() != null")
	assert_not_null(cc.macro_view, "MacroMapView instantiated")
	assert_not_null(cc.macro_view.get_map_canvas_node(), "macro_view.get_map_canvas_node() != null")
	assert_gte(cc.macro_view.get_static_edge_count(), 22, "macro_view loads >= 22 static edges")
	assert_true(cc.start_ambient_bgm(), "start_ambient_bgm() returns true")

	# Clear any prior telemetry before verifying UI/command semantic SFX wiring
	cc.audio_manager.clear_played_events()

	# 1. Tab switch -> TAB_SWITCH
	cc.switch_tab(1)
	assert_eq(cc.get_active_tab_index(), 1, "switch_tab(1) updates active_tab_index")

	# 2. Build/Upgrade command -> BUILD_UPGRADE
	var _env_build: Dictionary = cc.package_command("CMD_BUILD_OR_UPGRADE", {"building_id": "MAIN_HALL"})

	# 3. Market order command -> COIN_TRADE
	var _env_mkt: Dictionary = cc.package_command("CMD_PLACE_MARKET_ORDER", {
		"node_id": "xuchang",
		"commodity": "GRAIN",
		"side": "BID",
		"price_bp": 1000,
		"quantity": 10
	})

	# 4. Expedition dispatch command -> MARCH_DISPATCH
	var _env_march: Dictionary = cc.package_command("CMD_DISPATCH_EXPEDITION", {
		"target_node_id": "luoyang",
		"path_edge_ids": ["e_xuchang_luoyang"],
		"troop_count": 100,
		"carried_grain": 200
	})

	# 5. Gazette open -> GAZETTE_OPEN
	cc.apply_gazette({
		"from_tick": 1,
		"to_tick": 10,
		"net_yields": {"GRAIN": 120},
		"stipends_received": {"COIN": 50, "GRAIN": 100, "count": 1}
	})

	# 6. Challenge arrival -> SEAL_VERIFY
	cc.apply_challenge({
		"challenge_id": "ch_test_001",
		"ttl_expires_tick": 500,
		"prompt_text": "Test challenge prompt"
	})

	# 7. Raw plaintext JSON submission in CourtHUD -> UI_ERROR
	var bad_cc_res: Dictionary = cc.court_hud.submit_character_creation(
		"SmuggleHero",
		"FUSION_INTERVIEW",
		[0, 1, 2, 0, 1, 2, 0, 1],
		"{\"LEA\": 99, \"MAR\": 99}"
	)
	assert_false(_as_bool(bad_cc_res.get("ok", true), true), "Plaintext JSON submission rejected")
	assert_eq(str(bad_cc_res.get("error_code", "")), DtoSchemas.ERR_PLAINTEXT_JSON_FORBIDDEN, "Plaintext JSON returns ERR_PLAINTEXT_JSON_FORBIDDEN")

	var sfx_log: Array[String] = cc.audio_manager.get_played_events()
	var expected_sfx: Array[String] = [
		"TAB_SWITCH",
		"BUILD_UPGRADE",
		"COIN_TRADE",
		"MARCH_DISPATCH",
		"GAZETTE_OPEN",
		"SEAL_VERIFY",
		"UI_ERROR"
	]
	assert_eq(sfx_log.size(), expected_sfx.size(), "All 7 semantic SFX events recorded")
	for i: int in range(mini(sfx_log.size(), expected_sfx.size())):
		assert_eq(sfx_log[i], expected_sfx[i], "SFX event %d == %s" % [i, expected_sfx[i]])

	# Mute button toggle wiring
	assert_not_null(cc._mute_btn, "_mute_btn exists on ClientController")
	assert_false(cc.audio_manager.is_muted(), "AudioManager unmuted before pressing _mute_btn")
	cc._mute_btn.pressed.emit()
	assert_true(cc.audio_manager.is_muted(), "Pressing _mute_btn toggles audio_manager.is_muted() to true")
	assert_contains(cc._mute_btn.text, "ON", "_mute_btn text reflects muted ON state")

	cc._mute_btn.pressed.emit()
	assert_false(cc.audio_manager.is_muted(), "Pressing _mute_btn again toggles audio_manager.is_muted() to false")
	assert_contains(cc._mute_btn.text, "OFF", "_mute_btn text reflects unmuted OFF state")
