class_name AssetRegistry
extends RefCounted

const MANIFEST_PATH: String = "res://data/assets_manifest.json"

const TINY_TOWN: String = "res://assets/graphics/tilesets/kenney_tiny_town.png"
const TINY_DUNGEON: String = "res://assets/graphics/tilesets/kenney_tiny_dungeon.png"
const MAP_BG: String = "res://assets/graphics/backgrounds/oga_parchment_map_bg.jpg"
const CREST_BANNER: String = "res://assets/graphics/backgrounds/oga_parchment_banner.png"
const PANEL_BORDER_GOLD: String = "res://assets/graphics/ui/panel_border_015.png"
const PANEL_BORDER_SLATE: String = "res://assets/graphics/ui/panel_border_010.png"

const EMOTE_COMBAT: String = "res://assets/graphics/emotes/emote_combat.png"
const EMOTE_ALERT: String = "res://assets/graphics/emotes/emote_exclamations.png"
const EMOTE_QUESTION: String = "res://assets/graphics/emotes/emote_question.png"
const UI_FONT_PATH: String = "res://assets/fonts/NotoSansKR-Subset.otf"

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

# ibelick/ui-skills 3-tier contrast, surface elevation & semantic status tokens
const COLOR_TEXT_PRIMARY: Color = Color(0.95, 0.91, 0.82, 1.0)
const COLOR_TEXT_SECONDARY: Color = Color(0.80, 0.74, 0.64, 1.0)
const COLOR_TEXT_MUTED: Color = Color(0.62, 0.57, 0.49, 1.0)
const COLOR_CARD_BG: Color = Color(0.15, 0.13, 0.11, 0.96)
const COLOR_CARD_ELEVATED: Color = Color(0.20, 0.17, 0.14, 0.98)
const COLOR_SUBTLE_BORDER: Color = Color(0.32, 0.26, 0.19, 0.90)
const COLOR_SUCCESS_JADE: Color = Color(0.34, 0.74, 0.52, 1.0)
const COLOR_WARNING_AMBER: Color = Color(0.92, 0.69, 0.26, 1.0)
const COLOR_DANGER_CRIMSON: Color = Color(0.86, 0.31, 0.27, 1.0)
const COLOR_INFO_AZURE: Color = Color(0.42, 0.68, 0.88, 1.0)

const FONT_SIZE_TITLE: int = 18
const FONT_SIZE_SECTION: int = 15
const FONT_SIZE_BODY: int = 13
const FONT_SIZE_CAPTION: int = 11

var _texture_cache: Dictionary = {}
var _atlas_cache: Dictionary = {}
var _stylebox_cache: Dictionary = {}
var _cached_theme: Theme = null
var _cached_font: Font = null


func _load_bundled_ui_font() -> FontFile:
	if ResourceLoader.exists(UI_FONT_PATH):
		var loaded: Resource = ResourceLoader.load(UI_FONT_PATH)
		if loaded is FontFile:
			var font_res: FontFile = loaded
			return font_res
	if FileAccess.file_exists(UI_FONT_PATH):
		var ff: FontFile = FontFile.new()
		var abs_path: String = ProjectSettings.globalize_path(UI_FONT_PATH)
		var err: Error = ff.load_dynamic_font(abs_path)
		if err == OK:
			return ff
	return null


func get_ui_font() -> Font:
	if _cached_font != null:
		return _cached_font
	var bundled_font: FontFile = _load_bundled_ui_font()
	if OS.has_feature("web") and bundled_font != null:
		_cached_font = bundled_font
		return _cached_font

	var sys_font: SystemFont = SystemFont.new()
	sys_font.font_names = PackedStringArray([
		"Noto Sans CJK KR",
		"Malgun Gothic",
		"Apple SD Gothic Neo",
		"NanumGothic",
		"DejaVu Sans"
	])
	sys_font.multichannel_signed_distance_field = false
	if bundled_font != null:
		sys_font.fallbacks = [bundled_font]
	_cached_font = sys_font
	return _cached_font


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


func build_card_stylebox(
	elevated: bool = false,
	accent_border: Color = COLOR_SUBTLE_BORDER
) -> StyleBoxFlat:
	var bg: Color = COLOR_CARD_ELEVATED if elevated else COLOR_CARD_BG
	var sb: StyleBoxFlat = _build_flat_stylebox(bg, accent_border, 1, 6, 10.0, 8.0)
	sb.shadow_color = Color(0.02, 0.02, 0.02, 0.38)
	sb.shadow_size = 3 if elevated else 2
	return sb


