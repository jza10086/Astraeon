extends RefCounted
## Shared rendering policy for closed cutout cubes. Grass cards remain double sided.
enum Mode { SHELL, LAYERS, STAGGERED }
const SINGLE: Shader = preload("res://game/shading/shaders/plant_layered.gdshader")
const DOUBLE: Shader = preload("res://game/shading/shaders/plant.gdshader")

static func is_foliage(model: VoxelBlockyModel) -> bool:
	return model.get_meta("astraeon_foliage_layers", false) == true

static func apply_material(material: Material, mode: int) -> void:
	assert(mode >= Mode.SHELL and mode <= Mode.STAGGERED)
	if material is ShaderMaterial:
		var shader_material: ShaderMaterial = material as ShaderMaterial
		shader_material.shader = DOUBLE if mode == Mode.SHELL else SINGLE
		shader_material.set_shader_parameter("foliage_staggered", mode == Mode.STAGGERED)
	elif material is BaseMaterial3D:
		(material as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED if mode == Mode.SHELL else BaseMaterial3D.CULL_BACK

## New baked library: running native tasks retain immutable geometry rules.
## Materials stay shared so environment bindings continue to target the same objects.
static func with_mode(source: VoxelBlockyLibrary, mode: int) -> VoxelBlockyLibrary:
	assert(mode >= Mode.SHELL and mode <= Mode.STAGGERED)
	var result: VoxelBlockyLibrary = VoxelBlockyLibrary.new()
	var models: Array[VoxelBlockyModel] = []
	for model: VoxelBlockyModel in source.models:
		if is_foliage(model):
			var copy: VoxelBlockyModel = model.duplicate() as VoxelBlockyModel
			copy.culls_neighbors = mode == Mode.SHELL
			apply_material(copy.get_material_override(0), mode)
			models.append(copy)
		else:
			models.append(model)
	result.models = models
	result.bake()
	return result
