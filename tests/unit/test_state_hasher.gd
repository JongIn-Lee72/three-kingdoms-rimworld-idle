class_name TestStateHasher
extends HarnessTestCase


func test_canonical_json_sorted_key_determinism() -> void:
	var d1: Dictionary = {
		"z": 1,
		"a": {"d": 4, "b": 2, "c": [3, true, null, "hi"]},
		"m": PackedInt64Array([10, 20])
	}
	var d2: Dictionary = {
		"m": PackedInt64Array([10, 20]),
		"a": {"c": [3, true, null, "hi"], "b": 2, "d": 4},
		"z": 1
	}
	var j1: String = StateHasher.canonical_json(d1)
	var j2: String = StateHasher.canonical_json(d2)
	assert_eq(j1, j2, "canonical_json must be identical regardless of dictionary insertion order")
	assert_eq(
		j1,
		"{\"a\":{\"b\":2,\"c\":[3,true,null,\"hi\"],\"d\":4},\"m\":[10,20],\"z\":1}",
		"canonical_json output must match exact sorted compact JSON representation"
	)


func test_has_floats_and_validate_deterministic_types() -> void:
	var clean_state: Dictionary = {
		"tick_id": 100,
		"ok": true,
		"empty": null,
		"name": "Luoyang",
		"sname": &"GRAIN",
		"nested": [1, 2, {"sub": PackedInt32Array([5, 6])}],
		"bytes": PackedByteArray([1, 2, 3]),
		"tags": PackedStringArray(["a", "b"]),
		12: "int_key_allowed"
	}
	assert_false(StateHasher.has_floats(clean_state), "Pure integer/string/bool/packed-int state has_floats == false")
	assert_true(StateHasher.validate_deterministic_types(clean_state), "Pure deterministic types must pass validation")

	assert_true(StateHasher.has_floats(1.5), "Scalar float triggers has_floats")
	assert_true(StateHasher.has_floats({"a": [1, {"b": 0.0}]}), "Nested float 0.0 triggers has_floats")
	assert_true(StateHasher.has_floats({2.5: "float_key"}), "Float dictionary key triggers has_floats")
	assert_true(StateHasher.has_floats(PackedFloat32Array([1.0])), "PackedFloat32Array triggers has_floats")
	assert_true(StateHasher.has_floats(PackedFloat64Array([1.0])), "PackedFloat64Array triggers has_floats")

	assert_false(StateHasher.validate_deterministic_types(3.14), "Scalar float rejected by validate_deterministic_types")
	assert_false(StateHasher.validate_deterministic_types({"x": 1.0}), "Nested float rejected by validate_deterministic_types")
	assert_false(StateHasher.validate_deterministic_types(PackedFloat64Array([1.0])), "PackedFloat64Array rejected")
	assert_false(StateHasher.validate_deterministic_types(Vector2(1.0, 2.0)), "Vector2 rejected")
	assert_false(StateHasher.validate_deterministic_types({true: 1}), "Bool dictionary key rejected")
	assert_false(StateHasher.validate_deterministic_types({"obj": SimClock.new()}), "Object instance rejected")


func test_ieee_802_3_crc32_reference_vectors() -> void:
	var crc_check: int = StateHasher.crc32_bytes("123456789".to_utf8_buffer())
	assert_eq(crc_check, 3421780262, "IEEE 802.3 CRC32 of '123456789' must equal 3421780262 (0xCBF43926)")

	var crc_empty: int = StateHasher.crc32_bytes(PackedByteArray())
	assert_eq(crc_empty, 0, "IEEE 802.3 CRC32 of empty bytes must equal 0")


func test_sha256_reference_vectors() -> void:
	var sha_abc: String = StateHasher.sha256_bytes("abc".to_utf8_buffer())
	assert_eq(
		sha_abc,
		"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
		"SHA-256 of 'abc' must match NIST FIPS 180-4 vector"
	)

	var sha_empty: String = StateHasher.sha256_bytes(PackedByteArray())
	assert_eq(
		sha_empty,
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"SHA-256 of empty bytes must match standard vector"
	)


func test_dict_hash_key_order_invariance_and_sensitivity() -> void:
	var a: Dictionary = {
		"tick": 55,
		"resources": {"GRAIN": 1000, "COIN": 500, "IRON": 250},
		"officers": [{"id": 2, "loyalty": 8000}, {"id": 1, "loyalty": 9500}]
	}
	var b: Dictionary = {
		"officers": [{"loyalty": 8000, "id": 2}, {"loyalty": 9500, "id": 1}],
		"resources": {"IRON": 250, "COIN": 500, "GRAIN": 1000},
		"tick": 55
	}
	var mutated: Dictionary = {
		"tick": 55,
		"resources": {"GRAIN": 1001, "COIN": 500, "IRON": 250},
		"officers": [{"id": 2, "loyalty": 8000}, {"id": 1, "loyalty": 9500}]
	}

	assert_eq(StateHasher.crc32_dict(a), StateHasher.crc32_dict(b), "crc32_dict must be key-order invariant")
	assert_eq(StateHasher.sha256_dict(a), StateHasher.sha256_dict(b), "sha256_dict must be key-order invariant")
	assert_ne(StateHasher.crc32_dict(a), StateHasher.crc32_dict(mutated), "crc32_dict must detect 1-unit mutation")
	assert_ne(StateHasher.sha256_dict(a), StateHasher.sha256_dict(mutated), "sha256_dict must detect 1-unit mutation")
