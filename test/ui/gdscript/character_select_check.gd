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
	Models.Library.set_directory(path + "_characters")
	var fixture: Script = preload("res://test/entities/gdscript/fixtures/character_pair_fixture.gd")
	fixture.install(Models.Library.directory, "basic_voxel")
	fixture.install(Models.Library.directory, "fixture")
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
	var buttons: Dictionary = page.get("model_buttons")
	var labels: Dictionary = page.get("current_labels")
	var use_button: Button = page.get("use_button") as Button
	check((buttons[&"basic_voxel"] as Button).text == "basic_voxel" and (buttons[&"fixture"] as Button).text == "fixture", "Model names are the list buttons")
	check((labels[&"basic_voxel"] as Label).visible and not (labels[&"fixture"] as Label).visible, "Current badge starts on saved model")
	check(use_button.button_pressed and use_button.text == "当前使用", "Saved model has pressed current-use action")
	check(not (page.get("message") as Label).visible, "No persistent instruction line")
	use_button.pressed.emit()
	check(use_button.button_pressed and page.visible and Models.load_id(path) == &"basic_voxel", "Current-use action is idempotent")
	check(page.call("model_folder") == ProjectSettings.globalize_path(path + "_characters/basic_voxel"), "Folder points at user character library")
	check(not (page.get("folder_button") as Button).disabled, "Existing folder can be opened")
	page.call("preview", &"fixture")
	check(not use_button.button_pressed and use_button.text == "使用此人物", "Different preview is not marked current")
	check((labels[&"basic_voxel"] as Label).visible and not (labels[&"fixture"] as Label).visible, "Preview does not move saved badge")
	await frames(10)
	var model: Node3D = page.get("preview_model") as Node3D
	var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false) as Skeleton3D
	check(skeleton != null and skeleton.get_bone_count() == 21, "Fixture preview has all 21 bones")
	var animation: AnimationPlayer = model.get_node("AnimationPlayer") as AnimationPlayer
	check(animation.current_animation == "Idle" and animation.is_playing(), "Preview plays Idle")
	check(page.fp_preview_model != null and page.fp_preview_model.get_node("AnimationPlayer").current_animation == "FP_Idle", "The same selection previews the FP pair")
	for clip: StringName in [&"Idle", &"Walk", &"Run", &"Sprint", &"JumpStart", &"Fall"]:
		check(animation.has_animation(clip), "Fixture clip " + String(clip))
	page.call("cancel")
	check(Models.load_id(path) == &"basic_voxel", "Preview cancellation does not save")
	check(page.fp_preview_model == null and page.fp_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Closing releases FP preview")
	check(root.gui_get_focus_owner() == button, "Back restores character button focus")
	button.pressed.emit()
	page.call("preview", &"fixture")
	await frames(3)
	for dimensions: Vector2i in [Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(3840,2160), Vector2i(3440,1440)]:
		root.size = dimensions
		await frames(5)
		var bounds: Rect2 = Rect2(Vector2.ZERO, menu.size)
		check(bounds.encloses(page.get_global_rect()), "Page bounds " + str(dimensions))
		check(bounds.encloses((page.get("use_button") as Button).get_global_rect()), "Confirm button bounds " + str(dimensions))
		check(bounds.encloses((page.get("folder_button") as Button).get_global_rect()) and bounds.encloses((page.get("delete_button") as Button).get_global_rect()), "Top actions within bounds " + str(dimensions))
		check((page.get("viewport") as SubViewport).size.x > 200 and page.fp_viewport.size.x > 200, "Both preview widths " + str(dimensions))
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
	check(Models.load_id(path) == &"fixture" and page.visible, "Confirm persists selection and stays on page")
	check(use_button.button_pressed and use_button.text == "当前使用" and (labels[&"fixture"] as Label).visible and not (labels[&"basic_voxel"] as Label).visible, "Confirm moves badge and presses current-use action")
	await frames(5)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/character_select_current.png")
	page.call("cancel")
	button.pressed.emit()
	check(page.get("selected_id") == &"fixture" and use_button.button_pressed, "Reopening restores saved current model")
	config.load(path)
	check(config.get_value("unrelated", "keep") == 42, "Character save preserves other settings")
	var player: CharacterMotor = Player.instantiate() as CharacterMotor
	var visual: Node3D = player.get_node("Visual") as Node3D
	visual.set("settings_path", path)
	player.get_node("Controller").set("input_enabled", false)
	root.add_child(player)
	await frames(3)
	check(visual.get("model_id") == &"fixture" and player.find_child("Skeleton3D", true, false).get_bone_count() == 21, "New player uses saved model")
	Models.save_id(&"basic_voxel", path)
	await frames()
	check(visual.get("model_id") == &"fixture", "Settings changes do not replace a live player")
	# Removing a current entry updates the saved selection atomically, not a live player.
	Models.save_id(&"fixture", path)
	page.call("cancel")
	button.pressed.emit()
	page.call("delete_selected")
	await frames()
	check(Models.load_id(path) == &"basic_voxel" and Models.available(path).size() == 1, "Deleting current entry selects remaining model")
	check(not (page.get("model_buttons") as Dictionary).has(&"fixture") and (page.get("delete_button") as Button).disabled, "Deleted entry disappears and last entry is protected")
	check((page.get("use_button") as Button).text == "当前使用" and (page.get("use_button") as Button).button_pressed, "Delete fallback is visibly current")
	check(visual.get("model_id") == &"fixture", "Deleting from catalog does not swap live player")
	check(not FileAccess.file_exists(Models.Library.directory.path_join("fixture/fixture_tp.glb")), "External removal deletes only its installed copy")
	check(Models.save_id(&"fixture", path) == ERR_INVALID_PARAMETER, "Removed model cannot be selected")
	check(Models.remove_id(&"basic_voxel", path) == ERR_INVALID_PARAMETER, "Cannot remove final available model")
	config.load(path)
	check(config.get_value("unrelated", "keep") == 42, "Removal preserves unrelated settings")
	page.call("cancel")
	button.pressed.emit()
	check((page.get("model_buttons") as Dictionary).size() == 1 and page.get("selected_id") == &"basic_voxel", "Reopening preserves removal and fallback")
	check(Models.available(path + "_fresh").size() == 1, "Deleted external file is absent for every settings file")
	var invalid_path: String = path + "_invalid"
	config.set_value("character", "model", "unknown")
	config.save(invalid_path)
	page.call("cancel")
	page.call("open", invalid_path)
	check((page.get("delete_button") as Button).disabled and not (page.get("use_button") as Button).button_pressed, "Invalid selection does not retain previous current state")
	check(Models.remove_id(&"basic_voxel", invalid_path) == ERR_INVALID_DATA, "Removal rejects invalid current selection")
	player.queue_free()
	menu.queue_free()
	await frames(3)
	print("CHARACTER_SELECT_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
