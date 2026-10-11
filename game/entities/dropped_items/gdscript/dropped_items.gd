extends Node3D
## Scene-local drop system. Native records own motion/query/state; meshes are derived views.
var world: Node3D
var pool: RefCounted
var _views: Dictionary[int, MeshInstance3D] = {}
var _meshes: Dictionary[StringName, Mesh] = {}
var _materials: Dictionary[StringName, StandardMaterial3D] = {}
var _hashes: Dictionary[StringName, String] = {}
var _owners: Dictionary[StringName, bool] = {}
var _keys: PackedStringArray
var _limits: PackedInt32Array
var _solid: PackedByteArray
var _mining_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _pickup_elapsed: float = 0.0
const ThrowSettings: Script = preload("res://game/gameplay/inventory/gdscript/throw_settings.gd")
var throw_settings: ThrowSettings = ThrowSettings.new()

func configure(target: Node3D) -> bool:
	world = target
	_mining_rng.randomize()
	if world.controller.visual.hand_skeleton == null or world.controller.visual.hand_bone < 0:
		world.fail_stop("人物缺少右手投掷所需的 RightLowerArm 骨骼")
		return false
	var settings_error: Error = throw_settings.load_settings(world.shading_settings_path)
	if settings_error != OK:
		world.fail_stop("无法读取扔出设置: " + error_string(settings_error))
		return false
	if not ClassDB.class_exists("AstraeonDroppedItems"):
		world.fail_stop("缺少掉落物原生 API，请重启并加载当前扩展")
		return false
	pool = ClassDB.instantiate("AstraeonDroppedItems")
	var keys: PackedStringArray = []
	var limits: PackedInt32Array = []
	for item: AstraeonItemDefinition in world.item_catalog.definitions:
		keys.append(String(item.key))
		limits.append(item.max_stack)
	var solid: PackedByteArray = []
	for state: String in world.content.state_keys:
		solid.append(0 if state == "astraeon:air/default" else int(world.content.bundle.blocks[world.content.bundle.state_records[state].block].collision))
	_keys = keys
	_limits = limits
	_solid = solid
	if not pool.call("configure", keys, limits, solid):
		world.fail_stop(pool.call("get_error"))
		return false
	return true

## Failure is terminal. No return-to-inventory, alternate position, or retry branch.
func spawn_item(key: StringName, count: int, position_in_world: Vector3, velocity: Vector3, delay: float = 0.6) -> bool:
	if world.failed:
		return false
	if int(pool.call("spawn", String(key), count, position_in_world, velocity, delay)) == 0:
		world.fail_stop(String(pool.call("get_error")))
		return false
	return true

func drop_selected(whole: bool) -> void:
	if world.saving or world.inventory.locked:
		return
	var stack: AstraeonItemStack = world.inventory.stack_at(world.inventory.selected)
	if stack == null:
		return
	var count: int = stack.count if whole else 1
	var previous: RefCounted = _begin_transaction()
	if previous == null:
		return
	if not _throw(stack.item.key, count):
		_abort_transaction(previous)
		return
	if not world.inventory.consume(world.inventory.selected, count):
		_abort_transaction(previous)
		world.fail_stop("掉落物事务写入失败: " + world.inventory_store.error)

## Stage the native candidate; rollback only the uncommitted candidate on failure and stop.
func drop_cursor(one: bool = false) -> bool:
	var stack: AstraeonItemStack = world.inventory.cursor_stack()
	if stack == null:
		return true
	if world.failed or world.saving or world.inventory.locked:
		return false
	var previous: RefCounted = _begin_transaction()
	if previous == null:
		return false
	if not _throw(stack.item.key, 1 if one else stack.count):
		_abort_transaction(previous)
		return false
	if not world.inventory.consume_cursor(one):
		_abort_transaction(previous)
		world.fail_stop("鼠标掉落物事务写入失败: " + world.inventory_store.error)
		return false
	return true

func _throw(key: StringName, count: int) -> bool:
	var launch: Dictionary = throw_trajectory()
	return spawn_item(key, count, launch.origin, launch.velocity, 0.8)

