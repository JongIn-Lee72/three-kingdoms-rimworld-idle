class_name ManorGridView
extends Control

signal intent_emitted(cmd_type: String, args: Dictionary)

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

var _selected_zone_id: String = ""
var _hover_tile: Vector2i = Vector2i(-1, -1)


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


func _make_card_panel(parent: Control, elevated: bool = false) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb: StyleBoxFlat = _assets.build_card_stylebox(elevated) if _assets != null else StyleBoxFlat.new()
	if _assets == null:
		sb.bg_color = AssetRegistry.COLOR_CARD_ELEVATED if elevated else AssetRegistry.COLOR_CARD_BG
		sb.border_color = AssetRegistry.COLOR_SUBTLE_BORDER
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 10.0
		sb.content_margin_right = 10.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", sb)
	var inner: VBoxContainer = VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	panel.add_child(inner)
	parent.add_child(panel)
	_card_panels.append(panel)
	return inner


func _build_ui() -> void:
	var outer: VBoxContainer = VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	# Top Compact KPI Strip (no duplicate resource lines; _resources_label kept hidden for test contract)
	var kpi_bar: VBoxContainer = _make_card_panel(outer, true)
	var kpi_row: HBoxContainer = HBoxContainer.new()
	kpi_row.add_theme_constant_override("separation", 12)
	kpi_bar.add_child(kpi_row)

	_header_label = Label.new()
	_header_label.text = "장원 [manor] · 32×32 · 실시간(LOD 1) · 대기 중"
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	AssetRegistry.apply_text_role(_header_label, "section")
	kpi_row.add_child(_header_label)

	_grid_summary_label = Label.new()
	_grid_summary_label.text = "32×32 격자 (1,024 타일)"
	AssetRegistry.apply_text_role(_grid_summary_label, "caption")
	kpi_row.add_child(_grid_summary_label)

	# Compatibility labels (hidden from screen to eliminate duplicate text clutter, kept synced for tests)
	_resources_label = Label.new()
	_resources_label.text = "자원: GRAIN: 0 | COIN: 0 | WOOD: 0 | IRON: 0 | HORSES: 0 | HERBS_WINE: 0 | WEAPONS: 0 | MERIT_PRESTIGE: 0"
	_resources_label.visible = false
	kpi_bar.add_child(_resources_label)

	_zones_label = Label.new()
	_zones_label.text = "8대 구역 요약: -"
	_zones_label.visible = false
	kpi_bar.add_child(_zones_label)

	_resource_icons_bar = HBoxContainer.new()
	_resource_icons_bar.visible = false
	for rk: String in DtoSchemas.RESOURCE_KEYS:
		var icon_rect: TextureRect = TextureRect.new()
		var rlbl: Label = Label.new()
		rlbl.text = "%s:0" % rk
		_resource_icons_bar.add_child(icon_rect)
		_resource_icons_bar.add_child(rlbl)
		_resource_icon_rects[rk] = icon_rect
		_resource_icon_labels[rk] = rlbl
	kpi_bar.add_child(_resource_icons_bar)

	# 2-Column HSplitContainer Dashboard
	var split: HSplitContainer = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.split_offset = 430
	outer.add_child(split)

	# LEFT COLUMN: Full Unclipped 32x32 Canvas + Hover Inspector + 8-Zone Legend Chips
	var left_col: VBoxContainer = VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(410, 0)
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 6)
	split.add_child(left_col)

	_grid_panel = PanelContainer.new()
	_grid_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_grid_canvas = Control.new()
	_grid_canvas.custom_minimum_size = Vector2(384, 384)
	_grid_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid_canvas.tooltip_text = "장원 32×32 타일 지도 — 마우스를 올려 타일·가신을 확인하고 클릭하여 구역을 강조하세요"
	_grid_canvas.draw.connect(_on_grid_canvas_draw)
	_grid_canvas.gui_input.connect(_on_grid_canvas_gui_input)
	_grid_canvas.mouse_exited.connect(_on_grid_canvas_mouse_exited)
	_grid_panel.add_child(_grid_canvas)
	left_col.add_child(_grid_panel)

	var insp_box: VBoxContainer = _make_card_panel(left_col, false)
	_tile_inspector_label = Label.new()
	_tile_inspector_label.text = "타일 점검: 32×32 격자에 마우스를 올리거나 아래 구역을 선택하세요"
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

	# RIGHT COLUMN: Scrollable 10 Buildings (2-col grid) + Retainer Cards + Quick Actions
	var right_scroll: ScrollContainer = ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right_scroll)

	var right_col: VBoxContainer = VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 8)
	right_scroll.add_child(right_col)

	# 10 Buildings Section (2-column compact cards)
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
	_buildings_grid.add_theme_constant_override("h_separation", 8)
	_buildings_grid.add_theme_constant_override("v_separation", 6)
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
		csb.content_margin_left = 8.0
		csb.content_margin_right = 8.0
		csb.content_margin_top = 5.0
		csb.content_margin_bottom = 5.0
		card_row.add_theme_stylebox_override("panel", csb)

		var hbox: HBoxContainer = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 6)
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
		cost_lbl.text = "비용: 목재 120 · 은전 180"
		AssetRegistry.apply_text_role(cost_lbl, "caption")
		info_col.add_child(cost_lbl)

		var btn: Button = Button.new()
		btn.text = "증축"
		btn.tooltip_text = "%s (%s) 증축" % [bname, bdesc]
		btn.pressed.connect(_on_upgrade_pressed.bind(bid))
		hbox.add_child(btn)

		_buildings_grid.add_child(card_row)
		_upgrade_buttons[bid] = {"label": lbl, "cost_label": cost_lbl, "button": btn, "card": card_row}

	# Pawns & Needs Card Section
	var pawn_sec: VBoxContainer = _make_card_panel(right_col, false)
	var pawn_title: Label = Label.new()
	pawn_title.text = "가신 현황 · 욕구 · 정신 상태"
	AssetRegistry.apply_text_role(pawn_title, "section")
	pawn_sec.add_child(pawn_title)

	_pawns_box = VBoxContainer.new()
	_pawns_box.add_theme_constant_override("separation", 6)
	pawn_sec.add_child(_pawns_box)

	_pawns_empty_label = Label.new()
	_pawns_empty_label.text = "배치된 가신이 없습니다. 4번 탭(장수 출사)에서 새 장수를 생성하거나 로컬 시연을 시작하세요."
	AssetRegistry.apply_text_role(_pawns_empty_label, "caption")
	pawn_sec.add_child(_pawns_empty_label)


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
		_tile_inspector_label.text = "타일 점검: 32×32 격자에 마우스를 올리거나 아래 구역을 선택하세요"

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
			var grid: Array[String] = _resolve_zone_grid()
			var zid: String = grid[gy * DtoSchemas.MANOR_GRID_SIZE + gx]
			_on_zone_chip_pressed(zid)


