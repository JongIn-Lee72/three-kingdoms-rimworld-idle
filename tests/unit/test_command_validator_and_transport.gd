class_name TestCommandValidatorAndTransport
extends HarnessTestCase


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


func _make_env(player_id: String, cmd_seq: int, cmd_type: String, args: Dictionary, tick: int = 1) -> Dictionary:
	return {
		"v": 1,
		"cmd_seq": cmd_seq,
		"client_tick": tick,
		"player_id": player_id,
		"cmd_type": cmd_type,
		"args": args
	}


func _make_test_server_ctx() -> Dictionary:
	var wg: WorldGraph = WorldGraph.new({}, true)
	var fm: FactionManager = FactionManager.new()
	var _f_res: Dictionary = fm.create_faction("fac_wei", "Wei", "lord_a", "xuchang", wg, 10000, 10000, "PREFECT")
	var _en_b: Dictionary = fm.enlist_officer("officer_b", "fac_wei", "RANK_9")
	var _reg_c: Dictionary = fm.register_player("free_c")

	var m_a: ManorState = ManorState.new("manor_lord_a", "lord_a")
	m_a.host_node_id = "xuchang"
	var p_a: PawnEntity = PawnEntity.new("lord_a_avatar", "Lord A", true)
	p_a.owner_player_id = "lord_a"
	var _add_a: bool = m_a.add_pawn(p_a)

	var m_b: ManorState = ManorState.new("manor_officer_b", "officer_b")
	m_b.host_node_id = "xuchang"
	var p_b: PawnEntity = PawnEntity.new("officer_b_avatar", "Officer B", true)
	p_b.owner_player_id = "officer_b"
	var _add_b: bool = m_b.add_pawn(p_b)

	var rm: RegionalMarket = RegionalMarket.new(wg)
	var cis: ChronicleInboxService = ChronicleInboxService.new()

	return {
		"current_tick_id": 10,
		"peer_to_player": {
			"peer_a": "lord_a",
			"peer_b": "officer_b",
			"peer_c": "free_c"
		},
		"manors": {
			"lord_a": m_a,
			"officer_b": m_b
		},
		"world_graph": wg,
		"faction_manager": fm,
		"regional_market": rm,
		"chronicle_inbox": cis
	}


func test_network_transport_loopback_peer_registration_send_drain_and_broadcast() -> void:
	var tr: NetworkTransport = NetworkTransport.new().create_loopback()
	assert_eq(tr.mode, NetworkTransport.MODE_LOOPBACK, "Transport mode is LOOPBACK_MEMORY")

	var pk_a: String = tr.register_loopback_peer("peer_a")
	var pk_b: String = tr.register_loopback_peer("peer_b")
	assert_eq(pk_a, "peer_a", "peer_a registered")
	assert_eq(pk_b, "peer_b", "peer_b registered")
	assert_true(tr.has_peer("peer_a"), "has_peer(peer_a) == true")
	assert_false(tr.has_peer("peer_unknown"), "has_peer(peer_unknown) == false")
	assert_eq(tr.get_connected_peer_ids(), ["peer_a", "peer_b"], "Connected peer IDs sorted")

	# Raw send & server drain
	assert_true(tr.client_send_raw("peer_a", "{\"hello\":1}"), "client_send_raw succeeds")
	assert_true(tr.client_send_envelope("peer_b", _make_env("officer_b", 1, "CMD_SET_DOCTRINE", {})), "client_send_envelope succeeds")
	var srv_in: Array[Dictionary] = tr.server_drain_incoming()
	assert_eq(srv_in.size(), 2, "Server drained 2 packets")
	assert_eq(str(srv_in[0].get("peer_key", "")), "peer_a", "First packet from peer_a")
	assert_eq(str(srv_in[1].get("peer_key", "")), "peer_b", "Second packet from peer_b")
	assert_eq(tr.server_drain_incoming().size(), 0, "Server inbox empty after drain")

	# Server broadcast -> client drain
	tr.server_broadcast({"v": 1, "msg_type": "MSG_TEST", "tick_id": 10})
	var c_a: Array[Dictionary] = tr.client_drain_incoming("peer_a")
	var c_b: Array[Dictionary] = tr.client_drain_incoming("peer_b")
	assert_eq(c_a.size(), 1, "peer_a received broadcast")
	assert_eq(c_b.size(), 1, "peer_b received broadcast")
	assert_eq(_as_int(c_a[0].get("tick_id", 0), 0), 10, "Broadcast payload tick_id normalized as int 10")
	assert_eq(tr.client_drain_incoming("peer_a").size(), 0, "peer_a inbox cleared after drain")


