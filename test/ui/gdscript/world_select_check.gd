extends Node
const Slots: Script = preload("res://game/core/gdscript/world_selection.gd")
const Page: Script = preload("res://game/ui/main_menu/gdscript/world_select.gd")
var checks: int = 0
var failures: int = 0
var requested: String = ""
var back_count: int = 0

func _ready() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _run() -> void:
	var root: String = "res://tmp/world_select_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(root)
	var settings: String = root + "/settings.cfg"
	var config: ConfigFile = ConfigFile.new()
	config.set_value("other", "preserved", 42)
	config.save(settings)
	var worlds: String = root + "/worlds"
	var page: Page = Page.new()
	add_child(page)
	page.start_requested.connect(func(directory: String) -> void: requested = directory)
	page.back_requested.connect(func() -> void: back_count += 1)
	page.open(settings, worlds)
	await get_tree().process_frame
	check(page.slots.is_empty() and page.read_button.disabled and page.delete_button.disabled, "Empty state")
	page._show_create()
	page.name_input.text = "我的世界"
	check(page.mode_select.get_selected_id() == 0, "Create defaults to survival")
	page.mode_select.select(1)
	page.create_world()
	check(requested == worlds + "/我的世界" and page.busy, "Create emits isolated world")
	config.load(settings)
	check(config.get_value("other", "preserved") == 42, "Preserve settings")
	check(Slots.selected(worlds + "/unused", settings).directory == requested, "Selection survives reload")
	check(Slots.parameters(requested).initial_mode == 1, "Create UI persists creative choice")
	var chosen: String = requested
	page.set_busy(false)
	page.open(settings, worlds)
	check(page.selected_slot() == "我的世界", "List detects created world")
	check(Slots.create_new(chosen, settings, "我的世界").has("error"), "Reject duplicate")
	for invalid: String in ["../escape", "a/b", "a\\b", "CON", ".", "a.", " trailing "]:
		check(Slots.create_new(chosen, settings, invalid).has("error"), "Reject invalid name: " + invalid)
	check(Slots.create_new(chosen, settings, "第二个世界").has("directory"), "Second isolated slot")
	page.refresh("我的世界")
	requested = ""
	page.read_selected()
	check(requested == chosen and page.busy, "Read selected existing slot")
	page.set_busy(false)
	page._ask_delete()
	check(page.delete_dialog.visible and page.delete_dialog.get_cancel_button().has_focus(), "Deletion defaults to keep")
	page.cancel()
	check(DirAccess.dir_exists_absolute(chosen), "Cancel preserves world")
	DirAccess.make_dir_recursive_absolute(chosen + "/nested")
	var file: FileAccess = FileAccess.open(chosen + "/nested/sentinel.txt", FileAccess.WRITE)
	file.store_string("fixture")
	file.close()
	page._ask_delete()
	page.delete_dialog.hide()
	page._delete_confirmed()
	check(not DirAccess.dir_exists_absolute(chosen), "Delete removes only selected subtree")
	check(DirAccess.dir_exists_absolute(worlds + "/第二个世界"), "Sibling preserved")
	config.clear()
	config.load(settings)
	check(not config.has_section("world") and config.get_value("other", "preserved") == 42, "Delete clears selection, preserves unrelated settings")
	check(Slots.delete_world(worlds, "../escape", settings).has("error"), "Refuse traversal deletion")
	page.cancel()
	check(back_count == 1 and not page.visible, "Back title")
	page.open(settings, worlds)
	page._show_create()
	page.cancel()
	check(page.list_page.visible and not page.create_page.visible and back_count == 1, "Create cancel returns list")
	config.set_value("world", "format", 999)
	config.save(settings)
	check(Slots.choose(worlds, "第二个世界", settings).has("error"), "Reject unsupported selection format")
	check(Slots.delete_world(worlds, "第二个世界", settings).has("error") and DirAccess.dir_exists_absolute(worlds + "/第二个世界"), "Unreadable config blocks destructive action")
	print("WORLD_SELECT_CHECK checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
