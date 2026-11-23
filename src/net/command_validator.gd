class_name CommandValidator
extends RefCounted

const TOKEN_BUCKET_BURST: int = 10
const TOKEN_BUCKET_REFILL_PER_TICK: int = 3

const KNOWN_COMMANDS: Array[String] = [
	"CMD_REQUEST_PERSONA_CHALLENGE",
	"CMD_CREATE_CHARACTER",
	"CMD_SET_WORK_PRIORITY",
	"CMD_SET_SCHEDULE",
	"CMD_SET_DOCTRINE",
	"CMD_BUILD_OR_UPGRADE",
	"CMD_PROMOTE_TROOPS",
	"CMD_DISPATCH_EXPEDITION",
	"CMD_PLACE_MARKET_ORDER",
	"CMD_CANCEL_MARKET_ORDER",
	"CMD_ENLIST_FACTION",
	"CMD_POST_MISSION",
	"CMD_APPOINT_GOVERNOR",
	"CMD_SET_NODE_POLICY",
	"CMD_PROPOSE_OR_SIGN_TREATY",
	"CMD_BREAK_TREATY",
	"CMD_FUND_INSURGENTS",
	"CMD_CREATE_COALITION_RALLY",
	"CMD_JOIN_COALITION_RALLY",
	"CMD_EXECUTE_COALITION_SIEGE",
	"CMD_HOST_BANQUET",
	"CMD_SOW_DISCORD",
	"CMD_POACH_RETAINER",
	"CMD_RAISE_UPRISING",
	"CMD_DECIDE_INBOX_EVENT",
	"CMD_SUBSCRIBE_CHANNEL"
]

var last_accepted_seq: Dictionary = {}  # player_id -> int
var token_buckets: Dictionary = {}      # player_id -> {"tokens": int, "last_tick": int}
var audit_log: Array[Dictionary] = []


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


static func _to_bool(v: Variant, fallback: bool = false) -> bool:
	if v is bool:
		var bv: bool = v
		return bv
	if v is int:
		var iv: int = v
		return iv != 0
	return fallback


func _init() -> void:
	last_accepted_seq.clear()
	token_buckets.clear()
	audit_log.clear()


func _build_receipt(cmd_seq: int, accepted: bool, error_code: String, exec_tick_id: int, reason: String = "") -> Dictionary:
	return {
		"v": 1,
		"msg_type": DtoSchemas.MSG_CMD_RECEIPT,
		"cmd_seq": maxi(0, cmd_seq),
		"status": "ACCEPTED" if accepted else "REJECTED",
		"error_code": DtoSchemas.ERR_OK if accepted else error_code,
		"exec_tick_id": maxi(0, exec_tick_id),
		"reason": reason
	}


func _build_audit_record(
	tick_id: int,
	player_id: String,
	cmd_type: String,
	accepted: bool,
	reject_reason: String,
	payload_dict: Dictionary
) -> Dictionary:
	var pid_safe: String = player_id if not player_id.is_empty() else "UNKNOWN"
	var cmd_safe: String = cmd_type if not cmd_type.is_empty() else "UNKNOWN"
	var payload_json: String = StateHasher.canonical_json(payload_dict)
	if payload_json.length() < 2:
		payload_json = "{}"
	return {
		"tick_id": maxi(0, tick_id),
		"player_id": pid_safe,
		"cmd_type": cmd_safe,
		"status": "ACCEPTED" if accepted else "REJECTED",
		"reject_reason": "" if accepted else reject_reason,
		"payload_json": payload_json
	}


func _reject(
	current_tick_id: int,
	cmd_seq: int,
	player_id: String,
	cmd_type: String,
	error_code: String,
	reason: String,
	payload_dict: Dictionary
) -> Dictionary:
	var receipt: Dictionary = _build_receipt(cmd_seq, false, error_code, current_tick_id, reason)
	var audit: Dictionary = _build_audit_record(current_tick_id, player_id, cmd_type, false, error_code + ":" + reason, payload_dict)
	audit_log.append(audit)
	return {
		"accepted": false,
		"error_code": error_code,
		"reason": reason,
		"receipt": receipt,
		"envelope": payload_dict,
		"audit_record": audit
	}


