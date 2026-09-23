extends Node3D
## Scene orchestration only. Voxel data, generation, meshes and persistence live in C++.
@export var player: CharacterMotor
@export var camera: Camera3D
@export var controller: Node
@export var block_catalog: AstraeonBlockCatalog
@export var water_definition: AstraeonFluidDefinition
var content: AstraeonWorldContent
const WATER_SURFACE_HEIGHT: float = 32.0 # Generation v2, half-open water fill.
@export var shading_profile: AstraeonShadingProfile = preload("res://game/shading/resources/default_profile.tres")
@export var shading_settings_path: String = "user://settings.cfg"
@export var seed: int = 20260916
@export var biome_layout: int = 0
@export var world_directory: String = "user://worlds/landscape_v2"
@export var horizontal_distance: int = 64
@export var vertical_distance: int = 32
@export var prediction_enabled: bool = true
var shading: AstraeonWorldShading
var terrain: VoxelTerrain
var stream: AstraeonNativeStream
var generator: AstraeonNativeGenerator
var voxel_tool: VoxelTool
var ready_to_play: bool = false
var saving: bool = false
var _status: Label
var _elapsed: float = 0.0
var _autosave_elapsed: float = 0.0

func _ready() -> void:
    if player == null or camera == null or controller == null or block_catalog == null or water_definition == null:
        push_error("NativeWorld requires player, camera, controller and content definitions.")
        set_process(false)
        return
    controller.set_physics_process(false)
    get_tree().auto_accept_quit = false
    _status = get_node("Overlay/Layout/Content/Subtitle") as Label
    _status.text = "Loading native terrain..."
    content = AstraeonWorldContent.new()
    if not content.build(block_catalog, water_definition):
        _status.text = "Invalid world content definitions"
        return
    generator = AstraeonNativeGenerator.new()
    if not generator.configure_content(content.state_keys):
        _status.text = "Missing required generator content"
        return
    generator.seed = seed
    generator.biome_layout = biome_layout
    stream = AstraeonNativeStream.new()
    if not stream.open_world(world_directory, seed, biome_layout, content.state_keys):
        _status.text = stream.get_last_error()
        return
    stream.save_generator_output = true
    var mesher: VoxelMesherBlocky = VoxelMesherBlocky.new()
    mesher.library = content.library
    terrain = VoxelTerrain.new()
    terrain.name = "Terrain"
    terrain.generator = generator
    terrain.stream = stream
    terrain.mesher = mesher
    terrain.mesh_block_size = 16
    terrain.max_view_distance = maxi(horizontal_distance + 32, 144) # Data-only shading viewer needs the full height.
    terrain.horizontal_circular_loading = true
    terrain.bounds = AABB(Vector3(-1048576, -64, -1048576), Vector3(2097152, 256, 2097152))
    terrain.generate_collisions = true
    add_child(terrain)
    voxel_tool = terrain.get_voxel_tool()
    voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE
    voxel_tool.mode = VoxelTool.MODE_SET
    var column: VoxelBuffer = VoxelBuffer.new()
    column.create(1, 256, 1)
    generator.generate_block(column, Vector3(0, -64, 3), 0)
    for y: int in range(255, -1, -1):
        var block: int = column.get_voxel(0, y, 0)
        if block == content.grass_id or block == content.dirt_id:
            player.position = Vector3(0.5, y - 64 + 2.0, 3.5)
            break
    controller.set("respawn_position", player.position)
    controller.set("respawn_below", -70.0)
    var visual: VoxelViewer = VoxelViewer.new()
    visual.name = "VisualViewer"
    visual.view_distance = horizontal_distance
    visual.view_distance_vertical_ratio = float(vertical_distance) / horizontal_distance
    visual.requires_collisions = false
    player.add_child(visual)
    var collision: VoxelViewer = VoxelViewer.new()
    collision.name = "CollisionViewer"
    collision.view_distance = mini(horizontal_distance, 32)
    collision.view_distance_vertical_ratio = float(vertical_distance) / collision.view_distance
    collision.requires_visuals = false
    player.add_child(collision)
    if prediction_enabled:
        var prefetch: AstraeonPrefetchViewer = AstraeonPrefetchViewer.new()
        prefetch.name = "PrefetchViewer"
        player.add_child(prefetch)
    shading = AstraeonWorldShading.new()
    shading.name = "Shading"
    shading.settings_path = shading_settings_path
    shading.profile = shading_profile
    add_child(shading)
    shading.configure(self)
    _bind_mouse_action("mine_block", MOUSE_BUTTON_LEFT)
    _bind_mouse_action("place_block", MOUSE_BUTTON_RIGHT)

func _bind_mouse_action(action: StringName, button: MouseButton) -> void:
    if InputMap.has_action(action):
        return
    InputMap.add_action(action)
    var event: InputEventMouseButton = InputEventMouseButton.new()
    event.button_index = button
    InputMap.action_add_event(action, event)

