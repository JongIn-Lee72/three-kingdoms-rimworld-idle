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

var _assets: AssetRegistry = null
var _section_panels_slate: Array[PanelContainer] = []
var _section_panels_gold: Array[PanelContainer] = []
var _prio_icon: TextureRect = null
var _sched_icon: TextureRect = null
var _doctrine_icon: TextureRect = null

var _pawn_selector: OptionButton = null
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
	var slate_sb: StyleBoxTexture = _assets.build_panel_stylebox(false)
	var gold_sb: StyleBoxTexture = _assets.build_panel_stylebox(true)
	for p_slate: PanelContainer in _section_panels_slate:
		if p_slate != null:
			p_slate.add_theme_stylebox_override("panel", slate_sb)
	for p_gold: PanelContainer in _section_panels_gold:
		if p_gold != null:
			p_gold.add_theme_stylebox_override("panel", gold_sb)
	if _prio_icon != null:
		_prio_icon.texture = _assets.get_zone_tile("ZONE_WORKSHOP")
	if _sched_icon != null:
		_sched_icon.texture = _assets.get_resource_icon("HERBS_WINE")
	if _doctrine_icon != null:
		_doctrine_icon.texture = _assets.get_resource_icon("WEAPONS")


func _make_section_panel(parent: VBoxContainer, use_gold: bool) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inner: VBoxContainer = VBoxContainer.new()
	panel.add_child(inner)
	parent.add_child(panel)
	if use_gold:
		_section_panels_gold.append(panel)
	else:
		_section_panels_slate.append(panel)
	return inner


func _make_header_with_icon(parent: VBoxContainer, title_text: String) -> TextureRect:
	var row: HBoxContainer = HBoxContainer.new()
	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var hdr: Label = Label.new()
	hdr.text = title_text
	row.add_child(hdr)
	parent.add_child(row)
	return icon


func _build_ui() -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	var top_sec: VBoxContainer = _make_section_panel(root, false)
	var title: Label = Label.new()
	title.text = "업무 우선순위 (0..4) & 십이지시 일과표 & 상시 교전 수칙"
	top_sec.add_child(title)

	var pawn_row: HBoxContainer = HBoxContainer.new()
	var pawn_lbl: Label = Label.new()
	pawn_lbl.text = "대상 가신:"
	pawn_row.add_child(pawn_lbl)

	_pawn_selector = OptionButton.new()
	_pawn_selector.item_selected.connect(_on_pawn_selected)
	pawn_row.add_child(_pawn_selector)
	top_sec.add_child(pawn_row)

	# 7-domain 0..4 priority buttons
	var prio_sec: VBoxContainer = _make_section_panel(root, false)
	_prio_icon = _make_header_with_icon(prio_sec, "[7대 업무 우선순위 매트릭스 (0=금지, 1=최우선..4=후순위)]")

	for domain: String in PawnEntity.WORK_DOMAINS:
		var row: HBoxContainer = HBoxContainer.new()
		var dlbl: Label = Label.new()
		dlbl.text = domain
		dlbl.custom_minimum_size = Vector2(140, 0)
		row.add_child(dlbl)

		var btns: Array[Button] = []
		for prio: int in range(5):
			var b: Button = Button.new()
			b.text = str(prio)
			b.toggle_mode = true
			b.button_pressed = (prio == 2)
			b.pressed.connect(_on_priority_pressed.bind(domain, prio))
			row.add_child(b)
			btns.append(b)
		_priority_buttons[domain] = btns
		prio_sec.add_child(row)

	# 12-ShiChen schedule editor
	var sched_sec: VBoxContainer = _make_section_panel(root, false)
	_sched_icon = _make_header_with_icon(sched_sec, "[십이지시(12-ShiChen) 일과표]")

	var sched_grid: GridContainer = GridContainer.new()
	sched_grid.columns = 4
	sched_sec.add_child(sched_grid)

	for si: int in range(12):
		var cell: VBoxContainer = VBoxContainer.new()
		var slbl: Label = Label.new()
		slbl.text = SHICHEN_NAMES[si]
		cell.add_child(slbl)

		var opt: OptionButton = OptionButton.new()
		for act: String in PawnEntity.SHICHEN_ACTIVITIES:
			opt.add_item(act)
		var def_idx: int = PawnEntity.SHICHEN_ACTIVITIES.find(_current_schedule[si])
		if def_idx >= 0:
			opt.select(def_idx)
		opt.item_selected.connect(_on_schedule_slot_changed.bind(si))
		cell.add_child(opt)
		sched_grid.add_child(cell)
		_schedule_selectors.append(opt)

	_schedule_apply_btn = Button.new()
	_schedule_apply_btn.text = "일과표 전체 적용 (CMD_SET_SCHEDULE)"
	_schedule_apply_btn.pressed.connect(_on_apply_schedule_pressed)
	sched_sec.add_child(_schedule_apply_btn)

	# Standing Tactical Doctrine selector
	var doc_sec: VBoxContainer = _make_section_panel(root, true)
	_doctrine_icon = _make_header_with_icon(doc_sec, "[상시 교전 수칙 (Standing Tactical Doctrine)]")

	_stance_opt = _make_option_row(doc_sec, "교전 태세:", STANCE_OPTIONS)
	_formation_opt = _make_option_row(doc_sec, "기본 진형:", FORMATION_OPTIONS)
	_duel_opt = _make_option_row(doc_sec, "일기토 수칙:", DUEL_OPTIONS)
	_stratagem_opt = _make_option_row(doc_sec, "계략 방침:", STRATAGEM_OPTIONS)
	_prisoner_opt = _make_option_row(doc_sec, "포로 처우:", PRISONER_OPTIONS)

	_doctrine_apply_btn = Button.new()
	_doctrine_apply_btn.text = "교전 수칙 저장 (CMD_SET_DOCTRINE)"
	_doctrine_apply_btn.pressed.connect(_on_apply_doctrine_pressed)
	doc_sec.add_child(_doctrine_apply_btn)


