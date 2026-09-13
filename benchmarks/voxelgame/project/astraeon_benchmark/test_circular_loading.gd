extends SceneTree
## Runtime contract checks: real native resident data, independent expected disk plus neighbor halo.
const Generator: Script = preload("res://astraeon_benchmark/benchmark_generator.gd")
var _terrain: VoxelTerrain
var _viewer: VoxelViewer
var _resident: Dictionary[Vector3i, bool] = {}
var _failed: bool = false

func _initialize() -> void:
    _run.call_deferred()

func _run() -> void:
    _terrain = VoxelTerrain.new()
    if not _terrain.has_method("set_horizontal_circular_loading"):
        push_error("Circular native patch missing")
        quit(1)
        return
    _terrain.bounds = AABB(Vector3(-1048576, -128, -1048576), Vector3(2097152, 512, 2097152))
    _terrain.max_view_distance = 512
    _terrain.mesh_block_size = 16
    _terrain.set("horizontal_circular_loading", true)
    var generator: VoxelGeneratorScript = Generator.new() as VoxelGeneratorScript
    generator.call("configure", "plain", 20260913)
    _terrain.generator = generator
    _terrain.mesher = load("res://blocky_game/blocks/mesher.tres") as VoxelMesherBlocky
    _terrain.block_loaded.connect(func(p: Vector3i) -> void: _resident[p] = true)
    _terrain.block_unloaded.connect(func(p: Vector3i) -> void: _resident.erase(p))
    root.add_child(_terrain)
    _viewer = VoxelViewer.new()
    _viewer.view_distance = 64
    _viewer.view_distance_vertical_ratio = 0.5
    _viewer.position = Vector3(0, 64, 0)
    root.add_child(_viewer)
    if not await _settle(): return
    _verify("initial", 4, 2)
    _viewer.position = Vector3(-17, 80, -33)
    if not await _settle(): return
    _verify("negative coordinates and vertical shift", 4, 2)
    _viewer.requires_collisions = false
    if not await _settle(): return
    _verify("collision flag disabled", 4, 2)
    _viewer.requires_collisions = true
    _viewer.position = Vector3(100000, 380, -100000)
    if not await _settle(): return
    _verify("teleport and upper world bound", 4, 2)
    _viewer.position = Vector3(-1, -120, -1)
    _viewer.view_distance = 256
    _viewer.view_distance_vertical_ratio = 1.0
    if not await _settle(): return
    _verify("16 chunk radius and lower world bound", 16, 16)
    _viewer.view_distance_vertical_ratio = 0.25
    if not await _settle(): return
    _verify("independent vertical shrink", 16, 4)
    _viewer.queue_free()
    if not await _settle(): return
    _check(_resident.is_empty(), "Viewer removal must unload all resident data")
    _terrain.queue_free()
    await process_frame
    print("CIRCULAR_LOADING_CONTRACT ", "FAIL" if _failed else "PASS")
    quit(1 if _failed else 0)

func _settle() -> bool:
    var deadline: int = Time.get_ticks_msec() + 20000
    var stable: int = 0
    while Time.get_ticks_msec() < deadline:
        await create_timer(0.05).timeout
        var stats: Dictionary = VoxelEngine.get_stats()
        var idle: bool = true
        for value: int in stats["tasks"].values():
            if value > 0: idle = false
        var pool: Dictionary = stats["thread_pools"]["general"]
        if int(pool["tasks"]) > 0 or int(pool["active_threads"]) > 0: idle = false
        stable = stable + 1 if idle else 0
        if stable >= 5: return true
    push_error("Circular contract test timed out")
    quit(1)
    return false

func _verify(label: String, radius: int, vertical: int) -> void:
    var anchor: Vector3i = Vector3i(floori(_viewer.position.x / 16.0), floori(_viewer.position.y / 16.0), floori(_viewer.position.z / 16.0))
    var expected: Dictionary[Vector3i, bool] = {}
    var columns: int = 0
    # Independent geometric oracle followed by explicit neighbor union (not native row spans).
    for x: int in range(-radius, radius):
        for z: int in range(-radius, radius):
            if Vector2(x + 0.5, z + 0.5).length() > float(radius): continue
            columns += 1
            for dx: int in range(-1, 2):
                for dz: int in range(-1, 2):
                    for y: int in range(maxi(-8, anchor.y - vertical - 1), mini(24, anchor.y + vertical + 1)):
                        expected[Vector3i(anchor.x + x + dx, y, anchor.z + z + dz)] = true
    _check(_resident.size() == expected.size(), "%s resident=%d expected=%d" % [label, _resident.size(), expected.size()])
    for pos: Vector3i in expected:
        if not _resident.has(pos) or not _terrain.has_data_block(pos):
            _check(false, label + " missing " + str(pos))
            break
    for pos: Vector3i in _resident:
        if not expected.has(pos):
            _check(false, label + " extraneous " + str(pos))
            break
    if radius == 16: _check(columns == 812, "256-voxel radius must select 812 horizontal columns")
    print("CIRCULAR_CASE ", label, " columns=", columns, " data_sections=", _resident.size())

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failed = true
        push_error(message)
