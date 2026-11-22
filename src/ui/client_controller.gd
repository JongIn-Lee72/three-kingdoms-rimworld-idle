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
var _tab_container: TabContainer = null
var _cc_modal: AcceptDialog = null
var _cc_modal_btn: Button = null

var _session_bar_panel: PanelContainer = null
var _mode_status_label: Label = null
var _pause_btn: Button = null
var _speed_1x_btn: Button = null
var _speed_2x_btn: Button = null
var _speed_5x_btn: Button = null
var _cmd_feedback_label: Label = null
var _ws_url_edit: LineEdit = null
var _ws_connect_btn: Button = null
var _local_demo_btn: Button = null

var _live_driver: LiveSessionDriver = null
var _tick_accumulator_sec: float = 0.0
var _base_tick_interval_sec: float = 1.0
var _speed_multiplier: int = 1
var _paused: bool = false
var _ws_connected_ui: bool = false
var _ws_conn_state_ui: String = "CLOSED"

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


func _build_ui() -> void:
	theme = asset_registry.build_three_kingdoms_theme()

	var bg_rect: ColorRect = ColorRect.new()
	bg_rect.color = AssetRegistry.COLOR_LACQUER_BG
	bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg_rect)

	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var hdr_panel: PanelContainer = PanelContainer.new()
	hdr_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_panel.custom_minimum_size = Vector2(0, 56)
	hdr_panel.add_theme_stylebox_override("panel", asset_registry.build_panel_stylebox(true))

	var hdr_overlay: Control = Control.new()
	hdr_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_overlay.custom_minimum_size = Vector2(0, 44)
	hdr_panel.add_child(hdr_overlay)

	_header_banner = TextureRect.new()
	_header_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_header_banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_header_banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_header_banner.modulate = Color(1.0, 1.0, 1.0, 0.28)
	_header_banner.texture = asset_registry.get_texture(AssetRegistry.CREST_BANNER)
	hdr_overlay.add_child(_header_banner)

	var hdr_row: HBoxContainer = HBoxContainer.new()
	hdr_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	hdr_overlay.add_child(hdr_row)

	_top_bar_label = Label.new()
	_top_bar_label.text = "삼국지 x 림월드 공유 월드 클라이언트 | 틱: 0 | 계절: SPRING"
	_top_bar_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_row.add_child(_top_bar_label)

	_mute_btn = Button.new()
	_mute_btn.text = "음소거: OFF"
	_mute_btn.pressed.connect(_on_mute_toggled)
	hdr_row.add_child(_mute_btn)

	_cc_modal_btn = Button.new()
	_cc_modal_btn.text = "출사 / 봉인 토큰 생성 모달"
	_cc_modal_btn.pressed.connect(_on_open_cc_modal)
	hdr_row.add_child(_cc_modal_btn)
	root.add_child(hdr_panel)

	_session_bar_panel = PanelContainer.new()
	_session_bar_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_session_bar_panel.custom_minimum_size = Vector2(0, 40)
	_session_bar_panel.add_theme_stylebox_override("panel", asset_registry.build_panel_stylebox(false))
	var session_row: HBoxContainer = HBoxContainer.new()
	session_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_session_bar_panel.add_child(session_row)

	_mode_status_label = Label.new()
	_mode_status_label.text = "세션: 대기"
	session_row.add_child(_mode_status_label)

	_pause_btn = Button.new()
	_pause_btn.text = "일시정지"
	_pause_btn.pressed.connect(_on_pause_toggled)
	session_row.add_child(_pause_btn)

	_speed_1x_btn = Button.new()
	_speed_1x_btn.text = "1x"
	_speed_1x_btn.pressed.connect(set_demo_speed.bind(1))
	session_row.add_child(_speed_1x_btn)

	_speed_2x_btn = Button.new()
	_speed_2x_btn.text = "2x"
	_speed_2x_btn.pressed.connect(set_demo_speed.bind(2))
	session_row.add_child(_speed_2x_btn)

	_speed_5x_btn = Button.new()
	_speed_5x_btn.text = "5x"
	_speed_5x_btn.pressed.connect(set_demo_speed.bind(5))
	session_row.add_child(_speed_5x_btn)

	_cmd_feedback_label = Label.new()
	_cmd_feedback_label.text = "명령: 대기"
	_cmd_feedback_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	session_row.add_child(_cmd_feedback_label)

	_ws_url_edit = LineEdit.new()
	_ws_url_edit.text = "ws://127.0.0.1:9090"
	_ws_url_edit.placeholder_text = "ws://127.0.0.1:9090"
	_ws_url_edit.custom_minimum_size = Vector2(200, 0)
	session_row.add_child(_ws_url_edit)

	_ws_connect_btn = Button.new()
	_ws_connect_btn.text = "서버 접속"
	_ws_connect_btn.pressed.connect(_on_ws_connect_pressed)
	session_row.add_child(_ws_connect_btn)

	_local_demo_btn = Button.new()
	_local_demo_btn.text = "로컬 시연"
	_local_demo_btn.pressed.connect(_on_local_demo_pressed)
	session_row.add_child(_local_demo_btn)
	root.add_child(_session_bar_panel)
	_refresh_session_bar()

	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_container.tab_changed.connect(_on_tab_container_changed)
	root.add_child(_tab_container)

	manor_view = ManorGridView.new()
	manor_view.name = "1. 장원 그리드"
	manor_view.set_asset_registry(asset_registry)
	manor_view.intent_emitted.connect(_on_view_intent)
	_tab_container.add_child(manor_view)

	priority_view = WorkPriorityScheduleView.new()
	priority_view.name = "2. 우선순위 & 일과"
	priority_view.set_asset_registry(asset_registry)
	priority_view.intent_emitted.connect(_on_view_intent)
	_tab_container.add_child(priority_view)

	macro_view = MacroMapView.new()
	macro_view.name = "3. 천하 전략도"
	macro_view.set_asset_registry(asset_registry)
	macro_view.intent_emitted.connect(_on_view_intent)
	_tab_container.add_child(macro_view)

	court_hud = CourtMarketGazetteHUD.new()
	court_hud.name = "4. 정청 / 거래소 / 조보"
	court_hud.set_asset_registry(asset_registry)
	court_hud.intent_emitted.connect(_on_view_intent)
	court_hud.validation_error_emitted.connect(_on_validation_error)
	_tab_container.add_child(court_hud)

	# Non-blocking modal shortcut focusing the Character Creation & TK3K2 panel
	_cc_modal = AcceptDialog.new()
	_cc_modal.title = "장수 출사 및 TK3K2 봉인 토큰 안내"
	_cc_modal.dialog_text = "4번 탭(정청 / 거래소 / 조보)의 [장수 출사 인터뷰 & TK3K2 봉인 토큰 패널]에서 챌린지를 발급받고 토큰을 붙여넣으세요. 평문 JSON 입력은 차단됩니다."
	_cc_modal.confirmed.connect(_on_cc_modal_confirmed)
	add_child(_cc_modal)
	switch_tab(0)
	_ui_ready_for_audio = true


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
		if _cmd_feedback_label != null:
			_cmd_feedback_label.text = "명령 전송: %s (#%d)" % [cmd_type, cmd_seq] if sent_ok else "명령 대기/미연결: %s" % cmd_type
	command_envelope_ready.emit(env)
	return env


