class_name HeadlessServerMain
extends Node

@export var auto_start_on_ready: bool = true
@export var persist_enabled: bool = true

var port: int = 9090
var bind_address: String = "127.0.0.1"
var db_path: String = "saves/world_state.db"
var wal_path: String = "saves/wal_commands.jsonl"
var snapshot_path: String = "saves/world_snapshot.json"
var world_seed: int = 18401
var tick_interval_sec: float = 1.0
var snapshot_interval_ticks: int = 24
var quit_after_ticks: int = 0

var server: AuthoritativeServer = null
var wal_logger: WALLogger = null
var _is_started: bool = false
var _tick_accum_sec: float = 0.0
var _ticks_executed: int = 0
var _last_checkpoint_tick: int = -1
var _wal_write_count: int = 0
var _checkpoint_count: int = 0
var _errors: Array[String] = []


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


static func _as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		var d: Dictionary = v
		return d
	return {}


static func _as_array(v: Variant) -> Array:
	if v is Array:
		var a: Array = v
		return a
	return []


func configure(opts: Dictionary) -> void:
	if opts.has("port"):
		port = clampi(_to_int(opts["port"], port), 1, 65535)
	if opts.has("bind"):
		bind_address = str(opts["bind"])
	if opts.has("db"):
		db_path = str(opts["db"])
	if opts.has("wal"):
		wal_path = str(opts["wal"])
	if opts.has("snapshot"):
		snapshot_path = str(opts["snapshot"])
	if opts.has("seed"):
		world_seed = _to_int(opts["seed"], world_seed)
	if opts.has("tick_sec"):
		var ts_v: Variant = opts["tick_sec"]
		if ts_v is float:
			var ts_f: float = ts_v
			tick_interval_sec = maxf(0.05, ts_f)
		elif ts_v is int:
			var ts_i: int = ts_v
			tick_interval_sec = maxf(0.05, float(ts_i))
	if opts.has("snapshot_interval"):
		snapshot_interval_ticks = maxi(1, _to_int(opts["snapshot_interval"], snapshot_interval_ticks))
	if opts.has("quit_after_ticks"):
		quit_after_ticks = maxi(0, _to_int(opts["quit_after_ticks"], quit_after_ticks))
	if opts.has("persist_enabled"):
		persist_enabled = _to_bool(opts["persist_enabled"], persist_enabled)


func parse_cli_args_list(raw_args: PackedStringArray) -> Dictionary:
	var opts: Dictionary = {}
	for raw_arg: String in raw_args:
		if raw_arg.begins_with("--port="):
			var v_str: String = raw_arg.substr("--port=".length()).strip_edges()
			if v_str.is_valid_int():
				var p_val: int = v_str.to_int()
				if p_val >= 1 and p_val <= 65535:
					opts["port"] = p_val
				else:
					push_warning("[headless_server] Invalid --port range (%s); keeping default %d" % [v_str, port])
			else:
				push_warning("[headless_server] Invalid --port value (%s); keeping default %d" % [v_str, port])
		elif raw_arg.begins_with("--bind="):
			opts["bind"] = raw_arg.substr("--bind=".length())
		elif raw_arg.begins_with("--db="):
			opts["db"] = raw_arg.substr("--db=".length())
		elif raw_arg.begins_with("--wal="):
			opts["wal"] = raw_arg.substr("--wal=".length())
		elif raw_arg.begins_with("--snapshot="):
			opts["snapshot"] = raw_arg.substr("--snapshot=".length())
		elif raw_arg.begins_with("--seed="):
			var s_str: String = raw_arg.substr("--seed=".length()).strip_edges()
			if s_str.is_valid_int():
				opts["seed"] = s_str.to_int()
			else:
				push_warning("[headless_server] Invalid --seed value (%s); keeping default %d" % [s_str, world_seed])
		elif raw_arg.begins_with("--tick-sec="):
			var t_str: String = raw_arg.substr("--tick-sec=".length()).strip_edges()
			if t_str.is_valid_float():
				var t_val: float = t_str.to_float()
				if t_val > 0.0:
					opts["tick_sec"] = t_val
				else:
					push_warning("[headless_server] Invalid --tick-sec range (%s); keeping default %.2f" % [t_str, tick_interval_sec])
			else:
				push_warning("[headless_server] Invalid --tick-sec value (%s); keeping default %.2f" % [t_str, tick_interval_sec])
		elif raw_arg.begins_with("--snapshot-interval="):
			var si_str: String = raw_arg.substr("--snapshot-interval=".length()).strip_edges()
			if si_str.is_valid_int() and si_str.to_int() >= 1:
				opts["snapshot_interval"] = si_str.to_int()
			else:
				push_warning("[headless_server] Invalid --snapshot-interval value (%s); keeping default %d" % [si_str, snapshot_interval_ticks])
		elif raw_arg.begins_with("--quit-after-ticks="):
			var q_str: String = raw_arg.substr("--quit-after-ticks=".length()).strip_edges()
			if q_str.is_valid_int() and q_str.to_int() >= 0:
				opts["quit_after_ticks"] = q_str.to_int()
			else:
				push_warning("[headless_server] Invalid --quit-after-ticks value (%s); keeping default %d" % [q_str, quit_after_ticks])
		elif raw_arg == "--no-persist":
			opts["persist_enabled"] = false
	return opts


