extends SceneTree
## Real streaming/edit/save/cache contracts; generated worlds remain under tmp.
const Policy: Script = preload("res://game/core/gdscript/cache_policy.gd")
var world: Node3D
var output: String = ""
var checks: int = 0
var failures: Array[String] = []
var last_changes: Array = []
func collect_changes(changes: Array) -> void:
    last_changes = changes
func _initialize() -> void: call_deferred("_run")
func check(value: bool, message: String) -> void:
    checks += 1
    if not value: failures.append(message)
func settle() -> bool:
    var deadline: int = Time.get_ticks_msec()+60000
    var stable: int = 0
    while Time.get_ticks_msec()<deadline:
        if world.shading.is_ready():
            if stable == 0: stable = Time.get_ticks_msec()
            if Time.get_ticks_msec()-stable > 600: return true
        else: stable = 0
        await process_frame
    return false
func metrics() -> Dictionary: return world.cache_coordinator.native.call("get_cache_metrics")
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
func sample_weather(cell: Vector2i) -> Color:
    var material: ShaderMaterial = world.shading.materials[0]
    var origin: Vector2 = material.get_shader_parameter("weather_table_origin")
    var table: Texture2D = material.get_shader_parameter("weather_page_table")
    var section: Vector2i = Vector2i(floori(float(cell.x)/16.0),floori(float(cell.y)/16.0))
    var q: Vector2i = section-Vector2i(origin)
    var encoded: Color = table.get_image().get_pixelv(q)
    var slot: int = roundi(encoded.r*255.0)+256*roundi(encoded.g*255.0)-1
    if slot<0: return Color.TRANSPARENT
    var pages: TextureLayered = material.get_shader_parameter("weather_pages")
    var local: Vector2i = cell-section*16
    return pages.get_layer_data(slot/16).get_pixel(local.x+(slot%16)*16,local.y)
