class_name AssetRegistry
extends RefCounted

const MANIFEST_PATH: String = "res://data/assets_manifest.json"

const TINY_TOWN: String = "res://assets/graphics/tilesets/kenney_tiny_town.png"
const TINY_DUNGEON: String = "res://assets/graphics/tilesets/kenney_tiny_dungeon.png"
const MAP_BG: String = "res://assets/graphics/backgrounds/three_kingdoms_map_bg.jpg"
const CREST_BANNER: String = "res://assets/graphics/backgrounds/three_kingdoms_crest_banner.jpg"
const PANEL_BORDER_GOLD: String = "res://assets/graphics/ui/panel_border_015.png"
const PANEL_BORDER_SLATE: String = "res://assets/graphics/ui/panel_border_010.png"

const EMOTE_COMBAT: String = "res://assets/graphics/emotes/emote_combat.png"
const EMOTE_ALERT: String = "res://assets/graphics/emotes/emote_exclamations.png"
const EMOTE_QUESTION: String = "res://assets/graphics/emotes/emote_question.png"

const TILE_SIZE: int = 16
const TILE_SPACING: int = 1
const TILE_STRIDE: int = 17

const COLOR_LACQUER_BG: Color = Color(0.11, 0.09, 0.08, 1.0)
const COLOR_LACQUER_PANEL: Color = Color(0.24, 0.20, 0.16, 0.96)
const COLOR_SLATE_PANEL: Color = Color(0.18, 0.21, 0.24, 0.96)
const COLOR_PARCHMENT_TEXT: Color = Color(0.95, 0.90, 0.78, 1.0)
const COLOR_GOLD_ACCENT: Color = Color(0.84, 0.67, 0.30, 1.0)
const COLOR_GOLD_HIGHLIGHT: Color = Color(0.96, 0.82, 0.45, 1.0)
const COLOR_CRIMSON_ACCENT: Color = Color(0.60, 0.17, 0.15, 1.0)
const COLOR_INK_BORDER: Color = Color(0.38, 0.30, 0.20, 1.0)
const COLOR_MUTED_TEXT: Color = Color(0.72, 0.66, 0.56, 1.0)

var _texture_cache: Dictionary = {}
var _atlas_cache: Dictionary = {}
var _stylebox_cache: Dictionary = {}
var _cached_theme: Theme = null


func _load_texture(res_path: String) -> Texture2D:
	if res_path.is_empty():
		return null
	if _texture_cache.has(res_path):
		var cached_v: Variant = _texture_cache[res_path]
		if cached_v is Texture2D:
			var cached_tex: Texture2D = cached_v
			return cached_tex

	var tex: Texture2D = null
	if ResourceLoader.exists(res_path):
		var loaded: Resource = ResourceLoader.load(res_path)
		if loaded is Texture2D:
			var loaded_tex: Texture2D = loaded
			tex = loaded_tex

	if tex == null:
		var abs_path: String = ProjectSettings.globalize_path(res_path)
		if FileAccess.file_exists(res_path) or FileAccess.file_exists(abs_path):
			var img: Image = Image.load_from_file(abs_path)
			if img != null and not img.is_empty():
				tex = ImageTexture.create_from_image(img)

	if tex != null:
		_texture_cache[res_path] = tex
	return tex


func get_texture(res_path: String) -> Texture2D:
	return _load_texture(res_path)


func slice_tile(
	sheet_path: String,
	col: int,
	row: int,
	tile_size: int = TILE_SIZE,
	spacing: int = TILE_SPACING
) -> AtlasTexture:
	var cache_key: String = "%s:%d:%d:%d:%d" % [sheet_path, col, row, tile_size, spacing]
	if _atlas_cache.has(cache_key):
		var cached_v: Variant = _atlas_cache[cache_key]
		if cached_v is AtlasTexture:
			var cached_atlas: AtlasTexture = cached_v
			return cached_atlas

	var sheet: Texture2D = _load_texture(sheet_path)
	if sheet == null:
		return null

	var stride: int = tile_size + spacing
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(
		float(col * stride),
		float(row * stride),
		float(tile_size),
		float(tile_size)
	)
	atlas.filter_clip = true
	_atlas_cache[cache_key] = atlas
	return atlas