func build_badge_stylebox(bg: Color, border: Color) -> StyleBoxFlat:
	return _build_flat_stylebox(bg, border, 1, 4, 8.0, 3.0)


func apply_button_variant(btn: Button, variant: String) -> void:
	if btn == null:
		return
	var focus_ring: StyleBoxFlat = _build_flat_stylebox(
		Color(0.24, 0.19, 0.14, 0.96),
		COLOR_GOLD_HIGHLIGHT,
		2,
		4,
		10.0,
		5.0
	)
	match variant:
		"primary":
			var n: StyleBoxFlat = _build_flat_stylebox(COLOR_GOLD_ACCENT, COLOR_GOLD_HIGHLIGHT, 1, 4, 12.0, 6.0)
			var h: StyleBoxFlat = _build_flat_stylebox(COLOR_GOLD_HIGHLIGHT, Color(1.0, 0.92, 0.65, 1.0), 1, 4, 12.0, 6.0)
			var p: StyleBoxFlat = _build_flat_stylebox(Color(0.72, 0.54, 0.20, 1.0), COLOR_GOLD_HIGHLIGHT, 1, 4, 12.0, 6.0)
			var d: StyleBoxFlat = _build_flat_stylebox(Color(0.22, 0.19, 0.15, 0.72), COLOR_SUBTLE_BORDER, 1, 4, 12.0, 6.0)
			btn.add_theme_stylebox_override("normal", n)
			btn.add_theme_stylebox_override("hover", h)
			btn.add_theme_stylebox_override("pressed", p)
			btn.add_theme_stylebox_override("focus", focus_ring)
			btn.add_theme_stylebox_override("disabled", d)
			btn.add_theme_color_override("font_color", Color(0.09, 0.07, 0.05, 1.0))
			btn.add_theme_color_override("font_hover_color", Color(0.06, 0.05, 0.03, 1.0))
			btn.add_theme_color_override("font_pressed_color", Color(0.09, 0.07, 0.05, 1.0))
			btn.add_theme_color_override("font_disabled_color", COLOR_TEXT_MUTED)
		"danger":
			var n_d: StyleBoxFlat = _build_flat_stylebox(Color(0.32, 0.12, 0.11, 0.96), COLOR_DANGER_CRIMSON, 1, 4, 10.0, 5.0)
			var h_d: StyleBoxFlat = _build_flat_stylebox(Color(0.46, 0.16, 0.14, 0.98), Color(0.95, 0.45, 0.40, 1.0), 1, 4, 10.0, 5.0)
			var p_d: StyleBoxFlat = _build_flat_stylebox(COLOR_CRIMSON_ACCENT, COLOR_GOLD_HIGHLIGHT, 1, 4, 10.0, 5.0)
			btn.add_theme_stylebox_override("normal", n_d)
			btn.add_theme_stylebox_override("hover", h_d)
			btn.add_theme_stylebox_override("pressed", p_d)
			btn.add_theme_stylebox_override("focus", focus_ring)
			btn.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
			btn.add_theme_color_override("font_hover_color", Color(1.0, 0.94, 0.90, 1.0))
		"chip":
			var n_c: StyleBoxFlat = _build_flat_stylebox(Color(0.16, 0.14, 0.12, 0.92), COLOR_SUBTLE_BORDER, 1, 4, 8.0, 4.0)
			var h_c: StyleBoxFlat = _build_flat_stylebox(Color(0.24, 0.20, 0.16, 0.98), COLOR_GOLD_ACCENT, 1, 4, 8.0, 4.0)
			var p_c: StyleBoxFlat = _build_flat_stylebox(Color(0.38, 0.29, 0.14, 0.98), COLOR_GOLD_HIGHLIGHT, 1, 4, 8.0, 4.0)
			btn.add_theme_stylebox_override("normal", n_c)
			btn.add_theme_stylebox_override("hover", h_c)
			btn.add_theme_stylebox_override("pressed", p_c)
			btn.add_theme_stylebox_override("focus", focus_ring)
			btn.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
			btn.add_theme_color_override("font_hover_color", COLOR_GOLD_HIGHLIGHT)
			btn.add_theme_color_override("font_pressed_color", COLOR_GOLD_HIGHLIGHT)
		_:
			var n_s: StyleBoxFlat = _build_flat_stylebox(Color(0.19, 0.17, 0.14, 0.95), COLOR_SUBTLE_BORDER, 1, 4, 10.0, 5.0)
			var h_s: StyleBoxFlat = _build_flat_stylebox(Color(0.27, 0.23, 0.18, 0.98), COLOR_GOLD_ACCENT, 1, 4, 10.0, 5.0)
			var p_s: StyleBoxFlat = _build_flat_stylebox(Color(0.33, 0.25, 0.15, 0.98), COLOR_GOLD_HIGHLIGHT, 1, 4, 10.0, 5.0)
			btn.add_theme_stylebox_override("normal", n_s)
			btn.add_theme_stylebox_override("hover", h_s)
			btn.add_theme_stylebox_override("pressed", p_s)
			btn.add_theme_stylebox_override("focus", focus_ring)
			btn.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
			btn.add_theme_color_override("font_hover_color", COLOR_GOLD_HIGHLIGHT)


