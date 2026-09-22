extends "res://test/shading/gdscript/test_lighting_modules.gd"
func _render_checks() -> void:
	_render = SubViewport.new()
	_render.size = Vector2i(1280,720)
	_render.own_world_3d = true
	_render.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_render)
	_sample = (load("res://test/shading/scenes/shading_sample.tscn") as PackedScene).instantiate() as Sample
	_sample.settings_path = _output.path_join("isolated.cfg")
	_render.add_child(_sample)
	_sample._start()
	_sample._settings.clouds_enabled = false
	_sample._settings.water_reflection_mode = 0
	_sample._settings.hard_shadows = true
	_sample._apply_lighting()
	await _settle()
	_sample._panel.hide()
	_check(_sample._sun.shadow_blur == 1.0, "Hard shadows use a nonzero neutral multiplier")
	_sample._view(Vector3(3,3,13),Vector3(29,1,-16))
	await _capture("hard-fixed-view-2")
	_sample._settings.glass_enabled = true
	_sample._view(Vector3(10,3,20),Vector3(9,1,12))
	for mode: int in range(7):
		_sample._settings.glass_filter_mode = mode
		_sample._apply_lighting()
		await _frames(6)
		_check(_sample._sections.materials[0].get_shader_parameter("glass_filter_mode") == mode, "Filter reaches receiver")
		await _capture("glass-filter-%d" % mode)
	_sample._settings.glass_enabled = false
	_sample._settings.celestial_sun_size = 6.0
	_sample._settings.celestial_moon_size = 6.0
	var sky_energy: float = 0.0
	for hour: float in [10.0,22.0]:
		_sample._set_hour(hour)
		sky_energy = _sample._sun.light_energy
		var eye: Vector3 = Vector3(0,15,0)
		_sample._view(eye,eye+_sample._sun.global_basis.z*100.0)
		for mode: int in range(3):
			_sample._settings.celestial_mode = mode
			_sample._apply_lighting()
			_check(is_equal_approx(_sample._sun.light_energy,sky_energy), "Appearance leaves illumination unchanged")
			await _capture("celestial-%d-hour-%d" % [mode,int(hour)])
	_sample._settings_panel.show_setting(&"celestial_mode")
	_check(_sample._settings_panel.widgets.has(&"glass_filter_mode"), "Filter selector available")
	_check(_sample._settings_panel.widgets.has(&"celestial_mode"), "Celestial selector available")
