extends SceneTree
var checks: int = 0
var failures: int = 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var packed: PackedScene = load("res://test/shading/scenes/content_sample.tscn")
	var scene: Node3D = packed.instantiate()
	root.add_child(scene)
	var image: Image = (load("res://test/data/assets/appearance_reference/leaves_checker.svg") as Texture2D).get_image()
	var transparent: int = 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a < 0.5:
				transparent += 1
	check(transparent * 2 == image.get_width() * image.get_height(), "Exactly half the leaf pixels are transparent")
	var content: AstraeonWorldContent = scene.get("content")
	var leaf_id: int = content.state_keys.find("astraeon:leaves/default")
	var glow_id: int = content.state_keys.find("astraeon:glowstone/default")
	var leaf_material: ORMMaterial3D = content.library.models[leaf_id].get_material_override(0)
	var glow_material: ORMMaterial3D = content.library.models[glow_id].get_material_override(0)
	check(leaf_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "Cutout material")
	check(leaf_material.cull_mode == BaseMaterial3D.CULL_BACK, "Layered leaves use front faces without coplanar double drawing")
	check(glow_material.emission_enabled and glow_material.emission_energy_multiplier == 3.0, "Emission compiled")
	var light: OmniLight3D = scene.get("glow_light")
	check(light.light_color == Color.WHITE and light.shadow_enabled, "White static light with shadows")
	light.visible = false
	check(glow_material.emission_enabled, "Illumination toggle preserves surface emission")
	light.visible = true
	var player: CharacterMotor = scene.get("player")
	player.get_node("Controller").set("input_enabled", false)
	for frame: int in range(120):
		await physics_frame
	check(player.is_on_floor(), "Production player rests on native mesh collider")
	check(player.position.y > 0.8 and player.position.y < 1.2, "Native mesh padding and floor match")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://tmp/shading-content")
		check(root.get_texture().get_image().save_png("res://tmp/shading-content/content_sample.png") == OK, "Rendered screenshot")
	print("CONTENT_SAMPLE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
