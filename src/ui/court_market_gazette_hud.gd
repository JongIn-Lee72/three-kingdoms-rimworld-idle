class_name CourtMarketGazetteHUD
extends Control

signal intent_emitted(cmd_type: String, args: Dictionary)
signal validation_error_emitted(error_code: String)

var _assets: AssetRegistry = null
var _section_panels_slate: Array[PanelContainer] = []
var _section_panels_gold: Array[PanelContainer] = []
var _card_panels: Array[PanelContainer] = []
var _court_icon: TextureRect = null
var _market_icon: TextureRect = null
var _inbox_icon: TextureRect = null
var _gazette_icon: TextureRect = null
var _hegemony_icon: TextureRect = null
var _cc_icon: TextureRect = null

var _court_label: Label = null
var _court_kpi_faction_val: Label = null
var _court_kpi_rank_val: Label = null
var _court_kpi_coin_val: Label = null
var _court_kpi_grain_val: Label = null
var _members_box: VBoxContainer = null
var _market_prices_label: Label = null
var _orders_box: VBoxContainer = null
var _orders_empty_label: Label = null
var _inbox_box: VBoxContainer = null
var _inbox_empty_label: Label = null
var _gazette_panel: PanelContainer = null
var _gazette_label: Label = null
var _gazette_empty_label: Label = null
var _hegemony_box: VBoxContainer = null
var _hegemony_empty_label: Label = null

# Market controls
var _mkt_node_opt: OptionButton = null
var _mkt_node_edit: LineEdit = null
var _mkt_comm_opt: OptionButton = null
var _mkt_side_opt: OptionButton = null
var _mkt_price_spin: SpinBox = null
var _mkt_qty_spin: SpinBox = null
var _mkt_submit_btn: Button = null

# Character Creation + TK3K2 Sealed Token Paste-Only Panel
var _cc_name_edit: LineEdit = null
var _cc_mode_opt: OptionButton = null
var _cc_origin_opt: OptionButton = null
var _cc_province_opt: OptionButton = null
var _cc_challenge_btn: Button = null
var _cc_challenge_label: Label = null
var _cc_prompt_display: TextEdit = null
var _cc_token_paste_edit: LineEdit = null
var _cc_preview_status_label: Label = null
var _cc_interview_opts: Array[OptionButton] = []
var _cc_submit_btn: Button = null

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
	var card_sb: StyleBoxFlat = _assets.build_card_stylebox(false, AssetRegistry.COLOR_SUBTLE_BORDER)
	for p_card: PanelContainer in _card_panels:
		if p_card != null:
			p_card.add_theme_stylebox_override("panel", card_sb)
	if _gazette_panel != null:
		_gazette_panel.add_theme_stylebox_override("panel", _assets.build_card_stylebox(true, AssetRegistry.COLOR_GOLD_ACCENT))
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
	if _mkt_submit_btn != null:
		_assets.apply_button_variant(_mkt_submit_btn, "primary")
	if _cc_challenge_btn != null:
		_assets.apply_button_variant(_cc_challenge_btn, "secondary")
	if _cc_submit_btn != null:
		_assets.apply_button_variant(_cc_submit_btn, "primary")


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


func _make_kpi_tile(parent: GridContainer, title_txt: String, initial_val: String) -> Label:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.10, 0.09, 0.94)
	sb.border_color = AssetRegistry.COLOR_SUBTLE_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	card.add_theme_stylebox_override("panel", sb)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	card.add_child(vbox)

	var tlbl: Label = Label.new()
	tlbl.text = title_txt
	AssetRegistry.apply_text_role(tlbl, "caption")
	vbox.add_child(tlbl)

	var vlbl: Label = Label.new()
	vlbl.text = initial_val
	AssetRegistry.apply_text_role(vlbl, "body")
	vbox.add_child(vlbl)

	parent.add_child(card)
	return vlbl


