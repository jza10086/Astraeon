extends Node3D
## Explicitly armed benchmark. Opening the scene alone never starts generation or writes saves.
const CONFIG: Script = preload("res://game/world/generation/world_config.gd")
const CATALOG: Script = preload("res://game/world/generation/terrain_catalog.gd")
const GENERATOR: Script = preload("res://game/world/generation/terrain_generator.gd")
const TELEMETRY: Script = preload("res://tests/world/telemetry_writer.gd")
const RUNTIME: Script = preload("res://game/world/runtime/world_runtime.gd")
var _telemetry: AstraeonTelemetryWriter
var _last_telemetry: int = 0
var _runtime: AstraeonWorldRuntime
var _camera: Camera3D
var _label: Label
var _sampler: AstraeonTerrainGenerator
var _ids: PackedInt32Array
var _options: Dictionary[String, String] = {}
var _records: Array[Dictionary] = []
var _frames: Array[PackedFloat64Array] = []
var _phase: int = 0
var _phase_started: int = 0
var _started: int = 0
var _last_frame: int = 0
var _last_edit: int = 0
var _last_observer: int = 0
var _run_id: String
var _output: String
var _world_path: String
var _armed: bool = false
var _finishing: bool = false
var _duration: float = 30.0
var _initial_timeout: float = 240.0
var _edit_attempts: int = 0
var _edit_successes: int = 0
var _phase_outcomes: Array[Dictionary] = []
var _phase_names: PackedStringArray = PackedStringArray(["initial", "stationary", "explore", "return", "teleport", "edit", "drain"])
var _manifest: Dictionary = {}

func _ready() -> void:
	_label = Label.new()
	_label.text = "World laboratory ready. Use tools/run_world_suite.py --run after authorization."
	_label.position = Vector2(16, 16)
	add_child(_label)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--"):
			var parts: PackedStringArray = argument.substr(2).split("=", true, 1)
			_options[parts[0]] = parts[1] if parts.size() == 2 else "true"
	if not _options.has("run"):
		return
	if DisplayServer.get_name() == "headless":
		push_error("Graphical benchmark requires a real renderer")
		get_tree().quit(2)
		return
	_start()

