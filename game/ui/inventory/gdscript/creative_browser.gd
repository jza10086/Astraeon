extends VBoxContainer
## Content area only. Main HUD owns the upper category/search and lower storage tabs.
var inventory: AstraeonInventoryState
var search: LineEdit
var group: StringName = &""
var search_page: bool = false
var results: Array[AstraeonItemDefinition] = []
var _grid: GridContainer
var _status: Label
var _scroll: ScrollContainer

func _ready() -> void:
	custom_minimum_size = Vector2(660, 304)
	search = LineEdit.new()
	search.placeholder_text = "搜索名称、ID、标签（空格分隔关键词）"
	search.clear_button_enabled = true
	search.text_changed.connect(func(_text: String) -> void: refresh())
	add_child(search)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(660, 244)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 10
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	_scroll.add_child(_grid)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("303238"))
	add_child(_status)
	show_page(&"", false)

func show_page(key: StringName, is_search: bool) -> void:
	group = key
	search_page = is_search
	search.visible = is_search
	search.release_focus()
	refresh()
	if is_search:
		search.grab_focus()

func refresh() -> void:
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	results = inventory.catalog.find_blocks(group, search.text if search_page else "")
	for item: AstraeonItemDefinition in results:
		var cell: Control = preload("res://game/ui/inventory/gdscript/creative_cell.gd").new()
		cell.item = item
		cell.inventory = inventory
		_grid.add_child(cell)
	_scroll.scroll_vertical = 0
	_status.text = "没有匹配的方块" if results.is_empty() else str(results.size()) + " 种方块 · 左键拿一个 / 中键拿一组"
