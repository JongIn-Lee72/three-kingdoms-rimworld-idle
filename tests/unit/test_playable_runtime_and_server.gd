class_name TestPlayableRuntimeAndServer
extends HarnessTestCase

const SCRATCH_DIR: String = "/home/antigravity/.gemini/jetski/scratch/teamwork_tmp"

var _ui_nodes: Array[Node] = []
var _created_files: Array[String] = []


func _track_ui(node: Node) -> Node:
	if node != null and not _ui_nodes.has(node):
		_ui_nodes.append(node)
		var loop: MainLoop = Engine.get_main_loop()
		if loop is SceneTree:
			var st: SceneTree = loop
			if st.root != null and node.get_parent() == null:
				st.root.add_child(node)
	return node


func _track_scratch_file(path: String) -> String:
	if not path.is_empty() and not _created_files.has(path):
		_created_files.append(path)
	return path


func after_each() -> void:
	for i: int in range(_ui_nodes.size() - 1, -1, -1):
		var n: Node = _ui_nodes[i]
		if n != null and is_instance_valid(n):
			if n is ClientController:
				var cc: ClientController = n
				cc.stop_live_session()
			elif n is HeadlessServerMain:
				var hsm: HeadlessServerMain = n
				hsm.stop_server()
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_ui_nodes.clear()

	for p: String in _created_files:
		if FileAccess.file_exists(p):
			var _rm: Error = DirAccess.remove_absolute(p)
		if FileAccess.file_exists(p + ".tmp"):
			var _rm_tmp: Error = DirAccess.remove_absolute(p + ".tmp")
	_created_files.clear()


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


func _find_available_port(start_port: int = 19120, attempts: int = 30) -> int:
	for i: int in range(attempts):
		var candidate: int = start_port + i
		var probe: TCPServer = TCPServer.new()
		var err: Error = probe.listen(candidate, "127.0.0.1")
		if err == OK:
			probe.stop()
			return candidate
	return start_port


func test_local_demo_session_initializes_and_ticks_with_speed_and_pause() -> void:
	var cc: ClientController = ClientController.new()
	cc.auto_start_live_demo = false
	var _tracked: Node = _track_ui(cc)

	# Must remain inert before explicit start_local_demo()
	assert_eq(cc.client_tick, 0, "ClientController.new() starts inert with client_tick == 0")
	assert_eq(cc.cmd_seq, 0, "ClientController.new() starts inert with cmd_seq == 0")

	var boot_res: Dictionary = cc.start_local_demo(18401)
	assert_true(_as_bool(boot_res.get("ok", false)), "start_local_demo() returns ok == true")
	var drv: LiveSessionDriver = cc.get_live_driver()
	assert_not_null(drv, "LiveSessionDriver initialized")
	assert_true(drv.is_local_mode(), "LiveSessionDriver is in MODE_LOCAL_DEMO")
	assert_gte(cc.client_tick, 6, "Initial bootstrap advances at least 1 macro tick (6 ticks)")

	# All 4 tabs populated from live embedded AuthoritativeServer
	assert_contains(cc.manor_view._header_label.text, "manor_player_01", "Tab 0 displays player_01 manor")
	assert_gte(cc.manor_view._pawns_box.get_child_count(), 2, "Tab 0 displays avatar and retainer pawns")
	assert_gte(cc.priority_view._pawn_selector.item_count, 2, "Tab 1 populates pawn selector")
	assert_eq(cc.macro_view.get_node_count(), 15, "Tab 2 holds all 15 Three Kingdoms nodes")
	assert_contains(cc.court_hud._court_label.text, "fac_han", "Tab 3 displays player faction fac_han")
	assert_contains(cc.court_hud._court_label.text, "LORD", "Tab 3 displays player LORD role_tier")

	# 1x speed accumulator via _process(delta)
	var t0: int = cc.client_tick
	cc.set_demo_speed(1)
	cc._process(1.05)
	assert_eq(cc.client_tick, t0 + 1, "1x speed advances 1 tick per ~1.0s delta")

	# 5x speed accumulator via _process(delta)
	var t1: int = cc.client_tick
	cc.set_demo_speed(5)
	cc._process(1.0)
	assert_eq(cc.client_tick, t1 + 5, "5x speed advances 5 ticks for 1.0s delta")

	# Pause freezes tick progression
	var t_paused: int = cc.client_tick
	cc.set_demo_paused(true)
	cc._process(2.5)
	assert_eq(cc.client_tick, t_paused, "Paused local demo freezes client_tick")

	cc.set_demo_paused(false)
	cc.set_demo_speed(2)
	cc._process(1.0)
	assert_eq(cc.client_tick, t_paused + 2, "Resumed 2x speed advances 2 ticks for 1.0s delta")


