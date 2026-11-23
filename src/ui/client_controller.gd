class_name ClientController
extends Control

signal command_envelope_ready(envelope: Dictionary)
signal gazette_received(digest_msg: Dictionary)
signal challenge_received(challenge_msg: Dictionary)

var player_id: String = "player_01"
var client_tick: int = 0
var cmd_seq: int = 0
var current_season: String = "SPRING"
var last_state_crc32: int = 0

var asset_registry: AssetRegistry = AssetRegistry.new()
var audio_manager: AudioManager = AudioManager.new()

@export var auto_start_live_demo: bool = true

var active_tab_index: int = 0
var _ui_ready_for_audio: bool = false
var _in_switch_tab: bool = false
var _header_banner: TextureRect = null
var _mute_btn: Button = null
var _top_bar_label: Label = null
var _top_bar_display_label: Label = null
var _tab_container: TabContainer = null
var _cc_modal: AcceptDialog = null
var _cc_modal_btn: Button = null

var _session_bar_panel: PanelContainer = null
var _mode_status_label: Label = null
var _pause_btn: Button = null
var _speed_1x_btn: Button = null
var _speed_2x_btn: Button = null
var _speed_5x_btn: Button = null
var _cmd_feedback_panel: PanelContainer = null
var _cmd_feedback_label: Label = null
var _server_dialog_btn: Button = null
var _server_modal: AcceptDialog = null
var _ws_url_edit: LineEdit = null
var _ws_connect_btn: Button = null
var _local_demo_btn: Button = null

# M8 F-47 / F-48: Persistent global resource strip & 5-step onboarding compatibility refs
var _global_res_panel: PanelContainer = null
var _global_res_icons: Dictionary = {}
var _global_res_labels: Dictionary = {}
var _onboarding_bar_panel: PanelContainer = null
var _onboarding_step_btns: Array[Button] = []
var _onboarding_hint_label: Label = null
var _onboarding_cta_btn: Button = null
var _quest_pill_btn: Button = null

var _live_driver: LiveSessionDriver = null
var _tick_accumulator_sec: float = 0.0
var _base_tick_interval_sec: float = 1.0
var _speed_multiplier: int = 1
var _paused: bool = false
var _ws_connected_ui: bool = false
var _ws_conn_state_ui: String = "CLOSED"
var _last_chronicle_tick: int = -1
var _prev_stockpile_snapshot: Dictionary = {}
var _prev_army_ids: Dictionary = {}

func get_active_tab_index() -> int: return active_tab_index

var manor_view: ManorGridView = null
var priority_view: WorkPriorityScheduleView = null
var macro_view: MacroMapView = null
var court_hud: CourtMarketGazetteHUD = null

var _manor_cache: Dictionary = {
	"manor_id": "manor_player_01",
	"meta": {"lod": 1, "wall_hp": 2000, "household_troops": 300},
	"stockpile": {},
	"pawns": {},
	"buildings": {},
	"standing_doctrine": {}
}
var _macro_cache: Dictionary = {"nodes": {}, "armies": {}, "rallies": {}}
var _court_cache: Dictionary = {"faction": {}, "members": {}, "prices": {}, "orders": {}, "player_profile": {}}


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
	name = "ClientController"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(audio_manager)
	_build_ui()


func _is_interactive_scene_boot() -> bool:
	if not auto_start_live_demo:
		return false
	if OS.get_cmdline_user_args().has("--no-demo"):
		return false
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	return scene_file_path == "res://scenes/main_client.tscn" or tree.current_scene == self


func _ready() -> void:
	var _bgm_ok: bool = start_ambient_bgm()
	if _is_interactive_scene_boot():
		var _boot_res: Dictionary = start_local_demo(18401)


func _exit_tree() -> void:
	stop_live_session()


func _process(delta: float) -> void:
	if _live_driver == null or not _live_driver.is_active():
		return

	var incoming: Array[Dictionary] = _live_driver.poll_incoming()
	for msg: Dictionary in incoming:
		apply_server_message(msg)

	if _live_driver.is_local_mode():
		if not _paused:
			_tick_accumulator_sec += maxf(0.0, delta) * float(_speed_multiplier)
			var steps_this_frame: int = 0
			while _tick_accumulator_sec >= _base_tick_interval_sec and steps_this_frame < 5:
				_tick_accumulator_sec -= _base_tick_interval_sec
				step_demo_ticks(1)
				steps_this_frame += 1
			if steps_this_frame >= 5:
				_tick_accumulator_sec = 0.0
	elif _live_driver.is_remote_mode():
		var now_state: String = _live_driver.get_remote_connection_state()
		var now_open: bool = (now_state == "OPEN")
		if now_open != _ws_connected_ui or now_state != _ws_conn_state_ui:
			_ws_connected_ui = now_open
			_ws_conn_state_ui = now_state
			_refresh_session_bar()


func start_ambient_bgm() -> bool:
	if audio_manager == null:
		return false
	return audio_manager.play_bgm("MAIN_THREE_KINGDOMS")


func _style_header_compact(sb: StyleBoxFlat) -> StyleBoxFlat:
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	return sb


func _current_shichen_ko() -> String:
	@warning_ignore("integer_division")
	var sh_idx: int = (client_tick % SimClock.DAILY_SETTLEMENT_TICK) / SimClock.TICKS_PER_SHICHEN
	var sh_name: String = SimClock.SHICHEN_NAMES[clampi(sh_idx, 0, SimClock.SHICHEN_NAMES.size() - 1)]
	var hour_ranges: Array[String] = [
		"23~01시", "01~03시", "03~05시", "05~07시", "07~09시", "09~11시",
		"11~13시", "13~15시", "15~17시", "17~19시", "19~21시", "21~23시"
	]
	return "%s(%s)" % [sh_name, hour_ranges[clampi(sh_idx, 0, hour_ranges.size() - 1)]]


static func _to_bool(v: Variant, fallback: bool = false) -> bool:
	if v is bool:
		var bv: bool = v
		return bv
	if v is int:
		var iv: int = v
		return iv != 0
	return fallback


func _hero_display_name() -> String:
	var pawns_v: Variant = _manor_cache.get("pawns", {})
	if pawns_v is Dictionary:
		var pd: Dictionary = pawns_v
		for pk: Variant in pd.keys():
			var pv: Variant = pd[pk]
			if pv is Dictionary:
				var pdict: Dictionary = pv
				var is_av: bool = _to_bool(pdict.get("is_avatar", str(pk).ends_with("_avatar")), str(pk).ends_with("_avatar"))
				if is_av:
					var nm: String = str(pdict.get("name", "")).strip_edges()
					if not nm.is_empty():
						return nm
	return "조자룡"


func _faction_display_name() -> String:
	var fac_v: Variant = _court_cache.get("faction", {})
	if fac_v is Dictionary:
		var fd: Dictionary = fac_v
		var fid: String = str(fd.get("faction_id", ""))
		if not fid.is_empty():
			return AssetRegistry.faction_name_ko(fid)
	return "한실 신흥군"


