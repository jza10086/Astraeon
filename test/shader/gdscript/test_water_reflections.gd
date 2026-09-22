extends "res://test/shader/gdscript/test_lighting_modules.gd"
## Water reflection render checks. Uses separate settings and no FPS benchmark.

func _render_checks() -> void:
	_render = SubViewport.new()
	_render.size = Vector2i(1920,1080)
	_render.own_world_3d = true
	_render.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_render)
	var display: TextureRect = TextureRect.new()
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.texture = _render.get_texture()
	root.add_child(display)
	var scene: PackedScene = load("res://test/shader/scenes/shading_sample.tscn")
	_sample = scene.instantiate() as Sample
	_sample.settings_path = _output.path_join("sample-settings.cfg")
	_render.add_child(_sample)
	_sample._reset_settings()
	for node: Node in _sample._panel.get_children():
		if node is Button:
			(node as Button).pressed.emit()
			break
	await _settle()
	_sample._settings.avatar_animate = false
	_sample._settings.cloud_speed = 0.0
	_sample._settings.clouds_enabled = false
	_sample._settings.waves_enabled = false
	_sample._settings.fog_enabled = false
	_sample._settings.water_roughness = 0.0
	_sample._settings.show_fps = false
	_sample._view(Vector3(20, 4, -5), Vector3(20, 1.0, -20))
	_sample._settings.water_reflection_mode = 0
	_sample._apply_lighting()
	await _capture("water-ssr-off")
	var off: Image = _render.get_texture().get_image()
	_sample._settings.water_reflection_mode = 1
	_sample._apply_lighting()
	await _capture("water-ssr-on")
	var on: Image = _render.get_texture().get_image()
	var changed: int = 0
	for y: int in range(500, 950, 4):
		for x: int in range(600, 1600, 4):
			var a: Color = off.get_pixel(x,y)
			var b: Color = on.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > 0.04:
				changed += 1
	_check(changed > 50, "SSR produces visible reflected geometry: %d pixels" % changed)
	_sample._settings.water_ssr_strength = 0.0
	_sample._apply_lighting()
	_check(_sample._details.water_materials[0].shader == Details.WATER_SHADER, "Zero SSR strength bypasses screen color copy")
	await _capture("water-ssr-zero")
	var zero: Image = _render.get_texture().get_image()
	var difference: float = 0.0
	for y: int in range(500,950,8):
		for x: int in range(600,1600,8):
			var a: Color = off.get_pixel(x,y)
			var b: Color = zero.get_pixel(x,y)
			difference += absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
	_check(difference < 0.1, "SSR zero intensity restores baseline pixels")
	_sample._settings.water_ssr_strength = 1.0
	for quality: int in range(3):
		_sample._settings.water_ssr_steps = 16 << quality
		_sample._apply_lighting()
		await _capture("water-quality-%d" % quality)
	_sample._settings.water_quality = 0
	_sample._apply_lighting()
	await _capture("water-uniform-ssr")
	_sample._settings.water_quality = 1
	_sample._settings.water_reflection = false
	_sample._apply_lighting()
	await _capture("water-ssr-without-sky")
	_check(_sample._details.water_materials[0].shader == Details.SSR_SHADER, "SSR independent of sky reflection")
	_sample._reset_settings()
	_sample._settings.avatar_animate = false
	_sample._settings.cloud_speed = 0.0
	_sample._settings.wave_speed = 0.0
	_sample._view(Vector3(20, 4, -5), Vector3(20, 1.0, -20))
	_sample._apply_lighting()
	await _capture("water-default")
	_sample._settings.water_shallow_color = Color(0.05,0.55,0.3)
	_sample._settings.water_absorption = 0.5
	_sample._settings.wave_scale = 1.8
	_sample._settings.water_opacity = 0.6
	_sample._apply_lighting()
	await _capture("water-tuned")
	_sample._settings.underwater_color = Color(0.02,0.2,0.1)
	_sample._settings.underwater_distance = 8.0
	_sample._view(Vector3(23,-2,-14),Vector3(25,-2,-22))
	_sample._apply_lighting()
	await _capture("water-underwater")
	_check(_sample._environment.fog_depth_end == 8.0 and _sample._underwater, "Underwater controls applied")
	_sample._view(Vector3(20,4,-5),Vector3(20,1,-20))
	_sample._settings.hour = 0.0
	_sample._apply_lighting()
	await _capture("water-night")
	_check(not _sample._underwater, "Leaving water restores air")
	_sample._reset_settings()
	_sample._settings.wave_speed = 0.0
	_sample._settings.avatar_animate = false
	_sample._settings.cloud_speed = 0.0
	_sample._apply_lighting()
	var scroll: ScrollContainer = _sample._panel.get_parent() as ScrollContainer
	_sample._settings_panel.show_setting(&"water_reflection_mode")
	scroll.ensure_control_visible(_sample._settings_panel.widgets[&"water_reflection_mode"])
	await _capture("water-controls")
	_sample._settings_panel.show_setting(&"water_ssr_edge_fade")
	scroll.ensure_control_visible(_sample._settings_panel.widgets[&"water_ssr_edge_fade"])
	await _capture("water-ssr-controls")
	for size: Vector2i in [Vector2i(2560,1440),Vector2i(3840,2160),Vector2i(2560,1080)]:
		_render.size = size
		await _capture("water-layout-%dx%d" % [size.x,size.y])
	# Exercise actual panel bindings and persist non-default water controls.
	var picker: ColorPickerButton = _sample._settings_panel.widgets[&"water_shallow_color"] as ColorPickerButton
	picker.color_changed.emit(Color(0.2,0.4,0.6))
	var quality: SpinBox = _sample._settings_panel.widgets[&"water_ssr_steps"] as SpinBox
	quality.value_changed.emit(64.0)
	_check(_sample._settings.water_shallow_color == Color(0.2,0.4,0.6) and _sample._settings.water_ssr_steps == 64,"Color and quality UI bindings")
	var saved: Profile = Profile.new()
	_check(saved.load_settings(_sample.settings_path) == OK and saved.water_shallow_color == Color(0.2,0.4,0.6) and saved.water_ssr_steps == 64,"Non-default water settings persist")
	_sample._reset_settings()
	_check(_sample._settings.water_ssr_steps == 32 and _sample._settings.water_shallow_color == Color(0.06,0.4,0.36),"Water defaults restore")
	_sample.queue_free()
	await _frames(3)
