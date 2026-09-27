class_name AstraeonInventoryHUD
extends Control
## Creative categories above, search at upper right, storage at lower right.
## Slots and the independent transient mouse stack are owned by InventoryState.
signal open_changed(opened: bool)
var inventory: AstraeonInventoryState
var can_interact: Callable
var opened: bool = false
var page: StringName = &""
var creative_browser: VBoxContainer
var _bag: CenterContainer
var _shade: ColorRect
var _bar: HBoxContainer
var _selected_name: Label
var _cursor_preview: Control
var _storage: VBoxContainer
var _title: Label
var _trash: Button
var _search_tab: Button
var _storage_tab: Button
var _tabs: Dictionary[StringName, Button] = {}
var _slots: Array[AstraeonInventorySlot] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_register_inputs()
	_shade = ColorRect.new()
	_shade.color = Color(0.015, 0.02, 0.03, 0.7)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	_shade.gui_input.connect(_background_input)
	_bag = CenterContainer.new()
	_bag.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bag)
	var shell: VBoxContainer = VBoxContainer.new()
	shell.add_theme_constant_override("separation", 0)
	_bag.add_child(shell)
	var top: HBoxContainer = HBoxContainer.new()
	top.custom_minimum_size.y = 50
	shell.add_child(top)
	var category_scroll: ScrollContainer = ScrollContainer.new()
	category_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	category_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	top.add_child(category_scroll)
	var categories: HBoxContainer = HBoxContainer.new()
	category_scroll.add_child(categories)
	for key: StringName in inventory.catalog.creative_groups:
		_add_tab(categories, key, inventory.catalog.creative_groups[key])
	_search_tab = _add_tab(top, &"search", "搜索")
	var frame: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("b9babc")
	style.border_color = Color("ededec")
	style.set_border_width_all(3)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	frame.add_theme_stylebox_override("panel", style)
	shell.add_child(frame)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	frame.add_child(column)
	var heading: HBoxContainer = HBoxContainer.new()
	column.add_child(heading)
	_title = _label("", 24, Color("202329"))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_title)
	var close: Button = Button.new()
	close.text = "关闭 [E / Esc]"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: set_open(false))
	heading.add_child(close)
	_storage = VBoxContainer.new()
	_storage.custom_minimum_size = Vector2(660, 304)
	column.add_child(_storage)
	_storage.add_child(_label("储物栏", 18, Color("343941")))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	_storage.add_child(grid)
	for index: int in range(10, 40):
		_add_slot(grid, index, true)
	_storage.add_child(_label("左键拿起 / 放下 · 右键拆半 / 放一个\n中键复制一组 · Shift+左键快速转移", 16, Color("343941")))
	creative_browser = preload("res://game/ui/inventory/gdscript/creative_browser.gd").new()
	creative_browser.inventory = inventory
	column.add_child(creative_browser)
	column.add_child(_label("快捷栏 · 1—0", 16, Color("343941")))
	var quick: HBoxContainer = HBoxContainer.new()
	quick.add_theme_constant_override("separation", 4)
	column.add_child(quick)
	for index: int in range(10):
		_add_slot(quick, index, true)
	column.add_child(_label("手上物品不占栏位 · 点击面板外或关闭背包会移除手上物品", 15, Color("343941")))
	var lower: HBoxContainer = HBoxContainer.new()
	lower.custom_minimum_size.y = 50
	shell.add_child(lower)
	_trash = Button.new()
	_trash.text = "移除物品"
	_trash.custom_minimum_size = Vector2(104, 48)
	_trash.focus_mode = Control.FOCUS_NONE
	_trash.tooltip_text = "左键移除手上整组 · 右键移除一个\nShift+左键清空储物栏与快捷栏"
	_trash.gui_input.connect(_trash_input)
	lower.add_child(_trash)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower.add_child(spacer)
	_storage_tab = _add_tab(lower, &"storage", "储物栏")
	var bottom: MarginContainer = MarginContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -116
	bottom.offset_bottom = -18
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	var centered: VBoxContainer = VBoxContainer.new()
	centered.alignment = BoxContainer.ALIGNMENT_END
	centered.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(centered)
	_selected_name = _label("", 20, Color.WHITE)
	_selected_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selected_name.add_theme_color_override("font_shadow_color", Color.BLACK)
	centered.add_child(_selected_name)
	_bar = HBoxContainer.new()
	_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_bar.add_theme_constant_override("separation", 4)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centered.add_child(_bar)
	for index: int in range(10):
		_add_slot(_bar, index, false)
	_cursor_preview = preload("res://game/ui/inventory/gdscript/item_icon.gd").new()
	_cursor_preview.z_index = 100
	add_child(_cursor_preview)
	inventory.changed.connect(_refresh)
	set_page(inventory.catalog.creative_groups.keys()[0] if not inventory.catalog.creative_groups.is_empty() else &"search")
	set_open(false)
	_refresh()

