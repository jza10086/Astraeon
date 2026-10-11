extends RefCounted
## Sparse gameplay damage, never a voxel mirror. 20 Hz damage, session-local retention.
const Visual: Script = preload("res://game/shading/blocks/gdscript/breaking_visual.gd")
const STEP: float = 0.05
const BASE_SPEED: float = 1.0
const DURABILITY_PER_HARDNESS: float = 1.5
var world: Node3D
var visual: Visual
var active: bool = false
var position: Vector3i
var state_id: int = -1
var progress: float = 0.0
var blocked_until_release: bool = false
var held: bool = false
var damage: Dictionary[Vector3i, Dictionary] = {}
var _clock: float = 0.0
var _remainder: float = 0.0
var _tool_key: StringName = &""
func configure(value: Node3D) -> void:
	world = value
	visual = Visual.new()
	visual.configure(world.content)
func begin_hold() -> void:
	held = true
func end_hold() -> void:
	held = false
	cancel()
func tick(delta: float) -> void:
	if world.get_tree().paused or world.failed:
		return
	if not Input.is_action_pressed("mine_block"):
		blocked_until_release = false
		if held or active:
			end_hold()
	if not held or blocked_until_release or not world.ready_to_play or world.saving or world.inventory.locked or world.player_state.is_creative() or not bool(world.controller.get("input_enabled")) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		elapse(delta)
		if held or active:
			end_hold()
		_show_retained_target()
		return
	var hit: VoxelRaycastResult = world.block_target.hit
	if hit == null:
		elapse(delta)
		cancel()
		return
	advance(delta, hit.position, world.block_target.state_id)
## Advance inactivity using game time. Paused frames never call this.
func elapse(delta: float) -> void:
	_clock += maxf(delta, 0.0)
	_expire()
func _expire(exempt: Vector3i = Vector3i(2147483647,0,0)) -> void:
	for cell: Vector3i in damage.keys():
		var entry: Dictionary = damage[cell]
		if cell != exempt and _clock - float(entry.touched) + 0.000000001 >= float(entry.recovery):
			damage.erase(cell)
## Expected edits (including replacement by the same state) invalidate old instance damage.
func forget(cell: Vector3i) -> void:
	damage.erase(cell)
	if active and position == cell:
		cancel()
## Explicit target step for deterministic tests and the held-input consumer.
func advance(delta: float, cell: Vector3i, id: int) -> void:
	if not is_finite(delta) or delta < 0.0:
		world.fail_stop("Invalid mining step: " + str(delta))
		return
	_clock += delta
	var continuing: bool = active and position == cell and state_id == id
	if continuing:
		_expire(cell)
	else:
		_expire()
	if id <= 0 or id == world.content.water_id:
		cancel()
		return
	if id >= world.content.state_keys.size():
		cancel()
		world.fail_stop("Mining target has an unregistered state ID: " + str(id))
		return
	if not world.voxel_tool.is_area_editable(AABB(Vector3(cell), Vector3.ONE)):
		cancel()
		return
	if world.voxel_tool.get_voxel(cell) != id:
		forget(cell)
		cancel()
		return
	if not continuing:
		cancel()
		active = true
		position = cell
		state_id = id
	if not visual.prepare(id):
		if not visual.error.is_empty():
			var failure: String = visual.error
			cancel()
			world.fail_stop(failure)
		return
	var record: Dictionary = world.content.bundle.blocks[world.content.bundle.state_records[world.content.state_keys[id]].block]
	var durability: float = float(record.hardness) * DURABILITY_PER_HARDNESS
	if damage.has(cell) and int(damage[cell].state) != id:
		damage.erase(cell)
	var entry: Dictionary = damage.get(cell, {"state":id,"amount":0.0,"touched":_clock,"recovery":float(record.mining_recovery_seconds)})
	var stack: AstraeonItemStack = world.inventory.stack_at(world.inventory.selected)
	var tool_key: StringName = stack.item.key if stack != null else &""
	if tool_key != _tool_key:
		_remainder = 0.0
		_tool_key = tool_key
	var speed: float = BASE_SPEED
	if stack != null and not String(record.required_tool_tag).is_empty() and stack.item.tool_tags.has(String(record.required_tool_tag)):
		speed = stack.item.mining_speed
	_remainder += delta
	var steps: int = floori((_remainder + 0.000000001) / STEP)
	_remainder = maxf(0.0, _remainder - steps * STEP)
	entry.amount = minf(durability, float(entry.amount) + steps * STEP * speed)
	entry.touched = _clock
	if float(entry.amount) > 0.0:
		damage[cell] = entry
	progress = (1.0 if steps > 0 else 0.0) if durability == 0.0 else minf(1.0, float(entry.amount) / durability)
	visual.show_progress(position, progress)
	if progress >= 1.0 - 0.000000001:
		var completed: Vector3i = position
		damage.erase(completed)
		cancel()
		if not world.inventory_interaction.edit(completed, false):
			blocked_until_release = true
func _show_retained_target() -> void:
	if world.player_state.is_creative() or world.block_target.hit == null:
		visual.clear()
		return
	var cell: Vector3i = world.block_target.hit.position
	if not damage.has(cell):
		visual.clear()
		return
	var id: int = world.block_target.state_id
	if int(damage[cell].state) != id:
		damage.erase(cell)
		return
	var record: Dictionary = world.content.bundle.blocks[world.content.bundle.state_records[world.content.state_keys[id]].block]
	if visual.prepare(id):
		visual.show_progress(cell, float(damage[cell].amount) / (float(record.hardness) * DURABILITY_PER_HARDNESS))
	elif not visual.error.is_empty():
		world.fail_stop(visual.error)
func cancel() -> void:
	if active and damage.has(position) and float(damage[position].recovery) == 0.0:
		damage.erase(position)
	if visual != null:
		visual.clear()
	active = false
	state_id = -1
	progress = 0.0
	_remainder = 0.0
	_tool_key = &""
