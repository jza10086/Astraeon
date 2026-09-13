extends Node3D
## Opt-in workload runner. The default entry creates only a setup UI.
## Measures the pinned demo generator/mesher, not the complete game.

@export_enum("initial_load", "stationary", "streaming", "editing") var scenario: String = "stationary"
@export_range(32, 512, 16) var view_distance: int = 128
@export var world_seed: int = 20260913
@export_range(1.0, 300.0) var warmup_seconds: float = 15.0
@export_range(1.0, 600.0) var sample_seconds: float = 60.0
@export var movement_speed: float = 16.0
@export var edits_per_second: float = 20.0
@export var generate_collisions: bool = true

var _running: bool = false
var _cli_run: bool = false
var _failed: bool = false
var _terrain: VoxelTerrain
var _viewer: VoxelViewer
var _camera: Camera3D
var _generator: VoxelGeneratorScript
var _tool: VoxelTool
var _status: Label
var _button: Button
var _output: String = ""
var _start_usec: int = 0
var _last_usec: int = 0
var _sample_start_usec: int = 0
var _counter_second: int = -1
var _edit_accumulator: float = 0.0
var _edit_index: int = 0
var _applied: int = 0
var _skipped: int = 0
var _frames: Array[Vector2] = []
var _counters: Array[Dictionary] = []
var _loaded: int = 0
var _unloaded: int = 0
var _center_ready_ms: float = -1.0
var _metadata: Dictionary = {}
var _sampling: bool = false

func _ready() -> void:
	set_process(false)
	get_tree().auto_accept_quit = false
	if not _read_arguments():
		get_tree().quit(2)
		return
	_build_ui()
	if _cli_run:
		_start.call_deferred()

func _read_arguments() -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--run-benchmark":
			_cli_run = true
		elif argument.begins_with("--case="):
			scenario = argument.trim_prefix("--case=")
		elif argument.begins_with("--distance="):
			view_distance = argument.trim_prefix("--distance=").to_int()
		elif argument.begins_with("--seconds="):
			sample_seconds = argument.trim_prefix("--seconds=").to_float()
		elif argument.begins_with("--warmup="):
			warmup_seconds = argument.trim_prefix("--warmup=").to_float()
		elif argument.begins_with("--seed="):
			world_seed = argument.trim_prefix("--seed=").to_int()
		elif argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		else:
			push_error("Unknown benchmark argument: " + argument)
			return false
	if scenario not in ["initial_load", "stationary", "streaming", "editing"]:
		push_error("Invalid scenario")
		return false
	if view_distance < 32 or view_distance > 512 or sample_seconds < 1.0 or sample_seconds > 600.0 or warmup_seconds < 1.0 or warmup_seconds > 300.0:
		push_error("Benchmark arguments outside supported ranges")
		return false
	return true

func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var margin: MarginContainer = MarginContainer.new()
	layer.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 32)
	var box: VBoxContainer = VBoxContainer.new()
	margin.add_child(box)
	_status = Label.new()
	_status.text = "ASTRAEON / voxelgame benchmark
READY - no world or workload started
Case: %s | distance: %d | seed: %d
Warmup: %.0fs | measurement: %.0fs
Wait for approval before pressing Start." % [scenario, view_distance, world_seed, warmup_seconds, sample_seconds]
	box.add_child(_status)
	_button = Button.new()
	_button.text = "Start selected benchmark"
	_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_button.pressed.connect(_start)
	box.add_child(_button)

