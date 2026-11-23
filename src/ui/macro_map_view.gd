class_name MacroMapView
extends Control

signal intent_emitted(cmd_type: String, args: Dictionary)

var _assets: AssetRegistry = null
var _map_panel: PanelContainer = null
var _map_canvas: Control = null
var _section_panels_slate: Array[PanelContainer] = []
var _card_panels: Array[PanelContainer] = []
var _static_nodes: Dictionary = {}
var _static_edges: Array[Dictionary] = []

var _summary_label: Label = null
var _selected_node_detail_label: Label = null
var _nodes_box: VBoxContainer = null
var _armies_box: VBoxContainer = null
var _armies_empty_label: Label = null
var _rallies_box: VBoxContainer = null
var _rallies_empty_label: Label = null

var _target_node_opt: OptionButton = null
var _unit_type_opt: OptionButton = null
var _troop_spin: SpinBox = null
var _grain_spin: SpinBox = null
var _edge_path_edit: LineEdit = null
var _rally_id_edit: LineEdit = null
var _dispatch_btn: Button = null
var _create_rally_btn: Button = null
var _join_rally_btn: Button = null

var _cached_nodes: Dictionary = {}
var _cached_armies: Dictionary = {}
var _cached_rallies: Dictionary = {}
var _world_graph: WorldGraph = null
var _host_node_id: String = "xuchang"
var _selected_node_id: String = "luoyang"


const LEGACY_HOST_NODE_ALIASES: Dictionary = {
	"ye": "ye_county",
	"jixian": "jicheng",
	"puyang": "chenliu"
}


func _resolve_host_node_id(node_id: String) -> String:
	var clean: String = node_id.strip_edges()
	if clean.is_empty():
		return "xuchang"
	if _world_graph != null and _world_graph.has_node(clean):
		return clean
	if LEGACY_HOST_NODE_ALIASES.has(clean):
		var mapped: String = str(LEGACY_HOST_NODE_ALIASES[clean])
		if _world_graph == null or _world_graph.has_node(mapped):
			return mapped
	if _world_graph != null and not _world_graph.has_node(clean):
		return "xuchang"
	return clean


func set_host_node_id(node_id: String) -> void:
	if not node_id.is_empty():
		var resolved: String = _resolve_host_node_id(node_id)
		var host_changed: bool = (resolved != _host_node_id)
		_host_node_id = resolved
		var shifted_target: bool = false
		var cur_opt_nid: String = _get_selected_target_node_id()
		if _selected_node_id == _host_node_id or cur_opt_nid == _host_node_id:
			_selected_node_id = "luoyang" if _host_node_id != "luoyang" else "xuchang"
			shifted_target = true
		if (host_changed or shifted_target) and (is_inside_tree() or _map_canvas != null):
			_select_map_node(_selected_node_id, shifted_target)


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


static func _terrain_color(terrain_type: String) -> Color:
	match terrain_type:
		"HIGHWAY":
			return Color(0.86, 0.69, 0.34, 0.90)
		"MOUNTAIN_PATH":
			return Color(0.58, 0.42, 0.30, 0.90)
		"WATERWAY":
			return Color(0.32, 0.64, 0.78, 0.90)
		_:
			return Color(0.70, 0.65, 0.55, 0.85)


static func _faction_ring_color(faction_id: String) -> Color:
	var upper: String = faction_id.to_upper()
	if upper == "" or upper == "NEUTRAL":
		return Color(0.62, 0.60, 0.54, 0.95)
	if upper.contains("YELLOW") or upper.contains("TURBAN"):
		return Color(0.92, 0.78, 0.24, 0.98)
	if upper.contains("WEI") or upper.contains("CAO"):
		return Color(0.28, 0.54, 0.94, 0.98)
	if upper.contains("SHU") or upper.contains("LIU"):
		return Color(0.24, 0.78, 0.48, 0.98)
	if upper.contains("WU") or upper.contains("SUN"):
		return Color(0.86, 0.28, 0.26, 0.98)
	if upper.contains("HAN"):
		return Color(0.95, 0.78, 0.30, 0.98)
	return AssetRegistry.COLOR_GOLD_HIGHLIGHT


static func _faction_halo_color(faction_id: String) -> Color:
	var upper: String = faction_id.to_upper()
	if upper == "" or upper == "NEUTRAL":
		return Color(0.55, 0.52, 0.46, 0.10)
	var base_c: Color = _faction_ring_color(faction_id)
	return Color(base_c.r, base_c.g, base_c.b, 0.18)


static func _faction_short_ko(faction_id: String) -> String:
	match faction_id:
		"", "NEUTRAL":
			return "중립"
		"fac_han":
			return "한실군"
		"fac_wei":
			return "위군"
		"fac_shu":
			return "촉군"
		"fac_wu":
			return "오군"
		_:
			return AssetRegistry.faction_name_ko(faction_id)


static func _node_label_offset(node_id: String, radius: float) -> Vector2:
	match node_id:
		"ye_county":
			return Vector2(-38.0, -radius - 6.0)
		"ye_city":
			return Vector2(14.0, 5.0)
		"luoyang":
			return Vector2(-38.0, -radius - 6.0)
		"hulao_pass":
			return Vector2(-46.0, radius + 12.0)
		"changan":
			return Vector2(-18.0, -radius - 7.0)
		"tong_pass":
			return Vector2(-14.0, radius + 14.0)
		"chenliu":
			return Vector2(12.0, -radius - 4.0)
		"xuchang":
			return Vector2(-18.0, radius + 16.0)
		_:
			return Vector2(-18.0, radius + 14.0)


func _init() -> void:
	name = "MacroMapView"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_static_map_geometry()
	_build_ui()


