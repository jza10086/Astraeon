extends Node3D
const Paths: Script = preload("res://game/core/gdscript/project_paths.gd")
## Scene orchestration only. Voxel data, generation, meshes and persistence live in C++.
@export var player: CharacterMotor
@export var camera: Camera3D
@export var controller: Node
@export var content_packages: PackedStringArray = ["res://game/data/content/packages/astraeon.aebpack"]
var water_definition: AstraeonFluidDefinition
var item_catalog: AstraeonItemCatalog
@export var inventory_definition: AstraeonInventoryDefinition = preload("res://game/data/inventory/resources/player_inventory.tres")
var player_state: AstraeonPlayerState
var inventory: AstraeonInventoryState
var inventory_store: AstraeonInventoryStore
var inventory_hud: AstraeonInventoryHUD
var dropped_items: Node3D
var failed: bool = false
var mining: RefCounted
var block_target: RefCounted
var inventory_interaction: AstraeonInventoryInteraction
var content: AstraeonWorldContent
const WATER_SURFACE_HEIGHT: float = 32.0 # Generation v2, half-open water fill.
@export var shading_profile: AstraeonShadingProfile = preload("res://game/shading/resources/default_profile.tres")
@export var shading_settings_path: String = Paths.settings_file()
@export var seed: int = 20260916
@export var biome_layout: int = 0
@export var world_directory: String = Paths.worlds_directory().path_join("landscape_current")
@export var horizontal_distance: int = 64
@export var vertical_distance: int = 32
@export var prediction_enabled: bool = true
var cache_coordinator: Node
var shading: AstraeonWorldShading
var terrain: VoxelTerrain
var stream: AstraeonNativeStream
var generator: AstraeonNativeGenerator
var voxel_tool: VoxelTool
var ready_to_play: bool = false
var saving: bool = false
var pause_menu: Control
var _previous_auto_accept_quit: bool = true
var _status: Label
var _configured_content_packages: PackedStringArray
var _elapsed: float = 0.0
var _autosave_elapsed: float = 0.0

