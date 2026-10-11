extends ColorPickerButton
## Keep the full built-in picker accessible even in a short window or beside a low button.
var _scroll: ScrollContainer
var _fitting: bool = false

func _init() -> void:
	picker_created.connect(_wrap_picker)

func _ready() -> void:
	get_window().size_changed.connect(_queue_fit)

func _wrap_picker() -> void:
	var popup: PopupPanel = get_popup()
	var picker: ColorPicker = get_picker()
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	popup.add_child(_scroll)
	picker.reparent(_scroll, false)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	popup.about_to_popup.connect(_queue_fit)
	picker.minimum_size_changed.connect(_queue_fit)

func _queue_fit() -> void:
	if not _fitting:
		_fitting = true
		_fit_popup.call_deferred()

func _fit_popup() -> void:
	_fitting = false
	if _scroll == null: return
	var popup: PopupPanel = get_popup()
	if not popup.visible: return
	var window: Window = get_window()
	var bounds: Rect2i = Rect2i(Vector2i.ZERO if popup.is_embedded() else window.position, window.size)
	if not popup.is_embedded():
		bounds = bounds.intersection(DisplayServer.screen_get_usable_rect(window.current_screen))
	var margin: Vector2i = Vector2i(12, 12)
	var available: Vector2i = (bounds.size - margin * 2).max(Vector2i(1, 1))
	var natural: Vector2i = Vector2i(get_picker().get_combined_minimum_size().ceil()) + Vector2i(32, 32)
	popup.min_size = Vector2i.ZERO
	popup.size = natural.min(available)
	popup.position = bounds.position + (bounds.size - popup.size) / 2
