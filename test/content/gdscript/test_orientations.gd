extends SceneTree
const Fixture = preload("res://test/content/gdscript/authoring_fixture.gd")
var checks: int = 0
var failures: int = 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var block: AstraeonBlockDefinition = AstraeonBlockDefinition.new()
	block.key = &"orientation:marked"
	block.default_state = &"r0"
	block.appearance = AstraeonBlockAppearance.new()
	block.appearance.breaking = null
	block.appearance.default_surface = AstraeonBlockSurface.new()
	block.appearance.texture_resolution = 16
	var image: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color.RED)
	image.set_pixel(1, 0, Color.GREEN)
	image.set_pixel(0, 1, Color.BLUE)
	image.set_pixel(1, 1, Color.WHITE)
	block.appearance.default_surface.albedo_texture = ImageTexture.create_from_image(image)
	for face: int in range(6):
		block.appearance.face_uv_rotations[face] = (face % 4) * 90
		block.appearance.face_uv_mirrors[face] = Vector2i(face % 2, (face / 2) % 2)
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
	var bases: Array[Basis] = []
	for x: Vector3 in axes:
		for y: Vector3 in axes:
			if not is_zero_approx(x.dot(y)): continue
			var basis: Basis = Basis(x, y, x.cross(y))
			var state: AstraeonBlockStateDefinition = AstraeonBlockStateDefinition.new()
			state.key = StringName("r%d" % bases.size())
			state.orientation = basis
			bases.append(basis)
			block.states.append(state)
	var manifest: Resource = load("res://game/data/content/gdscript/content_manifest.gd").new()
	manifest.package_id = "orientation"
	var asset: AstraeonBlockAsset = Fixture.add_block(manifest, block)
	var compiler: RefCounted = load("res://tools/content/compiler.gd").new()
	var path: String = "res://tmp/content/orientations.aebpack"
	var built: Dictionary = compiler.build(manifest, path)
	check(not built.has("error") and int(built.unique_blobs) == 1, "24 rotations share one atlas")
	var codec: RefCounted = ClassDB.instantiate("AstraeonContentPack")
	var data: Dictionary = codec.open_pack(path)
	var pixels: PackedByteArray = codec.read_blob(data.blocks[0].visual)
	var atlas: Image = Image.create_from_data(96, 16, false, Image.FORMAT_RGBA8, pixels.slice(16))
	for face: int in range(6):
		for uv: Vector2i in [Vector2i(0, 0), Vector2i(15, 0), Vector2i(0, 15), Vector2i(15, 15)]:
			var transformed: Vector2 = block.appearance.transform_uv(face, (Vector2(uv) + Vector2.ONE * 0.5) / 16.0)
			check(atlas.get_pixel(face*16+uv.x, uv.y).is_equal_approx(image.get_pixel(int(transformed.x*2), int(transformed.y*2))), "Six-face UV transform %d %s" % [face, uv])
	var content: AstraeonWorldContent = AstraeonWorldContent.new()
	check(content.build(PackedStringArray([path])), "Build oriented models")
	var normals: Array[Vector3] = [Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
	var shared: Material = content.library.models[1].get_material_override(0)
	for index: int in range(24):
		var id: int = content.state_keys.find("orientation:marked/r%d" % index)
		var model: VoxelBlockyModel = content.library.models[id]
		check(model.get_material_override(0) == shared, "Shared material rotation %d" % index)
		var library: VoxelBlockyLibrary = VoxelBlockyLibrary.new()
		library.models = [VoxelBlockyModelEmpty.new(), model]
		library.bake()
		var buffer: VoxelBuffer = VoxelBuffer.new()
		buffer.create(3, 3, 3)
		buffer.set_voxel(1, 1, 1, 1, VoxelBuffer.CHANNEL_TYPE)
		var mesher: VoxelMesherBlocky = VoxelMesherBlocky.new()
		mesher.library = library
		var mesh: ArrayMesh = mesher.build_mesh(buffer, [])
		var arrays: Array = mesh.surface_get_arrays(0)
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var norm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var correct: bool = true
		for triangle: int in range(0, indices.size(), 3):
			var u: float = (uv[indices[triangle]].x + uv[indices[triangle+1]].x + uv[indices[triangle+2]].x) / 3.0
			var face: int = clampi(int(floor(u*6.0)), 0, 5)
			correct = correct and norm[indices[triangle]].distance_to(bases[index] * normals[face]) < 0.0001 # Engine octahedral normal quantization.
		check(correct, "Mesh normals and canonical face mapping %d" % index)
	content.bundle.shutdown()
	print("CONTENT_ORIENTATION_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