func test_ai_bots_lord_wei_and_ally_shu_drive_shared_world_state_changes() -> void:
	var cc: ClientController = ClientController.new()
	cc.auto_start_live_demo = false
	var _tracked: Node = _track_ui(cc)

	var boot_res: Dictionary = cc.start_local_demo(18401)
	assert_true(_as_bool(boot_res.get("ok", false)), "Local demo boots cleanly")
	var srv: AuthoritativeServer = cc.get_live_driver().local_server
	var initial_crc: int = srv.compute_state_crc32()

	# Verify both AI rival lords exist on valid macro_map_3k.json provinces
	assert_true(srv.manors.has(LiveSessionDriver.BOT_WEI_ID), "lord_wei has active manor")
	assert_true(srv.manors.has(LiveSessionDriver.BOT_SHU_ID), "ally_shu has active manor")
	var wei_m: ManorState = srv.manors[LiveSessionDriver.BOT_WEI_ID]
	var shu_m: ManorState = srv.manors[LiveSessionDriver.BOT_SHU_ID]
	assert_eq(wei_m.host_node_id, "xiapi", "lord_wei starts on valid node xiapi")
	assert_eq(shu_m.host_node_id, "chengdu", "ally_shu starts on valid node chengdu")

	# Step 18 ticks (3 macro ticks) so AI bots place complementary orders & dispatch expeditions
	cc.step_demo_ticks(18)
	var after_crc: int = srv.compute_state_crc32()
	assert_ne(after_crc, initial_crc, "World state CRC32 mutates across AI bot macro ticks")
	assert_gte(srv.regional_market.orders.size(), 2, "AI bots place regional market orders")
	assert_gte(srv.regional_market.trade_history.size(), 1, "AI bot complementary BID/ASK orders match in RegionalMarket")
	assert_gte(srv.army_manager.get_entity_ids().size(), 1, "AI bots dispatch real ARMY/CARAVAN expeditions")
	assert_gte(cc.macro_view._armies_box.get_child_count(), 1, "MacroMapView renders live bot expeditions")


func test_client_controller_command_dispatch_roundtrip_in_local_demo() -> void:
	var cc: ClientController = ClientController.new()
	cc.auto_start_live_demo = false
	var _tracked: Node = _track_ui(cc)
	var _boot: Dictionary = cc.start_local_demo(18401)
	var srv: AuthoritativeServer = cc.get_live_driver().local_server
	var p_manor: ManorState = srv.manors["player_01"]
	var farm_lvl_before: int = p_manor.get_building_level("MILITARY_FARM")
	var orders_before: int = srv.regional_market.orders.size()

	# Track command_envelope_ready emissions using reference container (GDScript lambda captures ints by value)
	var emitted_envs: Array[Dictionary] = []
	cc.command_envelope_ready.connect(func(env: Dictionary) -> void: emitted_envs.append(env))

	# 1. Upgrade building via ManorGridView
	cc.manor_view.emit_upgrade_intent("MILITARY_FARM")
	# 2. Change work priority via WorkPriorityScheduleView
	cc.priority_view.set_work_priority_intent("player_01_avatar", "AGRICULTURE", 1)
	# 3. Place market order via CourtMarketGazetteHUD
	cc.court_hud.emit_place_market_order("xuchang", "GRAIN", "BID", 1100, 10)
	assert_eq(emitted_envs.size(), 3, "All 3 UI views emitted CommandEnvelopes")

	# Step 1 tick so AuthoritativeServer executes commands queued for exec_tick_id == current + 1
	cc.step_demo_ticks(1)
	assert_contains(cc._cmd_feedback_label.text, "수락", "ClientController received ACCEPTED MSG_CMD_RECEIPT")
	assert_eq(p_manor.get_building_level("MILITARY_FARM"), farm_lvl_before + 1, "MILITARY_FARM upgraded on embedded server")
	assert_eq(cc.manor_view.get_building_level_displayed("MILITARY_FARM"), farm_lvl_before + 1, "ManorGridView reflects upgraded building level")
	assert_gt(srv.regional_market.orders.size(), orders_before, "Market order persisted on embedded server")
	var av: PawnEntity = p_manor.get_pawn_by_id("player_01_avatar")
	assert_not_null(av, "Avatar pawn exists")
	if av != null:
		assert_eq(av.get_work_priority("AGRICULTURE"), 1, "Work priority updated to 1 on server pawn")