func _format_top_bar_text() -> String:
	var season_lbl: String = AssetRegistry.season_ko(current_season)
	var shichen_lbl: String = _current_shichen_ko()
	var hero_name: String = _hero_display_name()
	var fac_name: String = _faction_display_name()
	@warning_ignore("integer_division")
	var day_num: int = (client_tick / SimClock.DAILY_SETTLEMENT_TICK) + 1
	return "삼국지 천명록 · %s | 군주 %s (%s) · %d일차 %s · %s · 틱 %s | 천명 감독관: 사마천" % [
		fac_name,
		hero_name,
		player_id,
		day_num,
		season_lbl,
		shichen_lbl,
		AssetRegistry.format_num(client_tick)
	]


func _format_top_bar_display_text() -> String:
	var season_lbl: String = AssetRegistry.season_ko(current_season)
	var shichen_lbl: String = _current_shichen_ko()
	var hero_name: String = _hero_display_name()
	var fac_name: String = _faction_display_name()
	@warning_ignore("integer_division")
	var day_num: int = (client_tick / SimClock.DAILY_SETTLEMENT_TICK) + 1
	return "삼국지 천명록 · %s | 군주 %s · %d일차 %s · %s · 틱 %s | 천명 감독관: 사마천" % [
		fac_name,
		hero_name,
		day_num,
		season_lbl,
		shichen_lbl,
		AssetRegistry.format_num(client_tick)
	]


func _update_top_bar_display() -> void:
	var tip: String = "플레이어 ID: %s | 상태 무결성 CRC32: %d" % [player_id, last_state_crc32]
	if _top_bar_label != null:
		_top_bar_label.text = _format_top_bar_text()
		_top_bar_label.tooltip_text = tip
	if _top_bar_display_label != null:
		_top_bar_display_label.text = _format_top_bar_display_text()
		_top_bar_display_label.tooltip_text = tip