func _ready() -> void:
    if player == null or camera == null or controller == null:
        push_error("NativeWorld requires player, camera, controller and content definitions.")
        set_process(false)
        return
    controller.set_physics_process(false)
    _previous_auto_accept_quit = get_tree().auto_accept_quit
    get_tree().auto_accept_quit = false
    var pause_layer: CanvasLayer = CanvasLayer.new()
    pause_layer.name = "PauseLayer"
    pause_layer.layer = 30
    add_child(pause_layer)
    pause_menu = preload("res://game/ui/pause_menu/scenes/pause_menu.tscn").instantiate()
    pause_menu.world = self
    pause_layer.add_child(pause_menu)
    _status = get_node("Overlay/Layout/Content/Subtitle") as Label
    _status.text = "Loading native terrain..."
    if not controller.visual.load_error.is_empty():
        fail_stop(controller.visual.load_error)
        return
    var world_choice: Dictionary = preload("res://game/core/gdscript/world_selection.gd").selected(world_directory, shading_settings_path)
    if world_choice.has("error"):
        _status.text = world_choice.error
        return
    world_directory = world_choice.directory
    _configured_content_packages = content_packages.duplicate()
    var parameters: Dictionary = preload("res://game/core/gdscript/world_selection.gd").parameters(world_directory)
    if parameters.has("error"):
        _show_content_error(parameters.error, true)
        return
    seed = int(parameters.get("seed", seed))
    biome_layout = int(parameters.get("biome_layout", biome_layout))
    _configured_content_packages = content_packages.duplicate()
    var selection: Dictionary = preload("res://game/core/gdscript/content_selection.gd").selected(content_packages, shading_settings_path)
    if selection.has("error"):
        _status.text = selection.error
        return
    content_packages = selection.paths
    content = AstraeonWorldContent.new()
    if not content.build(content_packages, world_directory):
        _show_content_error(content.error)
        return
    var content_policy: AstraeonCachePolicy = AstraeonCachePolicy.new()
    var policy_error: Error = content_policy.load_settings(shading_settings_path)
    if policy_error not in [OK, ERR_FILE_NOT_FOUND] or not content.bundle.visuals.call("configure", content_policy.values):
        _status.text = "Invalid content cache settings or pinned visuals exceed capacity"
        return
    var preload_hashes: PackedStringArray = []
    for record: Dictionary in content.bundle.blocks.values():
        if record.load_policy == "preload" and not String(record.visual).is_empty() and not preload_hashes.has(record.visual):
            preload_hashes.append(record.visual)
    content.bundle.visuals.call("request", "preload", preload_hashes)
    var deadline: int = Time.get_ticks_msec() + 30000
    while not content.bundle.visuals.call("is_ready", preload_hashes):
        content.bundle.visuals.call("commit")
        var status: Dictionary = content.bundle.visuals.call("get_metrics")
        if not status.failures.is_empty() or not String(status.pressure).is_empty() or Time.get_ticks_msec() > deadline:
            _status.text = "Content loading failed: " + str(status)
            return
        await get_tree().process_frame
    water_definition = content.water_definition
    item_catalog = content.item_catalog
    generator = AstraeonNativeGenerator.new()
    if not generator.configure_content(content.state_keys):
        _status.text = "Missing required generator content"
        return
    generator.seed = seed
    generator.biome_layout = biome_layout
    stream = AstraeonNativeStream.new()
    if not stream.open_world(world_directory, seed, biome_layout, content.state_keys, content.bundle.world_id):
        _status.text = stream.get_last_error()
        return
    inventory = AstraeonInventoryState.new()
    player_state = inventory.player_state
    player_state.set_mode(int(parameters.initial_mode))
    inventory_store = AstraeonInventoryStore.new()
    if not inventory.configure(item_catalog, inventory_definition):
        _status.text = "Invalid inventory definitions"
        return
    dropped_items = preload("res://game/entities/dropped_items/gdscript/dropped_items.gd").new()
    if not dropped_items.configure(self):
        return
    inventory_store.dropped_items = dropped_items.pool
    var identity: Dictionary = {"generation": 2, "seed": seed, "layout": biome_layout, "world_id": content.bundle.world_id}
    if not inventory_store.open(world_directory, identity, inventory) or not inventory_store.recover(stream, generator, content.state_keys):
        fail_stop(inventory_store.error)
        return
    player_state.can_change = func() -> bool: return ready_to_play and not saving and not failed and not inventory.locked
    controller.player_state = player_state
    player_state.changed.connect(controller.apply_game_mode)
    player_state.changed.connect(_update_control_hint)
    controller.apply_game_mode()
    stream.save_generator_output = true
    var mesher: VoxelMesherBlocky = VoxelMesherBlocky.new()
    mesher.library = content.library
    terrain = VoxelTerrain.new()
    terrain.name = "Terrain"
    terrain.generator = generator
    terrain.stream = stream
    terrain.mesher = mesher
    var state_visuals: PackedStringArray = [""]
    for index: int in range(1, content.state_keys.size()):
        state_visuals.append(content.bundle.blocks[content.bundle.state_records[content.state_keys[index]].block].visual)
    terrain.call("set_content_visual_cache", content.bundle.visuals, state_visuals)
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
    cache_coordinator = preload("res://game/core/gdscript/cache_coordinator.gd").new()
    cache_coordinator.name = "CacheCoordinator"
    add_child(cache_coordinator)
    if not cache_coordinator.configure(self):
        _status.text = "Invalid cache configuration or missing native cache DLL"
        return
    shading = AstraeonWorldShading.new()
    shading.name = "Shading"
    shading.settings_path = shading_settings_path
    shading.profile = shading_profile
    add_child(shading)
    shading.configure(self)
    controller.connect("view_changed", shading.reset_camera_history)
    _bind_mouse_action("mine_block", MOUSE_BUTTON_LEFT)
    _bind_mouse_action("place_block", MOUSE_BUTTON_RIGHT)
    inventory_interaction = AstraeonInventoryInteraction.new()
    inventory_interaction.configure(self, inventory)
    var held_block: Node3D = preload("res://game/entities/player/gdscript/held_block.gd").new()
    held_block.name = "HeldBlock"
    held_block.failed.connect(fail_stop)
    held_block.configure(inventory, content.bundle, controller.visual)
    add_child(held_block)
    mining = preload("res://game/gameplay/interaction/gdscript/mining_progress.gd").new()
    mining.configure(self)
    block_target = preload("res://game/gameplay/interaction/gdscript/block_target.gd").new()
    block_target.configure(self)
    var inventory_layer: CanvasLayer = CanvasLayer.new()
    inventory_layer.name = "InventoryLayer"
    inventory_layer.layer = 20
    add_child(inventory_layer)
    inventory_hud = preload("res://game/ui/inventory/scenes/inventory_hud.tscn").instantiate() as AstraeonInventoryHUD
    inventory_hud.inventory = inventory
    inventory_hud.drop_cursor = dropped_items.drop_cursor
    inventory_hud.can_interact = func() -> bool: return ready_to_play and not saving and (bool(controller.get("input_enabled")) or inventory_hud.opened)
    inventory_hud.open_changed.connect(_inventory_open_changed)
    inventory_layer.add_child(inventory_hud)
    add_child(dropped_items)
    if not InputMap.has_action("drop_item"):
        InputMap.add_action("drop_item")
        var drop_key: InputEventKey = InputEventKey.new()
        drop_key.physical_keycode = KEY_Q
        InputMap.action_add_event("drop_item", drop_key)

