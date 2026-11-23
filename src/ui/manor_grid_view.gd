class_name ManorGridView
extends Control

signal intent_emitted(cmd_type: String, args: Dictionary)

const RPG_HOUSE_INN_PATH: String = "res://assets/graphics/props/rpg_house_inn.png"
const RPG_TREE01_PATH: String = "res://assets/graphics/props/rpg_tree01.png"

const COMPOUND_DEFS: Array[Dictionary] = [
	{"zone": "ZONE_DEFENSE_LINE", "label": "본영 관아", "building": "MAIN_HALL", "rect": Rect2i(11, 2, 10, 6), "pill_pos": Vector2(16.0, 2.1)},
	{"zone": "ZONE_FARMLAND", "label": "둔전 농지", "building": "MILITARY_FARM", "rect": Rect2i(2, 5, 9, 10), "pill_pos": Vector2(6.5, 5.1)},
	{"zone": "ZONE_STOCKPILE", "label": "군량고", "building": "GRANARY_VAULT", "rect": Rect2i(19, 8, 6, 6), "pill_pos": Vector2(22.0, 8.1)},
	{"zone": "ZONE_HIDDEN_VAULT", "label": "지하창고 50%", "building": "GRANARY_VAULT", "rect": Rect2i(25, 8, 5, 6), "pill_pos": Vector2(27.5, 8.1)},
	{"zone": "ZONE_BARRACKS", "label": "연병장", "building": "BARRACKS_DRILL", "rect": Rect2i(2, 17, 12, 7), "pill_pos": Vector2(8.0, 17.1)},
	{"zone": "ZONE_WORKSHOP", "label": "대장간", "building": "SMITHY_ARMORY", "rect": Rect2i(19, 15, 11, 7), "pill_pos": Vector2(24.5, 15.1)},
	{"zone": "ZONE_RESIDENCE", "label": "가신 숙소", "building": "QUARTERS", "rect": Rect2i(4, 24, 13, 6), "pill_pos": Vector2(10.5, 24.1)},
	{"zone": "ZONE_INFIRMARY", "label": "의막", "building": "STUDY_PAVILION", "rect": Rect2i(19, 23, 11, 7), "pill_pos": Vector2(24.5, 23.1)}
]

var _assets: AssetRegistry = null
var _grid_panel: PanelContainer = null
var _grid_canvas: Control = null
var _resource_icons_bar: HBoxContainer = null
var _resource_icon_rects: Dictionary = {}
var _resource_icon_labels: Dictionary = {}
var _section_panels_slate: Array[PanelContainer] = []
var _card_panels: Array[PanelContainer] = []

var _header_label: Label = null
var _resources_label: Label = null
var _grid_summary_label: Label = null
var _zones_label: Label = null
var _tile_inspector_label: Label = null
var _zone_filter_btns: Dictionary = {}
var _buildings_grid: GridContainer = null
var _buildings_box: VBoxContainer = null
var _pawns_box: VBoxContainer = null
var _pawns_empty_label: Label = null
var _upgrade_buttons: Dictionary = {}
var _last_snapshot: Dictionary = {}

# Hero Identity & Live Chronicle Card widgets
var _hero_card_panel: PanelContainer = null
var _hero_avatar_rect: TextureRect = null
var _hero_title_label: Label = null
var _hero_loc_label: Label = null
var _hero_traits_label: Label = null
var _hero_stat_labels: Dictionary = {}
var _chronicle_lines: Array[String] = []
var _chronicle_feed_label: Label = null

var _selected_zone_id: String = ""
var _hover_tile: Vector2i = Vector2i(-1, -1)
var _cached_hero_info: Dictionary = {}


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


static func _trait_ko(tid: String) -> String:
	match tid:
		"T_CHIVALROUS":
			return "의협"
		"T_AMBITIOUS":
			return "야심가"
		"T_CAUTIOUS":
			return "신중"
		"T_DRINKER":
			return "호주가"
		"T_MYSTIC":
			return "둔갑"
		"T_UNSELFISH":
			return "청렴"
		"T_GREEDY":
			return "탐욕"
		"T_FIERCE":
			return "맹장"
		"T_AGRARIAN":
			return "둔전가"
		"T_SCHOLAR":
			return "명사"
		_:
			return tid


static func _zone_tint(zone_type: String) -> Color:
	match zone_type:
		"ZONE_FARMLAND":
			return Color(0.75, 0.90, 0.65, 0.35)
		"ZONE_STOCKPILE":
			return Color(0.88, 0.78, 0.55, 0.30)
		"ZONE_HIDDEN_VAULT":
			return Color(0.65, 0.58, 0.85, 0.38)
		"ZONE_BARRACKS":
			return Color(0.88, 0.45, 0.40, 0.35)
		"ZONE_WORKSHOP":
			return Color(0.85, 0.62, 0.35, 0.35)
		"ZONE_RESIDENCE":
			return Color(0.72, 0.82, 0.92, 0.30)
		"ZONE_INFIRMARY":
			return Color(0.55, 0.88, 0.78, 0.35)
		"ZONE_DEFENSE_LINE":
			return Color(0.55, 0.55, 0.62, 0.40)
		_:
			return Color(0.70, 0.70, 0.70, 0.25)


static func _default_zone_at(gx: int, gy: int) -> String:
	if gy < 4:
		return "ZONE_DEFENSE_LINE"
	if gx < 16 and gy < 16:
		return "ZONE_FARMLAND"
	if gx >= 16 and gx < 26 and gy < 12:
		return "ZONE_STOCKPILE"
	if gx >= 26 and gy < 12:
		return "ZONE_HIDDEN_VAULT"
	if gx < 16 and gy >= 16 and gy < 24:
		return "ZONE_BARRACKS"
	if gx >= 16 and gy >= 12 and gy < 20:
		return "ZONE_WORKSHOP"
	if gx < 20 and gy >= 24:
		return "ZONE_RESIDENCE"
	if gx >= 20 and gy >= 20:
		return "ZONE_INFIRMARY"
	return "ZONE_STOCKPILE"


static func _compound_zone_at(gx: int, gy: int) -> String:
	for cdef: Dictionary in COMPOUND_DEFS:
		var r_v: Variant = cdef.get("rect", Rect2i(0, 0, 0, 0))
		if r_v is Rect2i:
			var r: Rect2i = r_v
			if r.has_point(Vector2i(gx, gy)):
				return str(cdef.get("zone", "ZONE_STOCKPILE"))
	if gx <= 1 or gx >= 30 or gy <= 1 or gy >= 30:
		return "ZONE_DEFENSE_LINE"
	return _default_zone_at(gx, gy)


static func _compound_anchor_for_job(job: String, is_avatar: bool) -> Vector2:
	match job:
		"AGRICULTURE":
			return Vector2(6.5, 10.0)
		"LOGISTICS", "EMERGENCY_EAT":
			return Vector2(21.5, 11.2)
		"TRAINING", "MARTIAL_DRILL_TRAINING":
			return Vector2(8.0, 20.5)
		"CRAFTING":
			return Vector2(24.0, 18.8)
		"SLEEP", "SLEEP_IN_QUARTERS", "RECREATION", "RECREATION_IN_HALL", "ATTEND_BANQUET_OR_RECREATION", "BANQUET":
			return Vector2(10.5, 27.2)
		"HEAL", "HEAL_IN_INFIRMARY", "INFIRMARY", "INFIRMARY_CARE":
			return Vector2(24.5, 26.8)
		"PATROL", "RAID_DEFENSE":
			return Vector2(16.0, 8.6) if is_avatar else Vector2(13.0, 15.0)
		"RESEARCH", "DIPLOMACY":
			return Vector2(16.0, 7.6)
		_:
			return Vector2(16.0, 9.2) if is_avatar else Vector2(12.0, 15.5)


func _init() -> void:
	name = "ManorGridView"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func set_asset_registry(reg: AssetRegistry) -> void:
	_assets = reg
	if _assets == null:
		return
	if _grid_panel != null:
		_grid_panel.add_theme_stylebox_override("panel", _assets.build_card_stylebox(true, AssetRegistry.COLOR_GOLD_ACCENT))
	if _hero_card_panel != null:
		_hero_card_panel.add_theme_stylebox_override("panel", _assets.build_card_stylebox(true, AssetRegistry.COLOR_GOLD_ACCENT))
	if _hero_avatar_rect != null:
		_hero_avatar_rect.texture = _assets.get_pawn_sprite(true, "LORD")
	var card_sb: StyleBoxFlat = _assets.build_card_stylebox(false, AssetRegistry.COLOR_SUBTLE_BORDER)
	for p_card: PanelContainer in _card_panels:
		if p_card != null:
			p_card.add_theme_stylebox_override("panel", card_sb)
	for rk: String in DtoSchemas.RESOURCE_KEYS:
		var tr_v: Variant = _resource_icon_rects.get(rk, null)
		if tr_v is TextureRect:
			var tr: TextureRect = tr_v
			tr.texture = _assets.get_resource_icon(rk)
	if _grid_canvas != null:
		_grid_canvas.queue_redraw()


func get_canvas_node() -> Control:
	return _grid_canvas


func _make_card_panel(parent: Control, elevated: bool = false, accent: Color = AssetRegistry.COLOR_SUBTLE_BORDER) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb: StyleBoxFlat = _assets.build_card_stylebox(elevated, accent) if _assets != null else StyleBoxFlat.new()
	if _assets == null:
		sb.bg_color = AssetRegistry.COLOR_CARD_ELEVATED if elevated else AssetRegistry.COLOR_CARD_BG
		sb.border_color = accent
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 10.0
		sb.content_margin_right = 10.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", sb)
	var inner: VBoxContainer = VBoxContainer.new()
	inner.add_theme_constant_override("separation", 5)
	panel.add_child(inner)
	parent.add_child(panel)
	if not elevated:
		_card_panels.append(panel)
	return inner