## Aim converges from the animated hand to the camera's pointer ray hit.
func throw_trajectory() -> Dictionary:
	var viewport: Viewport = world.camera.get_viewport()
	var pointer: Vector2 = viewport.get_visible_rect().size * 0.5 if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else viewport.get_mouse_position()
	var ray_origin: Vector3 = world.camera.project_ray_origin(pointer)
	var direction: Vector3 = world.camera.project_ray_normal(pointer)
	var hit: VoxelRaycastResult = world.voxel_tool.raycast(ray_origin, direction, 64.0)
	var target: Vector3 = ray_origin + direction * (hit.distance if hit != null else 64.0)
	var origin: Vector3 = world.controller.visual.throw_origin()
	return {"origin": origin, "velocity": origin.direction_to(target) * throw_settings.strength, "target": target}

func add_settings(parent: VBoxContainer) -> void:
	var controls: VBoxContainer = preload("res://game/ui/inventory/gdscript/throw_settings_panel.gd").new()
	var draft: ThrowSettings = throw_settings.duplicate() as ThrowSettings
	controls.configure(draft)
	parent.add_child(controls)
	var save: Button = Button.new()
	save.name = "SaveDropSettings"
	save.text = "保存投掷与掉落设置"
	save.pressed.connect(func() -> void:
		var error: Error = draft.save_settings(world.shading_settings_path)
		if error != OK:
			world.fail_stop("扔出设置保存失败: " + error_string(error))
			return
		throw_settings.strength = draft.strength
		throw_settings.mining_player_strength = draft.mining_player_strength)
	controls.add_child(save)

## Spawn inside the removed cell; add one horizontal launch bias without changing upward bounce.
## Randomness is cosmetic and never changes terrain generation or loot quantities.
func mining_trajectory(position_in_voxels: Vector3i) -> Dictionary:
	var offset: Vector3 = Vector3(_mining_rng.randf_range(-0.2, 0.2), _mining_rng.randf_range(-0.2, 0.2), _mining_rng.randf_range(-0.2, 0.2))
	var origin: Vector3 = Vector3(position_in_voxels) + Vector3(0.5, 0.5, 0.5) + offset
	var velocity: Vector3 = Vector3(_mining_rng.randf_range(-1.0, 1.0), _mining_rng.randf_range(3.0, 4.0), _mining_rng.randf_range(-1.0, 1.0))
	var toward_player: Vector3 = world.player.position - origin
	toward_player.y = 0.0
	velocity += toward_player.normalized() * throw_settings.mining_player_strength
	return {"origin": origin, "velocity": velocity}

func mine(key: StringName, position_in_voxels: Vector3i) -> bool:
	var previous: RefCounted = _begin_transaction()
	if previous == null:
		return false
	var launch: Dictionary = mining_trajectory(position_in_voxels)
	if not spawn_item(key, 1, launch.origin, launch.velocity, 0.35):
		_abort_transaction(previous)
		return false
	if not world.inventory.commit_world({"position": position_in_voxels, "state": world.content.state_keys[0]}):
		_abort_transaction(previous)
		world.fail_stop("挖掘掉落物事务写入失败: " + world.inventory_store.error)
		return false
	return true

func _physics_process(delta: float) -> void:
	if not world.ready_to_play or world.saving or world.failed:
		return
	pool.call("step", delta, world.player.position, world.voxel_tool)
	if not String(pool.call("get_error")).is_empty():
		world.fail_stop(pool.call("get_error"))
		return
	_pickup_elapsed += delta
	if _pickup_elapsed >= 0.15:
		_pickup_elapsed = 0.0
		pickup_nearby()
	if not world.failed:
		_update_views()