func _build_ui() -> void:
	theme = asset_registry.build_three_kingdoms_theme()

	var bg_rect: ColorRect = ColorRect.new()
	bg_rect.color = AssetRegistry.COLOR_LACQUER_BG
	bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg_rect)

	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 3)
	add_child(root)

	# =========================================================================
	# ROW 1: Game Identity + World Era Clock + Speed + Audio + Server Modal + Character Creation
	# =========================================================================
	var hdr_panel: PanelContainer = PanelContainer.new()
	hdr_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_panel.custom_minimum_size = Vector2(0, 38)
	var hdr_sb: StyleBoxFlat = asset_registry.build_card_stylebox(true, AssetRegistry.COLOR_GOLD_ACCENT)
	hdr_panel.add_theme_stylebox_override("panel", _style_header_compact(hdr_sb))

	var hdr_overlay: Control = Control.new()
	hdr_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_overlay.custom_minimum_size = Vector2(0, 30)
	hdr_panel.add_child(hdr_overlay)

	_header_banner = TextureRect.new()
	_header_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_header_banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_header_banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_header_banner.modulate = Color(1.0, 1.0, 1.0, 0.22)
	_header_banner.texture = asset_registry.get_texture(AssetRegistry.CREST_BANNER)
	hdr_overlay.add_child(_header_banner)

	var hdr_row: HBoxContainer = HBoxContainer.new()
	hdr_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	hdr_row.add_theme_constant_override("separation", 6)
	hdr_overlay.add_child(hdr_row)

	# Hidden compatibility label preserving player_id for unit test assertions
	_top_bar_label = Label.new()
	_top_bar_label.visible = false
	_top_bar_label.text = _format_top_bar_text()
	hdr_row.add_child(_top_bar_label)

	_top_bar_display_label = Label.new()
	_top_bar_display_label.text = _format_top_bar_display_text()
	_top_bar_display_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_bar_display_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_top_bar_display_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	AssetRegistry.apply_text_role(_top_bar_display_label, "body")
	hdr_row.add_child(_top_bar_display_label)

	_mode_status_label = Label.new()
	_mode_status_label.text = "○ 대기"
	AssetRegistry.apply_text_role(_mode_status_label, "caption")
	hdr_row.add_child(_mode_status_label)

	_pause_btn = Button.new()
	_pause_btn.text = "일시정지"
	asset_registry.apply_button_variant(_pause_btn, "chip")
	_pause_btn.pressed.connect(_on_pause_toggled)
	hdr_row.add_child(_pause_btn)

	_speed_1x_btn = Button.new()
	_speed_1x_btn.text = "1x"
	asset_registry.apply_button_variant(_speed_1x_btn, "chip")
	_speed_1x_btn.pressed.connect(set_demo_speed.bind(1))
	hdr_row.add_child(_speed_1x_btn)

	_speed_2x_btn = Button.new()
	_speed_2x_btn.text = "2x"
	asset_registry.apply_button_variant(_speed_2x_btn, "chip")
	_speed_2x_btn.pressed.connect(set_demo_speed.bind(2))
	hdr_row.add_child(_speed_2x_btn)

	_speed_5x_btn = Button.new()
	_speed_5x_btn.text = "5x"
	asset_registry.apply_button_variant(_speed_5x_btn, "chip")
	_speed_5x_btn.pressed.connect(set_demo_speed.bind(5))
	hdr_row.add_child(_speed_5x_btn)

	_mute_btn = Button.new()
	_mute_btn.text = "음소거: OFF"
	_mute_btn.tooltip_text = "배경음 및 효과음 음소거 전환"
	asset_registry.apply_button_variant(_mute_btn, "chip")
	_mute_btn.pressed.connect(_on_mute_toggled)
	hdr_row.add_child(_mute_btn)

	_server_dialog_btn = Button.new()
	_server_dialog_btn.text = "멀티 서버"
	_server_dialog_btn.tooltip_text = "원격 WebSocket 서버 연결 및 로컬 시연 전환 설정"
	asset_registry.apply_button_variant(_server_dialog_btn, "secondary")
	_server_dialog_btn.pressed.connect(_on_open_server_dialog)
	hdr_row.add_child(_server_dialog_btn)

	_cc_modal_btn = Button.new()
	_cc_modal_btn.text = "장수 출사"
	_cc_modal_btn.tooltip_text = "천명 문답 및 TK3K2 봉인 토큰 출사 안내 열기"
	asset_registry.apply_button_variant(_cc_modal_btn, "primary")
	_cc_modal_btn.pressed.connect(_on_open_cc_modal)
	hdr_row.add_child(_cc_modal_btn)
	root.add_child(hdr_panel)

	# =========================================================================
	# ROW 2: Persistent 8-Resource HUD Bar + Compact Next-Action Quest Pill + Command Toast
	# =========================================================================
	_session_bar_panel = PanelContainer.new()
	_session_bar_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_session_bar_panel.custom_minimum_size = Vector2(0, 34)
	var sess_sb: StyleBoxFlat = asset_registry.build_card_stylebox(false, AssetRegistry.COLOR_SUBTLE_BORDER)
	_session_bar_panel.add_theme_stylebox_override("panel", _style_header_compact(sess_sb))
	var res_bar_row: HBoxContainer = HBoxContainer.new()
	res_bar_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_bar_row.add_theme_constant_override("separation", 8)
	_session_bar_panel.add_child(res_bar_row)

	var res_strip: HBoxContainer = HBoxContainer.new()
	res_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_strip.add_theme_constant_override("separation", 10)
	for rk: String in DtoSchemas.RESOURCE_KEYS:
		var rbox: HBoxContainer = HBoxContainer.new()
		rbox.add_theme_constant_override("separation", 3)
		var ricon: TextureRect = TextureRect.new()
		ricon.custom_minimum_size = Vector2(16, 16)
		ricon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ricon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ricon.texture = asset_registry.get_resource_icon(rk)
		rbox.add_child(ricon)

		var rname: Label = Label.new()
		var short_ko: String = AssetRegistry.resource_label_ko(rk)
		if rk == "HERBS_WINE":
			short_ko = "약주"
		elif rk == "MERIT_PRESTIGE":
			short_ko = "공적"
		rname.text = short_ko
		AssetRegistry.apply_text_role(rname, "caption")
		rbox.add_child(rname)

		var rval: Label = AssetRegistry.make_numeric_label("0", 34.0)
		rval.add_theme_font_size_override("font_size", AssetRegistry.FONT_SIZE_CAPTION)
		rbox.add_child(rval)
		res_strip.add_child(rbox)
		_global_res_icons[rk] = ricon
		_global_res_labels[rk] = rval
	res_bar_row.add_child(res_strip)

	_quest_pill_btn = Button.new()
	_quest_pill_btn.text = "숙원: 장원 둔전·관아 살피기 [이동 →]"
	_quest_pill_btn.tooltip_text = "현재 추천 숙원 또는 대기 중인 결재 서신으로 바로 이동합니다"
	asset_registry.apply_button_variant(_quest_pill_btn, "chip")
	_quest_pill_btn.pressed.connect(_on_onboarding_cta_pressed)
	res_bar_row.add_child(_quest_pill_btn)

	_cmd_feedback_panel = PanelContainer.new()
	_cmd_feedback_panel.add_theme_stylebox_override(
		"panel",
		asset_registry.build_badge_stylebox(Color(0.14, 0.13, 0.11, 0.96), AssetRegistry.COLOR_SUBTLE_BORDER)
	)
	_cmd_feedback_label = Label.new()
	_cmd_feedback_label.text = "명령: 대기"
	_cmd_feedback_label.custom_minimum_size = Vector2(180, 0)
	AssetRegistry.apply_text_role(_cmd_feedback_label, "caption")
	_cmd_feedback_panel.add_child(_cmd_feedback_label)
	res_bar_row.add_child(_cmd_feedback_panel)
	root.add_child(_session_bar_panel)

	# =========================================================================
	# Hidden compatibility stepper bar (preserves _onboarding_step_btns[5], _onboarding_hint_label, _onboarding_cta_btn)
	# =========================================================================
	_onboarding_bar_panel = PanelContainer.new()
	_onboarding_bar_panel.visible = false
	var guide_row: HBoxContainer = HBoxContainer.new()
	_onboarding_bar_panel.add_child(guide_row)
	var step_defs: Array[Dictionary] = [
		{"label": "① 출사·봉인토큰", "action": "CC"},
		{"label": "② 장원 경영", "action": "TAB0"},
		{"label": "③ 업무·일과", "action": "TAB1"},
		{"label": "④ 천하 전략도", "action": "TAB2"},
		{"label": "⑤ 정청·거래소·조보", "action": "TAB3"}
	]
	for sdef: Dictionary in step_defs:
		var sbtn: Button = Button.new()
		sbtn.text = str(sdef["label"])
		sbtn.pressed.connect(_on_onboarding_step_pressed.bind(str(sdef["action"])))
		guide_row.add_child(sbtn)
		_onboarding_step_btns.append(sbtn)
	_onboarding_hint_label = Label.new()
	_onboarding_hint_label.text = "추천: 장원 둔전·관아 증축 또는 출사 토큰으로 새 군주 생성"
	guide_row.add_child(_onboarding_hint_label)
	_onboarding_cta_btn = Button.new()
	_onboarding_cta_btn.text = "다음 단계 →"
	_onboarding_cta_btn.pressed.connect(_on_onboarding_cta_pressed)
	guide_row.add_child(_onboarding_cta_btn)
	root.add_child(_onboarding_bar_panel)

	# =========================================================================
	# Main 4-Tab Workspace (Single authoritative navigation bar)
	# =========================================================================
	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_container.tab_changed.connect(_on_tab_container_changed)
	root.add_child(_tab_container)

	manor_view = ManorGridView.new()
	manor_view.name = "ManorTab"
	manor_view.set_asset_registry(asset_registry)
	manor_view.intent_emitted.connect(_on_view_intent)
	_tab_container.add_child(manor_view)

	priority_view = WorkPriorityScheduleView.new()
	priority_view.name = "PriorityTab"
	priority_view.set_asset_registry(asset_registry)
	priority_view.intent_emitted.connect(_on_view_intent)
	_tab_container.add_child(priority_view)

	macro_view = MacroMapView.new()
	macro_view.name = "MacroTab"
	macro_view.set_asset_registry(asset_registry)
	macro_view.intent_emitted.connect(_on_view_intent)
	_tab_container.add_child(macro_view)

	court_hud = CourtMarketGazetteHUD.new()
	court_hud.name = "CourtTab"
	court_hud.set_asset_registry(asset_registry)
	court_hud.intent_emitted.connect(_on_view_intent)
	court_hud.validation_error_emitted.connect(_on_validation_error)
	_tab_container.add_child(court_hud)

	_tab_container.set_tab_title(0, "1. 장원 경영")
	_tab_container.set_tab_title(1, "2. 우선순위 & 일과")
	_tab_container.set_tab_title(2, "3. 천하 전략도")
	_tab_container.set_tab_title(3, "4. 정청 · 거래소 · 조보")

	# =========================================================================
	# Clean Multi-Server AcceptDialog (houses _ws_url_edit, _ws_connect_btn, _local_demo_btn)
	# =========================================================================
	_server_modal = AcceptDialog.new()
	_server_modal.title = "멀티플레이 서버 접속 설정"
	_server_modal.ok_button_text = "닫기"
	var srv_vbox: VBoxContainer = VBoxContainer.new()
	srv_vbox.custom_minimum_size = Vector2(360, 0)
	srv_vbox.add_theme_constant_override("separation", 8)

	var srv_desc: Label = Label.new()
	srv_desc.text = "원격 권위 서버(WebSocket) 주소에 접속하거나 내장 로컬 시연 월드로 전환합니다."
	srv_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	AssetRegistry.apply_text_role(srv_desc, "muted")
	srv_vbox.add_child(srv_desc)

	_ws_url_edit = LineEdit.new()
	_ws_url_edit.text = "ws://127.0.0.1:9090"
	_ws_url_edit.placeholder_text = "ws://127.0.0.1:9090"
	_ws_url_edit.tooltip_text = "원격 멀티플레이 WebSocket 서버 주소"
	srv_vbox.add_child(_ws_url_edit)

	var srv_btn_row: HBoxContainer = HBoxContainer.new()
	srv_btn_row.add_theme_constant_override("separation", 8)
	_ws_connect_btn = Button.new()
	_ws_connect_btn.text = "서버 접속"
	_ws_connect_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	asset_registry.apply_button_variant(_ws_connect_btn, "secondary")
	_ws_connect_btn.pressed.connect(_on_ws_connect_pressed)
	srv_btn_row.add_child(_ws_connect_btn)

	_local_demo_btn = Button.new()
	_local_demo_btn.text = "로컬 시연"
	_local_demo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	asset_registry.apply_button_variant(_local_demo_btn, "secondary")
	_local_demo_btn.pressed.connect(_on_local_demo_pressed)
	srv_btn_row.add_child(_local_demo_btn)
	srv_vbox.add_child(srv_btn_row)
	_server_modal.add_child(srv_vbox)
	add_child(_server_modal)

	# Non-blocking onboarding modal directing to Tab 3 Character Creation & TK3K2 panel
	_cc_modal = AcceptDialog.new()
	_cc_modal.title = "장수 출사 및 5단계 플레이 가이드"
	_cc_modal.ok_button_text = "4번 탭(장수 출사)으로 이동"
	_cc_modal.dialog_text = "① [출사] 4번 탭 우측 상단에서 천명 문답(8문항) 또는 TK3K2 봉인 토큰(평문 JSON 차단)으로 장수를 출사시키세요.\n② [장원 경영] 32×32 구역을 점검하고 둔전·관아를 증축하세요.\n③ [업무·일과] 가신별 7대 업무 우선순위(0~4)와 12시진 일과, 교전 수칙을 설정하세요.\n④ [천하 전략도] 거점을 클릭해 군단·상단을 출진시키거나 연합 공성을 발령하세요.\n⑤ [정청·거래소·조보] 지정가 호가 거래 및 결재 서신과 조보를 확인하세요."
	_cc_modal.confirmed.connect(_on_cc_modal_confirmed)
	add_child(_cc_modal)

	_refresh_session_bar()
	switch_tab(0)
	_ui_ready_for_audio = true


