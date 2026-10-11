extends Control
## World-slot navigation only; core owns filesystem operations and the parent loads the scene.
signal start_requested(directory: String)
signal back_requested()
const Slots: Script = preload("res://game/core/gdscript/world_selection.gd")
var settings_path: String
var worlds_root: String
var list: ItemList
var status: Label
var list_page: VBoxContainer
var create_page: VBoxContainer
var name_input: LineEdit
var seed_input: LineEdit
var mode_select: OptionButton
var read_button: Button
var create_button: Button
var delete_button: Button
var back_button: Button
var confirm_create: Button
var delete_dialog: ConfirmationDialog
var slots: PackedStringArray = []
var busy: bool = false
var _delete_slot: String = ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = preload("res://game/ui/resources/menu_theme.tres")
	var panel: PanelContainer = PanelContainer.new()
	add_child(panel)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.08
	panel.anchor_bottom = 0.92
	panel.offset_left = -600
	panel.offset_right = 600
	var surface: StyleBoxFlat = StyleBoxFlat.new()
	surface.bg_color = Color(0.09, 0.105, 0.115)
	surface.content_margin_left = 32
	surface.content_margin_right = 32
	surface.content_margin_top = 28
	surface.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", surface)
	var column: VBoxContainer = VBoxContainer.new()
	panel.add_child(column)
	var heading: Label = Label.new()
	heading.text = "选择存档"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 40)
	column.add_child(heading)
	list_page = VBoxContainer.new()
	list_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(list_page)
	list = ItemList.new()
	list.name = "WorldList"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size.y = 180
	list.add_theme_constant_override("v_separation", 20)
	list.add_theme_constant_override("inner_item_margin_top", 20)
	list.add_theme_constant_override("inner_item_margin_bottom", 20)
	list.item_selected.connect(func(_index: int) -> void: _selection_changed())
	list.item_activated.connect(func(_index: int) -> void: read_selected())
	list_page.add_child(list)
	var first: HBoxContainer = HBoxContainer.new()
	list_page.add_child(first)
	read_button = _button(first, "读取存档", read_selected)
	create_button = _button(first, "创建新存档", _show_create)
	var second: HBoxContainer = HBoxContainer.new()
	list_page.add_child(second)
	delete_button = _button(second, "删除存档", _ask_delete)
	back_button = _button(second, "返回标题界面", cancel)
	create_page = VBoxContainer.new()
	create_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(create_page)
	var instructions: Label = Label.new()
	instructions.text = "创建新存档\n\n存档名称"
	instructions.add_theme_font_size_override("font_size", 28)
	create_page.add_child(instructions)
	name_input = LineEdit.new()
	name_input.name = "WorldName"
	name_input.max_length = 64
	name_input.placeholder_text = "例如：我的世界"
	name_input.custom_minimum_size.y = 64
	name_input.text_changed.connect(func(_value: String) -> void: _update_create_validity())
	name_input.text_submitted.connect(func(_value: String) -> void: create_world())
	create_page.add_child(name_input)
	var seed_label: Label = Label.new()
	seed_label.text = "世界种子"
	create_page.add_child(seed_label)
	seed_input = LineEdit.new()
	seed_input.name = "WorldSeed"
	seed_input.placeholder_text = "留空随机；整数范围 -2147483648 ～ 2147483647"
	seed_input.custom_minimum_size.y = 64
	seed_input.text_changed.connect(func(_value: String) -> void: _update_create_validity())
	seed_input.text_submitted.connect(func(_value: String) -> void: create_world())
	create_page.add_child(seed_input)
	mode_select = OptionButton.new()
	mode_select.name = "GameMode"
	mode_select.add_item("生存模式", AstraeonPlayerState.Mode.SURVIVAL)
	mode_select.add_item("创造模式", AstraeonPlayerState.Mode.CREATIVE)
	mode_select.custom_minimum_size.y = 56
	create_page.add_child(mode_select)
	var note: Label = Label.new()
	note.text = "每个存档独立保存地形和背包。\n相同种子与生成设置会生成相同地形；使用当前人物和内容包。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	create_page.add_child(note)
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	create_page.add_child(spacer)
	confirm_create = _button(create_page, "创建并进入", create_world)
	_button(create_page, "返回存档列表", cancel)
	status = Label.new()
	status.custom_minimum_size.y = 36
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 20)
	column.add_child(status)
	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = "删除存档"
	delete_dialog.ok_button_text = "确认删除"
	delete_dialog.cancel_button_text = "保留存档"
	delete_dialog.confirmed.connect(_delete_confirmed)
	delete_dialog.canceled.connect(func() -> void: delete_button.grab_focus())
	add_child(delete_dialog)
	create_page.hide()
	hide()

