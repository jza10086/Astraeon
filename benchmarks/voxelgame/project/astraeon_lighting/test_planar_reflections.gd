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
	_sample._settings.wave_speed = 0.0
	_sample._settings.waves_enabled = false
	_sample._settings.cloud_speed = 0.0
	_sample._settings.show_fps = false
	_sample._settings.fog_enabled = false
	_sample._view(Vector3(20,4,-5),Vector3(20,1,-20))
	_sample._settings.water_reflection_mode = 0
	_sample._apply_lighting()
	await _capture("reflection-off")
	_sample._settings.water_reflection_mode = 2
	_sample._apply_lighting()
	await _capture("planar-on")
	_sample._planar.viewport.get_texture().get_image().save_png(_output.path_join("capture-raw.png"))
	_check(_sample._planar.captures > 0, "Planar capture renders when water visible")
	_check(_sample._planar.viewport.size == Vector2i(960,540), "Half dimensions use quarter pixel count")
	_sample._view(Vector3(20,4,-5),Vector3(20,-8,-20))
	await _capture("planar-offscreen-objects")
	_check(not _sample._camera.is_position_in_frustum(Vector3(20,6,-27)),"Reference object outside main view")
	_check(_sample._planar.camera.is_position_in_frustum(Vector3(20,6,-27)),"Reference object inside mirrored view")
	_sample._settings.water_reflection_mode = 1
	_sample._apply_lighting()
	await _capture("ssr-offscreen-objects")
	_sample._settings.water_reflection_mode = 2
	_sample._apply_lighting()
	_sample._view(Vector3(24,-2,-14),Vector3(24,-2,-22))
	await _capture("planar-underwater")
	_check(not _sample._planar._valid,"Underwater capture disabled")
	_sample._view(Vector3(20,4,-5),Vector3(20,1,-20))
	await _capture("planar-resumed")
	_check(_sample._planar._valid,"Capture resumes above water")
	# All exported settings have visible controls, not hidden preset bundles.
	for property: Dictionary in _sample._settings.settings_properties():
		_check(_sample._settings_panel.widgets.has(StringName(property.name)),"Visible setting " + str(property.name))
	var migrated: AstraeonLightingProfile = AstraeonLightingProfile.new()
	var legacy: ConfigFile = ConfigFile.new()
	legacy.set_value("lighting","water_ssr",true)
	legacy.set_value("lighting","water_ssr_quality",2)
	var legacy_path: String = _output.path_join("legacy.cfg")
	legacy.save(legacy_path)
	migrated.load_settings(legacy_path)
	_check(migrated.water_reflection_mode == 1 and migrated.water_ssr_steps == 64,"Legacy SSR settings migrate")
	legacy.set_value("lighting","water_reflection_mode",2)
	legacy.set_value("lighting","water_ssr_steps",43)
	legacy.save(legacy_path)
	migrated.load_settings(legacy_path)
	_check(migrated.water_reflection_mode == 2 and migrated.water_ssr_steps == 43,"Explicit new parameters override old presets")
	# A bright underwater marker must never enter the capture color buffer.
	var marker: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(3,1,3)
	marker.mesh = box
	var marker_material: ShaderMaterial = ShaderMaterial.new()
	marker_material.shader = preload("res://astraeon_lighting/lamp_surface.gdshader")
	marker_material.set_shader_parameter("lamp_color",Color(1,0,1))
	marker.material_override = marker_material
	marker.position = Vector3(20,-0.5,-19)
	_sample.add_child(marker)
	await _capture("planar-underwater-marker-clipped")
	var clipped: Image = _sample._planar.viewport.get_texture().get_image()
	var magenta: int = 0
	for y: int in range(0,clipped.get_height(),4):
		for x: int in range(0,clipped.get_width(),4):
			var color: Color = clipped.get_pixel(x,y)
			if color.r > 0.5 and color.b > 0.5 and color.g < 0.1:
				magenta += 1
	_check(magenta == 0,"Underwater geometry excluded from capture")
	marker.position.y = 4.0
	await _capture("planar-marker-above-water")
	var above: Image = _sample._planar.viewport.get_texture().get_image()
	magenta = 0
	for y: int in range(0,above.get_height(),4):
		for x: int in range(0,above.get_width(),4):
			var color: Color = above.get_pixel(x,y)
			if color.r > 0.5 and color.b > 0.5 and color.g < 0.1:
				magenta += 1
	_check(magenta > 10,"Same geometry appears above water")
	marker.queue_free()
	# Test the scheduler with controlled delta, independent of device FPS.
	_sample.set_process(false)
	_sample._settings.planar_update_fps = 10
	_sample._planar.apply(_sample._settings,_sample._environment)
	_sample._planar._force = true
	_sample._planar.tick(0.0,_sample._settings)
	var initial: int = _sample._planar.captures
	for i: int in range(20):
		_sample._planar.apply(_sample._settings,_sample._environment)
		_sample._planar.tick(0.025,_sample._settings)
	_check(_sample._planar.captures-initial == 5,"10 Hz scheduler remains capped across environment updates")
	_sample._settings.water_reflection_mode = 0
	_sample._planar.apply(_sample._settings,_sample._environment)
	initial = _sample._planar.captures
	_sample._planar.tick(1.0,_sample._settings)
	_check(_sample._planar.captures == initial and not _sample._planar._valid,"Disabled reflection stops capture")
	_sample._settings.water_reflection_mode = 2
	_sample._settings.planar_update_fps = 0
	_sample._apply_lighting()
	_sample._view(Vector3(20,4,-5),Vector3(20,4,30))
	_sample._planar.tick(1.0,_sample._settings)
	_check(not _sample._planar._valid,"Water outside view pauses capture")
	_sample._settings.planar_visible_only = false
	_sample._planar.tick(1.0,_sample._settings)
	_check(_sample._planar._valid,"Explicit offscreen updating option")
	_sample._settings.planar_visible_only = true
	_sample._view(Vector3(20,4,-5),Vector3(20,1,-20))
	_sample.set_process(true)
	_sample._settings.planar_resolution_scale = 0.25
	_sample._settings.planar_blur_pixels = 2.0
	_sample._settings.planar_reflect_clouds = false
	_sample._settings.planar_reflect_plants = false
	_sample._apply_lighting()
	await _capture("planar-quarter-size-blurred")
	_check(_sample._planar.viewport.size == Vector2i(480,270),"Explicit resolution scale")
	_check((_sample._planar.camera.cull_mask & _sample.PlanarReflection.CLOUD_LAYER) == 0,"Cloud geometry excluded by capture mask")
	_check(not _sample._sections.materials[3].get_shader_parameter("reflection_plants"),"Leaf clipping follows plant option")
	_sample._settings.planar_resolution_scale = 1.0
	_sample._settings.planar_blur_pixels = 0.0
	_sample._settings.planar_distortion = 0.04
	_sample._settings.waves_enabled = true
	_sample._apply_lighting()
	await _capture("planar-full-size-waves")
	_check(_sample._planar.viewport.size == Vector2i(1920,1080),"Full size capture")
	_sample._settings.hour = 0.0
	_sample._apply_lighting()
	await _capture("planar-night")
	_sample._reset_settings()
	_sample._settings.wave_speed = 0.0
	_sample._settings.cloud_speed = 0.0
	_sample._settings.show_fps = false
	_sample._apply_lighting()
	var scroll: ScrollContainer = _sample._panel.get_parent() as ScrollContainer
	scroll.ensure_control_visible(_sample._settings_panel.widgets[&"planar_fog"])
	await _capture("planar-controls")
	for size: Vector2i in [Vector2i(2560,1440),Vector2i(3840,2160),Vector2i(2560,1080)]:
		_render.size = size
		await _capture("planar-layout-%dx%d" % [size.x,size.y])
		_check(_sample._planar.viewport.size == size/2,"Capture follows viewport resize")
	var spin: SpinBox = _sample._settings_panel.widgets[&"planar_update_fps"] as SpinBox
	spin.value_changed.emit(24.0)
	var mode: OptionButton = _sample._settings_panel.widgets[&"water_reflection_mode"] as OptionButton
	mode.item_selected.emit(1)
	var steps: SpinBox = _sample._settings_panel.widgets[&"water_ssr_steps"] as SpinBox
	steps.value_changed.emit(43.0)
	var restored: AstraeonLightingProfile = AstraeonLightingProfile.new()
	_check(restored.load_settings(_sample.settings_path) == OK and restored.planar_update_fps == 24 and restored.water_reflection_mode == 1 and restored.water_ssr_steps == 43,"Arbitrary values persist from real UI bindings")
	_sample._reset_settings()
	_check(_sample._settings.water_reflection_mode == 2 and _sample._settings.planar_update_fps == 0,"Defaults restore explicit parameters")
	_sample.queue_free()
	await _frames(3)