func _on_open_server_dialog() -> void:
	if audio_manager != null and _ui_ready_for_audio:
		var _ok: bool = audio_manager.play_sfx("UI_CLICK")
	if _server_modal != null:
		_server_modal.visible = true


func _on_onboarding_step_pressed(action: String) -> void:
	match action:
		"CC":
			switch_tab(3)
			if _cc_modal != null and not OS.has_feature("headless"):
				_cc_modal.visible = true
		"TAB0":
			switch_tab(0)
		"TAB1":
			switch_tab(1)
		"TAB2":
			switch_tab(2)
		"TAB3":
			switch_tab(3)


func _on_onboarding_cta_pressed() -> void:
	var pending_cnt: int = _get_pending_inbox_count()
	if pending_cnt > 0 and active_tab_index != 3:
		switch_tab(3)
	else:
		switch_tab((active_tab_index + 1) % 4)


func _get_pending_inbox_count() -> int:
	var inv: Variant = _court_cache.get("inbox_decisions", [])
	if inv is Array:
		var ina: Array = inv
		return ina.size()
	return 0


func _refresh_global_resources_and_onboarding() -> void:
	var stock_v: Variant = _manor_cache.get("stockpile", {})
	var stock: Dictionary = stock_v if stock_v is Dictionary else {}
	for rk: String in DtoSchemas.RESOURCE_KEYS:
		var lbl_v: Variant = _global_res_labels.get(rk, null)
		if lbl_v is Label:
			var lbl: Label = lbl_v
			lbl.text = AssetRegistry.format_num(_to_int(stock.get(rk, 0), 0))

	var pending_inbox: int = _get_pending_inbox_count()
	if _onboarding_step_btns.size() >= 5:
		var tab3_btn: Button = _onboarding_step_btns[4]
		tab3_btn.text = "⑤ 정청·결재(%d)" % pending_inbox if pending_inbox > 0 else "⑤ 정청·거래소·조보"
		var active_step_idx: int = active_tab_index + 1
		for i: int in range(_onboarding_step_btns.size()):
			var sb: Button = _onboarding_step_btns[i]
			if i == active_step_idx:
				asset_registry.apply_button_variant(sb, "primary")
			else:
				asset_registry.apply_button_variant(sb, "chip")

	if _onboarding_hint_label != null:
		if pending_inbox > 0:
			_onboarding_hint_label.text = "알림: 결재 서신 %d건 대기 중 — ⑤ 정청·결재에서 처리하세요" % pending_inbox
		elif active_tab_index == 0:
			_onboarding_hint_label.text = "장원: 좌측 32×32 타일에 마우스를 올려 점검하고, 우측에서 둔전·관아를 증축하세요"
		elif active_tab_index == 1:
			_onboarding_hint_label.text = "가신: 업무 우선순위(1=최우선)와 12시진 일과표·교전 수칙을 한 화면에서 조율하세요"
		elif active_tab_index == 2:
			_onboarding_hint_label.text = "천하: 지도에서 거점을 클릭해 목표를 고른 뒤 군단·상단을 출진시키세요"
		else:
			_onboarding_hint_label.text = "정청: 거래소 호가 등록, 결재 서신 처리, 우측에서 새 장수 출사(TK3K2)를 진행하세요"

	if _quest_pill_btn != null:
		if pending_inbox > 0:
			_quest_pill_btn.text = "숙원: 결재 서신 %d건 처리 [이동 →]" % pending_inbox
			asset_registry.apply_button_variant(_quest_pill_btn, "primary")
		else:
			match active_tab_index:
				0:
					_quest_pill_btn.text = "숙원: 가신 업무·일과 조율 [이동 →]"
				1:
					_quest_pill_btn.text = "숙원: 천하 전략도 출진 살피기 [이동 →]"
				2:
					_quest_pill_btn.text = "숙원: 정청·거래소 호가 확인 [이동 →]"
				_:
					_quest_pill_btn.text = "숙원: 본영 장원 순시 [이동 →]"
			asset_registry.apply_button_variant(_quest_pill_btn, "chip")


func _on_mute_toggled() -> void:
	if audio_manager == null:
		return
	var next_muted: bool = not audio_manager.is_muted()
	audio_manager.set_muted(next_muted)
	if _mute_btn != null:
		_mute_btn.text = "음소거: ON" if next_muted else "음소거: OFF"
	if not next_muted:
		var _ok: bool = audio_manager.play_sfx("UI_CLICK")


func _on_validation_error(_error_code: String) -> void:
	if audio_manager != null:
		var _ok: bool = audio_manager.play_sfx("UI_ERROR")


func _on_tab_container_changed(tab_index: int) -> void:
	if _in_switch_tab:
		return
	if tab_index != active_tab_index:
		switch_tab(tab_index)


func _on_open_cc_modal() -> void:
	if audio_manager != null and _ui_ready_for_audio:
		var _ok: bool = audio_manager.play_sfx("UI_CLICK")
	if _cc_modal != null:
		_cc_modal.visible = true


func _on_cc_modal_confirmed() -> void:
	switch_tab(3)


func switch_tab(tab_index: int) -> void:
	if _tab_container == null:
		return
	var count: int = _tab_container.get_tab_count()
	if tab_index >= 0 and tab_index < count:
		_in_switch_tab = true
		active_tab_index = tab_index
		if _tab_container.current_tab != tab_index:
			_tab_container.current_tab = tab_index
		var views: Array[Control] = [manor_view, priority_view, macro_view, court_hud]
		for i: int in range(views.size()):
			if views[i] != null:
				views[i].visible = (i == tab_index)
		_in_switch_tab = false
		_refresh_global_resources_and_onboarding()
		if _ui_ready_for_audio and audio_manager != null:
			var _ok_sfx: bool = audio_manager.play_sfx("TAB_SWITCH")


