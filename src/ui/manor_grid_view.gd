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

var _header_label: Label = null
var _resources_label: Label = null
var _grid_summary_label: Label = null
var _zones_label: Label = null
var _buildings_box: VBoxContainer = null
var _pawns_box: VBoxContainer = null
var _upgrade_buttons: Dictionary = {}
var _last_snapshot: Dictionary = {}


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
		_grid_panel.add_theme_stylebox_override("panel", _assets.build_panel_stylebox(true))
	var slate_sb: StyleBoxTexture = _assets.build_panel_stylebox(false)
	for p_slate: PanelContainer in _section_panels_slate:
		if p_slate != null:
			p_slate.add_theme_stylebox_override("panel", slate_sb)
	for rk: String in DtoSchemas.RESOURCE_KEYS:
		var tr_v: Variant = _resource_icon_rects.get(rk, null)
		if tr_v is TextureRect:
			var tr: TextureRect = tr_v
			tr.texture = _assets.get_resource_icon(rk)
	if _grid_canvas != null:
		_grid_canvas.queue_redraw()


func get_canvas_node() -> Control:
	return _grid_canvas


func _make_section_panel(parent: VBoxContainer) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inner: VBoxContainer = VBoxContainer.new()
	panel.add_child(inner)
	parent.add_child(panel)
	_section_panels_slate.append(panel)
	return inner


func _build_ui() -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	var hdr_sec: VBoxContainer = _make_section_panel(root)
	_header_label = Label.new()
	_header_label.text = "장원 그리드 뷰 (32x32) | LOD 1 | 대기 중"
	hdr_sec.add_child(_header_label)

	_resource_icons_bar = HBoxContainer.new()
	_resource_icons_bar.add_theme_constant_override("separation", 10)
	for rk: String in DtoSchemas.RESOURCE_KEYS:
		var item_box: HBoxContainer = HBoxContainer.new()
		item_box.add_theme_constant_override("separation", 4)
		var icon_rect: TextureRect = TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(18, 18)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		item_box.add_child(icon_rect)
		var rlbl: Label = Label.new()
		rlbl.text = "%s:0" % rk
		item_box.add_child(rlbl)
		_resource_icons_bar.add_child(item_box)
		_resource_icon_rects[rk] = icon_rect
		_resource_icon_labels[rk] = rlbl
	hdr_sec.add_child(_resource_icons_bar)

	_resources_label = Label.new()
	_resources_label.text = "자원: GRAIN 0 | COIN 0 | WOOD 0 | IRON 0 | HORSES 0 | HERBS_WINE 0 | WEAPONS 0 | MERIT_PRESTIGE 0"
	_resources_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_sec.add_child(_resources_label)

	_grid_summary_label = Label.new()
	_grid_summary_label.text = "32x32 논리 격자 (1024 타일): 구역 분포 대기"
	_grid_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_sec.add_child(_grid_summary_label)

	_zones_label = Label.new()
	_zones_label.text = "8대 구역 요약: -"
	_zones_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hdr_sec.add_child(_zones_label)

	_grid_panel = PanelContainer.new()
	_grid_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_grid_canvas = Control.new()
	_grid_canvas.custom_minimum_size = Vector2(384, 384)
	_grid_canvas.draw.connect(_on_grid_canvas_draw)
	_grid_panel.add_child(_grid_canvas)
	root.add_child(_grid_panel)

	var bld_sec: VBoxContainer = _make_section_panel(root)
	var bld_title: Label = Label.new()
	bld_title.text = "[10대 장원 시설 증축]"
	bld_sec.add_child(bld_title)

	_buildings_box = VBoxContainer.new()
	bld_sec.add_child(_buildings_box)
	for bid: String in ManorState.BUILDING_IDS:
		var row: HBoxContainer = HBoxContainer.new()
		var lbl: Label = Label.new()
		lbl.name = "Lbl_" + bid
		lbl.text = "%s: Lv.1" % bid
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var btn: Button = Button.new()
		btn.text = "증축 (%s)" % bid
		btn.pressed.connect(_on_upgrade_pressed.bind(bid))
		row.add_child(btn)
		_buildings_box.add_child(row)
		_upgrade_buttons[bid] = {"label": lbl, "button": btn}

	var pawn_sec: VBoxContainer = _make_section_panel(root)
	var pawn_title: Label = Label.new()
	pawn_title.text = "[가신 욕구 / 기분 / 정신 상태]"
	pawn_sec.add_child(pawn_title)

	_pawns_box = VBoxContainer.new()
	pawn_sec.add_child(_pawns_box)


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
			_grid_canvas.draw_rect(tile_rect, Color(0.08, 0.06, 0.05, 0.25), false, 1.0)

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