func _start() -> void:
	if _running:
		return
	if DisplayServer.get_name() == "headless":
		push_error("Rendered benchmarks cannot run headless")
		get_tree().quit(2)
		return
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var base: String = _output if not _output.is_empty() else "user://benchmark_results"
	_output = base.path_join("%s_%s_d%d_%d" % [stamp, scenario, view_distance, Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(_output) != OK:
		push_error("Cannot create output directory")
		get_tree().quit(2)
		return
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_button.disabled = true
	_button.hide()
	_metadata = {
		"schema_version": 1, "status": "running", "scenario": scenario,
		"voxelgame_commit": "4cf747a8456375e527c8c976c50fb24446f9d18f",
		"voxel_tools": str(VoxelEngine.get_version_v()), "voxel_edition": VoxelEngine.get_version_edition(), "voxel_git_hash": VoxelEngine.get_version_git_hash(), "godot": Engine.get_version_info(),
		"os": OS.get_name(), "cpu": OS.get_processor_name(), "cpu_threads": OS.get_processor_count(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"window_size": str(DisplayServer.window_get_size()), "viewport_size": str(get_viewport().get_visible_rect().size),
		"vsync": DisplayServer.window_get_vsync_mode(), "debug_build": OS.is_debug_build(),
		"seed": world_seed, "view_distance_voxels": view_distance, "mesh_block_size": 16,
		"collisions": generate_collisions, "warmup_seconds": 0.0 if scenario == "initial_load" else warmup_seconds,
		"sample_seconds": sample_seconds, "movement_speed": movement_speed, "edits_per_second": edits_per_second,
		"save_stream": "disabled", "lighting": "ambient + directional shadows; no SDFGI",
		"scope": "demo generator and mesher; excludes player, water ticks, inventory, networking",
		"clock": "monotonic process-to-process wall interval, not GPU frame time",
		"memory_note": "Godot allocator/render estimates, not OS process RSS",
		"engine_statistics_before": VoxelEngine.get_stats()
	}
	if not _write_json("metadata.json", _metadata):
		get_tree().quit(2)
		return
	_start_usec = Time.get_ticks_usec()
	_last_usec = _start_usec
	# Upstream tree templates use the global RNG in _init; seed before instantiation.
	seed(world_seed)
	var generator_script: Script = load("res://blocky_game/generator/generator.gd") as Script
	_generator = generator_script.new() as VoxelGeneratorScript
	var height_noise: FastNoiseLite = _generator.get("_heightmap_noise") as FastNoiseLite
	height_noise.seed = world_seed
	_terrain = VoxelTerrain.new()
	_terrain.name = "BenchmarkTerrain"
	_terrain.generator = _generator
	_terrain.mesher = load("res://blocky_game/blocks/mesher.tres") as VoxelMesherBlocky
	_terrain.max_view_distance = view_distance
	_terrain.mesh_block_size = 16
	_terrain.generate_collisions = generate_collisions
	_terrain.stream = null
	_terrain.block_loaded.connect(_on_block_loaded)
	_terrain.block_unloaded.connect(_on_block_unloaded)
	add_child(_terrain)
	_tool = _terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_tool.mode = VoxelTool.MODE_SET
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 56, 0)
	_camera.far = 2048.0
	_camera.current = true
	add_child(_camera)
	_camera.rotation_degrees = Vector3(-25, -35, 0)
	_viewer = VoxelViewer.new()
	_viewer.view_distance = view_distance
	_viewer.requires_collisions = generate_collisions
	_camera.add_child(_viewer)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	light.shadow_enabled = true
	add_child(light)
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.3, 0.5, 0.7)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.8, 1.0)
	environment.ambient_light_energy = 0.7
	environment_node.environment = environment
	add_child(environment_node)
	_running = true
	_sampling = scenario == "initial_load"
	if _sampling:
		_sample_start_usec = _start_usec
	set_process(true)

func _process(_delta: float) -> void:
	if not _running:
		return
	var now: int = Time.get_ticks_usec()
	var frame_seconds: float = float(now - _last_usec) / 1000000.0
	_last_usec = now
	var elapsed: float = float(now - _start_usec) / 1000000.0
	if _center_ready_ms < 0.0 and _terrain.is_area_meshed(AABB(Vector3(-16, 0, -16), Vector3(32, 64, 32))):
		_center_ready_ms = elapsed * 1000.0
	if not _sampling:
		if elapsed < warmup_seconds:
			_status.text = "WARMUP %.1f / %.1fs" % [elapsed, warmup_seconds]
			return
		if _center_ready_ms < 0.0:
			_finish("warmup_incomplete")
			return
		_sampling = true
		_sample_start_usec = now
		return # Exclude the interval spanning the warmup boundary.
	var measured: float = float(now - _sample_start_usec) / 1000000.0
	_frames.append(Vector2(measured, frame_seconds * 1000.0))
	if scenario == "streaming":
		_camera.position = Vector3(movement_speed * measured, 56, movement_speed * measured * 0.5)
	elif scenario == "editing":
		_apply_edits(frame_seconds)
	var second: int = int(measured)
	if second != _counter_second:
		_counter_second = second
		_counters.append({
			"t_s": measured, "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
			"video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
			"terrain": _terrain.get_statistics(), "engine": VoxelEngine.get_stats(),
			"loaded_events": _loaded, "unloaded_events": _unloaded, "edits_applied": _applied, "edits_skipped": _skipped
		})
		_status.text = "%s | distance %d | %.1f / %.1fs