func set_asset_registry(reg: AssetRegistry) -> void:
	_assets = reg
	if _assets == null:
		return
	if _map_panel != null:
		_map_panel.add_theme_stylebox_override("panel", _assets.build_card_stylebox(true, AssetRegistry.COLOR_GOLD_ACCENT))
	var card_sb: StyleBoxFlat = _assets.build_card_stylebox(false, AssetRegistry.COLOR_SUBTLE_BORDER)
	for p_card: PanelContainer in _card_panels:
		if p_card != null:
			p_card.add_theme_stylebox_override("panel", card_sb)
	if _dispatch_btn != null:
		_assets.apply_button_variant(_dispatch_btn, "primary")
	if _create_rally_btn != null:
		_assets.apply_button_variant(_create_rally_btn, "secondary")
	if _join_rally_btn != null:
		_assets.apply_button_variant(_join_rally_btn, "secondary")
	if _map_canvas != null:
		_map_canvas.queue_redraw()


func get_map_canvas_node() -> Control:
	return _map_canvas


func get_static_edge_count() -> int:
	return _static_edges.size()


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
	_card_panels.append(panel)
	return inner


func _load_static_map_geometry(path: String = "res://data/macro_map_3k.json") -> void:
	_static_nodes.clear()
	_static_edges.clear()
	if not FileAccess.file_exists(path):
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f.close()
	if txt.strip_edges().is_empty():
		return
	var parser: JSON = JSON.new()
	if parser.parse(txt) != OK:
		return
	var norm: Variant = DtoSchemas.normalize_json_ints(parser.data)
	if not (norm is Dictionary):
		return
	var root_d: Dictionary = norm
	var nodes_v: Variant = root_d.get("nodes", [])
	if nodes_v is Array:
		var nodes_a: Array = nodes_v
		for nv: Variant in nodes_a:
			if nv is Dictionary:
				var nd: Dictionary = nv
				var nid: String = str(nd.get("node_id", ""))
				if not nid.is_empty():
					_static_nodes[nid] = nd.duplicate(true)
	var edges_v: Variant = root_d.get("edges", [])
	if edges_v is Array:
		var edges_a: Array = edges_v
		for ev: Variant in edges_a:
			if ev is Dictionary:
				var ed: Dictionary = ev
				_static_edges.append(ed.duplicate(true))