func _run() -> void:
    output = "res://tmp/cache-contracts/"+str(Time.get_ticks_usec())
    DirAccess.make_dir_recursive_absolute(output)
    var policy: Policy = Policy.new()
    check(policy.preset_index()==1,"Balanced defaults")
    policy.values.commit_usec = 2100
    check(policy.preset_index()==3,"Any changed numeric option is custom")
    check(policy.save_settings(output+"/settings.cfg")==OK,"Save cache section")
    var restored: Policy = Policy.new()
    check(restored.load_settings(output+"/settings.cfg")==OK and restored.values.commit_usec==2100,"Restore custom policy")
    var config: ConfigFile = ConfigFile.new()
    config.set_value("cache","format",99)
    config.save(output+"/unsupported.cfg")
    check(restored.load_settings(output+"/unsupported.cfg")==ERR_FILE_UNRECOGNIZED,"Reject unsupported cache format")
    config.set_value("cache","format",1.5)
    config.save(output+"/unsupported.cfg")
    check(restored.load_settings(output+"/unsupported.cfg")==ERR_FILE_UNRECOGNIZED,"Do not truncate fractional format identifiers")
    world = (load("res://game/core/main.tscn") as PackedScene).instantiate()
    world.world_directory = output+"/world"
    world.shading_settings_path = output+"/first-run.cfg"
    world.horizontal_distance = 64
    world.biome_layout = 1
    world.get_node("Player/Controller").input_enabled = false
    preload("res://test/survival/gdscript/world_fixture.gd").prepare(world)
    root.add_child(world)
    check(await settle(),"Initial cache converges")
    world.controller.set_physics_process(false)
    world.set_process(false)
    var previous: Dictionary = metrics()
    world.camera.rotation.y += PI
    for i: int in range(60): await process_frame
    check(metrics().section_reads==previous.section_reads and metrics().passes==previous.passes,"Camera yaw does not rebuild lighting")
    var lamp: int = world.content.state_keys.find("astraeon:glowstone/default")
    check(lamp>0,"Authored light block exists")
    var p: Vector3i = Vector3i(-1,64,-1)
    world.terrain.connect("sections_changed",collect_changes)
    world.set_block(p,lamp)
    check(not last_changes.is_empty(),"Native edit emits section change batch")
    if not last_changes.is_empty():
        var event: Dictionary = last_changes[0]
        check(event.world_instance==world.terrain.get_instance_id() and event.section==Vector3i(-1,4,-1) and event.lifecycle>0 and event.data_version>0 and event.reason=="edit","Section event identifies world, lifetime, version, coordinates and reason")
    world.set_block(p+Vector3i(4,0,0),lamp)
    check(await settle(),"Cross-section overlapping sources settle")
    check(sample(p+Vector3i.RIGHT).g>0.7,"Published page contains cross-boundary block light")
    world.set_block(p,0)
    check(await settle(),"First source removal settles")
    check(sample(p+Vector3i.RIGHT).g>0.5,"Remaining source contribution survives removal")
    world.set_block(p+Vector3i(4,0,0),0)
    check(await settle(),"All sources removed")
    check(sample(p+Vector3i.RIGHT).g==0.0,"No stale GPU block light after source removal")
    for i: int in range(128): world.set_block(Vector3i(i%16-8,64,i/16-4),lamp)
    await process_frame
    for i: int in range(128): world.set_block(Vector3i(i%16-8,64,i/16-4),0)
    check(await settle(),"128 edits replaced during queued work converge")
    check(sample(Vector3i(0,65,0)).g==0.0,"Stale results cannot restore deleted light")
    var home: Vector3 = world.player.global_position
    world.player.global_position.x += 16.0
    check(await settle(),"Move into neighboring sections")
    var io: Dictionary = world.stream.get_metrics()
    var gen: Dictionary = world.generator.get_metrics()
    previous = metrics()
    world.player.global_position = home
    check(await settle(),"Warm return settles")
    check(world.stream.get_metrics().load_requests==io.load_requests,"Warm return does not read disk")
    check(world.generator.get_metrics().blocks==gen.blocks,"Warm return does not regenerate")
    check(metrics().section_reads==previous.section_reads,"Warm return does not recopy same-version voxels")
    check(metrics().passes==previous.passes,"Warm return does not re-solve same-version lighting")
    check(metrics().map_hits>previous.map_hits,"Warm map hit counter increases")
    world.set_block(p,lamp)
    world.save_world(false)
    world.set_block(p,world.content.dirt_id)
    while world.saving: await process_frame
    await world.save_world(false)
    var block: VoxelBuffer = VoxelBuffer.new()
    block.create(16,16,16)
    check(world.stream.load_voxel_block(block,Vector3i(-1,4,-1),0)==VoxelStream.RESULT_BLOCK_FOUND,"Read durable edited section")
    check(block.get_voxel(15,0,15)==world.content.dirt_id,"Save completion cannot discard a newer edit")
    for preset: int in [0,2,1]:
        world.cache_coordinator.policy.select_preset(preset)
        check(await world.cache_coordinator.apply_policy()==OK,"Rebuild pool in explicit loading/pause phase")
        check(await settle(),"Reconfigured cache converges")
        check(metrics().gpu_bytes==int(world.cache_coordinator.policy.values.gpu_mib)*1048576,"GPU pool obeys requested capacity")
    world.cache_coordinator.policy.values.gpu_mib = 96
    check(await world.cache_coordinator.apply_policy()==OK and metrics().gpu_bytes==96*1048576,"Custom numeric GPU capacity is independent from presets")
    var before_repack: Color = sample(p+Vector3i.UP)
    world.cache_coordinator.policy.values.gpu_mib = 97
    check(await world.cache_coordinator.apply_policy()==OK and metrics().gpu_bytes==97*1048576,"Odd MiB capacity packs without exceeding the budget")
    check(sample(p+Vector3i.UP).is_equal_approx(before_repack),"Changing physical page packing preserves GPU voxel values")
    world.cache_coordinator.policy.select_preset(1)
    check(await world.cache_coordinator.apply_policy()==OK,"Return custom capacity to balanced default")
    # Wetness belongs to world columns, so moving the page table must retain it.
    world.shading._settings.weather_mode = 2
    world.shading._settings.weather_transition = 0.01
    world.shading._settings.weather_weight = 1.0
    world.shading._settings.wet_enabled = true
    world.shading._settings.wet_accumulation = 1.0
    world.shading._settings.wet_drying = 0.0
    var wet_deadline: int = Time.get_ticks_msec()+1500
    while Time.get_ticks_msec()<wet_deadline: await process_frame
    var wet_before: Color = sample_weather(Vector2i(0,0))
    check(wet_before.g>0.1,"Weather page accumulates rain wetness")
    # Stop deliberate periodic weather work before asserting a continuously idle queue.
    # The cached value must survive independently from the update switch.
    world.shading._settings.wet_enabled = false
    world.player.global_position.x += 16.0
    check(await settle(),"Weather interest shift settles")
    world.player.global_position = home
    check(await settle(),"Weather return settles")
    check(sample_weather(Vector2i(0,0)).g>=wet_before.g,"World-coordinate wetness survives interest shifts")
    world.shading._settings.weather_mode = 0
    world.shading._settings.wet_enabled = false
    # A fresh scene gets independent native ownership while old tasks are draining.
    var old_world: Node3D = world
    world = (load("res://game/core/main.tscn") as PackedScene).instantiate()
    world.world_directory = output+"/second-world"
    world.shading_settings_path = output+"/second-settings.cfg"
    world.horizontal_distance = 64
    world.biome_layout = 1
    world.get_node("Player/Controller").input_enabled = false
    old_world.set_block(Vector3i(0,65,0),lamp)
    old_world.queue_free()
    preload("res://test/survival/gdscript/world_fixture.gd").prepare(world)
    root.add_child(world)
    check(await settle(),"Switching world while old lighting runs converges")
    check(sample(Vector3i(0,65,0)).g==0.0,"Old-world result cannot light the new world")
    check(world.stream.get_last_error().is_empty(),"No persistence errors")
    var result: Dictionary = {"checks":checks,"failures":failures,"metrics":metrics()}
    var file: FileAccess = FileAccess.open(output+"/results.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(result,"  "))
    file.close()
    print("CACHE_CONTRACTS ",JSON.stringify(result))
    world.queue_free()
    for i: int in range(5): await process_frame
    quit(0 if failures.is_empty() else 1)
