extends Node3D
## Finite test fixture using the production content table and native block mesher.
const PLAYER: PackedScene = preload("res://game/entities/player/scenes/player.tscn")
var content: AstraeonWorldContent
var player: CharacterMotor
var sun: DirectionalLight3D
var glow_light: OmniLight3D
var status: Label
var mesh_instance: MeshInstance3D
var fixture: VoxelBuffer
var _tool: VoxelTool
const LAMP_CELL: Vector3i = Vector3i(20, 2, 12)

func _ready() -> void:
	content = AstraeonWorldContent.new()
	if not content.build(PackedStringArray(["res://game/data/content/packages/astraeon.aebpack"])):
		push_error("Content sample: catalog compilation failed")
		return
	var hashes: PackedStringArray = []
	for record: Dictionary in content.bundle.blocks.values():
		if not String(record.visual).is_empty():
			hashes.append(record.visual)
	content.bundle.visuals.call("request", "content_preview", hashes)
	while not content.bundle.visuals.call("is_ready", hashes):
		content.bundle.visuals.call("commit")
		await get_tree().process_frame
	# This geometry/appearance preview uses a uniform test light field; full propagation is in shading_sample.
	var layers: Array[Image] = []
	for z: int in range(34):
		var layer: Image = Image.create_empty(34, 18, false, Image.FORMAT_RGBA8)
		layer.fill(Color(1, 0, 1, 1))
		layers.append(layer)
	var light_texture: ImageTexture3D = ImageTexture3D.new()
	light_texture.create(Image.FORMAT_RGBA8, 34, 18, 34, false, layers)
	for model: VoxelBlockyModel in content.library.models:
		if model is VoxelBlockyModelCube:
			preload("res://test/shading/gdscript/light_page_fixture.gd").bind_fixture(model.get_material_override(0), light_texture, Vector3i.ZERO, Vector3i(34, 18, 34))
	fixture = VoxelBuffer.new()
	fixture.create(34, 18, 34)
	fixture.set_channel_depth(VoxelBuffer.CHANNEL_TYPE, VoxelBuffer.DEPTH_16_BIT)
	_tool = fixture.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_tool.mode = VoxelTool.MODE_SET
	_box(Vector3i(1, 1, 1), Vector3i(32, 1, 32), "astraeon:grass/default")
	# Dark booth: roof, back and sides, open front.
	_box(Vector3i(17, 2, 7), Vector3i(25, 7, 7), "astraeon:dirt/default")
	_box(Vector3i(17, 2, 7), Vector3i(17, 7, 15), "astraeon:dirt/default")
	_box(Vector3i(25, 2, 7), Vector3i(25, 7, 15), "astraeon:dirt/default")
	_box(Vector3i(17, 7, 7), Vector3i(25, 7, 15), "astraeon:dirt/default")
	_box(LAMP_CELL, LAMP_CELL, "astraeon:glowstone/default")
	# Leaves: isolated panel and tree canopy, sun casts cutout shadows.
	_box(Vector3i(5, 2, 8), Vector3i(5, 6, 8), "astraeon:log/axis_y")
	_box(Vector3i(3, 6, 6), Vector3i(7, 7, 10), "astraeon:leaves/default")
	_box(Vector3i(8, 3, 14), Vector3i(12, 5, 14), "astraeon:leaves/default")
	_box(Vector3i(4, 2, 19), Vector3i(7, 2, 19), "astraeon:log/axis_x")
	_box(Vector3i(10, 2, 19), Vector3i(10, 2, 22), "astraeon:log/axis_z")
	# Water uses the currently integrated uniform-color fallback, no collision.
	_box(Vector3i(3, 2, 25), Vector3i(12, 2, 30), "astraeon:water/default")
	var mesher: VoxelMesherBlocky = VoxelMesherBlocky.new()
	mesher.library = content.library
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "NativeBlockFixture"
	mesh_instance.mesh = mesher.build_mesh(fixture, [])
	add_child(mesh_instance)
	# Collision generated separately without the no-collision water cells.
	var collision_buffer: VoxelBuffer = VoxelBuffer.new()
	collision_buffer.create(34, 18, 34)
	collision_buffer.set_channel_depth(VoxelBuffer.CHANNEL_TYPE, VoxelBuffer.DEPTH_16_BIT)
	collision_buffer.copy_channel_from(fixture, VoxelBuffer.CHANNEL_TYPE)
	var collision_tool: VoxelTool = collision_buffer.get_voxel_tool()
	collision_tool.channel = VoxelBuffer.CHANNEL_TYPE
	collision_tool.value = 0
	collision_tool.do_box(Vector3i(3, 2, 25), Vector3i(12, 2, 30))
	var collision_mesh: Mesh = mesher.build_mesh(collision_buffer, [])
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = collision_mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)
	_environment()
	_light()
	player = PLAYER.instantiate() as CharacterMotor
	player.position = Vector3(16, 2.2, 23)
	player.get_node("Controller").set("respawn_position", player.position)
	add_child(player)
	_ui()
	print("CONTENT_SHADING_READY: states=%d surfaces=%d" % [content.state_keys.size(), mesh_instance.mesh.get_surface_count()])

func _box(begin: Vector3i, end: Vector3i, key: String) -> void:
	var id: int = content.state_keys.find(key)
	assert(id >= 0, "Missing content " + key)
	_tool.value = id
	_tool.do_box(begin, end)

func _environment() -> void:
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.22, 0.34, 0.5)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.8, 1)
	environment.ambient_light_energy = 0.12
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 2.0
	add_child(sun)

func _light() -> void:
	var id: int = content.state_keys.find("astraeon:glowstone/default")
	var descriptor: AstraeonBlockLightAppearance = content.light_definitions[id]
	glow_light = OmniLight3D.new()
	glow_light.name = "StaticGlowstoneLight"
	glow_light.position = Vector3(LAMP_CELL) - Vector3.ONE * 0.5 + content.light_offsets[id]
	glow_light.light_color = descriptor.color
	glow_light.light_energy = descriptor.energy
	glow_light.omni_range = descriptor.range
	glow_light.omni_attenuation = descriptor.attenuation
	glow_light.shadow_enabled = descriptor.shadow_policy == AstraeonBlockLightAppearance.ShadowPolicy.FOLLOW_GLOBAL
	add_child(glow_light)

func _ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var panel: VBoxContainer = VBoxContainer.new()
	panel.position = Vector2(20, 20)
	layer.add_child(panel)
	var label: Label = Label.new()
	label.text = "数据驱动光影测试 · WASD / 空格 / Esc 释放鼠标\n叶片棋盘裁剪 · 三轴原木 · 白色发光石 · 正式玩家"
	panel.add_child(label)
	var daylight: Button = Button.new()
	daylight.text = "日月直射：开 / 关"
	daylight.pressed.connect(func() -> void: sun.visible = not sun.visible)
	panel.add_child(daylight)
	var lamp: Button = Button.new()
	lamp.text = "发光石照明：开 / 关（表面自发光保留）"
	lamp.pressed.connect(func() -> void: glow_light.visible = not glow_light.visible)
	panel.add_child(lamp)
	status = Label.new()
	panel.add_child(status)

func _process(_delta: float) -> void:
	if status != null:
		status.text = "FPS: %d | 方块状态: %d" % [Engine.get_frames_per_second(), content.state_keys.size()]

func _exit_tree() -> void:
	if content != null and content.bundle != null:
		content.bundle.shutdown()
