class_name TestSeasonHegemonyAndClientUI
extends HarnessTestCase

var _ui_nodes: Array[Node] = []


func _track_ui(node: Node) -> Node:
	if node != null and not _ui_nodes.has(node):
		_ui_nodes.append(node)
		var loop: MainLoop = Engine.get_main_loop()
		if loop is SceneTree:
			var st: SceneTree = loop
			if st.root != null and node.get_parent() == null:
				st.root.add_child(node)
	return node


func after_each() -> void:
	for i: int in range(_ui_nodes.size() - 1, -1, -1):
		var n: Node = _ui_nodes[i]
		if n != null and is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_ui_nodes.clear()



func _as_bool(v: Variant, fallback: bool = false) -> bool:
	if v is bool:
		var bv: bool = v
		return bv
	return fallback


func _as_int(v: Variant, fallback: int = 0) -> int:
	if v is int:
		var iv: int = v
		return iv
	if v is float:
		var fv: float = v
		return int(fv)
	return fallback


func _as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		var d: Dictionary = v
		return d
	return {}


func _as_array(v: Variant) -> Array:
	if v is Array:
		var a: Array = v
		return a
	return []


func test_season_settlement_lord_and_officer_leaderboards_scoring_and_tiebreakers() -> void:
	var svc: SeasonHegemonyService = SeasonHegemonyService.new()

	# Craft snapshot testing:
	# - Lord scoring: controlled_cities * 500 + royal_tier * 800 + prestige + treasury / 100
	# - Lexicographical tie-breaker on faction_id ("fac_alpha" < "fac_beta")
	# - NEUTRAL and 0-city YELLOW_TURBAN (npc_zhang_jiao) skipped
	# - Officer scoring: war_merit + court_tier * 400 + sworn_siblings * 250 + proposals_adopted * 150
	# - Lexicographical tie-breaker on player_id ("p_alpha" < "p_beta")
	# - NPCs skipped
	var snapshot: Dictionary = {
		"tick_id": 1440,
		"faction_manager": {
			"factions": {
				"NEUTRAL": {
					"faction_id": "NEUTRAL",
					"name": "중립",
					"lord_player_id": "npc_neutral_lord",
					"royal_rank": "EMPEROR",
					"prestige": 99999,
					"treasury_coin": 99999,
					"treasury_grain": 99999
				},
				"YELLOW_TURBAN": {
					"faction_id": "YELLOW_TURBAN",
					"name": "황건적",
					"lord_player_id": "npc_zhang_jiao",
					"royal_rank": "GOVERNOR_INSPECTOR",
					"prestige": 5000,
					"treasury_coin": 5000,
					"treasury_grain": 5000
				},
				"fac_beta": {
					"faction_id": "fac_beta",
					"name": "Beta Wei",
					"lord_player_id": "p_beta",
					"royal_rank": "DUKE", # tier 3 -> 2400
					"prestige": 600,
					"treasury_coin": 10000,
					"treasury_grain": 10000 # 20000 / 100 = 200
					# 2 cities * 500 = 1000 -> total = 1000 + 2400 + 600 + 200 = 4200
				},
				"fac_alpha": {
					"faction_id": "fac_alpha",
					"name": "Alpha Shu",
					"lord_player_id": "p_alpha",
					"royal_rank": "DUKE", # tier 3 -> 2400
					"prestige": 600,
					"treasury": 20099 # 20099 / 100 = 200 (integer truncation)
					# 2 cities * 500 = 1000 -> total = 1000 + 2400 + 600 + 200 = 4200 (ties fac_beta!)
				},
				"fac_gamma": {
					"faction_id": "fac_gamma",
					"name": "Gamma Wu",
					"lord_player_id": "p_gamma",
					"royal_rank": "KING", # tier 4 -> 3200
					"prestige": 1500,
					"treasury_coin": 5000,
					"treasury_grain": 5000 # 10000 / 100 = 100
					# 1 city * 500 = 500 -> total = 500 + 3200 + 1500 + 100 = 5300 (winner!)
				}
			},
			"players": {
				"npc_neutral_lord": {"player_id": "npc_neutral_lord", "war_merit": 99999, "court_rank": "SOVEREIGN"},
				"npc_zhang_jiao": {"player_id": "npc_zhang_jiao", "war_merit": 99999, "court_rank": "SOVEREIGN"},
				"p_beta": {
					"player_id": "p_beta",
					"faction_id": "fac_beta",
					"role_tier": "FACTION_OFFICER",
					"court_rank": "RANK_5", # tier 5 -> 2000
					"war_merit": 1000
					# sworn: 1 (*250=250), adopted proposals: 1 (*150=150) -> 1000 + 2000 + 250 + 150 = 3400
				},
				"p_alpha": {
					"player_id": "p_alpha",
					"faction_id": "fac_alpha",
					"role_tier": "FACTION_OFFICER",
					"court_rank": "RANK_5", # tier 5 -> 2000
					"war_merit": 1400
					# sworn: 0, proposals: 0 -> 1400 + 2000 = 3400 (ties p_beta!)
				},
				"p_gamma": {
					"player_id": "p_gamma",
					"faction_id": "fac_gamma",
					"role_tier": "LORD",
					"court_rank": "SOVEREIGN", # tier 10 -> 4000
					"war_merit": 1200
					# sworn: 2 (*250=500), adopted proposals: 2 (*150=300) -> 1200 + 4000 + 500 + 300 = 6000 (winner!)
				}
			},
			"proposals": [
				{"proposal_id": "prop_1", "status": "ADOPTED", "owner_player_id": "p_beta"},
				{"proposal_id": "prop_2", "status": "REJECTED", "owner_player_id": "p_beta"},
				{"proposal_id": "prop_3", "status": "ADOPTED", "pawn_id": "p_gamma_avatar"},
				{"proposal_id": "prop_4", "status": "ADOPTED", "owner_player_id": "p_gamma"}
			]
		},
		"world_graph": {
			"nodes": {
				"n1": {"owner_faction_id": "fac_alpha"},
				"n2": {"owner_faction_id": "fac_alpha"},
				"n3": {"owner_faction_id": "fac_beta"},
				"n4": {"owner_faction_id": "fac_beta"},
				"n5": {"owner_faction_id": "fac_gamma"},
				"n6": {"owner_faction_id": "NEUTRAL"}
			}
		},
		"social_service": {
			"relation_tags": {
				"p_beta_avatar->p_alpha_avatar": ["SWORN_SIBLING"],
				"p_beta->p_alpha_avatar": ["SWORN_SIBLING"], # duplicate normalized pair -> still 1
				"p_gamma_avatar->p_alpha_avatar": ["SWORN_SIBLING"],
				"p_gamma_avatar->p_beta_avatar": ["SWORN_SIBLING"],
				"p_alpha_avatar->p_beta_avatar": ["RIVAL"] # not SWORN_SIBLING
			}
		}
	}

	var res: Dictionary = svc.compute_season_settlement(snapshot, 1)
	assert_eq(_as_int(res.get("season_number", 0)), 1, "season_number == 1")
	assert_eq(_as_int(res.get("tick_id", 0)), 1440, "tick_id == 1440")
	assert_eq(str(res.get("hegemon_title", "")), "천하 패자", "hegemon_title == 천하 패자")
	assert_eq(str(res.get("top_officer_title", "")), "개국 공신", "top_officer_title == 개국 공신")

	var lord_board: Array = _as_array(res.get("lord_leaderboard", []))
	assert_eq(lord_board.size(), 3, "NEUTRAL and 0-city YELLOW_TURBAN excluded from lord_leaderboard")

	var l0: Dictionary = _as_dict(lord_board[0])
	var l1: Dictionary = _as_dict(lord_board[1])
	var l2: Dictionary = _as_dict(lord_board[2])
	assert_eq(str(l0.get("faction_id", "")), "fac_gamma", "Rank 1 lord is fac_gamma")
	assert_eq(_as_int(l0.get("score", 0)), 5300, "fac_gamma exact integer score == 5300")
	assert_eq(_as_int(l0.get("rank", 0)), 1, "fac_gamma rank == 1")
	assert_eq(str(l0.get("title", "")), "천하 패자", "Rank 1 lord holds 천하 패자 title")

	assert_eq(str(l1.get("faction_id", "")), "fac_alpha", "Tie-breaker puts fac_alpha ahead of fac_beta")
	assert_eq(_as_int(l1.get("score", 0)), 4200, "fac_alpha exact score == 4200")
	assert_eq(_as_int(l1.get("rank", 0)), 2, "fac_alpha rank == 2")
	assert_eq(str(l1.get("title", "")), "", "Rank 2 lord has empty title")

	assert_eq(str(l2.get("faction_id", "")), "fac_beta", "fac_beta ranked 3rd after tie-break")
	assert_eq(_as_int(l2.get("score", 0)), 4200, "fac_beta exact score == 4200")
	assert_eq(_as_int(l2.get("rank", 0)), 3, "fac_beta rank == 3")

	var off_board: Array = _as_array(res.get("officer_leaderboard", []))
	assert_eq(off_board.size(), 3, "NPC players excluded from officer_leaderboard")

	var o0: Dictionary = _as_dict(off_board[0])
	var o1: Dictionary = _as_dict(off_board[1])
	var o2: Dictionary = _as_dict(off_board[2])
	assert_eq(str(o0.get("player_id", "")), "p_gamma", "Rank 1 officer is p_gamma")
	assert_eq(_as_int(o0.get("score", 0)), 6000, "p_gamma exact officer score == 6000")
	assert_eq(str(o0.get("title", "")), "개국 공신", "Rank 1 officer holds 개국 공신 title")

	assert_eq(str(o1.get("player_id", "")), "p_alpha", "Tie-breaker puts p_alpha ahead of p_beta")
	assert_eq(_as_int(o1.get("score", 0)), 3400, "p_alpha exact officer score == 3400")
	assert_eq(str(o1.get("title", "")), "", "Rank 2 officer has empty title")

	assert_eq(str(o2.get("player_id", "")), "p_beta", "p_beta ranked 3rd after tie-break")
	assert_eq(_as_int(o2.get("score", 0)), 3400, "p_beta exact officer score == 3400")
	assert_eq(_as_int(o2.get("sworn_siblings", 0)), 1, "Normalized duplicate sworn edge counted once")
	assert_eq(_as_int(o2.get("proposals_adopted", 0)), 1, "Only ADOPTED proposal counted for p_beta")

	# Determinism: fresh service computing same snapshot yields identical SHA-256
	var svc2: SeasonHegemonyService = SeasonHegemonyService.new()
	var res2: Dictionary = svc2.compute_season_settlement(snapshot, 1)
	assert_eq(StateHasher.sha256_dict(res), StateHasher.sha256_dict(res2), "Settlement output is deterministic")
	assert_eq(svc.season_history.size(), 1, "season_history recorded 1 settlement")