func build_three_kingdoms_theme() -> Theme:
	if _cached_theme != null:
		return _cached_theme

	var theme: Theme = Theme.new()
	var ui_font: Font = get_ui_font()
	if ui_font != null:
		theme.default_font = ui_font
	theme.default_font_size = FONT_SIZE_BODY

	var panel_sb: StyleBoxTexture = build_panel_stylebox(true)
	var slate_sb: StyleBoxTexture = build_panel_stylebox(false)
	theme.set_stylebox("panel", "PanelContainer", panel_sb)
	theme.set_stylebox("panel", "Panel", slate_sb)

	var btn_normal: StyleBoxFlat = _build_flat_stylebox(
		Color(0.20, 0.16, 0.13, 0.96),
		COLOR_SUBTLE_BORDER,
		1,
		4,
		10.0,
		5.0
	)
	var btn_hover: StyleBoxFlat = _build_flat_stylebox(
		Color(0.29, 0.22, 0.16, 0.98),
		COLOR_GOLD_ACCENT,
		1,
		4,
		10.0,
		5.0
	)
	var btn_pressed: StyleBoxFlat = _build_flat_stylebox(
		COLOR_CRIMSON_ACCENT,
		COLOR_GOLD_HIGHLIGHT,
		1,
		4,
		10.0,
		5.0
	)
	var btn_focus: StyleBoxFlat = _build_flat_stylebox(
		Color(0.24, 0.19, 0.14, 0.98),
		COLOR_GOLD_HIGHLIGHT,
		2,
		4,
		10.0,
		5.0
	)
	var btn_disabled: StyleBoxFlat = _build_flat_stylebox(
		Color(0.14, 0.13, 0.12, 0.72),
		Color(0.30, 0.27, 0.22, 0.65),
		1,
		4,
		10.0,
		5.0
	)
	theme.set_stylebox("normal", "Button", btn_normal)
	theme.set_stylebox("hover", "Button", btn_hover)
	theme.set_stylebox("pressed", "Button", btn_pressed)
	theme.set_stylebox("focus", "Button", btn_focus)
	theme.set_stylebox("disabled", "Button", btn_disabled)
	theme.set_color("font_color", "Button", COLOR_TEXT_PRIMARY)
	theme.set_color("font_hover_color", "Button", COLOR_GOLD_HIGHLIGHT)
	theme.set_color("font_pressed_color", "Button", COLOR_TEXT_PRIMARY)
	theme.set_color("font_focus_color", "Button", COLOR_GOLD_HIGHLIGHT)
	theme.set_color("font_disabled_color", "Button", COLOR_TEXT_MUTED)

	# OptionButton inherits Button styling cleanly with clear focus
	theme.set_stylebox("normal", "OptionButton", btn_normal)
	theme.set_stylebox("hover", "OptionButton", btn_hover)
	theme.set_stylebox("pressed", "OptionButton", btn_pressed)
	theme.set_stylebox("focus", "OptionButton", btn_focus)
	theme.set_stylebox("disabled", "OptionButton", btn_disabled)
	theme.set_color("font_color", "OptionButton", COLOR_TEXT_PRIMARY)
	theme.set_color("font_hover_color", "OptionButton", COLOR_GOLD_HIGHLIGHT)

	var popup_bg: StyleBoxFlat = _build_flat_stylebox(Color(0.13, 0.11, 0.09, 0.98), COLOR_GOLD_ACCENT, 1, 4, 6.0, 6.0)
	var popup_hover: StyleBoxFlat = _build_flat_stylebox(Color(0.28, 0.21, 0.14, 0.98), COLOR_GOLD_HIGHLIGHT, 1, 3, 6.0, 4.0)
	theme.set_stylebox("panel", "PopupMenu", popup_bg)
	theme.set_stylebox("hover", "PopupMenu", popup_hover)
	theme.set_color("font_color", "PopupMenu", COLOR_TEXT_PRIMARY)
	theme.set_color("font_hover_color", "PopupMenu", COLOR_GOLD_HIGHLIGHT)

	var tab_panel: StyleBoxFlat = _build_flat_stylebox(COLOR_LACQUER_BG, COLOR_SUBTLE_BORDER, 1, 6, 8.0, 8.0)
	var tab_selected: StyleBoxFlat = _build_flat_stylebox(
		Color(0.27, 0.20, 0.13, 0.98),
		COLOR_GOLD_ACCENT,
		1,
		4,
		14.0,
		6.0
	)
	var tab_unselected: StyleBoxFlat = _build_flat_stylebox(
		Color(0.14, 0.13, 0.11, 0.94),
		COLOR_SUBTLE_BORDER,
		1,
		4,
		12.0,
		5.0
	)
	var tab_hovered: StyleBoxFlat = _build_flat_stylebox(
		Color(0.21, 0.17, 0.13, 0.96),
		COLOR_GOLD_HIGHLIGHT,
		1,
		4,
		12.0,
		5.0
	)
	theme.set_stylebox("panel", "TabContainer", tab_panel)
	theme.set_stylebox("tab_selected", "TabContainer", tab_selected)
	theme.set_stylebox("tab_unselected", "TabContainer", tab_unselected)
	theme.set_stylebox("tab_hovered", "TabContainer", tab_hovered)
	theme.set_stylebox("tab_focus", "TabContainer", btn_focus)
	theme.set_color("font_selected_color", "TabContainer", COLOR_GOLD_HIGHLIGHT)
	theme.set_color("font_unselected_color", "TabContainer", COLOR_TEXT_SECONDARY)
	theme.set_color("font_hovered_color", "TabContainer", COLOR_TEXT_PRIMARY)

	theme.set_color("font_color", "Label", COLOR_TEXT_PRIMARY)
	theme.set_color("font_shadow_color", "Label", Color(0.05, 0.04, 0.03, 0.55))
	theme.set_constant("shadow_offset_x", "Label", 0)
	theme.set_constant("shadow_offset_y", "Label", 1)

	var input_normal: StyleBoxFlat = _build_flat_stylebox(
		Color(0.11, 0.09, 0.08, 0.98),
		COLOR_SUBTLE_BORDER,
		1,
		4,
		8.0,
		4.0
	)
	var input_focus: StyleBoxFlat = _build_flat_stylebox(
		Color(0.14, 0.11, 0.09, 0.98),
		COLOR_GOLD_HIGHLIGHT,
		2,
		4,
		8.0,
		4.0
	)
	theme.set_stylebox("normal", "LineEdit", input_normal)
	theme.set_stylebox("focus", "LineEdit", input_focus)
	theme.set_color("font_color", "LineEdit", COLOR_TEXT_PRIMARY)
	theme.set_color("font_placeholder_color", "LineEdit", COLOR_TEXT_MUTED)
	theme.set_color("caret_color", "LineEdit", COLOR_GOLD_HIGHLIGHT)

	theme.set_stylebox("normal", "TextEdit", input_normal)
	theme.set_stylebox("focus", "TextEdit", input_focus)
	theme.set_stylebox("read_only", "TextEdit", input_normal)
	theme.set_color("font_color", "TextEdit", COLOR_TEXT_PRIMARY)
	theme.set_color("font_readonly_color", "TextEdit", COLOR_TEXT_SECONDARY)
	theme.set_color("font_placeholder_color", "TextEdit", COLOR_TEXT_MUTED)
	theme.set_color("caret_color", "TextEdit", COLOR_GOLD_HIGHLIGHT)

	theme.set_stylebox("normal", "SpinBox", input_normal)
	theme.set_stylebox("focus", "SpinBox", input_focus)

	# ProgressBar & slim dark ScrollBars
	var pb_bg: StyleBoxFlat = _build_flat_stylebox(Color(0.10, 0.09, 0.08, 0.95), COLOR_SUBTLE_BORDER, 1, 3, 2.0, 2.0)
	var pb_fill: StyleBoxFlat = _build_flat_stylebox(COLOR_SUCCESS_JADE, COLOR_SUCCESS_JADE, 0, 2, 0.0, 0.0)
	theme.set_stylebox("background", "ProgressBar", pb_bg)
	theme.set_stylebox("fill", "ProgressBar", pb_fill)
	theme.set_color("font_color", "ProgressBar", COLOR_TEXT_PRIMARY)

	var sb_track: StyleBoxFlat = _build_flat_stylebox(Color(0.09, 0.08, 0.07, 0.90), Color(0.18, 0.15, 0.12, 0.50), 0, 3, 2.0, 2.0)
	var sb_grab: StyleBoxFlat = _build_flat_stylebox(Color(0.32, 0.27, 0.20, 0.90), COLOR_GOLD_ACCENT, 1, 3, 2.0, 2.0)
	var sb_grab_hl: StyleBoxFlat = _build_flat_stylebox(Color(0.45, 0.37, 0.24, 0.95), COLOR_GOLD_HIGHLIGHT, 1, 3, 2.0, 2.0)
	theme.set_stylebox("scroll", "VScrollBar", sb_track)
	theme.set_stylebox("grabber", "VScrollBar", sb_grab)
	theme.set_stylebox("grabber_highlight", "VScrollBar", sb_grab_hl)
	theme.set_stylebox("grabber_pressed", "VScrollBar", sb_grab_hl)
	theme.set_stylebox("scroll", "HScrollBar", sb_track)
	theme.set_stylebox("grabber", "HScrollBar", sb_grab)
	theme.set_stylebox("grabber_highlight", "HScrollBar", sb_grab_hl)
	theme.set_stylebox("grabber_pressed", "HScrollBar", sb_grab_hl)

	var dlg_bg: StyleBoxFlat = _build_flat_stylebox(Color(0.14, 0.12, 0.10, 0.99), COLOR_GOLD_ACCENT, 2, 6, 14.0, 12.0)
	theme.set_stylebox("panel", "AcceptDialog", dlg_bg)
	theme.set_color("title_color", "AcceptDialog", COLOR_GOLD_HIGHLIGHT)

	theme.set_constant("separation", "HSplitContainer", 8)
	theme.set_constant("separation", "VBoxContainer", 6)
	theme.set_constant("separation", "HBoxContainer", 6)

	_cached_theme = theme
	return _cached_theme