func get_zone_tile(zone_type: String) -> Texture2D:
	match zone_type:
		"ZONE_FARMLAND":
			return slice_tile(TINY_TOWN, 1, 2)
		"ZONE_STOCKPILE":
			return slice_tile(TINY_TOWN, 9, 4)
		"ZONE_HIDDEN_VAULT":
			return slice_tile(TINY_DUNGEON, 5, 7)
		"ZONE_BARRACKS":
			return slice_tile(TINY_TOWN, 11, 7)
		"ZONE_WORKSHOP":
			return slice_tile(TINY_TOWN, 7, 9)
		"ZONE_RESIDENCE":
			return slice_tile(TINY_TOWN, 5, 4)
		"ZONE_INFIRMARY":
			return slice_tile(TINY_DUNGEON, 6, 9)
		"ZONE_DEFENSE_LINE":
			return slice_tile(TINY_TOWN, 9, 3)
		_:
			return slice_tile(TINY_TOWN, 0, 0)


func get_resource_icon(res_key: String) -> Texture2D:
	match res_key:
		"GRAIN":
			return slice_tile(TINY_TOWN, 10, 7)
		"COIN":
			return slice_tile(TINY_TOWN, 9, 7)
		"WOOD":
			return slice_tile(TINY_TOWN, 10, 8)
		"IRON":
			return slice_tile(TINY_TOWN, 7, 9)
		"HORSES":
			return slice_tile(TINY_TOWN, 9, 4)
		"HERBS_WINE":
			return slice_tile(TINY_TOWN, 11, 8)
		"WEAPONS":
			return slice_tile(TINY_DUNGEON, 8, 8)
		"MERIT_PRESTIGE":
			return slice_tile(TINY_DUNGEON, 5, 2)
		_:
			return slice_tile(TINY_TOWN, 9, 7)


func get_pawn_sprite(is_avatar: bool, role_hint: String = "") -> Texture2D:
	if is_avatar:
		return slice_tile(TINY_DUNGEON, 0, 8)
	var hint: String = role_hint.to_upper()
	if hint.contains("SCHOLAR") or hint.contains("MYSTIC") or hint.contains("STRATEGIST") or hint.contains("ADVISOR"):
		return slice_tile(TINY_DUNGEON, 0, 7)
	if hint.contains("FIERCE") or hint.contains("MARTIAL") or hint.contains("VANGUARD") or hint.contains("GENERAL"):
		return slice_tile(TINY_DUNGEON, 3, 7)
	if hint.contains("NOBLE") or hint.contains("ELDER") or hint.contains("GOVERNOR") or hint.contains("LORD"):
		return slice_tile(TINY_DUNGEON, 4, 8)
	if hint.contains("REBEL") or hint.contains("BANDIT") or hint.contains("RAID"):
		return slice_tile(TINY_DUNGEON, 4, 9)
	return slice_tile(TINY_DUNGEON, 2, 8)


func get_emote_texture(mental_state: String, raid_active: bool = false) -> Texture2D:
	var state_upper: String = mental_state.to_upper()
	if raid_active or state_upper.contains("MAJOR") or state_upper.contains("EXTREME") or state_upper == "BERSERK":
		return _load_texture(EMOTE_COMBAT)
	if state_upper.begins_with("AWAKENED_"):
		return _load_texture(EMOTE_ALERT)
	if state_upper.contains("MINOR") or state_upper == "DAZED" or state_upper == "WANDER":
		return _load_texture(EMOTE_QUESTION)
	return null


func get_macro_node_icon(node_tier: String) -> Texture2D:
	match node_tier:
		"CAPITAL":
			return slice_tile(TINY_TOWN, 3, 9)
		"CITY":
			return slice_tile(TINY_TOWN, 1, 4)
		"PASS":
			return slice_tile(TINY_TOWN, 4, 8)
		"COUNTY":
			return slice_tile(TINY_TOWN, 5, 4)
		_:
			return slice_tile(TINY_TOWN, 5, 4)