func _build_ui() -> void:
	var outer: VBoxContainer = VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	# Top Summary + Map Legend Strip
	var hdr_box: VBoxContainer = _make_card_panel(outer, true, AssetRegistry.COLOR_GOLD_ACCENT)
	var hdr_row: HBoxContainer = HBoxContainer.new()
	hdr_row.add_theme_constant_override("separation", 12)
	hdr_box.add_child(hdr_row)

	_summary_label = Label.new()
	_summary_label.text = "천하 전략도 (15개 거점) · 군단/상단 0 · 연합 집결 0"
	_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	AssetRegistry.apply_text_role(_summary_label, "section")
	hdr_row.add_child(_summary_label)

	var legend_lbl: Label = Label.new()
	legend_lbl.text = "도로: 황금(가도) · 갈색(산길) · 청색(수운) | 세력: 청(위) · 녹(촉) · 적(오) · 황금(한실)"
	AssetRegistry.apply_text_role(legend_lbl, "caption")
	hdr_row.add_child(legend_lbl)

	# 2-Column HSplitContainer Dashboard
	var split: HSplitContainer = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.split_offset = 660
	outer.add_child(split)

	# LEFT COLUMN: Interactive Parchment Map + Selected Node Detail Card
	var left_col: VBoxContainer = VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(560, 0)
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 6)
	split.add_child(left_col)

	_map_panel = PanelContainer.new()
	_map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_canvas = Control.new()
	_map_canvas.custom_minimum_size = Vector2(560, 380)
	_map_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_canvas.tooltip_text = "천하 전략도 — 거점을 클릭하면 목표 거점으로 자동 지정되고 최단 경로가 계산됩니다"
	_map_canvas.draw.connect(_on_map_canvas_draw)
	_map_canvas.gui_input.connect(_on_map_canvas_gui_input)
	_map_panel.add_child(_map_canvas)
	left_col.add_child(_map_panel)

	var detail_card: VBoxContainer = _make_card_panel(left_col, false)
	_selected_node_detail_label = Label.new()
	_selected_node_detail_label.text = "선택 거점: 낙양 (옹양주) — 지도에서 거점을 클릭해 출진 목표를 선택하세요"
	_selected_node_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	AssetRegistry.apply_text_role(_selected_node_detail_label, "muted")
	detail_card.add_child(_selected_node_detail_label)

	# RIGHT COLUMN: Scrollable Expedition/Rally Command Panel (top!) + Armies + Rallies + Nodes
	var right_scroll: ScrollContainer = ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right_scroll)

	var right_col: VBoxContainer = VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 8)
	right_scroll.add_child(right_col)

	# 1. Expedition & Coalition Rally Command Console (immediately visible above the fold)
	var ctrl_sec: VBoxContainer = _make_card_panel(right_col, true, AssetRegistry.COLOR_GOLD_ACCENT)
	var ctrl_hdr: Label = Label.new()
	ctrl_hdr.text = "출진 · 상단 파견 및 연합 공성 명령"
	AssetRegistry.apply_text_role(ctrl_hdr, "section")
	ctrl_sec.add_child(ctrl_hdr)

	var row1: HBoxContainer = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	var tgt_lbl: Label = Label.new()
	tgt_lbl.text = "목표 거점:"
	AssetRegistry.apply_text_role(tgt_lbl, "muted")
	row1.add_child(tgt_lbl)
	_target_node_opt = OptionButton.new()
	_target_node_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_node_opt.item_selected.connect(_on_target_node_opt_selected)
	row1.add_child(_target_node_opt)

	var ut_lbl: Label = Label.new()
	ut_lbl.text = "유형:"
	AssetRegistry.apply_text_role(ut_lbl, "muted")
	row1.add_child(ut_lbl)
	_unit_type_opt = OptionButton.new()
	_unit_type_opt.add_item("정규 군단")
	_unit_type_opt.set_item_metadata(0, "ARMY")
	_unit_type_opt.add_item("무역 상단")
	_unit_type_opt.set_item_metadata(1, "CARAVAN")
	row1.add_child(_unit_type_opt)
	ctrl_sec.add_child(row1)

	var row2: HBoxContainer = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	var tr_lbl: Label = Label.new()
	tr_lbl.text = "병력 수:"
	AssetRegistry.apply_text_role(tr_lbl, "muted")
	row2.add_child(tr_lbl)
	_troop_spin = SpinBox.new()
	_troop_spin.min_value = 1
	_troop_spin.max_value = 3000
	_troop_spin.value = 100
	_troop_spin.custom_minimum_size = Vector2(96, 0)
	row2.add_child(_troop_spin)

	var gr_lbl: Label = Label.new()
	gr_lbl.text = "휴대 군량:"
	AssetRegistry.apply_text_role(gr_lbl, "muted")
	row2.add_child(gr_lbl)
	_grain_spin = SpinBox.new()
	_grain_spin.min_value = 0
	_grain_spin.max_value = 50000
	_grain_spin.value = 200
	_grain_spin.custom_minimum_size = Vector2(104, 0)
	row2.add_child(_grain_spin)
	ctrl_sec.add_child(row2)

	var row3: HBoxContainer = HBoxContainer.new()
	row3.add_theme_constant_override("separation", 6)
	var path_lbl: Label = Label.new()
	path_lbl.text = "행군 경로:"
	AssetRegistry.apply_text_role(path_lbl, "muted")
	row3.add_child(path_lbl)
	_edge_path_edit = LineEdit.new()
	_edge_path_edit.placeholder_text = "비워두면 최단 경로 자동 탐색"
	_edge_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(_edge_path_edit)

	_dispatch_btn = Button.new()
	_dispatch_btn.text = "군단·상단 출진"
	_dispatch_btn.tooltip_text = "선택한 거점으로 군단 또는 무역 상단을 출진시킵니다"
	_dispatch_btn.pressed.connect(_on_dispatch_pressed)
	row3.add_child(_dispatch_btn)
	ctrl_sec.add_child(row3)

	var row4: HBoxContainer = HBoxContainer.new()
	row4.add_theme_constant_override("separation", 6)
	_create_rally_btn = Button.new()
	_create_rally_btn.text = "연합 집결 발령"
	_create_rally_btn.tooltip_text = "목표 거점 공성을 위한 동맹 연합 집결을 선포합니다"
	_create_rally_btn.pressed.connect(_on_create_rally_pressed)
	row4.add_child(_create_rally_btn)

	var rally_lbl: Label = Label.new()
	rally_lbl.text = "집결 번호:"
	AssetRegistry.apply_text_role(rally_lbl, "caption")
	row4.add_child(rally_lbl)

	_rally_id_edit = LineEdit.new()
	_rally_id_edit.placeholder_text = "연합 집결 번호 입력"
	_rally_id_edit.custom_minimum_size = Vector2(115, 0)
	_rally_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row4.add_child(_rally_id_edit)

	_join_rally_btn = Button.new()
	_join_rally_btn.text = "집결 합류"
	_join_rally_btn.pressed.connect(_on_join_rally_pressed)
	row4.add_child(_join_rally_btn)
	ctrl_sec.add_child(row4)

	# 2. Active Armies & Caravans (external empty-state label so _armies_box.get_child_count() == _cached_armies.size())
	var armies_sec: VBoxContainer = _make_card_panel(right_col, false)
	var armies_hdr: Label = Label.new()
	armies_hdr.text = "출진 군단 및 무역 상단"
	AssetRegistry.apply_text_role(armies_hdr, "section")
	armies_sec.add_child(armies_hdr)

	_armies_box = VBoxContainer.new()
	_armies_box.add_theme_constant_override("separation", 4)
	armies_sec.add_child(_armies_box)

	_armies_empty_label = Label.new()
	_armies_empty_label.text = "현재 이동 중인 군단이나 상단이 없습니다. 위에서 목표 거점을 골라 출진하세요."
	AssetRegistry.apply_text_role(_armies_empty_label, "caption")
	armies_sec.add_child(_armies_empty_label)

	# 3. Coalition Sieges
	var rallies_sec: VBoxContainer = _make_card_panel(right_col, false)
	var rallies_hdr: Label = Label.new()
	rallies_hdr.text = "연합 공성전 집결 현황"
	AssetRegistry.apply_text_role(rallies_hdr, "section")
	rallies_sec.add_child(rallies_hdr)

	_rallies_box = VBoxContainer.new()
	_rallies_box.add_theme_constant_override("separation", 4)
	rallies_sec.add_child(_rallies_box)

	_rallies_empty_label = Label.new()
	_rallies_empty_label.text = "진행 중인 연합 공성 집결이 없습니다. 군주·태수는 위에서 집결을 발령할 수 있습니다."
	AssetRegistry.apply_text_role(_rallies_empty_label, "caption")
	rallies_sec.add_child(_rallies_empty_label)

	# 4. All 15 Nodes Status
	var nodes_sec: VBoxContainer = _make_card_panel(right_col, false)
	var nodes_hdr: Label = Label.new()
	nodes_hdr.text = "15개 거점 현황 (주 · 세력 · 성벽 · 치안)"
	AssetRegistry.apply_text_role(nodes_hdr, "section")
	nodes_sec.add_child(nodes_hdr)

	_nodes_box = VBoxContainer.new()
	_nodes_box.add_theme_constant_override("separation", 3)
	nodes_sec.add_child(_nodes_box)

	_load_default_nodes_preview()