func _start() -> void:
	var config: AstraeonWorldConfig = CONFIG.new()
	config.generation_mode = int(_options.get("generator", "0"))
	config.layout = int(_options.get("layout", "1"))
	config.world_seed = int(_options.get("seed", "20260916"))
	var backend: int = int(_options.get("backend", "1"))
	var codec: int = int(_options.get("codec", "0"))
	var organization: int = int(_options.get("files", "1"))
	_duration = maxf(2.0, float(_options.get("seconds", "30")))
	_run_id = _options.get("run-id", str(Time.get_ticks_usec()))
	_output = _options.get("output", "res://tmp/world_lab/" + _run_id)
	_world_path = _options.get("world", _output.path_join("world"))
	if DirAccess.make_dir_recursive_absolute(_output) != OK:
		get_tree().quit(2)
		return
	var registry: AstraeonBlockRegistry = CATALOG.build_registry()
	_ids = CATALOG.ids(registry)
	_sampler = GENERATOR.new()
	_sampler.configure(config, _ids)
	_runtime = RUNTIME.new()
	_runtime.horizontal_distance = int(_options.get("horizontal", "64"))
	_runtime.vertical_distance = int(_options.get("vertical", "32"))
	var error: String = _runtime.configure(config, registry, _ids, _world_path, backend, codec, organization, int(_options.get("workers", "2")))
	if not error.is_empty():
		push_error(error)
		get_tree().quit(2)
		return
	_runtime.task_record.connect(_record)
	add_child(_runtime)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.5, 0.65, 0.85)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.45
	add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.shadow_enabled = true
	add_child(light)
	_camera = Camera3D.new()
	_camera.far = 512.0
	_camera.current = true
	add_child(_camera)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1280, 720)
	Engine.max_fps = 0
	_telemetry = TELEMETRY.new()
	if not _telemetry.configure(_output):
		push_error(_telemetry.error)
		get_tree().quit(2)
		return
	get_tree().auto_accept_quit = false
	_started = Time.get_ticks_usec()
	_last_frame = _started
	_phase_started = _started
	_manifest = {"run_id": _run_id, "config": config.snapshot(), "backend": backend, "codec": codec, "organization": organization, "options": _options, "engine": Engine.get_version_info(), "debug": OS.is_debug_build(), "os": OS.get_name(), "cpu": OS.get_processor_name(), "logical_cpus": OS.get_processor_count(), "renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "gl_compatibility")), "adapter": RenderingServer.get_video_adapter_name(), "resolution": [1280, 720], "gpu_timing": "unavailable", "read_cache_class": "new_process_os_cache_uncontrolled", "status": "running"}
	_write_json("manifest.json", _manifest)
	_armed = true

func _record(value: Dictionary) -> void:
	value["run_id"] = _run_id
	value["phase"] = _phase_names[_phase]
	value["recorded_us"] = Time.get_ticks_usec()
	_records.append(value)

func _process(_delta: float) -> void:
	if not _armed or _finishing:
		return
	var now: int = Time.get_ticks_usec()
	if not _runtime.failed.is_empty():
		_finish("failed", _runtime.failed)
		return
	if _telemetry.idle():
		if not _telemetry.error.is_empty():
			_finish("failed", _telemetry.error)
			return
		if now - _last_telemetry >= 2000000:
			_telemetry.submit(_frames, _records)
			_frames = []
			_records = []
			_last_telemetry = now
	var elapsed: float = float(now - _phase_started) / 1000000.0
	var fraction: float = clampf(elapsed / _duration, 0.0, 1.0)
	var x: float = 64.0
	if _phase == 2:
		x = lerpf(64.0, 1088.0, fraction)
	elif _phase == 3:
		x = lerpf(1088.0, 64.0, fraction)
	elif _phase >= 4:
		x = 2112.0
	var z: float = 64.0
	var height: float = maxf(float(_sampler.config.sea_level), _sampler.sample_exact(int(x), int(z)).x)
	var focus: Vector3 = Vector3(x, height + 2.0, z)
	_camera.position = focus + Vector3(12, 20, 24)
	_camera.look_at(focus)
	if now - _last_observer >= 250000 and _phase < 6:
		_runtime.set_observer(focus)
		_last_observer = now
	if _phase == 5 and now - _last_edit >= 100000:
		for offset: int in range(16):
			var position: Vector3i = Vector3i(int(x) - 8 + offset, int(floor(height)), int(z))
			var state: int = _ids[0] if int(_edit_attempts / 16) % 2 == 0 else _ids[1]
			_edit_attempts += 1
			if _runtime.edit(position, state):
				_edit_successes += 1
		_runtime.flush_saves()
		_last_edit = now
	var frame_us: int = now - _last_frame
	_last_frame = now
	_frames.append(PackedFloat64Array([now - _started, _phase, frame_us, _runtime.sections.size(), _runtime.dirty_count(), _runtime.pending_count(), _runtime.missing_count(), _runtime.visible_missing_count(), OS.get_static_memory_usage(), Performance.get_monitor(Performance.TIME_PROCESS), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]))
	_label.text = "%s | %.1f s | resident %d | missing %d | dirty %d" % [_phase_names[_phase], elapsed, _runtime.sections.size(), _runtime.visible_missing_count(), _runtime.dirty_count()]
	if _frames.size() > 1500000 or _records.size() > 500000:
		_finish("incomplete", "Telemetry memory cap reached")
		return
	if _phase == 0:
		if _runtime.missing_count() == 0 and _runtime.visible_missing_count() == 0 and _runtime.pending_count() == 0:
			_next_phase(true)
		elif elapsed >= _initial_timeout:
			_next_phase(false)
	elif _phase == 6:
		if _runtime.dirty_count() == 0 and _runtime.pending_count() == 0:
			_finish("completed", "")
		elif elapsed >= _initial_timeout:
			_finish("incomplete", "Save drain timed out")
	elif elapsed >= _duration:
		_next_phase(_runtime.visible_missing_count() == 0)

func _next_phase(ready: bool) -> void:
	_phase_outcomes.append({"phase": _phase_names[_phase], "ready_at_end": ready, "elapsed_us": Time.get_ticks_usec() - _phase_started, "missing": _runtime.visible_missing_count(), "dirty": _runtime.dirty_count()})
	if _phase in [1, 2, 3, 4]:
		get_viewport().get_texture().get_image().save_png(_output.path_join("view_" + _phase_names[_phase] + ".png"))
	_phase += 1
	_phase_started = Time.get_ticks_usec()
	if _phase == 6:
		_runtime.stop_requests()

func _write_json(name: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_output.path_join(name), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "\t"))

func _finish(status: String, error: String) -> void:
	_finishing = true
	if status == "completed":
		for outcome: Dictionary in _phase_outcomes:
			if not outcome.ready_at_end:
				status = "incomplete"
				error = "One or more phases ended before visible terrain was ready"
		if _edit_successes < _edit_attempts:
			status = "incomplete"
			error = "Edit targets were not all resident"
	_runtime.stop_requests()
	_manifest["status"] = status
	_manifest["error"] = error
	_manifest["elapsed_us"] = Time.get_ticks_usec() - _started
	_manifest["phase_outcomes"] = _phase_outcomes
	_manifest["edit_attempts"] = _edit_attempts
	_manifest["edit_successes"] = _edit_successes
	_write_json("manifest.json", _manifest)
	_telemetry.finish(_frames, _records)
	if not _telemetry.error.is_empty():
		status = "failed"
		_manifest["status"] = status
		_manifest["error"] = _telemetry.error
		_write_json("manifest.json", _manifest)
	print("WORLD_LAB_RESULT " + JSON.stringify(_manifest))
	get_tree().quit(0 if status == "completed" else 2)



func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not _armed:
			get_tree().quit()
		elif not _finishing:
			_phase_outcomes.append({"phase": _phase_names[_phase], "ready_at_end": false, "reason": "user_closed_window"})
			_phase = 6
			_phase_started = Time.get_ticks_usec()
			_runtime.stop_requests()
