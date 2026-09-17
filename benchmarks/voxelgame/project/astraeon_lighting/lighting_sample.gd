extends Node3D
## Opt-in finite lighting lab; does not instantiate terrain in the editor.
const TestAvatar: Script = preload("res://astraeon_lighting/test_avatar.gd")
const PlanarReflection: Script = preload("res://astraeon_lighting/planar_reflection.gd")
const Volume: Script = preload("res://astraeon_lighting/light_volume.gd")
const Fixtures: Script = preload("res://astraeon_lighting/sample_world.gd")
const Sections: Script = preload("res://astraeon_lighting/section_meshes.gd")
const BlockClouds: Script = preload("res://astraeon_lighting/block_clouds.gd")
const PLAIN_SKY_SHADER: Shader = preload("res://astraeon_lighting/background_sky.gdshader")
const LocalLights: Script = preload("res://astraeon_lighting/local_lights.gd")
const Details: Script = preload("res://astraeon_lighting/environment_details.gd")
const SettingsPanel: Script = preload("res://astraeon_lighting/settings_panel.gd")
@export var profile: AstraeonLightingProfile
@export var settings_path: String = "user://settings.cfg"
var _avatar: TestAvatar
var _test_lamps_original: Dictionary[Vector3i, int] = {}
var _planar: PlanarReflection
var _settings: AstraeonLightingProfile
var _volume: Volume
var _sections: Sections
var _texture: ImageTexture3D
var _camera: Camera3D
var _sun: DirectionalLight3D
var _environment: Environment
var _sky_material: ShaderMaterial
var _block_clouds: BlockClouds
var _settings_notice: String = ""
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
var _details: Details
var _settings_panel: SettingsPanel
var _cloud_clock: float = 0.0
var _underwater: bool = false
var _horizon: Color
var _frame_counter: int = 0
var _local_lights: LocalLights
var _fps_label: Label
var _fps_elapsed: float = 0.0
var _fps_frames: int = 0
var _previous_max_fps: int
var _previous_vsync: DisplayServer.VSyncMode
var _atlas_size: int = -1
var _filter_quality: int = -1

func _ready() -> void:
	if profile == null:
		push_error("Lighting sample requires a profile.")
		return
	_settings = profile.duplicate(true) as AstraeonLightingProfile
	_load_settings()
	_previous_max_fps = Engine.max_fps
	_previous_vsync = DisplayServer.window_get_vsync_mode()
	_make_ui()
	_apply_display()
	_register_input()

