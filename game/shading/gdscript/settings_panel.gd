extends RefCounted
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
const Extra: Script = preload("res://game/shading/gdscript/shading_controls.gd")
## Local UI binding for the exported lighting settings; no global service.
var widgets: Dictionary[StringName, Control] = {}
var profile: Profile
var changed: Callable
var rows: Dictionary[StringName, Control] = {}
var groups: Dictionary[String, VBoxContainer] = {}
var group_categories: Dictionary[String, String] = {}
var category: OptionButton
var submenu: OptionButton
var selected_group: String = ""
const CATEGORIES: Array[String] = ["光照", "水面", "环境", "显示与测试"]

func build(parent: VBoxContainer, settings: Profile, callback: Callable) -> void:
	profile = settings
	changed = callback
	var labels: Dictionary[StringName, String] = {
		&"ambient_minimum": "最低环境光强度", &"ambient_minimum_color": "暗处补光颜色",
		&"local_lighting_mode": "局部照明方案", &"voxel_light_strength": "体素主照明强度",
		&"local_point_budget": "混合方案点光源上限", &"local_shadow_budget": "混合方案阴影灯上限",
		&"lamp_emission_color": "发光方块自身颜色", &"lamp_emission_strength": "方块自发光倍率",
		&"test_light_count": "批量光源数量", &"avatar_visible": "测试人物方案",
		&"avatar_animate": "人物移动与摆臂", &"avatar_speed": "人物动画速度",
		&"avatar_travel": "人物移动幅度（米）", &"avatar_scale": "人物尺寸倍率",
		&"day_seconds": "昼夜周期（秒）", &"block_color": "方块光颜色", &"block_energy": "补光亮度系数",
		&"block_curve": "方块光衰减曲线", &"work_cells": "每帧传播格数预算", &"work_usec": "每帧传播预算（微秒）",
		&"water_ssr_refinements": "SSR 命中细化次数", &"water_ssr_normal_offset": "SSR 起点偏移（米）",
		&"planar_strength": "平面反射强度", &"planar_resolution_scale": "反射宽高倍率",
		&"planar_update_fps": "反射更新 Hz（0 每帧）", &"planar_distance": "反射距离（米）",
		&"planar_clip_offset": "水位裁剪偏移（米）", &"planar_distortion": "波纹倒影扰动",
		&"planar_blur_pixels": "倒影模糊半径（像素）", &"planar_edge_fade": "倒影边缘淡出",
		&"planar_aa": "倒影抗锯齿", &"planar_visible_only": "水面离屏停止更新",
		&"planar_reflect_plants": "倒影包含植被", &"planar_reflect_clouds": "倒影包含方块云",
		&"planar_fog": "倒影距离雾",
		&"water_shallow_color": "浅水颜色", &"water_deep_color": "深水颜色",
		&"water_absorption": "水体吸收", &"water_opacity": "水体不透明度",
		&"water_low_opacity": "统一水色不透明度", &"water_roughness": "水面粗糙度",
		&"water_specular": "直射高光强度", &"wave_scale": "波纹密度", &"wave_speed": "波纹速度",
		&"water_sky_strength": "天空反射强度", &"water_reflection_mode": "场景反射方式",
		&"water_ssr_strength": "SSR 强度", &"water_ssr_steps": "SSR 步进次数",
		&"water_ssr_distance": "SSR 最大距离", &"water_ssr_tolerance": "SSR 命中容差",
		&"water_ssr_edge_fade": "SSR 屏幕边缘淡出",
		&"underwater_color": "水下颜色", &"underwater_distance": "水下可视距离",
		&"ambient_smoothing": "环境光平滑", &"ambient_strength": "环境光强度", &"ambient_curve": "环境光衰减曲线",
		&"block_grid_strength": "方块格线强度", &"block_cloud_shadows": "方块云日月阴影",
		&"cloud_shadow_strength": "云影强度", &"cloud_shadow_softness": "云影边缘柔度",
		&"local_light_energy": "局部光强度", &"local_light_range": "局部光范围",
		&"indirect_enabled": "体素间接补光", &"indirect_strength": "补光强度",
		&"hard_shadows": "阴影边缘方式", &"shadow_blur": "阴影模糊半径", &"shadow_resolution": "日月阴影贴图",
		&"water_quality": "水色计算方式",
		&"show_fps": "显示 FPS", &"max_fps": "最大 FPS（0 不限）", &"vsync_enabled": "垂直同步",
		&"hour": "时间", &"cycle_enabled": "时间推进", &"sky_enhanced": "天空渐变",
		&"ao_enabled": "顶点 AO", &"ao_strength": "AO 强度",
		&"fog_enabled": "距离雾", &"fog_density": "雾浓度", &"fog_start": "雾起始距离",
		&"aa_mode": "抗锯齿", &"direct_enabled": "太阳 / 月亮直射", &"shadows_enabled": "日月阴影",
		&"shadow_distance": "阴影距离", &"shadow_quality": "阴影滤波采样", &"shadow_bias": "阴影偏移", &"shadow_normal_bias": "法线偏移",
		&"exposure": "固定曝光", &"water_enabled": "水体方案", &"waves_enabled": "水面波纹",
		&"wave_strength": "波纹强度", &"water_reflection": "水面天空反射", &"underwater_enabled": "水下效果",
		&"wind_enabled": "植被风动", &"wind_strength": "风动强度", &"translucency_enabled": "植被透光",
		&"translucency_strength": "透光强度", &"clouds_enabled": "云方案", &"cloud_coverage": "云覆盖率",
		&"cloud_speed": "云速度", &"bloom_enabled": "Bloom", &"bloom_strength": "Bloom 强度"}
	for key: String in Extra.LABELS:
		labels[StringName(key)] = Extra.LABELS[key]
	var tips: Dictionary[StringName, String] = {
		&"ambient_minimum": "仅抬高材质暗处可见度，不修改体素传播。0 恢复真实零光；非零会让密闭房间也能看清轮廓。",
		&"local_lighting_mode": "仅自发光不照亮周围；体素光没有逐灯阴影；点光源无阴影可能穿墙。混合方案使用体素照明，加少量近处点光源。",
		&"local_point_budget": "仅混合方案生效。按与观察相机距离选择，不合并光源；0 只保留体素光。",
		&"local_shadow_budget": "仅混合方案生效，且不超过启用的点光源数量。未获得阴影预算的点光源可能穿墙。",
		&"test_light_count": "点击放置测试光源才应用数量。固定布局，重新放置先恢复上一批；清除时保留已被用户改成其他方块的位置。",
		&"avatar_animate": "测试人物只有网格动画，没有碰撞、寻路或角色控制器。关闭后冻结当前姿态和位置。",
		&"water_reflection_mode": "关闭场景倒影时，天空反射仍由其独立开关控制。SSR 与平面反射互斥，不代表画质预设。",
		&"planar_resolution_scale": "反射宽高相对当前视口的倍率。0.5 = 宽高各减半、像素数 1/4；实际尺寸显示在顶部状态栏。",
		&"planar_update_fps": "0 表示每个渲染帧更新。正数是更新频率上限；低频率下动态物体倒影会滞后。相机矩阵与捕捉图像一起更新。",
		&"planar_distance": "镜像相机远裁剪距离。距离外物体不进入捕捉，但天空背景仍存在。",
		&"planar_clip_offset": "相对固定水位 0.75 米的裁剪高度。正值剔除更多岸边；负值可能反射水下物体。仅作用于反射相机。",
		&"planar_distortion": "根据水面波纹法线偏移倒影 UV；不是折射。0 保持严格平面投影。",
		&"planar_blur_pixels": "反射纹理像素单位，0 单次采样，非零四点采样。与水面高光粗糙度独立。",
		&"planar_reflect_plants": "关闭时反射不绘制草与树叶；树干和植被投下的阴影仍可能存在。",
		&"planar_reflect_clouds": "控制方块云几何。云关闭时此设置无效。",
		&"planar_fog": "仅控制倒影中的距离雾；仍受全局距离雾开关约束。",
		&"water_ssr_steps": "每像素最大步进次数。次数越多越不容易跳过细物体，深度采样开销越高。",
		&"water_ssr_refinements": "首次穿越深度后进行二分细化的次数；增加后可改善命中精度。",
		&"shadow_quality": "引擎提供的软阴影滤波采样数。硬阴影开启时忽略此项；滤波核半径也遵循引擎对应设置。"}
	category = OptionButton.new()
	for title: String in CATEGORIES:
		category.add_item(title)
	parent.add_child(category)
	submenu = OptionButton.new()
	parent.add_child(submenu)
	category.item_selected.connect(func(_index: int) -> void: _update_submenu())
	submenu.item_selected.connect(func(index: int) -> void:
		selected_group = submenu.get_item_text(index)
		_refresh_visibility())
	for property: Dictionary in profile.settings_properties():
		var key: StringName = property.name
		if not labels.has(key) or key in [&"water_quality", &"avatar_animate", &"block_cloud_shadows"]:
			continue
		var group: String = _group_for(key)
		if not groups.has(group):
			var box: VBoxContainer = VBoxContainer.new()
			parent.add_child(box)
			groups[group] = box
			group_categories[group] = _category_for(group)
		var row: VBoxContainer = VBoxContainer.new()
		groups[group].add_child(row)
		rows[key] = row
		var label: Label = Label.new()
		label.text = labels[key]
		row.add_child(label)
		var value: Variant = profile.get(key)
		if value is bool or property.hint == PROPERTY_HINT_ENUM:
			var option: OptionButton = OptionButton.new()
			var titles: PackedStringArray = ["关闭", "开启"] if value is bool else str(property.hint_string).split(",")
			if key == &"water_enabled": titles = ["关闭", "统一水色", "逐像素深度吸收"]
			if key == &"avatar_visible": titles = ["关闭", "静止人物", "动画人物"]
			if key == &"clouds_enabled": titles = ["关闭", "方块体积云", "方块体积云＋日月云影"]
			if key == &"hard_shadows": titles = ["软阴影", "硬阴影"]
			if key == &"local_lighting_mode": titles[0] = "关闭局部照明（仅自发光）"
			for title: String in titles: option.add_item(title)
			option.item_selected.connect(func(index: int) -> void: _select(key, index))
			row.add_child(option)
			widgets[key] = option
		elif value is Color:
			var picker: ColorPickerButton = ColorPickerButton.new()
			picker.edit_alpha = false
			picker.custom_minimum_size.y = 32
			picker.color_changed.connect(func(color: Color) -> void: _set_value(key, color))
			row.add_child(picker)
			widgets[key] = picker
		else:
			var spin: SpinBox = SpinBox.new()
			var limits: PackedStringArray = str(property.hint_string).split(",")
			spin.min_value = float(limits[0])
			spin.max_value = float(limits[1])
			spin.step = float(limits[2]) if limits.size() > 2 else 0.01
			spin.value_changed.connect(func(number: float) -> void: _set_value(key, number))
			row.add_child(spin)
			widgets[key] = spin
		if tips.has(key): widgets[key].tooltip_text = tips[key]
	# These profile fields are represented by one combined selection each.
	widgets[&"water_quality"] = widgets[&"water_enabled"]
	widgets[&"avatar_animate"] = widgets[&"avatar_visible"]
	widgets[&"block_cloud_shadows"] = widgets[&"clouds_enabled"]
	_update_submenu()
	sync(profile)