func test_websocket_client_controller_and_headless_server_integration() -> void:
	var _mk_err: Error = DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var db_p: String = _track_scratch_file(SCRATCH_DIR + "/test_ws_srv.db")
	var wal_p: String = _track_scratch_file(SCRATCH_DIR + "/test_ws_wal.jsonl")
	var snap_p: String = _track_scratch_file(SCRATCH_DIR + "/test_ws_snap.json")
	var ws_port: int = _find_available_port(19120, 40)

	var srv_node: HeadlessServerMain = HeadlessServerMain.new()
	srv_node.auto_start_on_ready = false
	srv_node.configure({
		"port": ws_port,
		"bind": "127.0.0.1",
		"db": db_p,
		"wal": wal_p,
		"snapshot": snap_p,
		"seed": 18401,
		"tick_sec": 0.2,
		"snapshot_interval": 24,
		"persist_enabled": true
	})
	var _tracked_srv: Node = _track_ui(srv_node)
	var listen_err: Error = srv_node.start_server()
	assert_eq(listen_err, OK, "HeadlessServerMain listens cleanly on localhost WebSocket port %d" % ws_port)

	var cc: ClientController = ClientController.new()
	cc.auto_start_live_demo = false
	cc.player_id = "ws_hero_01"
	var _tracked_cc: Node = _track_ui(cc)

	var conn_err: Error = cc.connect_remote_websocket("ws://127.0.0.1:%d" % ws_port, "ws_hero_01")
	assert_eq(conn_err, OK, "ClientController initiated WebSocket connection")

	# Pump handshake until client opens, sends CMD_SUBSCRIBE_CHANNEL hello, and server binds peer
	for _i: int in range(80):
		srv_node.pump_network()
		cc._process(0.02)
		if cc.get_live_driver().is_remote_connected() and srv_node.server.sessions_by_peer.size() >= 1:
			break
		OS.delay_msec(10)

	assert_true(cc.get_live_driver().is_remote_connected(), "WebSocket client reached STATE_OPEN")
	assert_gte(srv_node.server.sessions_by_peer.size(), 1, "HeadlessServerMain auto-registered WebSocket peer")

	# Create character via UI CommandEnvelope over real WebSocket
	var _cc_env: Dictionary = cc.package_command("CMD_CREATE_CHARACTER", {
		"avatar_name": "조운_자룡",
		"creation_mode": "INTERVIEW_ONLY",
		"origin_override": "ORIGIN_FRONTIER_OFFICER",
		"province_override": "YU_ZHOU",
		"interview_answers": [1, 0, 1, 2, 1, 0, 2, 1]
	})

	for _i: int in range(40):
		var _sr: Dictionary = srv_node.step_server_tick()
		cc._process(0.02)
		if srv_node.server.manors.has("ws_hero_01") and cc.client_tick >= 1:
			break
		OS.delay_msec(10)

	assert_true(srv_node.server.manors.has("ws_hero_01"), "Remote HeadlessServerMain created manor for ws_hero_01")
	assert_gte(cc.client_tick, 1, "ClientController received live MSG_TICK_DELTA over WebSocket")

	# Place market order over real WebSocket and advance to macro tick 6 (which broadcasts MSG_TICK_DELTA)
	var _mkt_env: Dictionary = cc.package_command("CMD_PLACE_MARKET_ORDER", {
		"node_id": "xuchang",
		"commodity": "GRAIN",
		"side": "ASK",
		"price_bp": 1200,
		"quantity": 15
	})

	for _i: int in range(18):
		var sr2: Dictionary = srv_node.step_server_tick()
		cc._process(0.02)
		OS.delay_msec(10)
		if _i >= 6 and _as_bool(sr2.get("macro_tick", false)):
			break

	# Pump a few extra frames so outbound WS frames arrive at client peer
	for _j: int in range(20):
		srv_node.pump_network()
		cc._process(0.02)
		if cc.last_state_crc32 == srv_node.server.state_crc32 and cc.client_tick == srv_node.server.clock.current_tick_id:
			break
		OS.delay_msec(10)

	assert_gte(srv_node.server.regional_market.orders.size(), 1, "Remote market order accepted via WebSocket")
	assert_eq(cc.last_state_crc32, srv_node.server.state_crc32, "Client CRC32 matches remote HeadlessServerMain CRC32")
	assert_contains(cc.manor_view._header_label.text, "manor_ws_hero_01", "Remote ClientController ManorGridView hydrated via WebSocket")

	# Test disconnect & reconnect gazette flow
	cc.stop_live_session()
	for _i: int in range(25):
		srv_node.pump_network()
		if srv_node.server.sessions_by_peer.is_empty():
			break
		OS.delay_msec(10)
	assert_true(srv_node.server.sessions_by_peer.is_empty(), "HeadlessServerMain cleaned up disconnected ws peer")
	var acct_after_dc: Dictionary = srv_node.server.player_accounts.get("ws_hero_01", {})
	assert_eq(_as_int(acct_after_dc.get("is_online", 1), 1), 0, "Disconnected player marked offline (LOD 1)")

	# Reconnect with a brand-new ClientController (cmd_seq == 0) and verify MSG_WS_WELCOME sync,
	# MSG_OFFLINE_CHRONICLE_DIGEST delivery, zero ERR_RATE_LIMITED, and post-reconnect CMD_PLACE_MARKET_ORDER ACCEPTED
	var cc2: ClientController = ClientController.new()
	cc2.auto_start_live_demo = false
	cc2.player_id = "ws_hero_01"
	var _tracked_cc2: Node = _track_ui(cc2)

	var gazettes: Array[Dictionary] = []
	cc2.gazette_received.connect(func(g: Dictionary) -> void: gazettes.append(g))
	var re_err: Error = cc2.connect_remote_websocket("ws://127.0.0.1:%d" % ws_port, "ws_hero_01")
	assert_eq(re_err, OK, "Reconnect WebSocket initiated cleanly on fresh ClientController")
	for _i: int in range(80):
		srv_node.pump_network()
		cc2._process(0.02)
		if gazettes.size() >= 1 and cc2.get_live_driver().is_remote_connected() and cc2.cmd_seq >= 2:
			break
		OS.delay_msec(10)
	assert_gte(gazettes.size(), 1, "Reconnecting WebSocket client receives MSG_OFFLINE_CHRONICLE_DIGEST")
	assert_false(cc2._cmd_feedback_label.text.contains("ERR_RATE_LIMITED"), "Reconnect handshake produces ZERO ERR_RATE_LIMITED")
	assert_gte(cc2.cmd_seq, 2, "MSG_WS_WELCOME synchronized client cmd_seq to server last_accepted_seq")

	var orders_before_re: int = srv_node.server.regional_market.orders.size()
	var _re_ord_env: Dictionary = cc2.package_command("CMD_PLACE_MARKET_ORDER", {
		"node_id": "xuchang",
		"commodity": "GRAIN",
		"side": "ASK",
		"price_bp": 1220,
		"quantity": 10
	})
	for _i: int in range(25):
		var _sr3: Dictionary = srv_node.step_server_tick()
		cc2._process(0.02)
		if srv_node.server.regional_market.orders.size() > orders_before_re and cc2._cmd_feedback_label.text.contains("수락"):
			break
		OS.delay_msec(10)
	assert_gt(srv_node.server.regional_market.orders.size(), orders_before_re, "Post-reconnect CMD_PLACE_MARKET_ORDER accepted by server")
	assert_contains(cc2._cmd_feedback_label.text, "수락", "Fresh reconnecting client received ACCEPTED receipt with zero ERR_RATE_LIMITED")

	# Flush persistence and verify SQLite DB + atomic snapshot files exist
	srv_node.stop_server()
	assert_true(FileAccess.file_exists(db_p), "HeadlessServerMain persisted SQLite DB")
	assert_true(FileAccess.file_exists(snap_p), "HeadlessServerMain persisted atomic snapshot")
	assert_true(FileAccess.file_exists(wal_p), "HeadlessServerMain persisted WAL JSONL")


