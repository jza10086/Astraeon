extends SceneTree
## Short repeatable streaming probe. Runs in a game process, never an editor.
const WORLD: PackedScene = preload("res://game/core/main.tscn")
var world: Node3D
var frames: Array[float] = []
var samples: Array[Dictionary] = []
var failures: Array[String] = []
var options: Dictionary[String, String] = {}
var previous_usec: int = 0

func _initialize() -> void:
    for argument: String in OS.get_cmdline_user_args():
        var pair: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
        if pair.size() == 2:
            options[pair[0]] = pair[1]
    call_deferred("_run")

func _run() -> void:
    world = WORLD.instantiate()
    world.set("world_directory", options.get("world", "res://tmp/native-probe/world"))
    world.set("biome_layout", 1)
    world.set("prediction_enabled", options.get("prediction", "1") == "1")
    preload("res://test/survival/gdscript/world_fixture.gd").prepare(world)
    root.add_child(world)
    var deadline: int = Time.get_ticks_msec() + 30000
    while not bool(world.get("ready_to_play")) and Time.get_ticks_msec() < deadline:
        await process_frame
    if not bool(world.get("ready_to_play")):
        failures.append("Spawn collision timeout")
        _finish()
        return
    var player: CharacterMotor = world.get("player") as CharacterMotor
    var controller: Node = world.get("controller") as Node
    controller.set_physics_process(false)
    controller.set("input_enabled", false)
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    var terrain: VoxelTerrain = world.get("terrain") as VoxelTerrain
    var tool: VoxelTool = world.get("voxel_tool") as VoxelTool
    var anchor: Vector3i = Vector3i(floori(player.position.x), floori(player.position.y) - 2, floori(player.position.z))
    # Queue multiple revisions without waiting between snapshots.
    var tracker: VoxelSaveCompletionTracker
    for revision: int in range(20):
        tool.set_voxel(anchor, 1 + revision % 4)
        tracker = terrain.save_modified_blocks()
    while not tracker.is_complete() and Time.get_ticks_msec() < deadline:
        await process_frame
    var reader: AstraeonNativeStream = AstraeonNativeStream.new()
    reader.open_world(world.get("world_directory"), int(world.get("seed")), 1, (world.get("content") as AstraeonWorldContent).state_keys, world.content.bundle.world_id)
    var stored: VoxelBuffer = VoxelBuffer.new()
    stored.create(16, 16, 16)
    var section: Vector3i = Vector3i(floori(anchor.x / 16.0), floori(anchor.y / 16.0), floori(anchor.z / 16.0))
    var local: Vector3i = anchor - section * 16
    if reader.load_voxel_block(stored, section, 0) != VoxelStream.RESULT_BLOCK_FOUND or stored.get_voxel_v(local) != 4:
        failures.append("Latest queued edit did not survive reload")
    var seconds: float = float(options.get("seconds", "1.5"))
    var start: Vector3 = player.position
    for speed: float in [16.0, 32.0, 64.0]:
        for phase: int in range(4):
            if phase == 3:
                player.position += Vector3(512, 0, 256)
            var elapsed: float = 0.0
            var sample_elapsed: float = 0.0
            var phase_start: Vector3 = player.position
            previous_usec = Time.get_ticks_usec()
            while elapsed < seconds:
                await process_frame
                var now: int = Time.get_ticks_usec()
                var delta: float = minf(float(now - previous_usec) / 1000000.0, 0.2)
                frames.append(float(now - previous_usec) / 1000.0)
                previous_usec = now
                elapsed += delta
                sample_elapsed += delta
                var direction: Vector3 = Vector3.RIGHT if phase == 0 else (Vector3.LEFT if phase == 1 else Vector3.BACK)
                if phase != 3:
                    var target: Vector3 = phase_start + direction * speed * minf(elapsed, seconds)
                    player.position.x = target.x
                    player.position.z = target.z
                if sample_elapsed >= 0.25:
                    sample_elapsed = 0.0
                    _follow_surface(player)
                    var collision_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(player.position + Vector3.UP, player.position - Vector3.UP * 5.0, 1)
                    var collision_present: bool = not world.get_world_3d().direct_space_state.intersect_ray(collision_query).is_empty()
                    samples.append({"speed": speed, "phase": phase, "collision_present": collision_present, "position": [player.position.x, player.position.y, player.position.z],
                        "near_meshed": terrain.is_area_meshed(AABB(player.position - Vector3(2, 3, 2), Vector3(4, 5, 4))),
                        "engine": VoxelEngine.get_stats(), "io": (world.get("stream") as AstraeonNativeStream).call("get_metrics"),
                        "generation": (world.get("generator") as AstraeonNativeGenerator).call("get_metrics")})
    player.position = start
    await create_timer(3.0).timeout
    world.call("save_world", false)
    while bool(world.get("saving")):
        await process_frame
    var stream: AstraeonNativeStream = world.get("stream") as AstraeonNativeStream
    if not stream.get_last_error().is_empty():
        failures.append(stream.get_last_error())
    _finish()

func _follow_surface(player: CharacterMotor) -> void:
    var column: VoxelBuffer = VoxelBuffer.new()
    column.create(1, 256, 1)
    var generator: AstraeonNativeGenerator = world.get("generator") as AstraeonNativeGenerator
    generator.generate_block(column, Vector3(floorf(player.position.x), -64, floorf(player.position.z)), 0)
    for y: int in range(255, -1, -1):
        var block: int = column.get_voxel(0, y, 0)
        if block == (world.get("content") as AstraeonWorldContent).grass_id or block == (world.get("content") as AstraeonWorldContent).dirt_id:
            player.position.y = y - 64 + 2.0
            return

func _finish() -> void:
    frames.sort()
    var report: Dictionary = {"options": options, "failures": failures, "samples": samples,
        "frame_count": frames.size(), "renderer": RenderingServer.get_current_rendering_method()}
    if not frames.is_empty():
        report["frame_p50_ms"] = frames[int(frames.size() * 0.5)]
        report["frame_p95_ms"] = frames[mini(frames.size() - 1, int(frames.size() * 0.95))]
        report["frame_max_ms"] = frames[-1]
        report["frame_p99_ms"] = frames[mini(frames.size() - 1, int(frames.size() * 0.99))]
    var output: String = options.get("output", "res://tmp/native-probe/report.json")
    DirAccess.make_dir_recursive_absolute(output.get_base_dir())
    var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
    file.store_string(JSON.stringify(report, "\t"))
    file.close()
    print("NATIVE_PROBE " + JSON.stringify({"failures": failures, "frames": frames.size(), "report": output}))
    quit(0 if failures.is_empty() else 1)
