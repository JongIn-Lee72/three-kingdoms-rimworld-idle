extends SceneTree

const DEFAULT_EQUIV_TICKS: int = 3600


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
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var world_seed: int = 18401
	var scenario_path: String = ""
	var ticks: int = 10000
	var checkpoint_interval: int = 1000
	var verify_determinism: bool = false
	var verify_offline_equiv: bool = false
	var out_path: String = "reports/sim_snapshot_18401.json"

	for arg: String in args:
		if arg.begins_with("--seed="):
			world_seed = arg.substr(7).to_int()
		elif arg.begins_with("--scenario="):
			scenario_path = arg.substr(11)
		elif arg.begins_with("--ticks="):
			ticks = maxi(1, arg.substr(8).to_int())
		elif arg.begins_with("--checkpoint-interval="):
			checkpoint_interval = maxi(1, arg.substr(22).to_int())
		elif arg == "--verify-determinism":
			verify_determinism = true
		elif arg == "--verify-offline-equivalence":
			verify_offline_equiv = true
		elif arg.begins_with("--out="):
			out_path = arg.substr(6)

	var scenario: Dictionary = _load_scenario(scenario_path, world_seed)
	var errors: Array[String] = []

	var run1: Dictionary = _run_simulation(world_seed, scenario, ticks, checkpoint_interval, 0, errors)
	var final_hash_1: String = str(run1.get("final_sha256", ""))
	var final_crc_1: int = _to_int(run1.get("final_crc32", 0), 0)

	var determinism_ok: bool = true
	if verify_determinism:
		var run2: Dictionary = _run_simulation(world_seed, scenario, ticks, checkpoint_interval, 0, errors)
		var final_hash_2: String = str(run2.get("final_sha256", ""))
		var final_crc_2: int = _to_int(run2.get("final_crc32", 0), 0)
		if final_hash_1 != final_hash_2 or final_crc_1 != final_crc_2:
			determinism_ok = false
			errors.append("Determinism failure: final hash mismatch (%s != %s)" % [final_hash_1, final_hash_2])

		var cps1_var: Variant = run1.get("checkpoints", [])
		var cps2_var: Variant = run2.get("checkpoints", [])
		if cps1_var is Array and cps2_var is Array:
			var cps1: Array = cps1_var
			var cps2: Array = cps2_var
			if cps1.size() != cps2.size():
				determinism_ok = false
				errors.append("Determinism failure: checkpoint count mismatch")
			else:
				for idx: int in range(cps1.size()):
					var c1_var: Variant = cps1[idx]
					var c2_var: Variant = cps2[idx]
					if c1_var is Dictionary and c2_var is Dictionary:
						var c1: Dictionary = c1_var
						var c2: Dictionary = c2_var
						if str(c1.get("sha256", "")) != str(c2.get("sha256", "")):
							determinism_ok = false
							errors.append("Determinism failure at checkpoint tick %d" % _to_int(c1.get("tick_id", 0), 0))

	var equiv_report: Dictionary = {"checked": false, "passed": true}
	if verify_offline_equiv:
		equiv_report = _verify_lod0_vs_lod1(world_seed, scenario, DEFAULT_EQUIV_TICKS, errors)

	# INV-JOB-PROGRESS & INV-WORLD-CONSERVATION check on primary run
	var manor1_var: Variant = run1.get("manor_obj", null)
	if manor1_var is ManorState:
		var m1: ManorState = manor1_var
		if m1.jobs_completed <= 0:
			errors.append("INV-JOB-PROGRESS failed: jobs_completed <= 0")
		_verify_conservation_dispatch(m1, world_seed, errors)
	else:
		errors.append("Internal error: missing primary ManorState")

	var snapshot_out: Dictionary = {
		"schema_version": "1.0",
		"seed": world_seed,
		"ticks": ticks,
		"checkpoint_interval": checkpoint_interval,
		"determinism_verified": verify_determinism and determinism_ok,
		"offline_equivalence": equiv_report,
		"final_crc32": final_crc_1,
		"final_sha256": final_hash_1,
		"checkpoints": run1.get("checkpoints", []),
		"final_manor_state": run1.get("final_state", {}),
		"errors": errors
	}
	_write_json_report(out_path, snapshot_out)

	if errors.is_empty():
		print("[sim_harness] PASS seed=%d ticks=%d crc32=%d jobs=%s equiv_ok=%s" % [
			world_seed, ticks, final_crc_1, str(run1.get("jobs_completed", 0)), str(equiv_report.get("passed", true))
		])
		quit(0)
	else:
		for e: String in errors:
			printerr("[sim_harness] ERROR: " + e)
		quit(1)


