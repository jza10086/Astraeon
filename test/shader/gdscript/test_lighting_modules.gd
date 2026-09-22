extends SceneTree
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
## Settings checks always run. --render opts into short GPU/interaction validation.
## FPS UI is verified, without collecting a performance benchmark. Artifacts use a separate output directory.
const Sample: Script = preload("res://test/shader/gdscript/shading_sample.gd")
const Details: Script = preload("res://test/shader/gdscript/environment_details.gd")
var _failures: int = 0
var _checks: int = 0
var _output: String = "user://lighting_validation"
var _sample: Sample
var _render: SubViewport

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		push_error(message)

func _run() -> void:
	var render: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--render":
			render = true
		elif argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(_output)
	_settings_checks()
	if render:
		if DisplayServer.get_name() == "headless":
			push_error("Rendered checks require a display")
			quit(2)
			return
		await _render_checks()
	print("P12_CHECK ", "PASS" if _failures == 0 else "FAIL", " assertions=", _checks, " failures=", _failures)
	quit(0 if _failures == 0 else 1)

func _settings_checks() -> void:
	var defaults: Profile = Profile.new()
	var missing: String = _output.path_join("missing-%d.cfg" % Time.get_ticks_usec())
	_check(defaults.load_settings(missing) == ERR_FILE_NOT_FOUND and defaults.aa_mode == 1, "First run keeps defaults")
	var file: String = _output.path_join("settings-test.cfg")
	var config: ConfigFile = ConfigFile.new()
	config.set_value("unrelated", "keep", "preserved")
	config.set_value("shading", "format", "astraeon-shading-20260922")
	config.set_value("shading", "ao_strength", 500.0)
	config.set_value("shading", "fog_density", -1)
	config.set_value("shading", "aa_mode", 40)
	config.set_value("shading", "bloom_enabled", "wrong type")
	config.save(file)
	defaults.load_settings(file)
	_check(defaults.ao_strength == 1.0 and defaults.fog_density == 0.001 and defaults.aa_mode == 2, "Numeric settings clamped")
	_check(not defaults.bloom_enabled, "Wrong setting type ignored")
	defaults.max_fps = 120
	defaults.hard_shadows = true
	defaults.shadow_blur = 0.35
	defaults.shadow_resolution = 1
	defaults.water_quality = 0
	defaults.indirect_strength = 0.02
	defaults.clouds_enabled = false
	defaults.bloom_enabled = true
	defaults.water_reflection = false
	_check(defaults.save_settings(file) == OK, "Save settings")
	var restored: Profile = Profile.new()
	_check(restored.load_settings(file) == OK, "Reload settings")
	for property: Dictionary in defaults.settings_properties():
		_check(defaults.get(property.name) == restored.get(property.name), "Roundtrip " + str(property.name))
	config.load(file)
	_check(config.get_value("unrelated", "keep") == "preserved", "Unrelated settings preserved")
	var detail: Details = Details.new()
	_check(detail.is_underwater(Vector3(24, -2, -15)), "Deep pool underwater")
	_check(not detail.is_underwater(Vector3(16, -3, -15)), "Below shallow bottom is not water")
	_check(not detail.is_underwater(Vector3(24, 1, -15)), "Above water is dry")
	detail.free()

func _settle() -> void:
	var begin: int = Time.get_ticks_msec()
	while (not _sample._volume.is_settled() or _sample._sections.pending_count() > 0 or _sample._uploaded_revision != _sample._volume.revision) and Time.get_ticks_msec() - begin < 90000:
		await process_frame
	_check(_sample._volume.is_settled(), "Light converges")
	await _frames(12)

func _frames(count: int) -> void:
	for i: int in range(count):
		await process_frame

func _capture(name: String) -> void:
	await _frames(16)
	await RenderingServer.frame_post_draw
	var image: Image = _render.get_texture().get_image()
	_check(image.save_png(_output.path_join(name + ".png")) == OK, "Capture " + name)
	print("P12_SCREENSHOT ", name, " size=", image.get_size())

