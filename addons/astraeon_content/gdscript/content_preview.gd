@tool
extends VBoxContainer
## Isolated preview: the current compiler, native mesher and production shader bindings.
const Compiler = preload("res://tools/content/compiler.gd")
const Builder = preload("res://game/shading/blocks/gdscript/compiled_block_builder.gd")
var viewport: SubViewport
var container: SubViewportContainer
var world: Node3D
var model_root: Node3D
var stage_floor: MeshInstance3D
var camera: Camera3D
var caption: Label
var cracks: OptionButton
var states: OptionButton
var icon: TextureRect
var icon_back: PanelContainer
var bundle: AstraeonContentBundle
var pending: AstraeonContentManifest
var record: Dictionary = {}
var hashes: PackedStringArray = []
var preview_kind: String = ""
var icon_hash: String = ""
var due: int = 0
var deadline: int = 0
var busy: bool = false
var generation: int = 0
var yaw: float = 0.65
var pitch: float = -0.35
var distance: float = 3.5
var pan_offset: Vector3 = Vector3.ZERO
var water_clock: float = 0.0
var wave_speed: float = 1.0
var paused: bool = false
var water_material: ShaderMaterial
var light_pages: Texture2DArray
var light_table: ImageTexture
var temporary: String = ""

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	temporary = "res://tmp/content/editor/" + str(get_instance_id()) + "/preview.aebpack"
	var controls: HFlowContainer = HFlowContainer.new()
	add_child(controls)
	for face: String in ["透视", "上", "下", "前", "后", "左", "右"]:
		var button: Button = Button.new()
		button.text = face
		button.pressed.connect(view_face.bind(face))
		controls.add_child(button)
	states = OptionButton.new()
	states.item_selected.connect(func(_index: int) -> void: draw_record())
	controls.add_child(states)
	cracks = OptionButton.new()
	cracks.add_item("裂纹：关闭")
	for stage: int in range(10): cracks.add_item("裂纹阶段 " + str(stage + 1))
	cracks.item_selected.connect(func(_index: int) -> void: draw_record())
	controls.add_child(cracks)
	var pause: CheckButton = CheckButton.new()
	pause.text = "暂停波纹"
	pause.toggled.connect(func(value: bool) -> void: paused = value)
	controls.add_child(pause)
	container = SubViewportContainer.new()
	container.stretch = true
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.custom_minimum_size = Vector2(180, 180)
	add_child(container)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	container.gui_input.connect(orbit)
	world = Node3D.new()
	viewport.add_child(world)
	model_root = Node3D.new()
	world.add_child(model_root)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.near = 0.02
	# Production shaders reserve layer 20 as a planar-reflection capture marker.
	camera.cull_mask = 1
	update_camera()
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_SKY
	environment.environment.sky = Sky.new()
	var sky: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	environment.environment.sky.sky_material = sky
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	world.add_child(sun)
	icon_back = PanelContainer.new()
	icon_back.custom_minimum_size = Vector2(120,120)
	icon_back.visible = false
	add_child(icon_back)
	# Checker is a UI background only, unrelated to the content texture compiler.
	var checker: StyleBoxFlat = StyleBoxFlat.new()
	checker.bg_color = Color(0.22,0.22,0.24)
	icon_back.add_theme_stylebox_override("panel", checker)
	var checker_grid: GridContainer = GridContainer.new()
	checker_grid.columns = 12
	checker_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_back.add_child(checker_grid)
	for cell: int in range(72):
		var square: ColorRect = ColorRect.new()
		square.color = Color(0.34,0.34,0.36) if (cell % 12 + cell / 12) % 2 else Color(0.23,0.23,0.25)
		square.custom_minimum_size = Vector2(16,16)
		square.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		checker_grid.add_child(square)
	icon = TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_back.add_child(icon)
	caption = Label.new()
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.text = "选择资源以预览 · 中键旋转 / Shift＋中键平移 / 滚轮或 Ctrl＋中键缩放"
	add_child(caption)
	var pixels: Image = Image.create(16,256,false,Image.FORMAT_RGBA8)
	pixels.fill(Color(1,0,0,1))
	light_pages = Texture2DArray.new()
	light_pages.create_from_images([pixels])
	var table: Image = Image.create(2,4,false,Image.FORMAT_RGBA8)
	table.fill(Color(1.0/255.0,0,0,1))
	light_table = ImageTexture.create_from_image(table)

func schedule(input: AstraeonContentManifest, kind: String) -> void:
	pending = input
	preview_kind = kind
	due = Time.get_ticks_msec() + 250

func _process(delta: float) -> void:
	if viewport == null: return
	var active: bool = is_visible_in_tree()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if not active: return
	if pending != null and Time.get_ticks_msec() >= due:
		rebuild()
	if busy:
		bundle.visuals.commit()
		if not bundle.visuals.get_metrics().failures.is_empty():
			fail("视觉载荷读取失败：" + str(bundle.visuals.get_metrics().failures))
		elif bundle.visuals.is_ready(hashes):
			busy = false
			draw_record()
		elif Time.get_ticks_msec() > deadline:
			fail("预览纹理读取超时")
	if water_material != null and not paused:
		water_clock += delta * wave_speed
		water_material.set_shader_parameter("clock", water_clock)

