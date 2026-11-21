class_name CourtMarketGazetteHUD
extends Control

signal intent_emitted(cmd_type: String, args: Dictionary)
signal validation_error_emitted(error_code: String)

var _assets: AssetRegistry = null
var _section_panels_slate: Array[PanelContainer] = []
var _section_panels_gold: Array[PanelContainer] = []
var _court_icon: TextureRect = null
var _market_icon: TextureRect = null
var _inbox_icon: TextureRect = null
var _gazette_icon: TextureRect = null
var _hegemony_icon: TextureRect = null
var _cc_icon: TextureRect = null

var _court_label: Label = null
var _members_box: VBoxContainer = null
var _market_prices_label: Label = null
var _orders_box: VBoxContainer = null
var _inbox_box: VBoxContainer = null
var _gazette_panel: PanelContainer = null
var _gazette_label: Label = null
var _hegemony_box: VBoxContainer = null

# Market controls
var _mkt_node_edit: LineEdit = null
var _mkt_comm_opt: OptionButton = null
var _mkt_side_opt: OptionButton = null
var _mkt_price_spin: SpinBox = null
var _mkt_qty_spin: SpinBox = null

# Character Creation + TK3K2 Sealed Token Paste-Only Panel
var _cc_name_edit: LineEdit = null
var _cc_mode_opt: OptionButton = null
var _cc_challenge_label: Label = null
var _cc_prompt_display: TextEdit = null
var _cc_token_paste_edit: LineEdit = null
var _cc_preview_status_label: Label = null
var _cc_interview_opts: Array[OptionButton] = []

