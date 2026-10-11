extends SceneTree
## Render the shared production filter against synthetic paged light, then the real sample.
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
const Pages: Script = preload("res://test/shading/gdscript/light_page_fixture.gd")
var checks: int = 0
var failures: int = 0
var viewport: SubViewport
var material: ShaderMaterial
var results: Array[String] = []
var output: String = "res://tmp/light-smoothing"

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	results.append(("%s: " % ("PASS" if value else "FAIL")) + message)
	if not value:
		failures += 1
		push_error(message)

func capture() -> Image:
	for frame: int in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func field(kind: int) -> void:
	var images: Array[Image] = []
	for z: int in range(-16,16):
		var image: Image = Image.create_empty(32,16,false,Image.FORMAT_RGBA8)
		for y: int in range(16):
			for x: int in range(-16,16):
				var level: float = maxf(0.0,1.0-absf(float(x))/8.0)
				var valid: float = 1.0
				if kind == 1: # Solid wall at x=0, bright on its far side.
					level = 1.0 if x > 0 else 0.0
					valid = 0.0 if x == 0 else 1.0
				elif kind == 2: # Bright diagonal behind two opaque side cells.
					level = 1.0 if x == 1 and z == 1 else 0.0
					valid = 0.0 if (x == 1 and z == 0) or (x == 0 and z == 1) else 1.0
				image.set_pixel(x+16,y,Color(level,level,valid,1.0))
		images.append(image)
	var texture: ImageTexture3D = ImageTexture3D.new()
	check(texture.create(Image.FORMAT_RGBA8,32,16,32,false,images) == OK,"Create paged test field")
	Pages.bind_fixture(material,texture,Vector3i(-16,0,-16),Vector3i(32,16,32))

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	print("SMOOTH_PROCESS ",JSON.stringify({"pid":OS.get_process_id(),"executable":OS.get_executable_path(),"project":ProjectSettings.globalize_path("res://"),"purpose":"light smoothing rendered regression"}))
	viewport = SubViewport.new()
	viewport.size = Vector2i(512,32)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var rect: ColorRect = ColorRect.new()
	rect.size = Vector2(512,32)
	material = ShaderMaterial.new()
	material.shader = preload("res://test/shading/shaders/light_filter_probe.gdshader")
	rect.material = material
	viewport.add_child(rect)
	field(0)
	var linear: Image
	var quadratic: Image
	for mode: int in range(3):
		material.set_shader_parameter("light_filter_mode",mode)
		var img: Image = await capture()
		img.save_png(output.path_join("probe_%d.png" % mode))
		# Independent analytic triangular field in open space, crossing section x=0.
		var max_error: float = 0.0
		for pixel: int in range(512):
			var x: float = -2.0+(float(pixel)+0.5)*4.0/512.0
			var anchor: int = floori(x)
			var expected: float = 0.0
			if mode == 0:
				expected = roundf(maxf(0.0,1.0-absf(float(anchor))/8.0)*255.0)/255.0
			else:
				var t: float = x-float(anchor)-0.5
				for offset: int in range(-1,2):
					var distance: float = absf(t-float(offset))
					var weight: float = maxf(0.0,1.0-distance)
					if mode == 2:
						weight = 0.75-distance*distance if distance <= 0.5 else 0.5*pow(maxf(0.0,1.5-distance),2.0)
					expected += weight*roundf(maxf(0.0,1.0-absf(float(anchor+offset))/8.0)*255.0)/255.0
			max_error = maxf(max_error,absf(img.get_pixel(pixel,16).r-expected))
		check(max_error < 0.012,"GPU mode %d matches analytic field across negative/positive section seam (error %.4f)" % [mode,max_error])
		if mode == 1: linear = img
		if mode == 2: quadratic = img
	check(quadratic.get_pixel(319,16).r < linear.get_pixel(319,16).r-0.015,"Nine-tap filter rounds the cell-center peak")
	field(1)
	material.set_shader_parameter("probe_origin",Vector3(-1,0,0.5))
	material.set_shader_parameter("probe_width",0.99)
	check((await capture()).get_pixel(500,16).r < 0.005,"No bright sample through one-cell opaque wall")
	field(2)
	material.set_shader_parameter("probe_origin",Vector3(0.8,0,0.8))
	material.set_shader_parameter("probe_width",0.1)
	check((await capture()).get_pixel(256,16).r < 0.005,"Blocked diagonal corner stays dark")
	material.set_shader_parameter("probe_origin",Vector3(-18,0,0.5))
	check((await capture()).get_pixel(256,16).r < 0.005,"Unknown page stays dark")
	material.set_shader_parameter("response_probe",true)
	for mode: int in range(2):
		material.set_shader_parameter("block_response_mode",mode)
		var image: Image = await capture()
		var monotone: bool = true
		for x: int in range(1,512):
			monotone = monotone and image.get_pixel(x,16).r >= image.get_pixel(x-1,16).r
		check(monotone and image.get_pixel(0,16).r < 0.005 and image.get_pixel(511,16).r > 0.99,"Curve %d monotone with zero/final endpoints" % mode)
	viewport.queue_free()
	await process_frame
	await sample_checks()
	var report: FileAccess = FileAccess.open(output.path_join("results.md"),FileAccess.WRITE)
	report.store_string("\n".join(results))
	report.close()
	print("SMOOTH_DONE checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)

func sample_checks() -> void:
	root.size = Vector2i(1920,1080)
	var sample: Node3D = preload("res://test/shading/scenes/shading_sample.tscn").instantiate()
	sample.set("settings_path",output.path_join("sample-settings.cfg"))
	root.add_child(sample)
	# Repeated runs must not inherit the last comparison mode from temporary settings.
	sample.call("_reset_settings")
	sample.call("_start")
	var settings: Profile = sample.get("_settings")
	settings.hour = 0.0
	settings.cycle_enabled = false
	settings.local_lighting_mode = 1
	settings.fog_enabled = false
	settings.water_enabled = false
	settings.ambient_minimum = 0.0
	settings.ambient_strength = 0.0
	settings.direct_enabled = false
	settings.ao_enabled = false
	settings.block_grid_strength = 0.0
	settings.max_fps = 120
	sample.call("_apply_lighting")
	var edits: Dictionary[Vector3i,int] = {}
	for x: int in [-12,-6,0]:
		for z: int in [8,14]:
			edits[Vector3i(x,1,z)] = 2
	sample.call("_edit",edits)
	var deadline: int = Time.get_ticks_msec()+90000
	while not sample.get("_volume").is_settled() or sample.get("_sections").pending_count() > 0 or sample.get("_uploaded_revision") != sample.get("_volume").revision:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			check(false,"Sample settles within 90 seconds")
			sample.queue_free()
			return
	var revision: int = sample.get("_volume").revision
	var rebuilt: int = sample.get("_sections").rebuilt_sections
	sample.call("_view",Vector3(3,11,24),Vector3(-6,0,11))
	var panel: RefCounted = sample.get("_settings_panel")
	panel.call("show_setting",&"light_filter_mode")
	for mode: int in [0,1,2]:
		panel.call("_select",&"light_filter_mode",mode)
		for frame: int in range(10):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("floor_%d.png" % mode))
		for surface: ShaderMaterial in sample.get("_sections").materials:
			check(surface.get_shader_parameter("light_filter_mode") == mode,"Sample material receives filter %d" % mode)
	panel.call("_select",&"block_response_mode",1)
	check(not panel.call("_effective",&"block_curve"),"MakeUp response hides unused exponent")
	for frame: int in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("floor_makeup.png"))
	check(sample.get("_volume").revision == revision and sample.get("_sections").rebuilt_sections == rebuilt,"Smoothing/response changes do not solve light or rebuild geometry")
	# Sky corridor exercises the same controls on ambient and directional visibility.
	settings.hour = 12.0
	settings.local_lighting_mode = 0
	settings.ambient_strength = 1.0
	settings.direct_enabled = true
	sample.call("_view",Vector3(16,-4,-0.5),Vector3(-16,-4,0))
	for mode: int in [1,2]:
		panel.call("_select",&"light_filter_mode",mode)
		for frame: int in range(10):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("sky_%d.png" % mode))
	check(sample.get("_volume").revision == revision,"Sky smoothing leaves logical light untouched")
	settings.block_smoothing = 0.75
	check(settings.save_settings(output.path_join("roundtrip.cfg")) == OK,"Save filter controls")
	var restored: Profile = Profile.new()
	check(restored.load_settings(output.path_join("roundtrip.cfg")) == OK and restored.light_filter_mode == 2 and restored.block_response_mode == 1 and is_equal_approx(restored.block_smoothing,0.75),"Restore filter controls")
	check(Profile.new().light_filter_mode == 2 and is_equal_approx(Profile.new().block_smoothing,1.0),"Default is full nine-tap smoothing")
	sample.queue_free()
	await process_frame