func _load_interview_question_titles() -> Array[String]:
	var titles: Array[String] = [
		"Q1 난세 낙하", "Q2 황건의 불길", "Q3 권력과 명분", "Q4 전장의 철학",
		"Q5 몰입의 불꽃", "Q6 인간의 그림자", "Q7 삶의 리듬", "Q8 첫 발걸음"
	]
	if FileAccess.file_exists("res://data/interview_questions.json"):
		var f: FileAccess = FileAccess.open("res://data/interview_questions.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				var pd: Dictionary = parsed
				var qs_v: Variant = pd.get("questions", [])
				if qs_v is Array:
					var qs: Array = qs_v
					for i: int in range(mini(8, qs.size())):
						if qs[i] is Dictionary:
							var qd: Dictionary = qs[i]
							var stitle: String = str(qd.get("scene_title", ""))
							var short_t: String = stitle.split(":")[0] if stitle.contains(":") else stitle
							if not short_t.is_empty():
								titles[i] = "Q%d %s" % [i + 1, short_t]
	return titles


func _build_ui() -> void:
	var outer: VBoxContainer = VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	var split: HSplitContainer = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.split_offset = 0
	outer.add_child(split)

	# =========================================================================
	# LEFT PANE: Court KPI + Regional Limit Order Book Market + Async Inbox
	# =========================================================================
	var left_scroll: ScrollContainer = ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(520, 0)
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_stretch_ratio = 0.96
	split.add_child(left_scroll)

	var left_col: VBoxContainer = VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 6)
	left_scroll.add_child(left_col)

	# 1. Faction Court / 9-Rank KPI Card
	var court_sec: VBoxContainer = _make_card_panel(left_col, false)
	_court_icon = _make_header_with_icon(court_sec, "정청 · 구품 관직 및 국고 현황")

	var kpi_grid: GridContainer = GridContainer.new()
	kpi_grid.columns = 4
	kpi_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kpi_grid.add_theme_constant_override("h_separation", 6)
	kpi_grid.add_theme_constant_override("v_separation", 4)
	_court_kpi_faction_val = _make_kpi_tile(kpi_grid, "소속 세력", "무소속")
	_court_kpi_rank_val = _make_kpi_tile(kpi_grid, "관직 · 작위", "재야 장수")
	_court_kpi_coin_val = _make_kpi_tile(kpi_grid, "국고 은전", "0")
	_court_kpi_grain_val = _make_kpi_tile(kpi_grid, "국고 군량", "0")
	court_sec.add_child(kpi_grid)

	_court_label = Label.new()
	_court_label.text = "세력: 무소속 | 신분: FREE_OFFICER | 품계: NONE | 작위: GOVERNOR_INSPECTOR"
	_court_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	AssetRegistry.apply_text_role(_court_label, "caption")
	court_sec.add_child(_court_label)

	_members_box = VBoxContainer.new()
	_members_box.add_theme_constant_override("separation", 2)
	court_sec.add_child(_members_box)

	# 2. Regional Market BID/ASK Order Book Panel
	var mkt_sec: VBoxContainer = _make_card_panel(left_col, false)
	_market_icon = _make_header_with_icon(mkt_sec, "지역 지정가 거래소 (매수 · 매도)")

	_market_prices_label = Label.new()
	_market_prices_label.text = "시세(bp): 군량 1,000 | 철광 2,000 | 목재 1,500"
	_market_prices_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	AssetRegistry.apply_text_role(_market_prices_label, "muted")
	mkt_sec.add_child(_market_prices_label)

	var mkt_row1: HBoxContainer = HBoxContainer.new()
	mkt_row1.add_theme_constant_override("separation", 4)
	var city_lbl: Label = Label.new()
	city_lbl.text = "거점:"
	AssetRegistry.apply_text_role(city_lbl, "caption")
	mkt_row1.add_child(city_lbl)

	_mkt_node_opt = OptionButton.new()
	_mkt_node_opt.custom_minimum_size = Vector2(125, 0)
	var market_cities: Array[String] = ["xuchang", "luoyang", "changan", "ye_city", "chengdu", "jianye", "xiapi"]
	for mci: int in range(market_cities.size()):
		var cid: String = market_cities[mci]
		_mkt_node_opt.add_item("%s (%s)" % [AssetRegistry.node_name_ko(cid), cid])
		_mkt_node_opt.set_item_metadata(mci, cid)
	_mkt_node_opt.item_selected.connect(_on_mkt_city_selected)
	mkt_row1.add_child(_mkt_node_opt)

	_mkt_node_edit = LineEdit.new()
	_mkt_node_edit.text = "xuchang"
	_mkt_node_edit.custom_minimum_size = Vector2(90, 0)
	_mkt_node_edit.tooltip_text = "직접 입력할 거래소 거점 ID (예: xuchang)"
	mkt_row1.add_child(_mkt_node_edit)

	_mkt_comm_opt = OptionButton.new()
	_mkt_comm_opt.custom_minimum_size = Vector2(88, 0)
	for ci: int in range(DtoSchemas.MARKET_COMMODITIES.size()):
		var c: String = DtoSchemas.MARKET_COMMODITIES[ci]
		_mkt_comm_opt.add_item(AssetRegistry.resource_label_ko(c))
		_mkt_comm_opt.set_item_metadata(ci, c)
	mkt_row1.add_child(_mkt_comm_opt)

	_mkt_side_opt = OptionButton.new()
	_mkt_side_opt.custom_minimum_size = Vector2(95, 0)
	_mkt_side_opt.add_item("매수 (BID)")
	_mkt_side_opt.set_item_metadata(0, "BID")
	_mkt_side_opt.add_item("매도 (ASK)")
	_mkt_side_opt.set_item_metadata(1, "ASK")
	mkt_row1.add_child(_mkt_side_opt)
	mkt_sec.add_child(mkt_row1)

	var mkt_row2: HBoxContainer = HBoxContainer.new()
	mkt_row2.add_theme_constant_override("separation", 6)
	var p_lbl: Label = Label.new()
	p_lbl.text = "단가(bp):"
	AssetRegistry.apply_text_role(p_lbl, "caption")
	mkt_row2.add_child(p_lbl)

	_mkt_price_spin = SpinBox.new()
	_mkt_price_spin.min_value = 100
	_mkt_price_spin.max_value = 100000
	_mkt_price_spin.value = 1000
	_mkt_price_spin.custom_minimum_size = Vector2(92, 0)
	mkt_row2.add_child(_mkt_price_spin)

	var q_lbl: Label = Label.new()
	q_lbl.text = "수량:"
	AssetRegistry.apply_text_role(q_lbl, "caption")
	mkt_row2.add_child(q_lbl)

	_mkt_qty_spin = SpinBox.new()
	_mkt_qty_spin.min_value = 1
	_mkt_qty_spin.max_value = 10000
	_mkt_qty_spin.value = 10
	_mkt_qty_spin.custom_minimum_size = Vector2(80, 0)
	mkt_row2.add_child(_mkt_qty_spin)

	_mkt_submit_btn = Button.new()
	_mkt_submit_btn.text = "거래소 주문 등록"
	_mkt_submit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mkt_submit_btn.pressed.connect(_on_place_order_pressed)
	mkt_row2.add_child(_mkt_submit_btn)
	mkt_sec.add_child(mkt_row2)

	_orders_box = VBoxContainer.new()
	_orders_box.add_theme_constant_override("separation", 3)
	mkt_sec.add_child(_orders_box)

	_orders_empty_label = Label.new()
	_orders_empty_label.text = "등록된 미체결 호가가 없습니다. 위에서 매수/매도 주문을 등록하세요."
	_orders_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	AssetRegistry.apply_text_role(_orders_empty_label, "caption")
	mkt_sec.add_child(_orders_empty_label)

	# 3. Async Decision Inbox
	var inbox_sec: VBoxContainer = _make_card_panel(left_col, false)
	_inbox_icon = _make_header_with_icon(inbox_sec, "비동기 결재 서신함")

	_inbox_box = VBoxContainer.new()
	_inbox_box.add_theme_constant_override("separation", 4)
	inbox_sec.add_child(_inbox_box)

	_inbox_empty_label = Label.new()
	_inbox_empty_label.text = "대기 중인 결재 서신이 없습니다."
	AssetRegistry.apply_text_role(_inbox_empty_label, "caption")
	inbox_sec.add_child(_inbox_empty_label)

	# =========================================================================
	# RIGHT PANE: Character Creation + TK3K2 (Promoted Top!) + Gazette + Hegemony
	# =========================================================================
	var right_scroll: ScrollContainer = ScrollContainer.new()
	right_scroll.custom_minimum_size = Vector2(560, 0)
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_stretch_ratio = 1.04
	split.add_child(right_scroll)

	var right_col: VBoxContainer = VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 8)
	right_scroll.add_child(right_col)

	# 4. Character Creation Interview + TK3K2 Paste-Only Sealed Token Panel (Promoted to top of right pane)
	var cc_sec: VBoxContainer = _make_card_panel(right_col, true, AssetRegistry.COLOR_GOLD_ACCENT)
	_cc_icon = _make_header_with_icon(cc_sec, "장수 출사 인터뷰 & TK3K2 봉인 토큰")

	var cc_guide: Label = Label.new()
	cc_guide.text = "단계: ① 챌린지 발급 → ② 외부 AI 프롬프트 복사 → ③ TK3K2 토큰 붙여넣기(JSON 금지) → ④ 출사 확정"
	cc_guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	AssetRegistry.apply_text_role(cc_guide, "caption")
	cc_sec.add_child(cc_guide)

	var cc_row1: HBoxContainer = HBoxContainer.new()
	cc_row1.add_theme_constant_override("separation", 4)
	var n_lbl: Label = Label.new()
	n_lbl.text = "장수명:"
	AssetRegistry.apply_text_role(n_lbl, "caption")
	cc_row1.add_child(n_lbl)
	_cc_name_edit = LineEdit.new()
	_cc_name_edit.text = "Nameless_Hero"
	_cc_name_edit.custom_minimum_size = Vector2(125, 0)
	_cc_name_edit.placeholder_text = "장수 이름"
	cc_row1.add_child(_cc_name_edit)

	var m_lbl: Label = Label.new()
	m_lbl.text = "방식:"
	AssetRegistry.apply_text_role(m_lbl, "caption")
	cc_row1.add_child(m_lbl)
	_cc_mode_opt = OptionButton.new()
	_cc_mode_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cc_mode_opt.clip_text = true
	for cmi: int in range(DtoSchemas.CREATION_MODES.size()):
		var cm: String = DtoSchemas.CREATION_MODES[cmi]
		_cc_mode_opt.add_item(AssetRegistry.creation_mode_ko(cm))
		_cc_mode_opt.set_item_metadata(cmi, cm)
	_cc_mode_opt.select(1)  # FUSION_INTERVIEW default
	cc_row1.add_child(_cc_mode_opt)

	_cc_challenge_btn = Button.new()
	_cc_challenge_btn.text = "챌린지 발급"
	_cc_challenge_btn.pressed.connect(_on_request_challenge_pressed)
	cc_row1.add_child(_cc_challenge_btn)
	cc_sec.add_child(cc_row1)

	var cc_row_orig: HBoxContainer = HBoxContainer.new()
	cc_row_orig.add_theme_constant_override("separation", 4)
	var o_lbl: Label = Label.new()
	o_lbl.text = "출신:"
	AssetRegistry.apply_text_role(o_lbl, "caption")
	cc_row_orig.add_child(o_lbl)
	_cc_origin_opt = OptionButton.new()
	_cc_origin_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cc_origin_opt.clip_text = true
	for oi: int in range(DtoSchemas.ORIGIN_ARCHETYPES.size()):
		var orig: String = DtoSchemas.ORIGIN_ARCHETYPES[oi]
		_cc_origin_opt.add_item(AssetRegistry.origin_ko(orig))
		_cc_origin_opt.set_item_metadata(oi, orig)
	_cc_origin_opt.select(3)
	cc_row_orig.add_child(_cc_origin_opt)

	var prov_lbl: Label = Label.new()
	prov_lbl.text = "거점 주:"
	AssetRegistry.apply_text_role(prov_lbl, "caption")
	cc_row_orig.add_child(prov_lbl)
	_cc_province_opt = OptionButton.new()
	_cc_province_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cc_province_opt.clip_text = true
	var prov_list: Array[Dictionary] = [
		{"id": "YU_ZHOU", "name": "예주 (허창/여남)"},
		{"id": "XU_ZHOU", "name": "서주 (하비)"},
		{"id": "JI_ZHOU", "name": "기주 (업성/업현)"},
		{"id": "YI_ZHOU", "name": "익주 (성도)"},
		{"id": "YANG_ZHOU", "name": "양주 (건업)"},
		{"id": "YONG_LIANG", "name": "옹양주 (장안/낙양)"}
	]
	for pi: int in range(prov_list.size()):
		_cc_province_opt.add_item(str(prov_list[pi]["name"]))
		_cc_province_opt.set_item_metadata(pi, str(prov_list[pi]["id"]))
	cc_row_orig.add_child(_cc_province_opt)
	cc_sec.add_child(cc_row_orig)

	_cc_challenge_label = Label.new()
	_cc_challenge_label.text = "챌린지 상태: 미발급 (AI 융합 모드 사용 시 먼저 발급하세요)"
	AssetRegistry.apply_text_role(_cc_challenge_label, "caption")
	cc_sec.add_child(_cc_challenge_label)

	# Read-only prompt display (NEVER editable raw JSON box!)
	_cc_prompt_display = TextEdit.new()
	_cc_prompt_display.editable = false
	_cc_prompt_display.custom_minimum_size = Vector2(0, 56)
	_cc_prompt_display.text = "일회성 챌린지를 발급하면 외부 AI에 전달할 읽기 전용 프롬프트가 이곳에 표시됩니다."
	cc_sec.add_child(_cc_prompt_display)

	# Paste-only single-line sealed token input
	var tok_row: HBoxContainer = HBoxContainer.new()
	tok_row.add_theme_constant_override("separation", 6)
	var tok_lbl: Label = Label.new()
	tok_lbl.text = "TK3K2 봉인 토큰:"
	AssetRegistry.apply_text_role(tok_lbl, "caption")
	tok_row.add_child(tok_lbl)

	_cc_token_paste_edit = LineEdit.new()
	_cc_token_paste_edit.placeholder_text = "TK3K2-XXXXXX-XXXXXX-XXXXXX-XXXX-XX (평문 JSON 금지)"
	_cc_token_paste_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cc_token_paste_edit.text_changed.connect(_on_token_text_changed)
	tok_row.add_child(_cc_token_paste_edit)
	cc_sec.add_child(tok_row)

	_cc_preview_status_label = Label.new()
	_cc_preview_status_label.text = "토큰 검증 대기"
	AssetRegistry.apply_text_role(_cc_preview_status_label, "caption")
	cc_sec.add_child(_cc_preview_status_label)

	# 8-Question Interview Option Selectors in clean 2-column grid
	var q_titles: Array[String] = _load_interview_question_titles()
	var q_grid: GridContainer = GridContainer.new()
	q_grid.columns = 2
	q_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q_grid.add_theme_constant_override("h_separation", 8)
	q_grid.add_theme_constant_override("v_separation", 4)
	for qi: int in range(8):
		var q_opt: OptionButton = OptionButton.new()
		q_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		q_opt.clip_text = true
		var qt: String = q_titles[qi]
		q_opt.add_item("%s: A안" % qt)
		q_opt.add_item("%s: B안" % qt)
		q_opt.add_item("%s: C안" % qt)
		q_opt.add_item("%s: D안" % qt)
		q_grid.add_child(q_opt)
		_cc_interview_opts.append(q_opt)
	cc_sec.add_child(q_grid)

	_cc_submit_btn = Button.new()
	_cc_submit_btn.text = "장수 출사 확정"
	_cc_submit_btn.pressed.connect(_on_submit_cc_pressed)
	cc_sec.add_child(_cc_submit_btn)

	# 5. Reconnect Morning Court Gazette Modal/Card
	_gazette_panel = PanelContainer.new()
	_gazette_panel.visible = false
	_gazette_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gbox: VBoxContainer = VBoxContainer.new()
	gbox.add_theme_constant_override("separation", 4)
	_gazette_panel.add_child(gbox)

	_gazette_icon = _make_header_with_icon(gbox, "조보: 지난 밤의 사기 브리핑")

	_gazette_label = Label.new()
	_gazette_label.text = "조보 내역 없음"
	_gazette_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gbox.add_child(_gazette_label)

	var btn_close_g: Button = Button.new()
	btn_close_g.text = "조보 확인 닫기"
	btn_close_g.pressed.connect(_on_close_gazette_pressed)
	gbox.add_child(btn_close_g)
	right_col.add_child(_gazette_panel)

	var gaz_placeholder_sec: VBoxContainer = _make_card_panel(right_col, false)
	var gaz_ph_hdr: Label = Label.new()
	gaz_ph_hdr.text = "조보 브리핑 · 시즌 천하통일 결산"
	AssetRegistry.apply_text_role(gaz_ph_hdr, "section")
	gaz_placeholder_sec.add_child(gaz_ph_hdr)

	_gazette_empty_label = Label.new()
	_gazette_empty_label.text = "최근 수신된 조보가 없습니다. 오프라인 재접속 시 간밤의 수확과 전투 요약이 표시됩니다."
	_gazette_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	AssetRegistry.apply_text_role(_gazette_empty_label, "caption")
	gaz_placeholder_sec.add_child(_gazette_empty_label)

	# 6. Season Hegemony Leaderboard Panel
	var heg_sec: VBoxContainer = _make_card_panel(right_col, false)
	_hegemony_icon = _make_header_with_icon(heg_sec, "시즌 천하통일 결산 (천하 패자 · 개국 공신)")

	_hegemony_box = VBoxContainer.new()
	_hegemony_box.add_theme_constant_override("separation", 3)
	heg_sec.add_child(_hegemony_box)

	_hegemony_empty_label = Label.new()
	_hegemony_empty_label.text = "시즌 결산 집계 대기 중 (정기 결산 시 천하 패자와 개국 공신이 기록됩니다)."
	AssetRegistry.apply_text_role(_hegemony_empty_label, "caption")
	heg_sec.add_child(_hegemony_empty_label)