func _parse_cli_args() -> Dictionary:
	return parse_cli_args_list(OS.get_cmdline_user_args())


func _is_scene_entrypoint() -> bool:
	if not auto_start_on_ready:
		return false
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	return scene_file_path == "res://scenes/headless_server.tscn" or tree.current_scene == self


func _ready() -> void:
	if _is_scene_entrypoint():
		configure(_parse_cli_args())
		var err: Error = start_server()
		if err != OK:
			printerr("[headless_server] Failed to start on %s:%d (err=%d)" % [bind_address, port, int(err)])
			var tree: SceneTree = get_tree()
			if tree != null:
				tree.quit(1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop_server()


func _exit_tree() -> void:
	stop_server()


func _ensure_parent_dir(path_str: String) -> void:
	if path_str.is_empty():
		return
	var resolved: String = WALLogger.resolve_path(path_str)
	var pdir: String = resolved.get_base_dir()
	if not pdir.is_empty():
		var _mk: Error = DirAccess.make_dir_recursive_absolute(pdir)


func start_server() -> Error:
	if _is_started:
		stop_server()
	_errors.clear()
	_tick_accum_sec = 0.0
	_ticks_executed = 0
	_last_checkpoint_tick = -1

	if persist_enabled:
		_ensure_parent_dir(db_path)
		_ensure_parent_dir(wal_path)
		_ensure_parent_dir(snapshot_path)

		var resolved_snap: String = SnapshotSerializer.resolve_path(snapshot_path)
		var resolved_wal: String = WALLogger.resolve_path(wal_path)
		if FileAccess.file_exists(resolved_snap) or FileAccess.file_exists(resolved_wal):
			var rec_res: Dictionary = SnapshotSerializer.load_for_crash_recovery(snapshot_path, wal_path)
			if _to_bool(rec_res.get("ok", false), false):
				var has_snap: bool = _to_bool(rec_res.get("has_snapshot", false), false)
				var ws: Dictionary = _as_dict(rec_res.get("world_state", {}))
				if has_snap and not ws.is_empty():
					server = AuthoritativeServer.from_dict(ws)
				else:
					server = AuthoritativeServer.new(world_seed, "ST_SIMA_QIAN")

				var replays_raw: Array = _as_array(rec_res.get("replay_records", []))
				var replays: Array[Dictionary] = []
				for rep_v: Variant in replays_raw:
					var rep_d: Dictionary = _as_dict(rep_v)
					if not rep_d.is_empty():
						replays.append(rep_d)
				replays.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
					var ta: int = _to_int(a.get("tick_id", 0), 0)
					var tb: int = _to_int(b.get("tick_id", 0), 0)
					if ta != tb:
						return ta < tb
					return _to_int(a.get("cmd_seq", 0), 0) < _to_int(b.get("cmd_seq", 0), 0)
				)

				var had_replayed_cmds: bool = false
				for rep: Dictionary in replays:
					var rep_pid: String = str(rep.get("player_id", ""))
					var rep_seq: int = _to_int(rep.get("cmd_seq", 0), 0)
					if rep_pid.is_empty():
						continue
					var prev_seq: int = _to_int(server.command_validator.last_accepted_seq.get(rep_pid, 0), 0)
					if rep_seq <= prev_seq:
						continue
					var exec_tick: int = maxi(1, _to_int(rep.get("tick_id", 1), 1))
					while server.clock.current_tick_id < exec_tick - 1:
						var _st: Dictionary = server.step_micro_tick()
					var rep_pkey: String = str(server.peer_by_player.get(rep_pid, "replay_" + rep_pid))
					if rep_pkey.is_empty():
						rep_pkey = "replay_" + rep_pid
					if not server.sessions_by_peer.has(rep_pkey):
						var _rs: Dictionary = server.register_session(rep_pkey, rep_pid, rep_pid)
					var rep_env: Dictionary = {
						"v": 1,
						"cmd_seq": rep_seq,
						"client_tick": maxi(0, exec_tick - 1),
						"player_id": rep_pid,
						"cmd_type": str(rep.get("cmd_type", "")),
						"args": _as_dict(rep.get("payload", {}))
					}
					var _sub_r: Dictionary = server.submit_raw_command(rep_pkey, rep_env)
					had_replayed_cmds = true

				if had_replayed_cmds or not server._pending_commands.is_empty():
					var _final_st: Dictionary = server.step_micro_tick()
			else:
				_errors.append("Crash recovery warning: " + str(rec_res.get("reason", "")))

	if server == null:
		server = AuthoritativeServer.new(world_seed, "ST_SIMA_QIAN")

	# Clear stale ws_* and replay_* peer keys left from a recovered snapshot/WAL before binding new TCP socket
	var stale_peers: Array[String] = []
	for pk_v: Variant in server.sessions_by_peer.keys():
		var pk_s: String = str(pk_v)
		if pk_s.begins_with("ws_") or pk_s.begins_with("replay_"):
			stale_peers.append(pk_s)
	for spk: String in stale_peers:
		var spid: String = str(server.sessions_by_peer[spk])
		var _es: bool = server.sessions_by_peer.erase(spk)
		if not spid.is_empty() and str(server.peer_by_player.get(spid, "")) == spk:
			var _ep: bool = server.peer_by_player.erase(spid)
		server.interest_manager.unregister_peer(spk)
	for pid_k: Variant in server.player_accounts.keys():
		var acct_v: Variant = server.player_accounts[pid_k]
		if acct_v is Dictionary:
			var acct: Dictionary = acct_v
			acct["is_online"] = 0
	server._sync_all_manor_lods()

	if persist_enabled:
		wal_logger = WALLogger.new()
		var wal_res: Dictionary = wal_logger.open_wal(wal_path)
		if not _to_bool(wal_res.get("ok", false), false):
			_errors.append("WAL open failed: " + str(wal_res.get("reason", "")))
		var resolved_db: String = SQLiteBridge.resolve_path(db_path)
		if not resolved_db.is_empty() and not FileAccess.file_exists(resolved_db):
			var init_res: Dictionary = SQLiteBridge.init_database(db_path)
			if not _to_bool(init_res.get("ok", false), false):
				_errors.append("SQLite init failed: " + str(init_res.get("reason", "")))
		server.attach_persistence_handlers(
			Callable(self, "_on_wal_record"),
			Callable(self, "_on_daily_checkpoint")
		)

	var listen_err: Error = server.transport.listen_websocket(port, bind_address)
	if listen_err != OK:
		return listen_err

	_is_started = true
	print("[headless_server] Listening on ws://%s:%d (seed=%d, tick_sec=%.2f)" % [bind_address, port, world_seed, tick_interval_sec])
	return OK


