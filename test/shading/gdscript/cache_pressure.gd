extends SceneTree
## Deliberately undersized cache: correctness/queue bounds, not a performance benchmark.
const Policy: Script = preload("res://game/core/gdscript/cache_policy.gd")
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
    var large: bool = OS.get_cmdline_user_args().has("--large")
    var output: String = "res://tmp/cache-pressure/"+str(Time.get_ticks_usec())
    DirAccess.make_dir_recursive_absolute(output)
    var policy: Policy = Policy.new()
    policy.select_preset(2 if large else 0)
    if not large: policy.values.cpu_mib = 64
    policy.save_settings(output+"/settings.cfg")
    var world: Node3D = (load("res://game/core/main.tscn") as PackedScene).instantiate()
    world.world_directory = output+"/world"
    world.shading_settings_path = output+"/settings.cfg"
    world.horizontal_distance = 960 if large else 480
    world.biome_layout = 1
    world.get_node("Player/Controller").input_enabled = false
    root.add_child(world)
    world.set_process(false)
    var deadline: int = Time.get_ticks_msec()+(180000 if large else 60000)
    var observed: bool = false
    var metrics: Dictionary = {}
    while Time.get_ticks_msec()<deadline:
        metrics = world.cache_coordinator.native.call("get_cache_metrics")
        if bool(metrics.get("unreclaimable_over_budget",false)) or int(metrics.capacity_pressure)>0:
            observed = true
            break
        await process_frame
    if not observed: failures.append("No actual pressure observed; this run cannot validate pressure handling")
    var cell: Vector3i = Vector3i(world.player.position.floor())+Vector3i(1,2,0)
    world.set_block(cell,world.content.dirt_id)
    await world.save_world(false)
    var section: Vector3i = Vector3i((Vector3(cell)/16.0).floor())
    var local: Vector3i = cell-section*16
    var buffer: VoxelBuffer = VoxelBuffer.new()
    buffer.create(16,16,16)
    if world.stream.load_voxel_block(buffer,section,0)!=VoxelStream.RESULT_BLOCK_FOUND or buffer.get_voxel(local.x,local.y,local.z)!=world.content.dirt_id:
        failures.append("Pressure lost a saved edit")
    if not world.stream.get_last_error().is_empty(): failures.append(world.stream.get_last_error())
    var pressure_snapshot: Dictionary = metrics.duplicate()
    # Retire the large demand and verify pending work drains instead of growing forever.
    world.horizontal_distance = 64
    world.player.get_node("VisualViewer").view_distance = 64
    world.player.get_node("VisualViewer").view_distance_vertical_ratio = float(world.vertical_distance)/64.0
    world.cache_coordinator._viewer.view_distance = 80
    world.cache_coordinator._viewer.view_distance_vertical_ratio = 144.0/80.0
    for i: int in range(5): await process_frame
    deadline = Time.get_ticks_msec()+(120000 if large else 60000)
    var stable_since: int = 0
    while Time.get_ticks_msec()<deadline:
        if world.shading.is_ready():
            if stable_since == 0: stable_since = Time.get_ticks_msec()
            if Time.get_ticks_msec()-stable_since >= 1500: break
        else: stable_since = 0
        await process_frame
    if not world.shading.is_ready(): failures.append("Queue did not recover after demand shrank")
    var result: Dictionary = {"large":large,"failures":failures,"pressure":pressure_snapshot,"recovered":world.cache_coordinator.native.call("get_cache_metrics")}
    var file: FileAccess = FileAccess.open(output+"/results.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(result,"  "))
    file.close()
    print("CACHE_PRESSURE ",JSON.stringify(result))
    world.queue_free()
    for i: int in range(5): await process_frame
    quit(0 if failures.is_empty() else 1)