func _load_default_nodes_preview() -> void:
	_world_graph = WorldGraph.new({}, true)
	var init_nodes: Dictionary = {}
	for nid: String in _world_graph.get_node_ids():
		init_nodes[nid] = _world_graph.get_node(nid)
	apply_snapshot({"nodes": init_nodes})


func _node_screen_pos(node_id: String, canvas_size: Vector2) -> Vector2:
	var nd: Dictionary = {}
	if _cached_nodes.has(node_id) and _cached_nodes[node_id] is Dictionary:
		nd = _cached_nodes[node_id]
	var st: Dictionary = {}
	if _static_nodes.has(node_id) and _static_nodes[node_id] is Dictionary:
		st = _static_nodes[node_id]
	var nx: int = _to_int(nd.get("x", st.get("x", 500)), 500)
	var ny: int = _to_int(nd.get("y", st.get("y", 500)), 500)
	var pad_x: float = 34.0
	var pad_y: float = 28.0
	var usable_w: float = maxf(64.0, canvas_size.x - pad_x * 2.0)
	var usable_h: float = maxf(64.0, canvas_size.y - pad_y * 2.0)
	return Vector2(
		pad_x + (float(nx) / 1000.0) * usable_w,
		pad_y + (float(ny) / 1000.0) * usable_h
	)


func _on_map_canvas_gui_input(event: InputEvent) -> void:
	if _map_canvas == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var csize: Vector2 = _map_canvas.size
			if csize.x <= 0.0 or csize.y <= 0.0:
				return
			var best_nid: String = ""
			var best_dist: float = 28.0
			for nid_v: Variant in _static_nodes.keys():
				var nid: String = str(nid_v)
				var pos: Vector2 = _node_screen_pos(nid, csize)
				var d: float = pos.distance_to(mb.position)
				if d < best_dist:
					best_dist = d
					best_nid = nid
			if not best_nid.is_empty():
				_select_map_node(best_nid)


func _on_target_node_opt_selected(idx: int) -> void:
	if _target_node_opt == null or idx < 0 or idx >= _target_node_opt.item_count:
		return
	var md: Variant = _target_node_opt.get_item_metadata(idx)
	var nid: String = str(md) if md is String and not str(md).is_empty() else _target_node_opt.get_item_text(idx)
	if not nid.is_empty():
		_select_map_node(nid, false)


func _select_map_node(nid: String, sync_dropdown: bool = true) -> void:
	_selected_node_id = nid
	if sync_dropdown and _target_node_opt != null:
		for i: int in range(_target_node_opt.item_count):
			var md: Variant = _target_node_opt.get_item_metadata(i)
			if (md is String and str(md) == nid) or _target_node_opt.get_item_text(i) == nid:
				_target_node_opt.select(i)
				break
	if _edge_path_edit != null and _world_graph != null and not nid.is_empty():
		var auto_path: Array[String] = _world_graph.find_path(_host_node_id, nid)
		_edge_path_edit.text = ",".join(PackedStringArray(auto_path))
	_update_selected_node_detail()
	if _map_canvas != null:
		_map_canvas.queue_redraw()


func _update_selected_node_detail() -> void:
	if _selected_node_detail_label == null:
		return
	var nd: Dictionary = _cached_nodes.get(_selected_node_id, _static_nodes.get(_selected_node_id, {}))
	if nd.is_empty():
		return
	var name_ko: String = str(nd.get("name_ko", AssetRegistry.node_name_ko(_selected_node_id)))
	var prov: String = str(nd.get("province", "-"))
	var owner_fid: String = str(nd.get("owner_faction_id", "NEUTRAL"))
	var owner_ko: String = AssetRegistry.faction_name_ko(owner_fid)
	var fort_hp: int = _to_int(nd.get("fortification_hp", 0), 0)
	var sec_pct: float = float(_to_int(nd.get("security_bp", 7000), 7000)) / 100.0
	_selected_node_detail_label.text = "선택 거점: %s (%s) | 점령: %s | 성벽 %s | 치안 %.1f%% | 내 장원: ★ %s" % [
		name_ko, prov, owner_ko, AssetRegistry.format_num(fort_hp), sec_pct, AssetRegistry.node_name_ko(_host_node_id)
	]


func _draw_province_watermarks(canvas_size: Vector2, font: Font) -> void:
	if _map_canvas == null or font == null:
		return
	var pad_x: float = 34.0
	var pad_y: float = 28.0
	var usable_w: float = maxf(64.0, canvas_size.x - pad_x * 2.0)
	var usable_h: float = maxf(64.0, canvas_size.y - pad_y * 2.0)
	var regions: Array[Dictionary] = [
		{"nx": 465, "ny": 230, "label": "기주 (하북)"},
		{"nx": 165, "ny": 395, "label": "옹양주 (관중)"},
		{"nx": 575, "ny": 670, "label": "중원 (예·연주)"},
		{"nx": 755, "ny": 430, "label": "서주"},
		{"nx": 345, "ny": 730, "label": "형주"},
		{"nx": 130, "ny": 885, "label": "익주 (촉)"},
		{"nx": 795, "ny": 725, "label": "강동 (양주)"}
	]
	var ink_col: Color = Color(0.24, 0.16, 0.09, 0.48)
	for reg: Dictionary in regions:
		var nx_i: int = _to_int(reg.get("nx", 500), 500)
		var ny_i: int = _to_int(reg.get("ny", 500), 500)
		var rx: float = pad_x + (float(nx_i) / 1000.0) * usable_w
		var ry: float = pad_y + (float(ny_i) / 1000.0) * usable_h
		var rtxt: String = str(reg["label"])
		_map_canvas.draw_string(
			font,
			Vector2(rx, ry),
			rtxt,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			ink_col
		)


