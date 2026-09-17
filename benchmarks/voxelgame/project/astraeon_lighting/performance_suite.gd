extends SceneTree
## Opt-in fixed-resolution cost experiment. Never executes without --run-cost-suite.
const Sample: Script = preload("res://astraeon_lighting/lighting_sample.gd")
var sample: Sample
var plan: Dictionary = {}
var output: String = ""
var events: FileAccess
var started_usec: int = 0
var epoch: float = 0.0
var drive: bool = false
var motion: String = "outdoor"
var motion_clock: float = 0.0
var update_ms: float = 0.0
var current_lamps: int = -1
var camera_origin: Vector3
var camera_target: Vector3
var failed: bool = false
var segment_serial: int = 0
var edit_pending: bool = false
var edit_started: int = 0
var edit_finished_ms: float = -1.0

func _initialize() -> void:
	var authorized: bool = false
	var manifest: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--run-cost-suite": authorized = true
		elif argument.begins_with("--manifest="): manifest = argument.trim_prefix("--manifest=")
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	if not authorized or manifest.is_empty() or output.is_empty():
		print("No performance test started. Requires --run-cost-suite, --manifest and --output.")
		quit(2)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest))
	if not parsed is Dictionary or parsed.get("format", "") != "astraeon-lighting-cost-1":
		push_error("Unsupported performance manifest")
		quit(2)
		return
	plan = parsed
	started_usec = Time.get_ticks_usec()
	epoch = Time.get_unix_time_from_system()
	_run.call_deferred()

func _elapsed() -> float:
	return (Time.get_ticks_usec() - started_usec) / 1000000.0

func _expired(limit: float = 3480.0) -> bool:
	return failed or _elapsed() >= limit

func _log(record: Dictionary) -> void:
	record["elapsed_seconds"] = _elapsed()
	record["unix_seconds"] = epoch + _elapsed()
	events.store_line(JSON.stringify(record))
	events.flush()

func _process(delta: float) -> bool:
	if not drive or sample == null: return false
	var begin: int = Time.get_ticks_usec()
	motion_clock += delta
	if motion == "moving":
		sample._camera.position = camera_origin + Vector3(sin(motion_clock * 0.8) * 2.0, 0, 0)
		sample._camera.look_at(camera_target)
	sample._process(delta)
	update_ms = (Time.get_ticks_usec() - begin) / 1000.0
	if edit_pending and _settled():
		edit_finished_ms = (Time.get_ticks_usec() - edit_started) / 1000.0
		edit_pending = false
	return false

func _settled() -> bool:
	return sample._volume.is_settled() and sample._sections.pending_count() == 0 and sample._uploaded_revision == sample._volume.revision

func _wait(seconds: float) -> void:
	var end: float = _elapsed() + seconds
	while _elapsed() < end and not _expired(): await process_frame

func _converge() -> bool:
	var end: float = _elapsed() + 60.0
	while not _settled() and _elapsed() < end and not _expired(): await process_frame
	return _settled()

func _set_profile(values: Dictionary) -> void:
	var settings: AstraeonLightingProfile = AstraeonLightingProfile.new()
	for key: String in values:
		if not plan.properties.has(key):
			failed = true
			push_error("Unknown performance setting: " + key)
			return
		var value: Variant = values[key]
		var kind: String = plan.properties[key].type
		if kind == "Color": value = Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
		elif kind == "int": value = int(value)
		elif kind == "float": value = float(value)
		settings.set(key, value)
	sample._settings = settings

func _view(scene: String) -> void:
	motion = scene
	match scene:
		"water_wide": camera_origin = Vector3(30,10,-5); camera_target = Vector3(20,0,-17)
		"water_close": camera_origin = Vector3(23,3,-12); camera_target = Vector3(23,1,-25)
		"water_away": camera_origin = Vector3(23,3,-12); camera_target = Vector3(23,4,25)
		"underwater": camera_origin = Vector3(23,-2,-14); camera_target = Vector3(25,-2,-22)
		"lamps": camera_origin = Vector3(-14,8,31); camera_target = Vector3(-14,1,20)
		"cave": camera_origin = Vector3(16,-4,-0.5); camera_target = Vector3(-16,-4,0)
		"plants": camera_origin = Vector3(-27,2,-9); camera_target = Vector3(-20,3,-20)
		_: camera_origin = Vector3(23,17,27); camera_target = Vector3(0,4,0)
	sample._view(camera_origin,camera_target)

func _reset_motion() -> void:
	motion_clock = 0.0
	sample._cloud_clock = 0.0
	sample._details.water_clock = 0.0
	sample._details.wind_clock = 0.0
	sample._avatar.move_to(Vector3(23,1,-26))
	for limb: Node3D in sample._avatar.limbs: limb.rotation.x = 0.0
	sample._local_lights._elapsed = 0.0
	sample._planar._elapsed = 0.0
	sample._planar._force = true
	sample._view(camera_origin,camera_target)

