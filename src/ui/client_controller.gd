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

var active_tab_index: int = 0
var _ui_ready_for_audio: bool = false
var _in_switch_tab: bool = false
var _header_banner: TextureRect = null
var _mute_btn: Button = null
var _top_bar_label: Label = null
var _tab_container: TabContainer = null
var _cc_modal: AcceptDialog = null
var _cc_modal_btn: Button = null

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


func _ready() -> void:
	var _bgm_ok: bool = start_ambient_bgm()


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
	command_envelope_ready.emit(env)
	return env


func apply_server_message(msg: Dictionary) -> void:
	var mtype: String = str(msg.get("msg_type", ""))
	match mtype:
		DtoSchemas.MSG_TICK_DELTA:
			apply_tick_delta(msg)
		DtoSchemas.MSG_OFFLINE_CHRONICLE_DIGEST:
			apply_gazette(msg)
		DtoSchemas.MSG_PERSONA_CHALLENGE:
			apply_challenge(msg)


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
	current_season = str(delta_msg.get("season", current_season))
	last_state_crc32 = _to_int(delta_msg.get("state_crc32", last_state_crc32), last_state_crc32)

	if _top_bar_label != null:
		_top_bar_label.text = "플레이어: %s | 틱: %d | 계절: %s | CRC32: %d" % [
			player_id, client_tick, current_season, last_state_crc32
		]

	var chans_v: Variant = delta_msg.get("channels", {})
	if not (chans_v is Dictionary):
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
			if payload.has("u_faction") and payload["u_faction"] is Dictionary:
				var uf_d: Dictionary = payload["u_faction"]
				var fac_c: Dictionary = _court_cache["faction"]
				_merge_flat(fac_c, uf_d)
			if payload.has("u_members") and payload["u_members"] is Dictionary:
				var um_d: Dictionary = payload["u_members"]
				var mem_c: Dictionary = _court_cache["members"]
				_merge_entities(mem_c, um_d)
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


func get_tab_count() -> int:
	return _tab_container.get_tab_count() if _tab_container != null else 0