func _render_checks() -> void:
	_render = SubViewport.new()
	_render.size = Vector2i(1920, 1080)
	_render.own_world_3d = true
	_render.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_render)
	var display: TextureRect = TextureRect.new()
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.texture = _render.get_texture()
	root.add_child(display)
	var scene: PackedScene = load("res://test/shader/scenes/shading_sample.tscn")
	_sample = scene.instantiate() as Sample
	_sample.settings_path = _output.path_join("sample-settings.cfg")
	_render.add_child(_sample)
	_sample._reset_settings()
	for node: Node in _sample._panel.get_children():
		if node is Button:
			(node as Button).pressed.emit()
			break
	await _settle()
	var ui_ao: OptionButton = _sample._settings_panel.widgets[&"ao_enabled"] as OptionButton
	ui_ao.item_selected.emit(0)
	_check(not _sample._settings.ao_enabled, "UI toggle applies")
	var persisted: Profile = Profile.new()
	persisted.load_settings(_sample.settings_path)
	_check(not persisted.ao_enabled, "UI toggle persists")
	ui_ao.item_selected.emit(1)
	var revision: int = _sample._volume.revision
	var mesh_count: int = _sample._sections.rebuilt_sections
	await _capture("p12-default")
	await _updated_module_checks()
	revision = _sample._volume.revision
	mesh_count = _sample._sections.rebuilt_sections
	# Independent switches must not dirty world data or mesh geometry.
	for key: StringName in [&"ao_enabled", &"fog_enabled", &"shadows_enabled", &"clouds_enabled", &"wind_enabled", &"translucency_enabled", &"bloom_enabled", &"water_reflection", &"waves_enabled"]:
		var old: bool = _sample._settings.get(key)
		_sample._settings.set(key, not old)
		_sample._apply_lighting()
		await _frames(3)
		_check(_sample._volume.revision == revision and _sample._sections.rebuilt_sections == mesh_count, "Display-only switch " + str(key))
		_sample._settings.set(key, old)
	_sample._settings.aa_mode = 2
	_sample._apply_lighting()
	_check(_render.use_taa and _render.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "TAA mutually exclusive")
	_sample._view(Vector3(-29, 8, 12), Vector3(-23, 3, 4))
	await _capture("p12-ao-taa")
	_sample._settings.aa_mode = 1
	_sample._apply_lighting()
	_check(not _render.use_taa and _render.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA, "FXAA mutually exclusive")
	_sample._view(Vector3(30, 10, -5), Vector3(20, 0, -17))
	await _capture("p12-water")
	_sample._view(Vector3(23, -2, -14), Vector3(25, -2, -22))
	await _frames(3)
	_check(_sample._underwater and _sample._environment.fog_depth_end == 12.0, "Underwater fog entered")
	await _capture("p12-underwater")
	_sample._view(Vector3(-27, 2, -9), Vector3(-20, 3, -20))
	await _frames(3)
	_check(not _sample._underwater, "Underwater state restored")
	_sample._settings.hour = 17.6
	_sample._apply_lighting()
	await _capture("p12-plants-sunset")
	_sample._settings.hour = 0.0
	_sample._settings.bloom_enabled = true
	_sample._apply_lighting()
	_sample._toggle_window()
	_sample._toggle_lamp()
	_sample._view(Vector3(5, 4, 1), Vector3(-3, 3, -4))
	await _settle()
	await _capture("p12-bloom-night")
	_sample._settings.bloom_enabled = false
	_sample._apply_lighting()
	await _capture("p12-no-bloom-night")
	# All-off: feature clocks stop and basic world light survives.
	for key: StringName in [&"indirect_enabled", &"sky_enhanced", &"direct_enabled", &"ao_enabled", &"fog_enabled", &"shadows_enabled", &"clouds_enabled", &"wind_enabled", &"translucency_enabled", &"bloom_enabled", &"water_enabled", &"underwater_enabled", &"water_reflection", &"waves_enabled"]:
		_sample._settings.set(key, false)
	_sample._settings.aa_mode = 0
	_sample._apply_lighting()
	var clocks: Vector3 = Vector3(_sample._cloud_clock, _sample._details.water_clock, _sample._details.wind_clock)
	await _frames(5)
	_check(clocks == Vector3(_sample._cloud_clock, _sample._details.water_clock, _sample._details.wind_clock), "Disabled clocks stop")
	_check(not _render.use_taa and _render.screen_space_aa == 0, "AA off")
	await _capture("p12-all-off")
	_sample._reset_settings()
	_check(_sample._settings.aa_mode == 1 and _sample._settings.ao_enabled and not _sample._settings.bloom_enabled, "Reset defaults")
	_sample._settings.bloom_enabled = true
	_sample._settings.aa_mode = 2
	_sample._apply_lighting()
	_sample._view(Vector3(23, 17, 27), Vector3(0, 4, 0))
	await _capture("p12-all-on")
	var scroll: ScrollContainer = _sample._panel.get_parent() as ScrollContainer
	scroll.scroll_vertical = 10000
	await _capture("p12-settings")
	# Render-size/layout checks without asking the desktop for a 4K window.
	var sizes: Array[Vector2i] = [Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(2560, 1080)]
	for size: Vector2i in sizes:
		_render.size = size
		_render.size_2d_override = Vector2i(roundi(float(size.x) * 1080.0 / size.y), 1080)
		_render.size_2d_override_stretch = true
		await _capture("p12-layout-%dx%d" % [size.x, size.y])
		_check(_sample._panel.get_parent() is ScrollContainer, "Panel scroll container")
	_sample._reset_settings()
	print("P12_RENDERED renderer=", RenderingServer.get_current_rendering_method())

