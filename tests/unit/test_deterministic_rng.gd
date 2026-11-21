class_name TestDeterministicRNG
extends HarnessTestCase


func test_reference_splitmix64_sequence_seed_18401() -> void:
	var expected: Array[int] = [6597, 3130, 5870, 2835, 4098, 8078, 429, 8058, 3432, 2984]
	var actual: Array[int] = []
	for tick: int in range(10):
		actual.append(DeterministicRNG.roll_range(18401, tick, 101, 7, 1, 10000))
	assert_eq(actual, expected, "SplitMix64 int64 parity must match reference sequence for seed 18401")

	# Calling a second time must produce the exact same sequence (stateless determinism)
	var replay: Array[int] = []
	for tick: int in range(10):
		replay.append(DeterministicRNG.roll_range(18401, tick, 101, 7, 1, 10000))
	assert_eq(replay, expected, "Repeated calls with identical 4-tuple must be deterministic")


func test_negative_seed_and_logical_shr_u64_handling() -> void:
	# Verify logical right shift does not sign-extend negative int64 values
	assert_eq(DeterministicRNG._shr_u64(-1, 1), 0x7FFFFFFFFFFFFFFF, "_shr_u64(-1, 1) must clear sign bit")
	assert_eq(DeterministicRNG._shr_u64(-1, 32), 0x00000000FFFFFFFF, "_shr_u64(-1, 32) logical shift")
	assert_eq(DeterministicRNG._shr_u64(-1, 64), 0, "_shr_u64(-1, 64) must be 0")
	assert_eq(DeterministicRNG._shr_u64(-12345, 0), -12345, "_shr_u64(x, 0) returns x")

	var neg_seeds: Array[int] = [-1, -18401, -9223372036854775808]
	for s: int in neg_seeds:
		var u63: int = DeterministicRNG.roll_u63(s, 3, 42, 9)
		assert_gte(u63, 0, "roll_u63 must always be non-negative for seed %d" % s)
		var r1: int = DeterministicRNG.roll_range(s, 3, 42, 9, 1, 10000)
		var r2: int = DeterministicRNG.roll_range(s, 3, 42, 9, 1, 10000)
		assert_in_range(r1, 1, 10000, "roll_range with negative seed %d must stay within [1, 10000]" % s)
		assert_eq(r1, r2, "Negative seed %d must remain deterministic" % s)


func test_tuple_component_sensitivity() -> void:
	var base: int = DeterministicRNG.hash_4tuple(18401, 5, 101, 7)
	assert_ne(DeterministicRNG.hash_4tuple(18402, 5, 101, 7), base, "Changing world_seed must alter hash")
	assert_ne(DeterministicRNG.hash_4tuple(18401, 6, 101, 7), base, "Changing tick_id must alter hash")
	assert_ne(DeterministicRNG.hash_4tuple(18401, 5, 102, 7), base, "Changing entity_id must alter hash")
	assert_ne(DeterministicRNG.hash_4tuple(18401, 5, 101, 8), base, "Changing salt must alter hash")


func test_range_permille_and_bp_bounds() -> void:
	assert_eq(DeterministicRNG.roll_range(18401, 0, 1, 0, 42, 42), 42, "Degenerate [42, 42] returns 42")
	assert_eq(DeterministicRNG.roll_range(18401, 0, 1, 0, 100, 50), 100, "Inverted [100, 50] returns min_val 100")

	for i: int in range(50):
		var neg_r: int = DeterministicRNG.roll_range(18401, i, 200, 3, -25, -10)
		assert_in_range(neg_r, -25, -10, "Negative interval [-25, -10] at i=%d" % i)

		var pm: int = DeterministicRNG.roll_permille(18401, i, 300, 11)
		assert_in_range(pm, 0, 999, "roll_permille must stay in [0, 999] at i=%d" % i)

		var bp: int = DeterministicRNG.roll_bp(18401, i, 400, 13)
		assert_in_range(bp, 0, 9999, "roll_bp must stay in [0, 9999] at i=%d" % i)


func test_non_mutating_deterministic_shuffle() -> void:
	var original: Array[int] = [10, 20, 30, 40, 50, 60, 70, 80]
	var snapshot: Array[int] = original.duplicate()

	var shuf_a: Array = DeterministicRNG.shuffle_deterministic(original, 18401, 12, 5, 1)
	var shuf_b: Array = DeterministicRNG.shuffle_deterministic(original, 18401, 12, 5, 1)
	var shuf_diff: Array = DeterministicRNG.shuffle_deterministic(original, 18401, 12, 5, 99)

	assert_eq(original, snapshot, "shuffle_deterministic must not mutate input array")
	assert_eq(shuf_a, shuf_b, "shuffle_deterministic must be deterministic for same 4-tuple")
	assert_ne(shuf_a, shuf_diff, "shuffle_deterministic must vary with different salt")
	assert_eq(shuf_a.size(), original.size(), "Shuffled array preserves length")

	var sorted_a: Array = shuf_a.duplicate()
	sorted_a.sort()
	assert_eq(sorted_a, [10, 20, 30, 40, 50, 60, 70, 80], "Shuffled array preserves exact multiset")

	var empty_res: Array = DeterministicRNG.shuffle_deterministic([], 18401, 0, 0, 0)
	assert_eq(empty_res.size(), 0, "Empty shuffle returns empty array")

	var single_res: Array = DeterministicRNG.shuffle_deterministic([99], 18401, 0, 0, 0)
	assert_eq(single_res, [99], "Single-element shuffle returns [99]")