func _physics_process(_delta: float) -> void:
    if ready_to_play or terrain == null or saving:
        return
    if shading == null or not shading.is_ready():
        return
    # A real physics hit is required; a mesh-loaded notification alone is insufficient.
    var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(player.position + Vector3.UP, player.position - Vector3.UP * 4.0, 1)
    if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
        ready_to_play = true
        controller.set_physics_process(true)
        _status.text = "WASD Move | Shift Sprint | Space Jump | Left Mine | Right Place | Esc Release"

func _process(delta: float) -> void:
    if stream == null:
        return
    _elapsed += delta
    _autosave_elapsed += delta
    if not stream.get_last_error().is_empty():
        _status.text = "World I/O error: " + stream.get_last_error()
        controller.set_physics_process(false)
        ready_to_play = false
        set_physics_process(false)
    if _autosave_elapsed >= 30.0 and not saving:
        _autosave_elapsed = 0.0
        save_world(false)

func _unhandled_input(event: InputEvent) -> void:
    if not ready_to_play or saving or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
        return
    if not event.is_action_pressed("mine_block") and not event.is_action_pressed("place_block"):
        return
    var hit: VoxelRaycastResult = voxel_tool.raycast(camera.global_position, -camera.global_basis.z, 8.0)
    if hit == null:
        return
    var position_in_voxels: Vector3i = hit.position if event.is_action_pressed("mine_block") else hit.previous_position
    if event.is_action_pressed("place_block"):
        var block_box: AABB = AABB(Vector3(position_in_voxels), Vector3.ONE)
        var player_box: AABB = AABB(player.position - Vector3(0.35, 0.0, 0.35), Vector3(0.7, 1.8, 0.7))
        if block_box.intersects(player_box):
            return
    set_block(position_in_voxels, 0 if event.is_action_pressed("mine_block") else content.dirt_id)
    get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        save_world(true)

## Completion requires the worker tracker AND the stream's durable-write status.
func save_world(quit_after: bool) -> void:
    if terrain == null:
        if quit_after:
            get_tree().quit()
        return
    if saving:
        if quit_after:
            while saving:
                await get_tree().process_frame
            save_world(true)
        return
    saving = true
    if quit_after:
        controller.set_physics_process(false)
        _status.text = "Saving world..."
    var deadline: int = Time.get_ticks_msec() + 60000
    if quit_after:
        # Also drain saves from unloaded sections and generated terrain, which are not
        # necessarily included in the explicit modified-section tracker.
        var idle_frames: int = 0
        while idle_frames < 3 and Time.get_ticks_msec() < deadline:
            var tasks: Dictionary = VoxelEngine.get_stats()["tasks"]
            idle_frames = idle_frames + 1 if int(tasks["streaming"]) == 0 and int(tasks["generation"]) == 0 else 0
            await get_tree().process_frame
    var tracker: VoxelSaveCompletionTracker = terrain.save_modified_blocks()
    while not tracker.is_complete() and not tracker.is_aborted() and Time.get_ticks_msec() < deadline:
        await get_tree().process_frame
    var success: bool = Time.get_ticks_msec() < deadline and tracker.is_complete() and not tracker.is_aborted() and stream.get_last_error().is_empty()
    saving = false
    if not success:
        _status.text = "Save failed or timed out: " + stream.get_last_error()
        return
    if quit_after:
        get_tree().quit()

## Bulk read-only capture for derived rendering. Unknown sections remain explicitly unknown.
func capture_shading_snapshot(origin: Vector3i, size: Vector3i) -> Dictionary:
    var buffer: VoxelBuffer = VoxelBuffer.new()
    buffer.create(size.x,size.y,size.z)
    buffer.set_channel_depth(VoxelBuffer.CHANNEL_TYPE,VoxelBuffer.DEPTH_16_BIT)
    voxel_tool.copy(origin,buffer,1 << VoxelBuffer.CHANNEL_TYPE,false)
    var known: PackedByteArray = PackedByteArray()
    for z: int in range(0,size.z,16):
        for y: int in range(0,size.y,16):
            for x: int in range(0,size.x,16):
                known.append(1 if voxel_tool.is_area_editable(AABB(Vector3(origin+Vector3i(x,y,z)),Vector3(16,16,16))) else 0)
    return {"buffer":buffer,"known":known,"origin":origin,"opacity":content.opacity,"emission":content.emission,"sources":content.sources}

## Gameplay edit boundary: commit authoritative voxel first, then invalidate derived lighting.
func set_block(position_in_voxels: Vector3i, state_id: int) -> void:
    if state_id < 0 or state_id >= content.state_keys.size():
        push_error("Invalid block state")
        return
    voxel_tool.set_voxel(position_in_voxels,state_id)
    shading.invalidate()
