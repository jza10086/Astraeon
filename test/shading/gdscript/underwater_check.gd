extends RefCounted
## Opt-in rendered underwater regression. Writes only tmp; restores scene configuration.
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
var checks: int = 0
var failures: int = 0
var rows: PackedStringArray = []

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	rows.append("| %s | %s |" % [label, "PASS" if ok else "FAIL"])
	print("UNDERWATER ", "PASS " if ok else "FAIL ", label)

func _capture(sample: Node3D, name: String) -> Image:
	for index: int in range(20): await sample.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var shot: Image = sample.get_viewport().get_texture().get_image()
	shot.save_png("res://tmp/underwater/" + name + ".png")
	shot.resize(64, 36, Image.INTERPOLATE_BILINEAR)
	return shot

func _difference(a: Image, b: Image) -> float:
	var sum: float = 0.0
	for y: int in range(36):
		for x: int in range(20, 64):
			var ca: Color = a.get_pixel(x, y)
			var cb: Color = b.get_pixel(x, y)
			sum += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return sum / (44.0 * 36.0 * 3.0)

func run(sample: Node3D) -> void:
	DirAccess.make_dir_recursive_absolute("res://tmp/underwater")
	var deadline: int = Time.get_ticks_msec() + 30000
	while (not sample._volume.is_settled() or sample._sections.pending_count() > 0 or sample._uploaded_revision != sample._volume.revision) and Time.get_ticks_msec() < deadline:
		await sample.get_tree().process_frame
	if not sample._volume.is_settled() or sample._sections.pending_count() > 0 or sample._uploaded_revision != sample._volume.revision:
		push_error("Underwater check requires a settled sample; timed out")
		return
	var original: Profile = sample._settings.duplicate(true)
	var camera_transform: Transform3D = sample._camera.global_transform
	var original_path: String = sample.settings_path
	var panel_visible: bool = sample._panel.visible
	sample.settings_path = "res://tmp/underwater/settings.cfg"
	var p: Profile = sample._settings
	p.cycle_enabled = false
	p.hour = 12.0
	p.rays_mode = 0
	p.wave_speed = 0.0
	p.cloud_speed = 0.0
	p.avatar_animate = false
	p.water_enabled = true
	p.underwater_enabled = true
	p.fog_enabled = true
	p.underwater_visibility_enabled = false
	sample._panel.hide()
	sample._view(Vector3(23, -2, -12), Vector3(23, -3, -17))
	sample._apply_lighting()
	var off: Image = await _capture(sample, "off")
	_check(sample._underwater and not sample._environment.fog_enabled, "Off removes underwater fog even with air fog enabled")
	p.underwater_visibility_enabled = true
	p.underwater_attenuation_rate = 0.3
	p.underwater_attenuation_start = 0.0
	sample._apply_lighting()
	var strong: Image = await _capture(sample, "rate_030_start_0")
	_check(_difference(off, strong) > 0.01, "Enabled attenuation visibly changes rendered water")
	p.underwater_attenuation_start = 3.0
	sample._apply_lighting()
	var delayed: Image = await _capture(sample, "rate_030_start_3")
	_check(is_equal_approx(sample._environment.fog_depth_begin, 3.0) and _difference(strong, delayed) > 0.005, "Start distance visibly preserves nearby detail (difference %.4f)" % _difference(strong, delayed))
	p.underwater_attenuation_rate = 0.1
	sample._apply_lighting()
	var weak: Image = await _capture(sample, "rate_010_start_3")
	_check(_difference(delayed, weak) > 0.005, "Lower rate visibly extends transition")
	p.underwater_attenuation_rate = 0.0
	sample._apply_lighting()
	var zero: Image = await _capture(sample, "zero_rate")
	_check(not sample._environment.fog_enabled and _difference(off, zero) < 0.006, "Zero rate equals disabled distance attenuation")
	sample._settings_panel.sync(p)
	sample._settings_panel._select(&"underwater_visibility_enabled", 0)
	_check(not sample._settings_panel.rows[&"underwater_attenuation_rate"].visible and not sample._settings_panel.rows[&"underwater_attenuation_start"].visible, "Disabled limit hides dependent controls")
	_check(sample._settings_panel.rows[&"underwater_color"].visible, "Color setting remains available")
	sample._settings_panel._select(&"underwater_visibility_enabled", 1)
	(sample._settings_panel.widgets[&"underwater_attenuation_rate"] as SpinBox).value_changed.emit(0.2)
	(sample._settings_panel.widgets[&"underwater_attenuation_start"] as SpinBox).value_changed.emit(2.0)
	_check(p.underwater_visibility_enabled and is_equal_approx(p.underwater_attenuation_rate, 0.2) and p.underwater_attenuation_start == 2.0, "Actual panel bindings update settings")
	var loaded: Profile = Profile.new()
	_check(loaded.load_settings(sample.settings_path) == OK and loaded.underwater_visibility_enabled and is_equal_approx(loaded.underwater_attenuation_rate, 0.2) and loaded.underwater_attenuation_start == 2.0, "Saved settings reload correctly")
	var far_before: float = sample._camera.far
	sample._view(Vector3(23, 3, -12), Vector3(23, 1, -24))
	await _capture(sample, "above_water")
	_check(not sample._underwater and sample._environment.fog_enabled and is_equal_approx(sample._environment.fog_depth_begin, p.fog_start), "Leaving water restores outdoor fog")
	_check(sample._camera.far == far_before, "Optical settings never change camera clipping")
	sample._reset_settings()
	_check(sample._settings.underwater_visibility_enabled and is_equal_approx(sample._settings.underwater_attenuation_rate, 1.0 / 12.0) and sample._settings.underwater_attenuation_start == 0.0, "Reset restores underwater defaults")
	var appearance: AstraeonWaterAppearance = preload("res://game/shading/water/resources/default_water.tres").duplicate(true)
	appearance.underwater_attenuation_rate = 0.0
	appearance.underwater_attenuation_start = 0.0
	_check(appearance.validate().is_empty(), "Appearance supports zero attenuation and start")
	appearance.underwater_attenuation_start = -1.0
	_check(not appearance.validate().is_empty(), "Appearance rejects negative start")

	# View-local filter replaces distance attenuation without tinting the settings UI.
	p = sample._settings
	p.underwater_visibility_enabled = false
	p.underwater_color = Color(0.02, 0.25, 0.4)
	p.underwater_tint_opacity = 0.0
	p.rays_mode = 0
	p.cycle_enabled = false
	p.wave_speed = 0.0
	p.cloud_speed = 0.0
	p.avatar_animate = false
	sample._view(Vector3(23, -2, -12), Vector3(23, -3, -17))
	sample._apply_lighting()
	var clear: Image = await _capture(sample, "tint_0")
	_check(not sample._underwater_tint.overlay.visible, "Zero opacity disables filter drawing")
	p.underwater_tint_opacity = 0.5
	sample._apply_lighting()
	var tinted: Image = await _capture(sample, "tint_050")
	_check(sample._underwater_tint.overlay.visible and _difference(clear, tinted) > 0.02, "Filter visibly tints the underwater scene")
	p.underwater_tint_opacity = 1.0
	sample._apply_lighting()
	var opaque: Image = await _capture(sample, "tint_100")
	var center: Color = opaque.get_pixel(40, 22)
	_check(absf(center.r - p.underwater_color.r) < 0.03 and absf(center.g - p.underwater_color.g) < 0.03 and absf(center.b - p.underwater_color.b) < 0.03, "Full opacity covers the world with selected color")
	sample._settings_panel.sync(p)
	(sample._settings_panel.widgets[&"underwater_tint_opacity"] as SpinBox).value_changed.emit(0.37)
	loaded = Profile.new()
	_check(loaded.load_settings(sample.settings_path) == OK and is_equal_approx(loaded.underwater_tint_opacity, 0.37), "Filter opacity UI saves and reloads")
	p.underwater_visibility_enabled = true
	p.underwater_attenuation_rate = 0.1
	sample._apply_lighting()
	sample._settings_panel.sync(p)
	_check(not sample._underwater_tint.overlay.visible and not sample._settings_panel.rows[&"underwater_tint_opacity"].visible, "Distance fog does not stack with filter")
	p.underwater_visibility_enabled = false
	sample._view(Vector3(23, 3, -12), Vector3(23, 1, -24))
	await _capture(sample, "tint_out_of_water")
	_check(not sample._underwater_tint.overlay.visible, "Leaving water clears filter")
	# A solid UI swatch stays white even with a fully opaque blue world filter.
	var ui: CanvasLayer = CanvasLayer.new()
	sample.add_child(ui)
	var swatch: ColorRect = ColorRect.new()
	swatch.color = Color.WHITE
	swatch.position = Vector2(900, 500)
	swatch.size = Vector2(100, 100)
	ui.add_child(swatch)
	sample._view(Vector3(23, -2, -12), Vector3(23, -3, -17))
	p.underwater_tint_opacity = 1.0
	sample._apply_lighting()
	await _capture(sample, "tint_ui")
	await RenderingServer.frame_post_draw
	var full: Image = sample.get_viewport().get_texture().get_image()
	var swatch_center: Vector2 = swatch.get_global_transform_with_canvas() * Vector2(50, 50)
	var canvas_size: Vector2 = sample.get_viewport().get_visible_rect().size
	var pixel: Vector2i = Vector2i(swatch_center * Vector2(full.get_size()) / canvas_size)
	_check(full.get_pixelv(pixel).r > 0.95 and full.get_pixelv(pixel).g > 0.95, "HUD canvas remains untinted")
	swatch.queue_free()
	var button: ColorPickerButton = preload("res://game/ui/gdscript/bounded_color_picker.gd").new()
	ui.add_child(button)
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	button.offset_left = -220
	button.offset_top = -40
	button.offset_right = -10
	button.offset_bottom = -8
	var popup: PopupPanel = button.get_popup()
	var window: Window = Window.new()
	window.title = "Color picker layout check"
	window.transient = true
	sample.add_child(window)
	button.reparent(window, false)
	for requested: Vector2i in [Vector2i(1024, 576), Vector2i(640, 360)]:
		window.popup_centered(requested)
		for index: int in range(5): await sample.get_tree().process_frame
		popup.popup()
		for index: int in range(10): await sample.get_tree().process_frame
		var bounds: Rect2i = Rect2i(Vector2i.ZERO if popup.is_embedded() else window.position, window.size)
		_check(window.size == requested and bounds.encloses(Rect2i(popup.position, popup.size)), "Bottom color popup fits actual window %s" % str(window.size))
		var scroll: ScrollContainer = button.get("_scroll")
		_check(scroll != null and button.get_picker().get_parent() == scroll and (requested.y > 400 or scroll.get_v_scroll_bar().visible), "Picker overflow is scrollable at %s" % str(window.size))
		popup.hide()
		window.hide()
	window.queue_free()
	ui.queue_free()

	sample._settings = original
	sample.settings_path = original_path
	sample._camera.global_transform = camera_transform
	sample._panel.visible = panel_visible
	sample._apply_lighting()
	sample._settings_panel.sync(original)
	var output: FileAccess = FileAccess.open("res://tmp/underwater/results.md", FileAccess.WRITE)
	output.store_string("# Underwater visibility checks\n\n| Check | Result |\n|---|---|\n" + "\n".join(rows) + "\n\nChecks: %d; failures: %d. No performance benchmark.\n" % [checks, failures])
	output.close()
	print("UNDERWATER_DONE checks=", checks, " failures=", failures)
