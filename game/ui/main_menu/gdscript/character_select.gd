extends PanelContainer
## Main-menu-only selection and isolated 3D preview; never touches a live player.
signal closed(selected: bool)
const Models: Script = preload("res://game/entities/common/gdscript/character_models.gd")
var settings_path: String = "user://settings.cfg"
var selected_id: StringName = &""
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
	heading = Label.new()
	heading.text = "选择人物"
	heading.add_theme_font_size_override("font_size", 36)
	column.add_child(heading)
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
	for entry: Dictionary in Models.MODELS:
		var row: VBoxContainer = VBoxContainer.new()
		row.custom_minimum_size.y = 112
		list.add_child(row)
		var label: Label = Label.new()
		label.text = entry.name
		row.add_child(label)
		var button: Button = Button.new()
		button.text = "预览"
		button.custom_minimum_size.y = 56
		button.pressed.connect(preview.bind(entry.id))
		row.add_child(button)
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
	use_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	use_button.pressed.connect(confirm)
	actions.add_child(use_button)

func open(path: String) -> void:
	settings_path = path
	show()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var id: StringName = Models.load_id(path)
	if id.is_empty():
		message.text = "人物设置无法读取，请重新选择；无法读取的设置文件不会被覆盖。"
		use_button.disabled = true
	else:
		preview(id)
	scroll.scroll_vertical = 0
	(list.get_child(0).get_child(1) as Button).grab_focus()

func preview(id: StringName) -> void:
	var model: Node3D = Models.instantiate(id)
	if model == null:
		message.text = "人物载入失败，请重新选择。"
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
	message.text = "当前使用：" + String(Models.definition(Models.load_id(settings_path)).get("name", "未选择")) + "。点击「使用此人物」保存；进入世界后不能切换。"
	use_button.disabled = false

func confirm() -> void:
	var error: Error = Models.save_id(selected_id, settings_path)
	if error != OK:
		message.text = "保存失败：" + error_string(error)
		return
	_close(true)

func cancel() -> void:
	_close(false)

func _close(selected: bool) -> void:
	hide()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if preview_model != null:
		preview_root.remove_child(preview_model)
		preview_model.queue_free()
		preview_model = null
	closed.emit(selected)