func clear() -> void:
	busy = false
	record.clear()
	water_material = null
	stage_floor = null
	icon.texture = null
	icon_back.hide()
	for child: Node in model_root.get_children():
		model_root.remove_child(child)
		child.queue_free()
	if bundle != null:
		bundle.shutdown()
		bundle = null

func fail(message: String) -> void:
	clear()
	caption.text = message
	states.clear()

func rebuild() -> void:
	var input: AstraeonContentManifest = pending
	pending = null
	clear()
	generation += 1
	var result: Dictionary = Compiler.new().build(input, temporary)
	if result.is_empty():
		fail("编译器未返回有效结果；检查编辑器错误输出。")
		return
	if result.has("error"):
		fail("预览校验失败：" + String(result.error))
		return
	bundle = AstraeonContentBundle.new()
	if not bundle.open(PackedStringArray([temporary])):
		fail(bundle.error)
		return
	hashes.clear()
	for block: Dictionary in bundle.blocks.values():
		record = block
		if not String(block.visual).is_empty(): hashes.append(block.visual)
		if not block.breaking.is_empty(): hashes.append(block.breaking.visual)
	icon_hash = ""
	if not bundle.items.is_empty():
		var item: Dictionary = bundle.items[0]
		icon_hash = item.get("icon", "")
		if not icon_hash.is_empty(): hashes.append(icon_hash)
	states.clear()
	if not record.is_empty():
		for state: Dictionary in record.states: states.add_item(String(state.name))
		if record.kind == "water":
			distance = 6.0
			wave_speed = float(record.water.wave_speed)
		else: distance = 3.5
	states.visible = states.item_count > 1
	cracks.visible = not record.is_empty() and not record.breaking.is_empty()
	update_camera()
	if not bundle.visuals.request("editor-preview", hashes):
		fail("预览纹理请求失败")
		return
	deadline = Time.get_ticks_msec() + 10000
	busy = true
	caption.text = "正在读取当前资源的编译载荷…"

func draw_record() -> void:
	for child: Node in model_root.get_children():
		model_root.remove_child(child)
		child.queue_free()
	water_material = null
	icon_back.visible = preview_kind in ["item", "paired"]
	container.visible = not record.is_empty()
	if not icon_hash.is_empty(): icon.texture = bundle.visuals.texture(icon_hash)
	if icon_back.visible and icon_hash.is_empty():
		var item: Dictionary = bundle.items[0]
		var color: Array = item.color
		icon.modulate = Color.WHITE
		var gradient: GradientTexture1D = GradientTexture1D.new()
		gradient.gradient = Gradient.new()
		gradient.gradient.colors = PackedColorArray([Color(color[0],color[1],color[2],color[3]),Color(color[0],color[1],color[2],color[3])])
		icon.texture = gradient
	else: icon.modulate = Color.WHITE
	if record.is_empty():
		caption.text = "物品图标 · 棋盘背景显示透明区域"
		return
	if record.kind == "water":
		draw_water()
	else:
		var state: Dictionary = record.states[maxi(states.selected,0)]
		var model: VoxelBlockyModelCube = Builder.block(record,int(state.rotation),bundle.visuals)
		var material: ShaderMaterial = model.get_material_override(0)
		material.set_shader_parameter("light_pages_0", light_pages)
		material.set_shader_parameter("light_page_table", light_table)
		material.set_shader_parameter("light_table_origin", Vector3(-1,-1,-1))
		material.set_shader_parameter("light_table_size", Vector3(2,2,2))
		material.set_shader_parameter("light_page_layers", 1)
		material.set_shader_parameter("light_page_shift", 0)
		material.set_shader_parameter("ambient_minimum", 0.2)
		material.set_shader_parameter("wind_enabled", false)
		if not record.breaking.is_empty():
			var tint: Array = record.breaking.tint
			material.set_shader_parameter("breaking_texture", bundle.visuals.texture(record.breaking.visual))
			material.set_shader_parameter("breaking_stage", cracks.selected - 1)
			material.set_shader_parameter("breaking_target", Vector3.ZERO)
			material.set_shader_parameter("breaking_tint", Color(tint[0],tint[1],tint[2],tint[3]))
			material.set_shader_parameter("breaking_strength", record.breaking.strength)
		var library: VoxelBlockyLibrary = VoxelBlockyLibrary.new()
		library.models = [VoxelBlockyModelEmpty.new(),model]
		library.bake()
		var buffer: VoxelBuffer = VoxelBuffer.new()
		buffer.create(3,3,3)
		buffer.set_voxel(1,1,1,1,VoxelBuffer.CHANNEL_TYPE)
		var mesher: VoxelMesherBlocky = VoxelMesherBlocky.new()
		mesher.library = library
		var mesh: MeshInstance3D = MeshInstance3D.new()
		mesh.mesh = mesher.build_mesh(buffer, [])
		mesh.position = Vector3.ZERO
		model_root.add_child(mesh)
		stage_floor = box(Vector3(4,0.1,4),Vector3(0.5,-0.1,0.5))
		if record.has("light") and float(record.light.energy) > 0:
			var lamp: OmniLight3D = OmniLight3D.new()
			var color: Array = record.light.color
			lamp.light_color = Color(color[0],color[1],color[2])
			lamp.light_energy = record.light.energy
			lamp.omni_range = record.light.range
			lamp.omni_attenuation = record.light.attenuation
			var offset: Array = state.get("light_offset",record.light.offset)
			lamp.position = Vector3(0.5,0.5,0.5) + Vector3(offset[0],offset[1],offset[2])
			lamp.light_size = float(record.light.radius)
			model_root.add_child(lamp)
	update_camera()
	caption.text = "当前资源 · 固定灯光 / 曝光 · 中键旋转 / Shift＋中键平移 / 滚轮或 Ctrl＋中键缩放"

