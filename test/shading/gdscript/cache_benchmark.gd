extends SceneTree
## Deterministic main-world paths. Actual rendering, fixed quality, no input simulation.
var world: Node3D
var output: String = ""
var distance: int = 64
var seconds: float = 8.0
var reverse: bool = false
var legacy: bool = false
var selected: PackedStringArray = []
var rows: Array[Dictionary] = []
var summaries: Array[Dictionary] = []
var failures: Array[String] = []
var phase: String = ""
var measuring: bool = false
var last_tick: int = 0
var diagnostic: Dictionary = {}
var base: Vector3
func _initialize() -> void: call_deferred("_run")
func _process(_delta: float) -> bool:
    var now: int = Time.get_ticks_usec()
    if measuring and last_tick > 0:
        var metrics: Dictionary = _metrics()
        rows.append({"phase":phase,"ms":float(now-last_tick)/1000.0,"focus":root.has_focus(),"cache":metrics,"diagnostic":diagnostic.duplicate(),"terrain":world.terrain.get_statistics(),"planar_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(world.shading.planar.viewport.get_viewport_rid()),"planar_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(world.shading.planar.viewport.get_viewport_rid()),"cache_tick_usec":0 if legacy else world.cache_coordinator.diagnostic_usec,"frame_setup_cpu_ms":RenderingServer.get_frame_setup_time_cpu(),"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,"draw_compile":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW),"specialization_compile":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),"render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())})
        rows.back()["record_usec"] = Time.get_ticks_usec()-now
    diagnostic.clear()
    last_tick = now
    return false
func _event(kind: StringName, _start: int, usec: int) -> void:
    if measuring: diagnostic[String(kind)] = float(usec)/1000.0
func _metrics() -> Dictionary:
    if legacy: return {"page_uploads":world.shading.field_publications}
    return world.cache_coordinator.native.call("get_cache_metrics")
func _settle() -> bool:
    var deadline: int = Time.get_ticks_msec()+120000
    var stable: int = 0
    while Time.get_ticks_msec()<deadline:
        if world.shading.is_ready():
            if stable == 0: stable = Time.get_ticks_msec()
            if Time.get_ticks_msec()-stable >= 1500: return true
        else: stable = 0
        await process_frame
    return false
func _pose(kind: String, elapsed: float) -> void:
    var p: Vector3 = base
    var angle: float = elapsed*PI*0.5
    if kind.begins_with("move_"): p.x += elapsed*float(kind.trim_prefix("move_"))
    if kind == "return_22": p.x += maxf(0.0,seconds*0.5-absf(elapsed-seconds*0.5))*22.0
    if kind == "continuous_40": p += Vector3(elapsed*32.0,0,elapsed*24.0)
    if kind == "teleport" and elapsed > seconds*0.25: p.x += 512.0
    world.player.velocity = Vector3.ZERO
    if kind.begins_with("move_"): world.player.velocity.x = float(kind.trim_prefix("move_"))
    if kind == "continuous_40": world.player.velocity = Vector3(32,0,24)
    if kind == "return_22": world.player.velocity.x = 22.0 if elapsed<seconds*0.5 else -22.0
    world.player.global_position = p
    var target: Vector3 = p+Vector3.UP*1.35
    if kind.begins_with("orbit"):
        world.camera.global_position = target+Vector3(sin(angle)*4,1,cos(angle)*4)
        world.camera.look_at(target)
    else:
        world.camera.global_position = target+Vector3(0,2,4)
        world.camera.rotation = Vector3(-0.2,angle if kind == "yaw" else 0.0,0)
