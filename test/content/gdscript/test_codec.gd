extends SceneTree
const Fixture = preload("res://test/content/gdscript/authoring_fixture.gd")
var checks: int = 0
var failures: int = 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var codec: RefCounted = ClassDB.instantiate("AstraeonContentPack")
	check(codec != null, "native codec loaded")
	if codec == null:
		quit(1)
		return
	var compiler: RefCounted = load("res://tools/content/compiler.gd").new()
	check(compiler != null, "authoring frontend parses")
	var manifest: Resource = load("res://game/data/content/gdscript/content_manifest.gd").new()
	manifest.package_id = "example"
	var block: AstraeonBlockDefinition = AstraeonBlockDefinition.new()
	block.key = &"example:crystal"
	block.load_policy = "on_demand"
	block.appearance = AstraeonBlockAppearance.new()
	block.appearance.breaking = null
	block.appearance.default_surface = AstraeonBlockSurface.new()
	block.appearance.default_surface.base_color = Color(0.2, 0.4, 0.8)
	var asset: AstraeonBlockAsset = Fixture.add_block(manifest, block)
	var output: String = "res://tmp/content/test.aebpack"
	var first: Dictionary = compiler.build(manifest, output)
	check(not first.has("error"), "compile constant block: " + str(first))
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(output)
	var second: Dictionary = compiler.build(manifest, output)
	check(not second.has("error") and bytes == FileAccess.get_file_as_bytes(output), "deterministic repeat build")
	check(int(second.get("cache_hits", 0)) == 1, "incremental cache hit")
	var definitions: Dictionary = codec.call("open_pack", output)
	check(not definitions.has("error") and int(codec.call("get_metrics").blob_reads) == 0, "metadata open does not read payload")
	check(int(first.get("unique_blobs", -1)) == 0, "pure color creates no image")
	for size: int in [16, 32, 64, 128]:
		var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
		image.fill(Color.RED)
		image.set_pixel(0, 0, Color.BLUE)
		block.appearance.texture_resolution = size
		Fixture.bind_image(manifest, asset, "surface/default", image)
		var result: Dictionary = compiler.build(manifest, output)
		check(not result.has("error"), "textured compile %d" % size)
		definitions = codec.call("open_pack", output)
		if definitions.has("error"):
			check(false, "read textured pack")
			continue
		var hash: String = definitions.blocks[0].visual
		var payload: PackedByteArray = codec.call("read_blob", hash)
		check(payload.size() == 16 + size * size * 6 * 4, "texture payload size %d" % size)
		check(hash == compiler._hash(payload), "decoded payload hash %d" % size)
	bytes = FileAccess.get_file_as_bytes(output)
	for index: int in [0, 8, 16, 32, 64, bytes.size() - 1]:
		var bad: PackedByteArray = bytes.duplicate()
		bad[index] = bad[index] ^ 255
		var path: String = "res://tmp/content/corrupt.aebpack"
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(bad)
		file.close()
		var rejected: Dictionary = codec.call("open_pack", path)
		if index == bytes.size() - 1 and not rejected.has("error"):
			check(PackedByteArray(codec.call("read_blob", rejected.blocks[0].visual)).is_empty(), "payload damage rejected on first request")
		else:
			check(rejected.has("error"), "corrupt header/index rejected %d" % index)
	var truncated: FileAccess = FileAccess.open("res://tmp/content/truncated.aebpack", FileAccess.WRITE)
	truncated.store_buffer(bytes.slice(0, bytes.size()-1))
	truncated.close()
	check(codec.call("open_pack", "res://tmp/content/truncated.aebpack").has("error"), "truncation rejected")
	print("CONTENT_CODEC_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