func _prepare(job: Dictionary, state: String) -> bool:
	if sample._batch_enabled:
		sample._toggle_batch()
		if not await _converge(): return false
	var cfg: Dictionary = job.settings.duplicate(true)
	cfg[job.key] = job[state.to_lower()]
	var lamps: int = int(job.lamps)
	if job.kind == "cardinality":
		lamps = int(cfg.test_light_count)
		cfg.test_light_count = maxi(1, lamps)
	var begin: int = Time.get_ticks_usec()
	_set_profile(cfg)
	if failed: return false
	_view(job.scene)
	if lamps != current_lamps:
		sample._clear_test_lamps()
		if lamps > 0:
			sample._settings.test_light_count = lamps
			sample._place_test_lamps()
		current_lamps = lamps
	_reset_motion()
	sample._apply_lighting()
	_log({"event":"switch", "case":job.id,"state":state,"apply_ms":(Time.get_ticks_usec()-begin)/1000.0})
	if not await _converge(): return false
	if job.kind == "edit_remove":
		sample._toggle_batch()
		if not await _converge(): return false
	await _wait(float(plan.settle_seconds))
	return not _expired()

func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty(): return -1.0
	values.sort()
	return values[int((values.size()-1)*fraction)]

func _capture(job: Dictionary, state: String, round_index: int, seconds: float) -> Dictionary:
	segment_serial += 1
	var rows: Array[PackedFloat64Array] = []
	var begin: int = Time.get_ticks_usec()
	var previous: int = begin
	var previous_captures: int = sample._planar.captures
	var done: bool = false
	edit_finished_ms = -1.0
	var edit_apply_ms: float = 0.0
	if str(job.kind).begins_with("edit_"):
		edit_pending = true
		edit_started = Time.get_ticks_usec()
		sample._toggle_batch()
		edit_apply_ms = (Time.get_ticks_usec()-edit_started)/1000.0
	var effective_settings: Dictionary = {}
	for property: Dictionary in sample._settings.settings_properties():
		var value: Variant = sample._settings.get(property.name)
		if value is Color:
			var color: Color = value
			value = [color.r,color.g,color.b,color.a]
		effective_settings[property.name] = value
	var unix_begin: float = epoch + _elapsed()
	while not done and not _expired():
		await RenderingServer.frame_post_draw
		if root.size != Vector2i(1920,1080) or not root.has_focus():
			failed = true
			_log({"event":"fatal", "reason":"window changed during capture", "case":job.id})
			break
		var now: int = Time.get_ticks_usec()
		var frame_ms: float = (now-previous)/1000.0
		previous = now
		var root_rid: RID = root.get_viewport_rid()
		var reflect_rid: RID = sample._planar.viewport.get_viewport_rid()
		var reflected: bool = sample._planar.captures != previous_captures
		previous_captures = sample._planar.captures
		var gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(root_rid)
		var reflection_gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(reflect_rid) if reflected else 0.0
		var render_cpu: float = RenderingServer.get_frame_setup_time_cpu() + RenderingServer.viewport_get_measured_render_time_cpu(root_rid)
		if reflected: render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(reflect_rid)
		rows.append(PackedFloat64Array([epoch+_elapsed(),frame_ms,update_ms,gpu,reflection_gpu,render_cpu,
			float(reflected),float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))]))
		done = (now-begin)/1000000.0 >= seconds
	# Persist outside the measured interval, one segment at a time for crash recovery.
	var filename: String = "%04d-%s-%s.csv" % [segment_serial, job.id, state]
	var file: FileAccess = FileAccess.open(output.path_join(filename), FileAccess.WRITE)
	if file == null:
		failed = true
		return {}
	file.store_line("unix_seconds,frame_ms,update_cpu_ms,gpu_main_ms,gpu_reflection_ms,render_cpu_ms,reflection_scheduled,draw_calls,primitives,video_mem_bytes")
	var frame_times: Array[float] = []
	for row: PackedFloat64Array in rows:
		var strings: PackedStringArray = []
		for number: float in row: strings.append("%.6f" % number)
		file.store_line(",".join(strings))
		frame_times.append(row[1])
	file.close()
	var record: Dictionary = {"event":"segment","case":job.id,"state":state,"round":round_index,
		"file":filename,"complete":done,"start_unix":unix_begin,"end_unix":epoch+(previous-started_usec)/1000000.0,
		"frames":rows.size(),"frame_median":_percentile(frame_times,0.5),
		"edit_apply_ms":edit_apply_ms,"edit_complete_ms":edit_finished_ms,
		"point_lights":sample._local_lights.active_points,"shadow_lights":sample._local_lights.active_shadows,
		"reflection_valid":sample._planar._valid,"resolution":[root.size.x,root.size.y],
		"settings":effective_settings,"tested_value":job[state.to_lower()]}
	_log(record)
	return record