func test_season_settlement_includes_yellow_turban_if_holding_city_and_flat_arrays() -> void:
	var svc: SeasonHegemonyService = SeasonHegemonyService.new()
	var flat_snap: Dictionary = {
		"tick_id": 720,
		"factions": [
			{
				"faction_id": "YELLOW_TURBAN",
				"name": "황건적",
				"lord_player_id": "npc_zhang_jiao",
				"royal_rank": "DUKE",
				"prestige": 100,
				"treasury": 500
			}
		],
		"players": [
			{
				"player_id": "hero_01",
				"faction_id": "YELLOW_TURBAN",
				"court_rank": "RANK_9",
				"war_merit": 250,
				"sworn_siblings": ["hero_02", "hero_03"],
				"proposals_adopted": 2
			}
		],
		"nodes": [
			{"node_id": "ye_city", "owner_faction_id": "YELLOW_TURBAN"}
		]
	}

	var res: Dictionary = svc.compute_season_settlement(flat_snap, 0)
	assert_eq(_as_int(res.get("season_number", 0)), 1, "Season clamped to >= 1")
	var lords: Array = _as_array(res.get("lord_leaderboard", []))
	assert_eq(lords.size(), 1, "YELLOW_TURBAN included when controlling >= 1 city")
	var l0: Dictionary = _as_dict(lords[0])
	# 1*500 + 3*800 + 100 + 5 = 3005
	assert_eq(_as_int(l0.get("score", 0)), 3005, "YELLOW_TURBAN score == 3005")

	var officers: Array = _as_array(res.get("officer_leaderboard", []))
	assert_eq(officers.size(), 1, "1 officer in flat leaderboard")
	var o0: Dictionary = _as_dict(officers[0])
	# 250 + 1*400 + 2*250 + 2*150 = 1450
	assert_eq(_as_int(o0.get("score", 0)), 1450, "hero_01 score == 1450")


func test_lineage_heir_mentorship_xp_surname_motto_and_320_budget_fairness() -> void:
	var svc: SeasonHegemonyService = SeasonHegemonyService.new()

	# Adversarial mentor with wildly inflated stats & double passion
	var inflated_mentor: Dictionary = {
		"pawn_id": "p1_avatar",
		"name": "Liu_Bei",
		"owner_player_id": "player_01",
		"origin_archetype": "ORIGIN_FALLEN_ROYAL",
		"stats": {"LEA": 999, "MAR": 450, "INT": 120, "POL": 100, "CHA": 800},
		"passions_pm": {"LEA": 1500, "MAR": 1250, "INT": 1000, "POL": 1000, "CHA": 1500}
	}

	var long_motto: String = "1234567890123456789012345678901234567890EXTRA_CHARS_MUST_BE_TRUNCATED"
	var heir1: Dictionary = svc.create_lineage_heir(inflated_mentor, "  Liu_Shan  ", long_motto, 18401, 2000)

	assert_eq(str(heir1.get("inherited_surname", "")), "Liu", "Surname extracted from underscore mentor name")
	assert_eq(str(heir1.get("heir_name", "")), "Liu_Shan", "Heir name trimmed")
	assert_eq(str(heir1.get("family_motto", "")).length(), 40, "Family motto capped at 40 chars")
	assert_eq(str(heir1.get("origin_archetype", "")), "ORIGIN_FALLEN_ROYAL", "Origin archetype inherited")

	var stats: Dictionary = _as_dict(heir1.get("stats", {}))
	var sum_stats: int = 0
	for sk: String in DtoSchemas.STAT_KEYS:
		var sv: int = _as_int(stats.get(sk, 0))
		assert_in_range(sv, DtoSchemas.STAT_MIN_BASE, DtoSchemas.STAT_MAX_BASE, "Heir stat %s in [35, 85]" % sk)
		sum_stats += sv
	assert_eq(sum_stats, DtoSchemas.TOTAL_STAT_BUDGET, "Heir stats sum strictly == 320")
	assert_eq(_as_int(heir1.get("total_stat_budget", 0)), DtoSchemas.TOTAL_STAT_BUDGET, "Recorded total_stat_budget == 320")

	var xp_boost: int = _as_int(heir1.get("mentorship_xp_boost_pm", 0))
	assert_in_range(xp_boost, 50, 120, "mentorship_xp_boost_pm bounded in [50, 120]")

	var passion_pts: int = _as_int(heir1.get("passion_points_used", -1), -1)
	assert_lte(passion_pts, DtoSchemas.PASSION_BUDGET, "Heir passion points <= PASSION_BUDGET")
	assert_eq(passion_pts, 1, "Heir inherits bounded single passion point")
	var passions: Dictionary = _as_dict(heir1.get("passions_pm", {}))
	assert_eq(_as_int(passions.get("LEA", 0)), PawnEntity.PASSION_SINGLE_PM, "Best mentor passion inherited as single passion (1250 pm)")

	# Determinism check for mentorship_xp_boost_pm across fresh instance
	var svc_det: SeasonHegemonyService = SeasonHegemonyService.new()
	var heir1_det: Dictionary = svc_det.create_lineage_heir(inflated_mentor, "Liu_Shan", long_motto, 18401, 2000)
	assert_eq(_as_int(heir1_det.get("mentorship_xp_boost_pm", 0)), xp_boost, "Mentorship XP boost is deterministic")
	assert_eq(StateHasher.sha256_dict(heir1), StateHasher.sha256_dict(heir1_det), "Lineage heir record is deterministic")

	# Test space-separated, Korean single-word, and empty fallbacks + multi-seed [50,120] bounds
	var mentor_sp: Dictionary = {"pawn_id": "m2", "name": "Cao Cao", "owner_player_id": "p2"}
	var heir2: Dictionary = svc.create_lineage_heir(mentor_sp, "", "", 18401, 2100)
	assert_eq(str(heir2.get("inherited_surname", "")), "Cao", "Surname extracted from space-separated mentor name")
	assert_eq(str(heir2.get("heir_name", "")), "후계자", "Empty heir_name falls back to 후계자")
	assert_eq(str(heir2.get("family_motto", "")), "가문의 대의를 잇는다", "Empty motto falls back to default motto")

	var mentor_ko: Dictionary = {"pawn_id": "m3", "name": "제갈량", "owner_player_id": "p3"}
	var heir3: Dictionary = svc.create_lineage_heir(mentor_ko, "제갈첨", "충효", 18401, 2200)
	assert_eq(str(heir3.get("inherited_surname", "")), "제", "Single-word Korean surname extracted")

	var mentor_empty: Dictionary = {"pawn_id": "m4", "name": "", "owner_player_id": "p4"}
	var heir4: Dictionary = svc.create_lineage_heir(mentor_empty, "무명후계", "가훈", 18401, 2300)
	assert_eq(str(heir4.get("inherited_surname", "")), "무명", "Empty mentor name falls back to 무명")

	for step: int in range(10):
		var h_sample: Dictionary = svc.create_lineage_heir(inflated_mentor, "Heir_%d" % step, "Motto", 9000 + step, 100 + step * 17)
		assert_in_range(_as_int(h_sample.get("mentorship_xp_boost_pm", 0)), 50, 120, "Sample %d xp boost in [50, 120]" % step)