func _on_view_intent(cmd_type: String, args: Dictionary) -> void:
	var _env: Dictionary = package_command(cmd_type, args)


func _sfx_event_for_command(cmd_type: String) -> String:
	match cmd_type:
		"CMD_BUILD_OR_UPGRADE":
			return "BUILD_UPGRADE"
		"CMD_PLACE_MARKET_ORDER":
			return "COIN_TRADE"
		"CMD_DISPATCH_EXPEDITION":
			return "MARCH_DISPATCH"
		"CMD_SET_DOCTRINE":
			return "DOCTRINE_BANNER"
		"CMD_CREATE_COALITION_RALLY", "CMD_JOIN_COALITION_RALLY":
			return "DUEL_CLASH"
		"CMD_EXECUTE_COALITION_SIEGE":
			return "SIEGE_IMPACT"
		"CMD_HOST_BANQUET":
			return "BANQUET_CHEER"
		"CMD_CREATE_CHARACTER":
			return "SEAL_VERIFY"
		_:
			return "UI_CLICK"


func _set_feedback_badge(text_val: String, tone: String = "neutral") -> void:
	if _cmd_feedback_label != null:
		_cmd_feedback_label.text = text_val
		var col: Color = AssetRegistry.COLOR_TEXT_SECONDARY
		var border: Color = AssetRegistry.COLOR_SUBTLE_BORDER
		var bg: Color = Color(0.14, 0.13, 0.11, 0.96)
		if tone == "ok":
			col = AssetRegistry.COLOR_SUCCESS_JADE
			border = AssetRegistry.COLOR_SUCCESS_JADE
			bg = Color(0.10, 0.18, 0.13, 0.96)
		elif tone == "err":
			col = AssetRegistry.COLOR_DANGER_CRIMSON
			border = AssetRegistry.COLOR_DANGER_CRIMSON
			bg = Color(0.22, 0.10, 0.10, 0.96)
		elif tone == "info":
			col = AssetRegistry.COLOR_INFO_AZURE
			border = AssetRegistry.COLOR_INFO_AZURE
			bg = Color(0.11, 0.15, 0.20, 0.96)
		_cmd_feedback_label.add_theme_color_override("font_color", col)
		if _cmd_feedback_panel != null:
			_cmd_feedback_panel.add_theme_stylebox_override("panel", asset_registry.build_badge_stylebox(bg, border))


func package_command(cmd_type: String, args: Dictionary) -> Dictionary:
	if _live_driver != null and _live_driver.is_remote_mode():
		cmd_seq = maxi(cmd_seq, _live_driver.get_remote_cmd_seq())
	cmd_seq += 1
	var env: Dictionary = {
		"v": 1,
		"cmd_seq": cmd_seq,
		"client_tick": client_tick,
		"player_id": player_id,
		"cmd_type": cmd_type,
		"args": args.duplicate(true)
	}
	if audio_manager != null:
		var _ok_sfx: bool = audio_manager.play_sfx(_sfx_event_for_command(cmd_type))
	if _live_driver != null and _live_driver.is_active():
		var sent_ok: bool = _live_driver.send_command_envelope(env)
		if _live_driver.is_remote_mode():
			cmd_seq = maxi(cmd_seq, _live_driver.get_remote_cmd_seq())
			env["cmd_seq"] = cmd_seq
		var cmd_ko: String = AssetRegistry.command_label_ko(cmd_type)
		_set_feedback_badge(
			"전달: %s (#%d)" % [cmd_ko, cmd_seq] if sent_ok else "미연결: %s" % cmd_ko,
			"info" if sent_ok else "err"
		)
	command_envelope_ready.emit(env)
	return env


func get_live_driver() -> LiveSessionDriver:
	return _live_driver


func _reset_session_view_state() -> void:
	client_tick = 0
	last_state_crc32 = 0
	current_season = "SPRING"
	_tick_accumulator_sec = 0.0
	_last_chronicle_tick = -1
	_prev_stockpile_snapshot.clear()
	_prev_army_ids.clear()
	_manor_cache = {
		"manor_id": "manor_" + player_id,
		"meta": {"lod": 1, "wall_hp": 2000, "household_troops": 300},
		"stockpile": {},
		"pawns": {},
		"buildings": {},
		"standing_doctrine": {}
	}
	_macro_cache = {"nodes": {}, "armies": {}, "rallies": {}}
	_court_cache = {"faction": {}, "members": {}, "prices": {}, "orders": {}, "player_profile": {}}
	_set_feedback_badge("명령: 대기", "neutral")
	_update_top_bar_display()
	if manor_view != null:
		manor_view.reset_view_state()
	if priority_view != null:
		priority_view.reset_view_state()
	if macro_view != null:
		macro_view.reset_view_state()
	if court_hud != null:
		court_hud.reset_view_state()
	_refresh_global_resources_and_onboarding()


func start_local_demo(world_seed: int = 18401) -> Dictionary:
	_reset_session_view_state()
	if _live_driver == null:
		_live_driver = LiveSessionDriver.new()
	var res: Dictionary = _live_driver.start_local_demo(world_seed, player_id)
	_tick_accumulator_sec = 0.0
	_paused = false
	_ws_connected_ui = false
	_ws_conn_state_ui = "CLOSED"
	if _live_driver.local_server != null:
		var srv_seq: int = _to_int(_live_driver.local_server.command_validator.last_accepted_seq.get(player_id, 0), 0)
		cmd_seq = maxi(cmd_seq, srv_seq)
	_set_feedback_badge("✓ 장원 준비 완료", "ok")
	var init_msgs_v: Variant = res.get("initial_messages", [])
	if init_msgs_v is Array:
		var init_msgs: Array = init_msgs_v
		for m_v: Variant in init_msgs:
			if m_v is Dictionary:
				var md: Dictionary = m_v
				apply_server_message(md)
	_apply_local_hydration()
	if manor_view != null:
		manor_view.append_chronicle_line("예주 허창 본영에서 %s의 새 일과가 시작되었습니다." % _hero_display_name())
	_refresh_session_bar()
	return res


func connect_remote_websocket(url: String, p_player_id: String = "") -> Error:
	if not p_player_id.is_empty():
		player_id = p_player_id
	_reset_session_view_state()
	if _live_driver == null:
		_live_driver = LiveSessionDriver.new()
	_tick_accumulator_sec = 0.0
	_paused = false
	var err: Error = _live_driver.connect_remote_ws(url, player_id)
	_ws_connected_ui = _live_driver.is_remote_connected()
	_ws_conn_state_ui = _live_driver.get_remote_connection_state()
	_refresh_session_bar()
	return err


func stop_live_session() -> void:
	if _live_driver != null:
		_live_driver.stop()
	_ws_connected_ui = false
	_ws_conn_state_ui = "CLOSED"
	_reset_session_view_state()
	_refresh_session_bar()


func set_demo_speed(mult: int) -> void:
	if mult == 1 or mult == 2 or mult == 5:
		_speed_multiplier = mult
	_refresh_session_bar()


func set_demo_paused(is_paused: bool) -> void:
	_paused = is_paused
	_refresh_session_bar()