func get_loaded_asset_stats() -> Dictionary:
	return {
		"textures_cached": _texture_cache.size(),
		"atlases_cached": _atlas_cache.size(),
		"styleboxes_cached": _stylebox_cache.size(),
		"theme_built": _cached_theme != null
	}


# =========================================================================
# Centralized Korean Localization & Tabular-Numeric Helpers (F-47 / F-48)
# =========================================================================

static func apply_text_role(lbl: Label, role: String) -> void:
	if lbl == null:
		return
	match role:
		"title":
			lbl.add_theme_font_size_override("font_size", FONT_SIZE_TITLE)
			lbl.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
		"section":
			lbl.add_theme_font_size_override("font_size", FONT_SIZE_SECTION)
			lbl.add_theme_color_override("font_color", COLOR_GOLD_HIGHLIGHT)
		"caption":
			lbl.add_theme_font_size_override("font_size", FONT_SIZE_CAPTION)
			lbl.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
		"muted":
			lbl.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
			lbl.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
		"numeric":
			lbl.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
			lbl.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_:
			lbl.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
			lbl.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)


static func format_num(n: int) -> String:
	var sign_prefix: String = "-" if n < 0 else ""
	var s: String = str(absi(n))
	var out: String = ""
	var cnt: int = 0
	for i: int in range(s.length() - 1, -1, -1):
		if cnt > 0 and cnt % 3 == 0:
			out = "," + out
		out = s[i] + out
		cnt += 1
	return sign_prefix + out


