extends Node3D
## Opt-in finite lighting lab; does not instantiate terrain in the editor.
const Volume: Script = preload("res://astraeon_lighting/light_volume.gd")
const Fixtures: Script = preload("res://astraeon_lighting/sample_world.gd")
const Sections: Script = preload("res://astraeon_lighting/section_meshes.gd")
const SKY_SHADER: Shader = preload("res://astraeon_lighting/sample_sky.gdshader")
@export var profile: AstraeonLightingProfile
var _settings: AstraeonLightingProfile
var _volume: Volume
var _sections: Sections
var _texture: ImageTexture3D
var _camera: Camera3D
var _sun: DirectionalLight3D
var _environment: Environment
var _sky_material: ShaderMaterial
var _status: Label
var _panel: VBoxContainer
var _controls: VBoxContainer
var _started: bool = false
var _roof_open: bool = false
var _window_open: bool = true
var _lamp_enabled: bool = false
var _batch_enabled: bool = false
var _uploaded_revision: int = -1
var _upload_usec: int = 0
var _image_usec: int = 0
var _update_begin: int = 0
var _converge_usec: int = 0
var _frame_counter: int = 0

func _ready() -> void:
	if profile == null:
		push_error("Lighting sample requires a profile.")
		return
	_settings = profile.duplicate(true) as AstraeonLightingProfile
	_load_settings()
	_make_ui()
	_register_input()

func _make_ui() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	add_child(canvas)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	margin.position = Vector2(20, 20)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	canvas.add_child(margin)
	var background: PanelContainer = PanelContainer.new()
	margin.add_child(background)
	_panel = VBoxContainer.new()
	_panel.custom_minimum_size.x = 350
	background.add_child(_panel)
	var title: Label = Label.new()
	title.text = "ASTRAEON · P0 光照样板"
	_panel.add_child(title)
	_status = Label.new()
	_status.text = "尚未创建体素世界"
	_panel.add_child(_status)
	var start: Button = Button.new()
	start.text = "创建光照样板"
	_panel.add_child(start)
	start.pressed.connect(func() -> void:
		start.hide()
		_start())
	_controls = VBoxContainer.new()
	_panel.add_child(_controls)
	_controls.hide()
	_button("正午", func() -> void: _set_hour(12.0))
	_button("日落", func() -> void: _set_hour(17.6))
	_button("夜间", func() -> void: _set_hour(0.0))
	_toggle("时间推进", _settings.cycle_enabled, func(value: bool) -> void:
		_settings.cycle_enabled = value
		_save_settings())
	_toggle("天空渐变", _settings.sky_enhanced, func(value: bool) -> void:
		_settings.sky_enhanced = value
		_apply_lighting()
		_save_settings())
	_toggle("太阳 / 月亮直射", _settings.direct_enabled, func(value: bool) -> void:
		_settings.direct_enabled = value
		_apply_lighting()
		_save_settings())
	_toggle("实时阴影", _settings.shadows_enabled, func(value: bool) -> void:
		_settings.shadows_enabled = value
		_apply_lighting()
		_save_settings())
	_button("室外观察", func() -> void: _view(Vector3(23, 17, 27), Vector3(0, 4, 0)))
	_button("窗边观察", func() -> void: _view(Vector3(0, 4, 9), Vector3(-1, 4, -3)))
	_button("屋内观察", func() -> void: _view(Vector3(5, 4, 1), Vector3(-3, 3, -4)))
	_button("地下观察", func() -> void: _view(Vector3(-13, -4, 0), Vector3(16, -4, 0)))
	_button("拆除 / 恢复屋顶", _toggle_roof)
	_button("封闭 / 打开窗口", _toggle_window)
	_button("放置 / 移除室内光源", _toggle_lamp)
	_button("放置 / 挖掘 128 方块", _toggle_batch)
	_button("挖掘准星方块", func() -> void: _edit_target(Volume.AIR))
	_button("放置准星方块", func() -> void: _edit_target(Volume.STONE))
	_button("放置准星光源", func() -> void: _edit_target(Volume.LAMP))
	var hint: Label = Label.new()
	hint.text = "右键按住环视 · WASD 移动 · Q/E 升降\nEsc 释放鼠标 · 仅样板操作，不写入存档"
	_controls.add_child(hint)
	var crosshair: Label = Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	canvas.add_child(crosshair)

func _button(title: String, callback: Callable) -> void:
	var button: Button = Button.new()
	button.text = title
	_controls.add_child(button)
	button.pressed.connect(callback)

func _toggle(title: String, value: bool, callback: Callable) -> void:
	var button: CheckButton = CheckButton.new()
	button.text = title
	button.button_pressed = value
	_controls.add_child(button)
	button.toggled.connect(callback)

