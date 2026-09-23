class_name AstraeonCacheCoordinator
extends Node
## One coordinator per world instance; no authoritative voxel mirror.
const Policy: Script = preload("res://game/core/gdscript/cache_policy.gd")
const Settings: Script = preload("res://game/ui/gdscript/cache_settings.gd")
var policy: Policy = Policy.new()
var native: RefCounted
var world: Node3D
var settings_path: String
var _viewer: VoxelViewer
var metrics: Dictionary = {}
var _metric_clock: float = 0.0
var diagnostic_usec: int = 0
func configure(owner_world: Node3D) -> bool:
    world = owner_world
    settings_path = world.shading_settings_path
    var error: Error = policy.load_settings(settings_path)
    if error != OK and error != ERR_FILE_NOT_FOUND:
        push_error("Unsupported cache configuration: " + error_string(error))
        return false
    if int(policy.values.upload_bytes)<Policy.minimum_upload_bytes(world.horizontal_distance):
        push_error("Cache upload limit cannot fit a light page and page tables for this view distance")
        return false
    native = ClassDB.instantiate("AstraeonSectionCache") as RefCounted
    if native == null:
        push_error("Native section cache DLL is not loaded; restart editor after native build")
        return false
    if not native.call("configure",world.terrain,world.content.opacity,world.content.emission,world.content.sources,policy.values):
        return false
    world.terrain.call("apply_derived_cache_policy",int(policy.values.cpu_mib)*1048576/4,float(policy.values.mesh_seconds))
    world.stream.call("set_region_handle_limit",int(policy.values.region_handles))
    var prefetch: Node = world.player.get_node_or_null("PrefetchViewer")
    if prefetch != null:
        prefetch.set("prediction_seconds",float(policy.values.prediction_seconds))
        prefetch.call("set_max_prediction_distance",float(policy.values.prediction_max_m))

    world.terrain.connect("sections_changed",Callable(native,"invalidate_sections"))
    _viewer = VoxelViewer.new()
    _viewer.requires_visuals = false
    _viewer.requires_collisions = false
    _viewer.view_distance = world.horizontal_distance + 16
    _viewer.view_distance_vertical_ratio = 144.0 / _viewer.view_distance
    add_child(_viewer)
    process_priority = -20
    process_mode = Node.PROCESS_MODE_ALWAYS
    return true
func _process(delta: float) -> void:
    if native == null: return
    var start_usec: int = Time.get_ticks_usec()
    var center: Vector3 = world.player.global_position
    _viewer.global_position = Vector3(center.x,64.0,center.z)
    native.call("set_interest",center,world.horizontal_distance,world.vertical_distance,world.player.velocity)
    native.call("commit")
    _metric_clock += delta
    if _metric_clock >= 0.2:
        _metric_clock = 0.0
        metrics = native.call("get_cache_metrics")
        var prefetch: Node = world.player.get_node_or_null("PrefetchViewer")
        if prefetch != null: prefetch.call("set_cache_pressure",bool(metrics.get("unreclaimable_over_budget",false)) or bool(metrics.get("capacity_blocked",false)))
    diagnostic_usec = Time.get_ticks_usec()-start_usec
func add_settings(parent: Control) -> void:
    var menu: Settings = Settings.new()
    parent.add_child(menu)
    menu.configure(self)
func apply_policy() -> Error:
    if not Policy.valid(policy.values): return ERR_INVALID_DATA
    if int(policy.values.upload_bytes)<Policy.minimum_upload_bytes(world.horizontal_distance): return ERR_INVALID_PARAMETER
    # Explicit loading/pause transition for allocation; never resize during a movement frame.
    var was_paused: bool = get_tree().paused
    get_tree().paused = true
    native.call("set_suspended",true)
    var applied: bool = native.call("apply_cache_policy",policy.values)
    native.call("set_suspended",false)
    if applied:
        var deadline: int = Time.get_ticks_msec()+30000
        while not native.call("is_ready") and Time.get_ticks_msec()<deadline:
            await get_tree().process_frame
    get_tree().paused = was_paused
    if not applied: return ERR_INVALID_DATA
    if not native.call("is_ready"): return ERR_TIMEOUT
    world.terrain.call("apply_derived_cache_policy",int(policy.values.cpu_mib)*1048576/4,float(policy.values.mesh_seconds))
    world.stream.call("set_region_handle_limit",int(policy.values.region_handles))
    var prefetch: Node = world.player.get_node_or_null("PrefetchViewer")
    if prefetch != null:
        prefetch.set("prediction_seconds",float(policy.values.prediction_seconds))
        prefetch.call("set_max_prediction_distance",float(policy.values.prediction_max_m))
    return policy.save_settings(settings_path)
func _exit_tree() -> void:
    if native != null: native.call("shutdown")
