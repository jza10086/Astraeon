extends Node
## Exercises the production pause/save/scene lifecycle against an isolated native world.
const WorldScene: PackedScene = preload("res://game/core/main.tscn")
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	get_viewport().push_input(event)
	event.pressed = false
	get_viewport().push_input(event)
	await get_tree().process_frame

func _run() -> void:
	var world: Node3D = WorldScene.instantiate()
	world.world_directory = "res://tmp/pause_world_%s" % Time.get_ticks_usec()
	world.shading_settings_path = world.world_directory + "/settings.cfg"
	world.horizontal_distance = 16
	world.vertical_distance = 16
	preload("res://test/survival/gdscript/world_fixture.gd").prepare(world)
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	var deadline: int = Time.get_ticks_msec() + 60000
	while not world.ready_to_play and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(world.ready_to_play, "World ready")
	var menu: Control = world.pause_menu
	await key(KEY_ESCAPE)
	check(get_tree().paused and menu.opened, "Esc opens and pauses")
	check(not world.controller.input_enabled and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Pause input isolation")
	var position_before: Vector3 = world.player.position
	await key(KEY_W)
	await key(KEY_E)
	await get_tree().create_timer(0.15, true).timeout
	check(world.player.position == position_before and not world.inventory_hud.opened, "No movement or inventory during pause")
	menu.get_node("%Settings").pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check(menu.settings_opened and world.shading._menu.visible and get_tree().paused, "Settings stay paused")
	check(world.shading.panel.category.get_parent().get_parent().get_global_rect().encloses(world.shading.panel.category.get_global_rect()), "Settings category visible")
	await key(KEY_ESCAPE)
	check(menu.opened and not menu.settings_opened, "Esc settings returns to pause")
	check(get_viewport().gui_get_focus_owner() == menu.get_node("%Settings"), "Settings restores focus")
	await key(KEY_ESCAPE)
	check(not get_tree().paused and not menu.opened and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Esc resumes")
	await key(KEY_E)
	check(world.inventory_hud.opened, "Inventory opens")
	await key(KEY_ESCAPE)
	check(not world.inventory_hud.opened and not menu.opened, "Inventory consumes first Esc")
	await key(KEY_F6)
	check(menu.opened and menu.settings_opened and get_tree().paused, "F6 uses pause settings")
	await key(KEY_F6)
	check(menu.opened and not menu.settings_opened, "F6 returns to pause")
	if "--failure" in OS.get_cmdline_user_args():
		world.inventory_store.error = "Injected checkpoint failure"
		await menu.return_to_title()
		check(get_tree().current_scene == world and get_tree().paused and world.failed, "Failed save stops world")
		check(menu.get_node("%Title").disabled and not menu.visible and world.inventory.locked, "Failed save exposes no retry or resume")
		print("PAUSE_MENU_FAILURE_CHECK checks=%d failures=%d" % [checks, failures])
		get_tree().quit(0 if failures == 0 else 1)
		return
	# Check saving without switching first, including the durable inventory checkpoint.
	var saved: bool = await world.save_world(false, true)
	check(saved and not world.saving and not world.inventory.locked, "Paused durable save completes")
	menu.get_node("%Resume").pressed.emit()
	check(not get_tree().paused and world.controller.input_enabled, "Button resumes")
	await key(KEY_ESCAPE)
	menu.get_node("%Title").pressed.emit()
	check(menu.leaving and menu.get_node("%Resume").disabled, "Return locks repeated actions")
	deadline = Time.get_ticks_msec() + 60000
	while (get_tree().current_scene == null or get_tree().current_scene == world) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(get_tree().current_scene.scene_file_path == "res://game/ui/main_menu/scenes/main_menu.tscn", "Save returns title")
	check(not get_tree().paused and get_tree().auto_accept_quit and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Title restores tree and window lifecycle")
	print("PAUSE_MENU_CHECK checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
