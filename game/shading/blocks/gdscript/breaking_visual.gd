extends RefCounted
## Display-only consumer of a gameplay target/progress; no geometry or light propagation edits.
var content: AstraeonWorldContent
var material: ShaderMaterial
var hash: String = ""
var error: String = ""
var state_id: int = -1
func configure(value: AstraeonWorldContent) -> void:
	content = value
func prepare(id: int) -> bool:
	if id != state_id:
		clear()
		state_id = id
		var record: Dictionary = content.bundle.blocks[content.bundle.state_records[content.state_keys[id]].block]
		var group: Dictionary = record.breaking
		if group.is_empty():
			return true
		hash = group.visual
		material = content.library.models[id].get_material_override(0) as ShaderMaterial
		if material == null:
			error = "Breaking target has no compiled ShaderMaterial: " + content.state_keys[id]
			return false
		if not content.bundle.visuals.call("request", "mining_overlay", PackedStringArray([hash])):
			error = "Cannot request breaking texture: " + hash
			return false
		material.set_shader_parameter("breaking_tint", AstraeonWorldContent.color(group.tint))
		material.set_shader_parameter("breaking_strength", float(group.strength))
	if hash.is_empty():
		return true
	var failures: Array = content.bundle.visuals.call("get_metrics").failures
	if not failures.is_empty():
		error = "Breaking texture load failed: " + str(failures)
		return false
	if not content.bundle.visuals.call("is_ready", PackedStringArray([hash])):
		return false
	material.set_shader_parameter("breaking_texture", content.bundle.visuals.call("texture", hash))
	return true
func show_progress(position: Vector3i, progress: float) -> void:
	if material == null:
		return
	material.set_shader_parameter("breaking_target", Vector3(position))
	material.set_shader_parameter("breaking_stage", mini(9, floori(clampf(progress, 0.0, 1.0) * 10.0 + 0.000001)) if progress > 0.0 else -1)
func clear() -> void:
	if material != null:
		material.set_shader_parameter("breaking_stage", -1)
		material.set_shader_parameter("breaking_texture", null)
		material = null
	if content != null and content.bundle != null and content.bundle.visuals != null:
		content.bundle.visuals.call("release", "mining_overlay")
	hash = ""
	state_id = -1
	error = ""