func _start() -> void:
	if _started:
		return
	_started = true
	_controls.show()
	_volume = Fixtures.create()
	_update_begin = Time.get_ticks_usec()
	_texture = ImageTexture3D.new()
	var blank: Array[Image] = []
	for z: int in range(_volume.size.z):
		blank.append(Image.create_empty(_volume.size.x, _volume.size.y, false, Image.FORMAT_RG8))
	var error: Error = _texture.create(Image.FORMAT_RG8, _volume.size.x, _volume.size.y, _volume.size.z, false, blank)
	if error != OK:
		push_error("Could not allocate lighting texture: %s" % error_string(error))
		_started = false
		_status.text = "光照纹理创建失败"
		return
	_sections = Sections.new()
	_sections.configure(_volume, self, _texture)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.far = 180.0
	_camera.near = 0.05
	add_child(_camera)
	_view(Vector3(23, 17, 27), Vector3(0, 4, 0))
	_sun = DirectionalLight3D.new()
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(_sun)
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = SKY_SHADER
	var sky: Sky = Sky.new()
	sky.sky_material = _sky_material
	_environment.sky = sky
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	environment_node.environment = _environment
	add_child(environment_node)
	_apply_lighting()

func _process(delta: float) -> void:
	if not _started:
		return
	if _settings.cycle_enabled:
		_settings.hour = fposmod(_settings.hour + delta * 24.0 / _settings.day_seconds, 24.0)
		_apply_lighting()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var movement: Vector3 = Vector3(
			Input.get_axis("p0_left", "p0_right"),
			Input.get_axis("p0_down", "p0_up"),
			Input.get_axis("p0_forward", "p0_back"))
		_camera.position += _camera.basis * movement.normalized() * delta * 10.0
	_sections.step()
	if not _volume.is_settled():
		_volume.step(_settings.work_cells, _settings.work_usec)
	# Publish only a converged current revision; edits during work share the queue.
	if _volume.is_settled() and _uploaded_revision != _volume.revision:
		_converge_usec = Time.get_ticks_usec() - _update_begin
		var begin: int = Time.get_ticks_usec()
		var images: Array[Image] = _volume.make_images()
		_image_usec = Time.get_ticks_usec() - begin
		begin = Time.get_ticks_usec()
		_texture.update(images)
		_upload_usec = Time.get_ticks_usec() - begin
		_uploaded_revision = _volume.settled_revision
	_frame_counter += 1
	if _frame_counter % 10 == 0:
		_status.text = ("时间 %.2f · 光照版本 %d/%d\n传播队列 %d · 网格队列 %d\n传播步 %.2f ms · 最近收敛 %.1f ms\n打包 %.2f ms · 上传提交 %.2f ms"
			% [_settings.hour, _uploaded_revision, _volume.revision, _volume.pending_count(),
			_sections.pending_count(), _volume.last_step_usec / 1000.0, _converge_usec / 1000.0,
			_image_usec / 1000.0, _upload_usec / 1000.0])

func _apply_lighting() -> void:
	if _sun == null:
		return
	var solar_angle: float = (_settings.hour - 6.0) * PI / 12.0
	var altitude: float = sin(solar_angle)
	var day: float = smoothstep(-0.12, 0.3, altitude)
	var sunset: float = (1.0 - smoothstep(0.05, 0.5, absf(altitude))) * day
	var moon: bool = altitude < 0.0
	_sun.rotation = Vector3(-solar_angle + (PI if moon else 0.0), -0.5, 0.0)
	_sun.visible = _settings.direct_enabled
	_sun.light_color = Color(0.5, 0.65, 1.0) if moon else Color(1.0, 0.95, 0.83).lerp(Color(1.0, 0.38, 0.12), sunset)
	_sun.light_energy = pow(absf(altitude), 0.4) * (0.08 if moon else 1.8)
	_sun.shadow_enabled = _settings.shadows_enabled and _settings.direct_enabled
	_sun.directional_shadow_max_distance = _settings.shadow_distance
	_environment.tonemap_exposure = _settings.exposure
	_sky_material.set_shader_parameter("enhanced", _settings.sky_enhanced)
	_sky_material.set_shader_parameter("zenith", Color(0.005, 0.009, 0.025).lerp(Color(0.12, 0.32, 0.7), day))
	_sky_material.set_shader_parameter("horizon", Color(0.015, 0.02, 0.045).lerp(Color(0.64, 0.78, 0.95).lerp(Color(0.95, 0.3, 0.12), sunset), day))
	var sky_color: Color = Color(0.025, 0.035, 0.07).lerp(Color(0.42, 0.51, 0.66).lerp(Color(0.48, 0.27, 0.22), sunset), day)
	for material: ShaderMaterial in _sections.materials:
		material.set_shader_parameter("sky_color", sky_color)
		material.set_shader_parameter("block_color", _settings.block_color)
		material.set_shader_parameter("block_energy", _settings.block_energy)
		material.set_shader_parameter("block_curve", _settings.block_curve)

