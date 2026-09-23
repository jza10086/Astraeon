extends Node
## Real main-world diagnostic. Camera paths are deterministic, not mouse-input or motor tests.
@export_range(16,256,16) var view_distance: int = 64
@export_range(2.0,30.0) var sample_seconds: float = 8.0
@export_range(1,4) var rounds: int = 1
@export var quit_when_finished: bool = true
var world: Node3D
var rows: Array[Dictionary] = []
var events: Array[Dictionary] = []
var summaries: Array[Dictionary] = []
var output: String
var phase: String = ""
var action: String = "static"
var frozen: bool = false
var measuring: bool = false
var driving: bool = false
var phase_start: int = 0
var last_tick: int = 0
var interval_phase: String = ""
var interval_events: Dictionary = {}
var interval_loads: int = 0
var interval_unloads: int = 0
var center: Vector3
var initial_center: Vector3
var label: Label
var failures: Array[String] = []

func _ready() -> void:
    process_priority = -1000 # Start-of-frame sampling, preceding the world's default-priority process.
    call_deferred("_run")

func _event(kind: StringName, start_usec: int, duration_usec: int) -> void:
    if not measuring: return
    interval_events[kind] = float(interval_events.get(kind,0.0))+duration_usec/1000.0
    events.append({"phase":phase,"kind":kind,"start_usec":start_usec,"duration_usec":duration_usec})

func _loaded(_position: Vector3i) -> void:
    if measuring: interval_loads += 1

func _unloaded(_position: Vector3i) -> void:
    if measuring: interval_unloads += 1

func _process(_delta: float) -> void:
    var now: int = Time.get_ticks_usec()
    if measuring and interval_phase == phase and last_tick > 0:
        rows.append({"phase":phase,"end_usec":now,"ms":(now-last_tick)/1000.0,
            "snapshot":interval_events.get(&"snapshot",0.0),"publish":interval_events.get(&"publish",0.0),
            "weather_map":interval_events.get(&"weather_map",0.0),
            "loaded":interval_loads,"unloaded":interval_unloads,
            "focused":get_window().has_focus(),"camera":world.camera.global_position})
    interval_events = {}
    interval_loads = 0
    interval_unloads = 0
    last_tick = now
    interval_phase = phase if measuring else ""
    if not driving: return
    var elapsed: float = (now-phase_start)/1000000.0
    _pose(elapsed)
    if frozen:
        # Test-only suppression of scheduling. Keep all render updates, viewers and prior texture.
        # Each phase settles workers first; loaded-data invalidations are discarded here.
        var p: Vector3 = world.camera.global_position
        var size: Vector3i = world.shading._size
        world.shading._requested_origin = Vector3i(floori(p.x/16.0)*16-size.x/2,-64,floori(p.z/16.0)*16-size.z/2)
        world.shading._dirty = false

func _pose(seconds: float) -> void:
    var angle: float = seconds*PI*0.5 # 90 degrees per second.
    var target: Vector3 = center+Vector3.UP*1.35
    world.player.global_position = center
    if action == "move":
        world.player.global_position = center+Vector3.RIGHT*seconds*8.0
        target = world.player.global_position+Vector3.UP*1.35
    if action.begins_with("orbit"):
        world.camera.global_position = target+Vector3(sin(angle)*4.0,1.0,cos(angle)*4.0)
        world.camera.look_at(target)
    else:
        world.camera.global_position = target+Vector3(0,2.0,4.0)
        world.camera.rotation = Vector3(-0.2,angle if action == "yaw" else 0.0,0)

func _settle() -> bool:
    var deadline: int = Time.get_ticks_msec()+90000
    var stable_since: int = 0
    while Time.get_ticks_msec()<deadline:
        if world.shading.is_ready():
            if stable_since == 0: stable_since = Time.get_ticks_msec()
            if Time.get_ticks_msec()-stable_since > 1500: return true
        else:
            stable_since = 0
        await get_tree().process_frame
    return false