func _load_scenario(path: String, world_seed: int) -> Dictionary:
	if not path.is_empty() and FileAccess.file_exists(path):
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f != null:
			var txt: String = f.get_as_text()
			f.close()
			var parsed: Variant = JSON.parse_string(txt)
			if parsed is Dictionary:
				var norm: Variant = DtoSchemas.normalize_json_ints(parsed)
				if norm is Dictionary:
					var d: Dictionary = norm
					return d
	return {
		"player_id": "sim_player_01",
		"avatar_name": "Sim_Warlord",
		"creation_mode": "INTERVIEW_ONLY",
		"interview_answers": [
			world_seed % 4,
			(world_seed / 3) % 4,
			(world_seed / 5) % 4,
			(world_seed / 7) % 4,
			(world_seed / 11) % 4,
			(world_seed / 13) % 4,
			(world_seed / 17) % 4,
			(world_seed / 19) % 4
		],
		"origin_override": "ORIGIN_AGRARIAN_GENTRY",
		"province_override": "YU_ZHOU"
	}


func _build_initial_manor(world_seed: int, scenario: Dictionary, lod: int) -> ManorState:
	var challenge_store: Dictionary = {}
	var cooldowns: Dictionary = {}
	var strikes: Dictionary = {}
	var created: Dictionary = CharacterCreationEngine.create_character_and_manor(
		scenario, challenge_store, cooldowns, strikes, world_seed, 0
	)
	var m_var: Variant = created.get("manor", null)
	var manor: ManorState = m_var if m_var is ManorState else ManorState.new("manor_sim", "sim_player_01")
	manor.current_lod = lod
	if manor.pawns.is_empty():
		var av: PawnEntity = PawnEntity.new("sim_av", "Sim_Hero", true)
		var _ok: bool = manor.add_pawn(av)
	return manor


func _check_invariants(manor: ManorState, tick_id: int, errors: Array[String]) -> void:
	for p: PawnEntity in manor.pawns:
		for nk: String in PawnEntity.NEED_KEYS:
			var nv: int = p.get_need(nk)
			if nv < 0 or nv > 10000:
				errors.append("INV-PAWN-BOUNDS: %s.%s=%d out of [0,10000] at tick %d" % [p.pawn_id, nk, nv, tick_id])
		if p.mood < 0 or p.mood > 100:
			errors.append("INV-PAWN-BOUNDS: %s.mood=%d out of [0,100] at tick %d" % [p.pawn_id, p.mood, tick_id])
		for sk: String in PawnEntity.STAT_KEYS:
			var sv: int = p.get_stat(sk)
			if sv < 1 or sv > 120:
				errors.append("INV-PAWN-BOUNDS: %s.%s=%d out of [1,120] at tick %d" % [p.pawn_id, sk, sv, tick_id])

	for rk: String in DtoSchemas.RESOURCE_KEYS:
		var rv: int = manor.get_resource(rk)
		if rv < 0:
			errors.append("INV-RESOURCE-NONNEG: %s=%d < 0 at tick %d" % [rk, rv, tick_id])


func _run_simulation(
	world_seed: int,
	scenario: Dictionary,
	ticks: int,
	checkpoint_interval: int,
	lod: int,
	errors: Array[String]
) -> Dictionary:
	var manor: ManorState = _build_initial_manor(world_seed, scenario, lod)
	var clock: SimClock = SimClock.new(0)
	var event_bus: SimEventBus = SimEventBus.new()
	var checkpoints: Array[Dictionary] = []

	for _t: int in range(ticks):
		var cur_tick: int = clock.step_micro()
		if manor.current_lod == 0:
			ManorSimulator.step_lod0_micro_tick(manor, clock, world_seed, event_bus)
		elif clock.is_macro_tick():
			ManorSimulator.step_lod1_macro_tick(manor, clock, world_seed, event_bus)

		if (cur_tick % 50) == 0 or cur_tick == ticks:
			_check_invariants(manor, cur_tick, errors)

		if (cur_tick % checkpoint_interval) == 0 or cur_tick == ticks:
			var snap: Dictionary = manor.to_dict()
			if not StateHasher.validate_deterministic_types(snap):
				errors.append("Non-deterministic type in manor.to_dict() at tick %d" % cur_tick)
			checkpoints.append({
				"tick_id": cur_tick,
				"crc32": StateHasher.crc32_dict(snap),
				"sha256": StateHasher.sha256_dict(snap),
				"jobs_completed": manor.jobs_completed,
				"grain": manor.get_resource("GRAIN"),
				"coin": manor.get_resource("COIN")
			})

	var final_dict: Dictionary = manor.to_dict()
	return {
		"manor_obj": manor,
		"final_state": final_dict,
		"final_crc32": StateHasher.crc32_dict(final_dict),
		"final_sha256": StateHasher.sha256_dict(final_dict),
		"jobs_completed": manor.jobs_completed,
		"checkpoints": checkpoints
	}


