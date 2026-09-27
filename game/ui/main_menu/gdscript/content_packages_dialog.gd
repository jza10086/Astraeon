extends ConfirmationDialog
const Paths: Script = preload("res://game/core/gdscript/project_paths.gd")
## Title-screen package installation and enablement, before world construction.
var settings_path: String = Paths.settings_file()
var list: VBoxContainer
var status: Label
var checks: Dictionary[String, CheckBox] = {}
var picker: FileDialog
func _ready() -> void:
	title = "方块内容包 / Mods"
	dialog_hide_on_ok = false
	size = Vector2i(720, 520)
	var body: VBoxContainer = VBoxContainer.new()
	add_child(body)
	var install: Button = Button.new()
	install.text = "安装 .aebpack 内容包"
	body.add_child(install)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(680, 320)
	body.add_child(scroll)
	list = VBoxContainer.new()
	scroll.add_child(list)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	picker = FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.filters = PackedStringArray(["*.aebpack ; Astraeon content"])
	add_child(picker)
	install.pressed.connect(func() -> void: picker.popup_centered_ratio(0.7))
	picker.file_selected.connect(_install)
	confirmed.connect(_save)
	refresh()
func refresh() -> void:
	for child: Node in list.get_children():
		list.remove_child(child)
		child.queue_free()
	checks.clear()
	var config: ConfigFile = ConfigFile.new()
	config.load(settings_path)
	var stored: Variant = config.get_value("content", "enabled", PackedStringArray())
	var enabled: PackedStringArray = stored if stored is PackedStringArray else PackedStringArray()
	if DirAccess.dir_exists_absolute(Paths.blocks_directory()):
		for file: String in DirAccess.get_files_at(Paths.blocks_directory()):
			if file.get_extension() != "aebpack":
				continue
			var reader: RefCounted = ClassDB.instantiate("AstraeonContentPack")
			var data: Dictionary = reader.call("open_pack", Paths.blocks_directory().path_join(file))
			var box: CheckBox = CheckBox.new()
			box.text = file + " — " + (String(data.error) if data.has("error") else String(data.name))
			box.disabled = data.has("error")
			box.button_pressed = enabled.has(file)
			list.add_child(box)
			checks[file] = box
	status.text = "勾选后保存，下次进入世界时生效。已有世界缺少必需内容时会拒绝进入。"
func _install(path: String) -> void:
	var reader: RefCounted = ClassDB.instantiate("AstraeonContentPack")
	var data: Dictionary = reader.call("open_pack", path)
	if data.has("error"):
		status.text = data.error
		return
	DirAccess.make_dir_recursive_absolute(Paths.blocks_directory())
	var target: String = Paths.blocks_directory().path_join(String(data.id) + ".aebpack")
	var result: Error = DirAccess.copy_absolute(path, target)
	refresh()
	status.text = "已安装，请选择启用" if result == OK else "安装失败：" + error_string(result)
func _save() -> void:
	var config: ConfigFile = ConfigFile.new()
	var result: Error = config.load(settings_path)
	if result not in [OK, ERR_FILE_NOT_FOUND]:
		status.text = "设置文件无法读取，未覆盖"
		return
	var enabled: PackedStringArray = []
	for file: String in checks:
		if checks[file].button_pressed and not checks[file].disabled:
			enabled.append(file)
	config.set_value("content", "format", 1)
	config.set_value("content", "enabled", enabled)
	result = config.save(settings_path)
	if result != OK:
		status.text = "保存失败：" + error_string(result)
		popup_centered()
	else:
		hide()
