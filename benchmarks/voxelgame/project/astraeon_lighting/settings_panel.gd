extends RefCounted
## Local UI binding for the exported lighting settings; no global service.
var widgets: Dictionary[StringName, Control] = {}
var profile: AstraeonLightingProfile
var changed: Callable

func build(parent: VBoxContainer, settings: AstraeonLightingProfile, callback: Callable) -> void:
	profile = settings
	changed = callback
	var labels: Dictionary[StringName, String] = {
		&"hour": "时间", &"cycle_enabled": "时间推进", &"sky_enhanced": "天空渐变",
		&"ao_enabled": "顶点 AO", &"ao_strength": "AO 强度",
		&"fog_enabled": "距离雾", &"fog_density": "雾浓度", &"fog_start": "雾起始距离",
		&"aa_mode": "抗锯齿", &"direct_enabled": "太阳 / 月亮直射", &"shadows_enabled": "实时阴影",
		&"shadow_distance": "阴影距离", &"shadow_quality": "阴影质量", &"shadow_bias": "阴影偏移", &"shadow_normal_bias": "法线偏移",
		&"exposure": "固定曝光", &"water_enabled": "显示水面", &"waves_enabled": "水面波纹",
		&"wave_strength": "波纹强度", &"water_reflection": "水面天空反射", &"underwater_enabled": "水下效果",
		&"wind_enabled": "植被风动", &"wind_strength": "风动强度", &"translucency_enabled": "植被透光",
		&"translucency_strength": "透光强度", &"clouds_enabled": "二维云", &"cloud_coverage": "云覆盖率",
		&"cloud_speed": "云速度", &"bloom_enabled": "Bloom", &"bloom_strength": "Bloom 强度"}
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
			if property.hint == PROPERTY_HINT_ENUM:
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
		elif control is SpinBox:
			(control as SpinBox).set_value_no_signal(profile.get(key))