var _cached_orders: Dictionary = {}
var _cached_prices: Dictionary = {}
var _cached_inbox: Array[Dictionary] = []
var _last_gazette: Dictionary = {}
var _last_challenge: Dictionary = {}


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
	name = "CourtMarketGazetteHUD"
	set_anchors_preset(Control.PRESET_FULL_RECT)
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
	if _court_icon != null:
		_court_icon.texture = _assets.get_macro_node_icon("CAPITAL")
	if _market_icon != null:
		_market_icon.texture = _assets.get_resource_icon("COIN")
	if _inbox_icon != null:
		_inbox_icon.texture = _assets.get_emote_texture("AWAKENED_HEARTS", false)
	if _gazette_icon != null:
		_gazette_icon.texture = _assets.get_resource_icon("MERIT_PRESTIGE")
	if _hegemony_icon != null:
		_hegemony_icon.texture = _assets.get_army_icon("COALITION_FORCE")
	if _cc_icon != null:
		_cc_icon.texture = _assets.get_pawn_sprite(true, "LORD")


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

	# 1. Faction Court / 9-Rank HUD
	var court_sec: VBoxContainer = _make_section_panel(root, false)
	_court_icon = _make_header_with_icon(court_sec, "[정청 & 구품 관직 HUD]")

	_court_label = Label.new()
	_court_label.text = "세력: 무소속 | 신분: FREE_OFFICER | 품계: NONE | 작위: GOVERNOR_INSPECTOR"
	court_sec.add_child(_court_label)

	_members_box = VBoxContainer.new()
	court_sec.add_child(_members_box)

	# 2. Regional Market BID/ASK Order Book Panel
	var mkt_sec: VBoxContainer = _make_section_panel(root, false)
	_market_icon = _make_header_with_icon(mkt_sec, "[지역 지정가 거래소 (BID / ASK)]")

	_market_prices_label = Label.new()
	_market_prices_label.text = "시세: GRAIN 1000bp | IRON 2000bp | WOOD 1500bp"
	mkt_sec.add_child(_market_prices_label)

	var mkt_ctrl: HBoxContainer = HBoxContainer.new()
	_mkt_node_edit = LineEdit.new()
	_mkt_node_edit.text = "xuchang"
	mkt_ctrl.add_child(_mkt_node_edit)

	_mkt_comm_opt = OptionButton.new()
	for c: String in DtoSchemas.MARKET_COMMODITIES:
		_mkt_comm_opt.add_item(c)
	mkt_ctrl.add_child(_mkt_comm_opt)

	_mkt_side_opt = OptionButton.new()
	_mkt_side_opt.add_item("BID")
	_mkt_side_opt.add_item("ASK")
	mkt_ctrl.add_child(_mkt_side_opt)

	_mkt_price_spin = SpinBox.new()
	_mkt_price_spin.min_value = 100
	_mkt_price_spin.max_value = 100000
	_mkt_price_spin.value = 1000
	mkt_ctrl.add_child(_mkt_price_spin)

	_mkt_qty_spin = SpinBox.new()
	_mkt_qty_spin.min_value = 1
	_mkt_qty_spin.max_value = 10000
	_mkt_qty_spin.value = 10
	mkt_ctrl.add_child(_mkt_qty_spin)

	var btn_order: Button = Button.new()
	btn_order.text = "주문 제출 (CMD_PLACE_MARKET_ORDER)"
	btn_order.pressed.connect(_on_place_order_pressed)
	mkt_ctrl.add_child(btn_order)
	mkt_sec.add_child(mkt_ctrl)

	_orders_box = VBoxContainer.new()
	mkt_sec.add_child(_orders_box)

	# 3. Async Decision Inbox
	var inbox_sec: VBoxContainer = _make_section_panel(root, false)
	_inbox_icon = _make_header_with_icon(inbox_sec, "[비동기 결재 서신함 (Async Decision Inbox)]")

	_inbox_box = VBoxContainer.new()
	inbox_sec.add_child(_inbox_box)

	# 4. Reconnect Morning Court Gazette Modal
	_gazette_panel = PanelContainer.new()
	_gazette_panel.visible = false
	_gazette_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_section_panels_gold.append(_gazette_panel)
	var gbox: VBoxContainer = VBoxContainer.new()
	_gazette_panel.add_child(gbox)

	_gazette_icon = _make_header_with_icon(gbox, "[조보: 지난 밤의 사기 브리핑 (MSG_OFFLINE_CHRONICLE_DIGEST)]")

	_gazette_label = Label.new()
	_gazette_label.text = "조보 내역 없음"
	_gazette_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gbox.add_child(_gazette_label)

	var btn_close_g: Button = Button.new()
	btn_close_g.text = "조보 확인 닫기"
	btn_close_g.pressed.connect(_on_close_gazette_pressed)
	gbox.add_child(btn_close_g)
	root.add_child(_gazette_panel)

	# 5. Season Hegemony Leaderboard Panel
	var heg_sec: VBoxContainer = _make_section_panel(root, true)
	_hegemony_icon = _make_header_with_icon(heg_sec, "[시즌 천하통일 결산 (천하 패자 / 개국 공신)]")

	_hegemony_box = VBoxContainer.new()
	heg_sec.add_child(_hegemony_box)

	# 6. Character Creation Interview + TK3K2 Paste-Only Sealed Token Panel
	var cc_sec: VBoxContainer = _make_section_panel(root, true)
	_cc_icon = _make_header_with_icon(cc_sec, "[장수 출사 인터뷰 & TK3K2 봉인 토큰 붙여넣기 전용 패널]")

	var cc_row1: HBoxContainer = HBoxContainer.new()
	var n_lbl: Label = Label.new()
	n_lbl.text = "장수명:"
	cc_row1.add_child(n_lbl)
	_cc_name_edit = LineEdit.new()
	_cc_name_edit.text = "Nameless_Hero"
	cc_row1.add_child(_cc_name_edit)

	var m_lbl: Label = Label.new()
	m_lbl.text = "생성 방식:"
	cc_row1.add_child(m_lbl)
	_cc_mode_opt = OptionButton.new()
	for cm: String in DtoSchemas.CREATION_MODES:
		_cc_mode_opt.add_item(cm)
	_cc_mode_opt.select(1)  # FUSION_INTERVIEW default
	cc_row1.add_child(_cc_mode_opt)

	var btn_chal: Button = Button.new()
	btn_chal.text = "일회성 챌린지 발급 (CMD_REQUEST_PERSONA_CHALLENGE)"
	btn_chal.pressed.connect(_on_request_challenge_pressed)
	cc_row1.add_child(btn_chal)
	cc_sec.add_child(cc_row1)

	_cc_challenge_label = Label.new()
	_cc_challenge_label.text = "챌린지 상태: 미발급"
	cc_sec.add_child(_cc_challenge_label)

	# Read-only prompt display (NEVER editable raw JSON box!)
	_cc_prompt_display = TextEdit.new()
	_cc_prompt_display.editable = false
	_cc_prompt_display.custom_minimum_size = Vector2(0, 72)
	_cc_prompt_display.text = "외부 AI 프롬프트가 이곳에 읽기 전용으로 표시됩니다."
	cc_sec.add_child(_cc_prompt_display)

	# Paste-only single-line sealed token input
	var tok_row: HBoxContainer = HBoxContainer.new()
	var tok_lbl: Label = Label.new()
	tok_lbl.text = "TK3K2 봉인 토큰 붙여넣기:"
	tok_row.add_child(tok_lbl)

	_cc_token_paste_edit = LineEdit.new()
	_cc_token_paste_edit.placeholder_text = "TK3K2-XXXXXX-XXXXXX-XXXXXX-XXXX-XX"
	_cc_token_paste_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cc_token_paste_edit.text_changed.connect(_on_token_text_changed)
	tok_row.add_child(_cc_token_paste_edit)
	cc_sec.add_child(tok_row)

	_cc_preview_status_label = Label.new()
	_cc_preview_status_label.text = "토큰 검증 대기"
	cc_sec.add_child(_cc_preview_status_label)

	# 8-Question Interview Option Selectors
	var q_row: HBoxContainer = HBoxContainer.new()
	for qi: int in range(8):
		var q_opt: OptionButton = OptionButton.new()
		q_opt.add_item("Q%d-A" % (qi + 1))
		q_opt.add_item("Q%d-B" % (qi + 1))
		q_opt.add_item("Q%d-C" % (qi + 1))
		q_opt.add_item("Q%d-D" % (qi + 1))
		q_row.add_child(q_opt)
		_cc_interview_opts.append(q_opt)
	cc_sec.add_child(q_row)

	var btn_submit_cc: Button = Button.new()
	btn_submit_cc.text = "캐릭터 출사 확정 (CMD_CREATE_CHARACTER)"
	btn_submit_cc.pressed.connect(_on_submit_cc_pressed)
	cc_sec.add_child(btn_submit_cc)