func _on_mkt_city_selected(idx: int) -> void:
	if _mkt_node_opt == null or idx < 0 or idx >= _mkt_node_opt.item_count:
		return
	var md: Variant = _mkt_node_opt.get_item_metadata(idx)
	if md is String and _mkt_node_edit != null:
		_mkt_node_edit.text = str(md)


func _get_option_meta_or_text(opt: OptionButton, fallback: String) -> String:
	if opt == null or opt.selected < 0:
		return fallback
	var md: Variant = opt.get_item_metadata(opt.selected)
	if md is String and not str(md).is_empty():
		return str(md)
	return opt.get_item_text(opt.selected)


func _on_place_order_pressed() -> void:
	var comm: String = _get_option_meta_or_text(_mkt_comm_opt, "GRAIN")
	var side: String = _get_option_meta_or_text(_mkt_side_opt, "BID")
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
	if _gazette_empty_label != null:
		_gazette_empty_label.visible = true


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
		_cc_preview_status_label.add_theme_color_override("font_color", AssetRegistry.COLOR_SUCCESS_JADE)
	else:
		var ec: String = str(check.get("error_code", DtoSchemas.ERR_TOKEN_FORMAT))
		_cc_preview_status_label.text = "거부됨: %s (평문 JSON이 아닌 TK3K2 토큰을 입력하세요)" % ec
		_cc_preview_status_label.add_theme_color_override("font_color", AssetRegistry.COLOR_DANGER_CRIMSON)