func stop_server() -> void:
	if not _is_started:
		return
	_is_started = false
	if server != null:
		if persist_enabled:
			flush_persistence()
		if server.transport != null:
			server.transport.close()
	wal_logger = null


func flush_persistence() -> void:
	if server == null or not persist_enabled:
		return
	if not snapshot_path.is_empty():
		var snap_res: Dictionary = SnapshotSerializer.save_atomic_snapshot(snapshot_path, server.to_dict())
		if not _to_bool(snap_res.get("ok", false), false):
			_errors.append("Snapshot save failed: " + str(snap_res.get("reason", "")))
	if not db_path.is_empty():
		var sql_res: Dictionary = SQLiteBridge.sync_world_checkpoint(db_path, _export_server_relational_snapshot(server))
		if not _to_bool(sql_res.get("ok", false), false):
			_errors.append("SQLite checkpoint failed: " + str(sql_res.get("reason", "")))
	_last_checkpoint_tick = server.clock.current_tick_id
	_checkpoint_count += 1


func _on_wal_record(rec: Dictionary) -> void:
	if wal_logger == null or not wal_logger.is_open():
		return
	var payload_d: Dictionary = _as_dict(rec.get("payload", {}))
	var res: Dictionary = wal_logger.append_record(
		_to_int(rec.get("tick_id", 0), 0),
		_to_int(rec.get("cmd_seq", 0), 0),
		str(rec.get("player_id", "")),
		str(rec.get("cmd_type", "")),
		payload_d
	)
	if _to_bool(res.get("ok", false), false):
		_wal_write_count += 1
	else:
		_errors.append("WAL append failed: " + str(res.get("reason", "")))


