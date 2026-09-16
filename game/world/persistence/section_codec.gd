class_name AstraeonSectionCodec
extends RefCounted
## Disk IDs belong to the world's append-only state table, never to a runtime registry.
enum Encoding { DIRECT, DIRECT_FASTLZ, DIRECT_ZSTD, PALETTE, PALETTE_FASTLZ }
const LIMIT: int = 1048576

static func digest(data: PackedByteArray) -> PackedByteArray:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish()

static func envelope(value: Dictionary) -> PackedByteArray:
	var body: PackedByteArray = var_to_bytes(value)
	return var_to_bytes({"body": body, "sha256": digest(body)})

static func unwrap(data: PackedByteArray) -> Dictionary:
	if data.is_empty() or data.size() > LIMIT * 16:
		return {}
	var wrapper: Variant = bytes_to_var(data)
	if not wrapper is Dictionary or not wrapper.get("body") is PackedByteArray or not wrapper.get("sha256") is PackedByteArray:
		return {}
	if digest(wrapper.body) != wrapper.sha256:
		return {}
	var value: Variant = bytes_to_var(wrapper.body)
	return value if value is Dictionary else {}

static func encode(states: PackedInt32Array, mode: int) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	if states.size() != 4096 or mode < 0 or mode > 4:
		return {"error": "Invalid encode input"}
	var palette: PackedInt32Array = PackedInt32Array()
	var lookup: Dictionary[int, int] = {}
	var uniform: bool = true
	for state: int in states:
		if state < 0 or state > 65535:
			return {"error": "Disk state outside uint16"}
		uniform = uniform and state == states[0]
	var raw: PackedByteArray = PackedByteArray()
	var bits: int = 16
	if uniform:
		palette.append(states[0])
		bits = 0
	elif mode >= Encoding.PALETTE:
		for state: int in states:
			if not lookup.has(state):
				lookup[state] = palette.size()
				palette.append(state)
		bits = 1
		while (1 << bits) < palette.size():
			bits += 1
		raw.resize((4096 * bits + 7) >> 3)
		for index: int in range(4096):
			var value: int = lookup[states[index]]
			for bit: int in range(bits):
				var offset: int = index * bits + bit
				raw[offset >> 3] |= ((value >> bit) & 1) << (offset & 7)
	else:
		raw.resize(8192)
		for index: int in range(4096):
			raw.encode_u16(index * 2, states[index])
	var encoded: int = Time.get_ticks_usec()
	var compression: int = -1
	var payload: PackedByteArray = raw
	var fallback: bool = false
	if not raw.is_empty() and mode in [Encoding.DIRECT_FASTLZ, Encoding.DIRECT_ZSTD, Encoding.PALETTE_FASTLZ]:
		var candidate_mode: int = FileAccess.COMPRESSION_ZSTD if mode == Encoding.DIRECT_ZSTD else FileAccess.COMPRESSION_FASTLZ
		var compressed: PackedByteArray = raw.compress(candidate_mode)
		if not compressed.is_empty() and compressed.size() < raw.size():
			payload = compressed
			compression = candidate_mode
		else:
			fallback = true
	var compressed_at: int = Time.get_ticks_usec()
	var record: Dictionary = {"version": 1, "mode": mode, "bits": bits, "palette": palette, "raw_size": raw.size(), "compression": compression, "payload": payload, "sha256": digest(raw)}
	return {"record": record, "encode_us": encoded - started, "compress_us": compressed_at - encoded, "checksum_us": Time.get_ticks_usec() - compressed_at, "payload_bytes": payload.size(), "raw_bytes": raw.size(), "fallback": fallback}

static func decode(record: Dictionary, mapping: PackedInt32Array) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	if record.get("version") != 1 or not record.get("palette") is PackedInt32Array or not record.get("payload") is PackedByteArray:
		return {"error": "Invalid section header"}
	var mode: int = int(record.get("mode", -1))
	var bits: int = int(record.get("bits", -1))
	var raw_size: int = int(record.get("raw_size", -1))
	var compression: int = int(record.get("compression", -2))
	var palette: PackedInt32Array = record.palette
	if mode < 0 or mode > 4 or bits < 0 or bits > 16 or raw_size < 0 or raw_size > 8192 or not compression in [-1, FileAccess.COMPRESSION_FASTLZ, FileAccess.COMPRESSION_ZSTD]:
		return {"error": "Invalid section bounds"}
	if (bits == 0 and (palette.size() != 1 or raw_size != 0)) or (bits > 0 and mode < 3 and (bits != 16 or not palette.is_empty() or raw_size != 8192)) or (bits > 0 and mode >= 3 and (palette.size() < 2 or palette.size() > 4096 or palette.size() > (1 << bits) or raw_size != ((4096 * bits + 7) >> 3))):
		return {"error": "Invalid palette layout"}
	var payload: PackedByteArray = record.payload
	if payload.size() > LIMIT:
		return {"error": "Payload too large"}
	var raw: PackedByteArray = payload if compression == -1 else payload.decompress(raw_size, compression)
	var decompressed: int = Time.get_ticks_usec()
	if raw.size() != raw_size or digest(raw) != record.get("sha256"):
		return {"error": "Section checksum mismatch"}
	var checked: int = Time.get_ticks_usec()
	var values: PackedInt32Array = PackedInt32Array()
	values.resize(4096)
	for index: int in range(4096):
		var disk_id: int
		if bits == 0:
			disk_id = palette[0]
		elif mode < 3:
			disk_id = raw.decode_u16(index * 2)
		else:
			var palette_index: int = 0
			for bit: int in range(bits):
				var offset: int = index * bits + bit
				palette_index |= ((raw[offset >> 3] >> (offset & 7)) & 1) << bit
			if palette_index >= palette.size():
				return {"error": "Palette index out of range"}
			disk_id = palette[palette_index]
		values[index] = disk_id
	var unpacked: int = Time.get_ticks_usec()
	for index: int in range(4096):
		var disk_id: int = values[index]
		if disk_id < 0 or disk_id >= mapping.size() or mapping[disk_id] < 0:
			return {"error": "Unknown persistent state"}
		values[index] = mapping[disk_id]
	return {"states": values, "decompress_us": decompressed - started, "verify_us": checked - decompressed, "unpack_us": unpacked - checked, "map_us": Time.get_ticks_usec() - unpacked}