func _updated_module_checks() -> void:
	var revision: int = _sample._volume.revision
	var cap: SpinBox = _sample._settings_panel.widgets[&"max_fps"] as SpinBox
	cap.value = 120
	_check(Engine.max_fps == 120, "FPS cap applies from UI")
	var saved: Profile = Profile.new()
	saved.load_settings(_sample.settings_path)
	_check(saved.max_fps == 120, "FPS cap persists")
	cap.value = 0
	_check(Engine.max_fps == 0, "Unlimited FPS restores")
	_sample._settings.show_fps = false
	_sample._apply_lighting()
	_check(not _sample._fps_label.visible, "FPS overlay can hide")
	_sample._settings.show_fps = true
	_sample._settings.hard_shadows = true
	_sample._settings.shadow_resolution = 1
	_sample._apply_lighting()
	_check(_sample._filter_quality == RenderingServer.SHADOW_QUALITY_HARD and _sample._atlas_size == 2048 and _sample._sun.shadow_blur == 0.0, "Hard shadow and atlas apply")
	_sample._settings.hour = 17.6
	_sample._view(Vector3(10, 3, 12), Vector3(0, 1, 0))
	_sample._apply_lighting()
	await _capture("update-hard-shadows")
	_sample._settings.hard_shadows = false
	_sample._settings.shadow_blur = 0.4
	_sample._settings.shadow_resolution = 2
	_sample._apply_lighting()
	_check(is_equal_approx(_sample._sun.shadow_blur, 0.4) and _sample._atlas_size == 4096, "Soft blur and atlas restore")
	await _capture("update-soft-shadows")
	_sample._settings.hour = 12.0
	_sample._view(Vector3(20, 2, 25), Vector3(20, 30, -20))
	_sample._apply_lighting()
	await _capture("update-clouds")
	_sample._apply_lighting()
	_sample._settings.clouds_enabled = false
	_sample._apply_lighting()
	await _capture("update-clouds-off")
	_check(_sample._volume.revision == revision, "New display controls do not alter voxels")
	_sample._view(Vector3(30, 10, -5), Vector3(20, 0, -17))
	_sample._settings.water_quality = 0
	_sample._apply_lighting()
	_check(not _sample._details.water_materials[0].get_shader_parameter("depth_absorption"), "Uniform water fallback")
	await _capture("update-water-low")
	_sample._settings.water_quality = 1
	_sample._apply_lighting()
	await _capture("update-water-depth")
	# Light tight against front wall; a one-voxel aperture versus fully sealed.
	_sample._settings.hour = 0.0
	_sample._settings.indirect_enabled = false
	_sample._settings.fog_enabled = false
	_sample._apply_lighting()
	var edits: Dictionary[Vector3i, int] = {}
	_sample.Fixtures.box(edits, _sample.Fixtures.WINDOW, _sample.Volume.WOOD)
	edits[Vector3i(-1, 1, 2)] = _sample.Volume.LAMP
	edits[Vector3i(-1, 2, 3)] = _sample.Volume.AIR
	_sample._edit(edits)
	await _settle()
	_check(_sample._local_lights.emitters.has(Vector3i(-1,1,2)), "Edited lamp creates local emitter")
	_sample._view(Vector3(5, 4, 1), Vector3(-1, 2, 2))
	await _capture("update-local-interior")
	_sample._view(Vector3(4, 4, 12), Vector3(-1, 2, 3))
	await _capture("update-local-hole-direct")
	_sample._settings.indirect_enabled = true
	_sample._apply_lighting()
	await _capture("update-local-hole-fill")
	_sample._edit({Vector3i(-1,2,3): _sample.Volume.WOOD})
	await _settle()
	await _capture("update-local-sealed")
	_sample._settings.local_lighting_mode = 0
	_sample._apply_lighting()
	_check(_sample._local_lights.emitters[Vector3i(-1,1,2)].light_energy == 0.0, "Local direct switch independent")
	_sample._edit({Vector3i(-1,1,2): _sample.Volume.AIR})
	_check(_sample._local_lights.emitters.is_empty(), "Removed lamp removes emitter")
	edits.clear()
	_sample.Fixtures.box(edits, _sample.Fixtures.WINDOW, _sample.Volume.AIR)
	_sample._edit(edits)
	await _settle()
	_sample._reset_settings()
	_sample._view(Vector3(23,17,27), Vector3(0,4,0))
