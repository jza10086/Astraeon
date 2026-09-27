extends RefCounted
## Instance-local headless mesh for the first-person body. Full meshes stay shared.
var parts: Array[Dictionary] = []

func _init(model: Node3D) -> void:
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = node as MeshInstance3D
		var skeleton: Skeleton3D = instance.get_node_or_null(instance.skeleton) as Skeleton3D
		if skeleton == null or instance.skin == null:
			continue
		var head: int = skeleton.find_bone("Head")
		if head < 0:
			continue
		var source: ArrayMesh = instance.mesh as ArrayMesh
		var body: ArrayMesh = ArrayMesh.new()
		body.blend_shape_mode = source.blend_shape_mode
		for index: int in range(source.get_blend_shape_count()):
			body.add_blend_shape(source.get_blend_shape_name(index))
		var hidden_binds: Array[int] = []
		for bind: int in range(instance.skin.get_bind_count()):
			var name: StringName = instance.skin.get_bind_name(bind)
			var bone: int = skeleton.find_bone(name) if not name.is_empty() else instance.skin.get_bind_bone(bind)
			while bone >= 0 and bone != head:
				bone = skeleton.get_bone_parent(bone)
			if bone == head:
				hidden_binds.append(bind)
		for surface: int in range(source.get_surface_count()):
			var arrays: Array = source.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var stride: int = bones.size() / vertices.size()
			var hidden: PackedByteArray = PackedByteArray()
			hidden.resize(vertices.size())
			for vertex: int in range(vertices.size()):
				var head_weight: float = 0.0
				for influence: int in range(stride):
					var offset: int = vertex * stride + influence
					if bones[offset] in hidden_binds:
						head_weight += weights[offset]
				hidden[vertex] = 1 if head_weight > 0.5 else 0
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				for vertex: int in range(vertices.size()):
					indices.append(vertex)
			var kept: PackedInt32Array = PackedInt32Array()
			for triangle: int in range(0, indices.size(), 3):
				if hidden[indices[triangle]] or hidden[indices[triangle + 1]] or hidden[indices[triangle + 2]]:
					continue
				kept.append_array(indices.slice(triangle, triangle + 3))
			if kept.is_empty():
				continue
			arrays[Mesh.ARRAY_INDEX] = kept
			body.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, source.surface_get_blend_shape_arrays(surface), {}, source.surface_get_format(surface))
			body.surface_set_material(body.get_surface_count() - 1, instance.get_active_material(surface))
		parts.append({"instance": instance, "full": source, "body": body})

func apply(first_person: bool) -> void:
	for part: Dictionary in parts:
		var instance: MeshInstance3D = part.instance
		var mesh: ArrayMesh = part.body if first_person else part.full
		instance.visible = mesh.get_surface_count() > 0
		if instance.visible:
			instance.mesh = mesh