func _run() -> void:
    root.mode = Window.MODE_FULLSCREEN
    await process_frame
    if root.size != Vector2i(1920,1080):
        push_error("Cache benchmark requires a 1920x1080 display mode; actual: "+str(root.size))
        quit(1)
        return
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
        if arg.begins_with("--distance="): distance = int(arg.trim_prefix("--distance="))
        if arg.begins_with("--seconds="): seconds = float(arg.trim_prefix("--seconds="))
        if arg == "--reverse": reverse = true
        if arg == "--legacy": legacy = true
        if arg.begins_with("--actions="): selected = arg.trim_prefix("--actions=").split(",")
    if output.is_empty(): output = "res://tmp/cache-benchmark/"+str(Time.get_ticks_usec())
    DirAccess.make_dir_recursive_absolute(output)
    world = (load("res://game/core/main.tscn") as PackedScene).instantiate()
    world.world_directory = output+"/world"
    world.shading_settings_path = output+"/no-settings.cfg"
    world.horizontal_distance = distance
    world.biome_layout = 1
    world.get_node("Player/Controller").input_enabled = false
    preload("res://test/survival/gdscript/world_fixture.gd").prepare(world)
    root.add_child(world)
    RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
    RenderingServer.viewport_set_measure_render_time(world.shading.planar.viewport.get_viewport_rid(),true)
    world.shading.diagnostics_enabled = true
    world.shading.diagnostic_timing.connect(_event)
    var started: int = Time.get_ticks_msec()
    if not await _settle():
        failures.append("Initial world did not settle")
        await _finish()
        return
    var initial_load_ms: int = Time.get_ticks_msec()-started
    world.controller.set_physics_process(false)
    world.camera.reparent(world)
    world.set_process(false)
    base = world.player.global_position
    base.x = 8.0
    base.z = 8.0
    var p: Resource = world.shading._settings
    p.max_fps = 0
    p.vsync_enabled = false
    p.cycle_enabled = false
    p.hour = 12.0
    p.weather_mode = 0
    world.shading._apply_lighting()
    var actions: Array[String] = ["static","yaw","orbit_center","orbit_boundary","move_8","move_22","move_40","return_22","continuous_40","teleport","isolate_coordinator","isolate_effects","isolate_terrain","isolate_cloud_clock","isolate_wind_clock","isolate_planar","isolate_pool32","isolate_pool128"]
    if reverse: actions.reverse()
    for kind: String in actions:
        if not selected.is_empty() and not selected.has(kind): continue
        if kind.begins_with("isolate_") and not selected.has(kind): continue
        measuring = false
        phase = kind
        base.x = 16.0 if kind == "orbit_boundary" else 8.0
        _pose(kind,0.0)
        if not await _settle():
            failures.append(kind+": did not settle before measurement")
            break
        if kind == "isolate_coordinator": world.cache_coordinator.set_process(false)
        if kind == "isolate_effects": world.shading.set_process(false)
        if kind == "isolate_terrain": world.terrain.set_process(false)
        if kind == "isolate_cloud_clock": world.shading._settings.cloud_speed = 0.0
        if kind == "isolate_wind_clock": world.shading._settings.wind_enabled = false
        if kind == "isolate_planar": world.shading.planar.active = false
        if kind == "isolate_pool32" or kind == "isolate_pool128":
            world.cache_coordinator.policy.values.gpu_mib = 32 if kind == "isolate_pool32" else 128
            await world.cache_coordinator.apply_policy()
            await _settle()
        var before: Dictionary = _metrics()
        var io_before: Dictionary = world.stream.get_metrics()
        var generation_before: Dictionary = world.generator.get_metrics()
        var start_index: int = rows.size()
        var start: int = Time.get_ticks_usec()
        measuring = true
        last_tick = 0
        while Time.get_ticks_usec()-start < seconds*1000000.0:
            _pose(kind,float(Time.get_ticks_usec()-start)/1000000.0)
            await process_frame
        measuring = false
        world.player.velocity = Vector3.ZERO
        var after: Dictionary = _metrics()
        var stop: int = Time.get_ticks_msec()
        var converged: bool = await _settle()
        var convergence_ms: int = Time.get_ticks_msec()-stop
        if not converged: failures.append(kind+": queue failed to converge")
        var values: Array[float] = []
        var unfocused: int = 0
        var slow: int = 0
        var light_slow: int = 0
        var latencies: Array[float] = []
        var previous_uploads: int = int(before.get("page_uploads",0))
        var compilation_frames: int = 0
        var previous_compilations: float = -1.0
        for row: Dictionary in rows.slice(start_index):
            values.append(float(row.ms))
            var uploads: int = int(row.cache.get("page_uploads",0))
            if not legacy and uploads != previous_uploads: latencies.append(float(row.cache.get("light_latency_usec",0))/1000.0)
            previous_uploads = uploads
            var compilations: float = float(row.draw_compile)+float(row.specialization_compile)
            if previous_compilations>=0.0 and compilations>previous_compilations: compilation_frames += 1
            previous_compilations = compilations
            if not row.focus: unfocused += 1
            if row.ms > 16.7: slow += 1
            var light_ms: float = float(row.diagnostic.get("snapshot",0.0))+float(row.diagnostic.get("publish",0.0))
            if legacy and light_ms > 16.7: light_slow += 1
            if not legacy and float(row.cache.get("upload_usec",0))/1000.0 > 16.7: light_slow += 1
        values.sort()
        var total: float = 0.0
        for value: float in values: total += value
        var low_count: int = maxi(1,ceili(values.size()*0.01))
        var low_total: float = 0.0
        for value: float in values.slice(values.size()-low_count): low_total += value
        var summary: Dictionary = {"phase":kind,"frames":values.size(),"fps":1000.0*values.size()/maxf(total,0.001),"low":1000.0*low_count/maxf(low_total,0.001),"median_ms":values[values.size()/2],"p99_ms":values[mini(values.size()-1,ceili(values.size()*0.99)-1)],"max_ms":values.back(),"slow_frames":slow,"light_slow_frames":light_slow,"unfocused":unfocused,"initial_load_ms":initial_load_ms,"convergence_ms":convergence_ms,"cache_before":before,"cache_after":after,"cache_settled":_metrics(),"io_before":io_before,"io_after":world.stream.get_metrics(),"generation_before":generation_before,"generation_after":world.generator.get_metrics(),"terrain":world.terrain.get_statistics()}
        latencies.sort()
        summary["light_latency_p99_ms"] = latencies[mini(latencies.size()-1,ceili(latencies.size()*0.99)-1)] if not latencies.is_empty() else 0.0
        summary["compilation_frames"] = compilation_frames
        summaries.append(summary)
        print("CACHE_PHASE ",JSON.stringify(summary))
    await _finish()
func _finish() -> void:
    var quality: Dictionary = {}
    if world != null and world.shading != null:
        for property: Dictionary in world.shading._settings.get_property_list():
            if int(property.usage)&PROPERTY_USAGE_STORAGE and not String(property.name).begins_with("resource_"):
                quality[property.name] = world.shading._settings.get(property.name)
    var result: Dictionary = {"quality":quality,"viewport":str(root.size),"distance":distance,"seconds":seconds,"legacy":legacy,"reverse":reverse,"position":str(base),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"failures":failures,"summaries":summaries}
    # Capture before serializing thousands of diagnostic rows. Serialization is outside
    # the measured phases and must not contaminate the frame-time HUD in the evidence.
    if world != null and world.shading != null:
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png(output+"/final.png")
    var file: FileAccess = FileAccess.open(output+"/results.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(result,"  "))
    file.close()
    file = FileAccess.open(output+"/frames.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(rows))
    file.close()
    if world != null:
        world.queue_free()
    for frame: int in range(3): await process_frame
    print("CACHE_BENCHMARK ",output)
    quit(0 if failures.is_empty() else 1)
