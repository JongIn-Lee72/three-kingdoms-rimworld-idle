class_name WorkPriorityScheduleView
extends Control

signal intent_emitted(cmd_type: String, args: Dictionary)

const SHICHEN_NAMES: Array[String] = [
	"자시(23-01)", "축시(01-03)", "인시(03-05)", "묘시(05-07)",
	"진시(07-09)", "사시(09-11)", "오시(11-13)", "미시(13-15)",
	"신시(15-17)", "유시(17-19)", "술시(19-21)", "해시(21-23)"
]

const STANCE_OPTIONS: Array[String] = [
	"DEFENSIVE_HOLD", "PREEMPTIVE_STRIKE", "EVADE_DISENGAGE"
]
const FORMATION_OPTIONS: Array[String] = [
	"SQUARE_SHIELD", "WEDGE_SPEAR", "CRANE_WING", "SNAKE_COLUMN"
]
const DUEL_OPTIONS: Array[String] = [
	"ACCEPT_IF_ADVANTAGE", "ALWAYS_ACCEPT", "DECLINE"
]
const STRATAGEM_OPTIONS: Array[String] = [
	"FIRE_OR_FLOOD", "AMBUSH_TRAP", "PRESERVE_TROOPS", "DISRUPT_CONFUSE"
]
const PRISONER_OPTIONS: Array[String] = [
	"RECRUIT_PERSUADE", "RANSOM", "RELEASE_CHIVALROUS"
]

const TRAIT_NAMES_KO: Dictionary = {
	"T_CHIVALROUS": "의협",
	"T_AMBITIOUS": "야심가",
	"T_CAUTIOUS": "신중함",
	"T_DRINKER": "호주가",
	"T_MYSTIC": "둔갑",
	"T_UNSELFISH": "청렴",
	"T_GREEDY": "탐욕",
	"T_FIERCE": "맹장",
	"T_AGRARIAN": "둔전가",
	"T_SCHOLAR": "명사"
}

var _assets: AssetRegistry = null
var _section_panels_slate: Array[PanelContainer] = []
var _section_panels_gold: Array[PanelContainer] = []
var _card_panels: Array[PanelContainer] = []
var _prio_icon: TextureRect = null
var _sched_icon: TextureRect = null
var _doctrine_icon: TextureRect = null

var _pawn_selector: OptionButton = null
var _pawn_status_label: Label = null
var _pawn_stats_pill_label: Label = null
var _ration_summary_label: Label = null
var _priority_buttons: Dictionary = {}   # domain -> Array[Button]
var _schedule_selectors: Array[OptionButton] = []
var _stance_opt: OptionButton = null
var _formation_opt: OptionButton = null
var _duel_opt: OptionButton = null
var _stratagem_opt: OptionButton = null
var _prisoner_opt: OptionButton = null
var _doctrine_apply_btn: Button = null
var _schedule_apply_btn: Button = null

var _selected_pawn_id: String = ""
var _pawns_cache: Dictionary = {}
var _current_schedule: Array[String] = []
var _current_doctrine: Dictionary = {}


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


static func _trait_ko(trait_id: String) -> String:
	if TRAIT_NAMES_KO.has(trait_id):
		return str(TRAIT_NAMES_KO[trait_id])
	return trait_id


static func _format_pawn_display_name(pid: String, pd_item: Dictionary, retainer_idx: int) -> String:
	var raw_av: Variant = pd_item.get("is_avatar", false)
	var flag_av: bool = false
	if raw_av is bool:
		var b_av: bool = raw_av
		flag_av = b_av
	var is_av: bool = pid.ends_with("_avatar") or flag_av
	var disp_name: String = str(pd_item.get("name", "")).strip_edges()
	if disp_name == "주인공 군주" or disp_name == "Nameless_Hero" or disp_name.is_empty():
		disp_name = "조자룡" if is_av else "진도"
	elif disp_name == "Retainer":
		disp_name = "서약 가신 %d" % maxi(1, retainer_idx)
	if is_av:
		return "주군 %s (주인공)" % disp_name
	return "서약 가신 %s" % disp_name


func _init() -> void:
	name = "WorkPriorityScheduleView"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_current_schedule = [
		"SLEEP", "SLEEP", "SLEEP", "DRILL",
		"WORK", "WORK", "WORK", "WORK",
		"WORK", "RECREATION", "ANYTHING", "SLEEP"
	]
	_current_doctrine = ManorState.DEFAULT_DOCTRINE.duplicate(true)
	_build_ui()


