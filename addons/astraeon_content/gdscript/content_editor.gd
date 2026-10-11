@tool
extends Control
## Main-screen host. Source files, previews and game state have separate lifetimes.
const Paths = preload("res://game/core/gdscript/project_paths.gd")
const Session = preload("res://addons/astraeon_content/gdscript/content_session.gd")
@export var layout_path: String = ""
@export var auto_open: bool = true
var session: RefCounted = Session.new()
var selected: Dictionary = {}
var visible_rows: Array[Dictionary] = []
var kind: String = "block"
var package_page: bool = false
var pending_action: Callable
var after_save: Callable
var file_action: Callable
var name_mode: String = ""
var copy_source: Dictionary = {}
var ui_rebuild_pending: bool = false
var check_clock: float = 0.0
var active: bool = true
var layout_writable: bool = false
@onready var toolbar: HFlowContainer = %Toolbar
@onready var title: Label = %Document
@onready var list: ItemList = %Resources
@onready var type_select: OptionButton = %Type
@onready var find: LineEdit = %Search
@onready var property_find: LineEdit = %PropertySearch
@onready var form: VBoxContainer = %Form
@onready var preview: VBoxContainer = %Preview
@onready var report: RichTextLabel = %Report
@onready var file_dialog: FileDialog = %FileDialog
@onready var unsaved: ConfirmationDialog = %Unsaved
@onready var conflict: ConfirmationDialog = %Conflict
@onready var name_dialog: ConfirmationDialog = %NameDialog
@onready var name_input: LineEdit = %NameInput
@onready var paired: CheckBox = %Paired
@onready var right_split: HSplitContainer = %RightSplit
@onready var left_split: HSplitContainer = %LeftSplit

func _ready() -> void:
	if layout_path.is_empty(): layout_path = Paths.root_directory().path_join("runtime_data/content_editor.cfg")
	session.changed.connect(document_changed)
	for entry: Array in [
		["新建包",func() -> void: guarded(ask_new_project)],
		["打开",func() -> void: guarded(choose_project)],
		["保存全部",func() -> void: save_current()],
		["撤销",func() -> void: session.undo()],
		["重做",func() -> void: session.redo()],
		["校验",validate],
		["导出 .aebpack",choose_export],
		["包设置",show_package],
		["关闭工程",func() -> void: guarded(close_document)]
	]:
		button(toolbar,entry[0],entry[1])
	type_select.item_selected.connect(func(index: int) -> void:
		kind = ["block","item","fluid"][index]
		package_page = false
		selected.clear()
		refresh_list()
	)
	find.text_changed.connect(func(_text: String) -> void: refresh_list())
	property_find.text_changed.connect(func(text: String) -> void: form.filter(text))
	list.item_selected.connect(select_index)
	%New.pressed.connect(func() -> void: ask_resource(false))
	%Copy.pressed.connect(func() -> void: ask_resource(true))
	%Remove.pressed.connect(func() -> void:
		if selected.is_empty(): return
		if not session.remove(selected): show_message(session.error,true)
		else:
			selected.clear()
			refresh_list()
	)
	form.message.connect(func(text: String) -> void: show_message(text,true))
	form.go_to_block.connect(func(index: int) -> void:
		kind = "block"
		type_select.selected = 0
		package_page = false
		find.text = ""
		selected = session.rows(kind)[index]
		refresh_list()
	)
	form.go_to_item.connect(func(index: int) -> void:
		kind = "item"
		type_select.selected = 1
		package_page = false
		find.text = ""
		selected = {"kind":"paired","index":index}
		refresh_list()
	)
	file_dialog.file_selected.connect(func(file: String) -> void: if file_action.is_valid(): file_action.call(file))
	unsaved.add_button("放弃更改",false,"discard")
	unsaved.confirmed.connect(func() -> void:
		if save_current(): run_pending()
	)
	unsaved.custom_action.connect(func(action: StringName) -> void:
		if action == &"discard":
			unsaved.hide()
			run_pending()
	)
	unsaved.canceled.connect(func() -> void: pending_action = Callable())
	conflict.add_button("放弃本地，重新加载",false,"reload")
	conflict.confirmed.connect(func() -> void:
		if session.save_all(true):
			if after_save.is_valid(): after_save.call()
			after_save = Callable()
			if pending_action.is_valid(): run_pending()
		else: show_message(session.error,true)
	)
	conflict.custom_action.connect(func(action: StringName) -> void:
		if action == &"reload":
			conflict.hide()
			after_save = Callable()
			pending_action = Callable()
			open_document(session.path)
	)
	conflict.canceled.connect(func() -> void: after_save = Callable(); pending_action = Callable())
	name_dialog.confirmed.connect(name_confirmed)
	name_input.text_submitted.connect(func(_text: String) -> void: name_confirmed())
	report.meta_clicked.connect(func(meta: Variant) -> void: locate_error(String(meta)))
	if not load_layout(): return
	if auto_open:
		var initial: String = "res://game/data/content/authoring/astraeon/pack.tres"
		if not FileAccess.file_exists(initial): initial = "res://test/content/resources/example_manifest.tres"
		if FileAccess.file_exists(initial): open_document(initial)

