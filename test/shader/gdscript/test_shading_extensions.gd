extends "res://test/shader/gdscript/test_lighting_modules.gd"
## Short functional/render checks; no FPS measurements or one-hour suite.
const Palette: Script = preload("res://game/shading/gdscript/day_palette.gd")
const Budget: Script = preload("res://game/shading/gdscript/light_budget.gd")
func _settings_checks() -> void:
	super._settings_checks()
	var p: Profile = Profile.new()
	var old: ConfigFile = ConfigFile.new()
	var file: String = _output.path_join("unsupported.cfg")
	old.set_value("shading","format","old-format")
	old.save(file)
	_check(p.load_settings(file) == ERR_FILE_UNRECOGNIZED,"Unsupported settings explicitly rejected")
	p.hour = 23.999
	var a: Color = Palette.sample(p).ambient
	p.hour = 0.001
	var b: Color = Palette.sample(p).ambient
	_check(a.is_equal_approx(b),"Palette is continuous over midnight")
	p.hour = 12.0
	_check((Palette.sample(p).ambient as Color).is_equal_approx(p.color_noon_ambient),"Noon color uses authored anchor")
	var budget: Budget = Budget.new()
	var host: Node3D = Node3D.new()
	root.add_child(host)
	var fixed: OmniLight3D = OmniLight3D.new()
	var moving: OmniLight3D = OmniLight3D.new()
	host.add_child(fixed)
	host.add_child(moving)
	moving.position = Vector3(5,0,0)
	budget.register(fixed,2,true,0)
	budget.register(moving,3,true,10)
	budget.allocate(Vector3.ZERO,1,1,2)
	_check(fixed.light_energy == 0.0 and moving.light_energy == 3.0 and moving.shadow_enabled,"Priority moving lamp shares point and shadow budget")
	budget.allocate(Vector3.ZERO,0,0,2)
	_check(moving.light_energy == 0.0 and not moving.shadow_enabled,"Zero budget disables all illumination")
	host.free()
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
	_sample = (load("res://test/shader/scenes/shading_sample.tscn") as PackedScene).instantiate() as Sample
	_sample.settings_path = _output.path_join("extensions.cfg")
	_render.add_child(_sample)
	_sample._reset_settings()
	_sample._start()
	await _settle()
	var revision: int = _sample._volume.revision
	var original_light: PackedByteArray = _sample._volume.sky.duplicate()
	var panel: RefCounted = _sample._settings_panel
	for property: Dictionary in _sample._settings.settings_properties():
		_check(panel.widgets.has(property.name),"UI binding "+str(property.name))
	await _capture("extensions-default")
	for mode: int in [0,1,2]:
		_sample._settings.rays_mode = mode
		_sample._settings.ssao_enabled = mode > 0
		_sample._settings.hour = 16.5
		_sample._view(Vector3(0,4,9),Vector3(-1,4,-3))
		_sample._apply_lighting()
		await _capture("rays-mode-%d" % mode)
		_check(_sample._environment.volumetric_fog_enabled == (mode==2),"Ray modes are exclusive")
		_check(_sample._extensions.post.enabled == (mode==1),"Screen rays only enabled in screen mode")
	_sample._settings.rays_mode = 0
	_sample._settings.hour = 12.0
	_sample._settings.glass_enabled = true
	_sample._view(Vector3(18,8,24),Vector3(10,1,12))
	_sample._apply_lighting()
	await _capture("glass-and-metal")
	_check(_sample._extensions.glass.captures>0,"Glass map actually captured")
	var count: int = _sample._extensions.glass.captures
	await _frames(10)
	_check(_sample._extensions.glass.captures==count,"Static glass projection does not recapture")
	_sample._settings.weather_mode = 2
	_sample._settings.weather_transition = 0.1
	_sample._settings.wet_accumulation = 1.0
	_sample._apply_lighting()
	await create_timer(1.2).timeout
	await _capture("rain-wet-glass-roof")
	_check(_sample._extensions.weather.rain.emitting,"Rain particles are active")
	var wet: Image = _sample._extensions.weather.wet
	_check(wet.get_pixel(40,40).g > 0.0,"Rain accumulates surface wetness")
	var old_height: float = wet.get_pixel(40,40).r
	_sample._edit({Vector3i(8,int(old_height),8):1})
	_check(_sample._extensions.weather.wet.get_pixel(40,40).g==0.0,"Newly built surface does not inherit removed surface wetness")
	_sample._settings.weather_mode = 0
	_sample._settings.moving_mode = 1
	_sample._settings.hour = 0.0
	_sample._view(Vector3(16,-4,0),Vector3(-10,-4,0))
	_sample._apply_lighting()
	await _capture("handheld-cave")
	_check(_sample._extensions.moving.light.light_energy>0.0,"Handheld real lamp enabled")
	_sample._settings.moving_mode = 2
	_sample._settings.motion_enabled = true
	_sample._settings.chroma_enabled = true
	_sample._settings.dof_mode = 2
	_sample._settings.exposure_mode = 1
	_sample._view(Vector3(18,8,24),Vector3(10,1,12))
	_sample._apply_lighting()
	await create_timer(0.5).timeout
	await _capture("camera-effects")
	_check(_sample._camera.attributes.auto_exposure_enabled,"Main camera auto exposure")
	_check(not _sample._planar.camera.attributes.auto_exposure_enabled,"Planar exposure remains neutral")
	_check(_sample._planar.camera.compositor==null,"Planar does not inherit main compositor")
	_sample._settings.dof_mode = 1
	_sample._settings.dof_focus = 7.0
	_sample._apply_lighting()
	_check(is_equal_approx(_sample._extensions.camera_effects.focus,7.0),"Manual focus uses exact distance")
	_sample._settings.motion_enabled = false
	_sample._settings.chroma_enabled = false
	_sample._settings.exposure_mode = 0
	_sample._settings.dof_mode = 0
	_sample._settings.moving_mode = 0
	_sample._settings.ssao_enabled = false
	_sample._settings.glass_enabled = false
	_sample._apply_lighting()
	await _capture("effects-restored-off")
	_check(not _sample._extensions.motion.enabled and not _sample._extensions.post.enabled,"Disabled compositor passes stop")
	_check(not _sample._camera.attributes.auto_exposure_enabled and not _sample._camera.attributes.dof_blur_far_enabled,"Camera effects restore")
	# Only the explicit building edit may change voxel state.
	_check(_sample._volume.revision == revision+1,"Display settings do not mutate authoritative voxels")
	_check(original_light.size()==_sample._volume.sky.size(),"Light volume dimensions unchanged")
	_sample._reset_settings()
	for size: Vector2i in [Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160),Vector2i(2560,1080)]:
		_render.size = size
		panel.show_setting(&"rays_mode")
		await _capture("extensions-layout-%dx%d" % [size.x,size.y])
		for key: StringName in panel.rows:
			var row: Control = panel.rows[key]
			if row.is_visible_in_tree(): _check(row.get_global_rect().end.x <= 430.0,"Panel width "+str(key))
	# Exercise the visible screen-ray path, rather than only its behind-camera fallback.
	_render.size = Vector2i(1920,1080)
	_sample._reset_settings()
	_sample._settings.show_fps = false
	_sample._settings.hour = 17.0
	_sample._settings.clouds_enabled = false
	_sample._settings.avatar_animate = false
	_sample._settings.wind_enabled = false
	_sample._settings.water_enabled = false
	_sample._apply_lighting()
	var eye: Vector3 = Vector3(18,3,20)
	_sample._view(eye,eye+_sample._sun.global_basis.z*100.0-Vector3.UP*5.0)
	await _capture("screen-rays-off")
	var before_rays: Image = _render.get_texture().get_image()
	_sample._settings.rays_mode = 1
	_sample._settings.rays_strength = 1.0
	_sample._apply_lighting()
	await _capture("screen-rays-visible")
	_check(_difference(before_rays,_render.get_texture().get_image())>0.0001,"Visible screen rays change rendered pixels")
	_sample._settings.rays_mode = 0
	_sample._settings.direct_enabled = false
	_sample._settings.ssao_enabled = false
	_sample._view(Vector3(-29,8,12),Vector3(-23,3,4))
	_sample._apply_lighting()
	await _capture("ssao-off")
	var before_ao: Image = _render.get_texture().get_image()
	_sample._settings.ssao_enabled = true
	_sample._settings.ssao_intensity = 3.0
	_sample._apply_lighting()
	await _capture("ssao-on")
	_check(_difference(before_ao,_render.get_texture().get_image())>0.00001,"SSAO changes ambient-lit geometry")
	_sample._settings.direct_enabled = true
	_sample._settings.motion_enabled = true
	_sample._settings.motion_shutter = 180.0
	_sample._apply_lighting()
	for frame: int in range(16):
		_sample._camera.position.x += 0.1
		await process_frame
	await RenderingServer.frame_post_draw
	_check(_render.get_texture().get_image().save_png(_output.path_join("motion-camera-pan.png"))==OK,"Moving camera compositor capture")
	_sample.queue_free()
	await _frames(3)

func _difference(a: Image,b: Image) -> float:
	var sum: float = 0.0
	var count: int = 0
	for y: int in range(100,a.get_height()-50,8):
		for x: int in range(460,a.get_width()-30,8):
			var ca: Color = a.get_pixel(x,y)
			var cb: Color = b.get_pixel(x,y)
			sum += absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b)
			count += 3
	return sum / maxi(1,count)