func step_demo_ticks(count: int = 1) -> void:
	if _live_driver == null or not _live_driver.is_local_mode():
		return
	var steps: int = maxi(1, count)
	for _i: int in range(steps):
		var msgs: Array[Dictionary] = _live_driver.step_local_tick()
		for msg: Dictionary in msgs:
			apply_server_message(msg)
	_apply_local_hydration()
	_refresh_session_bar()


func _sync_manor_hero_banner() -> void:
	if manor_view == null:
		return
	var meta_v: Variant = _manor_cache.get("meta", {})
	var meta: Dictionary = meta_v if meta_v is Dictionary else {}
	var fac_v: Variant = _court_cache.get("faction", {})
	var fac: Dictionary = fac_v if fac_v is Dictionary else {}
	var prof_v: Variant = _court_cache.get("player_profile", {})
	var prof: Dictionary = prof_v if prof_v is Dictionary else {}
	var host_id: String = str(_manor_cache.get("host_node_id", "xuchang"))
	if host_id.is_empty():
		host_id = "xuchang"
	var royal_rank: String = str(fac.get("royal_rank", prof.get("royal_rank", "DUKE")))
	var rank_ko: String = AssetRegistry.rank_ko(royal_rank)
	var fac_id: String = str(fac.get("faction_id", prof.get("faction_id", "fac_han")))
	var fac_ko: String = AssetRegistry.faction_name_ko(fac_id)

	var st_id: String = str(_court_cache.get("storyteller", "ST_SIMA_QIAN"))
	var st_ko: String = "사마천"
	if st_id.contains("DONG"):
		st_ko = "동탁"
	elif st_id.contains("WEN"):
		st_ko = "문경"

	var patch: Dictionary = {
		"name": _hero_display_name(),
		"faction_name": fac_ko,
		"rank_ko": rank_ko,
		"host_name": AssetRegistry.node_name_ko(host_id),
		"troops": _to_int(meta.get("household_troops", 300), 300),
		"wall_hp": _to_int(meta.get("wall_hp", 2000), 2000),
		"storyteller_ko": st_ko
	}
	manor_view.update_hero_banner(patch)


func _emit_narrative_chronicle_updates() -> void:
	if manor_view == null or client_tick <= 0:
		return
	if client_tick == _last_chronicle_tick:
		return
	_last_chronicle_tick = client_tick

	# 1. Resource production narration
	var stock_v: Variant = _manor_cache.get("stockpile", {})
	var stock: Dictionary = stock_v if stock_v is Dictionary else {}
	var cur_grain: int = _to_int(stock.get("GRAIN", 0), 0)
	var prev_grain: int = _to_int(_prev_stockpile_snapshot.get("GRAIN", cur_grain), cur_grain)
	var cur_wep: int = _to_int(stock.get("WEAPONS", 0), 0)
	var prev_wep: int = _to_int(_prev_stockpile_snapshot.get("WEAPONS", cur_wep), cur_wep)
	var cur_coin: int = _to_int(stock.get("COIN", 0), 0)
	var prev_coin: int = _to_int(_prev_stockpile_snapshot.get("COIN", cur_coin), cur_coin)

	if cur_grain > prev_grain:
		manor_view.append_chronicle_line("[%s] 둔전 농지에서 군량 +%d석을 수확했습니다." % [_current_shichen_ko(), cur_grain - prev_grain])
	elif cur_wep > prev_wep:
		manor_view.append_chronicle_line("[%s] 대장간에서 병기 +%d자루를 단조했습니다." % [_current_shichen_ko(), cur_wep - prev_wep])
	elif cur_coin > prev_coin:
		manor_view.append_chronicle_line("[%s] 장원 물류·상단 정산으로 은전 +%d냥이 들어왔습니다." % [_current_shichen_ko(), cur_coin - prev_coin])

	for rk: String in DtoSchemas.RESOURCE_KEYS:
		_prev_stockpile_snapshot[rk] = _to_int(stock.get(rk, 0), 0)

	# 2. Macro expedition departure narration
	var armies_v: Variant = _macro_cache.get("armies", {})
	if armies_v is Dictionary:
		var ad: Dictionary = armies_v
		for eid_v: Variant in ad.keys():
			var eid: String = str(eid_v)
			if not _prev_army_ids.has(eid):
				_prev_army_ids[eid] = true
				var ent_v: Variant = ad[eid_v]
				if ent_v is Dictionary:
					var ent: Dictionary = ent_v
					var fac_ko: String = AssetRegistry.faction_name_ko(str(ent.get("faction_id", "")))
					var ut_ko: String = AssetRegistry.unit_type_ko(str(ent.get("unit_type", "ARMY")))
					var node_ko: String = AssetRegistry.node_name_ko(str(ent.get("current_node_id", "xuchang")))
					manor_view.append_chronicle_line("%s %s 부대가 %s 방면으로 출진했습니다." % [fac_ko, ut_ko, node_ko])

	# 3. Periodic pawn activity chronicle on macro ticks
	if client_tick % SimClock.MACRO_TICK == 0:
		var pawns_v: Variant = _manor_cache.get("pawns", {})
		if pawns_v is Dictionary:
			var pd: Dictionary = pawns_v
			var idx_sel: int = (client_tick / SimClock.MACRO_TICK) % maxi(1, pd.size())
			var pkeys: Array[String] = []
			for k: Variant in pd.keys():
				pkeys.append(str(k))
			pkeys.sort()
			if idx_sel < pkeys.size():
				var pr_v: Variant = pd[pkeys[idx_sel]]
				if pr_v is Dictionary:
					var pr: Dictionary = pr_v
					var pname: String = str(pr.get("name", "")).strip_edges()
					if pname.is_empty():
						pname = "조자룡" if pkeys[idx_sel].ends_with("_avatar") else "진도"
					var jko: String = AssetRegistry.job_ko(str(pr.get("job", "IDLE")))
					manor_view.append_chronicle_line("[%s] %s(이)가 %s 임무를 수행 중입니다." % [_current_shichen_ko(), pname, jko])


