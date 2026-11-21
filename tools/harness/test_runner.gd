extends SceneTree


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
	var t_start_ms: int = Time.get_ticks_msec()
	var args: PackedStringArray = OS.get_cmdline_user_args()

	var target_dir: String = "res://tests"
	var target_file: String = ""
	var out_path: String = "reports/test_report.json"

	for arg: String in args:
		if arg.begins_with("--dir="):
			target_dir = arg.substr(6)
		elif arg.begins_with("--file="):
			target_file = arg.substr(7)
		elif arg.begins_with("--out="):
			out_path = arg.substr(6)

	var test_files: Array[String] = []
	if not target_file.is_empty():
		test_files.append(target_file)
	else:
		_discover_tests(target_dir, test_files)
		test_files.sort()

	var total_tests: int = 0
	var passed_tests: int = 0
	var failed_tests: int = 0
	var total_assertions: int = 0
	var min_assertions: int = -1
	var results: Array[Dictionary] = []

	for file_path: String in test_files:
		var suite_results: Array[Dictionary] = _run_suite_file(file_path)
		for rec: Dictionary in suite_results:
			results.append(rec)
			total_tests += 1
			var asserts_cnt: int = _to_int(rec.get("assertions", 0), 0)
			total_assertions += asserts_cnt
			if min_assertions < 0 or asserts_cnt < min_assertions:
				min_assertions = asserts_cnt
			if str(rec.get("status", "FAIL")) == "PASS":
				passed_tests += 1
			else:
				failed_tests += 1

	if min_assertions < 0:
		min_assertions = 0

	var elapsed_ms: int = maxi(0, Time.get_ticks_msec() - t_start_ms)
	var report: Dictionary = {
		"schema_version": "1.0",
		"total_tests": total_tests,
		"passed_tests": passed_tests,
		"failed_tests": failed_tests,
		"total_assertions": total_assertions,
		"min_assertions_per_test": min_assertions,
		"elapsed_ms": elapsed_ms,
		"results": results
	}

	_write_report(out_path, report)

	print("[test_runner] total=%d passed=%d failed=%d assertions=%d min_per_test=%d elapsed_ms=%d" % [
		total_tests, passed_tests, failed_tests, total_assertions, min_assertions, elapsed_ms
	])

	if total_tests > 0 and failed_tests == 0:
		quit(0)
	else:
		quit(1)


func _discover_tests(dir_path: String, out_files: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	var _err: Error = dir.list_dir_begin()
	while true:
		var name: String = dir.get_next()
		if name.is_empty():
			break
		if name.begins_with("."):
			continue
		var full_path: String = dir_path.path_join(name)
		if dir.current_is_dir():
			_discover_tests(full_path, out_files)
		elif name.begins_with("test_") and name.ends_with(".gd"):
			out_files.append(full_path)
	dir.list_dir_end()


func _run_suite_file(file_path: String) -> Array[Dictionary]:
	var suite_results: Array[Dictionary] = []
	if not FileAccess.file_exists(file_path):
		suite_results.append({
			"file": file_path,
			"test": "<load>",
			"status": "FAIL",
			"assertions": 0,
			"duration_ms": 0,
			"failures": [{"type": "load_error", "actual": "missing", "expected": "exists", "context": file_path}]
		})
		return suite_results

	var res: Resource = ResourceLoader.load(file_path)
	if not (res is GDScript):
		suite_results.append({
			"file": file_path,
			"test": "<load>",
			"status": "FAIL",
			"assertions": 0,
			"duration_ms": 0,
			"failures": [{"type": "load_error", "actual": "non-GDScript", "expected": "GDScript", "context": file_path}]
		})
		return suite_results

	var gd: GDScript = res
	var instance: Variant = gd.new()
	if not (instance is HarnessTestCase):
		suite_results.append({
			"file": file_path,
			"test": "<instantiate>",
			"status": "FAIL",
			"assertions": 0,
			"duration_ms": 0,
			"failures": [{"type": "type_error", "actual": "not HarnessTestCase", "expected": "extends HarnessTestCase", "context": file_path}]
		})
		return suite_results

	var tc: HarnessTestCase = instance
	var method_names: Array[String] = []
	for m_info: Dictionary in tc.get_method_list():
		var m_name: String = str(m_info.get("name", ""))
		if m_name.begins_with("test_"):
			var args_var: Variant = m_info.get("args", [])
			if args_var is Array:
				var args_arr: Array = args_var
				if args_arr.is_empty():
					if not method_names.has(m_name):
						method_names.append(m_name)
	method_names.sort()

	if method_names.is_empty():
		suite_results.append({
			"file": file_path,
			"test": "<discovery>",
			"status": "FAIL",
			"assertions": 0,
			"duration_ms": 0,
			"failures": [{"type": "empty_suite", "actual": "0", "expected": ">= 1", "context": "No test_* methods found in file"}]
		})
		return suite_results

	for m_name: String in method_names:
		var m_start: int = Time.get_ticks_msec()
		tc.assertions_run = 0
		tc.failures.clear()
		tc.before_each()
		tc.call(m_name)
		tc.after_each()

		if tc.assertions_run == 0:
			tc.failures.append({
				"type": "zero_assertions",
				"actual": "0",
				"expected": ">= 1",
				"context": "Vacuous test forbidden: 0 assertions executed"
			})

		var m_dur: int = maxi(0, Time.get_ticks_msec() - m_start)
		var passed: bool = tc.failures.is_empty()
		var status_str: String = "PASS" if passed else "FAIL"
		if not passed:
			printerr("[FAIL] %s::%s -> %s" % [file_path, m_name, JSON.stringify(tc.failures)])
		suite_results.append({
			"file": file_path,
			"test": m_name,
			"status": status_str,
			"assertions": tc.assertions_run,
			"duration_ms": m_dur,
			"failures": tc.failures.duplicate(true)
		})

	return suite_results


func _write_report(out_path: String, report: Dictionary) -> void:
	var resolved_path: String = out_path
	if not resolved_path.begins_with("res://") and not resolved_path.begins_with("user://") and not resolved_path.begins_with("/"):
		resolved_path = ProjectSettings.globalize_path("res://").path_join(resolved_path)
	elif resolved_path.begins_with("res://") or resolved_path.begins_with("user://"):
		resolved_path = ProjectSettings.globalize_path(resolved_path)

	var parent_dir: String = resolved_path.get_base_dir()
	if not parent_dir.is_empty():
		var _mk_err: Error = DirAccess.make_dir_recursive_absolute(parent_dir)

	var file: FileAccess = FileAccess.open(resolved_path, FileAccess.WRITE)
	if file == null:
		printerr("[test_runner] ERROR: Unable to write test report to " + resolved_path)
		return
	var _ok_write: bool = file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