func test_duplicate_player_id_ws_hijack_rejected_and_active_peer_stays_online() -> void:
	var ws_port: int = _find_available_port(19170, 40)
	var srv_node: HeadlessServerMain = HeadlessServerMain.new()
	srv_node.auto_start_on_ready = false
	srv_node.configure({
		"port": ws_port,
		"bind": "127.0.0.1",
		"seed": 18401,
		"tick_sec": 0.2,
		"persist_enabled": false
	})
	var _tracked_srv: Node = _track_ui(srv_node)
	assert_eq(srv_node.start_server(), OK, "HeadlessServerMain started for duplicate WS hijack test")

	var legit_cc: ClientController = ClientController.new()
	legit_cc.auto_start_live_demo = false
	var _tracked_legit: Node = _track_ui(legit_cc)
	assert_eq(legit_cc.connect_remote_websocket("ws://127.0.0.1:%d" % ws_port, "legit_lord"), OK, "Legit client connects")
	for _i: int in range(80):
		srv_node.pump_network()
		legit_cc._process(0.02)
		if legit_cc.get_live_driver().is_remote_connected() and srv_node.server.peer_by_player.has("legit_lord"):
			break
		OS.delay_msec(10)
	assert_true(srv_node.server.peer_by_player.has("legit_lord"), "Legit player bound to active WS peer")
	var legit_pkey: String = str(srv_node.server.peer_by_player["legit_lord"])

	# Attacker connects on a second WebSocket claiming the same player_id
	var attacker: NetworkTransport = NetworkTransport.new(NetworkTransport.MODE_WEBSOCKET)
	assert_eq(attacker.connect_websocket("ws://127.0.0.1:%d" % ws_port), OK, "Attacker opened WS socket")
	var attacker_replies: Array[Dictionary] = []
	var sent_spoof: bool = false
	for _i: int in range(80):
		attacker.poll()
		if attacker.is_ws_client_open() and not sent_spoof:
			sent_spoof = true
			var _ok_s: bool = attacker.client_send_envelope("legit_lord", {
				"v": 1,
				"msg_type": "MSG_WS_HELLO",
				"player_id": "legit_lord",
				"display_name": "Impostor"
			})
		srv_node.pump_network()
		for m: Dictionary in attacker.client_drain_incoming("legit_lord"):
			attacker_replies.append(m)
		if not attacker_replies.is_empty():
			break
		OS.delay_msec(10)

	assert_gte(attacker_replies.size(), 1, "Duplicate login received rejection receipt")
	assert_eq(str(attacker_replies[0].get("status", "")), "REJECTED", "Duplicate player_id login status is REJECTED")
	assert_eq(str(attacker_replies[0].get("error_code", "")), DtoSchemas.ERR_UNAUTHORIZED, "Duplicate player_id rejected with ERR_UNAUTHORIZED")
	assert_eq(str(srv_node.server.peer_by_player.get("legit_lord", "")), legit_pkey, "Original peer ownership preserved")

	# Disconnecting attacker must NEVER mark legit_lord offline
	attacker.close()
	for _i: int in range(25):
		srv_node.pump_network()
		OS.delay_msec(10)
	var acct: Dictionary = srv_node.server.player_accounts.get("legit_lord", {})
	assert_eq(_as_int(acct.get("is_online", 0), 0), 1, "Active legit_lord stays online after attacker disconnects")
	assert_eq(str(srv_node.server.peer_by_player.get("legit_lord", "")), legit_pkey, "Active legit_lord peer binding remains intact")