func set_asset_registry(reg: AssetRegistry) -> void:
	_assets = reg
	if _assets == null:
		return
	var card_sb: StyleBoxFlat = _assets.build_card_stylebox(false, AssetRegistry.COLOR_SUBTLE_BORDER)
	for p_card: PanelContainer in _card_panels:
		if p_card != null:
			p_card.add_theme_stylebox_override("panel", card_sb)
	if _prio_icon != null:
		_prio_icon.texture = _assets.get_zone_tile("ZONE_WORKSHOP")
	if _sched_icon != null:
		_sched_icon.texture = _assets.get_resource_icon("HERBS_WINE")
	if _doctrine_icon != null:
		_doctrine_icon.texture = _assets.get_resource_icon("WEAPONS")
	if _schedule_apply_btn != null:
		_assets.apply_button_variant(_schedule_apply_btn, "primary")
	if _doctrine_apply_btn != null:
		_assets.apply_button_variant(_doctrine_apply_btn, "primary")


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
	inner.add_theme_constant_override("separation", 6)
	panel.add_child(inner)
	parent.add_child(panel)
	_card_panels.append(panel)
	return inner


func _make_header_with_icon(parent: VBoxContainer, title_text: String) -> TextureRect:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = Vector2(18, 18)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var hdr: Label = Label.new()
	hdr.text = title_text
	AssetRegistry.apply_text_role(hdr, "section")
	row.add_child(hdr)
	parent.add_child(row)
	return icon


