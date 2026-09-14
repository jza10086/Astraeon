extends "res://astraeon_lighting/test_lighting_modules.gd"
## Focused rendered regression for ambient gradients and the new cloud branch.

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
	var revision: int = _sample._volume.revision
	var meshes: int = _sample._sections.rebuilt_sections
	_sample._settings.direct_enabled = false
	_sample._settings.local_lights_enabled = false
	_sample._settings.indirect_enabled = false
	_sample._settings.fog_enabled = false
	_sample._settings.block_grid_strength = 0.0
	_sample._settings.ambient_curve = 1.0
	_sample._settings.ambient_smoothing = 0.0
	_sample._view(Vector3(16,-4,-0.5),Vector3(-16,-4,0))
	_sample._apply_lighting()
	await _capture("ambient-nearest")
	_sample._settings.ambient_smoothing = 1.0
	_sample._apply_lighting()
	await _capture("ambient-smooth")
	_sample._settings.ambient_curve = 1.4
	_sample._apply_lighting()
	await _capture("ambient-smooth-curve")
	_sample._settings.block_grid_strength = 1.0
	_sample._apply_lighting()
	await _capture("ambient-smooth-grid")
	_check(_sample._volume.revision == revision and _sample._sections.rebuilt_sections == meshes,"Ambient controls preserve solver and geometry")
	# A fully sealed gallery cannot gain light from smoothing.
	var seal: Dictionary[Vector3i,int] = {}
	_sample.Fixtures.box(seal,AABB(Vector3(15,1,-3),Vector3(3,1,5)),_sample.Volume.STONE)
	_sample._edit(seal)
	await _settle()
	_sample._view(Vector3(16.5,-2,-1.5),Vector3(0,-4,-1.0))
	await _capture("ambient-sealed")
	_check(_sample._volume.light_at(Vector3i(16,-3,-1)).x == 0,"Sealed shaft receives no sky light")
	_sample.Fixtures.box(seal,AABB(Vector3(15,1,-3),Vector3(3,1,5)),_sample.Volume.AIR)
	_sample._edit(seal)
	await _settle()
	_sample._reset_settings()
	_sample._view(Vector3(20,2,25),Vector3(20,30,-20))
	_check(_sample._settings.cloud_type == 1 and _sample._sky_material == _sample._plain_sky_material,"Block branch bypasses raymarch sky")
	_check(_sample._block_clouds.geometry.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Cloud mesh excluded from directional shadow atlas")
	var rebuilds: int = _sample._block_clouds.rebuilds
	await _capture("cloud-blocks")
	_check(_sample._block_clouds.rebuilds == rebuilds,"Cloud movement does not rebuild mesh")
	_sample._settings.cloud_type = 0
	_sample._apply_lighting()
	_check(not _sample._block_clouds.visible and _sample._sky_material == _sample._volume_sky_material,"Realistic branch hides block mesh")
	_check(not _sample._sections.materials[0].get_shader_parameter("cloud_shadow_enabled"),"Realistic branch does not enable block shadows")
	await _capture("cloud-realistic")
	_sample._settings.cloud_type = 1
	_sample._settings.cloud_coverage = 1.0
	_sample._settings.cloud_speed = 0.0
	_sample._settings.cloud_shadow_strength = 0.8
	_sample._settings.cloud_shadow_softness = 0.0
	_sample._apply_lighting()
	_check(_sample._block_clouds.cells.count(1) == 1024,"Full coverage mask matches full mesh")
	_sample._view(Vector3(20,12,25),Vector3(4,0,0))
	await _capture("cloud-shadow-on")
	_sample._settings.block_cloud_shadows = false
	_sample._apply_lighting()
	await _capture("cloud-shadow-off")
	_sample._settings.block_cloud_shadows = true
	_sample._settings.cloud_coverage = 0.45
	_sample._apply_lighting()
	# Find a cloud edge across the small lab so partial projection is observable.
	for step: int in range(512):
		var clock: float = step * 0.5
		var off: Vector2 = Vector2(clock*22.0,clock*7.0)
		var left: Vector2i = Vector2i(((Vector2(-24,0)-off)/24.0).floor())
		var right: Vector2i = Vector2i(((Vector2(24,0)-off)/24.0).floor())
		if _sample._block_clouds.occupied(left.x,left.y) != _sample._block_clouds.occupied(right.x,right.y):
			_sample._cloud_clock = clock
			break
	_sample._settings.cloud_shadow_softness = 0.3
	_sample._apply_lighting()
	await _capture("cloud-shadow-partial")
	_sample._settings.hour = 0.0
	_sample._apply_lighting()
	await _capture("cloud-shadow-moon")
	_sample._settings.cloud_coverage = 0.0
	_sample._apply_lighting()
	_check(_sample._block_clouds.cells.count(1) == 0,"Zero coverage clears mask")
	_sample._settings.clouds_enabled = false
	_sample._apply_lighting()
	_check(_sample._sky_material == _sample._plain_sky_material and not _sample._block_clouds.visible,"Clouds off bypass both branches")
	_check(not _sample._details.water_materials[0].get_shader_parameter("cloud_shadow_enabled"),"Water cloud shadow disabled with cloud module")
	await _capture("cloud-off")
	_sample._reset_settings()
	_sample._settings.cloud_coverage = 1.0
	_sample._settings.direct_enabled = false
	_sample._settings.indirect_enabled = false
	_sample._settings.hard_shadows = true
	_sample._settings.fog_enabled = false
	_sample._settings.ambient_strength = 0.0
	_sample._toggle_lamp()
	_sample._view(Vector3(5,4,1),Vector3(-3,3,-4))
	_sample._apply_lighting()
	await _settle()
	await _capture("local-cloud-shadow-on")
	var with_shadow: Image = _render.get_texture().get_image()
	_sample._settings.block_cloud_shadows = false
	_sample._apply_lighting()
	await _capture("local-cloud-shadow-off")
	var without_shadow: Image = _render.get_texture().get_image()
	var error_sum: float = 0.0
	var count: int = 0
	for y: int in range(180,900,8):
		for x: int in range(500,1800,8):
			var a: Color = with_shadow.get_pixel(x,y)
			var c: Color = without_shadow.get_pixel(x,y)
			error_sum += absf(a.r-c.r)+absf(a.g-c.g)+absf(a.b-c.b)
			count += 3
	_check(error_sum / count < 0.002,"Cloud shadows do not alter local direct illumination")
	_sample._toggle_lamp()
	await _settle()
	_sample._reset_settings()
	_sample._view(Vector3(20,12,25),Vector3(4,0,0))
	var scroll: ScrollContainer = _sample._panel.get_parent() as ScrollContainer
	scroll.ensure_control_visible(_sample._settings_panel.widgets[&"ambient_curve"])
	await _capture("ambient-controls")
	scroll.ensure_control_visible(_sample._settings_panel.widgets[&"cloud_shadow_softness"])
	await _capture("cloud-controls")
	for size: Vector2i in [Vector2i(2560,1440),Vector2i(3840,2160),Vector2i(2560,1080)]:
		_render.size = size
		_render.size_2d_override = Vector2i(roundi(float(size.x)*1080.0/size.y),1080)
		_render.size_2d_override_stretch = true
		await _capture("cloud-layout-%dx%d" % [size.x,size.y])
	_sample._reset_settings()
