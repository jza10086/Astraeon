extends "res://test/shading/gdscript/test_lighting_modules.gd"
func _settings_checks() -> void:
	var catalog: AstraeonBlockCatalog = preload("res://test/shading/resources/blocks/catalog.tres")
	_check(catalog.definitions.size() == 5, "All solid fixture definitions including air")
	for definition: AstraeonBlockDefinition in catalog.definitions:
		_check(String(definition.key).begins_with("shading_test_"), "Independent test namespace")
		if definition.key != &"shading_test_air":
			_check(definition.appearance.validate().is_empty(), "Valid appearance")
func _render_checks() -> void:
	_render = SubViewport.new()
	_render.size = Vector2i(1280, 720)
	_render.own_world_3d = true
	_render.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_render)
	var scene: PackedScene = load("res://test/shading/scenes/shading_sample.tscn")
	_sample = scene.instantiate() as Sample
	_sample.settings_path = _output.path_join("sample-settings.cfg")
	_render.add_child(_sample)
	_sample._start()
	await _settle()
	_check(_sample._volume.voxels is VoxelBuffer, "Native authoritative storage")
	_check(_sample._sections.pending_count() == 0, "All native sections built")
	_check(_sample._sections.materials[3].get_shader_parameter("block_cutout") == true, "Leaves consume compiled cutout")
	_check(_sample._sections.materials[0].get_shader_parameter("block_atlas") != null, "Shared builder atlas bound")
	_sample._toggle_lamp()
	await _settle()
	_sample._toggle_window()
	await _settle()
	await _capture("native-sample")
