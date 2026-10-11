extends RefCounted
## Shared current target for hover feedback and held mining; voxel queries stay native.
const Visual: Script = preload("res://game/shading/blocks/gdscript/block_target_visual.gd")
const REACH: float = 8.0
var world: Node3D
var visual: MeshInstance3D
var hit: VoxelRaycastResult
var state_id: int = 0

func configure(value: Node3D) -> void:
	world = value
	visual = Visual.new()
	world.add_child(visual)

func clear() -> void:
	hit = null
	state_id = 0
	visual.hide()

func refresh() -> void:
	clear()
	if not world.ready_to_play or world.failed or world.saving or world.get_tree().paused or world.inventory.locked or not bool(world.controller.get("input_enabled")) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var result: VoxelRaycastResult = world.voxel_tool.raycast(world.camera.global_position, -world.camera.global_basis.z, REACH)
	if result == null or not world.voxel_tool.is_area_editable(AABB(Vector3(result.position), Vector3.ONE)):
		return
	var id: int = world.voxel_tool.get_voxel(result.position)
	if id <= 0 or id == world.content.water_id:
		return
	hit = result
	state_id = id
	visual.show_cell(result.position)