func _on_map_canvas_draw() -> void:
	if _map_canvas == null:
		return
	var canvas_size: Vector2 = _map_canvas.size
	if canvas_size.x <= 0.0 or canvas_size.y <= 0.0:
		canvas_size = _map_canvas.custom_minimum_size
	var canvas_rect: Rect2 = Rect2(Vector2.ZERO, canvas_size)
	_map_canvas.draw_rect(canvas_rect, AssetRegistry.COLOR_LACQUER_BG)

	if _assets != null:
		var map_bg: Texture2D = _assets.get_texture(AssetRegistry.MAP_BG)
		if map_bg != null:
			_map_canvas.draw_texture_rect(map_bg, canvas_rect, false)
		_map_canvas.draw_rect(canvas_rect, Color(0.08, 0.06, 0.05, 0.22))

	var font: Font = _assets.get_ui_font() if _assets != null else ThemeDB.fallback_font
	if font == null:
		font = ThemeDB.fallback_font

	# 1. Subtle Province Region Watermarks
	_draw_province_watermarks(canvas_size, font)

	var node_ids: Array[String] = []
	for k: Variant in _static_nodes.keys():
		node_ids.append(str(k))
	for ck: Variant in _cached_nodes.keys():
		var cks: String = str(ck)
		if not node_ids.has(cks):
			node_ids.append(cks)
	node_ids.sort()

	# 2. Faction Territory Influence Halos behind owned cities
	for nid: String in node_ids:
		var nd: Dictionary = _cached_nodes[nid] if _cached_nodes.has(nid) and _cached_nodes[nid] is Dictionary else {}
		var st: Dictionary = _static_nodes[nid] if _static_nodes.has(nid) and _static_nodes[nid] is Dictionary else {}
		var owner_fid: String = str(nd.get("owner_faction_id", st.get("owner_faction_id", "NEUTRAL")))
		if owner_fid.is_empty() or owner_fid == "NEUTRAL":
			continue
		var pos: Vector2 = _node_screen_pos(nid, canvas_size)
		var tier: String = str(nd.get("node_tier", st.get("node_tier", "COUNTY")))
		var halo_r: float = 46.0 if tier == "CAPITAL" else (42.0 if tier == "CITY" else 34.0)
		_map_canvas.draw_circle(pos, halo_r, _faction_halo_color(owner_fid))

	# 3. Roads / Waterways / Mountain Passes
	for ed: Dictionary in _static_edges:
		var from_id: String = str(ed.get("from_node", ""))
		var to_id: String = str(ed.get("to_node", ""))
		if from_id.is_empty() or to_id.is_empty():
			continue
		var p1: Vector2 = _node_screen_pos(from_id, canvas_size)
		var p2: Vector2 = _node_screen_pos(to_id, canvas_size)
		var terrain: String = str(ed.get("terrain_type", "HIGHWAY"))
		_map_canvas.draw_line(p1, p2, _terrain_color(terrain), 2.5, true)

	# 4. City Nodes + Tier Distinction + ★ 내 장원 Highlight + Zero-Overlap Labels
	for nid: String in node_ids:
		var nd: Dictionary = _cached_nodes[nid] if _cached_nodes.has(nid) and _cached_nodes[nid] is Dictionary else {}
		var st: Dictionary = _static_nodes[nid] if _static_nodes.has(nid) and _static_nodes[nid] is Dictionary else {}
		var pos: Vector2 = _node_screen_pos(nid, canvas_size)
		var tier: String = str(nd.get("node_tier", st.get("node_tier", "COUNTY")))
		var owner_fid: String = str(nd.get("owner_faction_id", st.get("owner_faction_id", "NEUTRAL")))
		var name_ko: String = str(nd.get("name_ko", st.get("name_ko", AssetRegistry.node_name_ko(nid))))
		var radius: float = 15.0 if tier == "CAPITAL" else (12.0 if tier == "CITY" or tier == "PASS" else 9.0)
		var ring_col: Color = _faction_ring_color(owner_fid)

		if nid == _host_node_id:
			_map_canvas.draw_arc(pos, radius + 9.0, 0.0, TAU, 32, Color(0.98, 0.84, 0.34, 0.95), 2.2, true)

		if nid == _selected_node_id:
			_map_canvas.draw_arc(pos, radius + 6.0, 0.0, TAU, 28, AssetRegistry.COLOR_GOLD_HIGHLIGHT, 2.5, true)

		_map_canvas.draw_circle(pos, radius + 2.0, Color(0.08, 0.06, 0.05, 0.90))
		_map_canvas.draw_arc(pos, radius + 2.0, 0.0, TAU, 24, ring_col, 2.8 if tier == "CAPITAL" else 2.2, true)

		var icon_rect: Rect2 = Rect2(pos - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0))
		if _assets != null:
			var ntex: Texture2D = _assets.get_macro_node_icon(tier)
			if ntex != null:
				_map_canvas.draw_texture_rect(ntex, icon_rect, false)
			else:
				_map_canvas.draw_circle(pos, radius, ring_col)
		else:
			_map_canvas.draw_circle(pos, radius, ring_col)

		if font != null:
			var loff: Vector2 = _node_label_offset(nid, radius)
			var txt_pos: Vector2 = pos + loff
			var label_str: String = name_ko
			if tier == "CAPITAL":
				label_str = "◆ " + name_ko
			var pill_w: float = float(label_str.length() * 11 + 10)
			var pill_rect: Rect2 = Rect2(txt_pos.x - 4.0, txt_pos.y - 11.0, pill_w, 15.0)
			_map_canvas.draw_rect(pill_rect, Color(0.08, 0.06, 0.05, 0.84))
			_map_canvas.draw_rect(pill_rect, ring_col if nid == _selected_node_id else Color(0.38, 0.30, 0.20, 0.80), false, 1.0)
			_map_canvas.draw_string(
				font,
				txt_pos,
				label_str,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				11,
				AssetRegistry.COLOR_GOLD_HIGHLIGHT if nid == _selected_node_id else AssetRegistry.COLOR_TEXT_PRIMARY
			)

			if nid == _host_node_id:
				var home_txt: String = "★ 내 장원"
				var home_pos: Vector2 = pos + Vector2(-28.0, -radius - 14.0)
				var home_rect: Rect2 = Rect2(home_pos.x - 4.0, home_pos.y - 11.0, 66.0, 15.0)
				_map_canvas.draw_rect(home_rect, Color(0.24, 0.16, 0.04, 0.94))
				_map_canvas.draw_rect(home_rect, AssetRegistry.COLOR_GOLD_HIGHLIGHT, false, 1.2)
				_map_canvas.draw_string(
					font,
					home_pos,
					home_txt,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					10,
					AssetRegistry.COLOR_GOLD_HIGHLIGHT
				)

	# 5. Live Armies & Caravans + Sleek Miniature Callout Badges
	var army_ids: Array[String] = []
	for ak: Variant in _cached_armies.keys():
		army_ids.append(str(ak))
	army_ids.sort()
	for idx: int in range(army_ids.size()):
		var eid: String = army_ids[idx]
		var ent_v: Variant = _cached_armies.get(eid, null)
		if not (ent_v is Dictionary):
			continue
		var ent: Dictionary = ent_v
		var cur_nid: String = str(ent.get("current_node_id", ""))
		if cur_nid.is_empty():
			continue
		var base_pos: Vector2 = _node_screen_pos(cur_nid, canvas_size)
		var offset: Vector2 = Vector2(16.0 + float((idx % 3) * 14), -16.0 - float((idx / 3) * 14))
		var apos: Vector2 = base_pos + offset
		var utype: String = str(ent.get("unit_type", "ARMY"))
		var afid: String = str(ent.get("faction_id", "NEUTRAL"))
		var acol: Color = _faction_ring_color(afid)
		var arect: Rect2 = Rect2(apos - Vector2(9.0, 9.0), Vector2(18.0, 18.0))
		_map_canvas.draw_circle(apos, 10.0, Color(0.08, 0.06, 0.05, 0.85))
		_map_canvas.draw_arc(apos, 10.0, 0.0, TAU, 18, acol, 1.5, true)
		if _assets != null:
			var atex: Texture2D = _assets.get_army_icon(utype)
			if atex != null:
				_map_canvas.draw_texture_rect(atex, arect, false)
			else:
				_map_canvas.draw_rect(arect, acol)
		else:
			_map_canvas.draw_rect(arect, acol)

		if font != null:
			var troops_i: int = _to_int(ent.get("troop_count", 0), 0)
			var fshort: String = _faction_short_ko(afid)
			var badge_txt: String = "%s 상단" % fshort if utype == "CARAVAN" else "%s %d" % [fshort, troops_i]
			var bpos: Vector2 = apos + Vector2(12.0, 4.0)
			var bw: float = float(badge_txt.length() * 8 + 10)
			var brect: Rect2 = Rect2(bpos.x - 3.0, bpos.y - 10.0, bw, 13.0)
			_map_canvas.draw_rect(brect, Color(0.09, 0.07, 0.06, 0.88))
			_map_canvas.draw_rect(brect, acol, false, 1.0)
			_map_canvas.draw_string(font, bpos, badge_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, acol)