func _update_hover_inspector(gx: int, gy: int) -> void:
	if _tile_inspector_label == null:
		return
	var grid: Array[String] = _resolve_zone_grid()
	var zid: String = grid[gy * DtoSchemas.MANOR_GRID_SIZE + gx]
	var zinfo: Dictionary = AssetRegistry.zone_info_ko(zid)
	var pawn_here: String = ""
	var pawn_rows: Array[Dictionary] = _extract_pawn_rows(_last_snapshot)
	for pr: Dictionary in pawn_rows:
		var px: int = _to_int(pr.get("x", pr.get("grid_x", 16)), 16)
		var py: int = _to_int(pr.get("y", pr.get("grid_y", 16)), 16)
		if px == gx and py == gy:
			var pid: String = str(pr.get("pawn_id", "pawn"))
			var pname: String = "주군" if pid.ends_with("_avatar") else "가신"
			var pjob: String = AssetRegistry.job_ko(str(pr.get("job", "IDLE")))
			pawn_here = " · 배치: %s(%s)" % [pname, pjob]
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


func _on_grid_canvas_draw() -> void:
	if _grid_canvas == null:
		return
	var canvas_size: Vector2 = _grid_canvas.size
	if canvas_size.x <= 0.0 or canvas_size.y <= 0.0:
		canvas_size = _grid_canvas.custom_minimum_size
	var tile_w: float = canvas_size.x / float(DtoSchemas.MANOR_GRID_SIZE)
	var tile_h: float = canvas_size.y / float(DtoSchemas.MANOR_GRID_SIZE)

	_grid_canvas.draw_rect(Rect2(Vector2.ZERO, canvas_size), AssetRegistry.COLOR_LACQUER_BG)

	var zone_grid: Array[String] = _resolve_zone_grid()
	for gy: int in range(DtoSchemas.MANOR_GRID_SIZE):
		for gx: int in range(DtoSchemas.MANOR_GRID_SIZE):
			var ztype: String = zone_grid[gy * DtoSchemas.MANOR_GRID_SIZE + gx]
			var tile_rect: Rect2 = Rect2(
				float(gx) * tile_w,
				float(gy) * tile_h,
				tile_w,
				tile_h
			)
			if _assets != null:
				var tex: Texture2D = _assets.get_zone_tile(ztype)
				if tex != null:
					_grid_canvas.draw_texture_rect(tex, tile_rect, false)
			_grid_canvas.draw_rect(tile_rect, _zone_tint(ztype))
			if not _selected_zone_id.is_empty():
				if ztype == _selected_zone_id:
					_grid_canvas.draw_rect(tile_rect, AssetRegistry.COLOR_GOLD_HIGHLIGHT, false, 1.5)
				else:
					_grid_canvas.draw_rect(tile_rect, Color(0.05, 0.04, 0.03, 0.48))
			else:
				_grid_canvas.draw_rect(tile_rect, Color(0.08, 0.06, 0.05, 0.25), false, 1.0)

	if _hover_tile.x >= 0 and _hover_tile.y >= 0:
		var hrect: Rect2 = Rect2(
			float(_hover_tile.x) * tile_w,
			float(_hover_tile.y) * tile_h,
			tile_w,
			tile_h
		)
		_grid_canvas.draw_rect(hrect, AssetRegistry.COLOR_GOLD_HIGHLIGHT, false, 2.0)

	var meta_v: Variant = _last_snapshot.get("meta", {})
	var meta: Dictionary = meta_v if meta_v is Dictionary else {}
	var raid_active: bool = _to_bool(meta.get("raid_defense_active", _last_snapshot.get("raid_defense_active", false)), false)

	var pawn_rows: Array[Dictionary] = _extract_pawn_rows(_last_snapshot)
	for pr: Dictionary in pawn_rows:
		var pid: String = str(pr.get("pawn_id", "pawn"))
		var gx: int = clampi(_to_int(pr.get("x", pr.get("grid_x", 16)), 16), 0, DtoSchemas.MANOR_GRID_SIZE - 1)
		var gy: int = clampi(_to_int(pr.get("y", pr.get("grid_y", 16)), 16), 0, DtoSchemas.MANOR_GRID_SIZE - 1)
		var is_avatar: bool = _to_bool(pr.get("is_avatar", pid.ends_with("_avatar")), pid.ends_with("_avatar"))
		var job: String = str(pr.get("job", pr.get("current_job", "IDLE")))
		var role_hint: String = str(pr.get("role_hint", pr.get("epithet", job)))
		var mstate: String = str(pr.get("mental_state", "NORMAL"))

		var px: float = float(gx) * tile_w
		var py: float = float(gy) * tile_h
		var sprite_rect: Rect2 = Rect2(px - 2.0, py - 2.0, tile_w + 4.0, tile_h + 4.0)
		if _assets != null:
			var ptex: Texture2D = _assets.get_pawn_sprite(is_avatar, role_hint)
			if ptex != null:
				_grid_canvas.draw_texture_rect(ptex, sprite_rect, false)
			else:
				_grid_canvas.draw_rect(sprite_rect, AssetRegistry.COLOR_GOLD_HIGHLIGHT if is_avatar else AssetRegistry.COLOR_PARCHMENT_TEXT)
			var emote_tex: Texture2D = _assets.get_emote_texture(mstate, raid_active)
			if emote_tex != null:
				var emote_rect: Rect2 = Rect2(px, maxf(0.0, py - tile_h * 0.9), tile_w, tile_h * 0.85)
				_grid_canvas.draw_texture_rect(emote_tex, emote_rect, false)
		else:
			_grid_canvas.draw_rect(sprite_rect, AssetRegistry.COLOR_GOLD_HIGHLIGHT if is_avatar else AssetRegistry.COLOR_PARCHMENT_TEXT)


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
	pb.custom_minimum_size = Vector2(0, 7)
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
					clbl.text = "비용: 목재 %s · 은전 %s" % [AssetRegistry.format_num(cost_wood), AssetRegistry.format_num(cost_coin)]
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

		var pcard: PanelContainer = PanelContainer.new()
		pcard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var psb: StyleBoxFlat = StyleBoxFlat.new()
		psb.bg_color = Color(0.12, 0.10, 0.09, 0.94)
		psb.border_color = AssetRegistry.COLOR_GOLD_ACCENT if is_av else AssetRegistry.COLOR_SUBTLE_BORDER
		psb.set_border_width_all(1)
		psb.set_corner_radius_all(4)
		psb.content_margin_left = 8.0
		psb.content_margin_right = 8.0
		psb.content_margin_top = 6.0
		psb.content_margin_bottom = 6.0
		pcard.add_theme_stylebox_override("panel", psb)

		var pvbox: VBoxContainer = VBoxContainer.new()
		pvbox.add_theme_constant_override("separation", 4)
		pcard.add_child(pvbox)

		var header_r: HBoxContainer = HBoxContainer.new()
		header_r.add_theme_constant_override("separation", 6)
		pvbox.add_child(header_r)

		if _assets != null:
			var p_icon: TextureRect = TextureRect.new()
			p_icon.custom_minimum_size = Vector2(18, 18)
			p_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			p_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			p_icon.texture = _assets.get_pawn_sprite(is_av, job_raw)
			header_r.add_child(p_icon)

		var role_tag: String = "주군 아바타" if is_av else "서약 가신"
		var name_lbl: Label = Label.new()
		name_lbl.text = "%s (%s) · (%d,%d)" % [role_tag, pid, gx, gy]
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
				clbl.text = "비용: 목재 120 · 은전 180"
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