func _make_ui() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	add_child(canvas)
	_fps_label = Label.new()
	_fps_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.offset_left = -340
	_fps_label.offset_right = -20
	_fps_label.offset_top = 16
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_fps_label.add_theme_constant_override("shadow_offset_x", 2)
	_fps_label.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(_fps_label)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	margin.offset_left = 20
	margin.offset_right = 430
	margin.offset_top = 20
	margin.offset_bottom = -20
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	canvas.add_child(margin)
	var background: PanelContainer = PanelContainer.new()
	margin.add_child(background)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	background.add_child(scroll)
	_panel = VBoxContainer.new()
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_panel)
	var title: Label = Label.new()
	title.text = "ASTRAEON · 模块化光照样板"
	_panel.add_child(title)
	if not _settings_notice.is_empty():
		var notice: Label = Label.new()
		notice.text = _settings_notice
		notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_panel.add_child(notice)
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
	_button("室外观察", func() -> void: _view(Vector3(23, 17, 27), Vector3(0, 4, 0)))
	_button("窗边观察", func() -> void: _view(Vector3(0, 4, 9), Vector3(-1, 4, -3)))
	_button("屋内观察", func() -> void: _view(Vector3(5, 4, 1), Vector3(-3, 3, -4)))
	_button("地下观察", func() -> void: _view(Vector3(-13, -4, 0), Vector3(16, -4, 0)))
	_button("拆除 / 恢复屋顶", _toggle_roof)
	_button("封闭 / 打开窗口", _toggle_window)
	_button("放置 / 移除室内光源", _toggle_lamp)
	_button("放置 / 挖掘 128 方块", _toggle_batch)
	_button("放置测试光源（按设置数量）", _place_test_lamps)
	_button("清除测试光源", _clear_test_lamps)
	_button("多光源观察", func() -> void: _view(Vector3(-14,8,31),Vector3(-14,1,20)))
	_button("人物：岸边反射", func() -> void:
		_avatar.move_to(Vector3(23,1,-26))
		_view(Vector3(23,3,-12),Vector3(23,1,-25)))
	_button("人物：涉水反射", func() -> void:
		_avatar.move_to(Vector3(23,-0.6,-19))
		_view(Vector3(23,2.5,-11),Vector3(23,0.8,-19)))
	_button("人物：多光源区域", func() -> void:
		_avatar.move_to(Vector3(-14,1,21))
		_view(Vector3(-14,4,30),Vector3(-14,2,21)))
	_button("挖掘准星方块", func() -> void: _edit_target(Volume.AIR))
	_button("放置准星方块", func() -> void: _edit_target(Volume.STONE))
	_button("放置准星光源", func() -> void: _edit_target(Volume.LAMP))
	_button("阶梯 / 窄缝", func() -> void: _view(Vector3(-29, 8, 12), Vector3(-23, 3, 4)))
	_button("洞口环境光观察", func() -> void: _view(Vector3(16, -4, -0.5), Vector3(-16, -4, 0)))
	_button("云层观察", func() -> void: _view(Vector3(20, 2, 25), Vector3(20, 30, -20)))
	_button("水池观察", func() -> void: _view(Vector3(30, 10, -5), Vector3(20, 0, -17)))
	_button("水面倒影观察", func() -> void: _view(Vector3(20, 4, -5), Vector3(20, 1, -20)))
	_button("水下观察", func() -> void: _view(Vector3(23, -2, -14), Vector3(25, -2, -22)))
	_button("逆光植被", func() -> void: _view(Vector3(-27, 2, -9), Vector3(-20, 3, -20)))
	_button("夜间光源", func() -> void:
		_set_hour(0.0)
		if not _lamp_enabled:
			_toggle_lamp()
		_view(Vector3(5, 4, 1), Vector3(-3, 3, -4)))
	var actions: VBoxContainer = VBoxContainer.new()
	for child: Node in _controls.get_children():
		_controls.remove_child(child)
		actions.add_child(child)
	var page: OptionButton = OptionButton.new()
	page.add_item("参数设置")
	page.add_item("场景操作与观察")
	_controls.add_child(page)
	var parameters: VBoxContainer = VBoxContainer.new()
	_controls.add_child(parameters)
	_controls.add_child(actions)
	actions.hide()
	page.item_selected.connect(func(index: int) -> void:
		parameters.visible = index == 0
		actions.visible = index == 1)
	_settings_panel = SettingsPanel.new()
	_settings_panel.build(parameters, _settings, _settings_changed)
	var reset: Button = Button.new()
	reset.text = "恢复默认设置"
	reset.pressed.connect(_reset_settings)
	_controls.add_child(reset)
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
		blank.append(Image.create_empty(_volume.size.x, _volume.size.y, false, Image.FORMAT_RGBA8))
	var error: Error = _texture.create(Image.FORMAT_RGBA8, _volume.size.x, _volume.size.y, _volume.size.z, false, blank)
	if error != OK:
		push_error("Could not allocate lighting texture: %s" % error_string(error))
		_started = false
		_status.text = "光照纹理创建失败"
		return
	_sections = Sections.new()
	_sections.configure(_volume, self, _texture)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.far = 1600.0 # Cloud mesh horizon; directional shadow distance remains independent.
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
	_sky_material.shader = PLAIN_SKY_SHADER
	var sky: Sky = Sky.new()
	sky.sky_material = _sky_material
	_environment.sky = sky
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	environment_node.environment = _environment
	add_child(environment_node)
	_details = Details.new()
	add_child(_details)
	_details.configure(_texture, _volume.origin, _volume.size)
	_avatar = TestAvatar.new()
	add_child(_avatar)
	_avatar.configure(_texture, _volume.origin, _volume.size)
	_local_lights = LocalLights.new()
	add_child(_local_lights)
	_local_lights.configure(_volume)
	_block_clouds = BlockClouds.new()
	add_child(_block_clouds)
	var receivers: Array[ShaderMaterial] = _sections.materials.duplicate()
	receivers.append(_details.grass_material)
	receivers.append_array(_details.marker_materials)
	receivers.append_array(_avatar.materials)
	receivers.append_array(_details.water_materials)
	_block_clouds.configure(receivers)
	_planar = PlanarReflection.new()
	add_child(_planar)
	var clips: Array[ShaderMaterial] = _sections.materials.duplicate()
	clips.append_array(_details.marker_materials)
	clips.append_array(_avatar.materials)
	clips.append(_details.grass_material)
	clips.append(_local_lights._material)
	_planar.configure(_camera, _details.water_materials, clips)
	_apply_lighting()