static func make_numeric_label(initial_text: String, min_width: float = 56.0) -> Label:
	var lbl: Label = Label.new()
	lbl.text = initial_text
	lbl.custom_minimum_size = Vector2(min_width, 0.0)
	apply_text_role(lbl, "numeric")
	return lbl


static func resource_label_ko(key: String) -> String:
	match key:
		"GRAIN":
			return "군량"
		"COIN":
			return "은전"
		"WOOD":
			return "목재"
		"IRON":
			return "철광"
		"HORSES":
			return "군마"
		"HERBS_WINE":
			return "약재·명주"
		"WEAPONS":
			return "병기"
		"MERIT_PRESTIGE":
			return "공적·명망"
		_:
			return key


static func zone_info_ko(zone_id: String) -> Dictionary:
	match zone_id:
		"ZONE_FARMLAND":
			return {"name": "둔전 농지", "desc": "매 틱 군량 수확 · 농사 우선순위 가신 배치", "building": "MILITARY_FARM"}
		"ZONE_STOCKPILE":
			return {"name": "비축 창고", "desc": "군량·목재·철광·병기 적재 및 물류 거점", "building": "GRANARY_VAULT"}
		"ZONE_HIDDEN_VAULT":
			return {"name": "비상 지하창고", "desc": "약탈 시 40~65% 자원 보호 (오프라인 방어)", "building": "GRANARY_VAULT"}
		"ZONE_BARRACKS":
			return {"name": "병영", "desc": "사병 훈련·무장 및 순찰 집결 구역", "building": "BARRACKS_DRILL"}
		"ZONE_WORKSHOP":
			return {"name": "공방", "desc": "환도·경갑·연노 및 약재 제조 공방", "building": "SMITHY_ARMORY"}
		"ZONE_RESIDENCE":
			return {"name": "가신 숙소", "desc": "주군과 가신의 취침·휴식·기분 회복", "building": "QUARTERS"}
		"ZONE_INFIRMARY":
			return {"name": "의막", "desc": "부상 가신 요양 및 탕약 치료 구역", "building": "STUDY_PAVILION"}
		"ZONE_DEFENSE_LINE":
			return {"name": "방어선", "desc": "목책·망루·함정 외곽 방어 경계선", "building": "WATCHTOWER_WALL"}
		_:
			return {"name": zone_id, "desc": "장원 일반 구역", "building": "MAIN_HALL"}