func test_season_hegemony_service_canonical_roundtrip_and_zero_floats() -> void:
	var svc: SeasonHegemonyService = SeasonHegemonyService.new()
	var snap: Dictionary = {
		"tick_id": 500,
		"factions": [
			{"faction_id": "fac_1", "name": "Han", "lord_player_id": "p1", "royal_rank": "KING", "prestige": 800, "treasury": 4500}
		],
		"players": [
			{"player_id": "p1", "faction_id": "fac_1", "court_rank": "RANK_2", "war_merit": 2000}
		],
		"nodes": [
			{"node_id": "luoyang", "owner_faction_id": "fac_1"}
		]
	}
	var _s: Dictionary = svc.compute_season_settlement(snap, 1)
	var _h: Dictionary = svc.create_lineage_heir({"pawn_id": "p1_avatar", "name": "Han_Xin", "owner_player_id": "p1", "stats": {"LEA": 80, "MAR": 75, "INT": 70, "POL": 50, "CHA": 45}}, "Han_Junior", "Loyalty", 18401, 500)

	var d: Dictionary = svc.to_dict()
	assert_false(StateHasher.has_floats(d), "SeasonHegemonyService.to_dict() has zero floats")
	assert_true(StateHasher.validate_deterministic_types(d), "SeasonHegemonyService.to_dict() uses only deterministic types")

	var restored: SeasonHegemonyService = SeasonHegemonyService.from_dict(d)
	assert_eq(restored.season_history.size(), 1, "Restored season_history size == 1")
	assert_eq(restored.lineage_records.size(), 1, "Restored lineage_records size == 1")
	assert_eq(StateHasher.sha256_dict(restored.to_dict()), StateHasher.sha256_dict(d), "Canonical SHA-256 parity after to_dict/from_dict")


func test_client_controller_tab_switching_and_cc_modal_in_headless() -> void:
	var cc: ClientController = ClientController.new()
	var _tracked: Node = _track_ui(cc)

	assert_eq(cc.get_tab_count(), 4, "ClientController has 4 view tabs")
	assert_not_null(cc.manor_view, "ManorGridView instantiated")
	assert_not_null(cc.priority_view, "WorkPriorityScheduleView instantiated")
	assert_not_null(cc.macro_view, "MacroMapView instantiated")
	assert_not_null(cc.court_hud, "CourtMarketGazetteHUD instantiated")
	assert_not_null(cc._tab_container, "TabContainer created")
	assert_eq(cc.get_active_tab_index(), 0, "Initial active tab index is 0")
	assert_true(cc.manor_view.visible, "Manor view is visible")
	assert_false(cc.priority_view.visible, "Priority view is hidden")
	assert_false(cc.macro_view.visible, "Macro view is hidden")
	assert_false(cc.court_hud.visible, "Court hud is hidden")

	cc.switch_tab(1)
	assert_eq(cc.get_active_tab_index(), 1, "Switched to active tab index 1")
	assert_false(cc.manor_view.visible, "Manor view is hidden")
	assert_true(cc.priority_view.visible, "Priority view is visible")
	assert_false(cc.macro_view.visible, "Macro view is hidden")
	assert_false(cc.court_hud.visible, "Court hud is hidden")

	cc.switch_tab(2)
	assert_eq(cc.get_active_tab_index(), 2, "Switched to active tab index 2")
	assert_false(cc.manor_view.visible, "Manor view is hidden")
	assert_false(cc.priority_view.visible, "Priority view is hidden")
	assert_true(cc.macro_view.visible, "Macro view is visible")
	assert_false(cc.court_hud.visible, "Court hud is hidden")

	cc.switch_tab(3)
	assert_eq(cc.get_active_tab_index(), 3, "Switched to active tab index 3")
	assert_false(cc.manor_view.visible, "Manor view is hidden")
	assert_false(cc.priority_view.visible, "Priority view is hidden")
	assert_false(cc.macro_view.visible, "Macro view is hidden")
	assert_true(cc.court_hud.visible, "Court hud is visible")

	cc.switch_tab(0)
	assert_eq(cc.get_active_tab_index(), 0, "Switched back to active tab index 0")
	assert_true(cc.manor_view.visible, "Manor view is visible")

	# Boundary/invalid tab indices should not crash or alter active tab
	cc.switch_tab(-1)
	assert_eq(cc.get_active_tab_index(), 0, "Negative tab index ignored")
	cc.switch_tab(4)
	assert_eq(cc.get_active_tab_index(), 0, "Out-of-bounds tab index ignored")

	# Character creation modal opens and confirmation jumps to tab 3
	assert_not_null(cc._cc_modal, "Character Creation modal dialog exists")
	assert_false(cc._cc_modal.visible, "CC modal hidden initially")
	cc._cc_modal_btn.pressed.emit()
	assert_true(cc._cc_modal.visible, "CC modal becomes visible when button pressed")
	cc._cc_modal.confirmed.emit()
	assert_eq(cc.get_active_tab_index(), 3, "Confirming CC modal switches active tab to 3")
	assert_true(cc.court_hud.visible, "Court hud visible after confirmation")
	assert_false(cc.court_hud._cc_prompt_display.editable, "Prompt display TextEdit is strictly read-only")



