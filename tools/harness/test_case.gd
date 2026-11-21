class_name HarnessTestCase
extends RefCounted

var assertions_run: int = 0
var failures: Array[Dictionary] = []


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func _record_failure(check_type: String, actual: String, expected: String, context: String) -> void:
	failures.append({
		"type": check_type,
		"actual": actual,
		"expected": expected,
		"context": context
	})


func fail(reason: String = "") -> void:
	assertions_run += 1
	_record_failure("fail", "failed", "pass", reason)


func assert_eq(actual: Variant, expected: Variant, context: String = "") -> void:
	assertions_run += 1
	if actual != expected:
		_record_failure("assert_eq", str(actual), str(expected), context)


func assert_ne(actual: Variant, unexpected: Variant, context: String = "") -> void:
	assertions_run += 1
	if actual == unexpected:
		_record_failure("assert_ne", str(actual), "!= " + str(unexpected), context)


func assert_true(condition: bool, context: String = "") -> void:
	assertions_run += 1
	if not condition:
		_record_failure("assert_true", "false", "true", context)


func assert_false(condition: bool, context: String = "") -> void:
	assertions_run += 1
	if condition:
		_record_failure("assert_false", "true", "false", context)


func assert_in_range(val: int, min_val: int, max_val: int, context: String = "") -> void:
	assertions_run += 1
	if val < min_val or val > max_val:
		_record_failure("assert_in_range", str(val), "[%d, %d]" % [min_val, max_val], context)


func assert_has_key(dict: Dictionary, key: Variant, context: String = "") -> void:
	assertions_run += 1
	if not dict.has(key):
		_record_failure("assert_has_key", "missing", str(key), context)


func assert_gt(actual: int, threshold: int, context: String = "") -> void:
	assertions_run += 1
	if actual <= threshold:
		_record_failure("assert_gt", str(actual), "> " + str(threshold), context)


func assert_gte(actual: int, threshold: int, context: String = "") -> void:
	assertions_run += 1
	if actual < threshold:
		_record_failure("assert_gte", str(actual), ">= " + str(threshold), context)


func assert_lt(actual: int, threshold: int, context: String = "") -> void:
	assertions_run += 1
	if actual >= threshold:
		_record_failure("assert_lt", str(actual), "< " + str(threshold), context)


func assert_lte(actual: int, threshold: int, context: String = "") -> void:
	assertions_run += 1
	if actual > threshold:
		_record_failure("assert_lte", str(actual), "<= " + str(threshold), context)


func assert_not_null(val: Variant, context: String = "") -> void:
	assertions_run += 1
	if val == null:
		_record_failure("assert_not_null", "null", "non-null", context)


func assert_null(val: Variant, context: String = "") -> void:
	assertions_run += 1
	if val != null:
		_record_failure("assert_null", str(val), "null", context)


func assert_contains(haystack: String, needle: String, context: String = "") -> void:
	assertions_run += 1
	if not haystack.contains(needle):
		_record_failure("assert_contains", haystack, "contains '%s'" % needle, context)