func get_army_icon(unit_type: String) -> Texture2D:
	match unit_type:
		"CARAVAN":
			return slice_tile(TINY_TOWN, 9, 4)
		"RAID_PARTY":
			return slice_tile(TINY_DUNGEON, 4, 9)
		"COALITION_FORCE":
			return slice_tile(TINY_DUNGEON, 5, 2)
		_:
			return slice_tile(TINY_DUNGEON, 1, 8)


func build_panel_stylebox(use_gold: bool = true) -> StyleBoxTexture:
	var key: String = "gold" if use_gold else "slate"
	if _stylebox_cache.has(key):
		var cached_v: Variant = _stylebox_cache[key]
		if cached_v is StyleBoxTexture:
			var cached_sb: StyleBoxTexture = cached_v
			return cached_sb

	var tex_path: String = PANEL_BORDER_GOLD if use_gold else PANEL_BORDER_SLATE
	var border_tex: Texture2D = _load_texture(tex_path)
	var sb: StyleBoxTexture = StyleBoxTexture.new()
	sb.texture = border_tex
	sb.texture_margin_left = 24.0
	sb.texture_margin_top = 24.0
	sb.texture_margin_right = 24.0
	sb.texture_margin_bottom = 24.0
	sb.content_margin_left = 10.0
	sb.content_margin_top = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_bottom = 10.0
	sb.modulate_color = COLOR_LACQUER_PANEL if use_gold else COLOR_SLATE_PANEL
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	_stylebox_cache[key] = sb
	return sb


func _build_flat_stylebox(
	bg_color: Color,
	border_color: Color,
	border_width: int = 1,
	corner_radius: int = 4,
	pad_x: float = 10.0,
	pad_y: float = 6.0
) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.border_color = border_color
	sb.border_width_left = border_width
	sb.border_width_top = border_width
	sb.border_width_right = border_width
	sb.border_width_bottom = border_width
	sb.corner_radius_top_left = corner_radius
	sb.corner_radius_top_right = corner_radius
	sb.corner_radius_bottom_right = corner_radius
	sb.corner_radius_bottom_left = corner_radius
	sb.content_margin_left = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_right = pad_x
	sb.content_margin_bottom = pad_y
	return sb