func test_headless_server_crash_recovery_pre_and_post_snapshot_wal_replay() -> void:
	var _mk_err: Error = DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)

	# Scenario A: Pre-snapshot WAL-only crash recovery (no snapshot file yet)
	var pre_db: String = _track_scratch_file(SCRATCH_DIR + "/test_pre_wal.db")
	var pre_wal: String = _track_scratch_file(SCRATCH_DIR + "/test_pre_wal.jsonl")
	var pre_snap: String = _track_scratch_file(SCRATCH_DIR + "/test_pre_wal_snap.json")
	var pre_port1: int = _find_available_port(19220, 40)

	var srv_a1: HeadlessServerMain = HeadlessServerMain.new()
	srv_a1.auto_start_on_ready = false
	srv_a1.configure({
		"port": pre_port1,
		"db": pre_db,
		"wal": pre_wal,
		"snapshot": pre_snap,
		"seed": 18401,
		"snapshot_interval": 500,
		"persist_enabled": true
	})
	var _ta1: Node = _track_ui(srv_a1)
	assert_eq(srv_a1.start_server(), OK, "Scenario A server 1 started")
	var _r_a: Dictionary = srv_a1.server.register_session("peer_wal_a", "wal_a", "wal_a")
	var _sub_a1: Dictionary = srv_a1.server.submit_raw_command("peer_wal_a", {
		"v": 1, "cmd_seq": 1, "client_tick": 0, "player_id": "wal_a",
		"cmd_type": "CMD_CREATE_CHARACTER",
		"args": {
			"avatar_name": "강유",
			"creation_mode": "INTERVIEW_ONLY",
			"origin_override": "ORIGIN_FRONTIER_OFFICER",
			"province_override": "YU_ZHOU",
			"interview_answers": [1, 0, 1, 2, 1, 0, 2, 1]
		}
	})
	var _st_a1: Dictionary = srv_a1.step_server_tick()
	var _sub_a2: Dictionary = srv_a1.server.submit_raw_command("peer_wal_a", {
		"v": 1, "cmd_seq": 2, "client_tick": 1, "player_id": "wal_a",
		"cmd_type": "CMD_PLACE_MARKET_ORDER",
		"args": {"node_id": "xuchang", "commodity": "GRAIN", "side": "ASK", "price_bp": 1150, "quantity": 10}
	})
	var _st_a2: Dictionary = srv_a1.step_server_tick()
	assert_false(FileAccess.file_exists(pre_snap), "Pre-snapshot crash has no snapshot file yet")
	assert_true(FileAccess.file_exists(pre_wal), "Pre-snapshot crash has WAL records on disk")

	# Simulate crash (disable persist_enabled before stop_server so flush_persistence is NOT called!)
	srv_a1.persist_enabled = false
	srv_a1.stop_server()

	var pre_port2: int = _find_available_port(19260, 40)
	var srv_a2: HeadlessServerMain = HeadlessServerMain.new()
	srv_a2.auto_start_on_ready = false
	srv_a2.configure({
		"port": pre_port2,
		"db": pre_db,
		"wal": pre_wal,
		"snapshot": pre_snap,
		"seed": 18401,
		"snapshot_interval": 500,
		"persist_enabled": true
	})
	var _ta2: Node = _track_ui(srv_a2)
	assert_eq(srv_a2.start_server(), OK, "Scenario A recovery server started from WAL-only")
	assert_true(srv_a2.server.manors.has("wal_a"), "Pre-snapshot WAL replay recovered manor for wal_a")
	assert_gte(srv_a2.server.regional_market.orders.size(), 1, "Pre-snapshot WAL replay recovered dependent market order")
	for pe_k: Variant in srv_a2.server.sessions_by_peer.keys():
		assert_false(str(pe_k).begins_with("replay_"), "No leaked replay_* peers remain after recovery")

	# Scenario B: Post-snapshot WAL replay (snapshot at tick 2, then dependent commands at tick 3 and 4, then crash)
	srv_a2.flush_persistence()
	assert_true(FileAccess.file_exists(pre_snap), "Snapshot saved at tick %d" % srv_a2.server.clock.current_tick_id)
	var _r_b: Dictionary = srv_a2.server.register_session("peer_wal_b", "wal_b", "wal_b")
	var _sub_b1: Dictionary = srv_a2.server.submit_raw_command("peer_wal_b", {
		"v": 1, "cmd_seq": 1, "client_tick": srv_a2.server.clock.current_tick_id, "player_id": "wal_b",
		"cmd_type": "CMD_CREATE_CHARACTER",
		"args": {
			"avatar_name": "등애",
			"creation_mode": "INTERVIEW_ONLY",
			"origin_override": "ORIGIN_CHIVALROUS_HERO",
			"province_override": "YU_ZHOU",
			"interview_answers": [0, 1, 2, 0, 1, 2, 0, 1]
		}
	})
	var _st_b1: Dictionary = srv_a2.step_server_tick()
	var _sub_b2: Dictionary = srv_a2.server.submit_raw_command("peer_wal_b", {
		"v": 1, "cmd_seq": 2, "client_tick": srv_a2.server.clock.current_tick_id, "player_id": "wal_b",
		"cmd_type": "CMD_PLACE_MARKET_ORDER",
		"args": {"node_id": "xuchang", "commodity": "GRAIN", "side": "ASK", "price_bp": 1180, "quantity": 12}
	})
	var _st_b2: Dictionary = srv_a2.step_server_tick()
	srv_a2.persist_enabled = false
	srv_a2.stop_server()

	var pre_port3: int = _find_available_port(19300, 40)
	var srv_a3: HeadlessServerMain = HeadlessServerMain.new()
	srv_a3.auto_start_on_ready = false
	srv_a3.configure({
		"port": pre_port3,
		"db": pre_db,
		"wal": pre_wal,
		"snapshot": pre_snap,
		"seed": 18401,
		"snapshot_interval": 500,
		"persist_enabled": true
	})
	var _ta3: Node = _track_ui(srv_a3)
	assert_eq(srv_a3.start_server(), OK, "Scenario B recovery server started from snapshot + WAL")
	assert_true(srv_a3.server.manors.has("wal_b"), "Post-snapshot WAL replay recovered manor for wal_b")
	assert_gte(srv_a3.server.regional_market.orders.size(), 2, "Post-snapshot WAL replay recovered dependent market order for wal_b")
	var invalid_state_rejects: int = 0
	for aud: Dictionary in srv_a3.server.command_validator.audit_log:
		if str(aud.get("reject_reason", "")).contains("ERR_INVALID_STATE"):
			invalid_state_rejects += 1
	assert_eq(invalid_state_rejects, 0, "Post-snapshot WAL replay produced zero ERR_INVALID_STATE rejections")
	srv_a3.stop_server()
	assert_true(FileAccess.file_exists(pre_db), "Recovered SQLite DB exists after clean stop")