static func building_info_ko(building_id: String) -> Dictionary:
	match building_id:
		"MAIN_HALL":
			return {"name": "본영 관아", "desc": "행정 총괄 및 장원 최대 수용량 확장"}
		"QUARTERS":
			return {"name": "가신 숙소", "desc": "가신 최대 정원 확장 및 휴식 효율 증가"}
		"MILITARY_FARM":
			return {"name": "둔전", "desc": "군량 자동 생산량 및 수확 보너스 증대"}
		"GRANARY_VAULT":
			return {"name": "군량고", "desc": "비축 한도 및 비상 지하창고 보호율 상승"}
		"HORSE_PASTURE":
			return {"name": "군마 목장", "desc": "군마 육성 및 기병 편성 지원"}
		"SMITHY_ARMORY":
			return {"name": "대장간", "desc": "병기 제련 속도 및 명품 제작 확률 향상"}
		"BARRACKS_DRILL":
			return {"name": "병영", "desc": "사병 정원 및 군사 훈련 숙련도 증가"}
		"STUDY_PAVILION":
			return {"name": "서책관", "desc": "병법 연구 속도 및 계략 숙련도 향상"}
		"BANQUET_HALL":
			return {"name": "연회청", "desc": "연회 기분 회복량 및 명사 등용 확률 상승"}
		"WATCHTOWER_WALL":
			return {"name": "망루·성벽", "desc": "최대 성벽 내구도 및 침공 방어력 강화"}
		_:
			return {"name": building_id, "desc": "장원 시설"}


static func work_domain_ko(domain_id: String) -> String:
	match domain_id:
		"LOGISTICS":
			return "물류·운반"
		"PATROL":
			return "순찰·방비"
		"AGRICULTURE":
			return "둔전·농사"
		"TRAINING":
			return "군사·훈련"
		"CRAFTING":
			return "공방·제작"
		"RESEARCH":
			return "병법·연구"
		"DIPLOMACY":
			return "외교·교류"
		_:
			return domain_id


static func shichen_activity_ko(act_id: String) -> String:
	match act_id:
		"WORK":
			return "집무"
		"DRILL":
			return "연무"
		"RECREATION":
			return "연회/휴양"
		"SLEEP":
			return "취침"
		"ANYTHING":
			return "자율"
		_:
			return act_id