func test_client_controller_server_deltas_gazette_challenge_update_views_without_mutating_server() -> void:
	var srv: AuthoritativeServer = AuthoritativeServer.new(18401, "ST_SIMA_QIAN")
	var _reg: Dictionary = srv.register_session("peer_1", "player_01", "Hero01")
	var _create: Dictionary = srv.submit_raw_command("peer_1", JSON.stringify({
		"v": 1, "cmd_seq": 1, "client_tick": 0, "player_id": "player_01",
		"cmd_type": "CMD_CREATE_CHARACTER",
		"args": {
			"avatar_name": "Hero01",
			"creation_mode": "INTERVIEW_ONLY",
			"interview_answers": [0, 1, 2, 0, 1, 2, 0, 1]
		}
	}))
	var _t_step0: Dictionary = srv.step_micro_tick()
	var _fac: Dictionary = srv.faction_manager.create_faction("fac_han", "Han", "player_01", "xuchang", srv.world_graph, 8000, 9000, "DUKE")
	var _sub_fac: bool = srv.interest_manager.subscribe("peer_1", DtoSchemas.CHAN_FACTION + ":fac_han")
	var _sub_node: bool = srv.interest_manager.subscribe("peer_1", DtoSchemas.CHAN_NODE + ":xuchang")
	var _ord: Dictionary = srv.regional_market.place_order("xuchang", "player_01", "GRAIN", "ASK", 1200, 20, 1)
	var _arm: Dictionary = srv.army_manager.spawn_entity({
		"entity_id": "army_han_01",
		"faction_id": "fac_han",
		"node_id": "xuchang",
		"path": ["e_xuchang_luoyang"],
		"soldiers": 200,
		"morale": 300
	}, srv.world_graph)
	var _t_step: Dictionary = srv.step_micro_tick()

	srv.chronicle_inbox.mark_player_offline("player_01", 1, {"GRAIN": 500, "COIN": 500})
	srv.chronicle_inbox.record_offline_event("player_01", ChronicleInboxService.CATEGORY_STIPEND, {"tick_id": 2, "coin": 150, "grain": 300})
	var gazette_msg: Dictionary = srv.chronicle_inbox.build_reconnect_gazette("player_01", 1, 5, {"GRAIN": 800, "COIN": 650})
	var v_gaz: Dictionary = DtoSchemas.validate_offline_chronicle_digest(gazette_msg)
	assert_true(_as_bool(v_gaz.get("ok", false)), "Gazette passes validate_offline_chronicle_digest")

	var srv_crc_before: int = srv.compute_state_crc32()

	var cc: ClientController = ClientController.new()
	var _tracked: Node = _track_ui(cc)
	cc.player_id = "player_01"

	var gazette_signals: Array[Dictionary] = []
	var challenge_signals: Array[Dictionary] = []
	cc.gazette_received.connect(func(msg: Dictionary) -> void: gazette_signals.append(msg))
	cc.challenge_received.connect(func(msg: Dictionary) -> void: challenge_signals.append(msg))

	# 1. Build real MSG_TICK_DELTA from server and feed to ClientController
	var delta_msg: Dictionary = srv.interest_manager.build_tick_delta_for_peer("peer_1", {
		"clock": srv.clock,
		"tick_id": srv.clock.current_tick_id,
		"macro_tick_id": srv.clock.get_macro_tick_id(),
		"day_id": srv.clock.get_day_id(),
		"season": srv.clock.get_season(),
		"state_crc32": srv_crc_before,
		"world_graph": srv.world_graph,
		"army_manager": srv.army_manager,
		"faction_manager": srv.faction_manager,
		"diplomacy": srv.diplomacy_engine,
		"siege_resolver": srv.siege_resolver,
		"regional_market": srv.regional_market,
		"manors": srv.manors
	})
	var v_delta: Dictionary = DtoSchemas.validate_tick_delta(delta_msg)
	assert_true(_as_bool(v_delta.get("ok", false)), "Server delta passes validate_tick_delta")

	cc.apply_server_message(delta_msg)
	assert_eq(cc.client_tick, srv.clock.current_tick_id, "client_tick updated from MSG_TICK_DELTA")
	assert_eq(cc.last_state_crc32, srv_crc_before, "last_state_crc32 updated from MSG_TICK_DELTA")
	assert_contains(cc._top_bar_label.text, "player_01", "Top bar shows player_id")
	assert_contains(cc.manor_view._header_label.text, "manor_player_01", "ManorGridView header updated")
	assert_contains(cc.manor_view._resources_label.text, "GRAIN:", "ManorGridView resources bar updated")
	assert_gte(cc.manor_view._pawns_box.get_child_count(), 2, "ManorGridView displays avatar + retainer pawns")
	assert_gte(cc.priority_view._pawn_selector.item_count, 2, "WorkPriorityScheduleView populated pawn selector")
	assert_eq(cc.macro_view.get_node_count(), 15, "MacroMapView holds all 15 world nodes")
	assert_eq(cc.macro_view._armies_box.get_child_count(), 1, "MacroMapView displays dispatched army")
	assert_contains(cc.court_hud._court_label.text, "DUKE", "CourtHUD updated royal_rank to DUKE")
	assert_eq(cc.court_hud._orders_box.get_child_count(), 1, "CourtHUD displays open market order")

	# 2. Feed MSG_OFFLINE_CHRONICLE_DIGEST
	cc.apply_server_message(gazette_msg)

	assert_eq(gazette_signals.size(), 1, "gazette_received signal emitted")
	assert_true(cc.court_hud.is_gazette_visible(), "CourtHUD gazette panel visible after apply_gazette")
	assert_contains(cc.court_hud._gazette_label.text, "150", "Gazette text shows stipend COIN")

	# 3. Feed MSG_PERSONA_CHALLENGE
	var c_store: Dictionary = {}
	var c_cool: Dictionary = {}
	var ch_res: Dictionary = SealedTokenCodec.issue_challenge("acc_01", "player_01", 10, c_store, c_cool)
	assert_true(_as_bool(ch_res.get("ok", false)), "Challenge issued cleanly")
	var ch_msg: Dictionary = _as_dict(ch_res.get("data", {}))
	var v_ch: Dictionary = DtoSchemas.validate_persona_challenge(ch_msg)
	assert_true(_as_bool(v_ch.get("ok", false)), "Challenge passes validate_persona_challenge")

	cc.apply_server_message(ch_msg)
	assert_eq(challenge_signals.size(), 1, "challenge_received signal emitted")
	assert_contains(cc.court_hud._cc_challenge_label.text, str(ch_msg.get("challenge_id", "")), "Challenge label shows challenge_id")
	assert_contains(cc.court_hud._cc_prompt_display.text, str(ch_msg.get("challenge_id", "")), "Read-only prompt display updated")

	# 4. Feed Season Hegemony settlement + inbox decision into CourtHUD snapshot
	var heg_svc: SeasonHegemonyService = SeasonHegemonyService.new()
	var sett: Dictionary = heg_svc.compute_season_settlement({
		"tick_id": 50,
		"factions": [{"faction_id": "fac_han", "name": "Han", "lord_player_id": "player_01", "royal_rank": "DUKE", "prestige": 500, "treasury": 5000}],
		"players": [{"player_id": "player_01", "faction_id": "fac_han", "court_rank": "SOVEREIGN", "war_merit": 900}],
		"nodes": [{"node_id": "xuchang", "owner_faction_id": "fac_han"}]
	}, 1)
	cc.court_hud.apply_snapshot({
		"inbox_decisions": [{"decision_id": "dec_000001", "event_type": "REBEL_SURRENDER", "deadline_tick": 100, "options": ["ACCEPT", "REFUSE"]}],
		"season_settlement": sett
	})
	assert_eq(cc.court_hud._inbox_box.get_child_count(), 1, "CourtHUD renders inbox decision row")
	assert_eq(cc.court_hud._hegemony_box.get_child_count(), 2, "CourtHUD renders hegemon and top officer labels")

	# Verify server CRC32 was NOT mutated by any client view update
	assert_eq(srv.compute_state_crc32(), srv_crc_before, "Server state CRC32 completely untouched by client UI updates")


