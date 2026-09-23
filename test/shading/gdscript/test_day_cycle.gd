extends SceneTree
## Fixed-view diagnostic, isolated world/settings. No user save writes.
var world: Node3D
var failures: int = 0
func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        push_error(message)
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    DirAccess.make_dir_recursive_absolute("res://tmp/cycle-probe")
    world = (load("res://game/core/main.tscn") as PackedScene).instantiate()
    world.world_directory = "res://tmp/cycle-probe/world"
    world.shading_settings_path = "res://tmp/cycle-probe/missing.cfg"
    world.horizontal_distance = 48
    world.biome_layout = 1
    world.get_node("Player/Controller").input_enabled = false
    root.add_child(world)
    var deadline: int = Time.get_ticks_msec()+90000
    while not world.shading.is_ready() and Time.get_ticks_msec()<deadline:
        await process_frame
    check(world.shading.is_ready(),"World becomes ready")
    world.controller.set_physics_process(false)
    world.camera.reparent(world)
    world.camera.global_position = Vector3(12,42,16)
    world.camera.look_at(Vector3(0,31,0))
    await create_timer(5.0).timeout
    var p: Resource = world.shading._settings
    p.max_fps = 0
    p.vsync_enabled = false
    p.weather_mode = 0
    p.day_seconds = 1200.0
    p.planar_visible_only = false
    p.planar_update_fps = 0
    for reflection: int in [0,2]:
        for cycle: bool in [false,true,true,false]:
            p.hour = 12.0
            p.cycle_enabled = cycle
            p.water_reflection_mode = reflection
            world.shading._apply_lighting()
            await create_timer(1.0).timeout
            var initial_hour: float = p.hour
            var initial_sun: Basis = world.shading._sun.basis
            var initial_cloud: Resource = world.shading._cloud_profile
            var cloud_rebuilds: int = world.shading.clouds.rebuilds
            var values: Array[float] = []
            var changes: int = 0
            var env: Environment = world.shading.planar.camera.environment
            var last: int = Time.get_ticks_usec()
            var stop: int = last+3000000
            while Time.get_ticks_usec()<stop:
                await process_frame
                var now: int = Time.get_ticks_usec()
                values.append((now-last)/1000.0)
                last = now
                if env != world.shading.planar.camera.environment:
                    changes += 1
                    env = world.shading.planar.camera.environment
            check(changes == 0,"Cycle retains reflection Environment")
            check(world.shading._cloud_profile == initial_cloud,"Cycle retains cloud configuration")
            check(world.shading.clouds.rebuilds == cloud_rebuilds,"Cycle does not rebuild cloud geometry")
            check((p.hour != initial_hour) == cycle,"Hour follows cycle toggle")
            check((world.shading._sun.basis != initial_sun) == cycle,"Sun follows cycle toggle")
            values.sort()
            print("CYCLE_PROBE reflection=%d cycle=%s median_ms=%.3f p95_ms=%.3f env_changes=%d samples=%d" % [reflection,cycle,values[values.size()/2],values[int(values.size()*0.95)],changes,values.size()])
    p.cycle_enabled = false
    var capture_environment: Environment = world.shading.planar.camera.environment
    p.aa_mode = 2
    p.fog_enabled = true
    p.planar_fog = true
    p.planar_ssao = false
    p.water_reflection_mode = 2
    world.shading._apply_lighting()
    check(root.use_taa,"Settings still apply TAA")
    check(world.shading.planar.camera.environment == capture_environment,"Settings retain reflection Environment")
    check(not capture_environment.ssao_enabled,"Capture keeps independent SSAO")
    check(capture_environment.tonemap_mode == Environment.TONE_MAPPER_LINEAR,"Capture remains linear HDR")
    check(capture_environment.sky == world.shading._environment.sky,"Reflection shares animated sky")
    world.camera.global_position = world.player.global_position+Vector3(18,14,18)
    world.camera.look_at(world.player.global_position)
    await create_timer(3.0).timeout
    for hour: float in [12.0,18.0,22.0]:
        p.hour = hour
        world.shading._update_daylight()
        await create_timer(0.3).timeout
        check(capture_environment.fog_light_color == world.shading._environment.fog_light_color,"Reflection fog follows daylight")
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png("res://tmp/cycle-probe/hour-%d.png" % int(hour))
    p.weather_mode = 2
    p.weather_transition = 0.1
    p.weather_weight = 1.0
    world.shading._apply_lighting()
    await create_timer(0.5).timeout
    check(world.shading.weather.cloud_weight > 0.9,"Weather continues with clock paused")
    check(is_equal_approx(world.shading._cloud_profile.cloud_coverage,p.weather_cloud),"Weather updates cloud coverage")
    p.water_reflection_mode = 0
    world.shading._apply_lighting()
    check(not world.shading.planar.active,"Reflection disables")
    p.water_reflection_mode = 2
    world.shading._apply_lighting()
    check(world.shading.planar.camera.environment == capture_environment,"Reflection re-enable reuses Environment")
    print("CYCLE_REGRESSION failures=%d" % failures)
    world.queue_free()
    await process_frame
    await process_frame
    quit(0 if failures == 0 else 1)