func test_session_mode_switch_resets_caches_and_clamps_tick_accumulator() -> void:
	var cc: ClientController = ClientController.new()
	cc.auto_start_live_demo = false
	var _tracked: Node = _track_ui(cc)

	var _b1: Dictionary = cc.start_local_demo(18401)
	cc.step_demo_ticks(18)  # tick 24
	assert_gte(cc.client_tick, 24, "Run 1 reached tick >= 24")
	assert_gt(cc.court_hud._cached_orders.size(), 0, "Run 1 populated market orders cache")
	assert_gt(cc.macro_view._cached_armies.size(), 0, "Run 1 populated armies cache")

	# Switch to unreachable remote WebSocket -> closed/refused state, then back to fresh Local Demo
	var _cerr: Error = cc.connect_remote_websocket("ws://127.0.0.1:1", "player_01")
	assert_eq(cc.client_tick, 0, "Switching to remote WS reset client_tick to 0")
	assert_eq(cc.court_hud._cached_orders.size(), 0, "Switching to remote WS cleared stale orders cache")
	assert_eq(cc.macro_view._cached_armies.size(), 0, "Switching to remote WS cleared stale armies cache")

	var _b2: Dictionary = cc.start_local_demo(18401)
	var srv2: AuthoritativeServer = cc.get_live_driver().local_server
	assert_eq(cc.client_tick, srv2.clock.current_tick_id, "Restarted Local Demo client_tick matches fresh server tick (6)")
	assert_eq(cc.court_hud._cached_orders.size(), srv2.regional_market.orders.size(), "Restarted Local Demo orders cache matches fresh server (0)")
	assert_eq(cc.macro_view._cached_armies.size(), srv2.army_manager.get_entity_ids().size(), "Restarted Local Demo armies cache matches fresh server (0)")

	# Accumulator spike clamp: delta=10.0 executes 5 catch-up steps, follow-up delta=0.016 executes 0 steps
	var t_before: int = cc.client_tick
	cc.set_demo_speed(1)
	cc._process(10.0)
	assert_eq(cc.client_tick, t_before + 5, "Spike delta=10.0 capped at 5 catch-up ticks")
	assert_lt(cc._tick_accumulator_sec, 1.0, "Accumulator clamped below 1.0s after catch-up cap")
	cc._process(0.016)
	assert_eq(cc.client_tick, t_before + 5, "Follow-up 0.016s frame advances 0 ticks (no burst storm)")


