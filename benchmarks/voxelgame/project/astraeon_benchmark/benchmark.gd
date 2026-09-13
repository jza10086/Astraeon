extends Node3D
## Opt-in rendered benchmark. Fixed 1080p render target; independent of OS window overrides.
const Generator: Script = preload("res://astraeon_benchmark/benchmark_generator.gd")
@export_enum("initial_load", "stationary", "streaming", "editing", "smoke") var scenario: String = "stationary"
@export var view_distance: int = 256
@export var vertical_distance: int = 256
@export var world_seed: int = 20260913
@export var warmup_seconds: float = 3.0
@export var sample_seconds: float = 45.0
@export var movement_speed: float = 22.0
@export var profile: String = "plain"
@export var fps_cap: int = 0
@export var generate_collisions: bool = true
var _run: bool = false
var _running: bool = false
var _finishing: bool = false
var _sampling: bool = false
var _output: String = ""
var _terrain: VoxelTerrain
var _viewer: VoxelViewer
var _camera: Camera3D
var _generator: VoxelGeneratorScript
var _tool: VoxelTool
var _render: SubViewport
var _label: Label
var _frames: Array[Vector2] = []
var _counters: Array[Dictionary] = []
var _edits: Array[Dictionary] = []
var _metadata: Dictionary = {}
var _start: int = 0
var _last: int = 0
var _sample_start: int = 0
var _idle_since: int = 0
var _last_check: int = 0
var _loaded: int = 0
var _unloaded: int = 0
var _counter_second: int = -1
var _edit_index: int = 0
var _pending: bool = false
var _edit_start: int = 0
var _edit_physics_frame: int = 0
var _idle_frames: int = 0
var _next_edit: float = 0.5
var _edit_origin: Vector3i
var _edit_size: Vector3i
var _edit_value: int = 0
var _near_missing: int = 0
var _collision_missing: int = 0
var _max_missing_seconds: float = 0.0
var _missing_start: float = -1.0
var _distance_travelled: float = 0.0
var _route: PackedVector3Array = PackedVector3Array()
var _route_lengths: PackedFloat32Array = PackedFloat32Array()
var _route_cursor: int = 0
var _invalid: String = ""

func _ready() -> void:
	set_process(false)
	get_tree().auto_accept_quit = false
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--run-benchmark":
			_run = true
		elif arg.begins_with("--case="): scenario = arg.get_slice("=", 1)
		elif arg.begins_with("--vertical-distance="): vertical_distance = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--distance="): view_distance = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--seconds="): sample_seconds = arg.get_slice("=", 1).to_float()
		elif arg.begins_with("--warmup="): warmup_seconds = arg.get_slice("=", 1).to_float()
		elif arg.begins_with("--seed="): world_seed = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--speed="): movement_speed = arg.get_slice("=", 1).to_float()
		elif arg.begins_with("--profile="): profile = arg.get_slice("=", 1)
		elif arg.begins_with("--cap="): fps_cap = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--output="): _output = arg.trim_prefix("--output=")
		else:
			push_error("Unknown argument: " + arg)
			get_tree().quit(2)
			return
	if scenario not in ["initial_load", "stationary", "streaming", "editing", "smoke"] or profile not in ["plain", "forest", "mountain", "mixed"] or vertical_distance < 16 or vertical_distance > 512 or vertical_distance % 16 != 0 or view_distance % 16 != 0 or view_distance < 32 or view_distance > 512 or sample_seconds < 1 or sample_seconds > 120 or movement_speed <= 0 or warmup_seconds < 1 or warmup_seconds > 30 or fps_cap < 0:
		push_error("Invalid benchmark configuration")
		get_tree().quit(2)
		return
	var canvas: CanvasLayer = CanvasLayer.new()
	add_child(canvas)
	_label = Label.new()
	_label.position = Vector2(20, 20)
	_label.text = "ASTRAEON benchmark READY - no workload running"
	canvas.add_child(_label)
	if _run:
		_start_run.call_deferred()
	else:
		var button: Button = Button.new()
		button.text = "Start selected benchmark"
		button.position = Vector2(20, 60)
		canvas.add_child(button)
		button.pressed.connect(func() -> void:
			button.hide()
			_start_run())