func _build_ui() -> void:
	var outer: VBoxContainer = VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	# Top Pawn Selector, Status Badge, 5-Stat & Trait Pill Bar & Quick Presets
	var top_sec: VBoxContainer = _make_card_panel(outer, true, AssetRegistry.COLOR_GOLD_ACCENT)
	var pawn_row: HBoxContainer = HBoxContainer.new()
	pawn_row.add_theme_constant_override("separation", 8)
	top_sec.add_child(pawn_row)

	var pawn_lbl: Label = Label.new()
	pawn_lbl.text = "대상 가신:"
	AssetRegistry.apply_text_role(pawn_lbl, "body")
	pawn_row.add_child(pawn_lbl)

	_pawn_selector = OptionButton.new()
	_pawn_selector.custom_minimum_size = Vector2(210, 0)
	_pawn_selector.item_selected.connect(_on_pawn_selected)
	pawn_row.add_child(_pawn_selector)

	_pawn_status_label = Label.new()
	_pawn_status_label.text = "주군 조자룡 (주인공) · 직무: 대기 · 기분 55 · 충성 80% · 상태: 평온"
	_pawn_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	AssetRegistry.apply_text_role(_pawn_status_label, "muted")
	pawn_row.add_child(_pawn_status_label)

	var preset_lbl: Label = Label.new()
	preset_lbl.text = "빠른 프리셋:"
	AssetRegistry.apply_text_role(preset_lbl, "caption")
	pawn_row.add_child(preset_lbl)

	var preset_defs: Array[Dictionary] = [
		{"id": "DOMESTIC", "label": "내정 집중"},
		{"id": "WAR", "label": "전시 대비"},
		{"id": "REST", "label": "휴양 회복"}
	]
	for pdef: Dictionary in preset_defs:
		var pbtn: Button = Button.new()
		pbtn.text = str(pdef["label"])
		pbtn.pressed.connect(_on_preset_pressed.bind(str(pdef["id"])))
		pawn_row.add_child(pbtn)

	# Compact 5-Stat & Trait Pill Bar
	var stat_pill_panel: PanelContainer = PanelContainer.new()
	stat_pill_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pill_sb: StyleBoxFlat = StyleBoxFlat.new()
	pill_sb.bg_color = Color(0.11, 0.10, 0.09, 0.94)
	pill_sb.border_color = AssetRegistry.COLOR_SUBTLE_BORDER
	pill_sb.set_border_width_all(1)
	pill_sb.set_corner_radius_all(4)
	pill_sb.content_margin_left = 10.0
	pill_sb.content_margin_right = 10.0
	pill_sb.content_margin_top = 4.0
	pill_sb.content_margin_bottom = 4.0
	stat_pill_panel.add_theme_stylebox_override("panel", pill_sb)
	_pawn_stats_pill_label = Label.new()
	_pawn_stats_pill_label.text = "통솔 64 · 무력 64 · 지력 64 · 정치 64 · 매력 64 | 특성: 의협 · 신중함"
	_pawn_stats_pill_label.add_theme_font_size_override("font_size", AssetRegistry.FONT_SIZE_BODY)
	_pawn_stats_pill_label.add_theme_color_override("font_color", AssetRegistry.COLOR_GOLD_HIGHLIGHT)
	stat_pill_panel.add_child(_pawn_stats_pill_label)
	top_sec.add_child(stat_pill_panel)

	# 2-Column HSplitContainer Dashboard
	var split: HSplitContainer = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.split_offset = 0
	outer.add_child(split)

	# LEFT PANE: 7-Domain Priority Matrix + Ration Summary Card
	var left_scroll: ScrollContainer = ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(450, 0)
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_stretch_ratio = 0.80
	split.add_child(left_scroll)

	var left_col: VBoxContainer = VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 8)
	left_scroll.add_child(left_col)

	var prio_sec: VBoxContainer = _make_card_panel(left_col, false)
	_prio_icon = _make_header_with_icon(prio_sec, "7대 업무 우선순위 매트릭스")

	var loop_sub: Label = Label.new()
	loop_sub.text = "위(물류·운반)부터 아래(외교·교류) 순서로 1→4 우선순위가 24시간 자동 실행됩니다"
	loop_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	AssetRegistry.apply_text_role(loop_sub, "muted")
	prio_sec.add_child(loop_sub)

	var legend_lbl: Label = Label.new()
	legend_lbl.text = "1 최우선(홍금) · 2 높음(호박) · 3 보통(청자) · 4 낮음(연록) · 0 제외(비활성)"
	AssetRegistry.apply_text_role(legend_lbl, "caption")
	prio_sec.add_child(legend_lbl)

	var hdr_row: HBoxContainer = HBoxContainer.new()
	hdr_row.add_theme_constant_override("separation", 6)
	var dom_hdr: Label = Label.new()
	dom_hdr.text = "업무 영역"
	dom_hdr.custom_minimum_size = Vector2(130, 0)
	AssetRegistry.apply_text_role(dom_hdr, "caption")
	hdr_row.add_child(dom_hdr)
	var prio_hdr_names: Array[String] = ["제외(0)", "최우선(1)", "높음(2)", "보통(3)", "낮음(4)"]
	for htxt: String in prio_hdr_names:
		var hl: Label = Label.new()
		hl.text = htxt
		hl.custom_minimum_size = Vector2(54, 0)
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		AssetRegistry.apply_text_role(hl, "caption")
		hdr_row.add_child(hl)
	prio_sec.add_child(hdr_row)

	for domain: String in PawnEntity.WORK_DOMAINS:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var dlbl: Label = Label.new()
		dlbl.text = AssetRegistry.work_domain_ko(domain)
		dlbl.tooltip_text = "%s (%s)" % [AssetRegistry.work_domain_ko(domain), domain]
		dlbl.custom_minimum_size = Vector2(130, 0)
		AssetRegistry.apply_text_role(dlbl, "body")
		row.add_child(dlbl)

		var btns: Array[Button] = []
		for prio: int in range(5):
			var b: Button = Button.new()
			b.text = str(prio)
			b.custom_minimum_size = Vector2(54, 30)
			b.toggle_mode = true
			b.button_pressed = (prio == 2)
			b.pressed.connect(_on_priority_pressed.bind(domain, prio))
			row.add_child(b)
			btns.append(b)
		_priority_buttons[domain] = btns
		_update_priority_button_visuals(domain, 2)
		prio_sec.add_child(row)

	# Ration & Wine Policy Summary Card
	var ration_sec: VBoxContainer = _make_card_panel(left_col, false)
	var r_title: Label = Label.new()
	r_title.text = "장원 배급 · 주류 정책 요약"
	AssetRegistry.apply_text_role(r_title, "section")
	ration_sec.add_child(r_title)

	_ration_summary_label = Label.new()
	_ration_summary_label.text = "현재 식량 배급: 표준식(보통) · 명주 배급 활성(호주가 가신 기분 보너스) · 비축 약주: 0"
	_ration_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	AssetRegistry.apply_text_role(_ration_summary_label, "muted")
	ration_sec.add_child(_ration_summary_label)

	# RIGHT PANE: 12-ShiChen Schedule (top) + Standing Tactical Doctrine (bottom)
	var right_scroll: ScrollContainer = ScrollContainer.new()
	right_scroll.custom_minimum_size = Vector2(560, 0)
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_stretch_ratio = 1.20
	split.add_child(right_scroll)

	var right_col: VBoxContainer = VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 8)
	right_scroll.add_child(right_col)

	var sched_sec: VBoxContainer = _make_card_panel(right_col, false)
	var sched_hdr_row: HBoxContainer = HBoxContainer.new()
	_sched_icon = _make_header_with_icon(sched_sec, "십이지시(12시진) 일과표")

	var sched_sub: Label = Label.new()
	sched_sub.text = "하루 12시진(24시간) 동안 가신이 자동으로 수행할 집무·연무·연회·취침 리듬을 배정합니다"
	sched_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	AssetRegistry.apply_text_role(sched_sub, "caption")
	sched_sec.add_child(sched_sub)

	var sched_grid: GridContainer = GridContainer.new()
	sched_grid.columns = 4
	sched_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sched_grid.add_theme_constant_override("h_separation", 8)
	sched_grid.add_theme_constant_override("v_separation", 6)
	sched_sec.add_child(sched_grid)

	for si: int in range(12):
		var cell: VBoxContainer = VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 2)
		var slbl: Label = Label.new()
		slbl.text = SHICHEN_NAMES[si]
		AssetRegistry.apply_text_role(slbl, "caption")
		cell.add_child(slbl)

		var opt: OptionButton = OptionButton.new()
		opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for ai: int in range(PawnEntity.SHICHEN_ACTIVITIES.size()):
			var act: String = PawnEntity.SHICHEN_ACTIVITIES[ai]
			opt.add_item(AssetRegistry.shichen_activity_ko(act))
			opt.set_item_metadata(ai, act)
		var def_idx: int = PawnEntity.SHICHEN_ACTIVITIES.find(_current_schedule[si])
		if def_idx >= 0:
			opt.select(def_idx)
		opt.item_selected.connect(_on_schedule_slot_changed.bind(si))
		cell.add_child(opt)
		sched_grid.add_child(cell)
		_schedule_selectors.append(opt)

	_schedule_apply_btn = Button.new()
	_schedule_apply_btn.text = "일과표 일괄 적용"
	_schedule_apply_btn.tooltip_text = "선택한 가신의 12시진 일과표를 서버에 즉시 반영합니다"
	_schedule_apply_btn.pressed.connect(_on_apply_schedule_pressed)
	sched_hdr_row.add_child(_schedule_apply_btn)
	sched_sec.add_child(sched_hdr_row)

	# Standing Tactical Doctrine selector
	var doc_sec: VBoxContainer = _make_card_panel(right_col, true, AssetRegistry.COLOR_GOLD_ACCENT)
	_doctrine_icon = _make_header_with_icon(doc_sec, "상시 교전 수칙 (원정 · 방어 자동 판단)")

	var doc_sub: Label = Label.new()
	doc_sub.text = "부재 중 침공 방어나 장거리 원정 출진 시 가신·장수들이 따르는 기본 전술 방침입니다"
	doc_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	AssetRegistry.apply_text_role(doc_sub, "caption")
	doc_sec.add_child(doc_sub)

	_stance_opt = _make_option_row(doc_sec, "교전 태세:", STANCE_OPTIONS)
	_formation_opt = _make_option_row(doc_sec, "기본 진형:", FORMATION_OPTIONS)
	_duel_opt = _make_option_row(doc_sec, "일기토 수칙:", DUEL_OPTIONS)
	_stratagem_opt = _make_option_row(doc_sec, "계략 방침:", STRATAGEM_OPTIONS)
	_prisoner_opt = _make_option_row(doc_sec, "포로 처우:", PRISONER_OPTIONS)

	_doctrine_apply_btn = Button.new()
	_doctrine_apply_btn.text = "교전 수칙 저장"
	_doctrine_apply_btn.tooltip_text = "오프라인 및 원정 시 자동 적용되는 상시 교전 수칙을 저장합니다"
	_doctrine_apply_btn.pressed.connect(_on_apply_doctrine_pressed)
	doc_sec.add_child(_doctrine_apply_btn)


