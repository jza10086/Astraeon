extends SceneTree
## Real main-world integration plus native propagation invariants; isolated saves/settings.
var failures: int = 0
var checks: int = 0
var world: Node3D
func _initialize() -> void:
    call_deferred("_run")
func check(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures += 1
        push_error(message)
func _native_checks() -> void:
    var buffer: VoxelBuffer = VoxelBuffer.new()
    buffer.create(16,16,16)
    buffer.set_channel_depth(VoxelBuffer.CHANNEL_TYPE,VoxelBuffer.DEPTH_16_BIT)
    for z: int in range(4,12):
        for y: int in range(4,12):
            for x: int in range(4,12):
                if x in [4,11] or y in [4,11] or z in [4,11]: buffer.set_voxel(1,x,y,z)
    buffer.set_voxel(2,7,5,7)
    var solver: AstraeonLightReference = AstraeonLightReference.new()
    var result: Dictionary = solver.solve(buffer,PackedByteArray([0,15,15]),PackedByteArray([0,0,15]),PackedByteArray([0,0,1]),PackedByteArray([1]),16,Vector3i(-16,-16,-16))
    check(result.images[7].get_pixel(7,7).r == 0.0,"Sealed room blocks sky")
    check(result.images[7].get_pixel(7,7).g > 0.0,"Enclosed source propagates")
    check(result.images[0].get_pixel(0,0).r == 1.0,"Open columns get sky")
    check(result.emitters[0].position == Vector3i(-9,-11,-9),"Negative world coordinates")
    var independent: Dictionary = solver.solve(buffer,PackedByteArray([0,15,15]),PackedByteArray([0,0,0]),PackedByteArray([0,0,1]),PackedByteArray([1]),16,Vector3i.ZERO)
    check(independent.emitters.size() == 1 and independent.images[7].get_pixel(7,7).g == 0.0,"Point requests independent of voxel emission")
    buffer.set_voxel(0,7,5,7)
    result = solver.solve(buffer,PackedByteArray([0,15,15]),PackedByteArray([0,0,15]),PackedByteArray([0,0,1]),PackedByteArray([1]),16,Vector3i.ZERO)
    check(result.images[7].get_pixel(7,7).g == 0.0,"Deleted light fully removed")
    result = solver.solve(buffer,PackedByteArray([0,15,15]),PackedByteArray([0,0,15]),PackedByteArray([0,0,1]),PackedByteArray([0]),16,Vector3i.ZERO)
    check(result.images[0].get_pixel(0,0).r == 0.0,"Unknown data does not emit sky")
func frames(count: int) -> void:
    for i: int in range(count): await process_frame
func capture(name: String) -> void:
    await frames(16)
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://tmp/world-shading/"+name+".png")
func wait_field(previous: int) -> void:
    var deadline: int = Time.get_ticks_msec()+60000
    while world.shading.field_publications <= previous and Time.get_ticks_msec()<deadline:
        await process_frame
    while not world.shading.is_ready() and Time.get_ticks_msec()<deadline:
        await process_frame
    check(world.shading.field_publications>previous and world.shading.is_ready(),"World field publication")
func _run() -> void:
    _native_checks()
    DirAccess.make_dir_recursive_absolute("res://tmp/world-shading")
    world = (load("res://game/core/main.tscn") as PackedScene).instantiate()
    world.world_directory = "res://tmp/world-shading/world"
    world.shading_settings_path = "res://tmp/world-shading/settings.cfg"
    world.horizontal_distance = 48
    world.biome_layout = 1
    world.get_node("Player/Controller").input_enabled = false
    root.add_child(world)
    await wait_field(0)
    var deadline: int = Time.get_ticks_msec()+60000
    while not world.shading.is_ready() and Time.get_ticks_msec()<deadline:
        await process_frame
    check(world.shading.is_ready(),"Streaming lighting settles")
    world.controller.set_physics_process(false)
    world.camera.reparent(world)
    world.camera.global_position = world.player.global_position+Vector3(18,14,18)
    world.camera.look_at(world.player.global_position)
    await capture("day")
    check(world.content.library.models[world.content.dirt_id].get_material_override(0) is ShaderMaterial,"Native mesher uses shading material")
    check(int(world.cache_coordinator.native.call("get_cache_metrics").pages) > 0,"World light texture published")
    var origin: Vector3i = Vector3i(world.player.position.floor())+Vector3i(2,2,0)
    var previous: int = world.shading.field_publications
    world.set_block(origin,world.content.state_keys.find("astraeon_glowstone/default"))
    await wait_field(previous)
    world.shading._settings.hour = 22.0
    world.shading._settings.moving_mode = 1
    var pane: MeshInstance3D = MeshInstance3D.new()
    var plane: PlaneMesh = PlaneMesh.new()
    plane.size = Vector2(5,5)
    pane.mesh = plane
    var transparent: StandardMaterial3D = StandardMaterial3D.new()
    transparent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    pane.material_override = transparent
    world.add_child(pane)
    pane.global_position = world.player.position+Vector3(0,5,0)
    world.shading.register_transparent_caster(pane)
    world.shading._settings.glass_enabled = true
    world.shading._settings.water_reflection_mode = 1
    world.shading._apply_lighting()
    await capture("night")
    check(world.shading.glass.captures > 0,"Registered scene glass casts colored shadow")
    check(world.shading.moving.light.light_energy>0.0,"Held light receives shared budget")
    previous = world.shading.field_publications
    world.set_block(origin,0)
    await wait_field(previous)
    var water_position: Vector3 = Vector3.ZERO
    for z: int in range(-24,25,8):
        for x: int in range(-24,25,8):
            if world.voxel_tool.get_voxel(Vector3i(x,31,z)) == world.content.water_id:
                water_position = Vector3(x,31,z)
    check(water_position != Vector3.ZERO,"Generated water available")
    world.camera.global_position = water_position+Vector3(4,5,8)
    world.camera.look_at(water_position)
    world.shading._settings.hour = 12.0
    for mode: int in [0,1,2]:
        world.shading._settings.water_reflection_mode = mode
        world.shading._apply_lighting()
        await capture("water-%d" % mode)
        check(world.shading.water_materials[0].shader != null,"Water scheme applies")
    world.camera.global_position = water_position+Vector3(0,0.2,0)
    await frames(4)
    check(world.shading._underwater,"Underwater follows voxel occupancy")
    await capture("underwater")
    world.camera.global_position.y += 6.0
    await frames(4)
    check(not world.shading._underwater,"Leaving water restores atmosphere")
    var before_camera: Dictionary = world.cache_coordinator.native.call("get_cache_metrics")
    world.camera.global_position.x += 32.0
    await frames(60)
    var after_camera: Dictionary = world.cache_coordinator.native.call("get_cache_metrics")
    check(before_camera.section_reads == after_camera.section_reads and before_camera.passes == after_camera.passes,"Camera movement does not move world lighting interest")
    world.shading._settings.hour = 12.0
    world.shading._settings.weather_mode = 2
    world.shading._settings.weather_transition = 0.1
    world.shading._settings.rain_enabled = true
    world.shading._apply_lighting()
    await capture("rain")
    world.shading._menu.show()
    world.shading.panel.sync(world.shading._settings)
    await capture("settings")
    print("WORLD_SHADING checks=%d failures=%d" % [checks,failures])
    await world.save_world(false)
    world.queue_free()
    await frames(3)
    quit(0 if failures == 0 else 1)