func _button(parent: Control, caption: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = caption
	button.custom_minimum_size.y = 64
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	button.pressed.connect(callback)
	return button

func open(path: String, root: String) -> void:
	settings_path = path
	worlds_root = root
	show()
	create_page.hide()
	list_page.show()
	set_busy(false)
	var current: Dictionary = Slots.selected(worlds_root.path_join("unused"), settings_path)
	refresh(String(current.get("directory", "")).get_file())
	if slots.is_empty():
		create_button.grab_focus()
	else:
		list.grab_focus()

func refresh(preferred: String = "") -> void:
	list.clear()
	slots.clear()
	var result: Dictionary = Slots.list_worlds(worlds_root)
	if result.has("error"):
		status.text = result.error
	else:
		slots = result.slots
		for slot: String in slots:
			list.add_item(slot)
		status.text = "还没有存档，点击「创建新存档」开始。" if slots.is_empty() else "选择存档后读取，或双击进入。"
		if not slots.is_empty():
			var index: int = slots.find(preferred)
			list.select(maxi(index, 0))
	_selection_changed()

func _selection_changed() -> void:
	var selected: bool = not list.get_selected_items().is_empty()
	read_button.disabled = busy or not selected
	delete_button.disabled = busy or not selected

func selected_slot() -> String:
	var indices: PackedInt32Array = list.get_selected_items()
	return slots[indices[0]] if not indices.is_empty() and indices[0] < slots.size() else ""

func read_selected() -> void:
	if busy or selected_slot().is_empty():
		return
	var result: Dictionary = Slots.choose(worlds_root, selected_slot(), settings_path)
	if result.has("error"):
		status.text = result.error
		return
	set_busy(true)
	start_requested.emit(result.directory)

func _show_create() -> void:
	list_page.hide()
	create_page.show()
	name_input.text = ""
	seed_input.text = ""
	mode_select.select(0)
	confirm_create.disabled = true
	status.text = "名称不能重复，不能包含路径符号或系统保留名称。"
	name_input.grab_focus()

func _update_create_validity() -> void:
	confirm_create.disabled = not Slots.valid_slot(name_input.text) or not Slots.valid_seed_text(seed_input.text)
	if not Slots.valid_seed_text(seed_input.text):
		status.text = "种子必须是 -2147483648 到 2147483647 之间的整数，或留空随机。"
	else:
		status.text = "名称不能重复；种子留空时会随机生成并保存在该存档中。"

func create_world() -> void:
	if busy or not Slots.valid_slot(name_input.text) or not Slots.valid_seed_text(seed_input.text):
		return
	var seed: int = randi_range(-2147483648, 2147483647) if seed_input.text.strip_edges().is_empty() else seed_input.text.strip_edges().to_int()
	var result: Dictionary = Slots.create_new(worlds_root.path_join("unused"), settings_path, name_input.text, seed, 0, mode_select.get_selected_id())
	if result.has("error"):
		status.text = result.error
		return
	create_page.hide()
	list_page.show()
	refresh(String(result.directory).get_file())
	set_busy(true)
	start_requested.emit(result.directory)

func _ask_delete() -> void:
	if busy or selected_slot().is_empty():
		return
	_delete_slot = selected_slot()
	delete_dialog.dialog_text = "确定删除「%s」？\n此存档的地形和背包将永久删除，无法撤销。" % _delete_slot
	delete_dialog.popup_centered(Vector2i(720, 240))
	delete_dialog.get_cancel_button().grab_focus()

func _delete_confirmed() -> void:
	var result: Dictionary = Slots.delete_world(worlds_root, _delete_slot, settings_path)
	_delete_slot = ""
	refresh()
	status.text = result.error if result.has("error") else "存档已删除"
	create_button.grab_focus() if slots.is_empty() else list.grab_focus()

func set_busy(value: bool) -> void:
	busy = value
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE if value else Control.MOUSE_FILTER_STOP
	list.focus_mode = Control.FOCUS_NONE if value else Control.FOCUS_ALL
	create_button.disabled = value
	back_button.disabled = value
	_selection_changed()
	if value:
		status.text = "正在读取存档…"

func cancel() -> void:
	if busy:
		return
	if delete_dialog.visible:
		delete_dialog.hide()
		delete_button.grab_focus()
	elif create_page.visible:
		create_page.hide()
		list_page.show()
		refresh()
		create_button.grab_focus()
	else:
		hide()
		back_requested.emit()