func test_headless_server_malformed_cli_flags_preserve_safe_defaults() -> void:
	var hsm: HeadlessServerMain = HeadlessServerMain.new()
	hsm.auto_start_on_ready = false
	var _tracked: Node = _track_ui(hsm)

	var opts_bad: Dictionary = hsm.parse_cli_args_list(PackedStringArray([
		"--port=abc",
		"--seed=not_an_int",
		"--tick-sec=-0.5",
		"--snapshot-interval=0",
		"--quit-after-ticks=-1"
	]))
	hsm.configure(opts_bad)
	assert_eq(hsm.port, 9090, "Malformed --port=abc preserves default port 9090")
	assert_eq(hsm.world_seed, 18401, "Malformed --seed preserves default world_seed 18401")
	assert_true(is_equal_approx(hsm.tick_interval_sec, 1.0), "Non-positive --tick-sec preserves default 1.0s")
	assert_eq(hsm.snapshot_interval_ticks, 24, "Zero --snapshot-interval preserves default 24")
	assert_eq(hsm.quit_after_ticks, 0, "Negative --quit-after-ticks preserves default 0")

	var opts_oor: Dictionary = hsm.parse_cli_args_list(PackedStringArray(["--port=0", "--port=70000"]))
	hsm.configure(opts_oor)
	assert_eq(hsm.port, 9090, "Out-of-range ports 0 and 70000 preserve default port 9090")


