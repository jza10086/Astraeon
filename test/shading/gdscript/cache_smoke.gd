extends SceneTree
var world: Node3D
var started: int
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    world = (load("res://game/core/main.tscn") as PackedScene).instantiate()
    world.world_directory = "res://tmp/cache-smoke/world-" + str(Time.get_ticks_usec())
    world.shading_settings_path = "res://tmp/cache-smoke/no-settings.cfg"
    world.horizontal_distance = 64
    world.biome_layout = 1
    preload("res://test/survival/gdscript/world_fixture.gd").prepare(world)
    root.add_child(world)
    started = Time.get_ticks_msec()
    var last_report: int = 0
    while Time.get_ticks_msec()-started < 90000:
        await process_frame
        if Time.get_ticks_msec()-last_report > 2000:
            last_report = Time.get_ticks_msec()
            if world.cache_coordinator != null: print("CACHE_PROGRESS ",JSON.stringify(world.cache_coordinator.metrics))
        if world.shading != null and world.shading.is_ready(): break
    if world.shading == null or not world.shading.is_ready():
        push_error("Cache failed to settle within 90 seconds")
        quit(1)
        return
    world.controller.set_physics_process(false)
    world.camera.reparent(world)
    world.camera.global_position = world.player.global_position+Vector3(16,15,16)
    world.camera.look_at(world.player.global_position)
    for frame: int in range(60): await process_frame
    await RenderingServer.frame_post_draw
    DirAccess.make_dir_recursive_absolute("res://tmp/cache-smoke")
    root.get_texture().get_image().save_png("res://tmp/cache-smoke/first.png")
    print("CACHE_SMOKE PASS ",JSON.stringify(world.cache_coordinator.native.call("get_cache_metrics")))
    world.queue_free()
    for frame: int in range(3): await process_frame
    quit()
