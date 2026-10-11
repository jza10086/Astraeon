extends Node
## Independent windows verify canvas scaling, bounded settings and focus restoration.
const Menu: PackedScene = preload("res://game/ui/main_menu/scenes/main_menu.tscn")
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var sizes: Array[Vector2i] = [Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(3840,2160), Vector2i(3440,1440), Vector2i(1024,576), Vector2i(640,360)]
	for dimensions: Vector2i in sizes:
		var window: Window = Window.new()
		window.size = dimensions
		window.content_scale_size = Vector2i(1920,1080)
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		get_tree().root.add_child(window)
		var menu: Control = Menu.instantiate()
		menu.settings_path = "res://tmp/main_menu_check_%s.cfg" % Time.get_ticks_usec()
		window.add_child(menu)
		await get_tree().process_frame
		await get_tree().process_frame
		var bounds: Rect2 = Rect2(Vector2.ZERO, menu.size)
		var play: Button = menu.get_node("%Play")
		_check(window.size == dimensions, "Window dimensions differ: %s" % dimensions)
		_check(bounds.encloses(play.get_global_rect()), "Play clipped: %s" % dimensions)
		_check(bounds.encloses(menu.get_node("Home/Footer").get_global_rect()), "Footer clipped: %s" % dimensions)
		_check(menu.get_node("%Multiplayer").disabled, "Multiplayer must remain unavailable")
		_check(is_equal_approx(play.size.x / play.size.y, 600.0 / 72.0), "Primary button proportions")
		menu.get_node("%Settings").pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(not menu.home.visible and menu.settings_page.visible, "Settings navigation")
		_check(bounds.encloses(menu.settings_page.get_global_rect()), "Settings clipped: %s" % dimensions)
		_check(bounds.encloses(menu.get_node("%Apply").get_global_rect()), "Settings actions clipped")
		_check(menu.get_node("%SettingsScroll").size.y > 100.0, "Settings scroll area usable")
		var original: float = menu.draft.hour
		menu.draft.hour = 3.0
		menu.get_node("%Back").pressed.emit()
		_check(not FileAccess.file_exists(menu.settings_path), "Cancel must not write")
		_check(window.gui_get_focus_owner() == menu.settings_button, "Restore settings focus")
		menu.get_node("%Settings").pressed.emit()
		_check(menu.draft.hour == original, "Discard settings draft")
		menu.draft.hour = 7.0
		menu.get_node("%Apply").pressed.emit()
		var loaded: Profile = Profile.new()
		_check(loaded.load_settings(menu.settings_path) == OK and loaded.hour == 7.0, "Save and reload current config")
		_check(menu.home.visible and not menu.settings_page.visible, "Save returns home")
		menu.get_node("%Quit").pressed.emit()
		await get_tree().process_frame
		_check(menu.quit_dialog.visible, "Exit confirmation")
		_check(menu.quit_dialog.get_cancel_button().has_focus(), "Exit defaults to cancel")
		menu.quit_dialog.hide()
		var config: ConfigFile = ConfigFile.new()
		config.set_value("shading", "format", "unsupported")
		config.save(menu.settings_path)
		menu.get_node("%Settings").pressed.emit()
		_check(menu.get_node("%Apply").disabled, "Unsupported config must not be overwritten")
		print("MAIN_MENU_SIZE ", dimensions, " logical=", menu.size)
		window.queue_free()
		await get_tree().process_frame
	print("MAIN_MENU_CHECK checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