func test_web_export_preset_and_project_rendering_config() -> void:
	assert_true(FileAccess.file_exists("res://export_presets.cfg"), "export_presets.cfg exists at project root")
	var presets: ConfigFile = ConfigFile.new()
	var load_err: Error = presets.load("res://export_presets.cfg")
	assert_eq(load_err, OK, "export_presets.cfg parses cleanly via ConfigFile")
	assert_eq(str(presets.get_value("preset.0", "name", "")), "Web", "preset.0 name is Web")
	assert_eq(str(presets.get_value("preset.0", "platform", "")), "Web", "preset.0 platform is Web")
	assert_true(_as_bool(presets.get_value("preset.0", "runnable", false)), "Web preset is runnable")
	assert_eq(str(presets.get_value("preset.0", "export_filter", "")), "all_resources", "Web preset exports all_resources")
	assert_eq(str(presets.get_value("preset.0", "export_path", "")), "build/web/index.html", "Web preset exports to build/web/index.html")
	assert_false(_as_bool(presets.get_value("preset.0.options", "variant/thread_support", true), true), "Web preset disables thread_support for GitHub Pages compatibility")
	assert_true(_as_bool(presets.get_value("preset.0.options", "vram_texture_compression/for_desktop", false)), "Web preset enables desktop VRAM texture compression")
	var head_inc: String = str(presets.get_value("preset.0.options", "html/head_include", ""))
	assert_contains(head_inc, "coi-serviceworker.js", "Web preset head_include references coi-serviceworker.js")

	var proj_cfg: ConfigFile = ConfigFile.new()
	var proj_err: Error = proj_cfg.load("res://project.godot")
	assert_eq(proj_err, OK, "project.godot parses cleanly via ConfigFile")
	assert_eq(
		str(proj_cfg.get_value("rendering", "renderer/rendering_method.web", "")),
		"gl_compatibility",
		"project.godot sets Web renderer to gl_compatibility"
	)


func test_web_cjk_font_and_github_pages_workflow_present() -> void:
	assert_true(FileAccess.file_exists("res://web/coi-serviceworker.js"), "web/coi-serviceworker.js exists")
	var sw_file: FileAccess = FileAccess.open("res://web/coi-serviceworker.js", FileAccess.READ)
	assert_not_null(sw_file, "Opened web/coi-serviceworker.js")
	if sw_file != null:
		var sw_text: String = sw_file.get_as_text()
		sw_file.close()
		assert_contains(sw_text, "coi-serviceworker", "coi-serviceworker.js contains valid service worker header")

	assert_true(FileAccess.file_exists("res://.github/workflows/deploy-pages.yml"), ".github/workflows/deploy-pages.yml exists")
	var wf_file: FileAccess = FileAccess.open("res://.github/workflows/deploy-pages.yml", FileAccess.READ)
	assert_not_null(wf_file, "Opened deploy-pages.yml")
	if wf_file != null:
		var wf_text: String = wf_file.get_as_text()
		wf_file.close()
		assert_contains(wf_text, "4.4.1-stable", "deploy-pages.yml pins Godot 4.4.1-stable")
		assert_contains(wf_text, "--export-release \"Web\" build/web/index.html", "deploy-pages.yml exports Web preset")
		assert_contains(wf_text, "actions/configure-pages@v5", "deploy-pages.yml configures GitHub Pages")
		assert_contains(wf_text, "actions/upload-pages-artifact@v3", "deploy-pages.yml uploads Pages artifact")
		assert_contains(wf_text, "actions/deploy-pages@v4", "deploy-pages.yml deploys to GitHub Pages")

	assert_true(FileAccess.file_exists("res://assets/fonts/NotoSansKR-Subset.otf"), "Bundled Korean CJK font exists for Web WASM")
	assert_true(FileAccess.file_exists("res://assets/fonts/OFL.txt"), "Bundled OFL.txt license file exists")
	var reg: AssetRegistry = AssetRegistry.new()
	var ui_font: Font = reg.get_ui_font()
	assert_not_null(ui_font, "AssetRegistry.get_ui_font() returns valid Font")
	var audio_mgr: AudioManager = AudioManager.new()
	assert_gte(audio_mgr.get_loaded_sfx_count(), 16, "AudioManager preloads all 16 SFX streams via ResourceLoader")
	assert_gte(audio_mgr.get_loaded_bgm_count(), 1, "AudioManager preloads BGM stream via ResourceLoader")
	audio_mgr.free()

