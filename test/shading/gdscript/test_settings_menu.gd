extends "res://test/shading/gdscript/test_lighting_modules.gd"
## Exercise real menu signals, scheme-dependent rows and rendered lamp brightness.
func _render_checks() -> void:
	_render = SubViewport.new()
	_render.size = Vector2i(1920, 1080)
	_render.own_world_3d = true
	_render.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_render)
	var display: TextureRect = TextureRect.new()
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.texture = _render.get_texture()
	root.add_child(display)
	var scene: PackedScene = load("res://test/shading/scenes/shading_sample.tscn")
	_sample = scene.instantiate() as Sample
	_sample.settings_path = _output.path_join("sample-settings.cfg")
	_render.add_child(_sample)
	_sample._reset_settings()
	for node: Node in _sample._panel.get_children():
		if node is Button:
			(node as Button).pressed.emit()
			break
	await _settle()
	var panel: RefCounted = _sample._settings_panel
	_check(_sample._controls.find_children("*", "CheckButton", true, false).is_empty(), "No standalone effect toggle buttons")
	for property: Dictionary in _sample._settings.settings_properties():
		_check(panel.widgets.has(StringName(property.name)), "Current setting represented: " + str(property.name))
	_sample._view(Vector3(23, -2, -14), Vector3(25, -2, -22))
	_choose(&"water_enabled", 0)
	_check(not _sample._underwater and not _sample._planar._valid, "Water off stops underwater and planar capture")
	_sample._view(Vector3(23,17,27), Vector3(0,4,0))
	panel.show_setting(&"water_reflection_mode")
	_check(not panel.rows[&"water_reflection_mode"].visible, "Water off hides reflection selection")
	_choose(&"water_enabled", 1)
	_check(_sample._settings.water_enabled and _sample._settings.water_quality == 0, "Uniform water combined selection")
	_check(panel.rows[&"water_low_opacity"].visible and not panel.rows[&"water_absorption"].visible, "Only uniform water controls exposed")
	_choose(&"water_enabled", 2)
	_check(panel.rows[&"water_absorption"].visible and not panel.rows[&"water_low_opacity"].visible, "Only absorption controls exposed")
	_choose(&"water_reflection_mode", 1)
	_check(panel.rows[&"water_ssr_steps"].visible and not panel.rows[&"planar_strength"].visible, "SSR hides planar settings")
	await _capture("menu-water-ssr")
	_choose(&"water_reflection_mode", 2)
	_check(not panel.rows[&"water_ssr_steps"].visible and panel.rows[&"planar_strength"].visible, "Planar hides SSR settings")
	await _capture("menu-water-planar")
	_choose(&"water_reflection_mode", 0)
	_check(not panel.rows[&"water_ssr_steps"].visible and not panel.rows[&"planar_strength"].visible, "Reflection off hides both implementations")
	_choose(&"clouds_enabled", 1)
	_check(_sample._block_clouds.visible and not _sample._settings.block_cloud_shadows, "Cloud without shadow")
	_check(not panel.rows[&"cloud_shadow_strength"].visible, "Cloud shadow parameters hidden")
	_choose(&"clouds_enabled", 2)
	_check(panel.rows[&"cloud_shadow_strength"].visible, "Cloud shadow parameters shown")
	await _capture("menu-clouds")
	_choose(&"clouds_enabled", 0)
	_check(not _sample._block_clouds.visible and not panel.rows[&"cloud_coverage"].visible, "Cloud off hides mesh and parameters")
	_check(not FileAccess.file_exists("res://astraeon_lighting/sample_sky.gdshader"), "Raymarched cloud shader removed")
	_choose(&"avatar_visible", 1)
	_check(_sample._avatar.visible and not _sample._settings.avatar_animate and not panel.rows[&"avatar_speed"].visible, "Static avatar selection")
	_choose(&"avatar_visible", 2)
	_check(panel.rows[&"avatar_speed"].visible, "Animated avatar settings")
	_choose(&"local_lighting_mode", 0)
	_check(not panel.rows[&"local_light_energy"].visible and not panel.rows[&"voxel_light_strength"].visible, "Emission-only hides lighting parameters")
	_choose(&"local_lighting_mode", 1)
	_check(panel.rows[&"voxel_light_strength"].visible and not panel.rows[&"local_light_energy"].visible, "Voxel light settings")
	_choose(&"local_lighting_mode", 4)
	_check(panel.rows[&"local_point_budget"].visible and panel.rows[&"local_light_energy"].visible, "Hybrid light settings")
	await _capture("menu-local-hybrid")
	_choose(&"hard_shadows", 1)
	_check(not panel.rows[&"shadow_blur"].visible and not panel.rows[&"shadow_quality"].visible, "Hard shadows hide soft filter settings")
	_choose(&"hard_shadows", 0)
	_check(panel.rows[&"shadow_blur"].visible, "Soft shadows restore filter controls")
	# Render an actual lamp with fixed camera, no direct light, fog, glow or reflections.
	_sample._settings.local_lighting_mode = 0
	_sample._settings.direct_enabled = false
	_sample._settings.fog_enabled = false
	_sample._settings.water_enabled = false
	_sample._settings.bloom_enabled = false
	_sample._settings.avatar_animate = false
	_sample._settings.cycle_enabled = false
	_sample._settings.lamp_emission_color = Color(0.6, 0.3, 0.1)
	_sample._edit({Vector3i(-14, 2, 20): _sample.Volume.LAMP})
	await _settle()
	_sample._view(Vector3(-13.5, 2.5, 24), Vector3(-13.5, 2.5, 20.5))
	panel.show_setting(&"lamp_emission_strength")
	var previous: float = -1.0
	for strength: float in [0.0, 0.5, 1.5, 4.0]:
		(panel.widgets[&"lamp_emission_strength"] as SpinBox).value_changed.emit(strength)
		await _capture("emission-%.1f" % strength)
		var pixel: Color = _render.get_texture().get_image().get_pixel(980, 565)
		var brightness: float = pixel.get_luminance()
		print("EMISSION_PIXEL multiplier=", strength, " luminance=", brightness)
		_check(brightness > previous + 0.01, "Rendered emission increases at %.1f" % strength)
		if strength == 0.0: _check(brightness < 0.01, "Zero emission is black")
		previous = brightness
	# Saved choices rebuild their matching menus, not stale controls.
	var loaded: Profile = Profile.new()
	_check(loaded.load_settings(_sample.settings_path) == OK, "Current format reloads")
	panel.sync(loaded)
	_check((panel.widgets[&"local_lighting_mode"] as OptionButton).selected == 0 and not panel.rows[&"local_point_budget"].visible, "Reload synchronizes selected mode and hidden rows")
	_sample._reset_settings()
	panel.show_setting(&"water_enabled")
	_check((panel.widgets[&"water_enabled"] as OptionButton).selected == 2, "Reset restores combined water mode")
	for size: Vector2i in [Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(3840,2160), Vector2i(2560,1080)]:
		_render.size = size
		await _capture("menu-layout-%dx%d" % [size.x, size.y])
		for key: StringName in panel.rows:
			var row: Control = panel.rows[key]
			if row.is_visible_in_tree():
				_check(row.get_global_rect().end.x <= 430.0, "Setting fits panel width: " + str(key))
	_sample.queue_free()
	await _frames(3)

func _choose(key: StringName, index: int) -> void:
	_sample._settings_panel.show_setting(key)
	(_sample._settings_panel.widgets[key] as OptionButton).item_selected.emit(index)