func _on_place_order_pressed() -> void:
	var comm: String = _mkt_comm_opt.get_item_text(_mkt_comm_opt.selected) if _mkt_comm_opt.selected >= 0 else "GRAIN"
	var side: String = _mkt_side_opt.get_item_text(_mkt_side_opt.selected) if _mkt_side_opt.selected >= 0 else "BID"
	emit_place_market_order(
		_mkt_node_edit.text.strip_edges(),
		comm,
		side,
		int(_mkt_price_spin.value),
		int(_mkt_qty_spin.value)
	)


func emit_place_market_order(node_id: String, commodity: String, side: String, price_bp: int, quantity: int) -> void:
	intent_emitted.emit("CMD_PLACE_MARKET_ORDER", {
		"node_id": node_id if not node_id.is_empty() else "xuchang",
		"commodity": commodity,
		"side": side,
		"price_bp": clampi(price_bp, 100, 100000),
		"quantity": maxi(1, quantity)
	})


func emit_decide_inbox_event(decision_id: String, chosen_option: String) -> void:
	intent_emitted.emit("CMD_DECIDE_INBOX_EVENT", {
		"decision_id": decision_id,
		"chosen_option": chosen_option
	})


func _on_close_gazette_pressed() -> void:
	_gazette_panel.visible = false


func _on_request_challenge_pressed() -> void:
	request_challenge()


func request_challenge(account_id: String = "") -> void:
	var args: Dictionary = {}
	if not account_id.is_empty():
		args["account_id"] = account_id
	intent_emitted.emit("CMD_REQUEST_PERSONA_CHALLENGE", args)