func _make_option_row(parent: VBoxContainer, label_text: String, items: Array[String]) -> OptionButton:
	var row: HBoxContainer = HBoxContainer.new()
	var lbl: Label = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(140, 0)
	row.add_child(lbl)

	var opt: OptionButton = OptionButton.new()
	for it: String in items:
		opt.add_item(it)
	row.add_child(opt)
	parent.add_child(row)
	return opt


func _on_pawn_selected(index: int) -> void:
	if _pawn_selector != null and index >= 0 and index < _pawn_selector.item_count:
		_selected_pawn_id = _pawn_selector.get_item_text(index)
		_refresh_pawn_controls()


func _on_priority_pressed(domain: String, priority: int) -> void:
	set_work_priority_intent(_selected_pawn_id, domain, priority)


func set_work_priority_intent(pawn_id: String, domain: String, priority: int) -> void:
	var target_pid: String = pawn_id if not pawn_id.is_empty() else _selected_pawn_id
	if target_pid.is_empty():
		target_pid = "player_01_avatar"
	var clamped_prio: int = clampi(priority, 0, 4)
	_update_priority_button_visuals(domain, clamped_prio)
	intent_emitted.emit("CMD_SET_WORK_PRIORITY", {
		"pawn_id": target_pid,
		"domain": domain,
		"priority": clamped_prio
	})


func _on_schedule_slot_changed(item_idx: int, shichen_idx: int) -> void:
	if shichen_idx < 0 or shichen_idx >= 12:
		return
	if item_idx >= 0 and item_idx < PawnEntity.SHICHEN_ACTIVITIES.size():
		var act: String = PawnEntity.SHICHEN_ACTIVITIES[item_idx]
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


func _on_apply_doctrine_pressed() -> void:
	var stance: String = STANCE_OPTIONS[_stance_opt.selected] if _stance_opt.selected >= 0 and _stance_opt.selected < STANCE_OPTIONS.size() else "DEFENSIVE_HOLD"
	var formation: String = FORMATION_OPTIONS[_formation_opt.selected] if _formation_opt.selected >= 0 and _formation_opt.selected < FORMATION_OPTIONS.size() else "SQUARE_SHIELD"
	var duel: String = DUEL_OPTIONS[_duel_opt.selected] if _duel_opt.selected >= 0 and _duel_opt.selected < DUEL_OPTIONS.size() else "ACCEPT_IF_ADVANTAGE"
	var stratagem: String = STRATAGEM_OPTIONS[_stratagem_opt.selected] if _stratagem_opt.selected >= 0 and _stratagem_opt.selected < STRATAGEM_OPTIONS.size() else "FIRE_OR_FLOOD"
	var prisoner: String = PRISONER_OPTIONS[_prisoner_opt.selected] if _prisoner_opt.selected >= 0 and _prisoner_opt.selected < PRISONER_OPTIONS.size() else "RECRUIT_PERSUADE"
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


func _update_priority_button_visuals(domain: String, active_prio: int) -> void:
	var btns_v: Variant = _priority_buttons.get(domain, null)
	if btns_v is Array:
		var btns: Array = btns_v
		for p: int in range(btns.size()):
			var bv: Variant = btns[p]
			if bv is Button:
				var b: Button = bv
				b.set_pressed_no_signal(p == active_prio)


func _refresh_pawn_controls() -> void:
	var p_v: Variant = _pawns_cache.get(_selected_pawn_id, {})
	if not (p_v is Dictionary):
		return
	var pd: Dictionary = p_v
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


func _select_option_by_text(opt: OptionButton, text: String) -> void:
	for i: int in range(opt.item_count):
		if opt.get_item_text(i) == text:
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
	for pid: String in ordered_ids:
		_pawn_selector.add_item(pid)

	if not ordered_ids.is_empty():
		if _selected_pawn_id.is_empty() or not _pawns_cache.has(_selected_pawn_id):
			_selected_pawn_id = ordered_ids[0]
		var sel_idx: int = ordered_ids.find(_selected_pawn_id)
		if sel_idx >= 0:
			_pawn_selector.select(sel_idx)
		_refresh_pawn_controls()

	var doc_v: Variant = snapshot.get("standing_doctrine", {})
	if doc_v is Dictionary:
		var doc: Dictionary = doc_v
		for k: Variant in doc.keys():
			_current_doctrine[str(k)] = doc[k]
		_select_option_by_text(_stance_opt, str(_current_doctrine.get("engagement_stance", "DEFENSIVE_HOLD")))
		_select_option_by_text(_formation_opt, str(_current_doctrine.get("formation", "SQUARE_SHIELD")))
		_select_option_by_text(_duel_opt, str(_current_doctrine.get("duel_policy", "ACCEPT_IF_ADVANTAGE")))
		_select_option_by_text(_stratagem_opt, str(_current_doctrine.get("stratagem_policy", "FIRE_OR_FLOOD")))
		_select_option_by_text(_prisoner_opt, str(_current_doctrine.get("prisoner_policy", "RECRUIT_PERSUADE")))