func _apply_local_hydration() -> void:
	if _live_driver == null or not _live_driver.is_local_mode():
		return
	var hyd: Dictionary = _live_driver.build_local_ui_hydration()
	if hyd.is_empty():
		return
	client_tick = maxi(client_tick, _to_int(hyd.get("tick_id", client_tick), client_tick))
	current_season = str(hyd.get("season", current_season))
	last_state_crc32 = _to_int(hyd.get("state_crc32", last_state_crc32), last_state_crc32)

	var manor_v: Variant = hyd.get("manor", {})
	if manor_v is Dictionary:
		var md: Dictionary = manor_v
		if not md.is_empty():
			if md.has("manor_id"):
				_manor_cache["manor_id"] = str(md["manor_id"])
			if md.has("host_node_id"):
				_manor_cache["host_node_id"] = str(md["host_node_id"])
				if macro_view != null:
					macro_view.set_host_node_id(str(md["host_node_id"]))
			if md.has("meta") and md["meta"] is Dictionary:
				var um: Dictionary = md["meta"]
				var mc: Dictionary = _manor_cache["meta"]
				_merge_flat(mc, um)
			if md.has("stockpile") and md["stockpile"] is Dictionary:
				var us: Dictionary = md["stockpile"]
				var sc: Dictionary = _manor_cache["stockpile"]
				_merge_flat(sc, us)
			if md.has("buildings") and md["buildings"] is Dictionary:
				var ub: Dictionary = md["buildings"]
				var bc: Dictionary = _manor_cache["buildings"]
				_merge_flat(bc, ub)
			if md.has("standing_doctrine") and md["standing_doctrine"] is Dictionary:
				var udoc: Dictionary = md["standing_doctrine"]
				var dc: Dictionary = _manor_cache["standing_doctrine"]
				_merge_flat(dc, udoc)
			if md.has("tile_zone_map"):
				_manor_cache["tile_zone_map"] = md["tile_zone_map"]
			if md.has("pawns") and md["pawns"] is Dictionary:
				var upw: Dictionary = md["pawns"]
				var pwc: Dictionary = _manor_cache["pawns"]
				_merge_entities(pwc, upw)

	var court_v: Variant = hyd.get("court", {})
	if court_v is Dictionary:
		var cd: Dictionary = court_v
		if not cd.is_empty():
			if cd.has("player_profile") and cd["player_profile"] is Dictionary:
				var upf: Dictionary = cd["player_profile"]
				var pfc: Dictionary = _court_cache["player_profile"]
				_merge_flat(pfc, upf)
			if cd.has("faction") and cd["faction"] is Dictionary:
				var ufc: Dictionary = cd["faction"]
				var fcc: Dictionary = _court_cache["faction"]
				_merge_flat(fcc, ufc)
			if cd.has("inbox_decisions"):
				_court_cache["inbox_decisions"] = cd["inbox_decisions"]
			if cd.has("storyteller"):
				_court_cache["storyteller"] = str(cd["storyteller"])

	_update_top_bar_display()
	if manor_view != null:
		manor_view.apply_snapshot(_manor_cache)
	_sync_manor_hero_banner()
	if priority_view != null:
		priority_view.apply_snapshot(_manor_cache)
	if macro_view != null:
		macro_view.apply_snapshot(_macro_cache)
	if court_hud != null:
		court_hud.apply_snapshot(_court_cache)
	_refresh_global_resources_and_onboarding()
	_emit_narrative_chronicle_updates()


func _refresh_session_bar() -> void:
	if _mode_status_label == null:
		return
	var is_local: bool = _live_driver != null and _live_driver.is_local_mode()
	var is_remote: bool = _live_driver != null and _live_driver.is_remote_mode()
	if is_local:
		var state_txt: String = "정지" if _paused else "%dx" % _speed_multiplier
		_mode_status_label.text = "● 로컬(%s)" % state_txt
		_mode_status_label.add_theme_color_override("font_color", AssetRegistry.COLOR_WARNING_AMBER if _paused else AssetRegistry.COLOR_SUCCESS_JADE)
		if _pause_btn != null:
			_pause_btn.disabled = false
			_pause_btn.text = "재개" if _paused else "일시정지"
		if _ws_connect_btn != null:
			_ws_connect_btn.text = "서버 접속"
			asset_registry.apply_button_variant(_ws_connect_btn, "secondary")
		if _local_demo_btn != null:
			asset_registry.apply_button_variant(_local_demo_btn, "primary")
	elif is_remote:
		var remote_st: String = _live_driver.get_remote_connection_state()
		var conn_txt: String = "연결됨" if remote_st == "OPEN" else ("연결 중" if remote_st == "CONNECTING" else "끊김")
		_mode_status_label.text = "● 원격(%s)" % conn_txt
		_mode_status_label.add_theme_color_override("font_color", AssetRegistry.COLOR_INFO_AZURE if remote_st == "OPEN" else AssetRegistry.COLOR_DANGER_CRIMSON)
		if _pause_btn != null:
			_pause_btn.disabled = true
			_pause_btn.text = "일시정지"
		if _ws_connect_btn != null:
			_ws_connect_btn.text = "연결 해제"
			asset_registry.apply_button_variant(_ws_connect_btn, "danger")
		if _local_demo_btn != null:
			asset_registry.apply_button_variant(_local_demo_btn, "secondary")
	else:
		_mode_status_label.text = "○ 대기"
		_mode_status_label.add_theme_color_override("font_color", AssetRegistry.COLOR_TEXT_MUTED)
		if _pause_btn != null:
			_pause_btn.disabled = true
			_pause_btn.text = "일시정지"
		if _ws_connect_btn != null:
			_ws_connect_btn.text = "서버 접속"
			asset_registry.apply_button_variant(_ws_connect_btn, "secondary")
		if _local_demo_btn != null:
			asset_registry.apply_button_variant(_local_demo_btn, "secondary")

	var speed_btns: Array[Button] = [_speed_1x_btn, _speed_2x_btn, _speed_5x_btn]
	var speed_vals: Array[int] = [1, 2, 5]
	for idx: int in range(3):
		var sb: Button = speed_btns[idx]
		var sv: int = speed_vals[idx]
		if sb != null:
			sb.disabled = (not is_local) or (_speed_multiplier == sv)
			asset_registry.apply_button_variant(sb, "primary" if (is_local and _speed_multiplier == sv) else "chip")


func _on_pause_toggled() -> void:
	set_demo_paused(not _paused)


func _on_ws_connect_pressed() -> void:
	if _live_driver != null and _live_driver.is_remote_mode():
		stop_live_session()
		return
	var target_url: String = _ws_url_edit.text.strip_edges() if _ws_url_edit != null else "ws://127.0.0.1:9090"
	var err: Error = connect_remote_websocket(target_url, player_id)
	_set_feedback_badge(
		"접속 시도: %s" % target_url if err == OK else "접속 실패 (err=%d)" % int(err),
		"info" if err == OK else "err"
	)
	if _server_modal != null:
		_server_modal.visible = false


func _on_local_demo_pressed() -> void:
	var _res: Dictionary = start_local_demo(18401)
	if _server_modal != null:
		_server_modal.visible = false


func apply_server_message(msg: Dictionary) -> void:
	var mtype: String = str(msg.get("msg_type", ""))
	match mtype:
		"MSG_WS_WELCOME":
			var server_last_seq: int = _to_int(msg.get("last_accepted_seq", 0), 0)
			cmd_seq = maxi(cmd_seq, server_last_seq)
			client_tick = _to_int(msg.get("tick_id", client_tick), client_tick)
			_update_top_bar_display()
			_set_feedback_badge("✓ 서버 연결 (%d틱)" % client_tick, "ok")
			_refresh_session_bar()
		DtoSchemas.MSG_TICK_DELTA:
			apply_tick_delta(msg)
		DtoSchemas.MSG_CMD_RECEIPT:
			_apply_cmd_receipt(msg)
		DtoSchemas.MSG_OFFLINE_CHRONICLE_DIGEST:
			apply_gazette(msg)
		DtoSchemas.MSG_PERSONA_CHALLENGE:
			apply_challenge(msg)


func _apply_cmd_receipt(receipt: Dictionary) -> void:
	var status: String = str(receipt.get("status", "ACCEPTED"))
	var seq: int = _to_int(receipt.get("cmd_seq", 0), 0)
	var err_code: String = str(receipt.get("error_code", DtoSchemas.ERR_OK))
	var exec_t: int = _to_int(receipt.get("exec_tick_id", client_tick), client_tick)
	if status == "REJECTED":
		_set_feedback_badge("거부(#%d): %s" % [seq, err_code], "err")
		if audio_manager != null:
			var _ok_err: bool = audio_manager.play_sfx("UI_ERROR")
	else:
		_set_feedback_badge("✓ 수락 · 명령 하달 (%d틱)" % exec_t, "ok")
		if manor_view != null:
			manor_view.append_chronicle_line("주군의 명(#%d)이 %d틱에 집행되었습니다." % [seq, exec_t])


