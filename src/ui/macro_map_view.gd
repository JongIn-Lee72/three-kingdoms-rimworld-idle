class_name MacroMapView
extends Control

signal intent_emitted(cmd_type: String, args: Dictionary)

var _assets: AssetRegistry = null
var _map_panel: PanelContainer = null
var _map_canvas: Control = null
var _section_panels_slate: Array[PanelContainer] = []
var _static_nodes: Dictionary = {}
var _static_edges: Array[Dictionary] = []

var _summary_label: Label = null
var _nodes_box: VBoxContainer = null
var _armies_box: VBoxContainer = null
var _rallies_box: VBoxContainer = null

var _target_node_opt: OptionButton = null
var _unit_type_opt: OptionButton = null
var _troop_spin: SpinBox = null
var _grain_spin: SpinBox = null
var _edge_path_edit: LineEdit = null
var _rally_id_edit: LineEdit = null

var _cached_nodes: Dictionary = {}
var _cached_armies: Dictionary = {}
var _cached_rallies: Dictionary = {}


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
		return Color(0.30, 0.56, 0.90, 0.98)
	if upper.contains("WU") or upper.contains("SUN"):
		return Color(0.28, 0.74, 0.46, 0.98)
	if upper.contains("SHU") or upper.contains("HAN") or upper.contains("LIU"):
		return Color(0.84, 0.30, 0.26, 0.98)
	return AssetRegistry.COLOR_GOLD_HIGHLIGHT


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
		_map_panel.add_theme_stylebox_override("panel", _assets.build_panel_stylebox(true))
	var slate_sb: StyleBoxTexture = _assets.build_panel_stylebox(false)
	for p_slate: PanelContainer in _section_panels_slate:
		if p_slate != null:
			p_slate.add_theme_stylebox_override("panel", slate_sb)
	if _map_canvas != null:
		_map_canvas.queue_redraw()


func get_map_canvas_node() -> Control:
	return _map_canvas


func get_static_edge_count() -> int:
	return _static_edges.size()


func _make_section_panel(parent: VBoxContainer) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inner: VBoxContainer = VBoxContainer.new()
	panel.add_child(inner)
	parent.add_child(panel)
	_section_panels_slate.append(panel)
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
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	_summary_label = Label.new()
	_summary_label.text = "천하 전략도 그래프 (15개 주요 거점) | 군단/상단: 0 | 연합 집결: 0"
	root.add_child(_summary_label)

	_map_panel = PanelContainer.new()
	_map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_canvas = Control.new()
	_map_canvas.custom_minimum_size = Vector2(560, 320)
	_map_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_canvas.draw.connect(_on_map_canvas_draw)
	_map_panel.add_child(_map_canvas)
	root.add_child(_map_panel)

	var nodes_sec: VBoxContainer = _make_section_panel(root)
	var nodes_hdr: Label = Label.new()
	nodes_hdr.text = "[거점 현황 (주/세력/성벽/치안)]"
	nodes_sec.add_child(nodes_hdr)

	_nodes_box = VBoxContainer.new()
	nodes_sec.add_child(_nodes_box)

	var armies_sec: VBoxContainer = _make_section_panel(root)
	var armies_hdr: Label = Label.new()
	armies_hdr.text = "[출진 군단 및 무역 상단]"
	armies_sec.add_child(armies_hdr)

	_armies_box = VBoxContainer.new()
	armies_sec.add_child(_armies_box)

	var rallies_sec: VBoxContainer = _make_section_panel(root)
	var rallies_hdr: Label = Label.new()
	rallies_hdr.text = "[연합 공성전 집결 현황]"
	rallies_sec.add_child(rallies_hdr)

	_rallies_box = VBoxContainer.new()
	rallies_sec.add_child(_rallies_box)

	# Expedition & Coalition Rally Controls
	var ctrl_sec: VBoxContainer = _make_section_panel(root)
	var ctrl_hdr: Label = Label.new()
	ctrl_hdr.text = "[출진 / 상단 파견 & 연합 공성 집결 명령]"
	ctrl_sec.add_child(ctrl_hdr)

	var row1: HBoxContainer = HBoxContainer.new()
	var tgt_lbl: Label = Label.new()
	tgt_lbl.text = "목표 거점:"
	row1.add_child(tgt_lbl)
	_target_node_opt = OptionButton.new()
	row1.add_child(_target_node_opt)

	var ut_lbl: Label = Label.new()
	ut_lbl.text = "유형:"
	row1.add_child(ut_lbl)
	_unit_type_opt = OptionButton.new()
	_unit_type_opt.add_item("ARMY")
	_unit_type_opt.add_item("CARAVAN")
	row1.add_child(_unit_type_opt)
	ctrl_sec.add_child(row1)

	var row2: HBoxContainer = HBoxContainer.new()
	var tr_lbl: Label = Label.new()
	tr_lbl.text = "병력:"
	row2.add_child(tr_lbl)
	_troop_spin = SpinBox.new()
	_troop_spin.min_value = 1
	_troop_spin.max_value = 3000
	_troop_spin.value = 100
	row2.add_child(_troop_spin)

	var gr_lbl: Label = Label.new()
	gr_lbl.text = "휴대 군량:"
	row2.add_child(gr_lbl)
	_grain_spin = SpinBox.new()
	_grain_spin.min_value = 0
	_grain_spin.max_value = 50000
	_grain_spin.value = 200
	row2.add_child(_grain_spin)
	ctrl_sec.add_child(row2)

	var row3: HBoxContainer = HBoxContainer.new()
	var path_lbl: Label = Label.new()
	path_lbl.text = "간선 경로(쉼표):"
	row3.add_child(path_lbl)
	_edge_path_edit = LineEdit.new()
	_edge_path_edit.placeholder_text = "e_xuchang_luoyang"
	_edge_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(_edge_path_edit)

	var btn_dispatch: Button = Button.new()
	btn_dispatch.text = "출진/파견 (CMD_DISPATCH_EXPEDITION)"
	btn_dispatch.pressed.connect(_on_dispatch_pressed)
	row3.add_child(btn_dispatch)
	ctrl_sec.add_child(row3)

	var row4: HBoxContainer = HBoxContainer.new()
	var btn_create_rally: Button = Button.new()
	btn_create_rally.text = "연합 집결 발령 (CMD_CREATE_COALITION_RALLY)"
	btn_create_rally.pressed.connect(_on_create_rally_pressed)
	row4.add_child(btn_create_rally)

	_rally_id_edit = LineEdit.new()
	_rally_id_edit.placeholder_text = "rally_000001"
	row4.add_child(_rally_id_edit)

	var btn_join_rally: Button = Button.new()
	btn_join_rally.text = "연합 집결 합류 (CMD_JOIN_COALITION_RALLY)"
	btn_join_rally.pressed.connect(_on_join_rally_pressed)
	row4.add_child(btn_join_rally)
	ctrl_sec.add_child(row4)

	_load_default_nodes_preview()