func _start_run() -> void:
	if _running or _finishing: return
	if DisplayServer.get_name() == "headless":
		push_error("Performance measurement requires a real renderer")
		get_tree().quit(2)
		return
	if _output.is_empty(): _output = "user://benchmark_results"
	_output = _output.path_join("%s_%s_%s_%d" % [Time.get_datetime_string_from_system().replace(":", "-"), scenario, profile, Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(_output) != OK:
		get_tree().quit(2)
		return
	Engine.max_fps = fps_cap
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_render = SubViewport.new()
	_render.size = Vector2i(1920, 1080)
	_render.own_world_3d = true
	_render.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_render)
	var display: TextureRect = TextureRect.new()
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.texture = _render.get_texture()
	add_child(display)
	seed(world_seed)
	_generator = Generator.new() as VoxelGeneratorScript
	_generator.call("configure", profile, world_seed)
	_terrain = VoxelTerrain.new()
	_terrain.bounds = AABB(Vector3(-1048576, -128, -1048576), Vector3(2097152, 512, 2097152))
	_terrain.generator = _generator
	_terrain.mesher = load("res://blocky_game/blocks/mesher.tres") as VoxelMesherBlocky
	_terrain.max_view_distance = maxi(view_distance, vertical_distance)
	_terrain.mesh_block_size = 16
	if not _terrain.has_method("set_horizontal_circular_loading"):
		push_error("Circular loading native patch missing; run tools/build_voxel_circular.py --install")
		get_tree().quit(2)
		return
	_terrain.set("horizontal_circular_loading", true)
	_terrain.generate_collisions = generate_collisions
	_terrain.block_loaded.connect(func(_p: Vector3i) -> void: _loaded += 1)
	_terrain.block_unloaded.connect(func(_p: Vector3i) -> void: _unloaded += 1)
	_render.add_child(_terrain)
	_tool = _terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_tool.mode = VoxelTool.MODE_SET
	_camera = Camera3D.new()
	_camera.far = 2048
	_camera.current = true
	_render.add_child(_camera)
	_camera.position = Vector3(0, _height(0, 0) + 18.0, 0)
	_camera.rotation_degrees = Vector3(-20, -35, 0)
	if scenario in ["editing", "smoke"]:
		_camera.position = Vector3(32, 160, 44)
		_camera.look_at(Vector3(4, 142, 4))
	_viewer = VoxelViewer.new()
	_viewer.view_distance = view_distance
	_viewer.view_distance_vertical_ratio = float(vertical_distance) / float(view_distance)
	_viewer.requires_collisions = generate_collisions
	_camera.add_child(_viewer)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	light.shadow_enabled = true
	_render.add_child(light)
	var env_node: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.5, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.8, 1.0)
	env.ambient_light_energy = 0.7
	env_node.environment = env
	_render.add_child(env_node)
	_build_route()
	_metadata = {"schema_version": 3, "status": "warming", "scenario": scenario, "profile": profile,
		"godot": Engine.get_version_info(), "voxel_tools": str(VoxelEngine.get_version_v()),
		"voxel_git_hash": VoxelEngine.get_version_git_hash(), "voxel_edition": VoxelEngine.get_version_edition(),
		"voxelgame_commit": "4cf747a8456375e527c8c976c50fb24446f9d18f",
		"cpu": OS.get_processor_name(), "cpu_threads": OS.get_processor_count(), "gpu": RenderingServer.get_video_adapter_name(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(), "rendering_method": RenderingServer.get_current_rendering_method(),
		"render_size": str(_render.size), "window_size": str(DisplayServer.window_get_size()), "debug_build": OS.is_debug_build(),
		"distance": view_distance, "horizontal_shape": "circle", "chunk_width": 16, "view_distance_chunks": view_distance / 16, "vertical_distance": vertical_distance, "bounds": str(_terrain.bounds), "height": 512, "seed": world_seed, "speed_mps": movement_speed,
		"seconds": sample_seconds, "cap": fps_cap, "vsync": DisplayServer.window_get_vsync_mode(), "collisions": generate_collisions,
		"scope": "controlled heightmap/trees, no caves/player/AI/water ticks/network/saves; fixed 1080p offscreen target composited into window",
		"completion_method": "queue drain, two process frames, >= two physics ticks and surface ray checks; conservative update latency, not direct mesh timestamp",
		"vertical_loading": "Horizontal block-center disk snapped to 16-voxel grid; independent vertical half-range clipped to world bounds; one data-neighbor halo",
		"lighting": "ambient + directional shadows, no SDFGI"}
	_write_json("metadata.json", _metadata)
	_start = Time.get_ticks_usec()
	_last = _start
	_running = true
	set_process(true)

func _height(x: int, z: int) -> float:
	return float(_generator.call("_get_height_at", x, z))

func _build_route() -> void:
	# 1 m horizontal samples, height above tree canopy. Arc-length traversal gives true 3D speed.
	var length: float = 0.0
	for x: int in range(0, 5201):
		var z: int = int(48.0 * sin(float(x) / 180.0))
		var p: Vector3 = Vector3(x, _height(x, z) + 24.0, z)
		if not _route.is_empty(): length += p.distance_to(_route[-1])
		_route.append(p)
		_route_lengths.append(length)
	if scenario == "streaming": _camera.position = _route[0]

func _queues_idle() -> bool:
	var stats: Dictionary = VoxelEngine.get_stats()
	var tasks: Dictionary = stats["tasks"]
	for key: String in ["generation", "meshing", "main_thread", "streaming", "gpu"]:
		if int(tasks.get(key, 0)) != 0: return false
	var pool: Dictionary = stats["thread_pools"]["general"]
	return int(pool["tasks"]) == 0 and int(pool["active_threads"]) == 0

func _near_ready() -> bool:
	var p: Vector3 = _camera.position
	return _terrain.is_area_meshed(AABB(p - Vector3(24, 32, 24), Vector3(48, 64, 48)))

func _process(_delta: float) -> void:
	if not _running: return
	var now: int = Time.get_ticks_usec()
	var dt: float = float(now - _last) / 1000000.0
	_last = now
	var elapsed: float = float(now - _start) / 1000000.0
	if _render.size != Vector2i(1920, 1080):
		_finish("invalid_render_size")
		return
	if not _sampling:
		_label.text = "WARMUP %s/%s %.1fs" % [scenario, profile, elapsed]
		if now - _last_check >= 100000:
			_last_check = now
			if _queues_idle() and _near_ready():
				if _idle_since == 0: _idle_since = now
			else: _idle_since = 0
		if elapsed >= warmup_seconds and _idle_since > 0 and now - _idle_since >= 2000000:
			# Screenshot and readback happen before sampling and are followed by settling frames.
			set_process(false)
			await RenderingServer.frame_post_draw
			_render.get_texture().get_image().save_png(_output.path_join("before.png"))
			await get_tree().create_timer(0.5).timeout
			if not _running: return
			_sample_start = Time.get_ticks_usec()
			_last = _sample_start
			_sampling = true
			_metadata["warmup_actual_s"] = float(_sample_start - _start) / 1000000.0
			set_process(true)
		elif elapsed > 30.0: _finish("warmup_timeout")
		return
	var t: float = float(now - _sample_start) / 1000000.0
	_frames.append(Vector2(t, dt * 1000.0))
	if scenario == "streaming": _move(t)
	if scenario in ["editing", "smoke"]: _edit(t, now)
	if _finishing: return
	if int(t) != _counter_second:
		_counter_second = int(t)
		_record_counter(t)
		_label.text = "%s/%s | 256 distance, 512 height | %.1f / %.1fs\nSpeed %.0f m/s | edits %d | Esc abort" % [scenario, profile, t, sample_seconds, movement_speed, _edit_index]
	if not _invalid.is_empty():
		_finish(_invalid)
	elif scenario in ["editing", "smoke"]:
		var count: int = 2 if scenario == "smoke" else 30
		if _edit_index >= count and not _pending and t >= _next_edit: _finish("completed")
		elif t > sample_seconds: _finish("edit_timeout")
	elif t >= sample_seconds: _finish("completed")

func _move(t: float) -> void:
	_distance_travelled = t * movement_speed
	while _route_cursor + 1 < _route.size() - 1 and _route_lengths[_route_cursor + 1] < _distance_travelled:
		_route_cursor += 1
	var a: float = _route_lengths[_route_cursor]
	var b: float = _route_lengths[_route_cursor + 1]
	var p: Vector3 = _route[_route_cursor].lerp(_route[_route_cursor + 1], clampf((_distance_travelled - a) / (b - a), 0, 1))
	_camera.position = p
	var forward: Vector3 = (_route[mini(_route_cursor + 12, _route.size() - 1)] - p).normalized()
	_camera.look_at(p + forward * 30.0 + Vector3(0, -8, 0))

func _record_counter(t: float) -> void:
	var near: bool = _near_ready()
	if not near: _near_missing += 1
	if not near and _missing_start < 0: _missing_start = t
	if near and _missing_start >= 0:
		_max_missing_seconds = maxf(_max_missing_seconds, t - _missing_start)
		_missing_start = -1
	var p: Vector3 = _camera.position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(p + Vector3(0, 16, 0), Vector3(p.x, -128, p.z))
	var hit: Dictionary = _render.find_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): _collision_missing += 1
	_counters.append({"t_s": t, "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), "static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED), "engine": VoxelEngine.get_stats(), "terrain": _terrain.get_statistics(),
		"loaded": _loaded, "unloaded": _unloaded, "near_ready": near, "ground_collision": not hit.is_empty(), "camera": str(p), "distance_m": _distance_travelled})