func _make_option_row(parent: VBoxContainer, label_text: String, items: Array[String]) -> OptionButton:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl: Label = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(110, 0)
	AssetRegistry.apply_text_role(lbl, "muted")
	row.add_child(lbl)

	var opt: OptionButton = OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i: int in range(items.size()):
		var it: String = items[i]
		opt.add_item(AssetRegistry.doctrine_option_ko(it))
		opt.set_item_metadata(i, it)
	row.add_child(opt)
	parent.add_child(row)
	return opt


func _get_selected_pawn_from_selector(index: int) -> String:
	if _pawn_selector == null or index < 0 or index >= _pawn_selector.item_count:
		return ""
	var md: Variant = _pawn_selector.get_item_metadata(index)
	if md is String and not str(md).is_empty():
		return str(md)
	return _pawn_selector.get_item_text(index)


func _get_selected_pawn_id() -> String:
	if not _selected_pawn_id.is_empty():
		return _selected_pawn_id
	if _pawn_selector != null and _pawn_selector.selected >= 0:
		return _get_selected_pawn_from_selector(_pawn_selector.selected)
	return ""


func _on_pawn_selected(index: int) -> void:
	var pid: String = _get_selected_pawn_from_selector(index)
	if not pid.is_empty():
		_selected_pawn_id = pid
		_refresh_pawn_controls()