func _process(delta: float) -> void:
	if _settings == null:
		return
	if _settings.show_fps:
		_fps_elapsed += delta
		_fps_frames += 1
		if _fps_elapsed >= 0.5:
			_fps_label.text = "%.0f FPS · %.2f ms\n上限 %s · VSync %s" % [float(_fps_frames) / _fps_elapsed, _fps_elapsed * 1000.0 / _fps_frames, str(_settings.max_fps) if _settings.max_fps > 0 else "不限", "开" if _settings.vsync_enabled else "关"]
			_fps_elapsed = 0.0
			_fps_frames = 0
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
	_avatar.tick(delta, _settings)
	_local_lights.tick(delta, _settings, _camera.global_position)
	_details.tick(delta, _settings, _sections.materials[3])
	if _settings.clouds_enabled and _settings.cloud_speed > 0.0:
		_cloud_clock += delta * _settings.cloud_speed
	_block_clouds.tick(_cloud_clock, _camera.position)
	var wet: bool = _settings.water_enabled and _details.is_underwater(_camera.position) and _settings.underwater_enabled
	if wet != _underwater:
		_underwater = wet
		_apply_fog()
	_planar.tick(delta, _settings)
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
		_status.text += "\n光源方块 %d · 点光源 %d · 阴影灯 %d" % [_local_lights.emitters.size(), _local_lights.active_points, _local_lights.active_shadows]
		if _settings.water_reflection_mode == 2:
			_status.text += "\n平面反射 %d×%d · %s · %s" % [_planar.viewport.size.x, _planar.viewport.size.y, "每帧" if _settings.planar_update_fps == 0 else "%d Hz 上限" % _settings.planar_update_fps, "更新中" if _planar._valid else "暂停"]

func _apply_lighting() -> void:
	_apply_display()
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
	_apply_modules(sky_color, Color(0.015, 0.02, 0.045).lerp(Color(0.64, 0.78, 0.95).lerp(Color(0.95, 0.3, 0.12), sunset), day))