func _group_for(key: StringName) -> String:
	var name: String = str(key)
	if Extra.GROUPS.has(name): return Extra.GROUPS[name]
	if name.begins_with("planar_") or name.begins_with("water_ssr_") or key == &"water_reflection_mode": return "场景反射"
	if name.begins_with("underwater_"): return "水下"
	if name.begins_with("wave") or key == &"waves_enabled": return "波纹"
	if name.begins_with("water_"): return "水体与天空反射"
	if name.begins_with("cloud") or key == &"block_cloud_shadows": return "方块云"
	if name.begins_with("wind") or name.begins_with("translucency"): return "植被"
	if name.begins_with("fog"): return "距离雾"
	if name.begins_with("ambient") or name.begins_with("ao_") or key == &"block_grid_strength": return "环境光与 AO"
	if name.begins_with("shadow") or key == &"hard_shadows": return "阴影"
	if name.begins_with("lamp_"): return "方块自发光"
	if name.begins_with("avatar_") or key == &"test_light_count": return "人物与批量光源"
	if name.begins_with("work_"): return "传播预算"
	if key in [&"hour", &"cycle_enabled", &"day_seconds", &"sky_enhanced", &"direct_enabled", &"exposure"]: return "时间与天空"
	if key in [&"aa_mode", &"show_fps", &"max_fps", &"vsync_enabled", &"bloom_enabled", &"bloom_strength"]: return "画面与帧率"
	return "局部照明"