func test_all_four_views_emit_schema_valid_command_envelopes_with_monotonic_seq() -> void:
	var cc: ClientController = ClientController.new()
	var _tracked: Node = _track_ui(cc)
	cc.player_id = "player_01"
	cc.client_tick = 12

	var emitted: Array[Dictionary] = []
	cc.command_envelope_ready.connect(func(env: Dictionary) -> void: emitted.append(env))

	# 1. ManorGridView -> CMD_BUILD_OR_UPGRADE
	cc.manor_view.emit_upgrade_intent("GRANARY_VAULT", 8, 10)

	# 2. WorkPriorityScheduleView -> CMD_SET_WORK_PRIORITY, CMD_SET_SCHEDULE (slot & full), CMD_SET_DOCTRINE
	cc.priority_view.set_work_priority_intent("player_01_avatar", "AGRICULTURE", 1)
	cc.priority_view.set_schedule_slot_intent("player_01_avatar", 4, "DRILL")
	var full_sched: Array[String] = [
		"SLEEP", "SLEEP", "SLEEP", "DRILL",
		"WORK", "WORK", "WORK", "WORK",
		"WORK", "RECREATION", "ANYTHING", "SLEEP"
	]
	cc.priority_view.set_full_schedule_intent("player_01_avatar", full_sched)
	cc.priority_view.set_doctrine_intent({
		"engagement_stance": "PREEMPTIVE_STRIKE",
		"formation": "WEDGE_SPEAR",
		"duel_policy": "ALWAYS_ACCEPT",
		"stratagem_policy": "AMBUSH_TRAP",
		"prisoner_policy": "RECRUIT_PERSUADE"
	})

	# 3. MacroMapView -> CMD_DISPATCH_EXPEDITION, CMD_CREATE_COALITION_RALLY, CMD_JOIN_COALITION_RALLY
	var edges: Array[String] = ["e_xuchang_luoyang"]
	var officers: Array[String] = ["player_01_avatar"]
	cc.macro_view.emit_dispatch_expedition("luoyang", edges, 150, 300, "ARMY", officers, {"COIN": 50})
	cc.macro_view.emit_create_coalition_rally("chenliu", 600, 9000)
	cc.macro_view.emit_join_coalition_rally("rally_000001", 400, 8500)

	# 4. CourtMarketGazetteHUD -> CMD_PLACE_MARKET_ORDER, CMD_DECIDE_INBOX_EVENT, CMD_REQUEST_PERSONA_CHALLENGE, CMD_CREATE_CHARACTER
	cc.court_hud.emit_place_market_order("xuchang", "GRAIN", "BID", 1100, 25)
	cc.court_hud.emit_decide_inbox_event("dec_000001", "ACCEPT")
	cc.court_hud.request_challenge("acc_01")

	var c_store: Dictionary = {}
	var c_cool: Dictionary = {}
	var ch_res: Dictionary = SealedTokenCodec.issue_challenge("acc_01", "player_01", 12, c_store, c_cool)
	var ch_data: Dictionary = _as_dict(ch_res.get("data", {}))
	var cid: String = str(ch_data.get("challenge_id", ""))
	var slots: Array[int] = [2, 18, 14, 16, 12, 10, 0, 2, 10, 0, 5, 2, 3, 0, 1, 0]
	var sealed_tok: String = SealedTokenCodec.encode_tk3k2(cid, "player_01", slots)
	var ans: Array[int] = [0, 1, 2, 0, 1, 2, 0, 1]
	var cc_res: Dictionary = cc.court_hud.submit_character_creation("Guan_Ping", "FUSION_INTERVIEW", ans, sealed_tok)
	assert_true(_as_bool(cc_res.get("ok", false)), "Valid sealed token character creation submission succeeded")

	var expected_types: Array[String] = [
		"CMD_BUILD_OR_UPGRADE",
		"CMD_SET_WORK_PRIORITY",
		"CMD_SET_SCHEDULE",
		"CMD_SET_SCHEDULE",
		"CMD_SET_DOCTRINE",
		"CMD_DISPATCH_EXPEDITION",
		"CMD_CREATE_COALITION_RALLY",
		"CMD_JOIN_COALITION_RALLY",
		"CMD_PLACE_MARKET_ORDER",
		"CMD_DECIDE_INBOX_EVENT",
		"CMD_REQUEST_PERSONA_CHALLENGE",
		"CMD_CREATE_CHARACTER"
	]
	assert_eq(emitted.size(), expected_types.size(), "All 12 view intents emitted CommandEnvelopes")

	var prev_seq: int = 0
	for i: int in range(emitted.size()):
		var env: Dictionary = emitted[i]
		var val_res: Dictionary = DtoSchemas.validate_command_envelope(env)
		assert_true(_as_bool(val_res.get("ok", false)), "Envelope %d (%s) passes DtoSchemas.validate_command_envelope: %s" % [i, expected_types[i], str(val_res.get("reason", ""))])
		assert_false(StateHasher.has_floats(env), "Envelope %d has zero floats" % i)
		assert_eq(str(env.get("cmd_type", "")), expected_types[i], "Envelope %d cmd_type matches %s" % [i, expected_types[i]])
		assert_eq(str(env.get("player_id", "")), "player_01", "Envelope %d player_id == player_01" % i)
		assert_eq(_as_int(env.get("client_tick", -1), -1), 12, "Envelope %d client_tick == 12" % i)
		var seq: int = _as_int(env.get("cmd_seq", 0), 0)
		assert_gt(seq, prev_seq, "Envelope %d cmd_seq strictly monotonic (%d > %d)" % [i, seq, prev_seq])
		assert_eq(seq, i + 1, "Envelope %d cmd_seq == %d" % [i, i + 1])
		prev_seq = seq


func test_tk3k2_paste_only_modal_rejects_plaintext_json_and_accepts_sealed_token() -> void:
	var cc: ClientController = ClientController.new()
	var _tracked: Node = _track_ui(cc)
	cc.player_id = "player_01"

	var emitted: Array[Dictionary] = []
	cc.command_envelope_ready.connect(func(env: Dictionary) -> void: emitted.append(env))

	var answers: Array[int] = [0, 0, 1, 2, 1, 0, 3, 2]
	var bad_inputs: Array[String] = [
		"{\"LEA\": 99, \"MAR\": 99, \"INT\": 99}",
		"AI_PERSONA_EXPORT_V1: LEA=95",
		"persona_weights = [30, 30, 30, 30, 30]",
		"\"lea\": 95, \"mar\": 90",
		"{\"traits\": [\"T_CHIVALROUS\"]}"
	]

	for bad: String in bad_inputs:
		var preview: Dictionary = cc.court_hud.validate_client_token_preview(bad)
		assert_false(_as_bool(preview.get("ok", true), true), "Plaintext JSON/smuggle preview rejected: " + bad)
		assert_eq(str(preview.get("error_code", "")), DtoSchemas.ERR_PLAINTEXT_JSON_FORBIDDEN, "Error code == ERR_PLAINTEXT_JSON_FORBIDDEN for: " + bad)

		cc.court_hud._cc_token_paste_edit.text = bad
		cc.court_hud._on_token_text_changed(bad)
		assert_contains(cc.court_hud._cc_preview_status_label.text, DtoSchemas.ERR_PLAINTEXT_JSON_FORBIDDEN, "Live preview status displays ERR_PLAINTEXT_JSON_FORBIDDEN")

		var sub_fusion: Dictionary = cc.court_hud.submit_character_creation("CheatHero", "FUSION_INTERVIEW", answers, bad)
		assert_false(_as_bool(sub_fusion.get("ok", true), true), "FUSION_INTERVIEW submission rejected for plaintext JSON")
		assert_eq(str(sub_fusion.get("error_code", "")), DtoSchemas.ERR_PLAINTEXT_JSON_FORBIDDEN, "FUSION_INTERVIEW returns ERR_PLAINTEXT_JSON_FORBIDDEN")

		var sub_direct: Dictionary = cc.court_hud.submit_character_creation("CheatHero", "AI_DIRECT_WITH_CONFIRM", answers, bad)
		assert_false(_as_bool(sub_direct.get("ok", true), true), "AI_DIRECT_WITH_CONFIRM submission rejected for plaintext JSON")
		assert_eq(str(sub_direct.get("error_code", "")), DtoSchemas.ERR_PLAINTEXT_JSON_FORBIDDEN, "AI_DIRECT_WITH_CONFIRM returns ERR_PLAINTEXT_JSON_FORBIDDEN")

	# Empty input rejected with ERR_TOKEN_FORMAT
	var empty_sub: Dictionary = cc.court_hud.submit_character_creation("NoTokenHero", "FUSION_INTERVIEW", answers, "   ")
	assert_false(_as_bool(empty_sub.get("ok", true), true), "Empty token rejected in FUSION_INTERVIEW")
	assert_eq(str(empty_sub.get("error_code", "")), DtoSchemas.ERR_TOKEN_FORMAT, "Empty token error == ERR_TOKEN_FORMAT")
	assert_eq(emitted.size(), 0, "Zero envelopes emitted for rejected character creation attempts")

	# Now issue a real challenge from AuthoritativeServer and submit wrapped TK3K2 token through UI
	var srv: AuthoritativeServer = AuthoritativeServer.new(18401, "ST_SIMA_QIAN")
	var _reg: Dictionary = srv.register_session("peer_1", "player_01", "Hero01")
	cc.court_hud.request_challenge("acc_01")
	assert_eq(emitted.size(), 1, "Challenge request envelope emitted")
	var req_res: Dictionary = srv.submit_raw_command("peer_1", emitted[0])
	assert_true(_as_bool(req_res.get("accepted", false)), "Server accepted CMD_REQUEST_PERSONA_CHALLENGE")
	var _step1: Dictionary = srv.step_micro_tick()
	var msgs: Array[Dictionary] = srv.transport.client_drain_incoming("peer_1")
	var chal_msg: Dictionary = {}
	for m: Dictionary in msgs:
		if str(m.get("msg_type", "")) == DtoSchemas.MSG_PERSONA_CHALLENGE:
			chal_msg = m
			break
	assert_false(chal_msg.is_empty(), "Server returned MSG_PERSONA_CHALLENGE")
	cc.apply_server_message(chal_msg)

	var cid: String = str(chal_msg.get("challenge_id", ""))
	var slots: Array[int] = [3, 18, 12, 22, 16, 14, 0, 2, 10, 0, 5, 2, 3, 0, 1, 0]
	var tok: String = SealedTokenCodec.encode_tk3k2(cid, "player_01", slots)
	var wrapped_tok: String = "<<<TK3K_PERSONA_V2>>>\n%s\n<<<END_TK3K_PERSONA_V2>>>" % tok

	var valid_prev: Dictionary = cc.court_hud.validate_client_token_preview(wrapped_tok)
	assert_true(_as_bool(valid_prev.get("ok", false)), "Wrapped TK3K2 token passes client preview")
	assert_eq(str(valid_prev.get("error_code", "")), DtoSchemas.ERR_OK, "Preview error_code == OK")

	cc.court_hud._cc_token_paste_edit.text = wrapped_tok
	cc.court_hud._on_token_text_changed(wrapped_tok)
	assert_contains(cc.court_hud._cc_preview_status_label.text, "사전 확인 완료", "Preview status label shows valid confirmation")

	var sub_ok: Dictionary = cc.court_hud.submit_character_creation("Zhao_Yun", "FUSION_INTERVIEW", answers, wrapped_tok)
	assert_true(_as_bool(sub_ok.get("ok", false)), "submit_character_creation accepts valid TK3K2 token")
	assert_eq(emitted.size(), 2, "CMD_CREATE_CHARACTER envelope emitted")
	var create_env: Dictionary = emitted[1]
	assert_true(_as_bool(DtoSchemas.validate_command_envelope(create_env).get("ok", false)), "Emitted CMD_CREATE_CHARACTER passes schema check")

	var srv_create_res: Dictionary = srv.submit_raw_command("peer_1", create_env)
	assert_true(_as_bool(srv_create_res.get("accepted", false)), "Server accepted UI-emitted CMD_CREATE_CHARACTER")
	var _step2: Dictionary = srv.step_micro_tick()
	assert_true(srv.manors.has("player_01"), "AuthoritativeServer created manor for UI-submitted TK3K2 character")