func _consume_rate_token(player_id: String, current_tick_id: int) -> bool:
	var entry_var: Variant = token_buckets.get(player_id, null)
	var tokens: int = TOKEN_BUCKET_BURST
	var last_tick: int = current_tick_id
	if entry_var is Dictionary:
		var ed: Dictionary = entry_var
		tokens = _to_int(ed.get("tokens", TOKEN_BUCKET_BURST), TOKEN_BUCKET_BURST)
		last_tick = _to_int(ed.get("last_tick", current_tick_id), current_tick_id)
		var elapsed: int = maxi(0, current_tick_id - last_tick)
		if elapsed > 0:
			tokens = mini(TOKEN_BUCKET_BURST, tokens + elapsed * TOKEN_BUCKET_REFILL_PER_TICK)
			last_tick = current_tick_id
	if tokens <= 0:
		token_buckets[player_id] = {"tokens": 0, "last_tick": last_tick}
		return false
	token_buckets[player_id] = {"tokens": tokens - 1, "last_tick": last_tick}
	return true


func validate_raw_command(
	peer_id: Variant,
	raw_payload: Variant,
	server_ctx: Dictionary
) -> Dictionary:
	var current_tick_id: int = maxi(0, _to_int(server_ctx.get("current_tick_id", 0), 0))
	var env: Dictionary = {}

	# =========================================================================
	# Stage 1: Wire Safety & Schema Guard (ERR_SCHEMA)
	# =========================================================================
	if raw_payload is String:
		var raw_str: String = raw_payload
		if raw_str.to_utf8_buffer().size() > DtoSchemas.MAX_COMMAND_BYTES:
			return _reject(current_tick_id, 0, "", "", DtoSchemas.ERR_SCHEMA, "Raw command exceeds 4096 bytes", {})
		var parsed: Variant = JSON.parse_string(raw_str)
		if not (parsed is Dictionary):
			return _reject(current_tick_id, 0, "", "", DtoSchemas.ERR_SCHEMA, "Invalid JSON command object", {})
		var norm: Variant = DtoSchemas.normalize_json_ints(parsed)
		if not (norm is Dictionary):
			return _reject(current_tick_id, 0, "", "", DtoSchemas.ERR_SCHEMA, "Normalized payload is not Dictionary", {})
		var d_norm: Dictionary = norm
		env = d_norm
	elif raw_payload is Dictionary:
		var raw_d: Dictionary = raw_payload
		var norm_d: Variant = DtoSchemas.normalize_json_ints(raw_d)
		if norm_d is Dictionary:
			var d2: Dictionary = norm_d
			env = d2
		else:
			env = raw_d.duplicate(true)
	else:
		return _reject(current_tick_id, 0, "", "", DtoSchemas.ERR_SCHEMA, "Unsupported payload type", {})

	var schema_res: Dictionary = DtoSchemas.validate_command_envelope(env)
	var cmd_seq: int = maxi(0, _to_int(env.get("cmd_seq", 0), 0))
	var player_id: String = str(env.get("player_id", ""))
	var cmd_type: String = str(env.get("cmd_type", ""))
	if not _to_bool(schema_res.get("ok", false), false):
		return _reject(
			current_tick_id,
			cmd_seq,
			player_id,
			cmd_type,
			DtoSchemas.ERR_SCHEMA,
			str(schema_res.get("reason", "Schema validation failed")),
			env
		)

	if not KNOWN_COMMANDS.has(cmd_type):
		return _reject(current_tick_id, cmd_seq, player_id, cmd_type, DtoSchemas.ERR_SCHEMA, "Unknown cmd_type: " + cmd_type, env)

	var args_var: Variant = env.get("args", {})
	var args: Dictionary = args_var if args_var is Dictionary else {}

	# =========================================================================
	# Stage 2: Session Auth & Ownership Binding (ERR_UNAUTHORIZED)
	# =========================================================================
	var peer_key: String = str(peer_id)
	var session_map_var: Variant = server_ctx.get("peer_to_player", {})
	var session_map: Dictionary = session_map_var if session_map_var is Dictionary else {}
	if not session_map.has(peer_key):
		return _reject(current_tick_id, cmd_seq, player_id, cmd_type, DtoSchemas.ERR_UNAUTHORIZED, "Peer has no authenticated session", env)

	var bound_player_id: String = str(session_map.get(peer_key, ""))
	if bound_player_id.is_empty() or bound_player_id != player_id:
		return _reject(current_tick_id, cmd_seq, player_id, cmd_type, DtoSchemas.ERR_UNAUTHORIZED, "Player ID mismatch with authenticated peer", env)

	var manors_var: Variant = server_ctx.get("manors", {})
	var manors_dict: Dictionary = manors_var if manors_var is Dictionary else {}
	var expected_manor_id: String = "manor_" + player_id
	if manors_dict.has(player_id):
		var m_v: Variant = manors_dict[player_id]
		if m_v is ManorState:
			var m_st: ManorState = m_v
			expected_manor_id = m_st.manor_id

	if args.has("manor_id"):
		var arg_mid: String = str(args.get("manor_id", ""))
		if not arg_mid.is_empty() and arg_mid != expected_manor_id and cmd_type != "CMD_SUBSCRIBE_CHANNEL":
			return _reject(current_tick_id, cmd_seq, player_id, cmd_type, DtoSchemas.ERR_UNAUTHORIZED, "Cross-player manor tampering rejected", env)

	if args.has("owner_player_id"):
		var arg_owner: String = str(args.get("owner_player_id", ""))
		if not arg_owner.is_empty() and arg_owner != player_id:
			return _reject(current_tick_id, cmd_seq, player_id, cmd_type, DtoSchemas.ERR_UNAUTHORIZED, "Cross-player owner_player_id tampering rejected", env)

	if args.has("pawn_id") and cmd_type != "CMD_SOW_DISCORD" and cmd_type != "CMD_POACH_RETAINER":
		var arg_pawn: String = str(args.get("pawn_id", ""))
		if not arg_pawn.is_empty() and manors_dict.has(player_id):
			var m_v2: Variant = manors_dict[player_id]
			if m_v2 is ManorState:
				var manor_own: ManorState = m_v2
				if manor_own.get_pawn_by_id(arg_pawn) == null:
					return _reject(current_tick_id, cmd_seq, player_id, cmd_type, DtoSchemas.ERR_UNAUTHORIZED, "Pawn does not belong to player manor", env)

	# =========================================================================
	# Stage 3: Monotonic Sequence & Token-Bucket Rate Limiter (ERR_RATE_LIMITED)
	# =========================================================================
	var prev_seq: int = _to_int(last_accepted_seq.get(player_id, 0), 0)
	if cmd_seq <= prev_seq:
		return _reject(current_tick_id, cmd_seq, player_id, cmd_type, DtoSchemas.ERR_RATE_LIMITED, "Non-monotonic cmd_seq replay rejected", env)

	if not _consume_rate_token(player_id, current_tick_id):
		return _reject(current_tick_id, cmd_seq, player_id, cmd_type, DtoSchemas.ERR_RATE_LIMITED, "Command rate limit exceeded", env)

	# =========================================================================
	# Stage 4: Political Role Permission Check (ERR_ROLE_PERMISSION)
	# =========================================================================
	var fm_var: Variant = server_ctx.get("faction_manager", null)
	var faction_mgr: FactionManager = fm_var if fm_var is FactionManager else null
	var wg_var: Variant = server_ctx.get("world_graph", null)
	var world_graph: WorldGraph = wg_var if wg_var is WorldGraph else null

	var role_tier: String = "FREE_OFFICER"
	var faction_id: String = ""
	var governed_nodes: Array[String] = []
	if faction_mgr != null and faction_mgr.has_player(player_id):
		var prof: Dictionary = faction_mgr.get_player_profile(player_id)
		role_tier = str(prof.get("role_tier", "FREE_OFFICER"))
		faction_id = str(prof.get("faction_id", ""))
		var gn_var: Variant = prof.get("governed_node_ids", [])
		if gn_var is Array:
			var gna: Array = gn_var
			for item: Variant in gna:
				governed_nodes.append(str(item))

	match cmd_type:
		"CMD_SET_NODE_POLICY":
			var target_nid: String = str(args.get("node_id", ""))
			if target_nid.is_empty() or world_graph == null or not world_graph.has_node(target_nid):
				return _reject(current_tick_id, cmd_seq, player_id, cmd_type, DtoSchemas.ERR_INVALID_STATE, "Unknown target node_id", env)
			var nd: Dictionary = world_graph.get_node(target_nid)
			var node_owner: String = str(nd.get("owner_faction_id", ""))
			var node_gov: String = str(nd.get("governor_player_id", ""))
			if faction_id.is_empty() or node_owner != faction_id:
				return _reject(current_tick_id, cmd_seq, player_id, cmd_type, DtoSchemas.ERR_ROLE_PERMISSION, "Faction does not own node", env)
			if role_tier != "LORD" and node_gov != player_id and not governed_nodes.has(target_nid):
				return _reject(current_tick_id, cmd_seq, player_id, cmd_type, DtoSchemas.ERR_ROLE_PERMISSION, "Requires GOVERNOR of node or LORD", env)
		"CMD_APPOINT_GOVERNOR":
			if role_tier != "LORD" or faction_id.is_empty():
				return _reject(current_tick_id, cmd_seq, player_id, cmd_type, DtoSchemas.ERR_ROLE_PERMISSION, "Only LORD may appoint governor", env)
		"CMD_PROPOSE_OR_SIGN_TREATY", "CMD_BREAK_TREATY":
			if role_tier != "LORD" or faction_id.is_empty():
				return _reject(current_tick_id, cmd_seq, player_id, cmd_type, DtoSchemas.ERR_ROLE_PERMISSION, "Only LORD may sign or break treaties", env)
		"CMD_POST_MISSION", "CMD_FUND_INSURGENTS":
			if (role_tier != "LORD" and role_tier != "GOVERNOR") or faction_id.is_empty():
				return _reject(current_tick_id, cmd_seq, player_id, cmd_type, DtoSchemas.ERR_ROLE_PERMISSION, "Requires LORD or GOVERNOR role", env)
		"CMD_CREATE_COALITION_RALLY":
			if (role_tier != "LORD" and role_tier != "GOVERNOR") or faction_id.is_empty():
				return _reject(current_tick_id, cmd_seq, player_id, cmd_type, DtoSchemas.ERR_ROLE_PERMISSION, "Requires LORD or GOVERNOR to create coalition rally", env)
		"CMD_RAISE_UPRISING":
			if role_tier != "FREE_OFFICER":
				return _reject(current_tick_id, cmd_seq, player_id, cmd_type, DtoSchemas.ERR_ROLE_PERMISSION, "Only FREE_OFFICER may raise uprising", env)

	# =========================================================================
	# Stage 5: Resource Escrow, Sealed Persona & Domain Bounds
	# =========================================================================
	var stage5_res: Dictionary = _validate_stage5_domain(cmd_type, args, player_id, current_tick_id, server_ctx)
	if not _to_bool(stage5_res.get("ok", false), false):
		return _reject(
			current_tick_id,
			cmd_seq,
			player_id,
			cmd_type,
			str(stage5_res.get("error_code", DtoSchemas.ERR_INVALID_STATE)),
			str(stage5_res.get("reason", "Domain validation failed")),
			env
		)

	# =========================================================================
	# Stage 6: Tick Queue Commit & Audit Log (ACCEPTED)
	# =========================================================================
	last_accepted_seq[player_id] = cmd_seq
	var exec_tick_id: int = current_tick_id + 1
	var receipt: Dictionary = _build_receipt(cmd_seq, true, DtoSchemas.ERR_OK, exec_tick_id, "")
	var audit: Dictionary = _build_audit_record(exec_tick_id, player_id, cmd_type, true, "", env)
	audit_log.append(audit)

	return {
		"accepted": true,
		"error_code": DtoSchemas.ERR_OK,
		"reason": "",
		"exec_tick_id": exec_tick_id,
		"receipt": receipt,
		"envelope": env,
		"audit_record": audit
	}


