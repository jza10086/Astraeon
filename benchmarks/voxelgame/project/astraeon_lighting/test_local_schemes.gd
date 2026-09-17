extends "res://astraeon_lighting/test_lighting_modules.gd"
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
	var scene: PackedScene = load("res://astraeon_lighting/lighting_sample.tscn")
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
	_sample._settings.wave_speed = 0.0
	_sample._settings.cloud_speed = 0.0
	_sample._settings.show_fps = false
	_sample._settings.direct_enabled = false
	_sample._settings.fog_enabled = false
	_sample._settings.ambient_minimum = 0.0
	_sample._view(Vector3(-13,-4,0),Vector3(-17,-4,0))
	_sample._apply_lighting()
	await _capture("ambient-floor-zero")
	var dark: Image = _render.get_texture().get_image()
	var revision: int = _sample._volume.revision
	_sample._settings.ambient_minimum = 0.08
	_sample._apply_lighting()
	await _capture("ambient-floor-raised")
	var bright: Image = _render.get_texture().get_image()
	_check(bright.get_pixel(960,600).get_luminance() > dark.get_pixel(960,600).get_luminance()+0.01,"Minimum ambient lifts dark surfaces")
	_check(_sample._volume.revision == revision,"Minimum ambient leaves propagation unchanged")
	_sample._settings.ambient_minimum = 0.015
	_sample._settings.test_light_count = 16
	_press("放置测试光源（按设置数量）")
	await _settle()
	_check(_sample._local_lights.emitters.size() == 16,"Batch creates requested light count")
	_press("放置测试光源（按设置数量）")
	await _settle()
	_check(_sample._local_lights.emitters.size() == 16,"Repeated batch does not duplicate emitters")
	_sample._settings.hour = 0.0
	_sample._settings.local_point_budget = 3
	_sample._settings.local_shadow_budget = 2
	_sample._view(Vector3(-14,8,31),Vector3(-14,1,20))
	var expected_points: Array[int] = [0,0,16,16,3]
	var expected_shadows: Array[int] = [0,0,16,0,2]
	for mode: int in range(5):
		_sample._settings.local_lighting_mode = mode
		_sample._apply_lighting()
		await _capture("local-scheme-%d" % mode)
		_check(_sample._local_lights.active_points == expected_points[mode],"Point count for mode %d" % mode)
		_check(_sample._local_lights.active_shadows == expected_shadows[mode],"Shadow count for mode %d" % mode)
		var fill: float = _sample._sections.materials[0].get_shader_parameter("indirect_strength")
		_check(is_equal_approx(fill,_sample._settings.effective_block_strength()),"Material uses mode-specific voxel fill")
	_sample._settings.local_point_budget = 0
	_sample._local_lights.apply(_sample._settings)
	_check(_sample._local_lights.active_points == 0 and _sample._local_lights.active_shadows == 0,"Zero hybrid budget disables all point lights")
	# A batch cleanup must preserve intervening user edits.
	var changed_position: Vector3i = _sample._test_lamps_original.keys()[0]
	_sample._edit({changed_position: _sample.Volume.STONE})
	_press("清除测试光源")
	await _settle()
	_check(_sample._local_lights.emitters.is_empty(),"Batch cleanup removes test lights")
	_check(_sample._volume.voxel_at(changed_position) == _sample.Volume.STONE,"Cleanup preserves player edit")
	_sample._edit({changed_position: _sample.Volume.AIR})
	await _settle()
	_sample._settings.local_lighting_mode = 1
	_sample._settings.test_light_count = 32
	_sample._apply_lighting()
	_press("放置测试光源（按设置数量）")
	await _settle()
	_check(_sample._local_lights.emitters.size()==32 and _sample._local_lights.active_points==0,"32-lamp batch works without point lights")
	_press("清除测试光源")
	await _settle()
	_sample._reset_settings()
	_sample._settings.avatar_animate = false
	_sample._settings.wave_speed = 0.0
	_sample._settings.cloud_speed = 0.0
	_sample._settings.show_fps = false
	_sample._apply_lighting()
	_press("人物：岸边反射")
	await _capture("avatar-shore-planar")
	var with_avatar: Image = _sample._planar.viewport.get_texture().get_image()
	_sample._settings.avatar_visible = false
	_sample._apply_lighting()
	await _capture("avatar-hidden-planar")
	var without_avatar: Image = _sample._planar.viewport.get_texture().get_image()
	var different: int = 0
	for y: int in range(0,with_avatar.get_height(),3):
		for x: int in range(0,with_avatar.get_width(),3):
			var a: Color = with_avatar.get_pixel(x,y)
			var b: Color = without_avatar.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > 0.05:
				different += 1
	_check(different > 20,"Avatar contributes visible pixels to planar capture")
	_sample._settings.avatar_visible = true
	_sample._apply_lighting()
	_press("人物：涉水反射")
	await _capture("avatar-wading-planar")
	_sample._settings.water_reflection_mode = 1
	_sample._apply_lighting()
	await _capture("avatar-wading-ssr")
	_sample._settings.avatar_animate = true
	_sample._settings.water_reflection_mode = 2
	_sample._apply_lighting()
	var before: Vector3 = _sample._avatar.position
	await _frames(30)
	_check(not before.is_equal_approx(_sample._avatar.position),"Avatar animates and moves")
	await _capture("avatar-wading-moving")
	_sample._settings.avatar_animate = false
	_sample._apply_lighting()
	before = _sample._avatar.position
	await _frames(10)
	_check(before.is_equal_approx(_sample._avatar.position),"Animation disable freezes pose")
	for property: Dictionary in _sample._settings.settings_properties():
		_check(_sample._settings_panel.widgets.has(StringName(property.name)),"Setting has control: "+str(property.name))
	var spin: SpinBox = _sample._settings_panel.widgets[&"ambient_minimum"] as SpinBox
	spin.value_changed.emit(0.035)
	var mode_control: OptionButton = _sample._settings_panel.widgets[&"local_lighting_mode"] as OptionButton
	mode_control.item_selected.emit(4)
	var loaded: AstraeonLightingProfile = AstraeonLightingProfile.new()
	_check(loaded.load_settings(_sample.settings_path)==OK and loaded.local_lighting_mode==4 and is_equal_approx(loaded.ambient_minimum,0.035),"New settings persist through UI")
	var scroll: ScrollContainer = _sample._panel.get_parent() as ScrollContainer
	_sample._settings_panel.show_setting(&"lamp_emission_strength")
	scroll.ensure_control_visible(_sample._settings_panel.widgets[&"lamp_emission_strength"])
	await _capture("local-mode-controls")
	for size: Vector2i in [Vector2i(2560,1440),Vector2i(3840,2160),Vector2i(2560,1080)]:
		_render.size = size
		await _capture("local-layout-%dx%d" % [size.x,size.y])
	_sample._reset_settings()
	_check(_sample._settings.local_lighting_mode==2 and is_equal_approx(_sample._settings.ambient_minimum,0.015),"New defaults restore")
	_sample.queue_free()
	await _frames(3)

func _press(title: String) -> void:
	for child: Node in _sample._controls.find_children("*", "Button", true, false):
		if child is Button and (child as Button).text == title:
			(child as Button).pressed.emit()
			return
	_check(false,"Missing button: "+title)