func apply_snapshot(snapshot: Dictionary) -> void:
	_last_snapshot = snapshot.duplicate(true)

	var meta_v: Variant = snapshot.get("meta", {})
	var meta: Dictionary = meta_v if meta_v is Dictionary else {}
	var lod: int = _to_int(meta.get("lod", snapshot.get("current_lod", 1)), 1)
	var wall_hp: int = _to_int(meta.get("wall_hp", snapshot.get("wall_hp", 0)), 0)
	var troops: int = _to_int(meta.get("household_troops", snapshot.get("household_troops", 0)), 0)
	var manor_id: String = str(snapshot.get("manor_id", "manor"))
	_header_label.text = "장원 [%s] | 32x32 | LOD %d | 성벽 HP: %d | 사병: %d" % [manor_id, lod, wall_hp, troops]

	# 8-resource bar
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

	_grid_summary_label.text = "32x32 격자 요약: %dx%d (%d 타일 활성)" % [DtoSchemas.MANOR_GRID_SIZE, DtoSchemas.MANOR_GRID_SIZE, counted_tiles]
	var z_parts: PackedStringArray = PackedStringArray()
	for zt: String in ManorState.ZONE_TYPES:
		var _ok_z: bool = z_parts.append("%s=%d" % [zt, _to_int(zone_counts.get(zt, 0), 0)])
	_zones_label.text = "8대 구역 타일 수: " + ", ".join(z_parts)

	# 10 building levels
	var bld_v: Variant = snapshot.get("buildings", {})
	var bld: Dictionary = bld_v if bld_v is Dictionary else {}
	for bid: String in ManorState.BUILDING_IDS:
		var lvl: int = clampi(_to_int(bld.get(bid, 1), 1), 1, 5)
		var entry_v: Variant = _upgrade_buttons.get(bid, null)
		if entry_v is Dictionary:
			var entry: Dictionary = entry_v
			var lbl_v: Variant = entry.get("label", null)
			if lbl_v is Label:
				var lbl: Label = lbl_v
				lbl.text = "%s: Lv.%d" % [bid, lvl]
			var btn_v: Variant = entry.get("button", null)
			if btn_v is Button:
				var btn: Button = btn_v
				btn.disabled = lvl >= 5

	# Pawn needs / mood / mental state list
	for child: Node in _pawns_box.get_children():
		child.queue_free()

	var pawn_rows: Array[Dictionary] = _extract_pawn_rows(snapshot)
	for pr: Dictionary in pawn_rows:
		var pid: String = str(pr.get("pawn_id", "pawn"))
		var gx: int = _to_int(pr.get("x", pr.get("grid_x", 16)), 16)
		var gy: int = _to_int(pr.get("y", pr.get("grid_y", 16)), 16)
		var job: String = str(pr.get("job", pr.get("current_job", "IDLE")))
		var mood_v: int = _to_int(pr.get("mood", 50), 50)
		var mstate: String = str(pr.get("mental_state", "NORMAL"))
		var needs_v: Variant = pr.get("needs_bp", {})
		var needs: Dictionary = needs_v if needs_v is Dictionary else {}
		var food_bp: int = _to_int(pr.get("food_bp", needs.get("FOOD", 5000)), 5000)
		var rest_bp: int = _to_int(pr.get("rest_bp", needs.get("REST", 5000)), 5000)
		var loy_bp: int = _to_int(pr.get("loyalty_bp", needs.get("LOYALTY", 5000)), 5000)

		var plbl: Label = Label.new()
		plbl.text = "%s (%d,%d) | 직무:%s | 기분:%d | 상태:%s | 군량:%d 휴식:%d 충성:%d" % [
			pid, gx, gy, job, mood_v, mstate, food_bp, rest_bp, loy_bp
		]
		plbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_pawns_box.add_child(plbl)

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
	if _header_label != null:
		_header_label.text = "장원 그리드 뷰 (32x32) | LOD 1 | 대기 중"
	if _resources_label != null:
		_resources_label.text = "자원: GRAIN 0 | COIN 0 | WOOD 0 | IRON 0 | HORSES 0 | HERBS_WINE 0 | WEAPONS 0 | MERIT_PRESTIGE 0"
	for rk: String in DtoSchemas.RESOURCE_KEYS:
		var rlbl_v: Variant = _resource_icon_labels.get(rk, null)
		if rlbl_v is Label:
			var rlbl: Label = rlbl_v
			rlbl.text = "%s:0" % rk
	if _grid_summary_label != null:
		_grid_summary_label.text = "32x32 논리 격자 (1024 타일): 구역 분포 대기"
	if _zones_label != null:
		_zones_label.text = "8대 구역 요약: -"
	for bid: String in ManorState.BUILDING_IDS:
		var entry_v: Variant = _upgrade_buttons.get(bid, null)
		if entry_v is Dictionary:
			var entry: Dictionary = entry_v
			var lbl_v: Variant = entry.get("label", null)
			if lbl_v is Label:
				var lbl: Label = lbl_v
				lbl.text = "%s: Lv.1" % bid
			var btn_v: Variant = entry.get("button", null)
			if btn_v is Button:
				var btn: Button = btn_v
				btn.disabled = false
	if _pawns_box != null:
		for child: Node in _pawns_box.get_children():
			child.queue_free()
	if _grid_canvas != null:
		_grid_canvas.queue_redraw()