func _build_ui() -> void:
	var outer: VBoxContainer = VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 4)
	add_child(outer)

	# Hidden compatibility header & resource/zone labels (synced for unit tests, kept off-clutter)
	var compat_bar: HBoxContainer = HBoxContainer.new()
	compat_bar.visible = false
	outer.add_child(compat_bar)

	_header_label = Label.new()
	_header_label.text = "장원 [manor] · 32×32 · 요약(LOD 1) · 대기 중"
	compat_bar.add_child(_header_label)

	_grid_summary_label = Label.new()
	_grid_summary_label.text = "32×32 격자 (1,024 타일)"
	compat_bar.add_child(_grid_summary_label)

	_resources_label = Label.new()
	_resources_label.text = "자원: GRAIN: 0 | COIN: 0 | WOOD: 0 | IRON: 0 | HORSES: 0 | HERBS_WINE: 0 | WEAPONS: 0 | MERIT_PRESTIGE: 0"
	compat_bar.add_child(_resources_label)

	_zones_label = Label.new()
	_zones_label.text = "8대 구역 요약: -"
	compat_bar.add_child(_zones_label)

	_resource_icons_bar = HBoxContainer.new()
	for rk: String in DtoSchemas.RESOURCE_KEYS:
		var icon_rect: TextureRect = TextureRect.new()
		var rlbl: Label = Label.new()
		rlbl.text = "%s:0" % rk
		_resource_icons_bar.add_child(icon_rect)
		_resource_icons_bar.add_child(rlbl)
		_resource_icon_rects[rk] = icon_rect
		_resource_icon_labels[rk] = rlbl
	compat_bar.add_child(_resource_icons_bar)

	# 2-Column HSplitContainer: Left Manor Compound Canvas + Right Hero/Chronicle/Buildings/Retainers
	var split: HSplitContainer = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.split_offset = 580
	outer.add_child(split)

	# LEFT COLUMN: Walled 32x32 Three Kingdoms Compound Canvas + Tile Inspector + Zone Filter Chips
	var left_col: VBoxContainer = VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(568, 0)
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 6)
	split.add_child(left_col)

	_grid_panel = PanelContainer.new()
	_grid_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_grid_canvas = Control.new()
	_grid_canvas.custom_minimum_size = Vector2(560, 440)
	_grid_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid_canvas.tooltip_text = "장원 32×32 본영 지도 — 마우스를 올려 시설과 가신을 살피고 클릭해 구역을 강조하세요"
	_grid_canvas.draw.connect(_on_grid_canvas_draw)
	_grid_canvas.gui_input.connect(_on_grid_canvas_gui_input)
	_grid_canvas.mouse_exited.connect(_on_grid_canvas_mouse_exited)
	_grid_panel.add_child(_grid_canvas)
	left_col.add_child(_grid_panel)

	var insp_box: VBoxContainer = _make_card_panel(left_col, false)
	_tile_inspector_label = Label.new()
	_tile_inspector_label.text = "본영 장원 점검: 지도에 마우스를 올리거나 구역을 클릭해 상세 정보를 확인하세요"
	_tile_inspector_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	AssetRegistry.apply_text_role(_tile_inspector_label, "muted")
	insp_box.add_child(_tile_inspector_label)

	var zone_grid: GridContainer = GridContainer.new()
	zone_grid.columns = 4
	zone_grid.add_theme_constant_override("h_separation", 4)
	zone_grid.add_theme_constant_override("v_separation", 4)
	for zt: String in ManorState.ZONE_TYPES:
		var zinfo: Dictionary = AssetRegistry.zone_info_ko(zt)
		var zbtn: Button = Button.new()
		zbtn.text = str(zinfo.get("name", zt))
		zbtn.tooltip_text = str(zinfo.get("desc", zt))
		zbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		zbtn.add_theme_font_size_override("font_size", AssetRegistry.FONT_SIZE_CAPTION)
		if _assets != null:
			_assets.apply_button_variant(zbtn, "chip")
		zbtn.pressed.connect(_on_zone_chip_pressed.bind(zt))
		zone_grid.add_child(zbtn)
		_zone_filter_btns[zt] = zbtn
	insp_box.add_child(zone_grid)

	# RIGHT COLUMN: Scrollable Hero Identity & Live Chronicle + 10 Buildings + Retainers
	var right_scroll: ScrollContainer = ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right_scroll)

	var right_col: VBoxContainer = VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 6)
	right_scroll.add_child(right_col)

	# 1. Top Hero Identity & Live Chronicle Card
	var hero_sec: VBoxContainer = _make_card_panel(right_col, true, AssetRegistry.COLOR_GOLD_ACCENT)
	if hero_sec.get_parent() is PanelContainer:
		var hp_p: PanelContainer = hero_sec.get_parent()
		_hero_card_panel = hp_p

	var hero_top_row: HBoxContainer = HBoxContainer.new()
	hero_top_row.add_theme_constant_override("separation", 10)
	hero_sec.add_child(hero_top_row)

	var av_frame: PanelContainer = PanelContainer.new()
	var av_sb: StyleBoxFlat = StyleBoxFlat.new()
	av_sb.bg_color = Color(0.11, 0.09, 0.08, 0.96)
	av_sb.border_color = AssetRegistry.COLOR_GOLD_ACCENT
	av_sb.set_border_width_all(1)
	av_sb.set_corner_radius_all(6)
	av_sb.content_margin_left = 4.0
	av_sb.content_margin_right = 4.0
	av_sb.content_margin_top = 4.0
	av_sb.content_margin_bottom = 4.0
	av_frame.add_theme_stylebox_override("panel", av_sb)
	_hero_avatar_rect = TextureRect.new()
	_hero_avatar_rect.custom_minimum_size = Vector2(44, 44)
	_hero_avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if _assets != null:
		_hero_avatar_rect.texture = _assets.get_pawn_sprite(true, "LORD")
	av_frame.add_child(_hero_avatar_rect)
	hero_top_row.add_child(av_frame)

	var hero_meta_col: VBoxContainer = VBoxContainer.new()
	hero_meta_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_meta_col.add_theme_constant_override("separation", 2)
	hero_top_row.add_child(hero_meta_col)

	_hero_title_label = Label.new()
	_hero_title_label.text = "군주 조자룡 · 한실 신흥군 (공작)"
	AssetRegistry.apply_text_role(_hero_title_label, "section")
	hero_meta_col.add_child(_hero_title_label)

	_hero_loc_label = Label.new()
	_hero_loc_label.text = "예주 허창 본영 · 사병 300명 · 성벽 2,000 · 천명 감독관: 사마천"
	AssetRegistry.apply_text_role(_hero_loc_label, "caption")
	hero_meta_col.add_child(_hero_loc_label)

	_hero_traits_label = Label.new()
	_hero_traits_label.text = "성향: 의협 · 야심가"
	AssetRegistry.apply_text_role(_hero_traits_label, "caption")
	_hero_traits_label.add_theme_color_override("font_color", AssetRegistry.COLOR_TEXT_SECONDARY)
	hero_meta_col.add_child(_hero_traits_label)

	# 5-Stat Chips Row (통솔, 무력, 지력, 정치, 매력)
	var stat_row: HBoxContainer = HBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 6)
	hero_sec.add_child(stat_row)
	var stat_names: Dictionary = {"LEA": "통솔", "MAR": "무력", "INT": "지력", "POL": "정치", "CHA": "매력"}
	var stat_defaults: Dictionary = {"LEA": 74, "MAR": 86, "INT": 70, "POL": 72, "CHA": 79}
	for sk: String in DtoSchemas.STAT_KEYS:
		var chip: PanelContainer = PanelContainer.new()
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var csb_stat: StyleBoxFlat = StyleBoxFlat.new()
		csb_stat.bg_color = Color(0.11, 0.10, 0.08, 0.94)
		csb_stat.border_color = AssetRegistry.COLOR_SUBTLE_BORDER
		csb_stat.set_border_width_all(1)
		csb_stat.set_corner_radius_all(4)
		csb_stat.content_margin_left = 6.0
		csb_stat.content_margin_right = 6.0
		csb_stat.content_margin_top = 3.0
		csb_stat.content_margin_bottom = 3.0
		chip.add_theme_stylebox_override("panel", csb_stat)
		var slbl: Label = Label.new()
		slbl.text = "%s %d" % [str(stat_names.get(sk, sk)), _to_int(stat_defaults.get(sk, 64), 64)]
		slbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		AssetRegistry.apply_text_role(slbl, "caption")
		slbl.add_theme_color_override("font_color", AssetRegistry.COLOR_GOLD_HIGHLIGHT)
		chip.add_child(slbl)
		stat_row.add_child(chip)
		_hero_stat_labels[sk] = slbl

	# Live Scrolling 4-line RimWorld x Three Kingdoms Chronicle Feed
	var chron_box: PanelContainer = PanelContainer.new()
	var chron_sb: StyleBoxFlat = StyleBoxFlat.new()
	chron_sb.bg_color = Color(0.10, 0.09, 0.08, 0.95)
	chron_sb.border_color = Color(0.45, 0.35, 0.22, 0.85)
	chron_sb.set_border_width_all(1)
	chron_sb.set_corner_radius_all(4)
	chron_sb.content_margin_left = 8.0
	chron_sb.content_margin_right = 8.0
	chron_sb.content_margin_top = 5.0
	chron_sb.content_margin_bottom = 5.0
	chron_box.add_theme_stylebox_override("panel", chron_sb)
	var chron_vbox: VBoxContainer = VBoxContainer.new()
	chron_vbox.add_theme_constant_override("separation", 2)
	chron_box.add_child(chron_vbox)

	var chron_hdr: Label = Label.new()
	chron_hdr.text = "실시간 장원·천하 실록"
	AssetRegistry.apply_text_role(chron_hdr, "caption")
	chron_hdr.add_theme_color_override("font_color", AssetRegistry.COLOR_GOLD_ACCENT)
	chron_vbox.add_child(chron_hdr)

	_chronicle_feed_label = Label.new()
	_chronicle_feed_label.text = "• 본영 관아에서 아침 점호가 시작되었습니다.\n• 가신 진도가 둔전 농지 순시를 준비 중입니다."
	_chronicle_feed_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	AssetRegistry.apply_text_role(_chronicle_feed_label, "caption")
	_chronicle_feed_label.add_theme_color_override("font_color", AssetRegistry.COLOR_TEXT_SECONDARY)
	chron_vbox.add_child(_chronicle_feed_label)
	hero_sec.add_child(chron_box)

	# 2. Pawns & Needs Card Section (immediately visible above the fold next to the live manor map)
	var pawn_sec: VBoxContainer = _make_card_panel(right_col, false)
	var pawn_title: Label = Label.new()
	pawn_title.text = "주군 · 서약 가신 현황 (기분 · 식량 · 휴식 · 충성)"
	AssetRegistry.apply_text_role(pawn_title, "section")
	pawn_sec.add_child(pawn_title)

	_pawns_box = VBoxContainer.new()
	_pawns_box.add_theme_constant_override("separation", 5)
	pawn_sec.add_child(_pawns_box)

	_pawns_empty_label = Label.new()
	_pawns_empty_label.text = "배치된 가신이 없습니다. 상단 [장수 출사] 또는 4번 탭에서 새 장수를 출사시키세요."
	AssetRegistry.apply_text_role(_pawns_empty_label, "caption")
	pawn_sec.add_child(_pawns_empty_label)

	# 3. 10 Buildings Section (2-column compact cards)
	var bld_sec: VBoxContainer = _make_card_panel(right_col, false)
	var bld_hdr_row: HBoxContainer = HBoxContainer.new()
	var bld_title: Label = Label.new()
	bld_title.text = "10대 장원 시설 증축"
	bld_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	AssetRegistry.apply_text_role(bld_title, "section")
	bld_hdr_row.add_child(bld_title)

	var banquet_btn: Button = Button.new()
	banquet_btn.text = "가신 연회 개최"
	banquet_btn.tooltip_text = "약재·명주 10 + 군량 20을 소비하여 가신 사기와 기분을 회복합니다"
	banquet_btn.pressed.connect(_on_quick_banquet_pressed)
	bld_hdr_row.add_child(banquet_btn)

	var troop_btn: Button = Button.new()
	troop_btn.text = "사병 무장(+20)"
	troop_btn.tooltip_text = "창방병 20명을 편성하여 장원 방어력을 강화합니다"
	troop_btn.pressed.connect(_on_quick_promote_troops_pressed)
	bld_hdr_row.add_child(troop_btn)
	bld_sec.add_child(bld_hdr_row)

	_buildings_grid = GridContainer.new()
	_buildings_grid.columns = 2
	_buildings_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buildings_grid.add_theme_constant_override("h_separation", 6)
	_buildings_grid.add_theme_constant_override("v_separation", 4)
	bld_sec.add_child(_buildings_grid)

	# Compatibility alias
	_buildings_box = VBoxContainer.new()
	_buildings_box.visible = false
	bld_sec.add_child(_buildings_box)

	for bid: String in ManorState.BUILDING_IDS:
		var binfo: Dictionary = AssetRegistry.building_info_ko(bid)
		var bname: String = str(binfo.get("name", bid))
		var bdesc: String = str(binfo.get("desc", ""))

		var card_row: PanelContainer = PanelContainer.new()
		card_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var csb: StyleBoxFlat = StyleBoxFlat.new()
		csb.bg_color = Color(0.12, 0.10, 0.09, 0.92)
		csb.border_color = AssetRegistry.COLOR_SUBTLE_BORDER
		csb.set_border_width_all(1)
		csb.set_corner_radius_all(4)
		csb.content_margin_left = 7.0
		csb.content_margin_right = 7.0
		csb.content_margin_top = 4.0
		csb.content_margin_bottom = 4.0
		card_row.add_theme_stylebox_override("panel", csb)

		var hbox: HBoxContainer = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 5)
		card_row.add_child(hbox)

		var info_col: VBoxContainer = VBoxContainer.new()
		info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_col.add_theme_constant_override("separation", 1)
		hbox.add_child(info_col)

		var lbl: Label = Label.new()
		lbl.name = "Lbl_" + bid
		lbl.text = "%s · Lv.1/5" % bname
		lbl.tooltip_text = bdesc
		AssetRegistry.apply_text_role(lbl, "body")
		info_col.add_child(lbl)

		var cost_lbl: Label = Label.new()
		cost_lbl.text = "목재 120 · 은전 180"
		AssetRegistry.apply_text_role(cost_lbl, "caption")
		info_col.add_child(cost_lbl)

		var btn: Button = Button.new()
		btn.text = "증축"
		btn.tooltip_text = "%s (%s) 증축" % [bname, bdesc]
		btn.pressed.connect(_on_upgrade_pressed.bind(bid))
		hbox.add_child(btn)

		_buildings_grid.add_child(card_row)
		_upgrade_buttons[bid] = {"label": lbl, "cost_label": cost_lbl, "button": btn, "card": card_row}