func _set_hour(hour: float) -> void:
	_settings.hour = hour
	_apply_lighting()
	_save_settings()

func _view(position_value: Vector3, target: Vector3) -> void:
	if _camera == null:
		return
	_camera.position = position_value
	_camera.look_at(target)

func _edit(edits: Dictionary[Vector3i, int]) -> void:
	var changed: Array[Vector3i] = _volume.apply_edits(edits)
	if not changed.is_empty():
		_sections.invalidate(changed)
		_update_begin = Time.get_ticks_usec()

func _toggle_roof() -> void:
	_roof_open = not _roof_open
	var edits: Dictionary[Vector3i, int] = {}
	Fixtures.box(edits, Fixtures.ROOF, Volume.AIR if _roof_open else Volume.WOOD)
	_edit(edits)

func _toggle_window() -> void:
	_window_open = not _window_open
	var edits: Dictionary[Vector3i, int] = {}
	Fixtures.box(edits, Fixtures.WINDOW, Volume.AIR if _window_open else Volume.WOOD)
	_edit(edits)

func _toggle_lamp() -> void:
	_lamp_enabled = not _lamp_enabled
	var edits: Dictionary[Vector3i, int] = {Fixtures.LAMP_POSITION: Volume.LAMP if _lamp_enabled else Volume.AIR}
	_edit(edits)

func _toggle_batch() -> void:
	_batch_enabled = not _batch_enabled
	var edits: Dictionary[Vector3i, int] = {}
	Fixtures.box(edits, AABB(Vector3(-20, 2, 18), Vector3(16, 1, 8)), Volume.STONE if _batch_enabled else Volume.AIR)
	_edit(edits)

func _edit_target(value: int) -> void:
	# Small fixed-distance voxel ray for the lab; no collision meshes or player controller.
	var previous: Vector3i = Vector3i(_camera.position.floor())
	for i: int in range(1, 401):
		var p: Vector3i = Vector3i((_camera.position - _camera.basis.z * float(i) * 0.05).floor())
		if _volume.contains(p) and _volume.voxel_at(p) != Volume.AIR:
			var target: Vector3i = p if value == Volume.AIR else previous
			var edits: Dictionary[Vector3i, int] = {target: value}
			_edit(edits)
			return
		previous = p

func _register_input() -> void:
	var bindings: Dictionary[StringName, Key] = {
		&"p0_forward": KEY_W, &"p0_back": KEY_S, &"p0_left": KEY_A,
		&"p0_right": KEY_D, &"p0_down": KEY_Q, &"p0_up": KEY_E, &"p0_release": KEY_ESCAPE}
	for action: StringName in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event: InputEventKey = InputEventKey.new()
			event.physical_keycode = bindings[action]
			InputMap.action_add_event(action, event)
	if not InputMap.has_action("p0_look"):
		InputMap.add_action("p0_look")
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("p0_look", event)

func _unhandled_input(event: InputEvent) -> void:
	if not _started:
		return
	if event.is_action_pressed("p0_release") or event.is_action_released("p0_look"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("p0_look"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_camera.rotation.y -= motion.relative.x * 0.003
		_camera.rotation.x = clampf(_camera.rotation.x - motion.relative.y * 0.003, -1.5, 1.5)

func _load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load("user://settings.cfg") != OK:
		return
	for key: String in ["cycle_enabled", "sky_enhanced", "direct_enabled", "shadows_enabled"]:
		var value: Variant = config.get_value("lighting_p0", key, _settings.get(key))
		if value is bool:
			_settings.set(key, value)
	var hour: Variant = config.get_value("lighting_p0", "hour", _settings.hour)
	if (hour is float or hour is int) and is_finite(float(hour)):
		_settings.hour = fposmod(float(hour), 24.0)

func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load("user://settings.cfg")
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning("Settings unreadable; preserving the existing file.")
		return
	for key: String in ["hour", "cycle_enabled", "sky_enhanced", "direct_enabled", "shadows_enabled"]:
		config.set_value("lighting_p0", key, _settings.get(key))
	error = config.save("user://settings.cfg")
	if error != OK:
		push_warning("Could not save lighting settings: %s" % error_string(error))