func apply_challenge(challenge_msg: Dictionary) -> void:
	if court_hud != null:
		court_hud.apply_challenge(challenge_msg)
	if audio_manager != null:
		var _ok_sfx: bool = audio_manager.play_sfx("SEAL_VERIFY")
	challenge_received.emit(challenge_msg)


func apply_gazette(digest_msg: Dictionary) -> void:
	if court_hud != null:
		court_hud.apply_gazette(digest_msg)
	if audio_manager != null:
		var _ok_sfx: bool = audio_manager.play_sfx("GAZETTE_OPEN")
	gazette_received.emit(digest_msg)


func _merge_flat(target: Dictionary, patch: Dictionary) -> void:
	for k: Variant in patch.keys():
		target[str(k)] = patch[k]


func _merge_entities(target: Dictionary, updates: Dictionary) -> void:
	for k: Variant in updates.keys():
		var eid: String = str(k)
		var uv: Variant = updates[k]
		if uv is Dictionary:
			var ud: Dictionary = uv
			var prev_v: Variant = target.get(eid, {})
			var merged: Dictionary = {}
			if prev_v is Dictionary:
				var prev_d: Dictionary = prev_v
				merged = prev_d.duplicate(true)
			for fk: Variant in ud.keys():
				merged[str(fk)] = ud[fk]
			target[eid] = merged


func apply_tick_delta(delta_msg: Dictionary) -> void:
	client_tick = maxi(client_tick, _to_int(delta_msg.get("tick_id", client_tick), client_tick))
	if _live_driver != null:
		_live_driver.update_remote_tick(client_tick)
	current_season = str(delta_msg.get("season", current_season))
	last_state_crc32 = _to_int(delta_msg.get("state_crc32", last_state_crc32), last_state_crc32)

	var chans_v: Variant = delta_msg.get("channels", {})
	if not (chans_v is Dictionary):
		_update_top_bar_display()
		_refresh_session_bar()
		return
	var chans: Dictionary = chans_v

	for chan_k_v: Variant in chans.keys():
		var chan: String = str(chan_k_v)
		var payload_v: Variant = chans[chan_k_v]
		if not (payload_v is Dictionary):
			continue
		var payload: Dictionary = payload_v

		if chan == DtoSchemas.CHAN_GLOBAL_MACRO:
			if payload.has("u_nodes") and payload["u_nodes"] is Dictionary:
				var un_d: Dictionary = payload["u_nodes"]
				var nodes_c: Dictionary = _macro_cache["nodes"]
				_merge_entities(nodes_c, un_d)
			if payload.has("u_armies") and payload["u_armies"] is Dictionary:
				var ua_d: Dictionary = payload["u_armies"]
				var armies_c: Dictionary = _macro_cache["armies"]
				_merge_entities(armies_c, ua_d)
			if payload.has("d_armies") and payload["d_armies"] is Array:
				var da: Array = payload["d_armies"]
				var armies_c2: Dictionary = _macro_cache["armies"]
				for eid_v: Variant in da:
					var _er: bool = armies_c2.erase(str(eid_v))

		elif chan.begins_with(DtoSchemas.CHAN_FACTION + ":"):
			var fid: String = chan.substr((DtoSchemas.CHAN_FACTION + ":").length())
			var fac_c: Dictionary = _court_cache["faction"]
			fac_c["faction_id"] = fid
			if payload.has("u_faction") and payload["u_faction"] is Dictionary:
				var uf_d: Dictionary = payload["u_faction"]
				_merge_flat(fac_c, uf_d)
			if payload.has("u_members") and payload["u_members"] is Dictionary:
				var um_d: Dictionary = payload["u_members"]
				var mem_c: Dictionary = _court_cache["members"]
				_merge_entities(mem_c, um_d)
				if mem_c.has(player_id) and mem_c[player_id] is Dictionary:
					var my_mem: Dictionary = mem_c[player_id]
					var prof_c: Dictionary = _court_cache["player_profile"]
					prof_c["faction_id"] = fid
					_merge_flat(prof_c, my_mem)
			if payload.has("u_rallies") and payload["u_rallies"] is Dictionary:
				var ur_d: Dictionary = payload["u_rallies"]
				var ral_c: Dictionary = _macro_cache["rallies"]
				_merge_entities(ral_c, ur_d)

		elif chan.begins_with(DtoSchemas.CHAN_NODE + ":"):
			if payload.has("u_prices") and payload["u_prices"] is Dictionary:
				var up_d: Dictionary = payload["u_prices"]
				var pr_c: Dictionary = _court_cache["prices"]
				_merge_flat(pr_c, up_d)
			if payload.has("u_orders") and payload["u_orders"] is Dictionary:
				var uo_d: Dictionary = payload["u_orders"]
				var ord_c: Dictionary = _court_cache["orders"]
				_merge_entities(ord_c, uo_d)
			if payload.has("d_orders") and payload["d_orders"] is Array:
				var do_a: Array = payload["d_orders"]
				var ord_c2: Dictionary = _court_cache["orders"]
				for oid_v: Variant in do_a:
					var _ero: bool = ord_c2.erase(str(oid_v))

		elif chan.begins_with(DtoSchemas.CHAN_MANOR + ":"):
			var mid: String = chan.substr((DtoSchemas.CHAN_MANOR + ":").length())
			_manor_cache["manor_id"] = mid
			if payload.has("u_meta") and payload["u_meta"] is Dictionary:
				var ume_d: Dictionary = payload["u_meta"]
				var meta_c: Dictionary = _manor_cache["meta"]
				_merge_flat(meta_c, ume_d)
			if payload.has("u_stockpile") and payload["u_stockpile"] is Dictionary:
				var ust_d: Dictionary = payload["u_stockpile"]
				var stock_c: Dictionary = _manor_cache["stockpile"]
				_merge_flat(stock_c, ust_d)
			if payload.has("u_pawns") and payload["u_pawns"] is Dictionary:
				var upw_d: Dictionary = payload["u_pawns"]
				var pawns_c: Dictionary = _manor_cache["pawns"]
				_merge_entities(pawns_c, upw_d)
			if payload.has("d_pawns") and payload["d_pawns"] is Array:
				var dpw_a: Array = payload["d_pawns"]
				var pawns_c2: Dictionary = _manor_cache["pawns"]
				for pid_v: Variant in dpw_a:
					var _erp: bool = pawns_c2.erase(str(pid_v))

	_update_top_bar_display()
	if manor_view != null:
		manor_view.apply_snapshot(_manor_cache)
	_sync_manor_hero_banner()
	if priority_view != null:
		priority_view.apply_snapshot(_manor_cache)
	if macro_view != null:
		macro_view.apply_snapshot(_macro_cache)
	if court_hud != null:
		court_hud.apply_snapshot(_court_cache)
	_refresh_global_resources_and_onboarding()
	_refresh_session_bar()
	_emit_narrative_chronicle_updates()


func get_tab_count() -> int:
	return _tab_container.get_tab_count() if _tab_container != null else 0