func _get_selected_target_node_id() -> String:
	if _target_node_opt == null or _target_node_opt.selected < 0 or _target_node_opt.selected >= _target_node_opt.item_count:
		return ""
	var md: Variant = _target_node_opt.get_item_metadata(_target_node_opt.selected)
	if md is String and not str(md).is_empty():
		return str(md)
	return _target_node_opt.get_item_text(_target_node_opt.selected)


func _get_selected_unit_type() -> String:
	if _unit_type_opt == null or _unit_type_opt.selected < 0:
		return "ARMY"
	var md: Variant = _unit_type_opt.get_item_metadata(_unit_type_opt.selected)
	if md is String and not str(md).is_empty():
		return str(md)
	return _unit_type_opt.get_item_text(_unit_type_opt.selected)


func _is_path_connected(from_nid: String, to_nid: String, edge_ids: Array[String]) -> bool:
	if _world_graph == null or edge_ids.is_empty():
		return false
	var cur: String = from_nid
	for eid: String in edge_ids:
		if not _world_graph.has_edge(eid):
			return false
		var nxt: String = _world_graph.get_other_endpoint(eid, cur)
		if nxt.is_empty():
			return false
		cur = nxt
	return cur == to_nid


func _on_dispatch_pressed() -> void:
	var target_nid: String = _get_selected_target_node_id()
	var unit_t: String = _get_selected_unit_type()
	var edges: Array[String] = []
	var raw_path: String = _edge_path_edit.text.strip_edges()
	if not raw_path.is_empty():
		for part: String in raw_path.split(",", false):
			var clean_e: String = part.strip_edges()
			if not clean_e.is_empty():
				edges.append(clean_e)
	if (edges.is_empty() or not _is_path_connected(_host_node_id, target_nid, edges)) and _world_graph != null and not target_nid.is_empty():
		edges.clear()
		var auto_path: Array[String] = _world_graph.find_path(_host_node_id, target_nid)
		for eid: String in auto_path:
			edges.append(eid)
		if not edges.is_empty():
			_edge_path_edit.text = ",".join(PackedStringArray(edges))
	emit_dispatch_expedition(
		target_nid,
		edges,
		int(_troop_spin.value),
		int(_grain_spin.value),
		unit_t
	)


