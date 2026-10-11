extends SceneTree
## Runtime contract checks against the actual C++ extension, without launching an editor.
var failures: Array[String] = []
var checks: int = 0

func expect(condition: bool, message: String) -> void:
    checks += 1
    if not condition:
        failures.append(message)

func buffer() -> VoxelBuffer:
    var result: VoxelBuffer = VoxelBuffer.new()
    result.create(16, 16, 16)
    return result

func _initialize() -> void:
    var generator: AstraeonNativeGenerator = AstraeonNativeGenerator.new()
    var content: AstraeonWorldContent = AstraeonWorldContent.new()
    expect(content.build(PackedStringArray(["res://game/data/content/packages/astraeon.aebpack"])), "Build actual content")
    expect(generator.configure_content(content.state_keys), "Configure generator IDs")
    generator.biome_layout = 1
    var a: VoxelBuffer = buffer()
    var b: VoxelBuffer = buffer()
    generator.generate_block(a, Vector3(-16, 32, -16), 0)
    generator.generate_block(b, Vector3(-16, 32, -16), 0)
    var identical: bool = true
    for z: int in range(16):
        for x: int in range(16):
            for y: int in range(16):
                identical = identical and a.get_voxel(x, y, z) == b.get_voxel(x, y, z)
    expect(identical, "Deterministic negative-coordinate generation")
    for pair: Vector2i in [Vector2i(0, content.grass_id), Vector2i(640, content.water_id), Vector2i(850, content.water_id)]:
        var column: VoxelBuffer = VoxelBuffer.new()
        column.create(1, 256, 1)
        generator.generate_block(column, Vector3(pair.x, -64, 0), 0)
        var top: int = 0
        for y: int in range(255, -1, -1):
            if column.get_voxel(0, y, 0) != 0:
                top = column.get_voxel(0, y, 0)
                break
        expect(top == pair.y, "Biome top at x=" + str(pair.x))
    var directory: String = "res://tmp/native-tests/" + str(Time.get_ticks_usec())
    var registry: RefCounted = ClassDB.instantiate("AstraeonContentRegistry")
    var registered: Dictionary = registry.call("resolve", directory, content.bundle.contracts, PackedStringArray(["astraeon"]))
    var stream: AstraeonNativeStream = AstraeonNativeStream.new()
    expect(stream.open_world(directory, 42, 0, content.state_keys, String(registered.world_id)), "Open current world")
    expect(stream.load_voxel_block(b, Vector3i(-1, -1, -1), 0) == VoxelStream.RESULT_BLOCK_NOT_FOUND, "Missing section")
    a.fill(1, 0)
    a.set_voxel(4, 15, 0, 15)
    stream.save_voxel_block(a, Vector3i(-1, -1, -1), 0)
    expect(stream.get_last_error().is_empty(), "First durable write")
    a.set_voxel(3, 15, 0, 15)
    stream.save_voxel_block(a, Vector3i(-1, -1, -1), 0)
    var reader: AstraeonNativeStream = AstraeonNativeStream.new()
    expect(reader.open_world(directory, 42, 0, content.state_keys, String(registered.world_id)), "Reopen world")
    expect(reader.load_voxel_block(b, Vector3i(-1, -1, -1), 0) == VoxelStream.RESULT_BLOCK_FOUND, "Reload section")
    expect(b.get_voxel(15, 0, 15) == 3, "Latest edit survives reload")
    var path: String = directory + "/-1_-1_-1.avr"
    var file: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE)
    file.seek(128 + 63 * 8208 * 2 + 8208 + 100)
    file.store_8(255)
    file.flush()
    file.close()
    expect(reader.load_voxel_block(b, Vector3i(-1, -1, -1), 0) == VoxelStream.RESULT_BLOCK_FOUND, "Recover older record after checksum failure")
    expect(b.get_voxel(15, 0, 15) == 4, "Recovered exact previous edit")
    var wrong_seed: AstraeonNativeStream = AstraeonNativeStream.new()
    expect(wrong_seed.open_world(directory, 43, 0, content.state_keys, String(registered.world_id)), "Open for metadata rejection check")
    expect(wrong_seed.load_voxel_block(b, Vector3i(-1, -1, -1), 0) == VoxelStream.RESULT_ERROR, "Reject mismatching seed")
    expect(not wrong_seed.get_last_error().is_empty(), "Surface metadata error")
    file = FileAccess.open(path, FileAccess.READ_WRITE)
    file.seek(128 + 63 * 8208 * 2 + 100)
    file.store_8(255)
    file.close()
    expect(reader.load_voxel_block(b, Vector3i(-1, -1, -1), 0) == VoxelStream.RESULT_ERROR, "Reject both corrupt records")
    print(JSON.stringify({"checks": checks, "failures": failures, "directory": directory}))
    quit(0 if failures.is_empty() else 1)
