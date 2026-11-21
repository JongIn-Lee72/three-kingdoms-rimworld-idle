class_name ManorGridView
extends Control

signal intent_emitted(cmd_type: String, args: Dictionary)

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


func _init() -> void:
	name = "ManorGridView"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	_header_label = Label.new()
	_header_label.text = "장원 그리드 뷰 (32x32) | LOD 1 | 대기 중"
	root.add_child(_header_label)

	_resources_label = Label.new()
	_resources_label.text = "자원: GRAIN 0 | COIN 0 | WOOD 0 | IRON 0 | HORSES 0 | HERBS_WINE 0 | WEAPONS 0 | MERIT_PRESTIGE 0"
	_resources_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_resources_label)

	_grid_summary_label = Label.new()
	_grid_summary_label.text = "32x32 논리 격자 (1024 타일): 구역 분포 대기"
	_grid_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_grid_summary_label)

	_zones_label = Label.new()
	_zones_label.text = "8대 구역 요약: -"
	_zones_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_zones_label)

	var bld_title: Label = Label.new()
	bld_title.text = "[10대 장원 시설 증축]"
	root.add_child(bld_title)

	_buildings_box = VBoxContainer.new()
	root.add_child(_buildings_box)
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

	var pawn_title: Label = Label.new()
	pawn_title.text = "[가신 욕구 / 기분 / 정신 상태]"
	root.add_child(pawn_title)

	_pawns_box = VBoxContainer.new()
	root.add_child(_pawns_box)


func _on_upgrade_pressed(building_id: String) -> void:
	emit_upgrade_intent(building_id)


func emit_upgrade_intent(building_id: String, grid_x: int = -1, grid_y: int = -1) -> void:
	var args: Dictionary = {"building_id": building_id}
	if grid_x >= 0 and grid_x < DtoSchemas.MANOR_GRID_SIZE:
		args["grid_x"] = grid_x
	if grid_y >= 0 and grid_y < DtoSchemas.MANOR_GRID_SIZE:
		args["grid_y"] = grid_y
	intent_emitted.emit("CMD_BUILD_OR_UPGRADE", args)


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
		var _ok_r: bool = res_parts.append("%s: %d" % [rk, _to_int(stock.get(rk, 0), 0)])
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
				pawn_rows.append(pv)

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


func get_building_level_displayed(building_id: String) -> int:
	var bld_v: Variant = _last_snapshot.get("buildings", {})
	if bld_v is Dictionary:
		var bld: Dictionary = bld_v
		return _to_int(bld.get(building_id, 1), 1)
	return 1