func _on_daily_checkpoint(srv: AuthoritativeServer) -> void:
	if srv == server:
		flush_persistence()


static func _export_server_relational_snapshot(srv: AuthoritativeServer) -> Dictionary:
	var rel: Dictionary = srv.export_relational_snapshot()
	var wm_arr: Array = _as_array(rel.get("world_meta", []))
	if not wm_arr.is_empty():
		var wm0: Dictionary = _as_dict(wm_arr[0])
		if not wm0.is_empty():
			rel["world_meta"] = wm0
			rel["world_id"] = wm0.get("world_id", srv.world_id)
			rel["world_seed"] = wm0.get("world_seed", srv.world_seed)
			rel["current_tick_id"] = wm0.get("current_tick_id", srv.clock.current_tick_id)
			rel["current_day_id"] = wm0.get("current_day_id", srv.clock.get_day_id())
			rel["season"] = wm0.get("season", srv.clock.get_season())
			rel["storyteller_id"] = wm0.get("storyteller_id", "SIMA_QIAN")
			rel["state_crc32"] = wm0.get("state_crc32", srv.state_crc32)
	return rel


func _cleanup_disconnected_peers() -> void:
	if server == null:
		return
	var disconnected: Array[String] = []
	for pkey_v: Variant in server.sessions_by_peer.keys():
		var pkey: String = str(pkey_v)
		if pkey.begins_with("ws_") and not server.transport.has_peer(pkey):
			disconnected.append(pkey)
	for pkey: String in disconnected:
		var pid: String = str(server.sessions_by_peer.get(pkey, ""))
		var is_active_owner: bool = not pid.is_empty() and str(server.peer_by_player.get(pid, "")) == pkey
		if is_active_owner and server.player_accounts.has(pid):
			var _off: Dictionary = server.set_player_online(pid, false)
		var _es: bool = server.sessions_by_peer.erase(pkey)
		if is_active_owner:
			var _ep: bool = server.peer_by_player.erase(pid)
		server.interest_manager.unregister_peer(pkey)


func _send_initial_delta_to_peer(pkey: String) -> void:
	if server == null:
		return
	server.interest_manager.reset_peer_cache(pkey)
	var srv_state: Dictionary = {
		"clock": server.clock,
		"state_crc32": server.state_crc32,
		"world_graph": server.world_graph,
		"army_manager": server.army_manager,
		"regional_market": server.regional_market,
		"faction_manager": server.faction_manager,
		"diplomacy": server.diplomacy_engine,
		"siege_resolver": server.siege_resolver,
		"manors": server.manors
	}
	var delta_msg: Dictionary = server.interest_manager.build_tick_delta_for_peer(pkey, srv_state, [])
	var _ok: bool = server.transport.server_send_to_peer(pkey, delta_msg)


func _send_ws_welcome(pkey: String, pid: String) -> void:
	if server == null:
		return
	var welcome: Dictionary = {
		"v": 1,
		"msg_type": "MSG_WS_WELCOME",
		"player_id": pid,
		"last_accepted_seq": _to_int(server.command_validator.last_accepted_seq.get(pid, 0), 0),
		"tick_id": server.clock.current_tick_id
	}
	var _ok: bool = server.transport.server_send_to_peer(pkey, welcome)


func _reject_duplicate_login(pkey: String, cmd_seq_val: int) -> void:
	if server == null:
		return
	var reject_receipt: Dictionary = {
		"v": 1,
		"msg_type": DtoSchemas.MSG_CMD_RECEIPT,
		"cmd_seq": cmd_seq_val,
		"status": "REJECTED",
		"error_code": DtoSchemas.ERR_UNAUTHORIZED,
		"exec_tick_id": server.clock.current_tick_id,
		"reason": "Player ID already active on another peer"
	}
	var _sent_r: bool = server.transport.server_send_to_peer(pkey, reject_receipt)