func build_three_kingdoms_theme() -> Theme:
	if _cached_theme != null:
		return _cached_theme

	var theme: Theme = Theme.new()

	var panel_sb: StyleBoxTexture = build_panel_stylebox(true)
	var slate_sb: StyleBoxTexture = build_panel_stylebox(false)
	theme.set_stylebox("panel", "PanelContainer", panel_sb)
	theme.set_stylebox("panel", "Panel", slate_sb)

	var btn_normal: StyleBoxFlat = _build_flat_stylebox(
		Color(0.22, 0.16, 0.13, 0.96),
		COLOR_GOLD_ACCENT,
		1,
		4,
		12.0,
		6.0
	)
	var btn_hover: StyleBoxFlat = _build_flat_stylebox(
		Color(0.32, 0.22, 0.16, 0.98),
		COLOR_GOLD_HIGHLIGHT,
		1,
		4,
		12.0,
		6.0
	)
	var btn_pressed: StyleBoxFlat = _build_flat_stylebox(
		COLOR_CRIMSON_ACCENT,
		COLOR_GOLD_HIGHLIGHT,
		1,
		4,
		12.0,
		6.0
	)
	var btn_disabled: StyleBoxFlat = _build_flat_stylebox(
		Color(0.14, 0.13, 0.12, 0.70),
		Color(0.35, 0.31, 0.26, 0.65),
		1,
		4,
		12.0,
		6.0
	)
	theme.set_stylebox("normal", "Button", btn_normal)
	theme.set_stylebox("hover", "Button", btn_hover)
	theme.set_stylebox("pressed", "Button", btn_pressed)
	theme.set_stylebox("focus", "Button", btn_hover)
	theme.set_stylebox("disabled", "Button", btn_disabled)
	theme.set_color("font_color", "Button", COLOR_PARCHMENT_TEXT)
	theme.set_color("font_hover_color", "Button", COLOR_GOLD_HIGHLIGHT)
	theme.set_color("font_pressed_color", "Button", COLOR_PARCHMENT_TEXT)
	theme.set_color("font_disabled_color", "Button", COLOR_MUTED_TEXT)

	var tab_panel: StyleBoxTexture = build_panel_stylebox(false)
	var tab_selected: StyleBoxFlat = _build_flat_stylebox(
		Color(0.28, 0.18, 0.14, 0.98),
		COLOR_GOLD_ACCENT,
		1,
		4,
		14.0,
		7.0
	)
	var tab_unselected: StyleBoxFlat = _build_flat_stylebox(
		Color(0.14, 0.13, 0.12, 0.92),
		COLOR_INK_BORDER,
		1,
		4,
		12.0,
		6.0
	)
	var tab_hovered: StyleBoxFlat = _build_flat_stylebox(
		Color(0.22, 0.18, 0.15, 0.96),
		COLOR_GOLD_HIGHLIGHT,
		1,
		4,
		12.0,
		6.0
	)
	theme.set_stylebox("panel", "TabContainer", tab_panel)
	theme.set_stylebox("tab_selected", "TabContainer", tab_selected)
	theme.set_stylebox("tab_unselected", "TabContainer", tab_unselected)
	theme.set_stylebox("tab_hovered", "TabContainer", tab_hovered)
	theme.set_color("font_selected_color", "TabContainer", COLOR_GOLD_HIGHLIGHT)
	theme.set_color("font_unselected_color", "TabContainer", COLOR_MUTED_TEXT)
	theme.set_color("font_hovered_color", "TabContainer", COLOR_PARCHMENT_TEXT)

	theme.set_color("font_color", "Label", COLOR_PARCHMENT_TEXT)
	theme.set_color("font_shadow_color", "Label", Color(0.05, 0.04, 0.03, 0.85))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)

	var input_normal: StyleBoxFlat = _build_flat_stylebox(
		Color(0.12, 0.10, 0.09, 0.96),
		COLOR_INK_BORDER,
		1,
		3,
		8.0,
		5.0
	)
	var input_focus: StyleBoxFlat = _build_flat_stylebox(
		Color(0.15, 0.12, 0.10, 0.98),
		COLOR_GOLD_ACCENT,
		1,
		3,
		8.0,
		5.0
	)
	theme.set_stylebox("normal", "LineEdit", input_normal)
	theme.set_stylebox("focus", "LineEdit", input_focus)
	theme.set_color("font_color", "LineEdit", COLOR_PARCHMENT_TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", COLOR_MUTED_TEXT)
	theme.set_color("caret_color", "LineEdit", COLOR_GOLD_HIGHLIGHT)

	theme.set_stylebox("normal", "TextEdit", input_normal)
	theme.set_stylebox("focus", "TextEdit", input_focus)
	theme.set_stylebox("read_only", "TextEdit", input_normal)
	theme.set_color("font_color", "TextEdit", COLOR_PARCHMENT_TEXT)
	theme.set_color("font_readonly_color", "TextEdit", COLOR_PARCHMENT_TEXT)
	theme.set_color("font_placeholder_color", "TextEdit", COLOR_MUTED_TEXT)
	theme.set_color("caret_color", "TextEdit", COLOR_GOLD_HIGHLIGHT)

	_cached_theme = theme
	return _cached_theme


func get_loaded_asset_stats() -> Dictionary:
	return {
		"textures_cached": _texture_cache.size(),
		"atlases_cached": _atlas_cache.size(),
		"styleboxes_cached": _stylebox_cache.size(),
		"theme_built": _cached_theme != null
	}
