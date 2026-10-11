@tool
extends VBoxContainer
## Presentation only: field widgets commit through the private authoring session.
signal message(text: String)
signal go_to_block(index: int)
signal go_to_item(index: int)
var session: RefCounted
var folds: Dictionary = {}
var field_rows: Array[Control] = []
var file_dialog: FileDialog
var file_action: Callable
var search: String = ""
var current_row: Dictionary = {}

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp,*.svg;图片"])
	file_dialog.file_selected.connect(func(path: String) -> void: if file_action.is_valid(): file_action.call(path))
	add_child(file_dialog)

func reset_form() -> void:
	field_rows.clear()
	for child: Node in get_children():
		if child != file_dialog:
			remove_child(child)
			child.queue_free()

func build(owner: RefCounted, row: Dictionary) -> void:
	session = owner
	current_row = row
	reset_form()
	if row.is_empty(): return
	match String(row.kind):
		"block": block_form(row.asset)
		"item", "paired": item_form(row)
		"fluid": fluid_form(row.data)
	filter(search)

func group(parent: VBoxContainer, title: String, key: String, depth: int = 0, expanded: bool = false) -> VBoxContainer:
	var panel: VBoxContainer = VBoxContainer.new()
	panel.set_meta("fold_key",key)
	parent.add_child(panel)
	var button: Button = Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.flat = false
	var opened: bool = bool(folds.get(key,expanded))
	if not folds.has(key): folds[key] = opened
	button.text = ("▾  " if opened else "▸  ") + title
	button.tooltip_text = title
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = Color(0.16 + depth * 0.025, 0.17 + depth * 0.025, 0.19 + depth * 0.025)
	background.content_margin_left = 8
	background.content_margin_top = 5
	background.content_margin_bottom = 5
	button.add_theme_stylebox_override("normal",background)
	panel.add_child(button)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left",10 + depth*3)
	panel.add_child(margin)
	var body: VBoxContainer = VBoxContainer.new()
	margin.add_child(body)
	margin.visible = opened
	button.pressed.connect(func() -> void:
		var visible: bool = not margin.visible
		folds[key] = visible
		margin.visible = visible
		button.text = ("▾  " if visible else "▸  ") + title
	)
	panel.set_meta("body",margin)
	panel.set_meta("button",button)
	panel.set_meta("title",title)
	return body

