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
		var hashes: PackedStringArray = world.content.bundle.state_visuals(PackedInt32Array([new_state]))
		world.content.bundle.visuals.call("request", "placement", hashes)
		if not world.content.bundle.visuals.call("is_ready", hashes):
			message = "正在准备方块外观，请稍候再次放置"
			return false
		var context: Dictionary = {"position": position, "state": world.content.state_keys[new_state]}
		var committed: bool = inventory.commit_world(context) if inventory.player_state.is_creative() else inventory.consume(inventory.selected, 1, context)
		if not committed:
			return false
	elif inventory.player_state.is_creative():
		if previous == 0 or previous == world.content.water_id:
			return false
		if not inventory.commit_world({"position": position, "state": world.content.state_keys[0]}):
			return false
	else:
		var block_key: String = world.content.state_keys[previous].get_slice("/", 0)
		if not drops.has(block_key):
			return false
		var key: StringName = drops[block_key]
		if not world.dropped_items.mine(key, position):
			return false
	world.set_block(position, new_state)
	return true