func _edit(t: float, now: int) -> void:
	if _pending:
		_idle_frames = _idle_frames + 1 if _queues_idle() else 0
		if _idle_frames >= 2 and Engine.get_physics_frames() - _edit_physics_frame >= 2 and _collision_matches():
			_edits[-1]["completion_ms"] = float(now - _edit_start) / 1000.0
			_pending = false
		elif now - _edit_start > 5000000:
			_invalid = "edit_completion_timeout"
		return
	var limit: int = 2 if scenario == "smoke" else 30
	if t < _next_edit or _edit_index >= limit: return
	@warning_ignore("integer_division")
	var layout: int = (_edit_index / 10) % 3
	_edit_size = Vector3i(16, 1, 8) if layout == 2 else Vector3i(8, 4, 4)
	_edit_origin = [Vector3i(4, 132, 4), Vector3i(-4, 142, -2), Vector3i(-8, 160, -4)][layout]
	_edit_value = 1 if _edit_index % 2 == 0 else 0
	var changed: int = 0
	for z: int in _edit_size.z:
		for y: int in _edit_size.y:
			for x: int in _edit_size.x:
				if _tool.get_voxel(_edit_origin + Vector3i(x, y, z)) != _edit_value: changed += 1
	if changed != 128 or not _tool.is_area_editable(AABB(Vector3(_edit_origin) - Vector3.ONE, Vector3(_edit_size) + Vector3.ONE * 2)):
		_invalid = "edit_fixture_invalid"
		return
	_edit_start = Time.get_ticks_usec()
	_edit_physics_frame = Engine.get_physics_frames()
	_tool.value = _edit_value
	_tool.do_box(_edit_origin, _edit_origin + _edit_size - Vector3i.ONE)
	var matches: int = 0
	for z: int in _edit_size.z:
		for y: int in _edit_size.y:
			for x: int in _edit_size.x:
				if _tool.get_voxel(_edit_origin + Vector3i(x, y, z)) == _edit_value: matches += 1
	_edits.append({"layout": ["compact", "boundary", "platform"][layout], "operation": "place" if _edit_value == 1 else "dig",
		"t_s": t, "changed": changed, "verified": matches, "submit_ms": float(Time.get_ticks_usec() - _edit_start) / 1000.0, "completion_ms": -1.0})
	if matches != 128: _invalid = "edit_data_mismatch"
	_edit_index += 1
	_pending = true
	_idle_frames = 0
	_next_edit = t + 2.2