func _show_content_error(reason: String, show_choices: bool = false) -> void:
    _status.text = reason
    if not show_choices and not reason.begins_with("Unsupported old prototype world: registry is absent"):
        return
    _status.text = reason
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    var panel: VBoxContainer = preload("res://game/ui/main_menu/gdscript/world_start_error.gd").new()
    panel.name = "WorldStartError"
    get_node("Overlay/Layout/Content").add_child(panel)
    panel.call("build", world_directory)
    panel.connect("create_requested", _create_new_world.bind(panel))
    panel.connect("back_requested", func() -> void: get_tree().call_deferred("change_scene_to_file", "res://game/ui/main_menu/scenes/main_menu.tscn"))

func _create_new_world(panel: VBoxContainer) -> void:
    panel.get("create_button").disabled = true
    var choice: Dictionary = preload("res://game/core/gdscript/world_selection.gd").create_new(world_directory, shading_settings_path, "", seed, biome_layout)
    if choice.has("error"):
        _status.text = choice.error
        panel.get("create_button").disabled = false
        return
    var next_world: Node = load(scene_file_path).instantiate()
    for key: String in ["seed", "biome_layout", "horizontal_distance", "vertical_distance", "prediction_enabled", "shading_profile", "shading_settings_path"]:
        next_world.set(key, get(key))
    next_world.set("content_packages", _configured_content_packages.duplicate())
    next_world.set("world_directory", choice.directory)
    var code: Error = get_tree().change_scene_to_node(next_world)
    if code != OK:
        next_world.free()
        _status.text = "新世界选择已保存，但场景打开失败：" + error_string(code)
        panel.get("create_button").disabled = false

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
        _update_control_hint()

func _process(delta: float) -> void:
    if failed:
        return
    if stream == null:
        return
    if inventory_store != null and not inventory_store.error.is_empty():
        fail_stop(inventory_store.error)
        return
    if cache_coordinator != null:
        var visual_errors: Array = cache_coordinator.metrics.get("visuals", {}).get("failures", [])
        if not visual_errors.is_empty(): _status.text = "Content visual error: " + str(visual_errors)
    if block_target != null:
        block_target.refresh()
    if mining != null:
        mining.tick(delta)
    if failed:
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
    if not ready_to_play or saving or inventory_interaction == null or not bool(controller.get("input_enabled")) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
        return
    if event.is_action_pressed("drop_item") and not event.is_echo():
        dropped_items.drop_selected(event is InputEventKey and event.shift_pressed)
        get_viewport().set_input_as_handled()
        return
    if not event.is_action_pressed("mine_block") and not event.is_action_pressed("place_block"):
        return
    if event.is_action_pressed("mine_block") and not player_state.is_creative():
        mining.begin_hold()
        get_viewport().set_input_as_handled()
        return
    block_target.refresh()
    var hit: VoxelRaycastResult = block_target.hit
    if hit == null:
        return
    var position_in_voxels: Vector3i = hit.position if event.is_action_pressed("mine_block") else hit.previous_position
    var placing: bool = event.is_action_pressed("place_block")
    inventory_interaction.edit(position_in_voxels, placing, hit.previous_position - hit.position)
    if not inventory_interaction.message.is_empty():
        _status.text = inventory_interaction.message
    get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
    if what == NOTIFICATION_PAUSED:
        if mining != null:
            mining.end_hold()
        if block_target != null:
            block_target.clear()
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        save_world(true)