func get_live_driver() -> LiveSessionDriver:
	return _live_driver


func _reset_session_view_state() -> void:
	client_tick = 0
	last_state_crc32 = 0
	current_season = "SPRING"
	_tick_accumulator_sec = 0.0
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
	if _cmd_feedback_label != null:
		_cmd_feedback_label.text = "명령: 대기"
	if _top_bar_label != null:
		_top_bar_label.text = "플레이어: %s | 틱: 0 | 계절: SPRING | CRC32: 0" % player_id
	if manor_view != null:
		manor_view.reset_view_state()
	if priority_view != null:
		priority_view.reset_view_state()
	if macro_view != null:
		macro_view.reset_view_state()
	if court_hud != null:
		court_hud.reset_view_state()


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
	if _cmd_feedback_label != null:
		_cmd_feedback_label.text = "명령: 준비됨"
	var init_msgs_v: Variant = res.get("initial_messages", [])
	if init_msgs_v is Array:
		var init_msgs: Array = init_msgs_v
		for m_v: Variant in init_msgs:
			if m_v is Dictionary:
				var md: Dictionary = m_v
				apply_server_message(md)
	_apply_local_hydration()
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


func _apply_local_hydration() -> void:
	if _live_driver == null or not _live_driver.is_local_mode():
		return
	var hyd: Dictionary = _live_driver.build_local_ui_hydration()
	if hyd.is_empty():
		return
	client_tick = maxi(client_tick, _to_int(hyd.get("tick_id", client_tick), client_tick))
	current_season = str(hyd.get("season", current_season))
	last_state_crc32 = _to_int(hyd.get("state_crc32", last_state_crc32), last_state_crc32)
	if _top_bar_label != null:
		_top_bar_label.text = "플레이어: %s | 틱: %d | 계절: %s | CRC32: %d" % [
			player_id, client_tick, current_season, last_state_crc32
		]

	var manor_v: Variant = hyd.get("manor", {})
	if manor_v is Dictionary:
		var md: Dictionary = manor_v
		if not md.is_empty():
			if md.has("manor_id"):
				_manor_cache["manor_id"] = str(md["manor_id"])
			if md.has("host_node_id") and macro_view != null:
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

	if manor_view != null:
		manor_view.apply_snapshot(_manor_cache)
	if priority_view != null:
		priority_view.apply_snapshot(_manor_cache)
	if court_hud != null:
		court_hud.apply_snapshot(_court_cache)