func _label(text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _add_slot(parent: Control, index: int, in_bag: bool) -> void:
	var slot: AstraeonInventorySlot = AstraeonInventorySlot.new()
	slot.index = index
	slot.inventory = inventory
	slot.panel = self
	slot.in_bag = in_bag
	parent.add_child(slot)
	_slots.append(slot)

func _add_tab(parent: Control, key: StringName, title: String) -> Button:
	var button: Button = Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(104, 48)
	button.toggle_mode = true
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color("85878c")
	normal.border_color = Color("dadbdd")
	normal.set_border_width_all(2)
	var active: StyleBoxFlat = normal.duplicate()
	active.bg_color = Color("b9babc")
	active.border_color = Color("ededec")
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color("a5a7ac")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("pressed", active)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("hover_pressed", active)
	button.add_theme_color_override("font_color", Color("202329"))
	button.add_theme_color_override("font_pressed_color", Color("202329"))
	button.add_theme_color_override("font_hover_color", Color("202329"))
	button.add_theme_color_override("font_hover_pressed_color", Color("202329"))
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void: set_page(key))
	parent.add_child(button)
	_tabs[key] = button
	return button

## Tab switching preserves the carried stack. Only the dedicated search page uses query text.
func set_page(key: StringName) -> void:
	if not _tabs.has(key):
		return
	page = key
	for tab: StringName in _tabs:
		_tabs[tab].set_pressed_no_signal(tab == key)
	_storage.visible = key == &"storage"
	_trash.visible = key == &"storage"
	creative_browser.visible = key != &"storage"
	creative_browser.search.release_focus()
	_title.text = "储物栏" if key == &"storage" else ("搜索方块" if key == &"search" else inventory.catalog.creative_groups[key])
	if key != &"storage":
		creative_browser.show_page(&"" if key == &"search" else key, key == &"search")

func _register_inputs() -> void:
	var bindings: Dictionary[StringName, int] = {&"inventory_toggle": KEY_E}
	for index: int in range(10):
		bindings[StringName("hotbar_" + str(index))] = KEY_0 if index == 9 else KEY_1 + index
	for action: StringName in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key: InputEventKey = InputEventKey.new()
			key.physical_keycode = bindings[action]
			InputMap.action_add_event(action, key)
	for direction: int in [-1, 1]:
		var action: StringName = &"hotbar_previous" if direction == -1 else &"hotbar_next"
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var wheel: InputEventMouseButton = InputEventMouseButton.new()
			wheel.button_index = MOUSE_BUTTON_WHEEL_UP if direction == -1 else MOUSE_BUTTON_WHEEL_DOWN
			InputMap.action_add_event(action, wheel)

func _input(event: InputEvent) -> void:
	if opened and InputMap.has_action("shading_settings") and event.is_action_pressed("shading_settings"):
		get_viewport().set_input_as_handled()
		return
	if opened and event is InputEventKey and get_viewport().gui_get_focus_owner() is LineEdit:
		if event.pressed and event.keycode == KEY_ESCAPE:
			set_open(false)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("inventory_toggle") and not event.is_echo():
		if opened or not can_interact.is_valid() or bool(can_interact.call()):
			set_open(not opened)
			get_viewport().set_input_as_handled()
		return
	if opened and event.is_action_pressed("release_mouse"):
		set_open(false)
		get_viewport().set_input_as_handled()
		return
	if inventory.locked or (can_interact.is_valid() and not bool(can_interact.call())):
		return
	for index: int in range(10):
		if event.is_action_pressed(StringName("hotbar_" + str(index))) and not event.is_echo():
			inventory.select(index)
			get_viewport().set_input_as_handled()
			return
	var direction: int = -1 if event.is_action_pressed("hotbar_previous") else (1 if event.is_action_pressed("hotbar_next") else 0)
	if direction != 0 and not opened:
		inventory.select(posmod(inventory.selected + direction, 10))
		get_viewport().set_input_as_handled()

func set_open(value: bool) -> void:
	if not value:
		creative_browser.search.release_focus()
		inventory.discard_cursor()
	opened = value
	_shade.visible = value
	_bag.visible = value
	_bar.visible = not value
	_selected_name.visible = not value
	_refresh()
	open_changed.emit(value)

func _refresh() -> void:
	var stack: AstraeonItemStack = inventory.stack_at(inventory.selected)
	_selected_name.text = (stack.item.display_name if stack != null else "空槽") + "   ·   E 物品栏"
	_cursor_preview.stack = inventory.cursor_stack()
	_cursor_preview.visible = opened and _cursor_preview.stack != null
	_cursor_preview.queue_redraw()
	set_process(_cursor_preview.visible)
	if _cursor_preview.visible:
		_process(0.0)

func slot_clicked(index: int, button: MouseButton, quick: bool = false) -> void:
	if inventory.locked:
		return
	if not opened:
		inventory.select(index)
	elif button == MOUSE_BUTTON_MIDDLE:
		inventory.clone_to_cursor(index)
	elif button == MOUSE_BUTTON_LEFT and quick:
		inventory.quick_move(index)
	elif button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		inventory.click_slot(index, button == MOUSE_BUTTON_RIGHT)

func _process(_delta: float) -> void:
	_cursor_preview.position = get_local_mouse_position() - Vector2(30, 30)

func _background_input(event: InputEvent) -> void:
	if opened and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		inventory.discard_cursor(event.button_index == MOUSE_BUTTON_RIGHT)
		accept_event()

func _trash_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		if event.button_index == MOUSE_BUTTON_LEFT and event.shift_pressed:
			inventory.clear_inventory()
		else:
			inventory.discard_cursor(event.button_index == MOUSE_BUTTON_RIGHT)
		_trash.accept_event()
