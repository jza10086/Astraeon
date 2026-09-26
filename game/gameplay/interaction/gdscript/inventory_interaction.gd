class_name AstraeonInventoryInteraction
extends RefCounted
## Main-thread single-player transaction boundary. No scene/node per voxel.
var world: Node3D
var inventory: AstraeonInventoryState
var drops: Dictionary[String, StringName] = {}
var message: String = ""

func configure(target: Node3D, state: AstraeonInventoryState) -> void:
	world = target
	inventory = state
	for item: AstraeonItemDefinition in inventory.items.values():
		if item.block != null:
			drops[String(item.block.key)] = item.key

func edit(position: Vector3i, placing: bool, normal: Vector3i = Vector3i.UP) -> bool:
	message = ""
	if inventory.locked or position.y < -64 or position.y >= 192 or not world.terrain.bounds.has_point(Vector3(position)) or not world.voxel_tool.is_area_editable(AABB(Vector3(position), Vector3.ONE)):
		message = "区段尚未加载或正在保存"
		return false
	var previous: int = world.voxel_tool.get_voxel(position)
	if previous < 0 or previous >= world.content.state_keys.size():
		return false
	var new_state: int = 0
	if placing:
		var stack: AstraeonItemStack = inventory.stack_at(inventory.selected)
		if stack == null or stack.item.block == null:
			message = "当前槽位没有可放置物品"
			return false
		if previous != 0 and previous != world.content.water_id:
			return false
		var player_box: AABB = AABB(world.player.position - Vector3(0.35, 0.0, 0.35), Vector3(0.7, 1.8, 0.7))
		if AABB(Vector3(position), Vector3.ONE).intersects(player_box):
			return false
		new_state = world.content.state_keys.find(stack.item.state_key(normal))
		if new_state < 0:
			message = "物品的方块状态尚未注册"
			return false
		if not inventory.consume(inventory.selected, 1, {"position": position, "state": world.content.state_keys[new_state]}):
			return false
	else:
		var block_key: String = world.content.state_keys[previous].get_slice("/", 0)
		if not drops.has(block_key):
			return false
		var key: StringName = drops[block_key]
		if inventory.capacity(key) < 1:
			message = "物品栏已满"
			return false
		if inventory.insert(key, 1, {"position": position, "state": world.content.state_keys[0]}) != 0:
			return false
	world.set_block(position, new_state)
	return true
