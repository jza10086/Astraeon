extends SceneTree
## GPU readback latency probe; deliberately excluded from FPS benchmarking.
var world: Node3D
var failures: Array[String] = []
var results: Array[Dictionary] = []
func _initialize() -> void: call_deferred("_run")
func sample(cell: Vector3i) -> Color:
    var material: ShaderMaterial = world.shading.materials[0]
    var origin: Vector3 = material.get_shader_parameter("light_table_origin")
    var size: Vector3 = material.get_shader_parameter("light_table_size")
    var section: Vector3i = Vector3i((Vector3(cell)/16.0).floor())
    var q: Vector3i = section-Vector3i(origin)
    if q.x<0 or q.y<0 or q.z<0 or q.x>=size.x or q.y>=size.y or q.z>=size.z: return Color.TRANSPARENT
    var table: Texture2D = material.get_shader_parameter("light_page_table")
    var encoded: Color = table.get_image().get_pixel(q.x,q.y+int(size.y)*q.z)
    var slot: int = roundi(encoded.r*255.0)+256*roundi(encoded.g*255.0)-1
    if slot<0: return Color.TRANSPARENT
    var layers: int = material.get_shader_parameter("light_page_layers")
    var pages: TextureLayered = material.get_shader_parameter("light_pages_%d" % (slot/layers))
    var local: Vector3i = cell-section*16
    var shift: int = material.get_shader_parameter("light_page_shift")
    return pages.get_layer_data((slot%layers)>>shift).get_pixel(local.x+((slot%layers)&((1<<shift)-1))*16,local.y+16*local.z)

func settle() -> bool:
    var deadline: int = Time.get_ticks_msec()+60000
    var stable: int = 0
    while Time.get_ticks_msec()<deadline:
        if world.shading.is_ready():
            if stable == 0: stable = Time.get_ticks_msec()
            if Time.get_ticks_msec()-stable >= 600: return true
        else: stable = 0
        await process_frame
    return false
func live_light() -> bool:
    for light: OmniLight3D in world.shading._lights:
        if light.light_energy>0.0: return true
    return false
func _run() -> void:
    var folder: String = "res://tmp/cache-edit-latency/"+str(Time.get_ticks_usec())
    DirAccess.make_dir_recursive_absolute(folder)
    for distance: int in [64,256]:
        world = (load("res://game/core/main.tscn") as PackedScene).instantiate()
        world.horizontal_distance = distance
        world.world_directory = folder+"/world-"+str(distance)
        world.shading_settings_path = folder+"/settings-"+str(distance)+".cfg"
        world.biome_layout = 1
        world.get_node("Player/Controller").input_enabled = false
        root.add_child(world)
        if not await settle(): failures.append("Initial load timeout")
        world.controller.set_physics_process(false)
        world.set_process(false)
        world.shading._settings.local_lighting_mode = 2
        var cell: Vector3i = Vector3i(world.player.global_position.floor())+Vector3i(4,3,0)
        var lamp: int = world.content.state_keys.find("astraeon_glowstone/default")
        for enabled: bool in [true,false]:
            var began: int = Time.get_ticks_usec()
            world.set_block(cell,lamp if enabled else 0)
            var gpu_ms: float = -1.0
            var point_ms: float = -1.0
            var last_negative_ms: float = 0.0
            var next_poll: int = began
            while Time.get_ticks_usec()-began<30000000 and (gpu_ms<0.0 or point_ms<0.0):
                if point_ms<0.0 and live_light()==enabled: point_ms=float(Time.get_ticks_usec()-began)/1000.0
                if gpu_ms<0.0 and Time.get_ticks_usec()>=next_poll:
                    var color: Color = sample(cell+Vector3i.RIGHT)
                    var value_matches: bool = color.g>0.7 if enabled else color.g<0.001
                    if value_matches: gpu_ms=float(Time.get_ticks_usec()-began)/1000.0
                    else: last_negative_ms=float(Time.get_ticks_usec()-began)/1000.0
                    next_poll=Time.get_ticks_usec()+50000
                await process_frame
            if gpu_ms<0.0 or point_ms<0.0: failures.append("Visible update timeout at "+str(distance))
            results.append({"distance":distance,"action":"place" if enabled else "remove","gpu_visible_ms":gpu_ms,"last_negative_gpu_ms":last_negative_ms,"point_light_ms":point_ms})
            if not await settle(): failures.append("Post-edit queue timeout")
        world.queue_free()
        for frame: int in range(5): await process_frame
    var file: FileAccess = FileAccess.open(folder+"/results.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"failures":failures,"results":results},"  "))
    file.close()
    print("CACHE_EDIT_LATENCY ",JSON.stringify({"failures":failures,"results":results}))
    quit(0 if failures.is_empty() else 1)