func _pair(job: Dictionary, round_index: int) -> bool:
	var records: Array[Dictionary] = []
	var order: Array[String] = ["A","B","B","A"] if round_index == 0 else ["B","A","A","B"]
	for state: String in order:
		if _expired(): return false
		if not await _prepare(job,state):
			_log({"event":"skipped","case":job.id,"reason":"convergence timeout or budget"})
			return true
		records.append(await _capture(job,state,round_index,float(plan.sample_seconds)))
	if records.size() < 4 or records.any(func(r: Dictionary) -> bool: return r.is_empty()): return false
	var ref_indices: Array[int] = [0,3] if round_index == 0 else [1,2]
	var test_indices: Array[int] = [1,2] if round_index == 0 else [0,3]
	var a0: float = records[ref_indices[0]].frame_median
	var a1: float = records[ref_indices[1]].frame_median
	var delta0: float = records[test_indices[0]].frame_median-a0
	var delta1: float = records[test_indices[1]].frame_median-a1
	var drift: float = absf(a1-a0)/maxf(a0,0.001)
	_log({"event":"pair","case":job.id,"round":round_index,"baseline_drift":drift,
		"delta_ms":[delta0,delta1]})
	return drift > 0.05 or delta0*delta1 < 0.0 or absf(delta0-delta1) > 0.15

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Cost measurements require actual rendering")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	events = FileAccess.open(output.path_join("events.jsonl"),FileAccess.WRITE)
	if events == null: quit(2); return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920,1080)
	root.content_scale_size = Vector2i.ZERO
	root.scaling_3d_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	sample = load("res://astraeon_lighting/lighting_sample.tscn").instantiate() as Sample
	sample.settings_path = output.path_join("isolated-settings.cfg")
	sample.benchmark_mode = true
	root.add_child(sample)
	sample.set_process(false)
	_set_profile(plan.base)
	sample._start()
	for child: Node in sample.get_children():
		if child is CanvasLayer: (child as CanvasLayer).hide()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	RenderingServer.viewport_set_measure_render_time(sample._planar.viewport.get_viewport_rid(),true)
	drive = true
	_log({"event":"start","engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),
		"api":RenderingServer.get_video_adapter_api_version(),"cpu":OS.get_processor_name(),
		"gpu_metric":"Godot viewport timings; reflection cadence-weighted estimate, NOT PresentMon GPU Busy",
		"cpu_metric":"sample update wall time and render CPU; NOT total CPU utilization"})
	if not await _converge():
		_log({"event":"fatal","reason":"initial convergence timeout"}); quit(2); return
	# Bring the GPU under a representative fixed load, without collecting benchmark frames.
	_set_profile(plan.base.merged({"water_enabled":true,"water_reflection_mode":2,"shadows_enabled":true,"clouds_enabled":true},true))
	_view("water_close")
	sample._apply_lighting()
	await _wait(float(plan.initial_warm_seconds))
	var retry: Array[Dictionary] = []
	for entry: Variant in plan.cases:
		var job: Dictionary = entry
		if _expired(float(plan.primary_deadline_seconds)): break
		if root.size != Vector2i(1920,1080) or not root.has_focus():
			_log({"event":"fatal","reason":"window resized or lost focus"}); failed = true; break
		if await _pair(job,0): retry.append(job)
	for job: Dictionary in retry:
		if _expired(float(plan.retry_deadline_seconds)): break
		await _pair(job,1)
	# Two explicitly labelled sustained combinations; no claim of full thermal equilibrium.
	for cap: int in [0,120]:
		if _expired(float(plan.stop_sampling_seconds)-65): break
		var combo: Dictionary = {"id":"combo-%d" % cap,"key":"max_fps","a":cap,"b":cap,
			"scene":"water_close","lamps":16,"kind":"sustained","settings":plan.base.merged({
			"water_enabled":true,"water_reflection_mode":2,"shadows_enabled":true,"clouds_enabled":true,
			"avatar_visible":true,"avatar_animate":true,"max_fps":cap},true)}
		if await _prepare(combo,"A"): await _capture(combo,"A",0,float(plan.sustained_seconds))
	_log({"event":"finish","failed":failed,"deadline_reached":_elapsed()>=float(plan.primary_deadline_seconds)})
	drive = false
	sample.queue_free()
	await process_frame
	events.close()
	quit(1 if failed else 0)
