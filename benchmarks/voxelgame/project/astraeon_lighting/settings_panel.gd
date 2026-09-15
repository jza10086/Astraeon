extends RefCounted
## Local UI binding for the exported lighting settings; no global service.
var widgets: Dictionary[StringName, Control] = {}
var profile: AstraeonLightingProfile
var changed: Callable

func build(parent: VBoxContainer, settings: AstraeonLightingProfile, callback: Callable) -> void:
	profile = settings
	changed = callback
	var labels: Dictionary[StringName, String] = {
		&"ambient_minimum": "最低环境光强度", &"ambient_minimum_color": "暗处补光颜色",
		&"local_lighting_mode": "局部照明方案", &"voxel_light_strength": "体素主照明强度",
		&"local_point_budget": "混合方案点光源上限", &"local_shadow_budget": "混合方案阴影灯上限",
		&"lamp_emission_color": "发光方块自身颜色", &"lamp_emission_strength": "方块自发光倍率",
		&"test_light_count": "批量光源数量", &"avatar_visible": "显示测试人物",
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
		&"block_grid_strength": "方块格线强度", &"cloud_type": "云类型", &"block_cloud_shadows": "方块云日月阴影",
		&"cloud_shadow_strength": "云影强度", &"cloud_shadow_softness": "云影边缘柔度",
		&"local_lights_enabled": "局部直射光", &"local_light_energy": "局部光强度", &"local_light_range": "局部光范围",
		&"indirect_enabled": "体素间接补光", &"indirect_strength": "补光强度",
		&"hard_shadows": "硬阴影", &"shadow_blur": "阴影模糊半径", &"shadow_resolution": "日月阴影贴图",
		&"water_quality": "水色计算方式", &"cloud_steps": "云采样步数", &"cloud_morph": "云动态变形",
		&"show_fps": "显示 FPS", &"max_fps": "最大 FPS（0 不限）", &"vsync_enabled": "垂直同步",
		&"hour": "时间", &"cycle_enabled": "时间推进", &"sky_enhanced": "天空渐变",
		&"ao_enabled": "顶点 AO", &"ao_strength": "AO 强度",
		&"fog_enabled": "距离雾", &"fog_density": "雾浓度", &"fog_start": "雾起始距离",
		&"aa_mode": "抗锯齿", &"direct_enabled": "太阳 / 月亮直射", &"shadows_enabled": "日月阴影",
		&"shadow_distance": "阴影距离", &"shadow_quality": "阴影滤波采样", &"shadow_bias": "阴影偏移", &"shadow_normal_bias": "法线偏移",
		&"exposure": "固定曝光", &"water_enabled": "显示水面", &"waves_enabled": "水面波纹",
		&"wave_strength": "波纹强度", &"water_reflection": "水面天空反射", &"underwater_enabled": "水下效果",
		&"wind_enabled": "植被风动", &"wind_strength": "风动强度", &"translucency_enabled": "植被透光",
		&"translucency_strength": "透光强度", &"clouds_enabled": "显示云", &"cloud_coverage": "云覆盖率",
		&"cloud_speed": "云速度", &"bloom_enabled": "Bloom", &"bloom_strength": "Bloom 强度"}
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
		&"planar_reflect_clouds": "控制方块云几何。程序化天空云属于天空背景，遵循全局云设置。",
		&"planar_fog": "仅控制倒影中的距离雾；仍受全局距离雾开关约束。",
		&"water_ssr_steps": "每像素最大步进次数。次数越多越不容易跳过细物体，深度采样开销越高。",
		&"water_ssr_refinements": "首次穿越深度后进行二分细化的次数；增加后可改善命中精度。",
		&"shadow_quality": "引擎提供的软阴影滤波采样数。硬阴影开启时忽略此项；滤波核半径也遵循引擎对应设置。"}
	var current_group: String = ""
	for property: Dictionary in profile.get_property_list():
		if property.usage & PROPERTY_USAGE_GROUP:
			current_group = property.name
			continue
		var key: StringName = property.name
		if not labels.has(key):
			continue
		if not current_group.is_empty():
			var heading: Label = Label.new()
			heading.text = "—— " + current_group + " ——"
			parent.add_child(heading)
			current_group = ""
		var value: Variant = profile.get(key)
		if value is bool:
			var check: CheckButton = CheckButton.new()
			check.text = labels[key]
			check.button_pressed = value
			check.toggled.connect(func(v: bool) -> void: _set_value(key, v))
			parent.add_child(check)
			widgets[key] = check
		else:
			var row: HBoxContainer = HBoxContainer.new()
			parent.add_child(row)
			var label: Label = Label.new()
			label.text = labels[key]
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			if value is Color:
				var picker: ColorPickerButton = ColorPickerButton.new()
				picker.color = value
				picker.edit_alpha = false
				picker.custom_minimum_size = Vector2(100, 32)
				picker.color_changed.connect(func(v: Color) -> void: _set_value(key, v))
				row.add_child(picker)
				widgets[key] = picker
			elif property.hint == PROPERTY_HINT_ENUM:
				var option: OptionButton = OptionButton.new()
				for title: String in str(property.hint_string).split(","):
					option.add_item(title)
				option.select(int(value))
				option.item_selected.connect(func(v: int) -> void: _set_value(key, v))
				row.add_child(option)
				widgets[key] = option
			else:
				var spin: SpinBox = SpinBox.new()
				var limits: PackedStringArray = str(property.hint_string).split(",")
				spin.min_value = float(limits[0])
				spin.max_value = float(limits[1])
				spin.step = float(limits[2]) if limits.size() > 2 else 0.01
				spin.value = float(value)
				spin.value_changed.connect(func(v: float) -> void: _set_value(key, v))
				row.add_child(spin)
				widgets[key] = spin

	for key: StringName in widgets:
		if tips.has(key):
			widgets[key].tooltip_text = tips[key]

func _set_value(key: StringName, value: Variant) -> void:
	profile.set(key, value)
	changed.call()

func sync(settings: AstraeonLightingProfile) -> void:
	profile = settings
	for key: StringName in widgets:
		var control: Control = widgets[key]
		if control is CheckButton:
			(control as CheckButton).set_pressed_no_signal(profile.get(key))
		elif control is OptionButton:
			(control as OptionButton).select(profile.get(key))
		elif control is ColorPickerButton:
			(control as ColorPickerButton).color = profile.get(key)
		elif control is SpinBox:
			(control as SpinBox).set_value_no_signal(profile.get(key))
