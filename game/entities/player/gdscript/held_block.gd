extends Node3D
## Selected block presentation only: no collider, inventory mutation or world voxel.
signal failed(message: String)
var inventory: AstraeonInventoryState
var bundle: AstraeonContentBundle
var visual: Node3D
var display: MeshInstance3D
var attachment: BoneAttachment3D
var fp_attachment: BoneAttachment3D
var fp_display: MeshInstance3D
var item: AstraeonItemDefinition
var material: StandardMaterial3D
var visual_hash: String = ""
var owner_key: String

func configure(state: AstraeonInventoryState, content: AstraeonContentBundle, character: Node3D) -> void:
	inventory = state
	bundle = content
	visual = character
	owner_key = "held:" + str(get_instance_id())

func _ready() -> void:
	attachment = BoneAttachment3D.new()
	attachment.bone_name = &"Grip_R"
	(visual.get("hand_skeleton") as Skeleton3D).add_child(attachment)
	display = MeshInstance3D.new()
	display.visible = false
	display.position = Vector3(0.0, 0.0, 0.06)
	# Authoring cube up +Y becomes grip outward +Z.
	display.rotation.x = PI * 0.5
	attachment.add_child(display)
	fp_attachment = BoneAttachment3D.new()
	fp_attachment.bone_name = &"Grip_R"
	(visual.get("first_person_skeleton") as Skeleton3D).add_child(fp_attachment)
	fp_display = MeshInstance3D.new()
	fp_display.visible = false
	fp_display.transform = display.transform
	fp_display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fp_attachment.add_child(fp_display)
	inventory.changed.connect(_selection_changed)
	_selection_changed()

func _selection_changed() -> void:
	var stack: AstraeonItemStack = inventory.stack_at(inventory.selected)
	var next: AstraeonItemDefinition = stack.item if stack != null and stack.item.block != null else null
	if next == item:
		return
	bundle.visuals.call("release", owner_key)
	item = next
	visual_hash = ""
	display.visible = false
	visual.set("holding_block", false)
	display.mesh = null
	fp_display.mesh = null
	fp_display.visible = false
	if item == null:
		return
	var record: Dictionary = bundle.blocks[String(item.block.key)]
	visual_hash = record.visual
	material = StandardMaterial3D.new()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR if int(record.surface.alpha) == 1 else BaseMaterial3D.TRANSPARENCY_DISABLED
	material.alpha_scissor_threshold = float(record.surface.cutoff)
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	var normals: Array[Vector3] = [Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
	for face: int in range(6):
		var normal: Vector3 = normals[face]
		var rgba: Array = record.surface.colors[face]
		surface.set_color(Color(rgba[0], rgba[1], rgba[2], rgba[3]) if visual_hash.is_empty() else Color.WHITE)
		var right: Vector3 = Vector3.RIGHT if face < 2 else Vector3.UP.cross(normal)
		var up: Vector3 = normal.cross(right)
		for corner: int in [0, 1, 2, 0, 2, 3]:
			var uv: Vector2 = [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)][corner]
			surface.set_normal(normal)
			surface.set_uv(Vector2((face + uv.x) / 6.0, uv.y))
			surface.add_vertex((normal + right * (uv.x * 2 - 1) + up * (1 - uv.y * 2)) * 0.06)
	display.mesh = surface.commit()
	fp_display.mesh = display.mesh
	if not visual_hash.is_empty():
		bundle.visuals.call("request", owner_key, PackedStringArray([visual_hash]))
	else:
		display.visible = true
		fp_display.visible = true
		visual.set("holding_block", true)

func _process(_delta: float) -> void:
	if item == null or visual_hash.is_empty() or display.visible:
		return
	var errors: Array = bundle.visuals.call("get_metrics").get("failures", [])
	if not errors.is_empty():
		set_process(false)
		failed.emit("手持方块外观加载失败: " + str(errors))
		return
	if bundle.visuals.call("is_ready", PackedStringArray([visual_hash])):
		material.albedo_texture = bundle.visuals.call("texture", visual_hash)
		if material.albedo_texture == null:
			set_process(false)
			failed.emit("手持方块缓存已就绪但纹理为空: " + visual_hash)
			return
		display.visible = true
		fp_display.visible = true
		visual.set("holding_block", true)

func _exit_tree() -> void:
	bundle.visuals.call("release", owner_key)
	if is_instance_valid(attachment):
		attachment.queue_free()
	if is_instance_valid(fp_attachment):
		fp_attachment.queue_free()