func button(parent: Container, text: String, callback: Callable) -> void:
	var node: Button = Button.new()
	node.text = text
	node.pressed.connect(callback)
	parent.add_child(node)

func set_active(value: bool) -> void:
	active = value
	visible = value

func open_document(path: String) -> void:
	if not session.open_project(path):
		show_message(session.error,true)
		return
	selected.clear()
	package_page = false
	kind = "block"
	type_select.selected = 0
	find.text = ""
	refresh_list()
	show_message("已打开：" + path)

func close_document() -> void:
	session.project = null
	session.history.clear_history()
	selected.clear()
	list.clear()
	form.reset_form()
	preview.pending = null
	preview.clear()
	title.text = "未打开包工程"

func guarded(action: Callable) -> void:
	if session.dirty():
		pending_action = action
		unsaved.dialog_text = "当前包工程有未保存更改。"
		unsaved.popup_centered()
	else: action.call()

func run_pending() -> void:
	var action: Callable = pending_action
	pending_action = Callable()
	if action.is_valid(): action.call()

func choose_project() -> void:
	file_action = open_document
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.tres;包工程"])
	file_dialog.popup_centered_ratio(0.7)

func ask_new_project() -> void:
	name_mode = "project"
	name_dialog.title = "新建包工程 · 命名空间"
	name_input.text = "example"
	paired.hide()
	name_dialog.popup_centered(Vector2i(440,180))

func ask_resource(copy: bool) -> void:
	if session.project == null or (copy and selected.is_empty()): return
	name_mode = "resource"
	copy_source = selected if copy else {}
	name_dialog.title = "复制资源（使用新 ID）" if copy else "新建资源"
	name_input.text = session.project.package_id + ":" + (String(selected.data.key).get_slice(":",1)+"_copy" if copy else "new_resource")
	paired.visible = kind == "block"
	paired.button_pressed = true
	name_dialog.popup_centered(Vector2i(440,180))

func name_confirmed() -> void:
	if name_mode == "project":
		var namespace_id: String = name_input.text.strip_edges()
		name_dialog.hide()
		file_action = func(file: String) -> void:
			if not session.create_project(file,namespace_id): show_message(session.error,true)
			else: show_package()
		file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		file_dialog.filters = PackedStringArray(["*.tres;包工程"])
		file_dialog.current_file = "pack.tres"
		file_dialog.popup_centered_ratio(0.7)
	else:
		if not session.add(kind,name_input.text.strip_edges(),paired.button_pressed,copy_source):
			show_message(session.error,true)
			return
		name_dialog.hide()
		selected.clear()
		refresh_list()
		for index: int in range(visible_rows.size()):
			if String(visible_rows[index].data.key) == name_input.text.strip_edges():
				list.select(index)
				select_index(index)
				break

func save_current() -> bool:
	if session.project == null: return false
	if not session.external_changes().is_empty():
		conflict.dialog_text = "以下文件在外部发生变化：\n" + "\n".join(session.external_changes()) + "\n覆盖会使用当前工作副本。"
		conflict.popup_centered(Vector2i(620,300))
		return false
	if not session.save_all():
		show_message(session.error,true)
		return false
	show_message("保存完成：" + session.path)
	return true

func choose_export() -> void:
	if session.project == null: return
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.filters = PackedStringArray(["*.aebpack;Astraeon 内容包"])
	file_dialog.current_path = ProjectSettings.globalize_path("res://game/data/content/packages/astraeon.aebpack") if session.project.package_id == "astraeon" else ProjectSettings.globalize_path(session.path.get_base_dir().path_join(session.project.package_id+".aebpack"))
	file_action = func(file: String) -> void:
		after_save = export_to.bind(file)
		if save_current():
			after_save = Callable()
			export_to(file)
	file_dialog.popup_centered_ratio(0.7)

func export_to(file: String) -> void:
	var checked: Dictionary = session.compile("",true)
	if checked.is_empty():
		show_message("编译器未返回结果；检查编辑器错误输出。",true)
		return
	if checked.has("error"):
		show_message(String(checked.error),true)
		return
	var result: Dictionary = session.compile(file)
	if result.is_empty(): result = {"error":"编译器未返回结果；检查编辑器错误输出。"}
	show_message(String(result.error) if result.has("error") else "导出完成：" + file + "\n" + JSON.stringify(result),result.has("error"))

func validate() -> void:
	if session.project == null: return
	var result: Dictionary = session.compile("",true)
	if result.is_empty(): result = {"error":"编译器未返回结果；检查编辑器错误输出。"}
	show_message(String(result.error) if result.has("error") else "校验通过：" + JSON.stringify(result),result.has("error"))

func show_message(text: String, failure: bool = false) -> void:
	report.clear()
	report.push_color(Color(1,0.55,0.45) if failure else Color(0.72,0.85,0.78))
	if failure: report.push_meta(text)
	report.append_text(text)
	if failure: report.pop()
	report.pop()
	if failure: locate_error(text)

