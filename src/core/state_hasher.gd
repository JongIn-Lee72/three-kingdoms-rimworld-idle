class_name StateHasher
extends RefCounted

static var _crc32_table: PackedInt64Array = PackedInt64Array()


static func _ensure_crc32_table() -> void:
	if _crc32_table.size() == 256:
		return
	var table: PackedInt64Array = PackedInt64Array()
	var _err: int = table.resize(256)
	for i: int in range(256):
		var c: int = i
		for _bit: int in range(8):
			if (c & 1) != 0:
				c = 0xEDB88320 ^ ((c >> 1) & 0x7FFFFFFF)
			else:
				c = (c >> 1) & 0x7FFFFFFF
		table[i] = c
	_crc32_table = table


static func has_floats(value: Variant) -> bool:
	if value is float:
		return true
	if value is Dictionary:
		var d: Dictionary = value
		for k: Variant in d.keys():
			if has_floats(k) or has_floats(d[k]):
				return true
		return false
	if value is Array:
		var arr: Array = value
		for elem: Variant in arr:
			if has_floats(elem):
				return true
		return false
	if value is PackedFloat32Array or value is PackedFloat64Array:
		return true
	return false


static func validate_deterministic_types(value: Variant) -> bool:
	var t: int = typeof(value)
	match t:
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			return true
		TYPE_ARRAY:
			var arr: Array = value
			for elem: Variant in arr:
				if not validate_deterministic_types(elem):
					return false
			return true
		TYPE_DICTIONARY:
			var d: Dictionary = value
			for k: Variant in d.keys():
				var kt: int = typeof(k)
				if kt != TYPE_STRING and kt != TYPE_STRING_NAME and kt != TYPE_INT:
					return false
				if not validate_deterministic_types(d[k]):
					return false
			return true
		_:
			return false


static func canonical_json(value: Variant) -> String:
	if value == null:
		return "null"
	if value is bool:
		var b: bool = value
		return "true" if b else "false"
	if value is int:
		var iv: int = value
		return str(iv)
	if value is float:
		var fv: float = value
		return JSON.stringify(fv)
	if value is String or value is StringName:
		return JSON.stringify(str(value))
	if value is Array:
		var arr: Array = value
		var parts: PackedStringArray = PackedStringArray()
		for elem: Variant in arr:
			var _ok: bool = parts.append(canonical_json(elem))
		return "[" + ",".join(parts) + "]"
	if value is PackedStringArray:
		var psa: PackedStringArray = value
		var parts_s: PackedStringArray = PackedStringArray()
		for elem_s: String in psa:
			var _ok: bool = parts_s.append(JSON.stringify(elem_s))
		return "[" + ",".join(parts_s) + "]"
	if value is PackedInt32Array:
		var pi32: PackedInt32Array = value
		var parts_i32: PackedStringArray = PackedStringArray()
		for elem_i32: int in pi32:
			var _ok: bool = parts_i32.append(str(elem_i32))
		return "[" + ",".join(parts_i32) + "]"
	if value is PackedInt64Array:
		var pi64: PackedInt64Array = value
		var parts_i64: PackedStringArray = PackedStringArray()
		for elem_i64: int in pi64:
			var _ok: bool = parts_i64.append(str(elem_i64))
		return "[" + ",".join(parts_i64) + "]"
	if value is PackedByteArray:
		var pba: PackedByteArray = value
		var parts_b: PackedStringArray = PackedStringArray()
		for elem_b: int in pba:
			var _ok: bool = parts_b.append(str(elem_b))
		return "[" + ",".join(parts_b) + "]"
	if value is Dictionary:
		var d: Dictionary = value
		var key_map: Dictionary = {}
		var sorted_keys: Array[String] = []
		for raw_k: Variant in d.keys():
			var ks: String = str(raw_k)
			if not key_map.has(ks):
				sorted_keys.append(ks)
			key_map[ks] = raw_k
		sorted_keys.sort()
		var kv_parts: PackedStringArray = PackedStringArray()
		for ks: String in sorted_keys:
			var orig_k: Variant = key_map[ks]
			var _ok: bool = kv_parts.append(JSON.stringify(ks) + ":" + canonical_json(d[orig_k]))
		return "{" + ",".join(kv_parts) + "}"
	return JSON.stringify(str(value))


static func crc32_bytes(data: PackedByteArray) -> int:
	_ensure_crc32_table()
	var crc: int = 0xFFFFFFFF
	for b: int in data:
		var idx: int = (crc ^ b) & 0xFF
		crc = ((crc >> 8) & 0x00FFFFFF) ^ _crc32_table[idx]
	return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF


static func crc32_dict(data: Dictionary) -> int:
	return crc32_bytes(canonical_json(data).to_utf8_buffer())


static func sha256_bytes(data: PackedByteArray) -> String:
	var ctx: HashingContext = HashingContext.new()
	var _err: int = ctx.start(HashingContext.HASH_SHA256)
	if not data.is_empty():
		_err = ctx.update(data)
	var digest: PackedByteArray = ctx.finish()
	return digest.hex_encode()


static func sha256_dict(data: Dictionary) -> String:
	return sha256_bytes(canonical_json(data).to_utf8_buffer())
