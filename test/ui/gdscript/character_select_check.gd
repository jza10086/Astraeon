extends SceneTree
const Menu: PackedScene = preload("res://game/ui/main_menu/scenes/main_menu.tscn")
const Player: PackedScene = preload("res://game/entities/player/scenes/player.tscn")
const Models: Script = preload("res://game/entities/common/gdscript/character_models.gd")
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int = 3) -> void:
	for i: int in range(count):
		await process_frame

func _run() -> void:
	root.get_node("MCPRuntimeServer").call("_stop_server")
	create_timer(90).timeout.connect(func() -> void: quit(2))
	var path: String = "res://tmp/character_select_%s.cfg" % Time.get_ticks_usec()
	var config: ConfigFile = ConfigFile.new()
	config.set_value("unrelated", "keep", 42)
	config.save(path)
	var menu: Control = Menu.instantiate() as Control
	menu.set("settings_path", path)
	root.add_child(menu)
	await frames()
	var button: Button = menu.get_node("%Characters") as Button
	check(button.get_global_rect().position.y > menu.size.y * 0.8 and button.get_global_rect().position.x < menu.size.x * 0.2, "Character entry at bottom left")
	button.pressed.emit()
	await frames()
	var page: Control = menu.get("character_page") as Control
	check(page.visible and not (menu.get("home") as Control).visible, "Character page replaces home")
	check(page.get("selected_id") == &"basic_voxel", "New settings default to standard body")
	page.call("preview", &"klukai")
	await frames(10)
	var model: Node3D = page.get("preview_model") as Node3D
	var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false) as Skeleton3D
	check(skeleton != null and skeleton.get_bone_count() == 67, "Klukai preview has all 67 bones")
	var animation: AnimationPlayer = model.get_node("AnimationPlayer") as AnimationPlayer
	check(animation.current_animation == "Idle" and animation.is_playing(), "Preview plays Idle")
	for clip: StringName in [&"Idle", &"Walk", &"Run", &"Sprint", &"JumpStart", &"Fall"]:
		check(animation.has_animation(clip), "Klukai clip " + String(clip))
	page.call("cancel")
	check(Models.load_id(path) == &"basic_voxel", "Preview cancellation does not save")
	check(root.gui_get_focus_owner() == button, "Back restores character button focus")
	button.pressed.emit()
	page.call("preview", &"klukai")
	await frames(3)
	for dimensions: Vector2i in [Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(3840,2160), Vector2i(3440,1440)]:
		root.size = dimensions
		await frames(5)
		var bounds: Rect2 = Rect2(Vector2.ZERO, menu.size)
		check(bounds.encloses(page.get_global_rect()), "Page bounds " + str(dimensions))
		check(bounds.encloses((page.get("use_button") as Button).get_global_rect()), "Confirm button bounds " + str(dimensions))
		check((page.get("viewport") as SubViewport).size.x > 200, "Preview width " + str(dimensions))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/character_select_%dx%d.png" % [dimensions.x, dimensions.y])
	root.size = Vector2i(1920,1080)
	var list: VBoxContainer = page.get("list") as VBoxContainer
	var scroll: ScrollContainer = page.get("scroll") as ScrollContainer
	var spacer: Control = Control.new()
	spacer.custom_minimum_size.y = 1800
	list.add_child(spacer)
	await frames(4)
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = scroll.get_global_rect().get_center()
	root.push_input(wheel)
	await frames(5)
	check(scroll.scroll_vertical > 0, "Mouse wheel scrolls overflowing model list")
	spacer.queue_free()
	page.call("confirm")
	check(Models.load_id(path) == &"klukai" and not page.visible, "Confirm persists selection and returns")
	config.load(path)
	check(config.get_value("unrelated", "keep") == 42, "Character save preserves other settings")
	var player: CharacterMotor = Player.instantiate() as CharacterMotor
	var visual: Node3D = player.get_node("Visual") as Node3D
	visual.set("settings_path", path)
	player.get_node("Controller").set("input_enabled", false)
	root.add_child(player)
	await frames(3)
	check(visual.get("model_id") == &"klukai" and player.find_child("Skeleton3D", true, false).get_bone_count() == 67, "New player uses saved model")
	Models.save_id(&"basic_voxel", path)
	await frames()
	check(visual.get("model_id") == &"klukai", "Settings changes do not replace a live player")
	player.queue_free()
	menu.queue_free()
	await frames(3)
	print("CHARACTER_SELECT_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
