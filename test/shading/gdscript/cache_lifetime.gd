extends SceneTree
## Check native ownership and GPU texture accounting after complete world destruction.
var failures: Array[String] = []
var samples: Array[Dictionary] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
    var output: String = "res://tmp/cache-lifetime/"+str(Time.get_ticks_usec())
    DirAccess.make_dir_recursive_absolute(output)
    for cycle: int in range(3):
        var world: Node3D = (load("res://game/core/main.tscn") as PackedScene).instantiate()
        world.horizontal_distance = 64
        world.world_directory = output+"/world-"+str(cycle)
        world.shading_settings_path = output+"/settings-"+str(cycle)+".cfg"
        world.biome_layout = 1
        world.get_node("Player/Controller").input_enabled = false
        root.add_child(world)
        var deadline: int = Time.get_ticks_msec()+30000
        while not world.shading.is_ready() and Time.get_ticks_msec()<deadline: await process_frame
        if not world.shading.is_ready(): failures.append("World did not settle: "+str(cycle))
        world.controller.set_physics_process(false)
        var cache: WeakRef = weakref(world.cache_coordinator.native)
        var metrics: Dictionary = world.cache_coordinator.native.call("get_cache_metrics")
        var active_gpu: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
        world.queue_free()
        world = null
        deadline = Time.get_ticks_msec()+15000
        var idle: int = 0
        while idle<10 and Time.get_ticks_msec()<deadline:
            await process_frame
            var tasks: Dictionary = VoxelEngine.get_stats()["tasks"]
            var count: int = 0
            for value: Variant in tasks.values():
                if value is int: count += value
            idle = idle+1 if count==0 and cache.get_ref()==null else 0
        if idle<10: failures.append("Native world tasks or ownership did not drain: "+str(cycle))
        await RenderingServer.frame_post_draw
        var released_gpu: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
        var memory: Dictionary = VoxelEngine.get_stats()["memory_pools"]
        samples.append({"cycle":cycle,"active_gpu_texture_bytes":active_gpu,"released_gpu_texture_bytes":released_gpu,"active_cache_metrics":metrics,"native_released":cache.get_ref()==null,"released_memory":memory})
        if active_gpu-released_gpu<60*1048576: failures.append("Expected light texture pool release was not observed: "+str(cycle))
        if cycle>0 and released_gpu>int(samples[0].released_gpu_texture_bytes)+1048576:
            failures.append("GPU texture occupancy grew across world lifetimes: "+str(cycle))
        if cycle>0 and int(memory.voxel_used)>int(samples[0].released_memory.voxel_used):
            failures.append("Native voxel occupancy grew across world lifetimes: "+str(cycle))
    var result: Dictionary = {"failures":failures,"samples":samples}
    var file: FileAccess = FileAccess.open(output+"/results.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(result,"  "))
    file.close()
    print("CACHE_LIFETIME ",JSON.stringify(result))
    quit(0 if failures.is_empty() else 1)
