extends SceneTree
const Fixture = preload("res://test/content/gdscript/authoring_fixture.gd")
var results: Array[Dictionary] = []
var failed: bool = false
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	for count: int in [100, 500, 1000]:
		for mode: String in ["preload", "on_demand", "orientations"]:
			await measure(count, mode)
	var report: FileAccess = FileAccess.open("res://tmp/content/scale.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(results, "  "))
	print("CONTENT_SCALE_DONE cases=", results.size(), " failures=", int(failed))
	quit(1 if failed else 0)
func measure(count: int, mode: String) -> void:
	var manifest: Resource = load("res://game/data/content/gdscript/content_manifest.gd").new()
	manifest.package_id = "scale"
	var orientations: int = 4 if mode == "orientations" else 1
	for index: int in range(count / orientations):
		var block: AstraeonBlockDefinition = AstraeonBlockDefinition.new()
		block.key = StringName("scale:block_%04d" % index)
		block.load_policy = "preload" if mode != "on_demand" or index < 5 else "on_demand"
		block.appearance = AstraeonBlockAppearance.new()
		block.appearance.default_surface = AstraeonBlockSurface.new()
		var pixels: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
		pixels.fill(Color.from_hsv(float(index) / count, 0.7, 0.8))
		pixels.set_pixel(0, 0, Color(float(index % 256) / 255, float(index / 256) / 255, 1))
		block.appearance.default_surface.albedo_texture = ImageTexture.create_from_image(pixels)
		if orientations > 1:
			block.default_state = &"r0"
			for rotation: int in range(orientations):
				var state: AstraeonBlockStateDefinition = AstraeonBlockStateDefinition.new()
				state.key = StringName("r%d" % rotation)
				state.orientation = Basis(Vector3.UP, rotation * PI / 2.0)
				block.states.append(state)
		var asset: AstraeonBlockAsset = Fixture.add_block(manifest, block)
	var compiler: RefCounted = load("res://tools/content/compiler.gd").new()
	var path: String = "res://tmp/content/scale_%d_%s.aebpack" % [count, mode]
	var begin: int = Time.get_ticks_usec()
	var compiled: Dictionary = compiler.build(manifest, path)
	var build_usec: int = Time.get_ticks_usec() - begin
	if compiled.has("error"):
		printerr(compiled)
		failed = true
		return
	begin = Time.get_ticks_usec()
	var repeated: Dictionary = compiler.build(manifest, path)
	var repeated_usec: int = Time.get_ticks_usec() - begin
	var content: AstraeonWorldContent = AstraeonWorldContent.new()
	begin = Time.get_ticks_usec()
	if not content.build(PackedStringArray([path])):
		printerr(content.error)
		failed = true
		return
	var metadata_usec: int = Time.get_ticks_usec() - begin
	var cache: RefCounted = content.bundle.visuals
	var wanted: PackedStringArray = []
	for block: Dictionary in content.bundle.blocks.values():
		if block.load_policy == "preload":
			wanted.append(block.visual)
	cache.request("active", wanted)
	begin = Time.get_ticks_usec()
	var frame_times: Array[float] = []
	var deadline: int = Time.get_ticks_msec() + 60000
	while not cache.is_ready(wanted) and Time.get_ticks_msec() < deadline:
		var frame_start: int = Time.get_ticks_usec()
		cache.commit()
		await process_frame
		frame_times.append(float(Time.get_ticks_usec() - frame_start) / 1000.0)
	var loading_usec: int = Time.get_ticks_usec() - begin
	if not cache.is_ready(wanted):
		printerr("Scale load timeout: ", count, " ", mode, " ", cache.get_metrics())
		failed = true
	var metrics: Dictionary = cache.get_metrics()
	if mode == "on_demand" and int(metrics.reads) != 5:
		failed = true
		printerr("Unused on-demand payload was read")
	cache.release("active")
	cache.request("return", wanted)
	cache.commit()
	if int(cache.get_metrics().reads) != int(metrics.reads) or int(cache.get_metrics().uploads) != int(metrics.uploads):
		failed = true
	frame_times.sort()
	var result: Dictionary = {"states": count, "mode": mode, "build_ms": build_usec / 1000.0, "incremental_ms": repeated_usec / 1000.0, "metadata_ms": metadata_usec / 1000.0, "first_visual_ms": loading_usec / 1000.0, "compiled": compiled, "repeat": repeated, "metrics": metrics, "renderer": DisplayServer.get_name(), "p99_loading_frame_ms": frame_times[mini(frame_times.size()-1, int(frame_times.size()*0.99))] if not frame_times.is_empty() else 0, "max_loading_frame_ms": frame_times[-1] if not frame_times.is_empty() else 0}
	results.append(result)
	print("CONTENT_SCALE_CASE ", JSON.stringify(result))
	content.bundle.shutdown()
	await process_frame