func locate_error(text: String) -> void:
	if session.project == null: return
	for category: String in ["block","item","fluid"]:
		for row: Dictionary in session.rows(category):
			if String(row.data.key).is_empty() or not String(row.data.key) in text: continue
			kind = category
			type_select.selected = ["block","item","fluid"].find(kind)
			package_page = false
			selected = row
			find.text = ""
			refresh_list()
			for property_row: Control in form.field_rows:
				var property: String = property_row.get_meta("property","")
				if not property.is_empty() and property in text:
					property_find.text = property
					form.filter(property)
					break
			return

func document_changed(rebuild: bool) -> void:
	if session.project == null: return
	title.text = ("● 未保存  " if session.dirty() else "") + session.project.display_name + "  ·  " + session.path
	title.tooltip_text = session.path
	if rebuild and not ui_rebuild_pending:
		ui_rebuild_pending = true
		rebuild_document.call_deferred()
	elif not rebuild:
		for index: int in range(visible_rows.size()):
			var row: Dictionary = visible_rows[index]
			list.set_item_text(index, String(row.data.display_name)+"  ·  "+String(row.data.key)+("  ↳ 方块关联" if row.kind=="paired" else ""))
		if not selected.is_empty(): preview.schedule(session.compiler_input(selected),selected.kind)

func rebuild_document() -> void:
	ui_rebuild_pending = false
	if package_page: show_package()
	else: refresh_list()

func refresh_list() -> void:
	list.clear()
	visible_rows.clear()
	if session.project == null: return
	var previous_kind: String = selected.get("kind","")
	var previous_index: int = selected.get("index",-1)
	var query: String = find.text.to_lower()
	var chosen: int = -1
	for row: Dictionary in session.rows(kind):
		var text: String = String(row.data.display_name) + "  ·  " + String(row.data.key)
		if not query.is_empty() and not query in text.to_lower(): continue
		if row.kind == "paired": text += "  ↳ 方块关联"
		list.add_item(text)
		list.set_item_tooltip(list.item_count-1,row.file + ("\n所属：" + row.owner if not row.owner.is_empty() else ""))
		visible_rows.append(row)
		if row.kind == previous_kind and row.index == previous_index: chosen = visible_rows.size()-1
	if not visible_rows.is_empty():
		chosen = maxi(chosen,0)
		list.select(chosen)
		select_index(chosen)
	else:
		selected.clear()
		form.reset_form()
		preview.pending = null
		preview.clear()

func select_index(index: int) -> void:
	if index < 0 or index >= visible_rows.size(): return
	package_page = false
	selected = visible_rows[index]
	form.build(session,selected)
	form.filter(property_find.text)
	preview.schedule(session.compiler_input(selected),selected.kind)

func show_package() -> void:
	if session.project == null: return
	package_page = true
	form.package_form(session)
	form.filter(property_find.text)

func _process(delta: float) -> void:
	if not active or session.project == null or title == null: return
	check_clock += delta
	if check_clock < 1: return
	check_clock = 0
	var external: bool = not session.external_changes().is_empty()
	title.text = ("● 未保存  " if session.dirty() else "") + ("⚠ 外部文件变化  " if external else "") + session.project.display_name + "  ·  " + session.path

func load_layout() -> bool:
	if not FileAccess.file_exists(layout_path):
		layout_writable = true
		return true
	var config: ConfigFile = ConfigFile.new()
	var code: Error = config.load(layout_path)
	if code != OK or config.get_value("editor","format",0) != 1:
		show_message("无法读取编辑器布局 " + layout_path + ": " + error_string(code) + "（要求格式 1）",true)
		return false
	var fold_values: Variant = config.get_value("editor","folds",{})
	var left: Variant = config.get_value("editor","left",0)
	var right: Variant = config.get_value("editor","right",0)
	if not fold_values is Dictionary or not left is int or not right is int:
		show_message("编辑器布局字段类型无效：" + layout_path,true)
		return false
	for key: Variant in fold_values:
		if not key is String or not fold_values[key] is bool:
			show_message("编辑器折叠状态无效：" + layout_path,true)
			return false
	form.folds = fold_values
	layout_writable = true
	left_split.split_offset = config.get_value("editor","left",0)
	right_split.split_offset = config.get_value("editor","right",0)
	return true

func save_layout() -> void:
	if not layout_writable: return
	var code: Error = DirAccess.make_dir_recursive_absolute(layout_path.get_base_dir())
	if code != OK:
		push_error("无法创建编辑器设置目录：" + error_string(code))
		return
	var config: ConfigFile = ConfigFile.new()
	config.set_value("editor","format",1)
	config.set_value("editor","folds",form.folds)
	config.set_value("editor","left",left_split.split_offset)
	config.set_value("editor","right",right_split.split_offset)
	code = config.save(layout_path + ".pending")
	if code == OK: code = DirAccess.rename_absolute(layout_path + ".pending",layout_path)
	if code != OK: push_error("无法保存编辑器布局 " + layout_path + ": " + error_string(code))

func _exit_tree() -> void:
	if is_instance_valid(form): save_layout()