func append_chronicle_line(line: String) -> void:
	var clean: String = line.strip_edges()
	if clean.is_empty():
		return
	if not _chronicle_lines.is_empty() and _chronicle_lines[_chronicle_lines.size() - 1] == clean:
		return
	_chronicle_lines.append(clean)
	while _chronicle_lines.size() > 4:
		_chronicle_lines.remove_at(0)
	if _chronicle_feed_label != null:
		var formatted: PackedStringArray = PackedStringArray()
		for item: String in _chronicle_lines:
			var _ok_ap: bool = formatted.append("• " + item)
		_chronicle_feed_label.text = "\n".join(formatted)


func update_hero_banner(hero_info: Dictionary) -> void:
	for k: Variant in hero_info.keys():
		_cached_hero_info[str(k)] = hero_info[k]

	var hero_name: String = str(_cached_hero_info.get("name", "조자룡"))
	if hero_name.is_empty():
		hero_name = "조자룡"
	var faction_name: String = str(_cached_hero_info.get("faction_name", "한실 신흥군"))
	var rank_ko: String = str(_cached_hero_info.get("rank_ko", "공작"))
	var host_name: String = str(_cached_hero_info.get("host_name", "허창"))
	var troops: int = _to_int(_cached_hero_info.get("troops", 300), 300)
	var wall_hp: int = _to_int(_cached_hero_info.get("wall_hp", 2000), 2000)
	var storyteller_ko: String = str(_cached_hero_info.get("storyteller_ko", "사마천"))

	if _hero_title_label != null:
		_hero_title_label.text = "군주 %s · %s (%s)" % [hero_name, faction_name, rank_ko]
	if _hero_loc_label != null:
		_hero_loc_label.text = "예주 %s 본영 · 사병 %s명 · 성벽 %s · 감독관: %s" % [
			host_name,
			AssetRegistry.format_num(troops),
			AssetRegistry.format_num(wall_hp),
			storyteller_ko
		]

	var traits_v: Variant = _cached_hero_info.get("traits", [])
	if _hero_traits_label != null:
		var t_names: PackedStringArray = PackedStringArray()
		if traits_v is Array:
			var ta: Array = traits_v
			for tv: Variant in ta:
				var _ok_t: bool = t_names.append(_trait_ko(str(tv)))
		if t_names.is_empty():
			_hero_traits_label.text = "성향: 의협 · 야심가"
		else:
			_hero_traits_label.text = "성향: " + " · ".join(t_names)

	var stats_v: Variant = _cached_hero_info.get("stats", {})
	var stats_d: Dictionary = stats_v if stats_v is Dictionary else {}
	var stat_ko: Dictionary = {"LEA": "통솔", "MAR": "무력", "INT": "지력", "POL": "정치", "CHA": "매력"}
	for sk: String in DtoSchemas.STAT_KEYS:
		var slbl_v: Variant = _hero_stat_labels.get(sk, null)
		if slbl_v is Label and stats_d.has(sk):
			var slbl: Label = slbl_v
			slbl.text = "%s %d" % [str(stat_ko.get(sk, sk)), _to_int(stats_d.get(sk, 64), 64)]


func _on_zone_chip_pressed(zone_id: String) -> void:
	if _selected_zone_id == zone_id:
		_selected_zone_id = ""
	else:
		_selected_zone_id = zone_id
	_refresh_zone_inspector_for_selection()
	if _grid_canvas != null:
		_grid_canvas.queue_redraw()


func _refresh_zone_inspector_for_selection() -> void:
	if _tile_inspector_label == null:
		return
	if not _selected_zone_id.is_empty():
		var zinfo: Dictionary = AssetRegistry.zone_info_ko(_selected_zone_id)
		var b_id: String = str(zinfo.get("building", "MAIN_HALL"))
		var binfo: Dictionary = AssetRegistry.building_info_ko(b_id)
		_tile_inspector_label.text = "선택 구역: %s — %s (연계 시설: %s)" % [
			str(zinfo.get("name", _selected_zone_id)),
			str(zinfo.get("desc", "")),
			str(binfo.get("name", b_id))
		]
	else:
		_tile_inspector_label.text = "본영 장원 점검: 지도에 마우스를 올리거나 구역을 클릭해 상세 정보를 확인하세요"

	for zt: String in ManorState.ZONE_TYPES:
		var btn_v: Variant = _zone_filter_btns.get(zt, null)
		if btn_v is Button:
			var b: Button = btn_v
			if _assets != null:
				_assets.apply_button_variant(b, "primary" if zt == _selected_zone_id else "chip")


func _on_grid_canvas_mouse_exited() -> void:
	_hover_tile = Vector2i(-1, -1)
	_refresh_zone_inspector_for_selection()
	if _grid_canvas != null:
		_grid_canvas.queue_redraw()


