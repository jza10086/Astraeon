extends PanelContainer
## Main-menu-only selection and isolated 3D preview; never touches a live player.
signal closed(selected: bool)
const Models: Script = preload("res://game/entities/common/gdscript/character_models.gd")
var settings_path: String = "user://settings.cfg"
var selected_id: StringName = &""
var current_id: StringName = &""
var selection_changed: bool = false
var model_buttons: Dictionary[StringName, Button] = {}
var current_labels: Dictionary[StringName, Label] = {}
var folder_button: Button
var delete_button: Button
var preview_model: Node3D
var viewport: SubViewport
var preview_root: Node3D
var list: VBoxContainer
var scroll: ScrollContainer
var use_button: Button
var message: Label
var heading: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 64
	offset_top = 64
	offset_right = -64
	offset_bottom = -64
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	margin.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 28)
	column.add_child(header)
	heading = Label.new()
	heading.text = "选择人物"
	heading.custom_minimum_size.x = 340
	heading.add_theme_font_size_override("font_size", 30)
	heading.clip_text = true
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(heading)
	folder_button = Button.new()
	folder_button.text = "打开文件所在位置"
	folder_button.custom_minimum_size.y = 64
	folder_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folder_button.pressed.connect(open_folder)
	header.add_child(folder_button)
	delete_button = Button.new()
	delete_button.text = "删除"
	delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_button.pressed.connect(delete_selected)
	delete_button.tooltip_text = "从人物列表删除，保留模型文件；至少保留一个人物。"
	header.add_child(delete_button)
	var content: HBoxContainer = HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 28)
	column.add_child(content)
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size.x = 340
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	content.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var display: SubViewportContainer = SubViewportContainer.new()
	display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	display.stretch = true
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(display)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	display.add_child(viewport)
	preview_root = Node3D.new()
	viewport.add_child(preview_root)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.15, 0.18)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.85, 1.0)
	environment.environment.ambient_light_energy = 0.7
	preview_root.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -35, 0)
	light.light_energy = 1.4
	preview_root.add_child(light)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.45
	camera.position = Vector3(2.2, 1.4, 4.8)
	preview_root.add_child(camera)
	camera.look_at(Vector3(0, 0.95, 0))
	camera.current = true
	message = Label.new()
	message.hide()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)
	var actions: HBoxContainer = HBoxContainer.new()
	column.add_child(actions)
	var back: Button = Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(200, 64)
	back.pressed.connect(cancel)
	actions.add_child(back)
	use_button = Button.new()
	use_button.text = "使用此人物"
	use_button.toggle_mode = true
	use_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	use_button.pressed.connect(confirm)
	actions.add_child(use_button)

func open(path: String) -> void:
	settings_path = path
	selection_changed = false
	selected_id = &""
	heading.text = "选择人物"
	show()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	message.hide()
	var id: StringName = Models.load_id(path)
	current_id = id
	_build_list()
	if id.is_empty():
		_error("人物设置无法读取，请重新选择；无法读取的设置文件不会被覆盖。")
		use_button.set_pressed_no_signal(false)
		use_button.text = "使用此人物"
		use_button.disabled = true
		folder_button.disabled = true
		delete_button.disabled = true
	else:
		preview(id)
	scroll.scroll_vertical = 0
	if model_buttons.has(id):
		model_buttons[id].grab_focus()
	elif not model_buttons.is_empty():
		model_buttons.values()[0].grab_focus()

func preview(id: StringName) -> void:
	var model: Node3D = Models.instantiate(id)
	if model == null:
		_error("人物载入失败，请重新选择。")
		use_button.disabled = true
		return
	if preview_model != null:
		preview_root.remove_child(preview_model)
		preview_model.queue_free()
	preview_model = model
	preview_root.add_child(model)
	selected_id = id
	var animation: AnimationPlayer = model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if animation != null:
		animation.play("Idle")
	heading.text = "选择人物 · " + String(Models.definition(id).name)
	message.hide()
	_sync_selection()

func _build_list() -> void:
	for child: Node in list.get_children():
		list.remove_child(child)
		child.queue_free()
	model_buttons.clear()
	current_labels.clear()
	for entry: Dictionary in Models.available(settings_path):
		var id: StringName = entry.id
		var button: Button = Button.new()
		button.text = entry.name
		button.custom_minimum_size = Vector2(0, 104)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.pressed.connect(preview.bind(id))
		list.add_child(button)
		model_buttons[id] = button
		var badge: Label = Label.new()
		badge.text = "当前使用"
		badge.visible = id == current_id
		badge.add_theme_font_size_override("font_size", 18)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		button.add_child(badge)
		badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.offset_left = -120
		badge.offset_right = -16
		badge.offset_top = -32
		badge.offset_bottom = -8
		current_labels[id] = badge

func _sync_selection() -> void:
	for id: StringName in model_buttons:
		model_buttons[id].set_pressed_no_signal(id == selected_id)
		current_labels[id].visible = id == current_id
	var active: bool = selected_id == current_id
	use_button.text = "当前使用" if active else "使用此人物"
	use_button.set_pressed_no_signal(active)
	use_button.disabled = false
	delete_button.disabled = model_buttons.size() <= 1 or current_id.is_empty()
	var location: String = model_folder()
	folder_button.disabled = location.is_empty() or not DirAccess.dir_exists_absolute(location)
	folder_button.tooltip_text = location

func model_folder() -> String:
	var entry: Dictionary = Models.definition(selected_id)
	return ProjectSettings.globalize_path(String(entry.path).get_base_dir()) if not entry.is_empty() else ""

func open_folder() -> void:
	var location: String = model_folder()
	if location.is_empty() or not DirAccess.dir_exists_absolute(location):
		_error("找不到人物文件夹。")
		return
	var error: Error = OS.shell_open(location)
	if error != OK:
		_error("无法打开人物文件夹：" + error_string(error))

func _error(text: String) -> void:
	message.text = text
	message.show()

func confirm() -> void:
	if selected_id == current_id:
		_sync_selection()
		return
	var error: Error = Models.save_id(selected_id, settings_path)
	if error != OK:
		_error("保存失败：" + error_string(error))
		_sync_selection()
		return
	current_id = selected_id
	selection_changed = true
	message.hide()
	_sync_selection()

func delete_selected() -> void:
	var error: Error = Models.remove_id(selected_id, settings_path)
	if error != OK:
		_error("删除失败：" + error_string(error))
		return
	current_id = Models.load_id(settings_path)
	selection_changed = true
	_build_list()
	preview(current_id)
	model_buttons[current_id].grab_focus()

func cancel() -> void:
	_close(false)

func _close(selected: bool) -> void:
	hide()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if preview_model != null:
		preview_root.remove_child(preview_model)
		preview_model.queue_free()
		preview_model = null
	closed.emit(selected or selection_changed)