func _category_for(group: String) -> String:
	if group in ["天气", "降雨", "潮湿表面"]: return "环境"
	if group in ["景深", "运动模糊", "色差", "曝光"] or group.begins_with("色彩"): return "显示与测试"
	if group in ["场景反射", "水下", "波纹", "水体与天空反射"]: return "水面"
	if group in ["方块云", "植被", "距离雾"]: return "环境"
	if group in ["人物与批量光源", "传播预算", "画面与帧率"]: return "显示与测试"
	return "光照"

func _update_submenu() -> void:
	submenu.clear()
	for group: String in groups:
		if group_categories[group] == category.get_item_text(category.selected):
			submenu.add_item(group)
	selected_group = submenu.get_item_text(0)
	_refresh_visibility()

## Navigate to the category and submenu containing a setting.
func show_setting(key: StringName) -> void:
	var group: String = _group_for(key)
	category.select(CATEGORIES.find(_category_for(group)))
	_update_submenu()
	for index: int in range(submenu.item_count):
		if submenu.get_item_text(index) == group: submenu.select(index)
	selected_group = group
	_refresh_visibility()

func _select(key: StringName, index: int) -> void:
	if key == &"water_enabled":
		profile.water_enabled = index > 0
		if index > 0: profile.water_quality = index - 1
	elif key == &"avatar_visible":
		profile.avatar_visible = index > 0
		profile.avatar_animate = index == 2
	elif key == &"clouds_enabled":
		profile.clouds_enabled = index > 0
		profile.block_cloud_shadows = index == 2
	else:
		profile.set(key, bool(index) if profile.get(key) is bool else index)
	changed.call()
	sync(profile)

