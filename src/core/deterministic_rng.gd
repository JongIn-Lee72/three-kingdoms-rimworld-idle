class_name DeterministicRNG
extends RefCounted

# Two's-complement signed int64 representations of SplitMix64 64-bit unsigned constants:
# 0x9E3779B97F4A7C15 -> -7046029254386353131
# 0xBF58476D1CE4E5B9 -> -4658895280553007687
# 0x94D049BB133111EB -> -7723592293110705685
const GOLDEN_GAMMA: int = -7046029254386353131
const MIX_MUL1: int = -4658895280553007687
const MIX_MUL2: int = -7723592293110705685
const MASK_U63: int = 0x7FFFFFFFFFFFFFFF


static func _shr_u64(x: int, k: int) -> int:
	if k <= 0:
		return x
	if k >= 64:
		return 0
	if k == 1:
		return (x >> 1) & MASK_U63
	var mask: int = (1 << (64 - k)) - 1
	return (x >> k) & mask


static func mix64(seed_val: int) -> int:
	var z: int = seed_val
	z = (z ^ _shr_u64(z, 30)) * MIX_MUL1
	z = (z ^ _shr_u64(z, 27)) * MIX_MUL2
	z = z ^ _shr_u64(z, 31)
	return z


static func hash_4tuple(world_seed: int, tick_id: int, entity_id: int, salt: int) -> int:
	var z: int = world_seed ^ (tick_id * GOLDEN_GAMMA) ^ (entity_id * MIX_MUL1) ^ (salt * MIX_MUL2)
	return mix64(z)


static func roll_u63(world_seed: int, tick_id: int, entity_id: int, salt: int) -> int:
	return hash_4tuple(world_seed, tick_id, entity_id, salt) & MASK_U63


static func roll_range(
	world_seed: int,
	tick_id: int,
	entity_id: int,
	salt: int,
	min_val: int,
	max_val: int
) -> int:
	if max_val <= min_val:
		return min_val
	var pos_z: int = roll_u63(world_seed, tick_id, entity_id, salt)
	var span: int = (max_val - min_val) + 1
	if span <= 0:
		return min_val
	return min_val + (pos_z % span)


static func roll_permille(world_seed: int, tick_id: int, entity_id: int, salt: int) -> int:
	return roll_range(world_seed, tick_id, entity_id, salt, 0, 999)


static func roll_bp(world_seed: int, tick_id: int, entity_id: int, salt: int) -> int:
	return roll_range(world_seed, tick_id, entity_id, salt, 0, 9999)


static func shuffle_deterministic(
	items: Array,
	world_seed: int,
	tick_id: int,
	entity_id: int,
	salt: int
) -> Array:
	var out: Array = items.duplicate()
	var n: int = out.size()
	if n <= 1:
		return out
	for i: int in range(n - 1, 0, -1):
		var j: int = roll_range(world_seed, tick_id, entity_id, salt + i, 0, i)
		var tmp: Variant = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out