func emit_dispatch_expedition(
	target_node_id: String,
	path_edge_ids: Array[String],
	troop_count: int,
	carried_grain: int,
	unit_type: String = "ARMY",
	officer_ids: Array[String] = [],
	cargo: Dictionary = {}
) -> void:
	intent_emitted.emit("CMD_DISPATCH_EXPEDITION", {
		"target_node_id": target_node_id,
		"path_edge_ids": path_edge_ids,
		"troop_count": maxi(1, troop_count),
		"carried_grain": maxi(0, carried_grain),
		"unit_type": unit_type,
		"officer_ids": officer_ids,
		"cargo": cargo
	})


func _on_create_rally_pressed() -> void:
	var target_nid: String = _get_selected_target_node_id()
	emit_create_coalition_rally(target_nid, int(_troop_spin.value), 8500)


func emit_create_coalition_rally(target_node_id: String, troop_count: int, morale_bp: int = 8500) -> void:
	intent_emitted.emit("CMD_CREATE_COALITION_RALLY", {
		"target_node_id": target_node_id,
		"troop_count": maxi(1, troop_count),
		"morale_bp": clampi(morale_bp, 1000, 10000)
	})


func _on_join_rally_pressed() -> void:
	emit_join_coalition_rally(_rally_id_edit.text.strip_edges(), int(_troop_spin.value), 8500)


func emit_join_coalition_rally(rally_id: String, troop_count: int, morale_bp: int = 8500) -> void:
	intent_emitted.emit("CMD_JOIN_COALITION_RALLY", {
		"rally_id": rally_id,
		"troop_count": maxi(1, troop_count),
		"morale_bp": clampi(morale_bp, 1000, 10000)
	})


func apply_snapshot(snapshot: Dictionary) -> void:
	var nodes_v: Variant = snapshot.get("nodes", null)
	if nodes_v is Dictionary:
		var nd_map: Dictionary = nodes_v
		for k: Variant in nd_map.keys():
			var nid: String = str(k)
			var val_v: Variant = nd_map[k]
			if val_v is Dictionary:
				var val_d: Dictionary = val_v
				var prev_v: Variant = _cached_nodes.get(nid, {})
				var merged: Dictionary = {}
				if prev_v is Dictionary:
					var prev_nd: Dictionary = prev_v
					merged = prev_nd.duplicate(true)
				for fk: Variant in val_d.keys():
					merged[str(fk)] = val_d[fk]
				merged["node_id"] = nid
				_cached_nodes[nid] = merged

	if snapshot.has("armies"):
		var armies_v: Variant = snapshot.get("armies", {})
		if armies_v is Dictionary:
			var ad: Dictionary = armies_v
			for k: Variant in ad.keys():
				var eid: String = str(k)
				var av: Variant = ad[k]
				if av is Dictionary:
					var ad_item: Dictionary = av
					var prev_a: Variant = _cached_armies.get(eid, {})
					var merged_a: Dictionary = {}
					if prev_a is Dictionary:
						var prev_ad: Dictionary = prev_a
						merged_a = prev_ad.duplicate(true)
					for fk: Variant in ad_item.keys():
						merged_a[str(fk)] = ad_item[fk]
					_cached_armies[eid] = merged_a

	if snapshot.has("deleted_armies") and snapshot["deleted_armies"] is Array:
		var del_a: Array = snapshot["deleted_armies"]
		for did: Variant in del_a:
			var _er: bool = _cached_armies.erase(str(did))

	if snapshot.has("rallies") and snapshot["rallies"] is Dictionary:
		var rmap: Dictionary = snapshot["rallies"]
		for k: Variant in rmap.keys():
			var rid: String = str(k)
			var rv: Variant = rmap[k]
			if rv is Dictionary:
				var rdict: Dictionary = rv
				_cached_rallies[rid] = rdict.duplicate(true)

	_redraw_lists()


func _format_army_entry_ko(ent: Dictionary) -> String:
	var ut_raw: String = str(ent.get("unit_type", "ARMY"))
	var ut_ko: String = AssetRegistry.unit_type_ko(ut_raw)
	var fac_ko: String = AssetRegistry.faction_name_ko(str(ent.get("faction_id", "NEUTRAL")))
	var cur_nid: String = str(ent.get("current_node_id", ""))
	var loc_ko: String = AssetRegistry.node_name_ko(cur_nid)
	var st_raw: String = str(ent.get("status", "MARCHING"))
	var st_ko: String = AssetRegistry.unit_type_ko(st_raw)
	var troops_str: String = AssetRegistry.format_num(_to_int(ent.get("troop_count", 0), 0))
	var morale_pct: float = float(_to_int(ent.get("morale_bp", 8000), 8000)) / 100.0
	var icon_prefix: String = "🐎" if ut_raw == "CARAVAN" else ("🏴" if ut_raw == "COALITION_FORCE" else "⚔️")

	var edge_id: String = str(ent.get("edge_id", ent.get("current_edge_id", "")))
	var dest_ko: String = ""
	if not edge_id.is_empty() and _world_graph != null and _world_graph.has_edge(edge_id) and not cur_nid.is_empty():
		var next_nid: String = _world_graph.get_other_endpoint(edge_id, cur_nid)
		if not next_nid.is_empty():
			dest_ko = AssetRegistry.node_name_ko(next_nid)
	if dest_ko.is_empty():
		var t_nid: String = str(ent.get("target_node_id", ""))
		if not t_nid.is_empty() and t_nid != cur_nid:
			dest_ko = AssetRegistry.node_name_ko(t_nid)

	var loc_phrase: String = "%s → %s %s" % [loc_ko, dest_ko, st_ko] if (not dest_ko.is_empty() and st_raw == "MARCHING") else "%s %s" % [loc_ko, st_ko]
	if ut_raw == "CARAVAN":
		return "%s [%s · %s] %s · 호위 %s · 사기 %.0f%%" % [
			icon_prefix, fac_ko, ut_ko, loc_phrase, troops_str, morale_pct
		]
	return "%s [%s · %s] %s · 병력 %s · 사기 %.0f%%" % [
		icon_prefix, fac_ko, ut_ko, loc_phrase, troops_str, morale_pct
	]