func _validate_stage5_domain(
	cmd_type: String,
	args: Dictionary,
	player_id: String,
	current_tick_id: int,
	server_ctx: Dictionary
) -> Dictionary:
	var manors_var: Variant = server_ctx.get("manors", {})
	var manors_dict: Dictionary = manors_var if manors_var is Dictionary else {}
	var manor: ManorState = null
	if manors_dict.has(player_id):
		var mv: Variant = manors_dict[player_id]
		if mv is ManorState:
			manor = mv

	var wg_var: Variant = server_ctx.get("world_graph", null)
	var world_graph: WorldGraph = wg_var if wg_var is WorldGraph else null

	match cmd_type:
		"CMD_CREATE_CHARACTER":
			var mode: String = str(args.get("creation_mode", "INTERVIEW_ONLY"))
			if not DtoSchemas.CREATION_MODES.has(mode):
				return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Invalid creation_mode"}
			if mode == "FUSION_INTERVIEW" or mode == "AI_DIRECT_WITH_CONFIRM":
				var raw_token: String = str(args.get("sealed_token_input", ""))
				if raw_token.contains("{") or raw_token.contains("}") or raw_token.contains("AI_PERSONA_EXPORT_V1"):
					return {"ok": false, "error_code": DtoSchemas.ERR_PLAINTEXT_JSON_FORBIDDEN, "reason": "Plaintext JSON forbidden in sealed persona creation"}
				if raw_token.is_empty():
					return {"ok": false, "error_code": DtoSchemas.ERR_TOKEN_FORMAT, "reason": "Missing sealed_token_input"}
			return {"ok": true}

		"CMD_SET_WORK_PRIORITY":
			if manor == null:
				return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Player has no manor"}
			var domain: String = str(args.get("domain", ""))
			if not PawnEntity.WORK_DOMAINS.has(domain):
				return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Invalid work domain"}
			if not args.has("priority") or not (args["priority"] is int):
				return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "priority must be int 0..4"}
			var prio: int = _to_int(args["priority"], -1)
			if prio < 0 or prio > 4:
				return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "priority out of 0..4 bounds"}
			var pid: String = str(args.get("pawn_id", ""))
			if pid.is_empty() or manor.get_pawn_by_id(pid) == null:
				return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown pawn_id"}
			return {"ok": true}

		"CMD_SET_SCHEDULE":
			if manor == null:
				return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Player has no manor"}
			var sh_idx: int = _to_int(args.get("shichen_index", -1), -1)
			var act: String = str(args.get("activity", ""))
			if args.has("schedule") and args["schedule"] is Array:
				var sched_arr: Array = args["schedule"]
				if sched_arr.size() != 12:
					return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "schedule must have 12 entries"}
				for s_item: Variant in sched_arr:
					if not PawnEntity.SHICHEN_ACTIVITIES.has(str(s_item)):
						return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Invalid schedule activity"}
				return {"ok": true}
			if sh_idx < 0 or sh_idx >= 12 or not PawnEntity.SHICHEN_ACTIVITIES.has(act):
				return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Invalid shichen_index or activity"}
			return {"ok": true}

		"CMD_SET_DOCTRINE":
			if manor == null:
				return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Player has no manor"}
			if args.has("grid_x"):
				var gx: int = _to_int(args.get("grid_x", -1), -1)
				if gx < 0 or gx >= DtoSchemas.MANOR_GRID_SIZE:
					return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "grid_x out of 0..31 bounds"}
			if args.has("grid_y"):
				var gy: int = _to_int(args.get("grid_y", -1), -1)
				if gy < 0 or gy >= DtoSchemas.MANOR_GRID_SIZE:
					return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "grid_y out of 0..31 bounds"}
			return {"ok": true}

		"CMD_BUILD_OR_UPGRADE":
			if manor == null:
				return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Player has no manor"}
			var bid: String = str(args.get("building_id", ""))
			if not ManorState.BUILDING_IDS.has(bid):
				return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Unknown building_id"}
			var cur_lvl: int = manor.get_building_level(bid)
			if cur_lvl >= 5:
				return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Building already at max level 5"}
			if args.has("grid_x"):
				var bx: int = _to_int(args["grid_x"], -1)
				if bx < 0 or bx >= DtoSchemas.MANOR_GRID_SIZE:
					return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "grid_x out of 0..31 bounds"}
			if args.has("grid_y"):
				var by: int = _to_int(args["grid_y"], -1)
				if by < 0 or by >= DtoSchemas.MANOR_GRID_SIZE:
					return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "grid_y out of 0..31 bounds"}
			var wood_cost: int = 120 * cur_lvl
			var coin_cost: int = 180 * cur_lvl
			if manor.get_resource("WOOD") < wood_cost or manor.get_resource("COIN") < coin_cost:
				return {"ok": false, "error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE, "reason": "Insufficient WOOD or COIN for upgrade"}
			return {"ok": true}

		"CMD_PROMOTE_TROOPS":
			if manor == null or world_graph == null:
				return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Missing manor or world_graph"}
			var ut: String = str(args.get("unit_type", ""))
			var cnt: int = _to_int(args.get("count", 0), 0)
			if not WorldGraph.UNIT_TYPES.has(ut) or cnt <= 0:
				return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Invalid unit_type or count"}
			var promoted: int = world_graph.get_manor_total_promoted(manor.manor_id)
			if promoted + cnt > manor.household_troops:
				return {"ok": false, "error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE, "reason": "Insufficient household_troops"}
			var costs: Dictionary = world_graph.compute_promotion_costs(ut, cnt)
			for rk_v: Variant in costs.keys():
				var rk: String = str(rk_v)
				if manor.get_resource(rk) < _to_int(costs[rk_v], 0):
					return {"ok": false, "error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE, "reason": "Insufficient " + rk}
			return {"ok": true}

		"CMD_DISPATCH_EXPEDITION":
			if manor == null or world_graph == null:
				return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Missing manor or world_graph"}
			var unit_type: String = str(args.get("unit_type", "ARMY"))
			if unit_type != "ARMY" and unit_type != "CARAVAN":
				return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "unit_type must be ARMY or CARAVAN"}
			var troop_cnt: int = _to_int(args.get("troop_count", 0), 0)
			var grain_amt: int = _to_int(args.get("carried_grain", 0), 0)
			if troop_cnt <= 0 or troop_cnt > manor.household_troops:
				return {"ok": false, "error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE, "reason": "Insufficient household_troops"}
			if grain_amt < 0 or grain_amt > manor.get_resource("GRAIN"):
				return {"ok": false, "error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE, "reason": "Insufficient GRAIN"}
			var off_var: Variant = args.get("officer_ids", [])
			if off_var is Array:
				var off_arr: Array = off_var
				for oid_v: Variant in off_arr:
					var pawn: PawnEntity = manor.get_pawn_by_id(str(oid_v))
					if pawn == null or pawn.state != "IN_MANOR":
						return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Officer not IN_MANOR"}
			var cargo_var: Variant = args.get("cargo", {})
			if cargo_var is Dictionary:
				var cargo_d: Dictionary = cargo_var
				for ck_v: Variant in cargo_d.keys():
					var ck: String = str(ck_v)
					var amt: int = _to_int(cargo_d[ck_v], -1)
					if amt < 0 or not DtoSchemas.RESOURCE_KEYS.has(ck):
						return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Invalid cargo item"}
					var needed: int = amt + (grain_amt if ck == "GRAIN" else 0)
					if manor.get_resource(ck) < needed:
						return {"ok": false, "error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE, "reason": "Insufficient cargo resource: " + ck}
			var path_var: Variant = args.get("path_edge_ids", [])
			if not (path_var is Array):
				return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "path_edge_ids must be Array"}
			var path_arr: Array = path_var
			if path_arr.is_empty():
				return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "path_edge_ids empty"}
			var cur_node: String = WorldGraph.resolve_node_alias(manor.host_node_id, world_graph)
			for eid_v: Variant in path_arr:
				var eid: String = str(eid_v)
				if not world_graph.has_edge(eid):
					return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown graph edge: " + eid}
				var nxt: String = world_graph.get_other_endpoint(eid, cur_node)
				if nxt.is_empty():
					return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Disconnected path at edge: " + eid}
				cur_node = nxt
			return {"ok": true}

		"CMD_PLACE_MARKET_ORDER":
			if manor == null or world_graph == null:
				return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Missing manor or world_graph"}
			var raw_mkt_nid: String = str(args.get("node_id", manor.host_node_id)).strip_edges()
			var nid: String = WorldGraph.map_known_node_alias(raw_mkt_nid)
			if nid.is_empty() or not world_graph.has_node(nid):
				return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown market node_id"}
			var comm: String = str(args.get("commodity", ""))
			var side: String = str(args.get("side", ""))
			var price_bp: int = _to_int(args.get("price_bp", 0), 0)
			var qty: int = _to_int(args.get("quantity", 0), 0)
			if not DtoSchemas.MARKET_COMMODITIES.has(comm) or (side != "BID" and side != "ASK") or price_bp < 100 or price_bp > 100000 or qty <= 0:
				return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Invalid market order parameters"}
			if side == "BID":
				@warning_ignore("integer_division")
				var coin_escrow: int = maxi(1, (price_bp * qty) / 1000)
				if manor.get_resource("COIN") < coin_escrow:
					return {"ok": false, "error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE, "reason": "Insufficient COIN for BID escrow"}
			else:
				if manor.get_resource(comm) < qty:
					return {"ok": false, "error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE, "reason": "Insufficient commodity for ASK escrow"}
			return {"ok": true}

		"CMD_CANCEL_MARKET_ORDER":
			var oid: String = str(args.get("order_id", ""))
			if oid.is_empty():
				return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Missing order_id"}
			var rm_var: Variant = server_ctx.get("regional_market", null)
			if rm_var is RegionalMarket:
				var rm: RegionalMarket = rm_var
				var ord: Dictionary = rm.get_order(oid)
				if ord.is_empty() or str(ord.get("status", "")) != "OPEN":
					return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Order not OPEN"}
				if str(ord.get("player_id", "")) != player_id:
					return {"ok": false, "error_code": DtoSchemas.ERR_UNAUTHORIZED, "reason": "Cannot cancel another player's order"}
			return {"ok": true}

		"CMD_SET_NODE_POLICY":
			var tax_bp: int = _to_int(args.get("tax_rate_bp", -1), -1)
			var def_budget: int = _to_int(args.get("defense_budget", 0), 0)
			if tax_bp < 500 or tax_bp > 2500 or def_budget < 0:
				return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "tax_rate_bp must be 500..2500 and defense_budget >= 0"}
			return {"ok": true}

		"CMD_RAISE_UPRISING":
			if manor == null:
				return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Player has no manor"}
			if manor.household_troops < EspionageService.UPRISING_MIN_TROOPS:
				return {"ok": false, "error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE, "reason": "Requires >= 2000 household_troops"}
			if manor.get_resource("COIN") < EspionageService.UPRISING_COIN_COST:
				return {"ok": false, "error_code": DtoSchemas.ERR_INSUFFICIENT_RESOURCE, "reason": "Requires >= 5000 COIN"}
			return {"ok": true}

		"CMD_DECIDE_INBOX_EVENT":
			var did: String = str(args.get("decision_id", ""))
			var choice: String = str(args.get("chosen_option", ""))
			if did.is_empty() or choice.is_empty():
				return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Missing decision_id or chosen_option"}
			var cis_var: Variant = server_ctx.get("chronicle_inbox", null)
			if cis_var is ChronicleInboxService:
				var cis: ChronicleInboxService = cis_var
				var dec: Dictionary = cis.get_decision(did)
				if dec.is_empty():
					return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown decision_id"}
				if str(dec.get("player_id", "")) != player_id:
					return {"ok": false, "error_code": DtoSchemas.ERR_UNAUTHORIZED, "reason": "Decision belongs to another player"}
				if str(dec.get("status", "")) != "PENDING":
					return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Decision already resolved"}
				var opts_var: Variant = dec.get("options", [])
				if opts_var is Array:
					var opts: Array = opts_var
					var found: bool = false
					for o: Variant in opts:
						if str(o) == choice:
							found = true
							break
					if not found:
						return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Invalid chosen_option"}
			return {"ok": true}

		"CMD_SUBSCRIBE_CHANNEL":
			var chan: String = str(args.get("channel", ""))
			if chan.is_empty():
				return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Missing channel"}
			if chan != DtoSchemas.CHAN_GLOBAL_MACRO and not chan.begins_with(DtoSchemas.CHAN_FACTION + ":") and not chan.begins_with(DtoSchemas.CHAN_NODE + ":") and not chan.begins_with(DtoSchemas.CHAN_MANOR + ":"):
				return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Invalid channel format"}
			return {"ok": true}

		_:
			var _unused_t: int = current_tick_id
			return {"ok": true}


func to_dict() -> Dictionary:
	var seq_copy: Dictionary = {}
	var pkeys: Array[String] = []
	for k: Variant in last_accepted_seq.keys():
		pkeys.append(str(k))
	pkeys.sort()
	for pk: String in pkeys:
		seq_copy[pk] = _to_int(last_accepted_seq[pk], 0)

	var tb_copy: Dictionary = {}
	var tkeys: Array[String] = []
	for k: Variant in token_buckets.keys():
		tkeys.append(str(k))
	tkeys.sort()
	for tk: String in tkeys:
		var tv: Variant = token_buckets[tk]
		if tv is Dictionary:
			var td: Dictionary = tv
			tb_copy[tk] = td.duplicate(true)

	var audit_copy: Array[Dictionary] = []
	for entry: Dictionary in audit_log:
		audit_copy.append(entry.duplicate(true))

	return {
		"last_accepted_seq": seq_copy,
		"token_buckets": tb_copy,
		"audit_log": audit_copy
	}


static func from_dict(data: Dictionary) -> CommandValidator:
	var cv: CommandValidator = CommandValidator.new()
	var seq_v: Variant = data.get("last_accepted_seq", {})
	if seq_v is Dictionary:
		var sd: Dictionary = seq_v
		for k: Variant in sd.keys():
			cv.last_accepted_seq[str(k)] = maxi(0, _to_int(sd[k], 0))

	var tb_v: Variant = data.get("token_buckets", {})
	if tb_v is Dictionary:
		var tbd: Dictionary = tb_v
		for k: Variant in tbd.keys():
			var ev: Variant = tbd[k]
			if ev is Dictionary:
				var ed: Dictionary = ev
				cv.token_buckets[str(k)] = {
					"tokens": clampi(_to_int(ed.get("tokens", TOKEN_BUCKET_BURST), TOKEN_BUCKET_BURST), 0, TOKEN_BUCKET_BURST),
					"last_tick": maxi(0, _to_int(ed.get("last_tick", 0), 0))
				}

	var al_v: Variant = data.get("audit_log", [])
	if al_v is Array:
		var ala: Array = al_v
		for item: Variant in ala:
			if item is Dictionary:
				var d: Dictionary = item
				cv.audit_log.append(d.duplicate(true))
	return cv