func pump_network() -> void:
	if not _is_started or server == null:
		return
	server.transport.poll()
	_cleanup_disconnected_peers()

	var packets: Array[Dictionary] = server.transport.server_drain_incoming()
	for pkt: Dictionary in packets:
		var pkey: String = str(pkt.get("peer_id", pkt.get("peer_key", "")))
		var raw_utf8: String = str(pkt.get("raw_utf8", ""))
		if pkey.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(raw_utf8)
		var pd: Dictionary = _as_dict(parsed)
		var msg_type: String = str(pd.get("msg_type", ""))

		var newly_bound: bool = false
		var bound_pid: String = ""
		if not server.sessions_by_peer.has(pkey):
			var candidate_pid: String = str(pd.get("player_id", ""))
			if not candidate_pid.is_empty():
				var existing_pkey: String = str(server.peer_by_player.get(candidate_pid, ""))
				if not existing_pkey.is_empty() and existing_pkey != pkey and server.transport.has_peer(existing_pkey):
					_reject_duplicate_login(pkey, _to_int(pd.get("cmd_seq", 0), 0))
					continue
				if not existing_pkey.is_empty() and existing_pkey != pkey:
					var _er_old: bool = server.sessions_by_peer.erase(existing_pkey)
					server.interest_manager.unregister_peer(existing_pkey)

				var was_offline: bool = false
				var from_tick: int = server.clock.current_tick_id
				var prev_resources: Dictionary = {}
				if server.player_accounts.has(candidate_pid):
					var acct: Dictionary = _as_dict(server.player_accounts[candidate_pid])
					was_offline = _to_int(acct.get("is_online", 0), 0) == 0
					from_tick = _to_int(acct.get("last_seen_tick", server.clock.current_tick_id), server.clock.current_tick_id)
					if server.manors.has(candidate_pid):
						var mv: Variant = server.manors[candidate_pid]
						if mv is ManorState:
							var m: ManorState = mv
							prev_resources = m.resources.duplicate(true)

				var disp_name: String = str(pd.get("display_name", candidate_pid))
				if disp_name.is_empty():
					disp_name = candidate_pid
				var _reg: Dictionary = server.register_session(pkey, candidate_pid, disp_name)
				newly_bound = true
				bound_pid = candidate_pid
				if was_offline:
					var gazette: Dictionary = server.chronicle_inbox.build_reconnect_gazette(
						candidate_pid, from_tick, server.clock.current_tick_id, prev_resources
					)
					var _sent_g: bool = server.transport.server_send_to_peer(pkey, gazette)
		else:
			bound_pid = str(server.sessions_by_peer.get(pkey, ""))

		if msg_type == "MSG_WS_HELLO":
			if not bound_pid.is_empty():
				_send_ws_welcome(pkey, bound_pid)
				_send_initial_delta_to_peer(pkey)
			continue

		var _sub_res: Dictionary = server.submit_raw_command(pkey, raw_utf8)
		if newly_bound:
			_send_ws_welcome(pkey, bound_pid)
			_send_initial_delta_to_peer(pkey)
	server.transport.poll()


func step_server_tick() -> Dictionary:
	if not _is_started or server == null:
		return {}
	pump_network()
	var step_res: Dictionary = server.step_micro_tick()
	_ticks_executed += 1
	var cur_tick: int = _to_int(step_res.get("tick_id", server.clock.current_tick_id), server.clock.current_tick_id)
	if persist_enabled and snapshot_interval_ticks > 0 and (cur_tick % snapshot_interval_ticks == 0) and cur_tick != _last_checkpoint_tick:
		flush_persistence()
	server.transport.poll()
	return step_res


func _process(delta: float) -> void:
	if not _is_started or server == null:
		return
	pump_network()
	_tick_accum_sec += maxf(0.0, delta)
	var max_steps: int = 4
	var stepped: int = 0
	while _tick_accum_sec >= tick_interval_sec and stepped < max_steps:
		_tick_accum_sec -= tick_interval_sec
		var _res: Dictionary = step_server_tick()
		stepped += 1
		if quit_after_ticks > 0 and _ticks_executed >= quit_after_ticks:
			stop_server()
			var tree: SceneTree = get_tree()
			if tree != null:
				tree.quit(0)
			return