func _run() -> void:
    for argument: String in OS.get_cmdline_user_args():
        if argument.begins_with("--seconds="): sample_seconds = clampf(argument.trim_prefix("--seconds=").to_float(),2.0,30.0)
        if argument.begins_with("--distance="): view_distance = clampi(argument.trim_prefix("--distance=").to_int(),16,256)
        if argument.begins_with("--rounds="): rounds = clampi(argument.trim_prefix("--rounds=").to_int(),1,4)
    output = "res://tmp/motion-stutter/"+str(Time.get_unix_time_from_system()).replace(".","-")
    DirAccess.make_dir_recursive_absolute(output)
    var layer: CanvasLayer = CanvasLayer.new()
    layer.layer = 100
    add_child(layer)
    label = Label.new()
    label.position = Vector2(24,230)
    label.text = "运动卡顿诊断：等待世界稳定…"
    layer.add_child(label)
    world = (load("res://game/core/main.tscn") as PackedScene).instantiate()
    world.world_directory = output+"/world"
    world.shading_settings_path = output+"/settings.cfg"
    world.horizontal_distance = view_distance
    world.biome_layout = 1
    world.get_node("Player/Controller").input_enabled = false
    add_child(world)
    world.shading.diagnostics_enabled = true
    world.shading.diagnostic_timing.connect(_event)
    world.terrain.block_loaded.connect(_loaded)
    world.terrain.block_unloaded.connect(_unloaded)
    if not await _settle():
        failures.append("Initial world did not settle")
        await _finish()
        return
    world.controller.set_physics_process(false)
    world.camera.reparent(world)
    # Suppress test autosave only, leave terrain/shading/viewer processes active.
    world.set_process(false)
    initial_center = world.player.global_position
    var p: Resource = world.shading._settings
    p.max_fps = 0
    p.vsync_enabled = false
    p.cycle_enabled = false
    p.hour = 12.0
    p.weather_mode = 0
    world.shading._apply_lighting()
    for round_index: int in range(rounds):
        for kind: String in ["static","yaw","orbit_center","orbit_boundary","move"]:
            var order: Array[bool] = [false,true]
            if round_index%2 != 0: order.reverse()
            for freeze: bool in order:
                measuring = false
                driving = false
                frozen = false
                action = kind
                center = initial_center
                center.x = 16.0 if kind == "orbit_boundary" else 8.0
                center.z = 8.0
                _pose(0.0)
                world.shading.invalidate()
                if not await _settle():
                    failures.append("Phase failed to settle: "+kind)
                    await _finish()
                    return
                # Warm renderer at the starting view; motion is measured from its first frame.
                await get_tree().create_timer(0.5).timeout
                frozen = freeze
                if frozen:
                    world.terrain.block_loaded.disconnect(world.shading._invalidate_block)
                    world.terrain.block_unloaded.disconnect(world.shading._invalidate_block)
                phase = "%d_%s_%s" % [round_index+1,kind,"frozen" if freeze else "normal"]
                phase_start = Time.get_ticks_usec()
                interval_phase = ""
                driving = true
                measuring = true
                label.text = "运动卡顿诊断："+phase+"\n请保持窗口前台；临时存档；自动输出 CSV / JSON / Markdown"
                await get_tree().create_timer(sample_seconds).timeout
                measuring = false
                driving = false
                if frozen:
                    world.terrain.block_loaded.connect(world.shading._invalidate_block)
                    world.terrain.block_unloaded.connect(world.shading._invalidate_block)
                var summary: Dictionary = _summarize(phase)
                summaries.append(summary)
                print("MOTION_PHASE ",JSON.stringify(summary))
                if summary.samples == 0 or summary.unfocused > 0:
                    failures.append(phase+": no frames or focus lost; performance result invalid")
                if freeze and (summary.snapshot_count > 0 or summary.publish_count > 0):
                    failures.append(phase+": frozen control unexpectedly updated light field")
    await _finish()