func _on_submit_cc_pressed() -> void:
	var mode: String = _get_option_meta_or_text(_cc_mode_opt, "INTERVIEW_ONLY")
	var answers: Array[int] = []
	for opt: OptionButton in _cc_interview_opts:
		answers.append(maxi(0, opt.selected))
	var fine: Dictionary = {}
	if _cc_origin_opt != null:
		fine["origin_override"] = _get_option_meta_or_text(_cc_origin_opt, "ORIGIN_CHIVALROUS_HERO")
	if _cc_province_opt != null:
		fine["province_override"] = _get_option_meta_or_text(_cc_province_opt, "YU_ZHOU")
	var _res: Dictionary = submit_character_creation(
		_cc_name_edit.text.strip_edges(),
		mode,
		answers,
		_cc_token_paste_edit.text,
		fine
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
			_cc_preview_status_label.add_theme_color_override("font_color", AssetRegistry.COLOR_DANGER_CRIMSON)
			if err_code == DtoSchemas.ERR_PLAINTEXT_JSON_FORBIDDEN:
				validation_error_emitted.emit(err_code)
			return {"ok": false, "error_code": err_code}

	var args: Dictionary = {
		"avatar_name": avatar_name if not avatar_name.is_empty() else "Nameless_Hero",
		"creation_mode": mode,
		"interview_answers": interview_answers.duplicate(),
		"sealed_token_input": sealed_token_input.strip_edges()
	}
	if fine_tuning.has("origin_override"):
		args["origin_override"] = str(fine_tuning["origin_override"])
	if fine_tuning.has("province_override"):
		args["province_override"] = str(fine_tuning["province_override"])
	if not fine_tuning.is_empty():
		args["fine_tuning"] = fine_tuning.duplicate(true)
	intent_emitted.emit("CMD_CREATE_CHARACTER", args)
	return {"ok": true, "error_code": DtoSchemas.ERR_OK}


func apply_challenge(challenge_msg: Dictionary) -> void:
	_last_challenge = challenge_msg.duplicate(true)
	var cid: String = str(challenge_msg.get("challenge_id", ""))
	var exp_t: int = _to_int(challenge_msg.get("ttl_expires_tick", 0), 0)
	_cc_challenge_label.text = "챌린지 ID: %s (만료 틱: %d)" % [cid, exp_t]
	_cc_challenge_label.add_theme_color_override("font_color", AssetRegistry.COLOR_SUCCESS_JADE)
	_cc_prompt_display.text = str(challenge_msg.get("prompt_text", ""))


func apply_gazette(digest_msg: Dictionary) -> void:
	_last_gazette = digest_msg.duplicate(true)
	var from_t: int = _to_int(digest_msg.get("from_tick", 0), 0)
	var to_t: int = _to_int(digest_msg.get("to_tick", 0), 0)

	var yields_v: Variant = digest_msg.get("net_yields", {})
	var yields: Dictionary = yields_v if yields_v is Dictionary else {}
	var yield_parts: PackedStringArray = PackedStringArray()
	for rk: Variant in yields.keys():
		var rk_s: String = str(rk)
		var _ok_y: bool = yield_parts.append("%s:%+d" % [AssetRegistry.resource_label_ko(rk_s), _to_int(yields[rk], 0)])

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
	if _gazette_empty_label != null:
		_gazette_empty_label.visible = false


func apply_snapshot(snapshot: Dictionary) -> void:
	# Faction & Court rank
	var fac_v: Variant = snapshot.get("faction", {})
	var fac: Dictionary = fac_v if fac_v is Dictionary else {}
	var prof_v: Variant = snapshot.get("player_profile", {})
	var prof: Dictionary = prof_v if prof_v is Dictionary else {}
	var fid: String = str(prof.get("faction_id", fac.get("faction_id", "무소속")))
	if fid.is_empty():
		fid = "무소속"
	var role_raw: String = str(prof.get("role_tier", "FREE_OFFICER"))
	var crank_raw: String = str(prof.get("court_rank", "NONE"))
	var rrank_raw: String = str(fac.get("royal_rank", "GOVERNOR_INSPECTOR"))
	var prestige_v: int = _to_int(fac.get("prestige", 0), 0)
	var t_coin: int = _to_int(fac.get("treasury_coin", 0), 0)
	var t_grain: int = _to_int(fac.get("treasury_grain", 0), 0)

	if _court_kpi_faction_val != null:
		_court_kpi_faction_val.text = AssetRegistry.faction_name_ko(fid)
	if _court_kpi_rank_val != null:
		_court_kpi_rank_val.text = "%s (%s)" % [AssetRegistry.role_ko(role_raw), AssetRegistry.rank_ko(rrank_raw)]
	if _court_kpi_coin_val != null:
		_court_kpi_coin_val.text = AssetRegistry.format_num(t_coin)
	if _court_kpi_grain_val != null:
		_court_kpi_grain_val.text = AssetRegistry.format_num(t_grain)

	# Keep _court_label containing raw faction_id, role_tier, royal_rank tokens for existing tests
	_court_label.text = "세력: %s | 신분: %s | 품계: %s | 작위: %s | 위명: %d | 국고(전/량): %d / %d" % [
		fid, role_raw, crank_raw, rrank_raw, prestige_v, t_coin, t_grain
	]

	for ch_m: Node in _members_box.get_children():
		_members_box.remove_child(ch_m)
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
				mlbl.text = "동료 %s · %s (%s) · 공적 %s" % [
					mk,
					AssetRegistry.role_ko(str(mdict.get("role_tier", "FACTION_OFFICER"))),
					AssetRegistry.rank_ko(str(mdict.get("court_rank", "RANK_9"))),
					AssetRegistry.format_num(_to_int(mdict.get("war_merit", 0), 0))
				]
				AssetRegistry.apply_text_role(mlbl, "caption")
				_members_box.add_child(mlbl)

	# Market prices & order book
	if snapshot.has("prices") and snapshot["prices"] is Dictionary:
		var pr_d: Dictionary = snapshot["prices"]
		for k: Variant in pr_d.keys():
			_cached_prices[str(k)] = _to_int(pr_d[k], 1000)
	var p_parts: PackedStringArray = PackedStringArray()
	for comm: String in DtoSchemas.MARKET_COMMODITIES:
		if _cached_prices.has(comm):
			var _ok_p: bool = p_parts.append("%s %s" % [AssetRegistry.resource_label_ko(comm), AssetRegistry.format_num(_to_int(_cached_prices[comm], 1000))])
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
		_orders_box.remove_child(ch_o)
		ch_o.queue_free()
	var okeys: Array[String] = []
	for k_o: Variant in _cached_orders.keys():
		okeys.append(str(k_o))
	okeys.sort()
	if _orders_empty_label != null:
		_orders_empty_label.visible = okeys.is_empty()
	for oid: String in okeys:
		var od: Dictionary = _cached_orders[oid]
		var side_s: String = str(od.get("side", "BID"))
		var comm_s: String = str(od.get("commodity", "GRAIN"))
		var olbl: Label = Label.new()
		olbl.text = "%s | %s %s | 단가 %s bp | 잔량 %s" % [
			oid,
			"매수(BID)" if side_s == "BID" else "매도(ASK)",
			AssetRegistry.resource_label_ko(comm_s),
			AssetRegistry.format_num(_to_int(od.get("price_bp", 1000), 1000)),
			AssetRegistry.format_num(_to_int(od.get("remaining_qty", 0), 0))
		]
		olbl.add_theme_color_override("font_color", AssetRegistry.COLOR_SUCCESS_JADE if side_s == "BID" else AssetRegistry.COLOR_DANGER_CRIMSON)
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
		_inbox_box.remove_child(ch_i)
		ch_i.queue_free()
	if _inbox_empty_label != null:
		_inbox_empty_label.visible = _cached_inbox.is_empty()
	for dec: Dictionary in _cached_inbox:
		var did: String = str(dec.get("decision_id", ""))
		var etype: String = str(dec.get("event_type", "EVENT"))
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var ilbl: Label = Label.new()
		ilbl.text = "[%s] %s (만료:%d틱)" % [did, AssetRegistry.inbox_label_ko(etype), _to_int(dec.get("deadline_tick", 0), 0)]
		ilbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(ilbl)
		var opts_v: Variant = dec.get("options", [])
		if opts_v is Array:
			var opts: Array = opts_v
			for oi: int in range(opts.size()):
				var opt_s: String = str(opts[oi])
				var b: Button = Button.new()
				b.text = AssetRegistry.inbox_label_ko(opt_s)
				if _assets != null:
					_assets.apply_button_variant(b, "primary" if oi == 0 else "danger")
				b.pressed.connect(emit_decide_inbox_event.bind(did, opt_s))
				row.add_child(b)
		_inbox_box.add_child(row)

	# Season Hegemony leaderboard
	if snapshot.has("season_settlement") and snapshot["season_settlement"] is Dictionary:
		var set_d: Dictionary = snapshot["season_settlement"]
		for ch_h: Node in _hegemony_box.get_children():
			_hegemony_box.remove_child(ch_h)
			ch_h.queue_free()
		var heg_cnt: int = 0
		var heg_v: Variant = set_d.get("hegemon", {})
		if heg_v is Dictionary:
			var heg: Dictionary = heg_v
			if not heg.is_empty():
				var hl: Label = Label.new()
				hl.text = "%s: %s (%s) 점수=%s" % [
					SeasonHegemonyService.HEGEMON_TITLE_KO,
					str(heg.get("faction_name", heg.get("faction_id", ""))),
					str(heg.get("lord_player_id", "")),
					AssetRegistry.format_num(_to_int(heg.get("score", 0), 0))
				]
				_hegemony_box.add_child(hl)
				heg_cnt += 1
		var top_v: Variant = set_d.get("top_merit_officer", {})
		if top_v is Dictionary:
			var top_o: Dictionary = top_v
			if not top_o.is_empty():
				var ol: Label = Label.new()
				ol.text = "%s: %s 점수=%s" % [
					SeasonHegemonyService.TOP_OFFICER_TITLE_KO,
					str(top_o.get("player_id", "")),
					AssetRegistry.format_num(_to_int(top_o.get("score", 0), 0))
				]
				_hegemony_box.add_child(ol)
				heg_cnt += 1
		if _hegemony_empty_label != null:
			_hegemony_empty_label.visible = (heg_cnt == 0)


func is_gazette_visible() -> bool:
	return _gazette_panel != null and _gazette_panel.visible


func reset_view_state() -> void:
	_cached_orders.clear()
	_cached_prices.clear()
	_cached_inbox.clear()
	_last_gazette.clear()
	_last_challenge.clear()
	if _court_kpi_faction_val != null:
		_court_kpi_faction_val.text = "무소속"
	if _court_kpi_rank_val != null:
		_court_kpi_rank_val.text = "재야 장수"
	if _court_kpi_coin_val != null:
		_court_kpi_coin_val.text = "0"
	if _court_kpi_grain_val != null:
		_court_kpi_grain_val.text = "0"
	if _court_label != null:
		_court_label.text = "세력: 무소속 | 신분: FREE_OFFICER | 품계: NONE | 작위: GOVERNOR_INSPECTOR"
	if _market_prices_label != null:
		_market_prices_label.text = "시세(bp): 군량 1,000 | 철광 2,000 | 목재 1,500"
	if _members_box != null:
		for ch_m: Node in _members_box.get_children():
			_members_box.remove_child(ch_m)
			ch_m.queue_free()
	if _orders_box != null:
		for ch_o: Node in _orders_box.get_children():
			_orders_box.remove_child(ch_o)
			ch_o.queue_free()
	if _orders_empty_label != null:
		_orders_empty_label.visible = true
	if _inbox_box != null:
		for ch_i: Node in _inbox_box.get_children():
			_inbox_box.remove_child(ch_i)
			ch_i.queue_free()
	if _inbox_empty_label != null:
		_inbox_empty_label.visible = true
	if _hegemony_box != null:
		for ch_h: Node in _hegemony_box.get_children():
			_hegemony_box.remove_child(ch_h)
			ch_h.queue_free()
	if _hegemony_empty_label != null:
		_hegemony_empty_label.visible = true
	if _gazette_label != null:
		_gazette_label.text = "조보 내역 없음"
	if _gazette_panel != null:
		_gazette_panel.visible = false
	if _gazette_empty_label != null:
		_gazette_empty_label.visible = true
	if _cc_challenge_label != null:
		_cc_challenge_label.text = "챌린지 상태: 미발급 (AI 융합 모드 사용 시 먼저 발급하세요)"
	if _cc_prompt_display != null:
		_cc_prompt_display.text = "일회성 챌린지를 발급하면 외부 AI에 전달할 읽기 전용 프롬프트가 이곳에 표시됩니다."
	if _cc_preview_status_label != null:
		_cc_preview_status_label.text = "토큰 검증 대기"