static func is_plaintext_json_smuggle(raw_text: String) -> bool:
	var kv_re: RegEx = RegEx.new()
	var _err: int = kv_re.compile(SealedTokenCodec.KV_SMUGGLE_REGEX_PATTERN)
	return (
		raw_text.contains("{")
		or raw_text.contains("}")
		or raw_text.contains("AI_PERSONA_EXPORT_V1")
		or raw_text.contains("persona_weights")
		or kv_re.search(raw_text) != null
	)


func validate_client_token_preview(raw_text: String) -> Dictionary:
	var trimmed: String = raw_text.strip_edges()
	if trimmed.is_empty():
		return {"ok": false, "error_code": DtoSchemas.ERR_TOKEN_FORMAT}
	if is_plaintext_json_smuggle(trimmed):
		return {"ok": false, "error_code": DtoSchemas.ERR_PLAINTEXT_JSON_FORBIDDEN}
	return {"ok": true, "error_code": DtoSchemas.ERR_OK}


func _on_token_text_changed(new_text: String) -> void:
	var check: Dictionary = validate_client_token_preview(new_text)
	if check.get("ok", false):
		_cc_preview_status_label.text = "토큰 형식 사전 확인 완료 (서버 검증 대기)"
	else:
		var ec: String = str(check.get("error_code", DtoSchemas.ERR_TOKEN_FORMAT))
		_cc_preview_status_label.text = "거부됨: " + ec


func _on_submit_cc_pressed() -> void:
	var mode: String = _cc_mode_opt.get_item_text(_cc_mode_opt.selected) if _cc_mode_opt.selected >= 0 else "INTERVIEW_ONLY"
	var answers: Array[int] = []
	for opt: OptionButton in _cc_interview_opts:
		answers.append(maxi(0, opt.selected))
	var _res: Dictionary = submit_character_creation(
		_cc_name_edit.text.strip_edges(),
		mode,
		answers,
		_cc_token_paste_edit.text
	)


func submit_character_creation(
	avatar_name: String,
	creation_mode: String,
	interview_answers: Array[int],
	sealed_token_input: String = "",
	fine_tuning: Dictionary = {}
) -> Dictionary:
	var mode: String = creation_mode if DtoSchemas.CREATION_MODES.has(creation_mode) else "INTERVIEW_ONLY"
	if mode == "FUSION_INTERVIEW" or mode == "AI_DIRECT_WITH_CONFIRM":
		var check: Dictionary = validate_client_token_preview(sealed_token_input)
		if not check.get("ok", false):
			var err_code: String = str(check.get("error_code", DtoSchemas.ERR_TOKEN_FORMAT))
			_cc_preview_status_label.text = "제출 거부: " + err_code
			if err_code == DtoSchemas.ERR_PLAINTEXT_JSON_FORBIDDEN:
				validation_error_emitted.emit(err_code)
			return {"ok": false, "error_code": err_code}

	var args: Dictionary = {
		"avatar_name": avatar_name if not avatar_name.is_empty() else "Nameless_Hero",
		"creation_mode": mode,
		"interview_answers": interview_answers.duplicate(),
		"sealed_token_input": sealed_token_input.strip_edges()
	}
	if not fine_tuning.is_empty():
		args["fine_tuning"] = fine_tuning.duplicate(true)
	intent_emitted.emit("CMD_CREATE_CHARACTER", args)
	return {"ok": true, "error_code": DtoSchemas.ERR_OK}


func apply_challenge(challenge_msg: Dictionary) -> void:
	_last_challenge = challenge_msg.duplicate(true)
	var cid: String = str(challenge_msg.get("challenge_id", ""))
	var exp_t: int = _to_int(challenge_msg.get("ttl_expires_tick", 0), 0)
	_cc_challenge_label.text = "챌린지 ID: %s (만료 틱: %d)" % [cid, exp_t]
	_cc_prompt_display.text = str(challenge_msg.get("prompt_text", ""))