## Completion requires the worker tracker AND the stream's durable-write status.
func save_world(quit_after: bool, drain: bool = false) -> bool:
    if failed:
        return false
    if terrain == null:
        if quit_after:
            get_tree().quit()
        return true
    if saving:
        if quit_after or drain:
            while saving:
                await get_tree().process_frame
            return await save_world(quit_after, drain)
        return false
    var final_save: bool = quit_after or drain
    var previous_terrain_mode: ProcessMode = terrain.process_mode
    var previous_controller_physics: bool = controller.is_physics_processing()
    saving = true
    if inventory != null:
        inventory.locked = true
    if final_save:
        controller.set_physics_process(false)
        terrain.process_mode = Node.PROCESS_MODE_ALWAYS
        _status.text = "Saving world..."
    var deadline: int = Time.get_ticks_msec() + 60000
    if final_save:
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
    # Worker completion can precede main-thread save-result disposal by a frame.
    # Wait for that final drain before retiring the shared player/terrain journal.
    while final_save and tracker.is_complete() and not tracker.is_aborted() and int(VoxelEngine.get_stats()["tasks"]["streaming"]) > 0 and Time.get_ticks_msec() < deadline:
        await get_tree().process_frame
    var success: bool = Time.get_ticks_msec() < deadline and tracker.is_complete() and not tracker.is_aborted() and stream.get_last_error().is_empty()
    if success and inventory_store != null:
        # Only retire the WAL after queued unload writes have drained as well.
        if int(VoxelEngine.get_stats()["tasks"]["streaming"]) == 0:
            success = inventory_store.checkpoint()
        elif final_save:
            success = false
    terrain.process_mode = previous_terrain_mode
    controller.set_physics_process(previous_controller_physics)
    saving = false
    if inventory != null:
        inventory.locked = false
    if not success:
        fail_stop("Save failed or timed out: " + stream.get_last_error() + " " + inventory_store.error)
        return false
    if quit_after:
        get_tree().quit()
    return true

func _exit_tree() -> void:
    if mining != null:
        mining.end_hold()
    if content != null and content.bundle != null:
        content.bundle.shutdown()
    get_tree().auto_accept_quit = _previous_auto_accept_quit

## Gameplay edit boundary: commit authoritative voxel first, then invalidate derived lighting.
func set_block(position_in_voxels: Vector3i, state_id: int) -> void:
    if state_id < 0 or state_id >= content.state_keys.size():
        push_error("Invalid block state")
        return
    if mining != null:
        mining.forget(position_in_voxels)
    voxel_tool.set_voxel(position_in_voxels,state_id)
    # VoxelTerrain emits a versioned area invalidation for every native editing path.

## Inventory and settings own separate modal intervals; the HUD refuses to open over settings.
func _inventory_open_changed(opened: bool) -> void:
    if not ready_to_play:
        return
    controller.set("input_enabled", not opened)
    player.move_intent = Vector3.ZERO
    player.jump_requested = false
    player.sprint_requested = false
    player.slow_walk_requested = false
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if opened else Input.MOUSE_MODE_CAPTURED

## Unexpected runtime failures stop the world. Never save partially applied in-memory transactions.
func fail_stop(message: String) -> void:
    if failed:
        return
    if mining != null:
        mining.end_hold()
    if block_target != null:
        block_target.clear()
    failed = true
    ready_to_play = false
    push_error(message)
    if _status != null:
        _status.text = "运行已停止：" + message
    if inventory != null:
        inventory.locked = true
    controller.set("input_enabled", false)
    controller.set_physics_process(false)
    if pause_menu != null:
        pause_menu.hide()
        pause_menu.process_mode = Node.PROCESS_MODE_DISABLED
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    get_tree().paused = true

## Mode changes publish only after the shared player/inventory journal is durable.
func set_game_mode(mode: int) -> bool:
    if player_state == null or not ready_to_play or saving or failed:
        return false
    return player_state.set_mode(mode)

func _update_control_hint() -> void:
    if not ready_to_play or saving or failed:
        return
    var movement: String = "WASD Move | Ctrl Walk | Shift Sprint | Space Jump"
    if player_state.is_creative():
        movement = "WASD Move | Double Space Fly | Space Up / Ctrl Down | Shift Fast"
    _status.text = movement + (" | Left Mine" if player_state.is_creative() else " | Hold Left Mine") + " | V View | Right Place | 1-0 Select | E Inventory | Q Drop | Esc Menu"