func pickup_nearby() -> void:
	var center: Vector3 = world.player.position + Vector3.UP * 0.5
	var records: Array = pool.call("nearby", center, 1.4, true)
	for record: Dictionary in records:
		var quantity: int = mini(world.inventory.capacity(StringName(record.item)), int(record.count))
		if quantity == 0:
			continue
		var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(center, record.position, 1, [world.player.get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		var previous: RefCounted = _begin_transaction()
		if previous == null:
			return
		if not pool.call("take", record.id, quantity):
			world.fail_stop(pool.call("get_error"))
			_abort_transaction(previous)
			return
		if world.inventory.insert(StringName(record.item), quantity) != 0:
			_abort_transaction(previous)
			world.fail_stop("拾取事务写入失败: " + world.inventory_store.error)
			return

func _update_views() -> void:
	var records: Array = pool.call("nearby", world.player.position, 32.0, false)
	var alive: Dictionary[int, bool] = {}
	var types: Dictionary[StringName, bool] = {}
	for record: Dictionary in records:
		var key: StringName = StringName(record.item)
		types[key] = true
		if not _meshes.has(key):
			_build_mesh(world.inventory.items[key])
		var hash: String = _hashes[key]
		if not hash.is_empty():
			if not _owners.has(key):
				if not world.content.bundle.visuals.call("request", "drop:" + String(key), PackedStringArray([hash])):
					world.fail_stop("掉落物外观请求失败: " + String(key))
					return
				_owners[key] = true
			if not world.content.bundle.visuals.call("is_ready", PackedStringArray([hash])):
				continue
			_materials[key].albedo_texture = world.content.bundle.visuals.call("texture", hash)
		alive[int(record.id)] = true
		if not _views.has(int(record.id)):
			var view: MeshInstance3D = MeshInstance3D.new()
			view.mesh = _meshes[key]
			add_child(view)
			_views[int(record.id)] = view
		_views[int(record.id)].position = record.position
		_views[int(record.id)].rotation.y = float(Time.get_ticks_msec()) * 0.001
	for id: int in _views.keys():
		if not alive.has(id):
			_views[id].queue_free()
			_views.erase(id)
	for key: StringName in _owners.keys():
		if not types.has(key):
			world.content.bundle.visuals.call("release", "drop:" + String(key))
			_materials[key].albedo_texture = null
			_owners.erase(key)

func _build_mesh(item: AstraeonItemDefinition) -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh: Mesh
	var hash: String = ""
	if item.block == null:
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2(0.36, 0.36)
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		quad.material = material
		mesh = quad
		hash = String(item.get_meta("content_icon", ""))
		if hash.is_empty():
			material.albedo_texture = item.icon
	else:
		var record: Dictionary = world.content.bundle.blocks[String(item.block.key)]
		hash = record.visual
		mesh = _cube_mesh(material, record.surface.colors, hash.is_empty())
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR if int(record.surface.alpha) == 1 else BaseMaterial3D.TRANSPARENCY_DISABLED
	_meshes[item.key] = mesh
	_materials[item.key] = material
	_hashes[item.key] = hash

func _cube_mesh(material: StandardMaterial3D, colors: Array, use_colors: bool) -> Mesh:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	material.vertex_color_use_as_albedo = true
	# Compiled face colors are authoring sRGB, matching terrain source_color uniforms.
	# Treating them as linear makes untextured drops visibly washed out.
	material.vertex_color_is_srgb = true
	var normals: Array[Vector3] = [Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
	for face: int in range(6):
		var normal: Vector3 = normals[face]
		var rgba: Array = colors[face]
		surface.set_color(Color(rgba[0], rgba[1], rgba[2], rgba[3]) if use_colors else Color.WHITE)
		var right: Vector3 = Vector3.RIGHT if face < 2 else Vector3.UP.cross(normal)
		var up: Vector3 = normal.cross(right)
		for corner: int in [0, 1, 2, 0, 2, 3]:
			var uv: Vector2 = [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)][corner]
			surface.set_normal(normal)
			surface.set_uv(Vector2((face + uv.x) / 6.0, uv.y))
			surface.add_vertex((normal + right * (uv.x * 2 - 1) + up * (1 - uv.y * 2)) * 0.14)
	return surface.commit()

## A short-lived native candidate keeps the published pool intact until the inventory write succeeds.
## The current API restores into an empty pool only; never use restore as in-place rollback.
func _begin_transaction() -> RefCounted:
	var candidate: RefCounted = ClassDB.instantiate("AstraeonDroppedItems")
	if not candidate.call("configure", _keys, _limits, _solid) or not candidate.call("restore", pool.call("snapshot")):
		world.fail_stop("无法准备掉落物事务：" + String(candidate.call("get_error")))
		return null
	var previous: RefCounted = pool
	pool = candidate
	world.inventory_store.dropped_items = candidate
	return previous

func _abort_transaction(previous: RefCounted) -> void:
	pool = previous
	world.inventory_store.dropped_items = previous
