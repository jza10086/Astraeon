extends Control
## Scene-local pause ownership. Saving continues through frame signals while gameplay is paused.
@export var world: Node
@export_file("*.tscn") var title_scene_path: String = "res://game/ui/main_menu/scenes/main_menu.tscn"
@onready var menu: VBoxContainer = %Menu
@onready var status: Label = %Status
var mode_select: OptionButton
var opened: bool = false
var settings_opened: bool = false
var leaving: bool = false
var _previous_input_enabled: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	%Resume.pressed.connect(resume_game)
	%Settings.pressed.connect(open_settings)
	%Title.pressed.connect(return_to_title)
	mode_select = OptionButton.new()
	mode_select.name = "GameMode"
	mode_select.add_item("模式：生存", AstraeonPlayerState.Mode.SURVIVAL)
	mode_select.add_item("模式：创造", AstraeonPlayerState.Mode.CREATIVE)
	mode_select.custom_minimum_size.y = 64
	menu.add_child(mode_select)
	menu.move_child(mode_select, 1)
	mode_select.item_selected.connect(_mode_selected)

func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("ui_cancel"):
		# Inventory owns its own Esc close; do not open a second modal on that event.
		if not opened and world.inventory_hud != null and world.inventory_hud.opened:
			return
		get_viewport().set_input_as_handled()
		if leaving:
			return
		if settings_opened:
			close_settings()
		elif opened:
			resume_game()
		else:
			open_menu()
	elif opened and InputMap.has_action("shading_settings") and event.is_action_pressed("shading_settings"):
		get_viewport().set_input_as_handled()
		if leaving:
			return
		if settings_opened:
			close_settings()
		else:
			open_settings()

func open_menu() -> void:
	if opened or get_tree().paused:
		return
	opened = true
	_previous_input_enabled = bool(world.controller.get("input_enabled"))
	world.controller.set("input_enabled", false)
	world.player.move_intent = Vector3.ZERO
	world.player.jump_requested = false
	world.player.sprint_requested = false
	world.player.slow_walk_requested = false
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()
	menu.show()
	%Settings.disabled = world.shading == null or not world.shading.is_ready()
	status.text = ""
	mode_select.disabled = world.player_state == null or not world.ready_to_play or world.saving or world.failed
	if world.player_state != null:
		mode_select.select(int(world.player_state.mode))
	%Resume.grab_focus()

func resume_game() -> void:
	if leaving or not opened:
		return
	if settings_opened:
		world.shading.set_settings_visible(false)
	settings_opened = false
	opened = false
	hide()
	world.controller.set("input_enabled", _previous_input_enabled)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func open_settings() -> void:
	if leaving or world.shading == null or not world.shading.is_ready():
		return
	if not opened:
		open_menu()
	if not opened:
		return
	settings_opened = true
	menu.hide()
	world.shading.set_settings_visible(true)

func close_settings() -> void:
	world.shading.set_settings_visible(false)
	settings_opened = false
	menu.show()
	%Settings.grab_focus()

func return_to_title() -> void:
	if leaving:
		return
	leaving = true
	_set_buttons_disabled(true)
	status.text = "正在保存世界…"
	var success: bool = await world.save_world(false, true)
	if not success:
		world.fail_stop("保存失败，已停止世界，未返回标题。")
		return
	var error: Error = get_tree().change_scene_to_file(title_scene_path)
	if error != OK:
		status.text = "无法返回标题：%s" % error_string(error)
		leaving = false
		_set_buttons_disabled(false)

func _set_buttons_disabled(value: bool) -> void:
	mode_select.disabled = value
	%Resume.disabled = value
	%Settings.disabled = value or world.shading == null or not world.shading.is_ready()
	%Title.disabled = value

func _exit_tree() -> void:
	if opened:
		get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _mode_selected(index: int) -> void:
	mode_select.disabled = true
	if not world.set_game_mode(mode_select.get_item_id(index)):
		status.text = "模式切换失败：" + world.inventory_store.error
	else:
		status.text = "已切换为" + ("创造模式" if world.player_state.is_creative() else "生存模式")
	mode_select.select(int(world.player_state.mode))
	mode_select.disabled = leaving or world.saving or world.failed