func _collision_matches() -> bool:
	for z: int in _edit_size.z:
		for x: int in _edit_size.x:
			var top: Vector3 = Vector3(_edit_origin) + Vector3(x + 0.5, _edit_size.y + 0.5, z + 0.5)
			var bottom: Vector3 = Vector3(top.x, _edit_origin.y - 0.5, top.z)
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(top, bottom)
			var hit: Dictionary = _render.find_world_3d().direct_space_state.intersect_ray(query)
			if _edit_value == 0 and not hit.is_empty(): return false
			if _edit_value == 1:
				if hit.is_empty(): return false
				var pos: Vector3 = hit["position"]
				if absf(pos.y - float(_edit_origin.y + _edit_size.y)) > 0.05: return false
	return true

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _running: _finish("aborted")
		elif not _finishing: get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _running: _finish("aborted")
		elif not _finishing: get_tree().quit()

func _finish(status: String) -> void:
	if _finishing: return
	_finishing = true
	_running = false
	set_process(false)
	_metadata["status"] = status
	_write_json("metadata.json", _metadata)
	var summary: Dictionary = {"status": status, "near_missing_samples": _near_missing, "collision_missing_samples": _collision_missing,
		"max_missing_seconds": _max_missing_seconds, "distance_m": _distance_travelled, "loaded": _loaded, "unloaded": _unloaded,
		"engine_final": VoxelEngine.get_stats(), "edit_count": _edits.size()}
	_write_json("summary.json", summary)
	_write_json("counters.json", _counters)
	_write_json("edits.json", _edits)
	var csv: FileAccess = FileAccess.open(_output.path_join("frames.csv"), FileAccess.WRITE)
	if csv == null:
		push_error("Cannot write frames")
		status = "write_error"
	else:
		csv.store_csv_line(PackedStringArray(["elapsed_s", "frame_ms"]))
		for row: Vector2 in _frames: csv.store_csv_line(PackedStringArray([str(row.x), str(row.y)]))
		csv.close()
	await RenderingServer.frame_post_draw
	_render.get_texture().get_image().save_png(_output.path_join("after.png"))
	print("BENCHMARK_OUTPUT ", ProjectSettings.globalize_path(_output))
	print("BENCHMARK_STATUS ", status)
	# Release native terrain while engine services and the main loop still exist.
	_tool = null
	_viewer.queue_free()
	_terrain.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_generator = null
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if status == "completed" else 1)

func _write_json(filename: String, value: Variant) -> void:
	var file: FileAccess = FileAccess.open(_output.path_join(filename), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write " + filename)
		return
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