func note(parent: VBoxContainer, text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color(0.72,0.75,0.8)
	parent.add_child(label)

func action(parent: Container, text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func field(parent: VBoxContainer, target: Resource, property: String, label: String, options: PackedStringArray = [], minimum: float = -100000, maximum: float = 100000, step: float = 0.01, rebuild: bool = false) -> Control:
	var row: VBoxContainer = VBoxContainer.new()
	row.set_meta("search_text",(label + " " + property).to_lower())
	row.set_meta("property",property)
	parent.add_child(row)
	field_rows.append(row)
	var header: HBoxContainer = HBoxContainer.new()
	row.add_child(header)
	var name_label: Label = Label.new()
	name_label.text = label
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	var revert: Button = Button.new()
	revert.text = "↶"
	revert.tooltip_text = "恢复默认值 · " + property
	header.add_child(revert)
	revert.pressed.connect(func() -> void:
		var defaults: Resource = target.get_script().new()
		session.edit(target,property,defaults.get(property),true)
	)
	row.tooltip_text = property + " · " + label
	var value: Variant = target.get(property)
	var widget: Control
	if not options.is_empty():
		var select: OptionButton = OptionButton.new()
		for option: String in options: select.add_item(option)
		select.selected = int(value)
		select.item_selected.connect(func(index: int) -> void: session.edit(target,property,index,rebuild))
		widget = select
	elif value is bool:
		var toggle: CheckButton = CheckButton.new()
		toggle.button_pressed = value
		toggle.text = "开启"
		toggle.toggled.connect(func(on: bool) -> void: session.edit(target,property,on,rebuild))
		widget = toggle
	elif value is int or value is float:
		var number: SpinBox = SpinBox.new()
		number.min_value = minimum
		number.max_value = maximum
		number.step = 1.0 if value is int else step
		number.value = value
		number.value_changed.connect(func(v: float) -> void: session.edit(target,property,int(v) if value is int else v,rebuild))
		widget = number
	elif value is Color:
		var color: ColorPickerButton = ColorPickerButton.new()
		color.color = value
		color.custom_minimum_size.y = 28
		color.color_changed.connect(func(v: Color) -> void: session.edit(target,property,v))
		prepare_color_popup(color)
		color.get_popup().about_to_popup.connect(func() -> void: clamp_popup.call_deferred(color.get_popup()))
		widget = color
	elif value is Basis:
		var select: OptionButton = OptionButton.new()
		var bases: Array[Basis] = rotations()
		for index: int in range(bases.size()):
			var basis: Basis = bases[index]
			select.add_item("上 " + axis_name(basis.y) + " · 前 " + axis_name(-basis.z))
			if basis.is_equal_approx(value): select.selected = index
		select.item_selected.connect(func(index: int) -> void: session.edit(target,property,bases[index]))
		widget = select
	elif value is Vector3:
		var line: LineEdit = LineEdit.new()
		line.text = "%s, %s, %s" % [value.x,value.y,value.z]
		line.placeholder_text = "x, y, z（米）"
		var apply: Callable = func() -> void:
			if not line.is_inside_tree(): return
			var numbers: PackedStringArray = line.text.split(",")
			if numbers.size() != 3 or not numbers[0].strip_edges().is_valid_float() or not numbers[1].strip_edges().is_valid_float() or not numbers[2].strip_edges().is_valid_float():
				message.emit("需要三个有效数字：" + property)
				return
			session.edit(target,property,Vector3(float(numbers[0]),float(numbers[1]),float(numbers[2])))
		line.text_submitted.connect(func(_text: String) -> void: apply.call())
		line.focus_exited.connect(apply)
		widget = line
	else:
		var line: LineEdit = LineEdit.new()
		line.text = ", ".join(value) if value is PackedStringArray else String(value)
		var apply: Callable = func() -> void:
			if not line.is_inside_tree(): return
			if line.text == (", ".join(target.get(property)) if value is PackedStringArray else String(target.get(property))): return
			var parsed: Variant = StringName(line.text) if value is StringName else line.text
			if value is PackedStringArray:
				parsed = PackedStringArray()
				for part: String in line.text.split(",",false): parsed.append(part.strip_edges())
			session.edit(target,property,parsed,rebuild)
		line.text_submitted.connect(func(_text: String) -> void: apply.call())
		line.focus_exited.connect(apply)
		widget = line
	widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(widget)
	return widget

static func prepare_color_popup(button: ColorPickerButton) -> void:
	var popup: PopupPanel = button.get_popup()
	var picker: ColorPicker = button.get_picker()
	var parent: Node = picker.get_parent()
	parent.remove_child(picker)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(260,260)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	scroll.add_child(picker)
	popup.set_meta("content_picker",picker)
	popup.set_meta("content_scroll",scroll)

static func clamp_popup(window: Window) -> void:
	var bounds: Rect2i = Rect2i(Vector2i.ZERO,Vector2i(window.get_parent().get_viewport().get_visible_rect().size)) if window.is_embedded() else DisplayServer.screen_get_usable_rect(window.current_screen)
	bounds = bounds.grow(-8)
	if window.has_meta("content_picker"):
		var picker: ColorPicker = window.get_meta("content_picker")
		var desired: Vector2i = Vector2i(picker.get_combined_minimum_size()) + Vector2i(32,32)
		var fitted: Vector2i = Vector2i(mini(desired.x,bounds.size.x),mini(desired.y,bounds.size.y))
		var scroll: ScrollContainer = window.get_meta("content_scroll")
		scroll.custom_minimum_size = Vector2(fitted - Vector2i(16,16))
		window.size = fitted
	else: window.size = Vector2i(mini(window.size.x,bounds.size.x),mini(window.size.y,bounds.size.y))
	window.position = Vector2i(clampi(window.position.x,bounds.position.x,bounds.end.x-window.size.x),clampi(window.position.y,bounds.position.y,bounds.end.y-window.size.y))

static func rotations() -> Array[Basis]:
	var result: Array[Basis] = []
	var axes: Array[Vector3] = [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK]
	for x: Vector3 in axes:
		for y: Vector3 in axes:
			if is_zero_approx(x.dot(y)): result.append(Basis(x,y,x.cross(y)))
	return result

static func axis_name(axis: Vector3) -> String:
	for index: int in range(3):
		if absf(axis[index]) > 0.5: return ("+" if axis[index] > 0 else "-") + ["X","Y","Z"][index]
	return "?"

func image_field(parent: VBoxContainer, asset: Resource, slot: String, title: String) -> void:
	var row: VBoxContainer = VBoxContainer.new()
	row.set_meta("search_text",(title + " " + slot + " 图片").to_lower())
	parent.add_child(row)
	field_rows.append(row)
	note(row,title)
	var key: StringName = asset.image_slots.get(slot,&"") if asset is AstraeonBlockAsset else asset.icon_image
	var keys: Array[StringName] = [&""]
	var select: OptionButton = OptionButton.new()
	select.add_item("无图片")
	for entry: StringName in session.project.image_sources:
		keys.append(entry)
		select.add_item(String(entry))
		if key == entry: select.selected = keys.size()-1
	select.item_selected.connect(func(index: int) -> void: session.set_image(asset,slot,keys[index]))
	row.add_child(select)
	var buttons: HBoxContainer = HBoxContainer.new()
	row.add_child(buttons)
	action(buttons,"选择文件…",func() -> void:
		file_action = func(file: String) -> void:
			if not session.bind_file(asset,slot,file): message.emit(session.error)
		file_dialog.popup_centered_ratio(0.65)
	)
	action(buttons,"刷新图片",func() -> void: session.changed.emit(true))
	if not key.is_empty(): picture(row,key)

func picture(parent: VBoxContainer, key: StringName) -> void:
	var path: String = session.image_path(key)
	var label: Label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = path
	parent.add_child(label)
	if path.is_empty() or not FileAccess.file_exists(path):
		label.text = "缺失图片：" + String(key) + "\n" + path
		label.modulate = Color(1,0.48,0.4)
		return
	var image: Image = Image.new()
	var code: Error = image.load(path)
	if code != OK:
		label.text += "\n无法读取：" + error_string(code)
		return
	label.text += "  (%d × %d)" % [image.get_width(),image.get_height()]
	var thumb: TextureRect = TextureRect.new()
	thumb.texture = ImageTexture.create_from_image(image)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.custom_minimum_size.y = 64
	parent.add_child(thumb)

func surface_form(parent: VBoxContainer, surface: AstraeonBlockSurface, asset: AstraeonBlockAsset, slot: String, key: String) -> void:
	var color: VBoxContainer = group(parent,"颜色与贴图",key+"/color",2,true)
	field(color,surface,"base_color","基础颜色")
	image_field(color,asset,slot,"颜色图片")
	var gloss: VBoxContainer = group(parent,"表面光泽",key+"/gloss",2)
	for spec: Array in [["roughness","粗糙度"],["metallic","金属度"],["specular","镜面强度"]]:
		field(gloss,surface,spec[0],spec[1],[],0,1)
	var alpha: VBoxContainer = group(parent,"透明裁剪",key+"/alpha",2)
	field(alpha,surface,"alpha_mode","透明方式",["不透明","裁剪透明"],0,1,1,true)
	if surface.alpha_mode == AstraeonBlockSurface.AlphaMode.CUTOUT:
		field(alpha,surface,"alpha_cutoff","裁剪阈值",[],0,1)
	field(alpha,surface,"double_sided","显示背面")
	var emission: VBoxContainer = group(parent,"自发光",key+"/emission",2)
	field(emission,surface,"emission_color","自发光颜色")
	field(emission,surface,"emission_energy","自发光倍率",[],0,64)
	note(color,"法线 / ORM / 自发光贴图：尚未接入，不能编辑。")

func block_form(asset: AstraeonBlockAsset) -> void:
	var appearance: AstraeonBlockAppearance = asset.block.appearance
	var material: VBoxContainer = group(self,"材质","block/material",0,true)
	var surface: VBoxContainer = group(material,"默认表面","block/surface",1,true)
	surface_form(surface,appearance.default_surface,asset,"surface/default","block/default")
	field(surface,appearance,"texture_resolution","每面像素边长（建议 32）",[],1,1024,1)
	var faces: VBoxContainer = group(material,"六面覆盖","block/faces",1)
	for face: int in range(6):
		var body: VBoxContainer = group(faces,["上面","下面","前面","后面","左面","右面"][face],"block/face/"+str(face),2)
		var toggle: CheckButton = CheckButton.new()
		toggle.text = "覆盖默认表面" if appearance.face_surfaces.has(face) else "继承默认表面"
		toggle.button_pressed = appearance.face_surfaces.has(face)
		body.add_child(toggle)
		toggle.toggled.connect(func(on: bool) -> void:
			var before: Dictionary = session.snapshot()
			if on:
				appearance.face_surfaces[face] = appearance.default_surface.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
				if asset.image_slots.has("surface/default"): asset.image_slots["surface/"+str(face)] = asset.image_slots["surface/default"]
			else:
				appearance.face_surfaces.erase(face)
				asset.image_slots.erase("surface/"+str(face))
			session.commit(before,"六面覆盖",true)
		)
		if appearance.face_surfaces.has(face):
			surface_form(body,appearance.face_surfaces[face],asset,"surface/"+str(face),"block/face/"+str(face))
		action(body,"↶ 重置此面 UV",func() -> void:
			var before: Dictionary = session.snapshot()
			appearance.face_uv_rotations.erase(face)
			appearance.face_uv_mirrors.erase(face)
			session.commit(before,"恢复 UV 默认值",true)
		)
		var rotation: OptionButton = OptionButton.new()
		for degrees: int in [0,90,180,270]: rotation.add_item("UV 旋转 %d°" % degrees)
		rotation.selected = int(appearance.face_uv_rotations.get(face,0))/90
		body.add_child(rotation)
		rotation.item_selected.connect(func(index: int) -> void:
			var values: Dictionary[int,int] = appearance.face_uv_rotations.duplicate()
			values[face] = index*90
			session.edit(appearance,"face_uv_rotations",values)
		)
		for axis: int in range(2):
			var mirror: CheckButton = CheckButton.new()
			mirror.text = "UV 镜像 " + ["U","V"][axis]
			mirror.button_pressed = appearance.face_uv_mirrors.get(face,Vector2i.ZERO)[axis] == 1
			body.add_child(mirror)
			mirror.toggled.connect(func(on: bool) -> void:
				var values: Dictionary[int,Vector2i] = appearance.face_uv_mirrors.duplicate()
				var vector: Vector2i = values.get(face,Vector2i.ZERO)
				vector[axis] = int(on)
				values[face] = vector
				session.edit(appearance,"face_uv_mirrors",values)
			)
	field(group(material,"制作朝向","block/orientation",1),appearance,"authoring_orientation","标准朝向修正")
	var light: VBoxContainer = group(material,"光源外观","block/light",1)
	var enable: CheckButton = CheckButton.new()
	enable.text = "产生局部光源"
	enable.button_pressed = appearance.light != null
	light.add_child(enable)
	enable.toggled.connect(func(on: bool) -> void:
		var value: AstraeonBlockLightAppearance = AstraeonBlockLightAppearance.new() if on else null
		if value != null: value.energy = 1.0
		session.edit(appearance,"light",value,true)
	)
	if appearance.light != null:
		for spec: Array in [["color","颜色"],["energy","强度"],["range","范围（米）"],["attenuation","衰减"],["local_offset","偏移（米）"],["source_radius","光源半径（米）"]]:
			field(light,appearance.light,spec[0],spec[1],[],0.001 if spec[0]=="attenuation" else 0,128)
		field(light,appearance.light,"shadow_policy","阴影策略",["跟随全局","关闭"])
	field(group(material,"树叶层次","block/foliage",1),appearance,"foliage_layers","树叶内部面层次")
	var breaking: VBoxContainer = group(material,"挖掘裂纹","block/breaking",1)
	var cracks: CheckButton = CheckButton.new()
	cracks.text = "启用裂纹"
	cracks.button_pressed = appearance.breaking != null
	breaking.add_child(cracks)
	cracks.toggled.connect(func(on: bool) -> void:
		var before: Dictionary = session.snapshot()
		appearance.breaking = AstraeonBreakingTextureGroup.new() if on else null
		if not on: asset.image_slots.erase("breaking")
		session.commit(before,"裂纹开关",true)
	)
	if appearance.breaking != null:
		image_field(breaking,asset,"breaking","十阶段条带（10N × N）")
		field(breaking,appearance.breaking,"tint","裂纹颜色")
		field(breaking,appearance.breaking,"strength","混合强度",[],0,1)
	var logic: VBoxContainer = group(self,"逻辑数据","block/logic",0,true)
	var basic: VBoxContainer = group(logic,"基本信息","block/basic",1,true)
	field(basic,asset.block,"key","内容 ID")
	field(basic,asset.block,"display_name","名称")
	var item_group: VBoxContainer = group(logic,"关联物品","block/item",1)
	if asset.item != null:
		note(item_group,"同一方块文件：" + String(asset.item.key))
		action(item_group,"编辑关联物品",func() -> void: go_to_item.emit(current_row.index))
	else:
		action(item_group,"创建关联物品",func() -> void:
			var id: String = String(asset.block.key) + "_item"
			if not session.validate_id(id):
				message.emit(session.error)
				return
			var item: AstraeonItemDefinition = AstraeonItemDefinition.new()
			item.key = StringName(id)
			item.display_name = asset.block.display_name
			session.edit(asset,"item",item,true)
		)
	var mining: VBoxContainer = group(logic,"挖掘","block/mining",1)
	field(mining,asset.block,"hardness","硬度",[],0,100000)
	field(mining,asset.block,"required_tool_tag","工具要求标签")
	field(mining,asset.block,"mining_recovery_seconds","进度恢复间隔（秒）",[],0,3600,0.5)
	var collision: VBoxContainer = group(logic,"碰撞与光传播","block/collision",1)
	field(collision,asset.block,"collision_enabled","实体碰撞")
	field(collision,asset.block,"light_opacity","传播光阻挡等级",[],0,15,1)
	field(collision,asset.block,"light_emission","传播光发光等级",[],0,15,1)
	var residency: VBoxContainer = group(logic,"加载策略","block/residency",1)
	var policy: OptionButton = OptionButton.new()
	policy.add_item("预加载 preload")
	policy.add_item("按需 on_demand")
	policy.selected = 0 if asset.block.load_policy == "preload" else 1
	policy.item_selected.connect(func(index: int) -> void: session.edit(asset.block,"load_policy","preload" if index==0 else "on_demand"))
	residency.add_child(policy)
	policy.tooltip_text = "load_policy · 预加载在进入世界前就绪；按需加载仅请求使用的视觉资源。"
	action(residency,"↶ 恢复预加载",func() -> void: session.edit(asset.block,"load_policy","preload",true))
	state_form(group(logic,"状态与朝向","block/states",1),asset.block)

func state_form(parent: VBoxContainer, block: AstraeonBlockDefinition) -> void:
	field(parent,block,"default_state","默认状态键")
	note(parent,"无显式状态时使用 default。这里不是世界中某一方块的当前朝向。")
	for index: int in range(block.states.size()):
		var state: AstraeonBlockStateDefinition = block.states[index]
		var body: VBoxContainer = group(parent,String(state.key),"state/"+str(index),2)
		field(body,state,"key","状态键")
		field(body,state,"orientation","允许朝向")
		dictionary_field(body,state,"properties","状态属性（每行 key=value）")
		action(body,"移除状态",func() -> void:
			if state.key == block.default_state:
				message.emit("请先调整默认状态，再移除此状态。")
				return
			var values: Array[AstraeonBlockStateDefinition] = block.states.duplicate()
			values.remove_at(index)
			session.edit(block,"states",values,true)
		)
	action(parent,"添加状态",func() -> void:
		var values: Array[AstraeonBlockStateDefinition] = block.states.duplicate()
		var state: AstraeonBlockStateDefinition = AstraeonBlockStateDefinition.new()
		state.key = StringName("state_" + str(values.size()))
		values.append(state)
		session.edit(block,"states",values,true)
	)

func item_form(row: Dictionary) -> void:
	var item: AstraeonItemDefinition = row.data
	var material: VBoxContainer = group(self,"材质","item/material",0,true)
	image_field(material,row.asset,"item/icon","物品图标")
	field(material,item,"icon_color","图标基础颜色")
	if row.kind == "paired":
		note(material,"关联方块：" + String(row.owner) + " · 与方块保存在同一文件")
		action(material,"编辑关联方块外观",func() -> void: go_to_block.emit(row.index))
	var logic: VBoxContainer = group(self,"逻辑数据","item/logic",0,true)
	field(logic,item,"key","内容 ID")
	field(logic,item,"display_name","名称")
	field(logic,item,"max_stack","最大堆叠",[],1,999,1)
	field(logic,item,"creative_group","创造目录分组")
	field(logic,item,"search_tags","搜索标签（逗号分隔）")
	var tool: VBoxContainer = group(logic,"工具","item/tool",1)
	field(tool,item,"tool_tags","工具标签（逗号分隔）")
	field(tool,item,"mining_speed","挖掘速度",[],1,1000,0.5)
	if row.kind == "paired": field(logic,item,"orient_to_face","按放置面确定朝向")

func fluid_form(fluid: AstraeonFluidDefinition) -> void:
	var material: VBoxContainer = group(self,"材质","fluid/material",0,true)
	var categories: Array[Array] = [
		["颜色与吸收",["shallow_color","浅水色"],["deep_color","深水色"],["absorption","吸收系数（1/米）"],["opacity","吸收模式不透明度"],["uniform_opacity","统一水色不透明度"]],
		["表面参数",["roughness","粗糙度"],["specular","镜面强度"]],
		["波纹",["wave_strength","波高（米）"],["wave_scale","波纹尺度"],["wave_speed","波纹速度倍率"]],
		["反射响应",["sky_strength","天空反射强度"],["scene_reflection_strength","场景反射强度"]],
		["水下",["underwater_color","水下颜色"],["underwater_attenuation_rate","衰减率（1/米）"],["underwater_attenuation_start","衰减起始距离（米）"]]
	]
	for category: Array in categories:
		var body: VBoxContainer = group(material,category[0],"fluid/"+category[0],1,category[0]=="颜色与吸收")
		for index: int in range(1,category.size()):
			var spec: Array = category[index]
			var maximum: float = 128 if spec[0]=="underwater_attenuation_start" else 8.0
			if spec[0] in ["opacity","uniform_opacity","roughness","specular","scene_reflection_strength"]: maximum = 1
			field(body,fluid.appearance,spec[0],spec[1],[],0.01 if spec[0]=="wave_scale" else 0,maximum,0.001)
	note(material,"基础预览不包含场景反射、水下镜头或完整光影环境。")
	var logic: VBoxContainer = group(self,"逻辑数据","fluid/logic",0,true)
	field(logic,fluid,"key","内容 ID")
	field(logic,fluid,"display_name","名称")
	field(logic,fluid,"collision_enabled","实体碰撞")
	field(logic,fluid,"light_opacity","传播光阻挡等级",[],0,15,1)

func dictionary_field(parent: VBoxContainer, target: Resource, property: String, label: String) -> void:
	note(parent,label)
	var text: TextEdit = TextEdit.new()
	text.custom_minimum_size.y = 90
	var lines: PackedStringArray = []
	var data: Dictionary = target.get(property)
	for key: Variant in data: lines.append(str(key)+"="+str(data[key]))
	text.text = "\n".join(lines)
	parent.add_child(text)
	action(parent,"应用",func() -> void:
		var values: Dictionary = data.duplicate()
		values.clear()
		for line: String in text.text.split("\n",false):
			var at: int = line.find("=")
			if at < 1:
				message.emit("需要 key=value：" + line)
				return
			var key: StringName = StringName(line.left(at).strip_edges())
			var value: String = line.substr(at+1).strip_edges()
			if values.has(key):
				message.emit("重复键：" + String(key))
				return
			values[key] = StringName(value) if property=="properties" else value
		session.edit(target,property,values,true)
	)

func package_form(owner: RefCounted) -> void:
	session = owner
	reset_form()
	var basic: VBoxContainer = group(self,"包设置","package/basic",0,true)
	field(basic,session.project,"package_id","包命名空间")
	field(basic,session.project,"display_name","包名称")
	field(basic,session.project,"dependencies","依赖包 ID（逗号分隔）")
	dictionary_field(group(self,"创造目录分组","package/groups",0),session.project,"creative_groups","分组 ID=显示名称")
	var images: VBoxContainer = group(self,"图片索引","package/images",0,true)
	for key: StringName in session.project.image_sources:
		var body: VBoxContainer = group(images,String(key),"image/"+String(key),1)
		picture(body,key)
		var input: LineEdit = LineEdit.new()
		input.text = session.project.image_sources[key]
		body.add_child(input)
		action(body,"更新路径",func() -> void:
			var values: Dictionary[StringName,String] = session.project.image_sources.duplicate()
			values[key] = input.text
			session.edit(session.project,"image_sources",values,true)
		)
		action(body,"移除索引",func() -> void:
			if not session.remove_image(key): message.emit(session.error)
		)
	note(images,"在材质图片字段选择文件会自动加入索引。图片可放在工程外。")
	action(images,"刷新源图片",func() -> void: session.changed.emit(true))

func filter(text: String) -> void:
	search = text.to_lower().strip_edges()
	for row: Control in field_rows:
		var terms: String = String(row.get_meta("search_text",""))
		var ancestor: Node = row.get_parent()
		while ancestor != self and ancestor != null:
			terms += " " + String(ancestor.get_meta("title",""))
			ancestor = ancestor.get_parent()
		row.visible = search.is_empty() or search in terms.to_lower()
	filter_groups(self)

func filter_groups(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Container: filter_groups(child)
	if node.has_meta("fold_key"):
		var body: MarginContainer = node.get_meta("body")
		var key: String = node.get_meta("fold_key")
		var button: Button = node.get_meta("button")
		if not search.is_empty():
			var matches: bool = search in String(node.get_meta("title", "")).to_lower()
			for row: Control in field_rows:
				if node.is_ancestor_of(row) and row.visible: matches = true
			node.visible = matches
			body.visible = matches
		else:
			node.visible = true
			body.visible = bool(folds.get(key,button.text.begins_with("▾")))
		button.text = ("▾  " if body.visible else "▸  ") + String(node.get_meta("title"))