func _apply_preset_priorities(target_pid: String, targets: Dictionary) -> void:
	var cur_prios: Dictionary = {}
	var p_v: Variant = _pawns_cache.get(target_pid, null)
	if p_v is Dictionary:
		var pd: Dictionary = p_v
		var wp_v: Variant = pd.get("work_priorities", null)
		if wp_v is Dictionary:
			cur_prios = wp_v
	for dom: String in PawnEntity.WORK_DOMAINS:
		if not targets.has(dom):
			continue
		var target_prio: int = _to_int(targets[dom], 2)
		if cur_prios.is_empty() or _to_int(cur_prios.get(dom, -1), -1) != target_prio:
			set_work_priority_intent(target_pid, dom, target_prio)


func _on_preset_pressed(preset_id: String) -> void:
	var target_pid: String = _selected_pawn_id if not _selected_pawn_id.is_empty() else "player_01_avatar"
	match preset_id:
		"DOMESTIC":
			_apply_preset_priorities(target_pid, {
				"AGRICULTURE": 1,
				"PATROL": 3,
				"TRAINING": 3
			})
		"WAR":
			_apply_preset_priorities(target_pid, {
				"PATROL": 1,
				"TRAINING": 1,
				"AGRICULTURE": 3
			})
		"REST":
			var rest_sched: Array[String] = [
				"SLEEP", "SLEEP", "SLEEP", "SLEEP",
				"RECREATION", "WORK", "RECREATION", "WORK",
				"RECREATION", "RECREATION", "SLEEP", "SLEEP"
			]
			set_full_schedule_intent(target_pid, rest_sched)


func _on_priority_pressed(domain: String, priority: int) -> void:
	set_work_priority_intent(_selected_pawn_id, domain, priority)


func set_work_priority_intent(pawn_id: String, domain: String, priority: int) -> void:
	var target_pid: String = pawn_id if not pawn_id.is_empty() else _selected_pawn_id
	if target_pid.is_empty():
		target_pid = "player_01_avatar"
	var clamped_prio: int = clampi(priority, 0, 4)
	_update_priority_button_visuals(domain, clamped_prio)
	if not _pawns_cache.has(target_pid) or not (_pawns_cache[target_pid] is Dictionary):
		_pawns_cache[target_pid] = {"work_priorities": {}}
	var pd_cache: Dictionary = _pawns_cache[target_pid]
	if not pd_cache.has("work_priorities") or not (pd_cache["work_priorities"] is Dictionary):
		pd_cache["work_priorities"] = {}
	var wp_cache: Dictionary = pd_cache["work_priorities"]
	wp_cache[domain] = clamped_prio
	intent_emitted.emit("CMD_SET_WORK_PRIORITY", {
		"pawn_id": target_pid,
		"domain": domain,
		"priority": clamped_prio
	})


func _on_schedule_slot_changed(item_idx: int, shichen_idx: int) -> void:
	if shichen_idx < 0 or shichen_idx >= 12:
		return
	var act: String = ""
	if shichen_idx < _schedule_selectors.size():
		var opt: OptionButton = _schedule_selectors[shichen_idx]
		var md: Variant = opt.get_item_metadata(item_idx)
		if md is String and not str(md).is_empty():
			act = str(md)
	if act.is_empty() and item_idx >= 0 and item_idx < PawnEntity.SHICHEN_ACTIVITIES.size():
		act = PawnEntity.SHICHEN_ACTIVITIES[item_idx]
	if not act.is_empty():
		_current_schedule[shichen_idx] = act
		set_schedule_slot_intent(_selected_pawn_id, shichen_idx, act)


func set_schedule_slot_intent(pawn_id: String, shichen_index: int, activity: String) -> void:
	var idx: int = clampi(shichen_index, 0, 11)
	var act: String = activity if PawnEntity.SHICHEN_ACTIVITIES.has(activity) else "WORK"
	_current_schedule[idx] = act
	var args: Dictionary = {
		"shichen_index": idx,
		"activity": act
	}
	var target_pid: String = pawn_id if not pawn_id.is_empty() else _selected_pawn_id
	if not target_pid.is_empty():
		args["pawn_id"] = target_pid
	intent_emitted.emit("CMD_SET_SCHEDULE", args)