func _on_grid_canvas_gui_input(event: InputEvent) -> void:
	if _grid_canvas == null:
		return
	var csize: Vector2 = _grid_canvas.size
	if csize.x <= 0.0 or csize.y <= 0.0:
		return
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		var gx: int = clampi(int((mm.position.x / csize.x) * float(DtoSchemas.MANOR_GRID_SIZE)), 0, DtoSchemas.MANOR_GRID_SIZE - 1)
		var gy: int = clampi(int((mm.position.y / csize.y) * float(DtoSchemas.MANOR_GRID_SIZE)), 0, DtoSchemas.MANOR_GRID_SIZE - 1)
		if _hover_tile.x != gx or _hover_tile.y != gy:
			_hover_tile = Vector2i(gx, gy)
			_update_hover_inspector(gx, gy)
			_grid_canvas.queue_redraw()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var gx: int = clampi(int((mb.position.x / csize.x) * float(DtoSchemas.MANOR_GRID_SIZE)), 0, DtoSchemas.MANOR_GRID_SIZE - 1)
			var gy: int = clampi(int((mb.position.y / csize.y) * float(DtoSchemas.MANOR_GRID_SIZE)), 0, DtoSchemas.MANOR_GRID_SIZE - 1)
			var zid: String = _compound_zone_at(gx, gy)
			_on_zone_chip_pressed(zid)


func _pawn_display_name(pr: Dictionary) -> String:
	var pid: String = str(pr.get("pawn_id", "pawn"))
	var is_av: bool = _to_bool(pr.get("is_avatar", pid.ends_with("_avatar")), pid.ends_with("_avatar"))
	var raw_name: String = str(pr.get("name", "")).strip_edges()
	if raw_name.is_empty():
		raw_name = "조자룡" if is_av else "진도"
	return ("주군 " + raw_name) if is_av else ("가신 " + raw_name)


func _resolve_pawn_canvas_pos(pr: Dictionary, idx: int) -> Vector2:
	var pid: String = str(pr.get("pawn_id", "pawn"))
	var is_av: bool = _to_bool(pr.get("is_avatar", pid.ends_with("_avatar")), pid.ends_with("_avatar"))
	var job: String = str(pr.get("job", pr.get("current_job", "IDLE")))
	var raw_x: int = clampi(_to_int(pr.get("x", pr.get("grid_x", 16)), 16), 2, 29)
	var raw_y: int = clampi(_to_int(pr.get("y", pr.get("grid_y", 16)), 16), 2, 29)
	var anchor: Vector2 = _compound_anchor_for_job(job, is_av)
	# Blend deterministic simulation position toward the visual compound zone center so pawns inhabit compounds cleanly
	var vx: float = clampf(lerpf(anchor.x, float(raw_x), 0.28) + (float(idx) * 1.6 - 0.8), 2.5, 29.5)
	var vy: float = clampf(lerpf(anchor.y, float(raw_y), 0.28), 3.0, 29.0)
	return Vector2(vx, vy)


func _update_hover_inspector(gx: int, gy: int) -> void:
	if _tile_inspector_label == null:
		return
	var zid: String = _compound_zone_at(gx, gy)
	var zinfo: Dictionary = AssetRegistry.zone_info_ko(zid)
	var pawn_here: String = ""
	var pawn_rows: Array[Dictionary] = _extract_pawn_rows(_last_snapshot)
	for i: int in range(pawn_rows.size()):
		var pr: Dictionary = pawn_rows[i]
		var ppos: Vector2 = _resolve_pawn_canvas_pos(pr, i)
		var px_i: int = int(roundf(ppos.x))
		var py_i: int = int(roundf(ppos.y))
		if absi(px_i - gx) <= 1 and absi(py_i - gy) <= 1:
			var pname: String = _pawn_display_name(pr)
			var pjob: String = AssetRegistry.job_ko(str(pr.get("job", "IDLE")))
			pawn_here = " · 활동 중: %s(%s)" % [pname, pjob]
			break
	_tile_inspector_label.text = "(%d, %d) %s — %s%s" % [
		gx, gy, str(zinfo.get("name", zid)), str(zinfo.get("desc", "")), pawn_here
	]


func _on_quick_banquet_pressed() -> void:
	var pawn_rows: Array[Dictionary] = _extract_pawn_rows(_last_snapshot)
	var host_pid: String = "player_01_avatar"
	if not pawn_rows.is_empty():
		host_pid = str(pawn_rows[0].get("pawn_id", host_pid))
	intent_emitted.emit("CMD_HOST_BANQUET", {
		"host_pawn_id": host_pid,
		"wine_cost": 10,
		"grain_cost": 20
	})


func _on_quick_promote_troops_pressed() -> void:
	intent_emitted.emit("CMD_PROMOTE_TROOPS", {
		"unit_type": "SPEAR_SHIELD",
		"count": 20
	})


func _on_upgrade_pressed(building_id: String) -> void:
	emit_upgrade_intent(building_id)


func emit_upgrade_intent(building_id: String, grid_x: int = -1, grid_y: int = -1) -> void:
	var args: Dictionary = {"building_id": building_id}
	if grid_x >= 0 and grid_x < DtoSchemas.MANOR_GRID_SIZE:
		args["grid_x"] = grid_x
	if grid_y >= 0 and grid_y < DtoSchemas.MANOR_GRID_SIZE:
		args["grid_y"] = grid_y
	intent_emitted.emit("CMD_BUILD_OR_UPGRADE", args)


func _resolve_zone_grid() -> Array[String]:
	var grid: Array[String] = []
	var total: int = DtoSchemas.MANOR_GRID_SIZE * DtoSchemas.MANOR_GRID_SIZE
	grid.resize(total)
	for gy: int in range(DtoSchemas.MANOR_GRID_SIZE):
		for gx: int in range(DtoSchemas.MANOR_GRID_SIZE):
			grid[gy * DtoSchemas.MANOR_GRID_SIZE + gx] = _default_zone_at(gx, gy)

	var tmap_v: Variant = _last_snapshot.get("tile_zone_map", [])
	if tmap_v is Array:
		var tma: Array = tmap_v
		for idx: int in range(mini(total, tma.size())):
			var zi: int = _to_int(tma[idx], -1)
			if zi >= 0 and zi < ManorState.ZONE_TYPES.size():
				grid[idx] = ManorState.ZONE_TYPES[zi]
	elif _last_snapshot.get("zones", []) is Array:
		var zones_a: Array = _last_snapshot.get("zones", [])
		for zv: Variant in zones_a:
			if zv is Dictionary:
				var zd: Dictionary = zv
				var zid: String = str(zd.get("id", ""))
				if ManorState.ZONE_TYPES.has(zid):
					var zx: int = maxi(0, _to_int(zd.get("x", 0), 0))
					var zy: int = maxi(0, _to_int(zd.get("y", 0), 0))
					var zw: int = maxi(0, _to_int(zd.get("w", 0), 0))
					var zh: int = maxi(0, _to_int(zd.get("h", 0), 0))
					for py: int in range(zy, mini(DtoSchemas.MANOR_GRID_SIZE, zy + zh)):
						for px: int in range(zx, mini(DtoSchemas.MANOR_GRID_SIZE, zx + zw)):
							grid[py * DtoSchemas.MANOR_GRID_SIZE + px] = zid
	return grid


func _extract_pawn_rows(snapshot: Dictionary) -> Array[Dictionary]:
	var pawns_v: Variant = snapshot.get("pawns", {})
	var pawn_rows: Array[Dictionary] = []
	if pawns_v is Dictionary:
		var pd: Dictionary = pawns_v
		var pkeys: Array[String] = []
		for k: Variant in pd.keys():
			pkeys.append(str(k))
		pkeys.sort()
		for pk: String in pkeys:
			var pv: Variant = pd[pk]
			if pv is Dictionary:
				var pdict: Dictionary = pv
				var copy_p: Dictionary = pdict.duplicate(true)
				if not copy_p.has("pawn_id"):
					copy_p["pawn_id"] = pk
				pawn_rows.append(copy_p)
	elif pawns_v is Array:
		var pa: Array = pawns_v
		for pv: Variant in pa:
			if pv is Dictionary:
				var pdict: Dictionary = pv
				pawn_rows.append(pdict.duplicate(true))
	return pawn_rows


func _draw_tile_at(tile_tex: Texture2D, gx: float, gy: float, tile_w: float, tile_h: float, span_x: float = 1.0, span_y: float = 1.0, tint: Color = Color.WHITE) -> void:
	if _grid_canvas == null or tile_tex == null:
		return
	var r: Rect2 = Rect2(gx * tile_w, gy * tile_h, span_x * tile_w, span_y * tile_h)
	_grid_canvas.draw_texture_rect(tile_tex, r, false, tint)