func _verify_lod0_vs_lod1(
	world_seed: int,
	scenario: Dictionary,
	equiv_ticks: int,
	errors: Array[String]
) -> Dictionary:
	var run_lod0: Dictionary = _run_simulation(world_seed, scenario, equiv_ticks, equiv_ticks, 0, errors)
	var run_lod1: Dictionary = _run_simulation(world_seed, scenario, equiv_ticks, equiv_ticks, 1, errors)
	var m0_var: Variant = run_lod0.get("manor_obj", null)
	var m1_var: Variant = run_lod1.get("manor_obj", null)
	if not (m0_var is ManorState) or not (m1_var is ManorState):
		errors.append("LOD equivalence failed: missing ManorState")
		return {"checked": true, "passed": false}

	var m0: ManorState = m0_var
	var m1: ManorState = m1_var
	var g0: int = m0.get_resource("GRAIN")
	var g1: int = m1.get_resource("GRAIN")
	var j0: int = m0.jobs_completed
	var j1: int = m1.jobs_completed

	var max_g: int = maxi(1, maxi(g0, g1))
	var grain_diff_bp: int = (abs(g0 - g1) * 10000) / max_g
	var max_j: int = maxi(1, maxi(j0, j1))
	var jobs_diff_bp: int = (abs(j0 - j1) * 10000) / max_j

	var passed: bool = j0 > 0 and j1 > 0 and grain_diff_bp <= 1500 and jobs_diff_bp <= 1500
	if not passed:
		errors.append("LOD0 vs LOD1 parity exceeded tolerance: grain=(%d vs %d, %d bp), jobs=(%d vs %d, %d bp)" % [
			g0, g1, grain_diff_bp, j0, j1, jobs_diff_bp
		])

	return {
		"checked": true,
		"passed": passed,
		"ticks": equiv_ticks,
		"lod0_grain": g0,
		"lod1_grain": g1,
		"grain_diff_bp": grain_diff_bp,
		"lod0_jobs": j0,
		"lod1_jobs": j1,
		"jobs_diff_bp": jobs_diff_bp
	}


func _verify_conservation_dispatch(manor: ManorState, world_seed: int, errors: Array[String]) -> void:
	# Verify INV-WORLD-CONSERVATION via deterministic copy dispatch
	var copy_m: ManorState = ManorState.from_dict(manor.to_dict())
	if copy_m.household_troops < 50:
		copy_m.household_troops = 50
	if copy_m.get_resource("GRAIN") < 200:
		var _a: int = copy_m.add_resource("GRAIN", 200)
	var before_troops: int = copy_m.household_troops
	var before_grain: int = copy_m.get_resource("GRAIN")
	var before_weapons: int = copy_m.get_resource("WEAPONS")
	var send_weapons: int = mini(10, before_weapons)
	var officer_id: String = ""
	for p: PawnEntity in copy_m.pawns:
		if p.state == "IN_MANOR":
			officer_id = p.pawn_id
			break
	if officer_id.is_empty():
		return
	var bus: SimEventBus = SimEventBus.new()
	var clk: SimClock = SimClock.new(world_seed % 100 + 1)
	var res: Dictionary = ManorSimulator.dispatch_expedition_from_manor(
		copy_m, [officer_id], 50, 150, {"WEAPONS": send_weapons}, ["edge_demo"], "ARMY", clk, bus
	)
	if not _to_bool(res.get("ok", false), false):
		errors.append("INV-WORLD-CONSERVATION dispatch failed")
		return
	if copy_m.household_troops != before_troops - 50:
		errors.append("INV-WORLD-CONSERVATION troops not atomically deducted")
	if copy_m.get_resource("GRAIN") != before_grain - 150:
		errors.append("INV-WORLD-CONSERVATION grain not atomically deducted")
	if copy_m.get_resource("WEAPONS") != before_weapons - send_weapons:
		errors.append("INV-WORLD-CONSERVATION cargo not atomically deducted")
	var disp_pawn: PawnEntity = copy_m.get_pawn_by_id(officer_id)
	if disp_pawn == null or disp_pawn.state != "ON_EXPEDITION":
		errors.append("INV-WORLD-CONSERVATION officer state not transitioned to ON_EXPEDITION")
	var p_var: Variant = res.get("payload", {})
	if p_var is Dictionary:
		var p_dict: Dictionary = p_var
		if not SimEventBus.validate_expedition_dispatched(p_dict):
			errors.append("INV-WORLD-CONSERVATION emitted payload failed SimEventBus schema check")
	else:
		errors.append("INV-WORLD-CONSERVATION emitted payload is not Dictionary")


func _write_json_report(out_path: String, report: Dictionary) -> void:
	var resolved_path: String = out_path
	if not resolved_path.begins_with("res://") and not resolved_path.begins_with("user://") and not resolved_path.begins_with("/"):
		resolved_path = ProjectSettings.globalize_path("res://").path_join(resolved_path)
	elif resolved_path.begins_with("res://") or resolved_path.begins_with("user://"):
		resolved_path = ProjectSettings.globalize_path(resolved_path)

	var parent_dir: String = resolved_path.get_base_dir()
	if not parent_dir.is_empty():
		var _mk_err: Error = DirAccess.make_dir_recursive_absolute(parent_dir)

	var f: FileAccess = FileAccess.open(resolved_path, FileAccess.WRITE)
	if f == null:
		printerr("[sim_harness] ERROR: Unable to write report to " + resolved_path)
		return
	var _ok_w: bool = f.store_string(JSON.stringify(report, "  ") + "\n")
	f.close()