func _find_nodes_of_type(root: Node, target_type: String, out: Array[Node]) -> void:
	if root == null:
		return
	if root.is_class(target_type):
		out.append(root)
	for child: Node in root.get_children():
		_find_nodes_of_type(child, target_type, out)


func test_m8_ui_ux_upgrade_split_layouts_onboarding_and_korean_localization() -> void:
	# 1. AssetRegistry ibelick/ui-skills tokens, flat cards & Korean localization helpers
	var reg: AssetRegistry = AssetRegistry.new()
	var card_sb: StyleBoxFlat = reg.build_card_stylebox(false)
	assert_not_null(card_sb, "build_card_stylebox() returns StyleBoxFlat")
	assert_eq(card_sb.corner_radius_top_left, 6, "Card corner radius is 6px")
	var badge_sb: StyleBoxFlat = reg.build_badge_stylebox(AssetRegistry.COLOR_CARD_BG, AssetRegistry.COLOR_GOLD_ACCENT)
	assert_eq(badge_sb.corner_radius_top_left, 4, "Badge concentric inner corner radius is 4px")
	assert_eq(AssetRegistry.resource_label_ko("GRAIN"), "군량", "resource_label_ko('GRAIN') -> 군량")
	assert_eq(AssetRegistry.work_domain_ko("AGRICULTURE"), "둔전·농사", "work_domain_ko('AGRICULTURE') -> 둔전·농사")
	assert_eq(AssetRegistry.shichen_activity_ko("SLEEP"), "취침", "shichen_activity_ko('SLEEP') -> 취침")
	assert_eq(AssetRegistry.format_num(12345), "12,345", "format_num formats thousands separator")
	assert_eq(str(AssetRegistry.building_info_ko("MILITARY_FARM").get("name", "")), "둔전", "building_info_ko('MILITARY_FARM') -> 둔전")
	assert_eq(str(AssetRegistry.zone_info_ko("ZONE_FARMLAND").get("name", "")), "둔전 농지", "zone_info_ko('ZONE_FARMLAND') -> 둔전 농지")

	# 2. ClientController clean tab titles, onboarding bar & global resource strip
	var cc: ClientController = ClientController.new()
	cc.auto_start_live_demo = false
	var _tracked: Node = _track_ui(cc)

	for ti: int in range(cc.get_tab_count()):
		var ttitle: String = cc._tab_container.get_tab_title(ti)
		assert_false(ttitle.contains("_"), "Tab %d title has zero underscores: %s" % [ti, ttitle])
	assert_eq(cc._tab_container.get_tab_title(0), "1. 장원 경영", "Tab 0 clean Korean title")
	assert_eq(cc._tab_container.get_tab_title(3), "4. 정청 · 거래소 · 조보", "Tab 3 clean Korean title")
	assert_eq(cc._onboarding_step_btns.size(), 5, "5-step onboarding bar has 5 clickable step buttons")
	assert_eq(cc._global_res_labels.size(), 8, "Global persistent 8-resource strip has 8 numeric labels")

	var _boot: Dictionary = cc.start_local_demo(18401)
	var grain_lbl: Label = cc._global_res_labels["GRAIN"]
	assert_ne(grain_lbl.text, "0", "Global resource strip updated with live GRAIN count: " + grain_lbl.text)

	# 3. All 4 views use 2-column HSplitContainer layouts & zero raw CMD_* button labels
	var views: Array[Control] = [cc.manor_view, cc.priority_view, cc.macro_view, cc.court_hud]
	for vi: int in range(views.size()):
		var v: Control = views[vi]
		var splits: Array[Node] = []
		_find_nodes_of_type(v, "HSplitContainer", splits)
		assert_gte(splits.size(), 1, "View %d contains HSplitContainer 2-column layout" % vi)

		var buttons: Array[Node] = []
		_find_nodes_of_type(v, "Button", buttons)
		for bn: Node in buttons:
			if bn is Button:
				var btn: Button = bn
				assert_false(btn.text.contains("CMD_"), "View %d button hides raw CMD_* string: %s" % [vi, btn.text])

	# 4. Metadata-backed OptionButtons emit canonical protocol keys while showing Korean text
	var emitted: Array[Dictionary] = []
	cc.command_envelope_ready.connect(func(env: Dictionary) -> void: emitted.append(env))
	cc.court_hud._on_place_order_pressed()
	cc.macro_view._on_dispatch_pressed()
	cc.priority_view._on_apply_doctrine_pressed()
	assert_eq(emitted.size(), 3, "Metadata-backed UI submit handlers emit 3 envelopes")
	var args0: Dictionary = _as_dict(emitted[0].get("args", {}))
	var args1: Dictionary = _as_dict(emitted[1].get("args", {}))
	var args2: Dictionary = _as_dict(emitted[2].get("args", {}))
	assert_eq(str(args0.get("commodity", "")), "GRAIN", "Market OptionButton emits canonical commodity GRAIN")
	assert_eq(str(args0.get("side", "")), "BID", "Market OptionButton emits canonical side BID")
	assert_eq(str(args1.get("unit_type", "")), "ARMY", "Macro OptionButton emits canonical unit_type ARMY")
	assert_eq(str(args2.get("engagement_stance", "")), "DEFENSIVE_HOLD", "Doctrine OptionButton emits canonical stance")

	# 5. Iteration 2 regression: same-frame remove_child() keeps dynamic box child counts exact
	cc.macro_view.apply_snapshot({
		"armies": {"a_1": {"unit_type": "ARMY", "faction_id": "fac_han", "current_node_id": "xuchang", "troop_count": 50}},
		"rallies": {"r_1": {"target_node_id": "luoyang", "status": "RALLYING", "participant_count": 1}}
	})
	cc.macro_view.apply_snapshot({
		"armies": {"a_1": {"unit_type": "ARMY", "faction_id": "fac_han", "current_node_id": "xuchang", "troop_count": 50}},
		"rallies": {"r_1": {"target_node_id": "luoyang", "status": "RALLYING", "participant_count": 1}}
	})
	assert_eq(cc.macro_view._armies_box.get_child_count(), cc.macro_view._cached_armies.size(), "Macro _armies_box child count exact immediately on re-apply")
	assert_eq(cc.macro_view._rallies_box.get_child_count(), cc.macro_view._cached_rallies.size(), "Macro _rallies_box child count exact immediately on re-apply")

	cc.court_hud.apply_snapshot({
		"orders": {"o_1": {"commodity": "GRAIN", "side": "BID", "price_bp": 1000, "remaining_qty": 10}},
		"inbox_decisions": [{"decision_id": "d_1", "event_type": "IMPERIAL_LEVY", "deadline_tick": 99, "options": ["PAY_LEVY"]}]
	})
	cc.court_hud.apply_snapshot({
		"orders": {"o_1": {"commodity": "GRAIN", "side": "BID", "price_bp": 1000, "remaining_qty": 10}},
		"inbox_decisions": [{"decision_id": "d_1", "event_type": "IMPERIAL_LEVY", "deadline_tick": 99, "options": ["PAY_LEVY"]}]
	})
	assert_eq(cc.court_hud._orders_box.get_child_count(), cc.court_hud._cached_orders.size(), "Court _orders_box child count exact immediately on re-apply")
	assert_eq(cc.court_hud._inbox_box.get_child_count(), 1, "Court _inbox_box child count exact immediately on re-apply")

	# 6. Iteration 2 regression: back-to-back Tab 1 preset clicks stay within TOKEN_BUCKET_BURST=10
	cc.step_demo_ticks(4)
	cc.priority_view._on_preset_pressed("DOMESTIC")
	cc.priority_view._on_preset_pressed("WAR")
	cc.priority_view._on_preset_pressed("REST")
	cc.step_demo_ticks(1)
	assert_contains(cc._cmd_feedback_label.text, "수락", "Back-to-back DOMESTIC+WAR+REST presets accepted: " + cc._cmd_feedback_label.text)
	assert_false(cc._cmd_feedback_label.text.contains(DtoSchemas.ERR_RATE_LIMITED), "Back-to-back presets never trip ERR_RATE_LIMITED")

	# 7. Iteration 2 regression: all 6 Tab 3 provinces map to valid WorldGraph host nodes and dispatch ARMY cleanly
	var expected_nodes_by_prov: Dictionary = {
		"YU_ZHOU": "xuchang",
		"XU_ZHOU": "xiapi",
		"JI_ZHOU": "ye_county",
		"YI_ZHOU": "chengdu",
		"YANG_ZHOU": "jianye",
		"YONG_LIANG": "changan"
	}
	assert_eq(cc.court_hud._cc_province_opt.item_count, 6, "Tab 3 province dropdown has 6 provinces")
	cc.court_hud._cc_mode_opt.select(0)  # INTERVIEW_ONLY
	for pi: int in range(cc.court_hud._cc_province_opt.item_count):
		var prov_id: String = str(cc.court_hud._cc_province_opt.get_item_metadata(pi))
		assert_true(expected_nodes_by_prov.has(prov_id), "Province dropdown uses canonical ID: " + prov_id)
		cc.court_hud._cc_province_opt.select(pi)
		cc.court_hud._on_submit_cc_pressed()
		cc.step_demo_ticks(1)
		var expected_nid: String = str(expected_nodes_by_prov[prov_id])
		assert_eq(cc.macro_view._host_node_id, expected_nid, "Province %s maps to valid host_node_id %s" % [prov_id, expected_nid])
		assert_true(cc.macro_view._world_graph.has_node(cc.macro_view._host_node_id), "host_node_id exists in WorldGraph: " + cc.macro_view._host_node_id)
		var target_nid: String = "luoyang" if cc.macro_view._host_node_id != "luoyang" else "xuchang"
		cc.macro_view._select_map_node(target_nid, true)
		cc.macro_view._on_dispatch_pressed()
		cc.step_demo_ticks(1)
		assert_contains(cc._cmd_feedback_label.text, "수락", "Dispatch after %s creation accepted: %s" % [prov_id, cc._cmd_feedback_label.text])
		assert_false(cc._cmd_feedback_label.text.contains(DtoSchemas.ERR_SCHEMA), "Dispatch after %s creation has zero ERR_SCHEMA" % prov_id)
		cc.step_demo_ticks(4)

	# 8. Iteration 3 regressions:
	# (a) CMD_PLACE_MARKET_ORDER rejects empty & bogus node_id with ERR_INVALID_STATE and zero COIN escrow loss,
	#     while normalizing known alias "ye" -> "ye_county" identically on validator & server.
	var iso_srv: AuthoritativeServer = AuthoritativeServer.new(18401, "ST_SIMA_QIAN")
	var _iso_reg: Dictionary = iso_srv.register_session("peer_iso", "p_iso", "IsoLord")
	var _iso_create: Dictionary = iso_srv.submit_raw_command("peer_iso", {
		"v": 1, "cmd_seq": 1, "client_tick": 0, "player_id": "p_iso",
		"cmd_type": "CMD_CREATE_CHARACTER",
		"args": {"name": "IsoLord", "mode": "INTERVIEW_ONLY", "province_override": "JI_ZHOU", "interview_answers": [0, 1, 2, 0, 1, 2, 0, 1]}
	})
	var _iso_t1: Dictionary = iso_srv.step_micro_tick()
	var iso_manor: ManorState = iso_srv.manors["p_iso"]
	var _iso_coin_add: int = iso_manor.add_resource("COIN", 500)
	var iso_coin_before: int = iso_manor.get_resource("COIN")

	var res_empty: Dictionary = iso_srv.submit_raw_command("peer_iso", {
		"v": 1, "cmd_seq": 2, "client_tick": 1, "player_id": "p_iso",
		"cmd_type": "CMD_PLACE_MARKET_ORDER",
		"args": {"node_id": "", "commodity": "GRAIN", "side": "BID", "price_bp": 1000, "quantity": 100}
	})
	var _iso_t2: Dictionary = iso_srv.step_micro_tick()
	assert_false(_as_bool(res_empty.get("accepted", true), true), "Validator rejects empty market node_id")
	assert_eq(str(_as_dict(res_empty.get("receipt", {})).get("error_code", "")), DtoSchemas.ERR_INVALID_STATE, "Empty market node_id returns ERR_INVALID_STATE")
	assert_eq(iso_manor.get_resource("COIN"), iso_coin_before, "Zero COIN escrow lost when empty market node_id is rejected")
	assert_eq(iso_srv.regional_market.orders.size(), 0, "Zero market orders created for empty node_id")

	var res_bogus: Dictionary = iso_srv.submit_raw_command("peer_iso", {
		"v": 1, "cmd_seq": 3, "client_tick": 2, "player_id": "p_iso",
		"cmd_type": "CMD_PLACE_MARKET_ORDER",
		"args": {"node_id": "bogus_node_999", "commodity": "GRAIN", "side": "BID", "price_bp": 1000, "quantity": 100}
	})
	var _iso_t3: Dictionary = iso_srv.step_micro_tick()
	assert_false(_as_bool(res_bogus.get("accepted", true), true), "Validator rejects bogus market node_id")
	assert_eq(str(_as_dict(res_bogus.get("receipt", {})).get("error_code", "")), DtoSchemas.ERR_INVALID_STATE, "Unknown market node_id returns ERR_INVALID_STATE")
	assert_eq(iso_manor.get_resource("COIN"), iso_coin_before, "Zero COIN escrow lost when bogus market node_id is rejected")
	assert_eq(iso_srv.regional_market.orders.size(), 0, "Zero market orders created for bogus node_id")

	var res_ye: Dictionary = iso_srv.submit_raw_command("peer_iso", {
		"v": 1, "cmd_seq": 4, "client_tick": 3, "player_id": "p_iso",
		"cmd_type": "CMD_PLACE_MARKET_ORDER",
		"args": {"node_id": "ye", "commodity": "GRAIN", "side": "BID", "price_bp": 1000, "quantity": 50}
	})
	var _iso_t4: Dictionary = iso_srv.step_micro_tick()
	assert_true(_as_bool(res_ye.get("accepted", false), false), "Validator accepts alias market node_id 'ye'")
	assert_eq(iso_srv.regional_market.orders.size(), 1, "Alias 'ye' market order created")
	var iso_oid: String = "ord_%06d" % (iso_srv.regional_market._next_order_seq - 1)
	assert_eq(str(iso_srv.regional_market.get_order(iso_oid).get("node_id", "")), "ye_county", "Server normalized market order node_id 'ye' -> 'ye_county'")

	# Also verify ClientController UI receipt feedback for empty/bogus/alias market orders
	var _mkt_empty_env: Dictionary = cc.package_command("CMD_PLACE_MARKET_ORDER", {
		"node_id": "", "commodity": "GRAIN", "side": "BID", "price_bp": 1000, "quantity": 100
	})
	cc.step_demo_ticks(1)
	assert_contains(cc._cmd_feedback_label.text, DtoSchemas.ERR_INVALID_STATE, "UI toast shows ERR_INVALID_STATE for empty market node_id")

	var _mkt_bogus_env: Dictionary = cc.package_command("CMD_PLACE_MARKET_ORDER", {
		"node_id": "bogus_node_999", "commodity": "GRAIN", "side": "BID", "price_bp": 1000, "quantity": 100
	})
	cc.step_demo_ticks(1)
	assert_contains(cc._cmd_feedback_label.text, DtoSchemas.ERR_INVALID_STATE, "UI toast shows ERR_INVALID_STATE for bogus market node_id")

	var _mkt_ye_env: Dictionary = cc.package_command("CMD_PLACE_MARKET_ORDER", {
		"node_id": "ye", "commodity": "GRAIN", "side": "BID", "price_bp": 1000, "quantity": 50
	})
	cc.step_demo_ticks(1)
	assert_contains(cc._cmd_feedback_label.text, "수락", "UI toast accepts alias market node_id 'ye': " + cc._cmd_feedback_label.text)

	# (b) MacroMapView.set_host_node_id() syncs _target_node_opt dropdown when shifting away from new host
	cc.macro_view.set_host_node_id("luoyang")
	cc.macro_view._select_map_node("xuchang", true)
	assert_eq(cc.macro_view._get_selected_target_node_id(), "xuchang", "Dropdown initially synced to xuchang")
	cc.macro_view.set_host_node_id("xuchang")
	assert_eq(cc.macro_view._selected_node_id, "luoyang", "set_host_node_id('xuchang') shifts _selected_node_id to luoyang")
	assert_eq(cc.macro_view._get_selected_target_node_id(), "luoyang", "set_host_node_id('xuchang') syncs _target_node_opt dropdown to luoyang")
	cc.macro_view.apply_snapshot({"nodes": {"xuchang": cc.macro_view._world_graph.get_node("xuchang")}})
	assert_eq(cc.macro_view._selected_node_id, "luoyang", "Subsequent apply_snapshot preserves shifted target luoyang")
	cc.step_demo_ticks(4)
	cc.macro_view._on_dispatch_pressed()
	cc.step_demo_ticks(1)
	assert_contains(cc._cmd_feedback_label.text, "수락", "Dispatch succeeds after host shift without manual re-select: " + cc._cmd_feedback_label.text)

	# (c) Toggling WAR -> DOMESTIC -> WAR + REST back-to-back in 1 tick stays <= TOKEN_BUCKET_BURST (10)
	cc.step_demo_ticks(4)
	cc.priority_view._on_preset_pressed("DOMESTIC")
	cc.step_demo_ticks(4)
	cc.priority_view._on_preset_pressed("WAR")
	cc.priority_view._on_preset_pressed("DOMESTIC")
	cc.priority_view._on_preset_pressed("WAR")
	cc.priority_view._on_preset_pressed("REST")
	cc.step_demo_ticks(1)
	assert_contains(cc._cmd_feedback_label.text, "수락", "3-toggle WAR->DOMESTIC->WAR+REST burst accepted: " + cc._cmd_feedback_label.text)
	assert_false(cc._cmd_feedback_label.text.contains(DtoSchemas.ERR_RATE_LIMITED), "3-toggle WAR->DOMESTIC->WAR+REST never trips ERR_RATE_LIMITED")

	# 9. Iteration 4 regressions:
	# (a) Fresh ClientController.start_local_demo(18401) with 0 prior clicks or ticks accepts immediate
	#     WAR -> DOMESTIC -> WAR -> REST and DOMESTIC -> WAR -> DOMESTIC -> REST bursts with zero ERR_RATE_LIMITED.
	var cc_fresh_war: ClientController = ClientController.new()
	cc_fresh_war.auto_start_live_demo = false
	var _tracked_war: Node = _track_ui(cc_fresh_war)
	var _boot_war: Dictionary = cc_fresh_war.start_local_demo(18401)
	cc_fresh_war.priority_view._on_preset_pressed("WAR")
	cc_fresh_war.priority_view._on_preset_pressed("DOMESTIC")
	cc_fresh_war.priority_view._on_preset_pressed("WAR")
	cc_fresh_war.priority_view._on_preset_pressed("REST")
	cc_fresh_war.step_demo_ticks(1)
	assert_contains(cc_fresh_war._cmd_feedback_label.text, "수락", "Fresh demo immediate WAR->DOMESTIC->WAR->REST accepted: " + cc_fresh_war._cmd_feedback_label.text)
	assert_false(cc_fresh_war._cmd_feedback_label.text.contains(DtoSchemas.ERR_RATE_LIMITED), "Fresh demo immediate WAR->DOMESTIC->WAR->REST has zero ERR_RATE_LIMITED")

	var cc_fresh_dom: ClientController = ClientController.new()
	cc_fresh_dom.auto_start_live_demo = false
	var _tracked_dom: Node = _track_ui(cc_fresh_dom)
	var _boot_dom: Dictionary = cc_fresh_dom.start_local_demo(18401)
	cc_fresh_dom.priority_view._on_preset_pressed("DOMESTIC")
	cc_fresh_dom.priority_view._on_preset_pressed("WAR")
	cc_fresh_dom.priority_view._on_preset_pressed("DOMESTIC")
	cc_fresh_dom.priority_view._on_preset_pressed("REST")
	cc_fresh_dom.step_demo_ticks(1)
	assert_contains(cc_fresh_dom._cmd_feedback_label.text, "수락", "Fresh demo immediate DOMESTIC->WAR->DOMESTIC->REST accepted: " + cc_fresh_dom._cmd_feedback_label.text)
	assert_false(cc_fresh_dom._cmd_feedback_label.text.contains(DtoSchemas.ERR_RATE_LIMITED), "Fresh demo immediate DOMESTIC->WAR->DOMESTIC->REST has zero ERR_RATE_LIMITED")

	# (b) Fresh ClientController.start_local_demo(18401) where _host_node_id == "xuchang":
	#     pre-selecting each province's own node (starting with YU_ZHOU -> "xuchang") before character creation
	#     must shift both _selected_node_id and _get_selected_target_node_id() away from expected_nid, survive
	#     apply_snapshot(), and dispatch cleanly with zero ERR_SCHEMA.
	var cc_map: ClientController = ClientController.new()
	cc_map.auto_start_live_demo = false
	var _tracked_map: Node = _track_ui(cc_map)
	var _boot_map: Dictionary = cc_map.start_local_demo(18401)
	assert_eq(cc_map.macro_view._host_node_id, "xuchang", "Fresh demo starts with host_node_id == xuchang")
	cc_map.court_hud._cc_mode_opt.select(0)  # INTERVIEW_ONLY
	for pi2: int in range(cc_map.court_hud._cc_province_opt.item_count):
		var prov_id2: String = str(cc_map.court_hud._cc_province_opt.get_item_metadata(pi2))
		var expected_nid2: String = str(expected_nodes_by_prov[prov_id2])
		cc_map.macro_view._select_map_node(expected_nid2, true)
		assert_eq(cc_map.macro_view._selected_node_id, expected_nid2, "Pre-selected map node == %s before %s creation" % [expected_nid2, prov_id2])
		cc_map.court_hud._cc_province_opt.select(pi2)
		cc_map.court_hud._on_submit_cc_pressed()
		cc_map.step_demo_ticks(1)
		cc_map.macro_view.apply_snapshot({"nodes": {expected_nid2: cc_map.macro_view._world_graph.get_node(expected_nid2)}})
		assert_eq(cc_map.macro_view._host_node_id, expected_nid2, "Host node updated to %s for %s" % [expected_nid2, prov_id2])
		assert_ne(cc_map.macro_view._selected_node_id, expected_nid2, "Target _selected_node_id shifted away from %s for %s" % [expected_nid2, prov_id2])
		assert_ne(cc_map.macro_view._get_selected_target_node_id(), expected_nid2, "Dropdown target shifted away from %s for %s" % [expected_nid2, prov_id2])
		cc_map.macro_view._on_dispatch_pressed()
		cc_map.step_demo_ticks(1)
		assert_contains(cc_map._cmd_feedback_label.text, "수락", "Dispatch after pre-selecting %s (%s) accepted: %s" % [prov_id2, expected_nid2, cc_map._cmd_feedback_label.text])
		assert_false(cc_map._cmd_feedback_label.text.contains(DtoSchemas.ERR_SCHEMA), "Dispatch after pre-selecting %s (%s) has zero ERR_SCHEMA" % [prov_id2, expected_nid2])
		cc_map.step_demo_ticks(4)