func _redraw_lists() -> void:
	var nids: Array[String] = []
	for k: Variant in _cached_nodes.keys():
		nids.append(str(k))
	nids.sort()

	_summary_label.text = "천하 전략도 (%d개 거점) · 군단/상단 %d · 연합 집결 %d" % [
		nids.size(), _cached_armies.size(), _cached_rallies.size()
	]

	var prev_sel_nid: String = _get_selected_target_node_id()
	if prev_sel_nid.is_empty():
		prev_sel_nid = _selected_node_id

	for ch: Node in _nodes_box.get_children():
		_nodes_box.remove_child(ch)
		ch.queue_free()
	_target_node_opt.clear()

	for idx_n: int in range(nids.size()):
		var nid: String = nids[idx_n]
		var nd: Dictionary = _cached_nodes[nid]
		var st: Dictionary = _static_nodes[nid] if _static_nodes.has(nid) and _static_nodes[nid] is Dictionary else {}
		var name_ko: String = str(nd.get("name_ko", st.get("name_ko", AssetRegistry.node_name_ko(nid))))
		var prov: String = str(nd.get("province", st.get("province", "-")))
		var owner_fid: String = str(nd.get("owner_faction_id", st.get("owner_faction_id", "NEUTRAL")))
		var owner_ko: String = AssetRegistry.faction_name_ko(owner_fid)
		var fort_hp: int = _to_int(nd.get("fortification_hp", 0), 0)
		var sec_pct: float = float(_to_int(nd.get("security_bp", 7000), 7000)) / 100.0

		_target_node_opt.add_item("%s (%s)" % [name_ko, prov])
		_target_node_opt.set_item_metadata(idx_n, nid)

		var row_n: HBoxContainer = HBoxContainer.new()
		row_n.add_theme_constant_override("separation", 6)
		var badge: Label = Label.new()
		badge.text = "● %s" % _faction_short_ko(owner_fid)
		badge.custom_minimum_size = Vector2(56, 0)
		badge.add_theme_font_size_override("font_size", AssetRegistry.FONT_SIZE_CAPTION)
		badge.add_theme_color_override("font_color", _faction_ring_color(owner_fid))
		row_n.add_child(badge)

		var lbl: Label = Label.new()
		var home_tag: String = " ★" if nid == _host_node_id else ""
		lbl.text = "%s%s (%s) · %s · 성벽 %s · 치안 %.0f%%" % [
			name_ko, home_tag, prov, owner_ko, AssetRegistry.format_num(fort_hp), sec_pct
		]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		AssetRegistry.apply_text_role(lbl, "caption")
		row_n.add_child(lbl)
		_nodes_box.add_child(row_n)

	if not prev_sel_nid.is_empty():
		var idx: int = nids.find(prev_sel_nid)
		if idx >= 0:
			_target_node_opt.select(idx)
			_selected_node_id = prev_sel_nid

	_update_selected_node_detail()

	# CRITICAL: Keep _armies_box.get_child_count() == _cached_armies.size()
	for ch_a: Node in _armies_box.get_children():
		_armies_box.remove_child(ch_a)
		ch_a.queue_free()
	var eids: Array[String] = []
	for k_a: Variant in _cached_armies.keys():
		eids.append(str(k_a))
	eids.sort()
	if _armies_empty_label != null:
		_armies_empty_label.visible = eids.is_empty()
	for eid: String in eids:
		var ent: Dictionary = _cached_armies[eid]
		var lbl_a: Label = Label.new()
		lbl_a.text = _format_army_entry_ko(ent)
		lbl_a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		AssetRegistry.apply_text_role(lbl_a, "muted")
		lbl_a.add_theme_color_override("font_color", _faction_ring_color(str(ent.get("faction_id", "NEUTRAL"))))
		_armies_box.add_child(lbl_a)

	for ch_r: Node in _rallies_box.get_children():
		_rallies_box.remove_child(ch_r)
		ch_r.queue_free()
	var rids: Array[String] = []
	for k_r: Variant in _cached_rallies.keys():
		rids.append(str(k_r))
	rids.sort()
	if _rallies_empty_label != null:
		_rallies_empty_label.visible = rids.is_empty()
	for idx_r: int in range(rids.size()):
		var rid: String = rids[idx_r]
		var ral: Dictionary = _cached_rallies[rid]
		var lbl_r: Label = Label.new()
		var tgt_ko: String = AssetRegistry.node_name_ko(str(ral.get("target_node_id", "")))
		var rst_ko: String = AssetRegistry.unit_type_ko(str(ral.get("status", "RALLYING")))
		lbl_r.text = "⚑ 제%d연합 집결 → %s 공성 · %s · 참여 군단 %d" % [
			idx_r + 1,
			tgt_ko,
			rst_ko,
			_to_int(ral.get("participant_count", 1), 1)
		]
		lbl_r.tooltip_text = "집결 코드: %s" % rid
		AssetRegistry.apply_text_role(lbl_r, "muted")
		_rallies_box.add_child(lbl_r)

	if _map_canvas != null:
		_map_canvas.queue_redraw()


func get_node_count() -> int:
	return _cached_nodes.size()


func reset_view_state() -> void:
	_cached_nodes.clear()
	_cached_armies.clear()
	_cached_rallies.clear()
	_host_node_id = "xuchang"
	_selected_node_id = "luoyang"
	if _edge_path_edit != null:
		_edge_path_edit.text = ""
	if _rally_id_edit != null:
		_rally_id_edit.text = ""
	_load_default_nodes_preview()
	if _map_canvas != null:
		_map_canvas.queue_redraw()