func apply_gazette(digest_msg: Dictionary) -> void:
	_last_gazette = digest_msg.duplicate(true)
	var from_t: int = _to_int(digest_msg.get("from_tick", 0), 0)
	var to_t: int = _to_int(digest_msg.get("to_tick", 0), 0)

	var yields_v: Variant = digest_msg.get("net_yields", {})
	var yields: Dictionary = yields_v if yields_v is Dictionary else {}
	var yield_parts: PackedStringArray = PackedStringArray()
	for rk: Variant in yields.keys():
		var _ok_y: bool = yield_parts.append("%s:%+d" % [str(rk), _to_int(yields[rk], 0)])

	var stip_v: Variant = digest_msg.get("stipends_received", {})
	var stip: Dictionary = stip_v if stip_v is Dictionary else {}
	var mis_v: Variant = digest_msg.get("completed_missions", [])
	var mis_cnt: int = 0
	if mis_v is Array:
		var mis_a: Array = mis_v
		mis_cnt = mis_a.size()
	var pev_v: Variant = digest_msg.get("pawn_events", [])
	var pev_cnt: int = 0
	if pev_v is Array:
		var pev_a: Array = pev_v
		pev_cnt = pev_a.size()
	var bat_v: Variant = digest_msg.get("battle_replays", [])
	var bat_cnt: int = 0
	if bat_v is Array:
		var bat_a: Array = bat_v
		bat_cnt = bat_a.size()

	_gazette_label.text = "기간: %d ~ %d 틱\n순 생산량: %s\n봉록: 은전 %d / 군량 %d (%d회)\n완료 임무: %d건 | 가신 사건: %d건 | 전투 기록: %d건" % [
		from_t,
		to_t,
		", ".join(yield_parts) if not yield_parts.is_empty() else "변동 없음",
		_to_int(stip.get("COIN", 0), 0),
		_to_int(stip.get("GRAIN", 0), 0),
		_to_int(stip.get("count", 0), 0),
		mis_cnt,
		pev_cnt,
		bat_cnt
	]
	_gazette_panel.visible = true


