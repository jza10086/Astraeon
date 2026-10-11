extends VBoxContainer
## Recovery choices only; core owns slot selection and world owns persistence.
signal create_requested()
signal back_requested()
var create_button: Button
func build(directory: String) -> void:
	var info: Label = Label.new()
	info.text = "此存档参数或内容格式不受当前版本支持，不能直接打开。\n旧存档将完整保留；创建新世界不会继承原有建筑和背包。\n旧目录：" + directory
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(info)
	create_button = Button.new()
	create_button.name = "CreateNewWorld"
	create_button.text = "创建新世界（保留旧存档）"
	create_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	create_button.pressed.connect(func() -> void: create_requested.emit())
	add_child(create_button)
	var back: Button = Button.new()
	back.text = "返回主菜单"
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func() -> void: back_requested.emit())
	add_child(back)