Edits %d, skipped %d
Esc: abort and save partial results" % [scenario, view_distance, measured, sample_seconds, _applied, _skipped]
	if measured >= sample_seconds:
		_finish("completed")

func _apply_edits(dt: float) -> void:
	_edit_accumulator += dt * edits_per_second
	var due: int = int(_edit_accumulator)
	_edit_accumulator -= float(due)
	if due > 32:
		_skipped += due - 32
	for operation: int in mini(due, 32):
		var x: int = (_edit_index % 16) - 8
		@warning_ignore("integer_division")
		var z: int = ((_edit_index / 16) % 16) - 8
		_edit_index += 1
		var height: int = int(_generator.call("_get_height_at", x, z))
		var target: Vector3i = Vector3i(x, height - 1, z)
		if not _tool.is_area_editable(AABB(Vector3(target) - Vector3.ONE, Vector3.ONE * 3.0)):
			_skipped += 1
			continue
		_tool.value = 1 if _tool.get_voxel(target) == 0 else 0
		_tool.do_point(target)
		_applied += 1

func _on_block_loaded(_position: Vector3i) -> void:
	_loaded += 1

func _on_block_unloaded(_position: Vector3i) -> void:
	_unloaded += 1

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _running:
			_finish("aborted")
		else:
			get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _running:
			_finish("aborted")
		else:
			get_tree().quit()

func _finish(status: String) -> void:
	_running = false
	set_process(false)
	if status == "completed" and _center_ready_ms < 0.0:
		status = "no_center_mesh"
	if status == "completed" and scenario == "editing" and _applied == 0:
		status = "no_edits_applied"
	_failed = status != "completed"
	var sorted_ms: Array[float] = []
	var sum_ms: float = 0.0
	var over_33: int = 0
	var over_50: int = 0
	for row: Vector2 in _frames:
		sorted_ms.append(row.y)
		sum_ms += row.y
		if row.y > 33.333:
			over_33 += 1
		if row.y > 50.0:
			over_50 += 1
	sorted_ms.sort()
	var mean_ms: float = sum_ms / maxf(float(sorted_ms.size()), 1.0)
	var summary: Dictionary = {
		"status": status, "frames": sorted_ms.size(),
		"mean_fps": 1000.0 / mean_ms if mean_ms > 0.0 else 0.0,
		"frame_ms_mean": mean_ms, "frame_ms_p50": _percentile(sorted_ms, 0.50),
		"frame_ms_p95": _percentile(sorted_ms, 0.95), "frame_ms_p99": _percentile(sorted_ms, 0.99),
		"frame_ms_max": sorted_ms.back() if not sorted_ms.is_empty() else 0.0,
		"frames_over_33ms": over_33, "frames_over_50ms": over_50, "first_center_meshed_ms": _center_ready_ms,
		"center_ready_definition": "central 32x64x32 mesh area, not whole viewing range or collision readiness",
		"edits_applied": _applied, "edits_skipped": _skipped,
		"loaded_events": _loaded, "unloaded_events": _unloaded,
		"terrain_final": _terrain.get_statistics(), "engine_final": VoxelEngine.get_stats()
	}
	var csv: FileAccess = FileAccess.open(_output.path_join("frames.csv"), FileAccess.WRITE)
	if csv == null:
		_failed = true
	else:
		csv.store_csv_line(PackedStringArray(["elapsed_s", "frame_ms"]))
		for row: Vector2 in _frames:
			csv.store_csv_line(PackedStringArray([str(row.x), str(row.y)]))
		csv.close()
	if not _write_json("counters.json", _counters):
		_failed = true
	if not _write_json("summary.json", summary):
		_failed = true
	_metadata["status"] = status
	if not _write_json("metadata.json", _metadata):
		_failed = true
	print("BENCHMARK_RESULT ", JSON.stringify(summary))
	print("BENCHMARK_OUTPUT ", ProjectSettings.globalize_path(_output))
	get_tree().quit(1 if _failed else 0)

func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	return values[clampi(int(ceil(float(values.size()) * fraction)) - 1, 0, values.size() - 1)]

func _write_json(filename: String, value: Variant) -> bool:
	var file: FileAccess = FileAccess.open(_output.path_join(filename), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write " + filename)
		return false
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
	return true
