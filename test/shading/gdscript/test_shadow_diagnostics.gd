extends "res://test/shading/gdscript/test_lighting_modules.gd"
func _settings_checks() -> void:
	pass
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
	_sample._settings.hour = 12.0
	_sample._settings.hard_shadows = true
	_sample._settings.clouds_enabled = false
	_sample._settings.glass_enabled = false
	_sample._settings.wind_enabled = false
	_sample._settings.water_reflection_mode = 0
	_sample._settings.shadow_resolution = 2
	_sample._apply_lighting()
	await _settle()
	_sample._panel.hide()
	for variant: int in range(4):
		_sample._sun.shadow_blur = 0.0 if variant == 0 else 1.0
		_sample._sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if variant == 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		if variant == 3:
			_sample._settings.clouds_enabled = true
			_sample._settings.water_reflection_mode = 2
			_sample._apply_lighting()
		for view: int in range(4):
			_sample._view(Vector3(3,3,13), Vector3(13 + view * 8, 1, -view * 8))
			await _capture("hard-%d-view-%d" % [variant,view])
