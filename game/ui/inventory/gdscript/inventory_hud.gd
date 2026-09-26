class_name AstraeonInventoryHUD
extends Control
## Ten-slot hotbar and a 10x3 storage grid. Both views reference the same inventory.
signal open_changed(opened: bool)
var inventory: AstraeonInventoryState
var can_interact: Callable
var source_slot: int = -1
var source_count: int = 0
var source_revision: int = -1
var opened: bool = false
var _bag: CenterContainer
var _shade: ColorRect
var _bar: HBoxContainer
var _selected_name: Label
var _instructions: Label
var _cursor_preview: Label
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
	_bag.add_child(frame)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	frame.add_child(column)
	var heading: HBoxContainer = HBoxContainer.new()
	column.add_child(heading)
	var title: Label = _label("物品栏", 24, Color("202329"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close: Button = Button.new()
	close.text = "关闭  [E / Esc]"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: set_open(false))
	heading.add_child(close)
	column.add_child(_label("储物栏", 16, Color("343941")))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	column.add_child(grid)
	for index: int in range(10, 40):
		_add_slot(grid, index, true)
	column.add_child(_label("快捷栏 · 1—0", 16, Color("343941")))
	var quick: HBoxContainer = HBoxContainer.new()
	quick.add_theme_constant_override("separation", 4)
	column.add_child(quick)
	for index: int in range(10):
		_add_slot(quick, index, true)
	_instructions = _label("左键移动 / 合并 · 右键拆半 / 放一个 · Shift+左键快速转移", 15, Color("343941"))
	column.add_child(_instructions)
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
	_selected_name.add_theme_constant_override("shadow_offset_x", 2)
	_selected_name.add_theme_constant_override("shadow_offset_y", 2)
	centered.add_child(_selected_name)
	_bar = HBoxContainer.new()
	_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_bar.add_theme_constant_override("separation", 4)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centered.add_child(_bar)
	for index: int in range(10):
		_add_slot(_bar, index, false)
	_cursor_preview = _label("", 20, Color.WHITE)
	_cursor_preview.add_theme_color_override("font_shadow_color", Color.BLACK)
	_cursor_preview.add_theme_constant_override("shadow_offset_x", 2)
	_cursor_preview.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_cursor_preview)
	inventory.changed.connect(_refresh)
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
	opened = value
	_shade.visible = value
	_bag.visible = value
	_bar.visible = not value
	_selected_name.visible = not value
	cancel_source()
	open_changed.emit(value)

func _refresh() -> void:
	var stack: AstraeonItemStack = inventory.stack_at(inventory.selected)
	_selected_name.text = (stack.item.display_name if stack != null else "空槽") + "   ·   E 物品栏"
	if source_slot >= 0 and source_revision != inventory.revision:
		cancel_source()

func cancel_source() -> void:
	source_slot = -1
	source_count = 0
	if _cursor_preview != null:
		_cursor_preview.hide()
	set_process(false)
	for slot: AstraeonInventorySlot in _slots:
		slot.queue_redraw()

func slot_clicked(index: int, right: bool, quick: bool) -> void:
	if inventory.locked:
		return
	if not opened:
		inventory.select(index)
		return
	if quick:
		inventory.quick_move(index)
		cancel_source()
		return
	if source_slot < 0:
		var stack: AstraeonItemStack = inventory.stack_at(index)
		if stack == null:
			return
		source_slot = index
		source_count = ceili(stack.count / 2.0) if right else stack.count
		source_revision = inventory.revision
	elif source_slot == index:
		cancel_source()
	else:
		var old_source: int = source_slot
		var old_count: int = source_count
		var old_stack: AstraeonItemStack = inventory.stack_at(old_source)
		var moved: bool = inventory.move(old_source, index, 1 if right else old_count, source_revision)
		cancel_source()
		var remaining: AstraeonItemStack = inventory.stack_at(old_source)
		if moved and remaining != null and remaining.item.key == old_stack.item.key:
			var carried: int = old_count - (old_stack.count - remaining.count)
			if carried > 0:
				source_slot = old_source
				source_count = mini(carried, remaining.count)
				source_revision = inventory.revision
	if source_slot >= 0:
		_cursor_preview.text = inventory.stack_at(source_slot).item.display_name + " × " + str(source_count)
		_cursor_preview.show()
		set_process(true)
		_process(0.0)
	for slot: AstraeonInventorySlot in _slots:
		slot.queue_redraw()

func _process(_delta: float) -> void:
	if _cursor_preview != null:
		_cursor_preview.position = get_local_mouse_position() + Vector2(18, 18)

func _background_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		cancel_source()
		accept_event()