func _load_default_nodes_preview() -> void:
	var wg: WorldGraph = WorldGraph.new({}, true)
	var init_nodes: Dictionary = {}
	for nid: String in wg.get_node_ids():
		init_nodes[nid] = wg.get_node(nid)
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
	var pad_x: float = 28.0
	var pad_y: float = 24.0
	var usable_w: float = maxf(64.0, canvas_size.x - pad_x * 2.0)
	var usable_h: float = maxf(64.0, canvas_size.y - pad_y * 2.0)
	return Vector2(
		pad_x + (float(nx) / 1000.0) * usable_w,
		pad_y + (float(ny) / 1000.0) * usable_h
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
		_map_canvas.draw_rect(canvas_rect, Color(0.08, 0.06, 0.05, 0.18))

	for ed: Dictionary in _static_edges:
		var from_id: String = str(ed.get("from_node", ""))
		var to_id: String = str(ed.get("to_node", ""))
		if from_id.is_empty() or to_id.is_empty():
			continue
		var p1: Vector2 = _node_screen_pos(from_id, canvas_size)
		var p2: Vector2 = _node_screen_pos(to_id, canvas_size)
		var terrain: String = str(ed.get("terrain_type", "HIGHWAY"))
		_map_canvas.draw_line(p1, p2, _terrain_color(terrain), 2.5, true)

	var node_ids: Array[String] = []
	for k: Variant in _static_nodes.keys():
		node_ids.append(str(k))
	for ck: Variant in _cached_nodes.keys():
		var cks: String = str(ck)
		if not node_ids.has(cks):
			node_ids.append(cks)
	node_ids.sort()

	var font: Font = ThemeDB.fallback_font
	for nid: String in node_ids:
		var nd: Dictionary = _cached_nodes[nid] if _cached_nodes.has(nid) and _cached_nodes[nid] is Dictionary else {}
		var st: Dictionary = _static_nodes[nid] if _static_nodes.has(nid) and _static_nodes[nid] is Dictionary else {}
		var pos: Vector2 = _node_screen_pos(nid, canvas_size)
		var tier: String = str(nd.get("node_tier", st.get("node_tier", "COUNTY")))
		var owner_fid: String = str(nd.get("owner_faction_id", st.get("owner_faction_id", "NEUTRAL")))
		var name_ko: String = str(nd.get("name_ko", st.get("name_ko", nid)))
		var radius: float = 13.0 if tier == "CAPITAL" else (11.0 if tier == "CITY" or tier == "PASS" else 9.0)
		var ring_col: Color = _faction_ring_color(owner_fid)

		_map_canvas.draw_circle(pos, radius + 2.0, Color(0.08, 0.06, 0.05, 0.85))
		_map_canvas.draw_arc(pos, radius + 2.0, 0.0, TAU, 24, ring_col, 2.5, true)

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
			_map_canvas.draw_string(
				font,
				pos + Vector2(-18.0, radius + 14.0),
				name_ko,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				11,
				AssetRegistry.COLOR_PARCHMENT_TEXT
			)

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
		var offset: Vector2 = Vector2(14.0 + float((idx % 3) * 10), -14.0 - float((idx / 3) * 10))
		var apos: Vector2 = base_pos + offset
		var utype: String = str(ent.get("unit_type", "ARMY"))
		var arect: Rect2 = Rect2(apos - Vector2(9.0, 9.0), Vector2(18.0, 18.0))
		if _assets != null:
			var atex: Texture2D = _assets.get_army_icon(utype)
			if atex != null:
				_map_canvas.draw_texture_rect(atex, arect, false)
			else:
				_map_canvas.draw_rect(arect, AssetRegistry.COLOR_CRIMSON_ACCENT)
		else:
			_map_canvas.draw_rect(arect, AssetRegistry.COLOR_CRIMSON_ACCENT)


func _on_dispatch_pressed() -> void:
	var target_nid: String = ""
	if _target_node_opt.selected >= 0 and _target_node_opt.selected < _target_node_opt.item_count:
		target_nid = _target_node_opt.get_item_text(_target_node_opt.selected)
	var unit_t: String = _unit_type_opt.get_item_text(_unit_type_opt.selected) if _unit_type_opt.selected >= 0 else "ARMY"
	var edges: Array[String] = []
	for part: String in _edge_path_edit.text.split(",", false):
		var clean_e: String = part.strip_edges()
		if not clean_e.is_empty():
			edges.append(clean_e)
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
	var target_nid: String = ""
	if _target_node_opt.selected >= 0 and _target_node_opt.selected < _target_node_opt.item_count:
		target_nid = _target_node_opt.get_item_text(_target_node_opt.selected)
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


func _redraw_lists() -> void:
	var nids: Array[String] = []
	for k: Variant in _cached_nodes.keys():
		nids.append(str(k))
	nids.sort()

	_summary_label.text = "천하 전략도 그래프 (%d개 거점) | 군단/상단: %d | 연합 집결: %d" % [
		nids.size(), _cached_armies.size(), _cached_rallies.size()
	]

	var prev_sel_nid: String = ""
	if _target_node_opt.selected >= 0 and _target_node_opt.selected < _target_node_opt.item_count:
		prev_sel_nid = _target_node_opt.get_item_text(_target_node_opt.selected)

	for ch: Node in _nodes_box.get_children():
		ch.queue_free()
	_target_node_opt.clear()

	for nid: String in nids:
		_target_node_opt.add_item(nid)
		var nd: Dictionary = _cached_nodes[nid]
		var name_ko: String = str(nd.get("name_ko", nid))
		var prov: String = str(nd.get("province", "-"))
		var owner_fid: String = str(nd.get("owner_faction_id", "NEUTRAL"))
		var fort_hp: int = _to_int(nd.get("fortification_hp", 0), 0)
		var sec_bp: int = _to_int(nd.get("security_bp", 7000), 7000)

		var lbl: Label = Label.new()
		lbl.text = "%s (%s) | 주:%s | 점령:%s | 성벽:%d | 치안:%d bp" % [
			nid, name_ko, prov, owner_fid, fort_hp, sec_bp
		]
		_nodes_box.add_child(lbl)

	if not prev_sel_nid.is_empty():
		var idx: int = nids.find(prev_sel_nid)
		if idx >= 0:
			_target_node_opt.select(idx)

	for ch_a: Node in _armies_box.get_children():
		ch_a.queue_free()
	var eids: Array[String] = []
	for k_a: Variant in _cached_armies.keys():
		eids.append(str(k_a))
	eids.sort()
	for eid: String in eids:
		var ent: Dictionary = _cached_armies[eid]
		var lbl_a: Label = Label.new()
		lbl_a.text = "%s [%s/%s] | 거점:%s | 병력:%d | 사기:%d | 상태:%s" % [
			eid,
			str(ent.get("unit_type", "ARMY")),
			str(ent.get("faction_id", "NEUTRAL")),
			str(ent.get("current_node_id", "")),
			_to_int(ent.get("troop_count", 0), 0),
			_to_int(ent.get("morale_bp", 8000), 8000),
			str(ent.get("status", "MARCHING"))
		]
		_armies_box.add_child(lbl_a)

	for ch_r: Node in _rallies_box.get_children():
		ch_r.queue_free()
	var rids: Array[String] = []
	for k_r: Variant in _cached_rallies.keys():
		rids.append(str(k_r))
	rids.sort()
	for rid: String in rids:
		var ral: Dictionary = _cached_rallies[rid]
		var lbl_r: Label = Label.new()
		lbl_r.text = "%s -> %s | 상태:%s | 참여군단:%d" % [
			rid,
			str(ral.get("target_node_id", "")),
			str(ral.get("status", "RALLYING")),
			_to_int(ral.get("participant_count", 1), 1)
		]
		_rallies_box.add_child(lbl_r)

	if _map_canvas != null:
		_map_canvas.queue_redraw()


func get_node_count() -> int:
	return _cached_nodes.size()