func _draw_pill_badge(font: Font, center_px: Vector2, text_val: String, font_size: int, bg_col: Color, border_col: Color, text_col: Color) -> void:
	if _grid_canvas == null or font == null or text_val.is_empty():
		return
	var text_sz: Vector2 = font.get_string_size(text_val, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad_x: float = 7.0
	var pad_y: float = 2.0
	var pill_w: float = text_sz.x + pad_x * 2.0
	var pill_h: float = text_sz.y + pad_y * 2.0
	var csize: Vector2 = _grid_canvas.size
	if csize.x <= 0.0:
		csize = _grid_canvas.custom_minimum_size
	var px: float = clampf(center_px.x - pill_w * 0.5, 4.0, maxf(4.0, csize.x - pill_w - 4.0))
	var py: float = clampf(center_px.y - pill_h * 0.5, 3.0, maxf(3.0, csize.y - pill_h - 3.0))
	var pill_rect: Rect2 = Rect2(px, py, pill_w, pill_h)
	_grid_canvas.draw_rect(pill_rect, bg_col, true)
	_grid_canvas.draw_rect(pill_rect, border_col, false, 1.2)
	var baseline_y: float = py + pad_y + font.get_ascent(font_size) - 1.0
	_grid_canvas.draw_string(font, Vector2(px + pad_x, baseline_y), text_val, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_col)


func _on_grid_canvas_draw() -> void:
	if _grid_canvas == null:
		return
	var canvas_size: Vector2 = _grid_canvas.size
	if canvas_size.x <= 0.0 or canvas_size.y <= 0.0:
		canvas_size = _grid_canvas.custom_minimum_size
	var tile_w: float = canvas_size.x / float(DtoSchemas.MANOR_GRID_SIZE)
	var tile_h: float = canvas_size.y / float(DtoSchemas.MANOR_GRID_SIZE)
	var ui_font: Font = _assets.get_ui_font() if _assets != null else ThemeDB.fallback_font

	# Base backdrop
	_grid_canvas.draw_rect(Rect2(Vector2.ZERO, canvas_size), Color(0.18, 0.26, 0.14, 1.0))

	if _assets == null:
		return

	# Preload verified CC0 tile slices
	var grass0: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 0, 0)
	var grass1: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 1, 0)
	var grass2: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 2, 0)
	var dirt_tile: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 1, 2)
	var dirt_edge: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 1, 1)
	var cobble_tile: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 7, 3)
	var stone_floor: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 1, 9)
	var stone_wall: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 4, 8)
	var palisade_h: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 9, 3)
	var fence_h: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 8, 3)
	var gate_l: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 3, 9)
	var gate_r: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 4, 9)

	var tree_oak: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 4, 2)
	var tree_autumn: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 3, 2)
	var tree_rpg: Texture2D = _assets.get_texture(RPG_TREE01_PATH)
	var inn_tex: Texture2D = _assets.get_texture(RPG_HOUSE_INN_PATH)

	# 1. TERRAIN LAYER: Lush green grass with deterministic variation + warm courtyard tint
	for gy: int in range(DtoSchemas.MANOR_GRID_SIZE):
		for gx: int in range(DtoSchemas.MANOR_GRID_SIZE):
			var h: int = (gx * 7 + gy * 13) % 11
			var gtex: Texture2D = grass0 if h < 7 else (grass1 if h < 10 else grass2)
			_draw_tile_at(gtex, float(gx), float(gy), tile_w, tile_h)
			# Subtle interior compound courtyard ground tone
			if gx >= 2 and gx <= 29 and gy >= 2 and gy <= 29:
				_grid_canvas.draw_rect(
					Rect2(float(gx) * tile_w, float(gy) * tile_h, tile_w, tile_h),
					Color(0.20, 0.17, 0.12, 0.14)
				)

	# 2. MAIN COURTYARD CROSSROADS (Stone cobblestone N-S & E-W paths connecting all 8 compounds)
	for gy: int in range(7, 31):
		_draw_tile_at(cobble_tile, 15.0, float(gy), tile_w, tile_h)
		_draw_tile_at(cobble_tile, 16.0, float(gy), tile_w, tile_h)
		_grid_canvas.draw_rect(Rect2(15.0 * tile_w, float(gy) * tile_h, tile_w * 2.0, tile_h), Color(0.68, 0.62, 0.50, 0.30))
	for gx: int in range(3, 29):
		_draw_tile_at(cobble_tile, float(gx), 14.0, tile_w, tile_h)
		_draw_tile_at(cobble_tile, float(gx), 15.0, tile_w, tile_h)
		_grid_canvas.draw_rect(Rect2(float(gx) * tile_w, 14.0 * tile_h, tile_w, tile_h * 2.0), Color(0.68, 0.62, 0.50, 0.30))
	# Central Manor Plaza circle/square
	for py: int in range(12, 16):
		for px: int in range(14, 18):
			_draw_tile_at(stone_floor, float(px), float(py), tile_w, tile_h, 1.0, 1.0, Color(0.92, 0.88, 0.78, 0.85))

	# 3. PERIMETER FOREST (Outside the palisade walls)
	var outer_trees: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(5, 0), Vector2i(10, 0), Vector2i(21, 0), Vector2i(27, 0), Vector2i(31, 0),
		Vector2i(0, 5), Vector2i(0, 12), Vector2i(0, 20), Vector2i(0, 28),
		Vector2i(31, 4), Vector2i(31, 13), Vector2i(31, 22), Vector2i(31, 29),
		Vector2i(2, 31), Vector2i(8, 31), Vector2i(23, 31), Vector2i(29, 31)
	]
	for ti: int in range(outer_trees.size()):
		var tp: Vector2i = outer_trees[ti]
		if ti % 4 == 0 and tree_rpg != null:
			_draw_tile_at(tree_rpg, float(tp.x) - 0.15, float(tp.y) - 0.4, tile_w, tile_h, 1.4, 1.6)
		else:
			_draw_tile_at(tree_autumn if ti % 3 == 1 else tree_oak, float(tp.x), float(tp.y), tile_w, tile_h, 1.15, 1.15)

	# 4. PERIMETER PALISADE & WATCHTOWERS (x=1..30, y=1..30 with southern double gatehouse at x=15..16, y=30)
	for gx: int in range(1, 31):
		# North stone battlements + palisade
		if gx == 1 or gx == 30 or gx == 10 or gx == 21:
			_draw_tile_at(stone_wall, float(gx), 1.0, tile_w, tile_h)
		else:
			_draw_tile_at(palisade_h, float(gx), 1.0, tile_w, tile_h)
		# South palisade with double gatehouse at x=15, 16
		if gx == 15:
			_draw_tile_at(gate_l, float(gx), 30.0, tile_w, tile_h)
		elif gx == 16:
			_draw_tile_at(gate_r, float(gx), 30.0, tile_w, tile_h)
		elif gx == 1 or gx == 30 or gx == 13 or gx == 18:
			_draw_tile_at(stone_wall, float(gx), 30.0, tile_w, tile_h)
		else:
			_draw_tile_at(palisade_h, float(gx), 30.0, tile_w, tile_h)
	for gy: int in range(2, 30):
		_draw_tile_at(stone_wall if gy % 7 == 1 else palisade_h, 1.0, float(gy), tile_w, tile_h)
		_draw_tile_at(stone_wall if gy % 7 == 1 else palisade_h, 30.0, float(gy), tile_w, tile_h)

	# 5. 8 DISTINCT ARCHITECTURAL COMPOUNDS (Cohesive buildings & props, zero wallpaper tiling!)
	var bld_v: Variant = _last_snapshot.get("buildings", {})
	var bld: Dictionary = bld_v if bld_v is Dictionary else {}
	var main_hall_lvl: int = clampi(_to_int(bld.get("MAIN_HALL", 1), 1), 1, 5)
	var vault_lvl: int = clampi(_to_int(bld.get("GRANARY_VAULT", 1), 1), 1, 5)
	var vault_pct: int = clampi(40 + (vault_lvl - 1) * 5, 40, 65)

	# (a) 본영 관아 (Main Hall, center-north x=12..20, y=3..7)
	var mh_rect: Rect2 = Rect2(11.5 * tile_w, 2.6 * tile_h, 9.0 * tile_w, 5.2 * tile_h)
	_grid_canvas.draw_rect(mh_rect, Color(0.22, 0.20, 0.18, 0.60))
	var slate_tl: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 0, 4)
	var slate_tm: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 1, 4)
	var slate_tr: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 2, 4)
	var slate_bl: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 0, 5)
	var slate_bm: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 1, 5)
	var slate_br: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 2, 5)
	var wall_mid: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 5, 6)
	var wood_door: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 2, 7)
	var banner_tex: Texture2D = _assets.slice_tile(AssetRegistry.TINY_DUNGEON, 5, 2)
	for mx: int in range(13, 19):
		var roof_top: Texture2D = slate_tl if mx == 13 else (slate_tr if mx == 18 else slate_tm)
		var roof_bot: Texture2D = slate_bl if mx == 13 else (slate_br if mx == 18 else slate_bm)
		_draw_tile_at(roof_top, float(mx), 3.0, tile_w, tile_h)
		_draw_tile_at(roof_bot, float(mx), 4.0, tile_w, tile_h)
		_draw_tile_at(wood_door if (mx == 15 or mx == 16) else wall_mid, float(mx), 5.0, tile_w, tile_h)
	_draw_tile_at(banner_tex, 12.2, 4.8, tile_w, tile_h, 1.1, 1.3)
	_draw_tile_at(banner_tex, 18.7, 4.8, tile_w, tile_h, 1.1, 1.3)

	# (b) 둔전 농지 (Farmland, west x=3..10, y=6..13) — warm tilled soil bordered by wooden fence, 4 grain sheaves + 1 pitchfork
	_grid_canvas.draw_rect(Rect2(2.6 * tile_w, 5.6 * tile_h, 7.8 * tile_w, 7.8 * tile_h), Color(0.42, 0.28, 0.16, 0.35))
	for fy: int in range(7, 13):
		for fx: int in range(3, 10):
			_draw_tile_at(dirt_tile if (fy % 2 == 0) else dirt_edge, float(fx), float(fy), tile_w, tile_h, 1.0, 1.0, Color(0.95, 0.88, 0.78, 0.92))
	for fx_f: int in range(3, 10):
		_draw_tile_at(fence_h, float(fx_f), 6.0, tile_w, tile_h)
		_draw_tile_at(fence_h, float(fx_f), 13.0, tile_w, tile_h)
	var wheat_tex: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 10, 7)
	var pitchfork_tex: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 8, 9)
	_draw_tile_at(wheat_tex, 3.8, 7.6, tile_w, tile_h, 1.15, 1.15)
	_draw_tile_at(wheat_tex, 6.2, 7.6, tile_w, tile_h, 1.15, 1.15)
	_draw_tile_at(wheat_tex, 4.4, 10.2, tile_w, tile_h, 1.15, 1.15)
	_draw_tile_at(wheat_tex, 7.2, 10.2, tile_w, tile_h, 1.15, 1.15)
	_draw_tile_at(pitchfork_tex, 8.6, 8.8, tile_w, tile_h, 1.1, 1.1)

	# (c) 군량고 · 비상 지하창고 (Stockpile & Hidden Vault, north-east x=19..29, y=8..13)
	for sy: int in range(9, 13):
		for sx: int in range(19, 25):
			_draw_tile_at(stone_floor, float(sx), float(sy), tile_w, tile_h, 1.0, 1.0, Color(0.85, 0.80, 0.68, 0.92))
		for vx: int in range(25, 30):
			_draw_tile_at(stone_wall, float(vx), float(sy), tile_w, tile_h, 1.0, 1.0, Color(0.70, 0.66, 0.84, 0.92))
	var cart_tex: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 9, 4)
	var crate_tex: Texture2D = _assets.slice_tile(AssetRegistry.TINY_DUNGEON, 3, 5)
	var barrel_tex: Texture2D = _assets.slice_tile(AssetRegistry.TINY_DUNGEON, 10, 6)
	var chest_tex: Texture2D = _assets.slice_tile(AssetRegistry.TINY_DUNGEON, 5, 7)
	_draw_tile_at(cart_tex, 19.6, 9.6, tile_w, tile_h, 1.3, 1.3)
	_draw_tile_at(cart_tex, 21.8, 11.2, tile_w, tile_h, 1.3, 1.3)
	_draw_tile_at(crate_tex, 21.6, 9.4, tile_w, tile_h, 1.05, 1.05)
	_draw_tile_at(crate_tex, 23.0, 9.4, tile_w, tile_h, 1.05, 1.05)
	_draw_tile_at(crate_tex, 19.8, 11.3, tile_w, tile_h, 1.05, 1.05)
	_draw_tile_at(barrel_tex, 23.4, 11.2, tile_w, tile_h, 1.05, 1.05)
	_draw_tile_at(barrel_tex, 20.8, 11.4, tile_w, tile_h, 1.05, 1.05)
	_draw_tile_at(chest_tex, 26.2, 10.2, tile_w, tile_h, 1.25, 1.25)
	_draw_tile_at(chest_tex, 27.8, 10.2, tile_w, tile_h, 1.25, 1.25)

	# (d) 병영 · 연병장 (Barracks, south-west x=3..13, y=17..23)
	for by: int in range(18, 23):
		for bx: int in range(3, 13):
			_draw_tile_at(dirt_edge, float(bx), float(by), tile_w, tile_h, 1.0, 1.0, Color(0.88, 0.78, 0.66, 0.85))
	var red_l: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 4, 4)
	var red_m: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 5, 4)
	var red_r: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 6, 4)
	var door_s: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 1, 7)
	for bx_h: int in range(7, 12):
		var rt: Texture2D = red_l if bx_h == 7 else (red_r if bx_h == 11 else red_m)
		_draw_tile_at(rt, float(bx_h), 18.2, tile_w, tile_h)
		_draw_tile_at(door_s if bx_h == 9 else wall_mid, float(bx_h), 19.2, tile_w, tile_h)
	var target_tex: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 11, 7)
	var wep_tex: Texture2D = _assets.slice_tile(AssetRegistry.TINY_DUNGEON, 8, 8)
	_draw_tile_at(target_tex, 3.6, 18.8, tile_w, tile_h, 1.15, 1.15)
	_draw_tile_at(target_tex, 3.6, 20.3, tile_w, tile_h, 1.15, 1.15)
	_draw_tile_at(target_tex, 3.6, 21.8, tile_w, tile_h, 1.15, 1.15)
	_draw_tile_at(wep_tex, 11.4, 21.2, tile_w, tile_h, 1.25, 1.25)

	# (e) 대장간 · 공방 (Workshop, center-east x=19..29, y=16..21)
	for wy: int in range(16, 21):
		for wx: int in range(20, 29):
			_draw_tile_at(stone_floor, float(wx), float(wy), tile_w, tile_h, 1.0, 1.0, Color(0.86, 0.78, 0.70, 0.85))
	if inn_tex != null:
		_draw_tile_at(inn_tex, 20.5, 16.2, tile_w, tile_h, 3.6, 3.8)
	else:
		for wx_h: int in range(21, 25):
			_draw_tile_at(red_m, float(wx_h), 16.5, tile_w, tile_h)
	var log_tex: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 10, 8)
	var pick_tex: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 7, 9)
	_draw_tile_at(log_tex, 25.4, 17.2, tile_w, tile_h, 1.25, 1.25)
	_draw_tile_at(log_tex, 27.0, 17.2, tile_w, tile_h, 1.25, 1.25)
	_draw_tile_at(pick_tex, 25.8, 19.2, tile_w, tile_h, 1.2, 1.2)
	# Glowing forge hearth accent
	var forge_center: Vector2 = Vector2(27.8 * tile_w, 19.6 * tile_h)
	_grid_canvas.draw_circle(forge_center, tile_w * 0.65, Color(0.96, 0.48, 0.14, 0.55))
	_grid_canvas.draw_circle(forge_center, tile_w * 0.32, Color(1.0, 0.84, 0.34, 0.88))

	# (f) 가신 숙소 (Residence quarters, south-center x=4..16, y=24..29)
	for rx_q: int in range(5, 13):
		if rx_q == 8 or rx_q == 9:
			continue
		var r_roof: Texture2D = red_l if (rx_q == 5 or rx_q == 10) else (red_r if (rx_q == 7 or rx_q == 12) else red_m)
		_draw_tile_at(r_roof, float(rx_q), 25.5, tile_w, tile_h)
		_draw_tile_at(door_s if (rx_q == 6 or rx_q == 11) else wall_mid, float(rx_q), 26.5, tile_w, tile_h)

	# (g) 의막 (Infirmary, south-east x=20..29, y=23..29)
	var well_tex: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 7, 8)
	var herb_tex: Texture2D = _assets.slice_tile(AssetRegistry.TINY_TOWN, 5, 2)
	var potion_tex: Texture2D = _assets.slice_tile(AssetRegistry.TINY_DUNGEON, 6, 9)
	for iy_h: int in range(25, 28):
		for ix_h: int in range(21, 25):
			var roof_i: Texture2D = slate_tl if ix_h == 21 else (slate_tr if ix_h == 24 else slate_tm)
			if iy_h == 25:
				_draw_tile_at(roof_i, float(ix_h), float(iy_h), tile_w, tile_h)
			elif iy_h == 26:
				_draw_tile_at(door_s if ix_h == 22 else wall_mid, float(ix_h), float(iy_h), tile_w, tile_h)
	_draw_tile_at(well_tex, 26.2, 25.2, tile_w, tile_h, 1.25, 1.25)
	_draw_tile_at(herb_tex, 26.0, 27.2, tile_w, tile_h, 1.15, 1.15)
	_draw_tile_at(herb_tex, 27.4, 27.2, tile_w, tile_h, 1.15, 1.15)
	_draw_tile_at(potion_tex, 23.6, 27.2, tile_w, tile_h, 1.15, 1.15)

	# 6. ZONE HIGHLIGHT OVERLAY & SELECTION GOLD FRAME
	for cdef: Dictionary in COMPOUND_DEFS:
		var z_id: String = str(cdef.get("zone", ""))
		var r_v: Variant = cdef.get("rect", Rect2i(0, 0, 0, 0))
		if not (r_v is Rect2i):
			continue
		var r: Rect2i = r_v
		var px_rect: Rect2 = Rect2(
			float(r.position.x) * tile_w,
			float(r.position.y) * tile_h,
			float(r.size.x) * tile_w,
			float(r.size.y) * tile_h
		)
		if not _selected_zone_id.is_empty():
			if z_id == _selected_zone_id:
				_grid_canvas.draw_rect(px_rect, Color(0.98, 0.82, 0.35, 0.16), true)
				_grid_canvas.draw_rect(px_rect, AssetRegistry.COLOR_GOLD_HIGHLIGHT, false, 2.4)
			else:
				_grid_canvas.draw_rect(px_rect, Color(0.05, 0.04, 0.03, 0.42), true)

	# Hover tile cursor
	if _hover_tile.x >= 0 and _hover_tile.y >= 0:
		var hrect: Rect2 = Rect2(
			float(_hover_tile.x) * tile_w,
			float(_hover_tile.y) * tile_h,
			tile_w,
			tile_h
		)
		_grid_canvas.draw_rect(hrect, AssetRegistry.COLOR_GOLD_HIGHLIGHT, false, 2.0)

	# 7. CRISP ON-CANVAS COMPOUND NAMEPLATE PILLS
	for cdef: Dictionary in COMPOUND_DEFS:
		var z_id: String = str(cdef.get("zone", ""))
		var lbl_text: String = str(cdef.get("label", ""))
		if z_id == "ZONE_DEFENSE_LINE":
			lbl_text = "본영 관아 Lv.%d" % main_hall_lvl
		elif z_id == "ZONE_HIDDEN_VAULT":
			lbl_text = "지하창고 %d%%" % vault_pct
		var ppos_v: Variant = cdef.get("pill_pos", Vector2(16.0, 16.0))
		var ppos: Vector2 = ppos_v if ppos_v is Vector2 else Vector2(16.0, 16.0)
		var is_sel: bool = (not _selected_zone_id.is_empty() and z_id == _selected_zone_id)
		_draw_pill_badge(
			ui_font,
			Vector2(ppos.x * tile_w, ppos.y * tile_h),
			lbl_text,
			10,
			Color(0.11, 0.09, 0.07, 0.88),
			AssetRegistry.COLOR_GOLD_HIGHLIGHT if is_sel else Color(0.76, 0.60, 0.28, 0.88),
			AssetRegistry.COLOR_GOLD_HIGHLIGHT if is_sel else AssetRegistry.COLOR_PARCHMENT_TEXT
		)

	# 8. VISIBLY ALIVE RIMWORLD PAWNS WITH SHADOW, SPRITE, NAME+JOB PILL, MOOD BAR & EMOTE
	var meta_v: Variant = _last_snapshot.get("meta", {})
	var meta: Dictionary = meta_v if meta_v is Dictionary else {}
	var raid_active: bool = _to_bool(meta.get("raid_defense_active", _last_snapshot.get("raid_defense_active", false)), false)

	var pawn_rows: Array[Dictionary] = _extract_pawn_rows(_last_snapshot)
	for i: int in range(pawn_rows.size()):
		var pr: Dictionary = pawn_rows[i]
		var pid: String = str(pr.get("pawn_id", "pawn"))
		var is_avatar: bool = _to_bool(pr.get("is_avatar", pid.ends_with("_avatar")), pid.ends_with("_avatar"))
		var job: String = str(pr.get("job", pr.get("current_job", "IDLE")))
		var role_hint: String = str(pr.get("role_hint", pr.get("epithet", job)))
		var mstate: String = str(pr.get("mental_state", "NORMAL"))
		var mood_v: int = clampi(_to_int(pr.get("mood", 60), 60), 0, 100)

		var pgrid_pos: Vector2 = _resolve_pawn_canvas_pos(pr, i)
		var cx: float = pgrid_pos.x * tile_w
		var cy: float = pgrid_pos.y * tile_h

		# Soft ground shadow
		_grid_canvas.draw_rect(Rect2(cx - 11.0, cy + 8.0, 22.0, 6.0), Color(0.03, 0.03, 0.02, 0.50), true)

		# 26x26 scaled CC0 character sprite
		var sprite_rect: Rect2 = Rect2(cx - 13.0, cy - 14.0, 26.0, 26.0)
		var ptex: Texture2D = _assets.get_pawn_sprite(is_avatar, role_hint)
		if ptex != null:
			_grid_canvas.draw_texture_rect(ptex, sprite_rect, false)
		else:
			_grid_canvas.draw_rect(sprite_rect, AssetRegistry.COLOR_GOLD_HIGHLIGHT if is_avatar else AssetRegistry.COLOR_PARCHMENT_TEXT)

		# Compact Mood bar underneath pawn
		var bar_w: float = 26.0
		var bar_rect_bg: Rect2 = Rect2(cx - bar_w * 0.5, cy + 14.0, bar_w, 4.0)
		_grid_canvas.draw_rect(bar_rect_bg, Color(0.08, 0.07, 0.06, 0.90), true)
		var mood_col: Color = AssetRegistry.COLOR_SUCCESS_JADE if mood_v >= 60 else (AssetRegistry.COLOR_WARNING_AMBER if mood_v >= 35 else AssetRegistry.COLOR_DANGER_CRIMSON)
		var fill_w: float = bar_w * (float(mood_v) / 100.0)
		_grid_canvas.draw_rect(Rect2(cx - bar_w * 0.5, cy + 14.0, fill_w, 4.0), mood_col, true)

		# Floating Korean nameplate + current job pill above head
		var disp_name: String = _pawn_display_name(pr)
		var job_txt: String = AssetRegistry.job_ko(job)
		_draw_pill_badge(
			ui_font,
			Vector2(cx, cy - 22.0),
			"%s · %s" % [disp_name, job_txt],
			10,
			Color(0.09, 0.08, 0.07, 0.92),
			AssetRegistry.COLOR_GOLD_HIGHLIGHT if is_avatar else AssetRegistry.COLOR_INFO_AZURE,
			AssetRegistry.COLOR_GOLD_HIGHLIGHT if is_avatar else AssetRegistry.COLOR_TEXT_PRIMARY
		)

		# CC0 Emote icon when active
		var emote_tex: Texture2D = _assets.get_emote_texture(mstate, raid_active)
		if emote_tex != null:
			var emote_rect: Rect2 = Rect2(cx + 10.0, cy - 18.0, 14.0, 14.0)
			_grid_canvas.draw_texture_rect(emote_tex, emote_rect, false)