func test_command_validator_stage1_to_stage6_and_rate_limiting() -> void:
	var cv: CommandValidator = CommandValidator.new()
	var ctx: Dictionary = _make_test_server_ctx()

	# Stage 1 (ERR_SCHEMA): oversized >4096B payload & invalid JSON
	var big_pad: String = "x".repeat(4200)
	var big_json: String = StateHasher.canonical_json(_make_env("lord_a", 1, "CMD_SET_DOCTRINE", {"pad": big_pad}))
	var r_big: Dictionary = cv.validate_raw_command("peer_a", big_json, ctx)
	assert_false(_as_bool(r_big.get("accepted", true), true), "Oversized >4096B payload rejected")
	assert_eq(str(r_big.get("error_code", "")), DtoSchemas.ERR_SCHEMA, "Oversized payload returns ERR_SCHEMA")

	var r_bad_json: Dictionary = cv.validate_raw_command("peer_a", "{not_valid_json", ctx)
	assert_false(_as_bool(r_bad_json.get("accepted", true), true), "Invalid JSON rejected")
	assert_eq(str(r_bad_json.get("error_code", "")), DtoSchemas.ERR_SCHEMA, "Invalid JSON returns ERR_SCHEMA")

	# Stage 2 (ERR_UNAUTHORIZED): spoofing another player_id, manor_id, or pawn_id
	var r_spoof_player: Dictionary = cv.validate_raw_command(
		"peer_b",
		_make_env("lord_a", 1, "CMD_SET_DOCTRINE", {}),
		ctx
	)
	assert_false(_as_bool(r_spoof_player.get("accepted", true), true), "Spoofed player_id rejected")
	assert_eq(str(r_spoof_player.get("error_code", "")), DtoSchemas.ERR_UNAUTHORIZED, "Spoofed player_id returns ERR_UNAUTHORIZED")

	var r_spoof_manor: Dictionary = cv.validate_raw_command(
		"peer_b",
		_make_env("officer_b", 1, "CMD_SET_DOCTRINE", {"manor_id": "manor_lord_a"}),
		ctx
	)
	assert_false(_as_bool(r_spoof_manor.get("accepted", true), true), "Cross-player manor_id rejected")
	assert_eq(str(r_spoof_manor.get("error_code", "")), DtoSchemas.ERR_UNAUTHORIZED, "Cross-player manor_id returns ERR_UNAUTHORIZED")

	var r_spoof_pawn: Dictionary = cv.validate_raw_command(
		"peer_b",
		_make_env("officer_b", 1, "CMD_SET_WORK_PRIORITY", {"pawn_id": "lord_a_avatar", "domain": "PATROL", "priority": 1}),
		ctx
	)
	assert_false(_as_bool(r_spoof_pawn.get("accepted", true), true), "Cross-player pawn_id rejected")
	assert_eq(str(r_spoof_pawn.get("error_code", "")), DtoSchemas.ERR_UNAUTHORIZED, "Cross-player pawn_id returns ERR_UNAUTHORIZED")

	# Stage 4 (ERR_ROLE_PERMISSION): non-LORD treaty/governor & non-governor node policy
	var r_treaty_nonlord: Dictionary = cv.validate_raw_command(
		"peer_b",
		_make_env("officer_b", 1, "CMD_PROPOSE_OR_SIGN_TREATY", {"target_faction_id": "YELLOW_TURBAN"}),
		ctx
	)
	assert_false(_as_bool(r_treaty_nonlord.get("accepted", true), true), "Non-LORD treaty rejected")
	assert_eq(str(r_treaty_nonlord.get("error_code", "")), DtoSchemas.ERR_ROLE_PERMISSION, "Non-LORD treaty returns ERR_ROLE_PERMISSION")

	var r_gov_nonlord: Dictionary = cv.validate_raw_command(
		"peer_b",
		_make_env("officer_b", 2, "CMD_APPOINT_GOVERNOR", {"target_player_id": "officer_b", "node_id": "xuchang"}),
		ctx
	)
	assert_false(_as_bool(r_gov_nonlord.get("accepted", true), true), "Non-LORD appoint governor rejected")
	assert_eq(str(r_gov_nonlord.get("error_code", "")), DtoSchemas.ERR_ROLE_PERMISSION, "Non-LORD appoint governor returns ERR_ROLE_PERMISSION")

	var r_pol_nongov: Dictionary = cv.validate_raw_command(
		"peer_b",
		_make_env("officer_b", 3, "CMD_SET_NODE_POLICY", {"node_id": "xuchang", "tax_rate_bp": 1000}),
		ctx
	)
	assert_false(_as_bool(r_pol_nongov.get("accepted", true), true), "Non-governor node policy rejected")
	assert_eq(str(r_pol_nongov.get("error_code", "")), DtoSchemas.ERR_ROLE_PERMISSION, "Non-governor node policy returns ERR_ROLE_PERMISSION")

	# Stage 5 (ERR_SCHEMA / ERR_PLAINTEXT_JSON_FORBIDDEN): priority out of 0..4 & plaintext JSON in CMD_CREATE_CHARACTER
	var r_prio_bad: Dictionary = cv.validate_raw_command(
		"peer_a",
		_make_env("lord_a", 1, "CMD_SET_WORK_PRIORITY", {"pawn_id": "lord_a_avatar", "domain": "PATROL", "priority": 5}),
		ctx
	)
	assert_false(_as_bool(r_prio_bad.get("accepted", true), true), "Priority 5 out of 0..4 rejected")
	assert_eq(str(r_prio_bad.get("error_code", "")), DtoSchemas.ERR_SCHEMA, "Priority out of 0..4 returns ERR_SCHEMA")

	var r_plaintext: Dictionary = cv.validate_raw_command(
		"peer_c",
		_make_env("free_c", 1, "CMD_CREATE_CHARACTER", {
			"creation_mode": "FUSION_INTERVIEW",
			"sealed_token_input": "{\"AI_PERSONA_EXPORT_V1\":true,\"LEA\":99}"
		}),
		ctx
	)
	assert_false(_as_bool(r_plaintext.get("accepted", true), true), "Plaintext JSON in CMD_CREATE_CHARACTER rejected")
	assert_eq(str(r_plaintext.get("error_code", "")), DtoSchemas.ERR_PLAINTEXT_JSON_FORBIDDEN, "Plaintext JSON returns ERR_PLAINTEXT_JSON_FORBIDDEN")

	# Stage 6 (ACCEPTED): valid command returns MSG_CMD_RECEIPT with exec_tick_id = tick + 1 and audit log entry
	var audit_before: int = cv.audit_log.size()
	var r_ok: Dictionary = cv.validate_raw_command(
		"peer_a",
		_make_env("lord_a", 1, "CMD_SET_WORK_PRIORITY", {"pawn_id": "lord_a_avatar", "domain": "PATROL", "priority": 1}),
		ctx
	)
	assert_true(_as_bool(r_ok.get("accepted", false), false), "Valid command accepted")
	assert_eq(str(r_ok.get("error_code", "")), DtoSchemas.ERR_OK, "Accepted error_code == OK")
	assert_eq(_as_int(r_ok.get("exec_tick_id", -1), -1), 11, "exec_tick_id == current_tick + 1 (11)")
	var receipt: Dictionary = _as_dict(r_ok.get("receipt", {}))
	var vr: Dictionary = DtoSchemas.validate_cmd_receipt(receipt)
	assert_true(_as_bool(vr.get("ok", false), false), "Receipt satisfies DtoSchemas.validate_cmd_receipt")
	assert_eq(_as_int(receipt.get("exec_tick_id", -1), -1), 11, "Receipt exec_tick_id == 11")
	assert_eq(cv.audit_log.size(), audit_before + 1, "Audit log gained 1 ACCEPTED record")
	var last_audit: Dictionary = _as_dict(r_ok.get("audit_record", {}))
	assert_eq(str(last_audit.get("status", "")), "ACCEPTED", "Audit record status == ACCEPTED")

	# Stage 3 (ERR_RATE_LIMITED): duplicate/non-monotonic cmd_seq replay rejected
	var r_replay: Dictionary = cv.validate_raw_command(
		"peer_a",
		_make_env("lord_a", 1, "CMD_SET_DOCTRINE", {}),
		ctx
	)
	assert_false(_as_bool(r_replay.get("accepted", true), true), "Duplicate cmd_seq replay rejected")
	assert_eq(str(r_replay.get("error_code", "")), DtoSchemas.ERR_RATE_LIMITED, "Duplicate cmd_seq returns ERR_RATE_LIMITED")

	# Stage 3 (ERR_RATE_LIMITED): burst > 10 in same tick triggers token bucket limit
	# lord_a already consumed 2 tokens in Stage 3 during tick 10 (r_prio_bad + r_ok), so 8 tokens remain
	for seq_i: int in range(2, 10):
		var r_burst_ok: Dictionary = cv.validate_raw_command(
			"peer_a",
			_make_env("lord_a", seq_i, "CMD_SET_DOCTRINE", {"step": seq_i}),
			ctx
		)
		assert_true(_as_bool(r_burst_ok.get("accepted", false), false), "Burst command seq=%d within 10-token cap accepted" % seq_i)

	var r_burst_over: Dictionary = cv.validate_raw_command(
		"peer_a",
		_make_env("lord_a", 10, "CMD_SET_DOCTRINE", {"step": 10}),
		ctx
	)
	assert_false(_as_bool(r_burst_over.get("accepted", true), true), "11th command in same tick exceeds burst limit")
	assert_eq(str(r_burst_over.get("error_code", "")), DtoSchemas.ERR_RATE_LIMITED, "Burst > 10 returns ERR_RATE_LIMITED")

	# Advancing 1 tick refills TOKEN_BUCKET_REFILL_PER_TICK (3) tokens
	ctx["current_tick_id"] = 11
	var r_refill_ok: Dictionary = cv.validate_raw_command(
		"peer_a",
		_make_env("lord_a", 11, "CMD_SET_DOCTRINE", {"step": 11}),
		ctx
	)
	assert_true(_as_bool(r_refill_ok.get("accepted", false), false), "Token bucket refills on next tick")