func apply_snapshot(snapshot: Dictionary) -> void:
	# Faction & Court rank
	var fac_v: Variant = snapshot.get("faction", {})
	var fac: Dictionary = fac_v if fac_v is Dictionary else {}
	var prof_v: Variant = snapshot.get("player_profile", {})
	var prof: Dictionary = prof_v if prof_v is Dictionary else {}
	var fid: String = str(prof.get("faction_id", fac.get("faction_id", "무소속")))
	if fid.is_empty():
		fid = "무소속"
	_court_label.text = "세력: %s | 신분: %s | 품계: %s | 작위: %s | 위명: %d | 국고(전/량): %d / %d" % [
		fid,
		str(prof.get("role_tier", "FREE_OFFICER")),
		str(prof.get("court_rank", "NONE")),
		str(fac.get("royal_rank", "GOVERNOR_INSPECTOR")),
		_to_int(fac.get("prestige", 0), 0),
		_to_int(fac.get("treasury_coin", 0), 0),
		_to_int(fac.get("treasury_grain", 0), 0)
	]

	for ch_m: Node in _members_box.get_children():
		ch_m.queue_free()
	var mem_v: Variant = snapshot.get("members", {})
	if mem_v is Dictionary:
		var md: Dictionary = mem_v
		var mkeys: Array[String] = []
		for k: Variant in md.keys():
			mkeys.append(str(k))
		mkeys.sort()
		for mk: String in mkeys:
			var mv: Variant = md[mk]
			if mv is Dictionary:
				var mdict: Dictionary = mv
				var mlbl: Label = Label.new()
				mlbl.text = "동료 %s | %s (%s) | 공적:%d" % [
					mk,
					str(mdict.get("role_tier", "FACTION_OFFICER")),
					str(mdict.get("court_rank", "RANK_9")),
					_to_int(mdict.get("war_merit", 0), 0)
				]
				_members_box.add_child(mlbl)

	# Market prices & order book
	if snapshot.has("prices") and snapshot["prices"] is Dictionary:
		var pr_d: Dictionary = snapshot["prices"]
		for k: Variant in pr_d.keys():
			_cached_prices[str(k)] = _to_int(pr_d[k], 1000)
	var p_parts: PackedStringArray = PackedStringArray()
	for comm: String in DtoSchemas.MARKET_COMMODITIES:
		if _cached_prices.has(comm):
			var _ok_p: bool = p_parts.append("%s:%d" % [comm, _to_int(_cached_prices[comm], 1000)])
	if not p_parts.is_empty():
		_market_prices_label.text = "지역 시세(bp): " + " | ".join(p_parts)

	if snapshot.has("orders") and snapshot["orders"] is Dictionary:
		var ord_d: Dictionary = snapshot["orders"]
		for k: Variant in ord_d.keys():
			var oid: String = str(k)
			var ov: Variant = ord_d[k]
			if ov is Dictionary:
				var od: Dictionary = ov
				_cached_orders[oid] = od.duplicate(true)
	if snapshot.has("deleted_orders") and snapshot["deleted_orders"] is Array:
		var del_o: Array = snapshot["deleted_orders"]
		for oid_v: Variant in del_o:
			var _eo: bool = _cached_orders.erase(str(oid_v))

	for ch_o: Node in _orders_box.get_children():
		ch_o.queue_free()
	var okeys: Array[String] = []
	for k_o: Variant in _cached_orders.keys():
		okeys.append(str(k_o))
	okeys.sort()
	for oid: String in okeys:
		var od: Dictionary = _cached_orders[oid]
		var olbl: Label = Label.new()
		olbl.text = "%s | %s %s | 단가:%d bp | 잔량:%d" % [
			oid,
			str(od.get("side", "BID")),
			str(od.get("commodity", "GRAIN")),
			_to_int(od.get("price_bp", 1000), 1000),
			_to_int(od.get("remaining_qty", 0), 0)
		]
		_orders_box.add_child(olbl)

	# Async Decision Inbox
	if snapshot.has("inbox_decisions") and snapshot["inbox_decisions"] is Array:
		_cached_inbox.clear()
		var dec_a: Array = snapshot["inbox_decisions"]
		for item: Variant in dec_a:
			if item is Dictionary:
				var dd: Dictionary = item
				_cached_inbox.append(dd.duplicate(true))

	for ch_i: Node in _inbox_box.get_children():
		ch_i.queue_free()
	for dec: Dictionary in _cached_inbox:
		var did: String = str(dec.get("decision_id", ""))
		var etype: String = str(dec.get("event_type", "EVENT"))
		var row: HBoxContainer = HBoxContainer.new()
		var ilbl: Label = Label.new()
		ilbl.text = "[%s] %s (만료:%d)" % [did, etype, _to_int(dec.get("deadline_tick", 0), 0)]
		row.add_child(ilbl)
		var opts_v: Variant = dec.get("options", [])
		if opts_v is Array:
			var opts: Array = opts_v
			for opt_v: Variant in opts:
				var opt_s: String = str(opt_v)
				var b: Button = Button.new()
				b.text = opt_s
				b.pressed.connect(emit_decide_inbox_event.bind(did, opt_s))
				row.add_child(b)
		_inbox_box.add_child(row)

	# Season Hegemony leaderboard
	if snapshot.has("season_settlement") and snapshot["season_settlement"] is Dictionary:
		var set_d: Dictionary = snapshot["season_settlement"]
		for ch_h: Node in _hegemony_box.get_children():
			ch_h.queue_free()
		var heg_v: Variant = set_d.get("hegemon", {})
		if heg_v is Dictionary:
			var heg: Dictionary = heg_v
			if not heg.is_empty():
				var hl: Label = Label.new()
				hl.text = "%s: %s (%s) 점수=%d" % [
					SeasonHegemonyService.HEGEMON_TITLE_KO,
					str(heg.get("faction_name", heg.get("faction_id", ""))),
					str(heg.get("lord_player_id", "")),
					_to_int(heg.get("score", 0), 0)
				]
				_hegemony_box.add_child(hl)
		var top_v: Variant = set_d.get("top_merit_officer", {})
		if top_v is Dictionary:
			var top_o: Dictionary = top_v
			if not top_o.is_empty():
				var ol: Label = Label.new()
				ol.text = "%s: %s 점수=%d" % [
					SeasonHegemonyService.TOP_OFFICER_TITLE_KO,
					str(top_o.get("player_id", "")),
					_to_int(top_o.get("score", 0), 0)
				]
				_hegemony_box.add_child(ol)


func is_gazette_visible() -> bool:
	return _gazette_panel != null and _gazette_panel.visible