func _set_hour(hour: float) -> void:
	_settings.hour = hour
	_settings_panel.sync(_settings)
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
		_local_lights.sync_edits(changed)
		_local_lights.apply(_settings)
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
	var error: Error = _settings.load_settings(settings_path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		_settings_notice = "设置格式不支持或读取失败，已使用默认值。\n调整设置后保存当前格式。"
		push_warning("Unsupported or invalid lighting settings; using defaults: " + error_string(error))

func _save_settings() -> void:
	var error: Error = _settings.save_settings(settings_path)
	if error != OK:
		push_warning("Could not save lighting settings: %s" % error_string(error))

func _settings_changed() -> void:
	_apply_lighting()
	_save_settings()

func _reset_settings() -> void:
	_settings = profile.duplicate(true) as AstraeonLightingProfile
	_settings_panel.sync(_settings)
	_apply_lighting()
	_save_settings()

func _apply_modules(sky_color: Color, horizon: Color) -> void:
	_settings_panel.sync(_settings)
	_horizon = horizon
	_block_clouds.apply(_settings, horizon, _sun.global_basis.z.normalized())
	_block_clouds.tick(_cloud_clock, _camera.position)
	get_viewport().use_taa = _settings.aa_mode == 2
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if _settings.aa_mode == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	_sun.shadow_bias = _settings.shadow_bias
	_sun.shadow_normal_bias = _settings.shadow_normal_bias
	_sun.directional_shadow_blend_splits = true
	_sun.shadow_blur = 0.0 if _settings.hard_shadows else _settings.shadow_blur
	var qualities: Array[RenderingServer.ShadowQuality] = [
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_ULTRA]
	var quality: int = RenderingServer.SHADOW_QUALITY_HARD if _settings.hard_shadows else qualities[_settings.shadow_quality]
	if quality != _filter_quality:
		RenderingServer.directional_soft_shadow_filter_set_quality(quality)
		RenderingServer.positional_soft_shadow_filter_set_quality(quality)
		_filter_quality = quality
	var atlas: int = 1024 << _settings.shadow_resolution
	if atlas != _atlas_size:
		RenderingServer.directional_shadow_atlas_set_size(atlas, false)
		_atlas_size = atlas
	_local_lights.apply(_settings)
	_environment.glow_enabled = _settings.bloom_enabled
	_environment.glow_intensity = _settings.bloom_strength
	_environment.glow_hdr_threshold = 1.0
	var materials: Array[ShaderMaterial] = _sections.materials.duplicate()
	materials.append(_details.grass_material)
	materials.append_array(_details.marker_materials)
	materials.append_array(_avatar.materials)
	for material: ShaderMaterial in materials:
		material.set_shader_parameter("ambient_smoothing", _settings.ambient_smoothing)
		material.set_shader_parameter("ambient_strength", _settings.ambient_strength)
		material.set_shader_parameter("ambient_minimum", _settings.ambient_minimum)
		material.set_shader_parameter("ambient_minimum_color", _settings.ambient_minimum_color)
		material.set_shader_parameter("ambient_curve", _settings.ambient_curve)
		material.set_shader_parameter("block_grid_strength", _settings.block_grid_strength)
		material.set_shader_parameter("indirect_strength", _settings.effective_block_strength())
		material.set_shader_parameter("ao_strength", _settings.ao_strength if _settings.ao_enabled else 0.0)
		material.set_shader_parameter("sky_color", sky_color)
		material.set_shader_parameter("block_color", _settings.block_color)
		material.set_shader_parameter("block_energy", _settings.block_energy)
		material.set_shader_parameter("block_curve", _settings.block_curve)
	for material: ShaderMaterial in [_sections.materials[3], _details.grass_material]:
		material.set_shader_parameter("wind_enabled", _settings.wind_enabled)
		material.set_shader_parameter("wind_strength", _settings.wind_strength)
		material.set_shader_parameter("translucency", _settings.translucency_strength if _settings.translucency_enabled else 0.0)
	_avatar.apply(_settings)
	_details.apply(_settings, sky_color, horizon)
	_underwater = _settings.water_enabled and _details.is_underwater(_camera.position) and _settings.underwater_enabled
	_apply_fog()
	if _planar != null:
		_planar.apply(_settings, _environment)

func _apply_fog() -> void:
	_environment.fog_enabled = _settings.fog_enabled or _underwater
	_environment.fog_mode = Environment.FOG_MODE_DEPTH
	_environment.fog_light_color = _settings.underwater_color if _underwater else _horizon
	_environment.fog_light_energy = 0.6 if _underwater else 1.0
	_environment.fog_sky_affect = 1.0 if _underwater else 0.0
	_environment.fog_depth_begin = 0.0 if _underwater else _settings.fog_start
	_environment.fog_depth_end = _settings.underwater_distance if _underwater else _settings.fog_start + 1.0 / _settings.fog_density
	_environment.fog_depth_curve = 1.0

func _apply_display() -> void:
	Engine.max_fps = _settings.max_fps
	var mode: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED if _settings.vsync_enabled else DisplayServer.VSYNC_DISABLED
	if DisplayServer.window_get_vsync_mode() != mode:
		DisplayServer.window_set_vsync_mode(mode)
	if _fps_label != null:
		_fps_label.visible = _settings.show_fps

func _exit_tree() -> void:
	if _settings != null:
		Engine.max_fps = _previous_max_fps
		DisplayServer.window_set_vsync_mode(_previous_vsync)

## Dedicated fixed-layout lamp batch. Restore only cells still owned by this test batch.
func _clear_test_lamps() -> void:
	var edits: Dictionary[Vector3i,int] = {}
	for p: Vector3i in _test_lamps_original:
		if _volume.voxel_at(p) == Volume.LAMP:
			edits[p] = _test_lamps_original[p]
	_test_lamps_original.clear()
	if not edits.is_empty():
		_edit(edits)

func _place_test_lamps() -> void:
	_clear_test_lamps()
	var edits: Dictionary[Vector3i,int] = {}
	for i: int in range(_settings.test_light_count):
		@warning_ignore("integer_division")
		var p: Vector3i = Vector3i(-25 + (i % 8)*3,1,15 + (i / 8)*4)
		_test_lamps_original[p] = _volume.voxel_at(p)
		edits[p] = Volume.LAMP
	_edit(edits)