func _make_need_bar(label_txt: String, pct_val: int) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 1)

	var top: HBoxContainer = HBoxContainer.new()
	var nlbl: Label = Label.new()
	nlbl.text = label_txt
	nlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	AssetRegistry.apply_text_role(nlbl, "caption")
	top.add_child(nlbl)

	var vlbl: Label = AssetRegistry.make_numeric_label("%d%%" % pct_val, 32.0)
	vlbl.add_theme_font_size_override("font_size", AssetRegistry.FONT_SIZE_CAPTION)
	top.add_child(vlbl)
	box.add_child(top)

	var pb: ProgressBar = ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = 100.0
	pb.value = float(clampi(pct_val, 0, 100))
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 6)
	var fill_col: Color = AssetRegistry.COLOR_SUCCESS_JADE if pct_val >= 60 else (AssetRegistry.COLOR_WARNING_AMBER if pct_val >= 30 else AssetRegistry.COLOR_DANGER_CRIMSON)
	var fill_sb: StyleBoxFlat = StyleBoxFlat.new()
	fill_sb.bg_color = fill_col
	fill_sb.set_corner_radius_all(2)
	pb.add_theme_stylebox_override("fill", fill_sb)
	box.add_child(pb)
	return box


func apply_snapshot(snapshot: Dictionary) -> void:
	_last_snapshot = snapshot.duplicate(true)

	var meta_v: Variant = snapshot.get("meta", {})
	var meta: Dictionary = meta_v if meta_v is Dictionary else {}
	var lod: int = _to_int(meta.get("lod", snapshot.get("current_lod", 1)), 1)
	var wall_hp: int = _to_int(meta.get("wall_hp", snapshot.get("wall_hp", 0)), 0)
	var troops: int = _to_int(meta.get("household_troops", snapshot.get("household_troops", 0)), 0)
	var manor_id: String = str(snapshot.get("manor_id", "manor"))
	var lod_ko: String = "실시간(LOD 0)" if lod == 0 else "요약(LOD %d)" % lod
	_header_label.text = "장원 [%s] · 32×32 · %s · 성벽 %s · 사병 %s" % [
		manor_id,
		lod_ko,
		AssetRegistry.format_num(wall_hp),
		AssetRegistry.format_num(troops)
	]

	# Keep hidden compatibility _resources_label updated with "GRAIN: ..." for existing unit tests
	var stock_v: Variant = snapshot.get("stockpile", snapshot.get("resources", {}))
	var stock: Dictionary = stock_v if stock_v is Dictionary else {}
	var res_parts: PackedStringArray = PackedStringArray()
	for rk: String in DtoSchemas.RESOURCE_KEYS:
		var rval: int = _to_int(stock.get(rk, 0), 0)
		var _ok_r: bool = res_parts.append("%s: %d" % [rk, rval])
		var rlbl_v: Variant = _resource_icon_labels.get(rk, null)
		if rlbl_v is Label:
			var rlbl: Label = rlbl_v
			rlbl.text = "%s:%d" % [rk, rval]
	_resources_label.text = "8대 자원 | " + " | ".join(res_parts)

	# 8-zone counts across 32x32 (1024 tiles)
	var zone_counts: Dictionary = {}
	for zt: String in ManorState.ZONE_TYPES:
		zone_counts[zt] = 0

	var tmap_v: Variant = snapshot.get("tile_zone_map", [])
	var counted_tiles: int = 0
	if tmap_v is Array:
		var tma: Array = tmap_v
		for tv: Variant in tma:
			var zi: int = _to_int(tv, 1)
			if zi >= 0 and zi < ManorState.ZONE_TYPES.size():
				var zname: String = ManorState.ZONE_TYPES[zi]
				zone_counts[zname] = _to_int(zone_counts.get(zname, 0), 0) + 1
				counted_tiles += 1
	elif snapshot.get("zones", []) is Array:
		var zones_a: Array = snapshot.get("zones", [])
		for zv: Variant in zones_a:
			if zv is Dictionary:
				var zd: Dictionary = zv
				var zid: String = str(zd.get("id", ""))
				var area: int = maxi(0, _to_int(zd.get("w", 0), 0)) * maxi(0, _to_int(zd.get("h", 0), 0))
				if zone_counts.has(zid):
					zone_counts[zid] = _to_int(zone_counts[zid], 0) + area
					counted_tiles += area

	if counted_tiles == 0:
		counted_tiles = DtoSchemas.MANOR_GRID_SIZE * DtoSchemas.MANOR_GRID_SIZE
		zone_counts["ZONE_DEFENSE_LINE"] = 128
		zone_counts["ZONE_FARMLAND"] = 192
		zone_counts["ZONE_STOCKPILE"] = 80
		zone_counts["ZONE_HIDDEN_VAULT"] = 48
		zone_counts["ZONE_BARRACKS"] = 128
		zone_counts["ZONE_WORKSHOP"] = 128
		zone_counts["ZONE_RESIDENCE"] = 176
		zone_counts["ZONE_INFIRMARY"] = 144

	_grid_summary_label.text = "32×32 격자 (%s 타일 활성)" % AssetRegistry.format_num(counted_tiles)
	var z_parts: PackedStringArray = PackedStringArray()
	for zt: String in ManorState.ZONE_TYPES:
		var zc: int = _to_int(zone_counts.get(zt, 0), 0)
		var _ok_z: bool = z_parts.append("%s=%d" % [zt, zc])
		var zbtn_v: Variant = _zone_filter_btns.get(zt, null)
		if zbtn_v is Button:
			var zbtn: Button = zbtn_v
			var zinfo: Dictionary = AssetRegistry.zone_info_ko(zt)
			zbtn.text = "%s (%d)" % [str(zinfo.get("name", zt)), zc]
	_zones_label.text = "8대 구역 타일 수: " + ", ".join(z_parts)

	# 10 building levels + upgrade costs
	var bld_v: Variant = snapshot.get("buildings", {})
	var bld: Dictionary = bld_v if bld_v is Dictionary else {}
	var wood_avail: int = _to_int(stock.get("WOOD", 0), 0)
	var coin_avail: int = _to_int(stock.get("COIN", 0), 0)
	for bid: String in ManorState.BUILDING_IDS:
		var lvl: int = clampi(_to_int(bld.get(bid, 1), 1), 1, 5)
		var binfo: Dictionary = AssetRegistry.building_info_ko(bid)
		var bname: String = str(binfo.get("name", bid))
		var cost_wood: int = 120 * lvl
		var cost_coin: int = 180 * lvl
		var entry_v: Variant = _upgrade_buttons.get(bid, null)
		if entry_v is Dictionary:
			var entry: Dictionary = entry_v
			var lbl_v: Variant = entry.get("label", null)
			if lbl_v is Label:
				var lbl: Label = lbl_v
				lbl.text = "%s · Lv.%d/5" % [bname, lvl]
			var cost_v: Variant = entry.get("cost_label", null)
			if cost_v is Label:
				var clbl: Label = cost_v
				if lvl >= 5:
					clbl.text = "최고 등급 달성"
					clbl.add_theme_color_override("font_color", AssetRegistry.COLOR_GOLD_HIGHLIGHT)
				else:
					clbl.text = "목재 %s · 은전 %s" % [AssetRegistry.format_num(cost_wood), AssetRegistry.format_num(cost_coin)]
					var can_afford: bool = wood_avail >= cost_wood and coin_avail >= cost_coin
					clbl.add_theme_color_override("font_color", AssetRegistry.COLOR_TEXT_SECONDARY if can_afford else AssetRegistry.COLOR_TEXT_MUTED)
			var btn_v: Variant = entry.get("button", null)
			if btn_v is Button:
				var btn: Button = btn_v
				btn.disabled = lvl >= 5
				btn.text = "완료" if lvl >= 5 else "증축"
				if _assets != null:
					_assets.apply_button_variant(btn, "secondary" if lvl < 5 else "chip")

	# Pawn needs / mood / mental state cards (preserve _pawns_box.get_child_count() == pawn_rows.size())
	for child: Node in _pawns_box.get_children():
		_pawns_box.remove_child(child)
		child.queue_free()

	var pawn_rows: Array[Dictionary] = _extract_pawn_rows(snapshot)
	if _pawns_empty_label != null:
		_pawns_empty_label.visible = pawn_rows.is_empty()

	var hero_banner_patch: Dictionary = {
		"troops": troops,
		"wall_hp": wall_hp
	}

	for pr: Dictionary in pawn_rows:
		var pid: String = str(pr.get("pawn_id", "pawn"))
		var is_av: bool = _to_bool(pr.get("is_avatar", pid.ends_with("_avatar")), pid.ends_with("_avatar"))
		var gx: int = _to_int(pr.get("x", pr.get("grid_x", 16)), 16)
		var gy: int = _to_int(pr.get("y", pr.get("grid_y", 16)), 16)
		var job_raw: String = str(pr.get("job", pr.get("current_job", "IDLE")))
		var job_lbl: String = AssetRegistry.job_ko(job_raw)
		var mood_v: int = clampi(_to_int(pr.get("mood", 50), 50), 0, 100)
		var mstate_raw: String = str(pr.get("mental_state", "NORMAL"))
		var mstate_lbl: String = AssetRegistry.mental_state_ko(mstate_raw)
		var needs_v: Variant = pr.get("needs_bp", {})
		var needs: Dictionary = needs_v if needs_v is Dictionary else {}
		var food_pct: int = clampi(_to_int(pr.get("food_bp", needs.get("FOOD", 5000)), 5000) / 100, 0, 100)
		var rest_pct: int = clampi(_to_int(pr.get("rest_bp", needs.get("REST", 5000)), 5000) / 100, 0, 100)
		var loy_pct: int = clampi(_to_int(pr.get("loyalty_bp", needs.get("LOYALTY", 5000)), 5000) / 100, 0, 100)

		if is_av:
			if pr.has("name") and not str(pr.get("name", "")).is_empty():
				hero_banner_patch["name"] = str(pr.get("name", ""))
			if pr.has("stats") and pr.get("stats") is Dictionary:
				hero_banner_patch["stats"] = pr.get("stats")
			if pr.has("traits") and pr.get("traits") is Array:
				hero_banner_patch["traits"] = pr.get("traits")

		var pcard: PanelContainer = PanelContainer.new()
		pcard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var psb: StyleBoxFlat = StyleBoxFlat.new()
		psb.bg_color = Color(0.12, 0.10, 0.09, 0.94)
		psb.border_color = AssetRegistry.COLOR_GOLD_ACCENT if is_av else AssetRegistry.COLOR_SUBTLE_BORDER
		psb.set_border_width_all(1)
		psb.set_corner_radius_all(4)
		psb.content_margin_left = 8.0
		psb.content_margin_right = 8.0
		psb.content_margin_top = 5.0
		psb.content_margin_bottom = 5.0
		pcard.add_theme_stylebox_override("panel", psb)

		var pvbox: VBoxContainer = VBoxContainer.new()
		pvbox.add_theme_constant_override("separation", 4)
		pcard.add_child(pvbox)

		var header_r: HBoxContainer = HBoxContainer.new()
		header_r.add_theme_constant_override("separation", 6)
		pvbox.add_child(header_r)

		if _assets != null:
			var p_icon: TextureRect = TextureRect.new()
			p_icon.custom_minimum_size = Vector2(20, 20)
			p_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			p_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			p_icon.texture = _assets.get_pawn_sprite(is_av, job_raw)
			header_r.add_child(p_icon)

		var disp_title: String = _pawn_display_name(pr)
		var epithet_str: String = str(pr.get("epithet", "")).strip_edges()
		if epithet_str.is_empty():
			epithet_str = "한실 신흥군" if is_av else "서약 가신"
		var name_lbl: Label = Label.new()
		name_lbl.text = "%s (%s) · (%d,%d)" % [disp_title, epithet_str, gx, gy]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		AssetRegistry.apply_text_role(name_lbl, "body")
		header_r.add_child(name_lbl)

		var state_lbl: Label = Label.new()
		state_lbl.text = "%s · %s" % [job_lbl, mstate_lbl]
		AssetRegistry.apply_text_role(state_lbl, "caption")
		header_r.add_child(state_lbl)

		var bars_grid: GridContainer = GridContainer.new()
		bars_grid.columns = 4
		bars_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bars_grid.add_theme_constant_override("h_separation", 8)
		bars_grid.add_child(_make_need_bar("기분", mood_v))
		bars_grid.add_child(_make_need_bar("군량", food_pct))
		bars_grid.add_child(_make_need_bar("휴식", rest_pct))
		bars_grid.add_child(_make_need_bar("충성", loy_pct))
		pvbox.add_child(bars_grid)

		_pawns_box.add_child(pcard)

	update_hero_banner(hero_banner_patch)

	if _grid_canvas != null:
		_grid_canvas.queue_redraw()