static func doctrine_option_ko(code: String) -> String:
	match code:
		"DEFENSIVE_HOLD":
			return "방어 고수"
		"PREEMPTIVE_STRIKE":
			return "선제 타격"
		"EVADE_DISENGAGE":
			return "우회 이탈"
		"SQUARE_SHIELD":
			return "방진 (수비)"
		"WEDGE_SPEAR":
			return "봉시진 (돌파)"
		"CRANE_WING":
			return "학익진 (포위)"
		"SNAKE_COLUMN":
			return "장사진 (기동)"
		"ACCEPT_IF_ADVANTAGE":
			return "우세 시 일기토"
		"ALWAYS_ACCEPT":
			return "일기토 항상 수락"
		"DECLINE":
			return "일기토 회피"
		"FIRE_OR_FLOOD":
			return "화공·수공"
		"AMBUSH_TRAP":
			return "매복 기습"
		"PRESERVE_TROOPS":
			return "병력 보존"
		"DISRUPT_CONFUSE":
			return "교란 혼란"
		"RECRUIT_PERSUADE":
			return "설득 등용"
		"RANSOM":
			return "몸값 협상"
		"RELEASE_CHIVALROUS":
			return "의협 석방"
		_:
			return code


static func season_ko(s: String) -> String:
	match s:
		"SPRING":
			return "춘(봄)"
		"SUMMER":
			return "하(여름)"
		"AUTUMN":
			return "추(가을)"
		"WINTER":
			return "동(겨울)"
		_:
			return s


static func role_ko(r: String) -> String:
	match r:
		"FREE_OFFICER":
			return "재야 장수"
		"FACTION_OFFICER":
			return "세력 장수"
		"GOVERNOR":
			return "태수"
		"LORD":
			return "군주"
		_:
			return r


static func rank_ko(r: String) -> String:
	match r:
		"NONE":
			return "무관"
		"RANK_9":
			return "종9품"
		"RANK_8":
			return "정8품"
		"RANK_7":
			return "정7품"
		"RANK_6":
			return "정6품"
		"RANK_5":
			return "정5품"
		"RANK_4":
			return "정4품"
		"RANK_3":
			return "정3품"
		"RANK_2":
			return "정2품"
		"RANK_1":
			return "정1품"
		"SOVEREIGN":
			return "전권 주군"
		"PREFECT":
			return "현령"
		"GOVERNOR_INSPECTOR":
			return "자사"
		"GOVERNOR_GENERAL":
			return "도독"
		"DUKE":
			return "공작"
		"KING":
			return "왕"
		"EMPEROR":
			return "황제"
		_:
			return r


static func unit_type_ko(u: String) -> String:
	match u:
		"ARMY":
			return "정규 군단"
		"CARAVAN":
			return "무역 상단"
		"RAID_PARTY":
			return "약탈대"
		"COALITION_FORCE":
			return "연합군"
		"MARCHING":
			return "행군 중"
		"ARRIVED":
			return "도착"
		"IDLE":
			return "대기"
		"SIEGING":
			return "공성 중"
		"RALLYING":
			return "집결 중"
		"EXECUTED":
			return "출진 완료"
		_:
			return u


static func node_name_ko(node_id: String) -> String:
	match node_id:
		"luoyang":
			return "낙양"
		"changan":
			return "장안"
		"xuchang":
			return "허창"
		"ye_city":
			return "업성"
		"ye_county":
			return "업현"
		"jicheng":
			return "계성"
		"chenliu":
			return "진류"
		"runan":
			return "여남"
		"nanyang":
			return "남양"
		"hulao_pass":
			return "호로관"
		"tong_pass":
			return "동관"
		"xiangyang":
			return "양양"
		"chengdu":
			return "성도"
		"jianye":
			return "건업"
		"xiapi":
			return "하비"
		_:
			return node_id


static func faction_name_ko(fid: String) -> String:
	match fid:
		"", "NEUTRAL":
			return "중립"
		"fac_han":
			return "한실 신흥군"
		"fac_wei":
			return "위(魏) 조조군"
		"fac_shu":
			return "촉(蜀) 유비군"
		"fac_wu":
			return "오(吳) 손권군"
		_:
			return fid