func _on_apply_schedule_pressed() -> void:
	set_full_schedule_intent(_selected_pawn_id, _current_schedule)


func set_full_schedule_intent(pawn_id: String, schedule: Array[String]) -> void:
	var clean: Array[String] = []
	for i: int in range(12):
		var act: String = schedule[i] if i < schedule.size() else "WORK"
		if not PawnEntity.SHICHEN_ACTIVITIES.has(act):
			act = "WORK"
		clean.append(act)
	_current_schedule = clean
	var args: Dictionary = {"schedule": clean}
	var target_pid: String = pawn_id if not pawn_id.is_empty() else _selected_pawn_id
	if not target_pid.is_empty():
		args["pawn_id"] = target_pid
	intent_emitted.emit("CMD_SET_SCHEDULE", args)


func _get_option_raw_value(opt: OptionButton, fallback_list: Array[String], fallback: String) -> String:
	if opt == null or opt.selected < 0:
		return fallback
	var md: Variant = opt.get_item_metadata(opt.selected)
	if md is String and not str(md).is_empty():
		return str(md)
	if opt.selected < fallback_list.size():
		return fallback_list[opt.selected]
	return fallback


func _on_apply_doctrine_pressed() -> void:
	var stance: String = _get_option_raw_value(_stance_opt, STANCE_OPTIONS, "DEFENSIVE_HOLD")
	var formation: String = _get_option_raw_value(_formation_opt, FORMATION_OPTIONS, "SQUARE_SHIELD")
	var duel: String = _get_option_raw_value(_duel_opt, DUEL_OPTIONS, "ACCEPT_IF_ADVANTAGE")
	var stratagem: String = _get_option_raw_value(_stratagem_opt, STRATAGEM_OPTIONS, "FIRE_OR_FLOOD")
	var prisoner: String = _get_option_raw_value(_prisoner_opt, PRISONER_OPTIONS, "RECRUIT_PERSUADE")
	set_doctrine_intent({
		"engagement_stance": stance,
		"formation": formation,
		"duel_policy": duel,
		"stratagem_policy": stratagem,
		"prisoner_policy": prisoner
	})


func set_doctrine_intent(doctrine_patch: Dictionary) -> void:
	for k: Variant in doctrine_patch.keys():
		_current_doctrine[str(k)] = doctrine_patch[k]
	intent_emitted.emit("CMD_SET_DOCTRINE", doctrine_patch.duplicate(true))


func _priority_active_style(prio: int) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6.0
	sb.content_margin_right = 6.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	match prio:
		1:
			sb.bg_color = Color(0.62, 0.19, 0.16, 0.98)
			sb.border_color = AssetRegistry.COLOR_GOLD_HIGHLIGHT
		2:
			sb.bg_color = Color(0.56, 0.38, 0.12, 0.98)
			sb.border_color = AssetRegistry.COLOR_WARNING_AMBER
		3:
			sb.bg_color = Color(0.18, 0.34, 0.46, 0.96)
			sb.border_color = AssetRegistry.COLOR_INFO_AZURE
		4:
			sb.bg_color = Color(0.20, 0.34, 0.24, 0.95)
			sb.border_color = AssetRegistry.COLOR_SUCCESS_JADE
		_:
			sb.bg_color = Color(0.14, 0.13, 0.12, 0.90)
			sb.border_color = AssetRegistry.COLOR_TEXT_MUTED
	return sb


func _update_priority_button_visuals(domain: String, active_prio: int) -> void:
	var btns_v: Variant = _priority_buttons.get(domain, null)
	if btns_v is Array:
		var btns: Array = btns_v
		for p: int in range(btns.size()):
			var bv: Variant = btns[p]
			if bv is Button:
				var b: Button = bv
				var is_active: bool = (p == active_prio)
				b.set_pressed_no_signal(is_active)
				if is_active:
					b.add_theme_stylebox_override("pressed", _priority_active_style(p))
					b.add_theme_stylebox_override("normal", _priority_active_style(p))
					b.add_theme_color_override("font_color", AssetRegistry.COLOR_TEXT_PRIMARY)
				else:
					b.remove_theme_stylebox_override("pressed")
					b.remove_theme_stylebox_override("normal")
					b.remove_theme_color_override("font_color")