func get_building_level_displayed(building_id: String) -> int:
	var bld_v: Variant = _last_snapshot.get("buildings", {})
	if bld_v is Dictionary:
		var bld: Dictionary = bld_v
		return _to_int(bld.get(building_id, 1), 1)
	return 1


func reset_view_state() -> void:
	_last_snapshot.clear()
	_selected_zone_id = ""
	_hover_tile = Vector2i(-1, -1)
	_chronicle_lines.clear()
	_cached_hero_info.clear()
	if _chronicle_feed_label != null:
		_chronicle_feed_label.text = "• 본영 관아에서 아침 점호가 시작되었습니다.\n• 가신 진도가 둔전 농지 순시를 준비 중입니다."
	update_hero_banner({
		"name": "조자룡",
		"faction_name": "한실 신흥군",
		"rank_ko": "공작",
		"host_name": "허창",
		"troops": 300,
		"wall_hp": 2000,
		"storyteller_ko": "사마천"
	})
	_refresh_zone_inspector_for_selection()
	if _header_label != null:
		_header_label.text = "장원 [manor] · 32×32 · 요약(LOD 1) · 대기 중"
	if _resources_label != null:
		_resources_label.text = "자원: GRAIN: 0 | COIN: 0 | WOOD: 0 | IRON: 0 | HORSES: 0 | HERBS_WINE: 0 | WEAPONS: 0 | MERIT_PRESTIGE: 0"
	for rk: String in DtoSchemas.RESOURCE_KEYS:
		var rlbl_v: Variant = _resource_icon_labels.get(rk, null)
		if rlbl_v is Label:
			var rlbl: Label = rlbl_v
			rlbl.text = "%s:0" % rk
	if _grid_summary_label != null:
		_grid_summary_label.text = "32×32 격자 (1,024 타일)"
	if _zones_label != null:
		_zones_label.text = "8대 구역 요약: -"
	for bid: String in ManorState.BUILDING_IDS:
		var binfo: Dictionary = AssetRegistry.building_info_ko(bid)
		var bname: String = str(binfo.get("name", bid))
		var entry_v: Variant = _upgrade_buttons.get(bid, null)
		if entry_v is Dictionary:
			var entry: Dictionary = entry_v
			var lbl_v: Variant = entry.get("label", null)
			if lbl_v is Label:
				var lbl: Label = lbl_v
				lbl.text = "%s · Lv.1/5" % bname
			var cost_v: Variant = entry.get("cost_label", null)
			if cost_v is Label:
				var clbl: Label = cost_v
				clbl.text = "목재 120 · 은전 180"
			var btn_v: Variant = entry.get("button", null)
			if btn_v is Button:
				var btn: Button = btn_v
				btn.disabled = false
				btn.text = "증축"
	if _pawns_box != null:
		for child: Node in _pawns_box.get_children():
			_pawns_box.remove_child(child)
			child.queue_free()
	if _pawns_empty_label != null:
		_pawns_empty_label.visible = true
	if _grid_canvas != null:
		_grid_canvas.queue_redraw()
