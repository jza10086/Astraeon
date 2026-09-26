extends VBoxContainer
## Creative block browser: grants a stack through the inventory transaction guard.
## This panel does not change world rules or provide flight/unlimited placement.
var inventory: AstraeonInventoryState
var search: LineEdit
var group: StringName = &""
var results: Array[AstraeonItemDefinition] = []
var _grid: GridContainer
var _status: Label
var _groups: Array[Button] = []

func _ready() -> void:
	custom_minimum_size = Vector2(636, 270)
	var tabs: HBoxContainer = HBoxContainer.new()
	add_child(tabs)
	_add_group(tabs, &"", "全部")
	for key: StringName in inventory.catalog.creative_groups:
		_add_group(tabs, key, inventory.catalog.creative_groups[key])
	search = LineEdit.new()
	search.placeholder_text = "搜索名称、ID、标签（空格分隔多个关键词）"
	search.clear_button_enabled = true
	search.text_changed.connect(func(_text: String) -> void: refresh())
	add_child(search)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(636, 180)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("eeeeee"))
	add_child(_status)
	refresh()

func _add_group(parent: Control, key: StringName, title: String) -> void:
	var button: Button = Button.new()
	button.text = title
	button.toggle_mode = true
	button.button_pressed = key == group
	button.set_meta("group", key)
	button.pressed.connect(func() -> void: select_group(key))
	parent.add_child(button)
	_groups.append(button)

func select_group(key: StringName) -> void:
	group = key
	for button: Button in _groups:
		button.set_pressed_no_signal(button.get_meta("group") == key)
	refresh()

func refresh() -> void:
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	results = inventory.catalog.find_blocks(group, search.text)
	for item: AstraeonItemDefinition in results:
		var button: Button = Button.new()
		button.text = item.display_name + "\n× " + str(item.max_stack)
		button.custom_minimum_size = Vector2(120, 72)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = String(item.key) + "\n" + " · ".join(item.search_tags)
		if item.icon != null:
			button.icon = item.icon
		button.pressed.connect(func() -> void: grant(item.key))
		_grid.add_child(button)
	_status.text = ("没有匹配的方块" if results.is_empty() else str(results.size()) + " 种方块 · 点击领取一组，优先合并到已有格子")

func grant(key: StringName) -> bool:
	if not inventory.items.has(key) or inventory.items[key].block == null:
		return false
	var requested: int = inventory.items[key].max_stack
	var remainder: int = inventory.insert(key, requested)
	_status.text = ("无法领取：背包已满、正在保存或写入失败" if remainder == requested else "已领取 " + inventory.items[key].display_name + " × " + str(requested - remainder))
	return remainder < requested