func _summarize(name: String) -> Dictionary:
    var times: Array[float] = []
    var sum: float = 0.0
    var slow: int = 0
    var associated: int = 0
    var unfocused: int = 0
    var counts: Dictionary = {"snapshot":0,"publish":0,"weather_map":0}
    var peaks: Dictionary = {"snapshot":0.0,"publish":0.0,"weather_map":0.0}
    for row: Dictionary in rows:
        if row.phase != name: continue
        times.append(row.ms)
        sum += row.ms
        if not row.focused: unfocused += 1
        if row.ms > 16.6667:
            slow += 1
            if row.snapshot > 0.0 or row.publish > 0.0: associated += 1
        for key: String in counts:
            if row[key] > 0.0: counts[key] += 1
            peaks[key] = maxf(peaks[key],row[key])
    times.sort()
    if times.is_empty(): return {"phase":name,"samples":0,"unfocused":0,"snapshot_count":0,"publish_count":0}
    var n: int = times.size()
    var tail_n: int = maxi(1,ceili(n*0.01))
    var tail: float = 0.0
    for i: int in range(n-tail_n,n): tail += times[i]
    return {"phase":name,"samples":n,"fps":n*1000.0/sum,"low":tail_n*1000.0/tail,
        "p99":times[ceili(n*0.99)-1],"max":times[-1],"slow":slow,"associated":associated,
        "snapshot_count":counts.snapshot,"publish_count":counts.publish,
        "snapshot_max":peaks.snapshot,"publish_max":peaks.publish,"weather_max":peaks.weather_map,
        "unfocused":unfocused}

func _finish() -> void:
    measuring = false
    driving = false
    var csv: FileAccess = FileAccess.open(output+"/frames.csv",FileAccess.WRITE)
    csv.store_csv_line(PackedStringArray(["phase","end_usec","frame_ms","snapshot_ms","publish_ms","weather_map_ms","loaded_blocks","unloaded_blocks","focused","camera_x","camera_y","camera_z"]))
    for row: Dictionary in rows:
        csv.store_csv_line(PackedStringArray([row.phase,str(row.end_usec),str(row.ms),str(row.snapshot),str(row.publish),str(row.weather_map),str(row.loaded),str(row.unloaded),str(row.focused),str(row.camera.x),str(row.camera.y),str(row.camera.z)]))
    csv.close()
    var settings: Dictionary = {}
    for property: Dictionary in world.shading._settings.get_property_list():
        if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
            settings[property.name] = world.shading._settings.get(property.name)
    var metadata: Dictionary = {"settings":settings,"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"resolution":get_viewport().get_visible_rect().size,"view_distance":view_distance,"seconds":sample_seconds,"rounds":rounds,"failures":failures,"summaries":summaries,"events":events}
    var json: FileAccess = FileAccess.open(output+"/results.json",FileAccess.WRITE)
    json.store_string(JSON.stringify(metadata,"  "))
    json.close()
    var report: String = "# 移动与转向卡顿诊断\n\n状态："+("完成" if failures.is_empty() else str(failures))+"\n\n"
    report += "视距 %d；每档 %.1f 秒；%d 轮；输出 %s。\n\n" % [view_distance,sample_seconds,rounds,output]
    report += "| 场景 | FPS | 1% Low | P99 ms | 最长 ms | >16.7ms帧 | 同帧光照事件 | 快照次数/峰值ms | 发布次数/峰值ms | 天气图峰值ms |\n|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n"
    for s: Dictionary in summaries:
        if s.samples == 0: continue
        report += "| %s | %.1f | %.1f | %.2f | %.2f | %d | %d | %d / %.2f | %d / %.2f | %.2f |\n" % [s.phase,s.fps,s.low,s.p99,s.max,s.slow,s.associated,s.snapshot_count,s.snapshot_max,s.publish_count,s.publish_max,s.weather_max]
    report += "\n1% Low=最慢1%帧的平均耗时取倒数。同帧事件是相关性，不是GPU阻塞归因。publish 包含 weather_map，不可相加；GPU上传计时只包括CPU调用，不代表GPU执行时间。冻结档保持旧光照，画面可能过时，仅用于诊断。首轮包含首次运动的加载；可用 rounds=2 反转对照顺序复测。\n"
    var md: FileAccess = FileAccess.open(output+"/report.md",FileAccess.WRITE)
    md.store_string(report)
    md.close()
    print("MOTION_STUTTER failures=%d report=%s/report.md" % [failures.size(),output])
    label.text = "测试完成："+output+"/report.md"
    if is_instance_valid(world):
        world.queue_free()
        await get_tree().process_frame
        await get_tree().process_frame
    if quit_when_finished: get_tree().quit(0 if failures.is_empty() else 1)