func _refresh_pawn_controls() -> void:
	var p_v: Variant = _pawns_cache.get(_selected_pawn_id, {})
	if not (p_v is Dictionary):
		return
	var pd: Dictionary = p_v
	if _pawn_status_label != null:
		var disp_lbl: String = _format_pawn_display_name(_selected_pawn_id, pd, 1)
		var job_ko_s: String = AssetRegistry.job_ko(str(pd.get("job", pd.get("current_job", "IDLE"))))
		var mood_i: int = clampi(_to_int(pd.get("mood", 50), 50), 0, 100)
		var loy_pct: int = clampi(_to_int(pd.get("loyalty_bp", 5000), 5000) / 100, 0, 100)
		var mstate_s: String = AssetRegistry.mental_state_ko(str(pd.get("mental_state", "NORMAL")))
		_pawn_status_label.text = "%s · 직무: %s · 기분 %d · 충성 %d%% · 상태: %s" % [disp_lbl, job_ko_s, mood_i, loy_pct, mstate_s]

	if _pawn_stats_pill_label != null:
		var stats_v: Variant = pd.get("stats", {})
		var stats_d: Dictionary = stats_v if stats_v is Dictionary else {}
		var raw_av_pill: Variant = pd.get("is_avatar", false)
		var flag_av_pill: bool = false
		if raw_av_pill is bool:
			var b_av_pill: bool = raw_av_pill
			flag_av_pill = b_av_pill
		var is_av: bool = _selected_pawn_id.ends_with("_avatar") or flag_av_pill
		var lea_i: int = _to_int(stats_d.get("LEA", 74 if is_av else 62), 64)
		var mar_i: int = _to_int(stats_d.get("MAR", 86 if is_av else 58), 64)
		var int_i: int = _to_int(stats_d.get("INT", 70 if is_av else 78), 64)
		var pol_i: int = _to_int(stats_d.get("POL", 72 if is_av else 68), 64)
		var cha_i: int = _to_int(stats_d.get("CHA", 79 if is_av else 64), 64)
		var traits_v: Variant = pd.get("traits", [])
		var trait_names: PackedStringArray = PackedStringArray()
		if traits_v is Array:
			var ta: Array = traits_v
			for tv: Variant in ta:
				var _ok_t: bool = trait_names.append(_trait_ko(str(tv)))
		var traits_str: String = " · ".join(trait_names) if not trait_names.is_empty() else ("의협 · 야심가" if is_av else "신중함 · 청렴")
		_pawn_stats_pill_label.text = "통솔 %d · 무력 %d · 지력 %d · 정치 %d · 매력 %d | 특성: %s" % [
			lea_i, mar_i, int_i, pol_i, cha_i, traits_str
		]

	var wp_v: Variant = pd.get("work_priorities", {})
	if wp_v is Dictionary:
		var wp: Dictionary = wp_v
		for dom: String in PawnEntity.WORK_DOMAINS:
			_update_priority_button_visuals(dom, clampi(_to_int(wp.get(dom, 2), 2), 0, 4))

	var sched_v: Variant = pd.get("daily_schedule", [])
	if sched_v is Array:
		var sa: Array = sched_v
		for si: int in range(mini(12, sa.size())):
			var act: String = str(sa[si])
			if PawnEntity.SHICHEN_ACTIVITIES.has(act):
				_current_schedule[si] = act
				var idx: int = PawnEntity.SHICHEN_ACTIVITIES.find(act)
				if si < _schedule_selectors.size() and idx >= 0:
					_schedule_selectors[si].select(idx)


func _select_option_by_raw(opt: OptionButton, raw_val: String) -> void:
	if opt == null:
		return
	for i: int in range(opt.item_count):
		var md: Variant = opt.get_item_metadata(i)
		if md is String and str(md) == raw_val:
			opt.select(i)
			return
		if opt.get_item_text(i) == raw_val:
			opt.select(i)
			return