static func job_ko(job_id: String) -> String:
	match job_id:
		"IDLE", "IDLE_STUDY_OR_GUARD":
			return "휴식·대기"
		"SLEEP", "SLEEP_IN_QUARTERS":
			return "숙소 취침"
		"RECREATION", "RECREATION_IN_HALL", "BANQUET":
			return "연회 휴양"
		"HEAL", "HEAL_IN_INFIRMARY", "INFIRMARY":
			return "의막 치료"
		"LOGISTICS":
			return "물류 운반"
		"PATROL":
			return "성벽 순찰"
		"AGRICULTURE":
			return "둔전 경작"
		"TRAINING":
			return "무예 훈련"
		"CRAFTING":
			return "병기 제작"
		"RESEARCH":
			return "병법 연구"
		"DIPLOMACY":
			return "외교 접대"
		_:
			return job_id


static func mental_state_ko(state_id: String) -> String:
	match state_id:
		"NORMAL":
			return "평온"
		"CATHARSIS":
			return "심기일전"
		"AWAKENED_STRATAGEM":
			return "각성·기책"
		"AWAKENED_VALOR":
			return "각성·일기당천"
		"AWAKENED_FORGING":
			return "각성·명장신기"
		"AWAKENED_HEARTS":
			return "각성·민심귀부"
		"BREAK_MINOR_BINGE":
			return "경미 붕괴(폭음)"
		"BREAK_MINOR_SECLUSION":
			return "경미 붕괴(태업)"
		"BREAK_MAJOR_CHARGE":
			return "중대 붕괴(독단)"
		"BREAK_MAJOR_EMBEZZLE":
			return "중대 붕괴(횡령)"
		"BREAK_EXTREME_DESERTION":
			return "극한 붕괴(하야)"
		"BREAK_EXTREME_MUTINY":
			return "극한 붕괴(반란)"
		_:
			return state_id


static func inbox_label_ko(code: String) -> String:
	match code:
		"IMPERIAL_LEVY":
			return "조정 군량 징발 칙서"
		"PAY_LEVY":
			return "군량 납부"
		"REFUSE_LEVY":
			return "징발 거부"
		"REBEL_SURRENDER":
			return "반군 투항 청원"
		"ACCEPT":
			return "수락"
		"REFUSE":
			return "거절"
		"ENVOY_BRIBE":
			return "외교 밀사 뇌물"
		"BANQUET_REQUEST":
			return "가신 연회 청원"
		_:
			return code


static func origin_ko(origin_id: String) -> String:
	match origin_id:
		"ORIGIN_FALLEN_ROYAL":
			return "몰락 왕족"
		"ORIGIN_FRONTIER_OFFICER":
			return "변방 무관"
		"ORIGIN_PURE_SCHOLAR":
			return "청류 명사"
		"ORIGIN_CHIVALROUS_HERO":
			return "유협 호걸"
		"ORIGIN_AGRARIAN_GENTRY":
			return "토착 호족"
		_:
			return origin_id


static func creation_mode_ko(mode_id: String) -> String:
	match mode_id:
		"INTERVIEW_ONLY":
			return "천명 문답 단독"
		"FUSION_INTERVIEW":
			return "AI 페르소나 융합 (권장)"
		"AI_DIRECT_WITH_CONFIRM":
			return "AI 직통 출사"
		_:
			return mode_id


static func command_label_ko(cmd_type: String) -> String:
	match cmd_type:
		"CMD_BUILD_OR_UPGRADE":
			return "시설 증축"
		"CMD_SET_WORK_PRIORITY":
			return "업무 우선순위"
		"CMD_SET_SCHEDULE":
			return "일과표"
		"CMD_SET_DOCTRINE":
			return "교전 수칙"
		"CMD_DISPATCH_EXPEDITION":
			return "군단/상단 출진"
		"CMD_CREATE_COALITION_RALLY":
			return "연합 집결"
		"CMD_JOIN_COALITION_RALLY":
			return "집결 합류"
		"CMD_PLACE_MARKET_ORDER":
			return "거래소 주문"
		"CMD_DECIDE_INBOX_EVENT":
			return "서신 결재"
		"CMD_REQUEST_PERSONA_CHALLENGE":
			return "챌린지 발급"
		"CMD_CREATE_CHARACTER":
			return "장수 출사"
		"CMD_HOST_BANQUET":
			return "연회 개최"
		"CMD_PROMOTE_TROOPS":
			return "병종 편성"
		_:
			return cmd_type

