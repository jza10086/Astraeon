extends SceneTree
## Compare the real drop mesh against the terrain's source_color uniform convention.
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
	var content: AstraeonWorldContent = AstraeonWorldContent.new()
	check(content.build(PackedStringArray(["res://game/data/content/packages/astraeon.aebpack"])), "compiled source definitions")
	if not content.error.is_empty():
		printerr(content.error)
		quit(1)
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1440, 900)
	var scene: Node3D = Node3D.new()
	root.add_child(scene)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.13, 0.15, 0.18)
	scene.add_child(environment)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.5
	scene.add_child(camera)
	camera.position = Vector3(0, 0, 12)
	camera.current = true
	var drops: Node3D = load("res://game/entities/dropped_items/gdscript/dropped_items.gd").new()
	var reference_shader: Shader = Shader.new()
	reference_shader.code = "shader_type spatial; render_mode unshaded, cull_disabled; uniform vec4 face_colors[6] : source_color; void fragment() { ALBEDO = face_colors[clamp(int(floor(UV.x*6.0)),0,5)].rgb; }"
	var corrected: Array[MeshInstance3D] = []
	var references: Array[MeshInstance3D] = []
	var old: Array[MeshInstance3D] = []
	var keys: Array[String] = ["astraeon:log", "astraeon:grass", "astraeon:dirt"]
	for row: int in range(keys.size()):
		var record: Dictionary = content.bundle.blocks[keys[row]]
		check(String(record.visual).is_empty(), "pure-color fixture " + keys[row])
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var mesh: Mesh = drops._cube_mesh(material, record.surface.colors, true)
		check(material.vertex_color_is_srgb, "production drop enables sRGB decode")
		var reference: ShaderMaterial = ShaderMaterial.new()
		reference.shader = reference_shader
		var colors: PackedColorArray = []
		for rgba: Array in record.surface.colors:
			colors.append(Color(rgba[0], rgba[1], rgba[2], rgba[3]))
		reference.set_shader_parameter("face_colors", colors)
		var legacy: StandardMaterial3D = material.duplicate() as StandardMaterial3D
		legacy.vertex_color_is_srgb = false
		for column: int in range(3):
			var node: MeshInstance3D = MeshInstance3D.new()
			node.mesh = mesh
			node.material_override = legacy if column == 0 else (material if column == 1 else reference)
			node.scale = Vector3.ONE * 4.0
			node.position = Vector3((column - 1) * 2.6, (1 - row) * 1.9, 0)
			node.rotation = Vector3(0.2, -0.45, 0.0)
			scene.add_child(node)
			if column == 0:
				old.append(node)
			elif column == 1:
				corrected.append(node)
			else:
				references.append(node)
	var title: Label = Label.new()
	title.text = "DROP COLOR CHECK (unlit, same source colors)\nLeft: previous linear interpretation | Middle: corrected sRGB | Right: terrain color convention\nRows: log, grass, dirt"
	title.position = Vector2(24,24)
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)
	for frame: int in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	for row: int in range(3):
		var a: Color = picture.get_pixelv(Vector2i(camera.unproject_position(corrected[row].position)))
		var b: Color = picture.get_pixelv(Vector2i(camera.unproject_position(references[row].position)))
		var before: Color = picture.get_pixelv(Vector2i(camera.unproject_position(old[row].position)))
		var difference: float = maxf(absf(a.r-b.r), maxf(absf(a.g-b.g), absf(a.b-b.b)))
		check(difference < 0.015, "drop matches uniform color, row %d delta %.4f" % [row,difference])
		check(before.get_luminance() > a.get_luminance() * 1.3, "previous material was materially too bright")
		print("COLOR_ROW ", keys[row], " previous=", before, " corrected=",a," reference=",b)
	check(picture.save_png("res://tmp/content/drop_colors.png") == OK, "save actual render")
	drops.free()
	scene.queue_free()
	content.bundle.shutdown()
	await process_frame
	print("DROP_COLORS_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