func _refresh_session_bar() -> void:
	if _mode_status_label == null:
		return
	var is_local: bool = _live_driver != null and _live_driver.is_local_mode()
	var is_remote: bool = _live_driver != null and _live_driver.is_remote_mode()
	if is_local:
		var state_txt: String = "일시정지" if _paused else "%dx" % _speed_multiplier
		_mode_status_label.text = "모드: 로컬 시연 (%s) | 틱 %d" % [state_txt, client_tick]
		if _pause_btn != null:
			_pause_btn.disabled = false
			_pause_btn.text = "재개" if _paused else "일시정지"
		if _ws_connect_btn != null:
			_ws_connect_btn.text = "서버 접속"
	elif is_remote:
		var remote_st: String = _live_driver.get_remote_connection_state()
		var conn_txt: String = "연결됨" if remote_st == "OPEN" else ("연결 중..." if remote_st == "CONNECTING" else "연결 끊김")
		_mode_status_label.text = "모드: 원격 (%s) | 틱 %d" % [conn_txt, client_tick]
		if _pause_btn != null:
			_pause_btn.disabled = true
			_pause_btn.text = "일시정지"
		if _ws_connect_btn != null:
			_ws_connect_btn.text = "연결 해제"
	else:
		_mode_status_label.text = "모드: 대기"
		if _pause_btn != null:
			_pause_btn.disabled = true
			_pause_btn.text = "일시정지"
		if _ws_connect_btn != null:
			_ws_connect_btn.text = "서버 접속"

	if _speed_1x_btn != null:
		_speed_1x_btn.disabled = (not is_local) or (_speed_multiplier == 1)
	if _speed_2x_btn != null:
		_speed_2x_btn.disabled = (not is_local) or (_speed_multiplier == 2)
	if _speed_5x_btn != null:
		_speed_5x_btn.disabled = (not is_local) or (_speed_multiplier == 5)


func _on_pause_toggled() -> void:
	set_demo_paused(not _paused)


func _on_ws_connect_pressed() -> void:
	if _live_driver != null and _live_driver.is_remote_mode():
		stop_live_session()
		return
	var target_url: String = _ws_url_edit.text.strip_edges() if _ws_url_edit != null else "ws://127.0.0.1:9090"
	var err: Error = connect_remote_websocket(target_url, player_id)
	if _cmd_feedback_label != null:
		_cmd_feedback_label.text = "서버 연결 시도: %s" % target_url if err == OK else "연결 실패 (err=%d)" % int(err)


func _on_local_demo_pressed() -> void:
	var _res: Dictionary = start_local_demo(18401)


func apply_server_message(msg: Dictionary) -> void:
	var mtype: String = str(msg.get("msg_type", ""))
	match mtype:
		"MSG_WS_WELCOME":
			var server_last_seq: int = _to_int(msg.get("last_accepted_seq", 0), 0)
			cmd_seq = maxi(cmd_seq, server_last_seq)
			client_tick = _to_int(msg.get("tick_id", client_tick), client_tick)
			if _top_bar_label != null:
				_top_bar_label.text = "플레이어: %s | 틱: %d | 계절: %s | CRC32: %d" % [
					player_id, client_tick, current_season, last_state_crc32
				]
			if _cmd_feedback_label != null:
				_cmd_feedback_label.text = "서버 연결 완료 (seq=%d, tick=%d)" % [cmd_seq, client_tick]
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
		if _cmd_feedback_label != null:
			_cmd_feedback_label.text = "거부(#%d): %s" % [seq, err_code]
		if audio_manager != null:
			var _ok_err: bool = audio_manager.play_sfx("UI_ERROR")
	else:
		if _cmd_feedback_label != null:
			_cmd_feedback_label.text = "수락(#%d) -> 실행틱 %d" % [seq, exec_t]


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

	if _top_bar_label != null:
		_top_bar_label.text = "플레이어: %s | 틱: %d | 계절: %s | CRC32: %d" % [
			player_id, client_tick, current_season, last_state_crc32
		]

	var chans_v: Variant = delta_msg.get("channels", {})
	if not (chans_v is Dictionary):
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

	if manor_view != null:
		manor_view.apply_snapshot(_manor_cache)
	if priority_view != null:
		priority_view.apply_snapshot(_manor_cache)
	if macro_view != null:
		macro_view.apply_snapshot(_macro_cache)
	if court_hud != null:
		court_hud.apply_snapshot(_court_cache)
	_refresh_session_bar()


func get_tab_count() -> int:
	return _tab_container.get_tab_count() if _tab_container != null else 0