func draw_water() -> void:
	water_material = ShaderMaterial.new()
	water_material.shader = preload("res://game/shading/shaders/water.gdshader")
	var appearance: AstraeonWaterAppearance = AstraeonWaterAppearance.new()
	for key: String in record.water:
		var value: Variant = record.water[key]
		if value is Array: value = Color(value[0],value[1],value[2],value[3])
		appearance.set(key,value)
	for key: StringName in appearance.surface_parameters(): water_material.set_shader_parameter(key,appearance.surface_parameters()[key])
	water_material.set_shader_parameter("water_bounds_min",Vector3(-2,-2,-2))
	water_material.set_shader_parameter("water_bounds_max",Vector3(2,0,2))
	var plane: MeshInstance3D = MeshInstance3D.new()
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = Vector2(4,4)
	mesh.subdivide_width = 16
	mesh.subdivide_depth = 16
	plane.mesh = mesh
	plane.material_override = water_material
	model_root.add_child(plane)
	box(Vector3(2,0.2,4),Vector3(-1,-0.6,0))
	box(Vector3(2,0.2,4),Vector3(1,-1.9,0))
	for z: float in [-2.1,2.1]: box(Vector3(4.4,2,0.2),Vector3(0,-1,z))
	for x: float in [-2.1,2.1]: box(Vector3(0.2,2,4.4),Vector3(x,-1,0))

func box(dimensions: Vector3, position: Vector3) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	node.mesh = mesh
	node.position = position
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.5,0.52,0.55)
	material.roughness = 0.9
	node.material_override = material
	model_root.add_child(node)
	return node

func view_face(face: String) -> void:
	pan_offset = Vector3.ZERO
	match face:
		"上": pitch = -PI/2.0+0.01; yaw = 0
		"下": pitch = PI/2.0-0.01; yaw = 0
		"前": pitch = 0; yaw = PI
		"后": pitch = 0; yaw = 0
		"左": pitch = 0; yaw = -PI/2.0
		"右": pitch = 0; yaw = PI/2.0
		_: pitch = -0.35; yaw = 0.65
	update_camera()

## Blender-style navigation is scoped to the preview's GUI input, never global editor input.
func orbit(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		if event.shift_pressed:
			# Keep screen-space panning consistent at different zooms and panel sizes.
			var span: float = 2.0 * distance * tan(deg_to_rad(camera.fov) * 0.5)
			var pixels: float = container.size.y if camera.keep_aspect == Camera3D.KEEP_HEIGHT else container.size.x
			pan_offset += (-camera.basis.x * event.relative.x + camera.basis.y * event.relative.y) * span / maxf(pixels, 1.0)
		elif event.ctrl_pressed:
			distance = clampf(distance * exp(event.relative.y * 0.01), 1.2, 15.0)
		else:
			yaw -= event.relative.x * 0.01
			pitch = clampf(pitch - event.relative.y * 0.01, -1.55, 1.55)
		update_camera()
		container.accept_event()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			container.accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var direction: float = 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			distance = clampf(distance * pow(0.9, direction * event.factor), 1.2, 15.0)
			update_camera()
			container.accept_event()

func update_camera() -> void:
	var target: Vector3 = Vector3.ZERO if record.is_empty() or record.get("kind", "") == "water" else Vector3(0.5,0.5,0.5)
	target += pan_offset
	camera.position = target + Vector3(sin(yaw)*cos(pitch),-sin(pitch),cos(yaw)*cos(pitch))*distance
	camera.look_at(target)
	if is_instance_valid(stage_floor): stage_floor.visible = pitch <= 0.0

func _exit_tree() -> void:
	if bundle != null: bundle.shutdown()
