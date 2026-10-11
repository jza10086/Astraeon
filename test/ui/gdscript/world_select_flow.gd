extends Node
const Menu: PackedScene = preload("res://game/ui/main_menu/scenes/main_menu.tscn")
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _wait_world() -> Node:
	var deadline: int = Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		var current: Node = get_tree().current_scene
		if current != null and current.scene_file_path == "res://game/core/main.tscn" and current.ready_to_play:
			return current
		await get_tree().process_frame
	return null

func _run() -> void:
	var base: String = "res://tmp/world_select_flow_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(base)
	var settings: String = base + "/settings.cfg"
	var menu: Control = Menu.instantiate()
	menu.settings_path = settings
	menu.worlds_root = base + "/worlds"
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	menu.get_node("%Play").pressed.emit()
	check(menu.world_page.visible and not menu.loading, "Single-player opens chooser without world")
	menu.world_page._show_create()
	menu.world_page.name_input.text = "流程验证"
	menu.world_page.seed_input.text = "-12345"
	menu.world_page.create_world()
	var world: Node = await _wait_world()
	check(world != null, "Create reaches playable native world")
	if world == null:
		get_tree().quit(1)
		return
	var expected: String = base + "/worlds/流程验证"
	check(world.world_directory == expected and world.shading_settings_path == settings and world.seed == -12345, "Selected directory and settings reach world")
	world.pause_menu.open_menu()
	await world.pause_menu.return_to_title()
	await get_tree().process_frame
	await get_tree().process_frame
	var title: Control = get_tree().current_scene as Control
	check(title != null and title.scene_file_path == "res://game/ui/main_menu/scenes/main_menu.tscn", "Save returns title")
	if title == null:
		get_tree().quit(1)
		return
	title.settings_path = settings
	title.worlds_root = base + "/worlds"
	title.get_node("%Play").pressed.emit()
	check(title.world_page.selected_slot() == "流程验证", "Remembered slot is selected")
	title.world_page.read_selected()
	world = await _wait_world()
	check(world != null and world.world_directory == expected and world.seed == -12345, "Read reopens the same playable save")
	if world != null:
		world.pause_menu.open_menu()
		await world.save_world(false, true)
	print("WORLD_SELECT_FLOW checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