func _set_value(key: StringName, value: Variant) -> void:
	profile.set(key, value)
	changed.call()
	sync(profile)

func _effective(key: StringName) -> bool:
	if Extra.GATES.has(str(key)):
		var gate: PackedStringArray = Extra.GATES[str(key)].split(":")
		return str(int(profile.get(gate[0]))) in gate[1].split(",")
	if key == &"exposure": return profile.exposure_mode == 0
	var name: String = str(key)
	if key == &"day_seconds": return profile.cycle_enabled
	if key == &"ambient_minimum_color": return profile.ambient_minimum > 0.0
	if key == &"ao_strength": return profile.ao_enabled
	if name.begins_with("fog_") and key != &"fog_enabled": return profile.fog_enabled
	if name.begins_with("bloom_") and key != &"bloom_enabled": return profile.bloom_enabled
	if key == &"shadows_enabled": return profile.direct_enabled
	if key in [&"shadow_distance", &"shadow_resolution", &"shadow_bias", &"shadow_normal_bias"]: return profile.direct_enabled and profile.shadows_enabled
	var shadow_active: bool = (profile.direct_enabled and profile.shadows_enabled) or profile.local_lighting_mode == 2 or (profile.local_lighting_mode == 4 and profile.local_point_budget > 0 and profile.local_shadow_budget > 0)
	if key == &"hard_shadows": return shadow_active
	if key in [&"shadow_blur", &"shadow_quality"]: return shadow_active and not profile.hard_shadows
	if key in [&"local_light_energy", &"local_light_range"]: return profile.local_lighting_mode >= 2
	if key in [&"local_point_budget", &"local_shadow_budget"]: return profile.local_lighting_mode == 4
	if key == &"voxel_light_strength": return profile.local_lighting_mode in [1, 4]
	if key == &"indirect_enabled": return profile.local_lighting_mode in [2, 3]
	if key == &"indirect_strength": return profile.local_lighting_mode in [2, 3] and profile.indirect_enabled
	if key == &"block_color": return profile.local_lighting_mode != 0
	if key in [&"block_energy", &"block_curve"]: return profile.effective_block_strength() > 0.0
	if key == &"water_enabled": return true
	if _category_for(_group_for(key)) == "水面":
		if not profile.water_enabled: return false
		if name.begins_with("water_ssr_"): return profile.water_reflection_mode == 1
		if name.begins_with("planar_"):
			if profile.water_reflection_mode != 2: return false
			if key == &"planar_reflect_clouds": return profile.clouds_enabled
			if key == &"planar_fog": return profile.fog_enabled
			if key == &"planar_distortion": return profile.waves_enabled
		if key in [&"water_deep_color", &"water_absorption", &"water_opacity"]: return profile.water_quality == 1
		if key == &"water_low_opacity": return profile.water_quality == 0
		if name.begins_with("wave_"): return profile.waves_enabled
		if key == &"water_sky_strength": return profile.water_reflection
		if name.begins_with("underwater_") and key != &"underwater_enabled": return profile.underwater_enabled
	if key in [&"cloud_coverage", &"cloud_speed"]: return profile.clouds_enabled
	if name.begins_with("cloud_shadow_"): return profile.clouds_enabled and profile.block_cloud_shadows and profile.direct_enabled
	if key == &"wind_strength": return profile.wind_enabled
	if key == &"translucency_strength": return profile.translucency_enabled
	if key == &"avatar_scale": return profile.avatar_visible
	if key in [&"avatar_speed", &"avatar_travel"]: return profile.avatar_visible and profile.avatar_animate
	return true

func _refresh_visibility() -> void:
	for group: String in groups: groups[group].visible = group == selected_group
	for key: StringName in rows: rows[key].visible = _effective(key)

func sync(settings: Profile) -> void:
	profile = settings
	for key: StringName in rows:
		var control: Control = widgets[key]
		var value: Variant = profile.get(key)
		if control is OptionButton:
			var index: int = int(value)
			if key == &"water_enabled": index = profile.water_quality + 1 if profile.water_enabled else 0
			if key == &"avatar_visible": index = (2 if profile.avatar_animate else 1) if profile.avatar_visible else 0
			if key == &"clouds_enabled": index = (2 if profile.block_cloud_shadows else 1) if profile.clouds_enabled else 0
			(control as OptionButton).select(index)
		elif control is ColorPickerButton: (control as ColorPickerButton).color = value
		elif control is SpinBox: (control as SpinBox).set_value_no_signal(value)
	_refresh_visibility()