func apply_snapshot(snapshot: Dictionary) -> void:
	_pawns_cache.clear()
	var pawns_v: Variant = snapshot.get("pawns", {})
	var ordered_ids: Array[String] = []
	if pawns_v is Dictionary:
		var pd: Dictionary = pawns_v
		for k: Variant in pd.keys():
			var pk: String = str(k)
			var pv: Variant = pd[k]
			if pv is Dictionary:
				var pdict: Dictionary = pv
				_pawns_cache[pk] = pdict.duplicate(true)
				ordered_ids.append(pk)
	elif pawns_v is Array:
		var pa: Array = pawns_v
		for pv: Variant in pa:
			if pv is Dictionary:
				var pdict: Dictionary = pv
				var pid: String = str(pdict.get("pawn_id", ""))
				if not pid.is_empty():
					_pawns_cache[pid] = pdict.duplicate(true)
					ordered_ids.append(pid)

	ordered_ids.sort()
	_pawn_selector.clear()
	var retainer_counter: int = 0
	for idx: int in range(ordered_ids.size()):
		var pid: String = ordered_ids[idx]
		var pd_item: Dictionary = _pawns_cache[pid]
		var raw_av: Variant = pd_item.get("is_avatar", false)
		var flag_av: bool = false
		if raw_av is bool:
			var b_av: bool = raw_av
			flag_av = b_av
		var is_av: bool = pid.ends_with("_avatar") or flag_av
		if not is_av:
			retainer_counter += 1
		var label_txt: String = _format_pawn_display_name(pid, pd_item, retainer_counter)
		_pawn_selector.add_item(label_txt)
		_pawn_selector.set_item_metadata(idx, pid)

	if not ordered_ids.is_empty():
		if _selected_pawn_id.is_empty() or not _pawns_cache.has(_selected_pawn_id):
			_selected_pawn_id = ordered_ids[0]
		var sel_idx: int = ordered_ids.find(_selected_pawn_id)
		if sel_idx >= 0:
			_pawn_selector.select(sel_idx)
		_refresh_pawn_controls()

	if _ration_summary_label != null:
		var stock_v: Variant = snapshot.get("stockpile", {})
		var stock: Dictionary = stock_v if stock_v is Dictionary else {}
		var grain_cnt: int = _to_int(stock.get("GRAIN", 0), 0)
		var wine_cnt: int = _to_int(stock.get("HERBS_WINE", 0), 0)
		_ration_summary_label.text = "현재 식량 배급: 표준식(보통) · 명주 배급 활성(호주가 사기 상승) · 비축 군량 %s · 약주 %s" % [
			AssetRegistry.format_num(grain_cnt),
			AssetRegistry.format_num(wine_cnt)
		]

	var doc_v: Variant = snapshot.get("standing_doctrine", {})
	if doc_v is Dictionary:
		var doc: Dictionary = doc_v
		for k: Variant in doc.keys():
			_current_doctrine[str(k)] = doc[k]
		_select_option_by_raw(_stance_opt, str(_current_doctrine.get("engagement_stance", "DEFENSIVE_HOLD")))
		_select_option_by_raw(_formation_opt, str(_current_doctrine.get("formation", "SQUARE_SHIELD")))
		_select_option_by_raw(_duel_opt, str(_current_doctrine.get("duel_policy", "ACCEPT_IF_ADVANTAGE")))
		_select_option_by_raw(_stratagem_opt, str(_current_doctrine.get("stratagem_policy", "FIRE_OR_FLOOD")))
		_select_option_by_raw(_prisoner_opt, str(_current_doctrine.get("prisoner_policy", "RECRUIT_PERSUADE")))


func reset_view_state() -> void:
	_pawns_cache.clear()
	_selected_pawn_id = ""
	if _pawn_selector != null:
		_pawn_selector.clear()
	if _pawn_status_label != null:
		_pawn_status_label.text = "주군 조자룡 (주인공) · 직무: 대기 · 기분 55 · 충성 80% · 상태: 평온"
	if _pawn_stats_pill_label != null:
		_pawn_stats_pill_label.text = "통솔 64 · 무력 64 · 지력 64 · 정치 64 · 매력 64 | 특성: 의협 · 신중함"
	for dom: String in PawnEntity.WORK_DOMAINS:
		_update_priority_button_visuals(dom, 2)
	_current_schedule = [
		"SLEEP", "SLEEP", "SLEEP", "DRILL",
		"WORK", "WORK", "WORK", "WORK",
		"WORK", "RECREATION", "ANYTHING", "SLEEP"
	]
	for si: int in range(mini(12, _schedule_selectors.size())):
		var idx: int = PawnEntity.SHICHEN_ACTIVITIES.find(_current_schedule[si])
		if idx >= 0:
			_schedule_selectors[si].select(idx)
	_current_doctrine = ManorState.DEFAULT_DOCTRINE.duplicate(true)
	if _stance_opt != null:
		_select_option_by_raw(_stance_opt, str(_current_doctrine.get("engagement_stance", "DEFENSIVE_HOLD")))
	if _formation_opt != null:
		_select_option_by_raw(_formation_opt, str(_current_doctrine.get("formation", "SQUARE_SHIELD")))
	if _duel_opt != null:
		_select_option_by_raw(_duel_opt, str(_current_doctrine.get("duel_policy", "ACCEPT_IF_ADVANTAGE")))
	if _stratagem_opt != null:
		_select_option_by_raw(_stratagem_opt, str(_current_doctrine.get("stratagem_policy", "FIRE_OR_FLOOD")))
	if _prisoner_opt != null:
		_select_option_by_raw(_prisoner_opt, str(_current_doctrine.get("prisoner_policy", "RECRUIT_PERSUADE")))
