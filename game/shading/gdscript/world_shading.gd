class_name AstraeonWorldShading
extends Node3D
const Paths: Script = preload("res://game/core/gdscript/project_paths.gd")
## Scene-local effects assembly. Native cache owns derived section lighting and bounded uploads.
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
const Palette: Script = preload("res://game/shading/gdscript/day_palette.gd")
const Clouds: Script = preload("res://game/shading/gdscript/block_clouds.gd")
const Weather: Script = preload("res://game/shading/gdscript/weather_effects.gd")
const Glass: Script = preload("res://game/shading/gdscript/colored_shadows.gd")
const Moving: Script = preload("res://game/shading/gdscript/moving_light.gd")
const Budget: Script = preload("res://game/shading/gdscript/light_budget.gd")
const Effects: Script = preload("res://game/shading/gdscript/camera_effects.gd")
const Shafts: Script = preload("res://game/shading/gdscript/light_shafts.gd")
const WaterBinding: Script = preload("res://game/shading/gdscript/water_appearance_binding.gd")
const Post: Script = preload("res://game/shading/gdscript/camera_post.gd")
const Planar: Script = preload("res://game/shading/gdscript/planar_reflection.gd")
const SettingsPanel: Script = preload("res://game/shading/gdscript/settings_panel.gd")
const FrameTimeLabel: Script = preload("res://game/ui/gdscript/frame_time_label.gd")
@export var profile: Profile = preload("res://game/shading/resources/default_profile.tres")
@export var settings_path: String = Paths.settings_file()
var world: Node3D
var _settings: Profile
var _cloud_profile: Profile
var _camera: Camera3D
var _sun: DirectionalLight3D
var _environment: Environment
var _sky_material: ShaderMaterial
var _fog_color: Color
const UnderwaterTint: Script = preload("res://game/shading/gdscript/underwater_tint.gd")
var _underwater_tint: UnderwaterTint = UnderwaterTint.new()
var _underwater: bool = false
var materials: Array[ShaderMaterial] = []
var plants: Array[ShaderMaterial] = []
const Foliage: Script = preload("res://game/shading/blocks/gdscript/foliage_rendering.gd")
var _foliage_mode: int = -1
var water_materials: Array[ShaderMaterial] = []
var clouds: Clouds = Clouds.new()
var weather: Weather = Weather.new()
var glass: Glass = Glass.new()
var moving: Moving = Moving.new()
var budget: Budget = Budget.new()
var effects: Effects = Effects.new()
var motion: Post = Post.new()
var post: Post = Post.new()
var shafts: Shafts = Shafts.new()
var planar: Planar = Planar.new()
var panel: SettingsPanel = SettingsPanel.new()
var _menu: PanelContainer
var _fps: FrameTimeLabel
var _timer: float = 0.0
var _clock: float = 0.0
var _water_clock: float = 0.0
var _cloud_clock: float = 0.0
var _revision: int = 0
var field_publications: int = 0
var _source_revision: int = -1
## Opt-in main-thread timing; no samples or clock reads when diagnostics are disabled.
signal diagnostic_timing(kind: StringName, start_usec: int, duration_usec: int)
var diagnostics_enabled: bool = false
var _emitters: Array = []
var _lights: Array[OmniLight3D] = []
var _previous_max_fps: int
var _previous_vsync: DisplayServer.VSyncMode
var _local_fog: FogVolume = FogVolume.new()
var _previous_camera: Transform3D

func configure(owner_world: Node3D) -> void:
    world = owner_world
    _camera = world.camera
    _sun = world.get_node("Sun") as DirectionalLight3D
    _environment = Environment.new()
    _environment.background_mode = Environment.BG_SKY
    _environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    _environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    _environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    _sky_material = ShaderMaterial.new()
    _sky_material.shader = preload("res://game/shading/shaders/background_sky.gdshader")
    _environment.sky = Sky.new()
    _environment.sky.sky_material = _sky_material
    (world.get_node("WorldEnvironment") as WorldEnvironment).environment = _environment
    _settings = profile.duplicate(true) as Profile
    var error: Error = _settings.load_settings(settings_path)
    if error != OK and error != ERR_FILE_NOT_FOUND:
        push_warning("Unsupported/unreadable shading settings; using defaults: " + error_string(error))
        _settings = profile.duplicate(true) as Profile
    _previous_max_fps = Engine.max_fps
    _previous_vsync = DisplayServer.window_get_vsync_mode()
    _compile_materials()
    for component: Node in [clouds,weather,glass,moving,planar]: add_child(component)
    var receivers: Array[ShaderMaterial] = materials.duplicate()
    receivers.append_array(water_materials)
    clouds.configure(receivers)
    weather.configure(materials)
    weather.configure_cache(world.cache_coordinator.native)
    glass.configure(receivers)
    planar.water_height = world.WATER_SURFACE_HEIGHT
    planar.configure(_camera,water_materials,materials)
    _local_fog.size = Vector3(24,16,24)
    _local_fog.material = FogMaterial.new()
    add_child(_local_fog)
    motion.configure_stage(true)
    post.configure_stage(false)
    var compositor: Compositor = Compositor.new()
    add_child(shafts)
    shafts.configure(_camera)
    compositor.compositor_effects = [motion,shafts.effect,post]
    _camera.compositor = compositor
    _camera.far = maxf(_camera.far,1600.0)
    _previous_camera = _camera.global_transform
    for material: ShaderMaterial in materials:
        world.cache_coordinator.native.call("bind_material",material)
    add_child(_underwater_tint)
    _make_ui()
    _apply_lighting()

func _compile_materials() -> void:
    var content: AstraeonWorldContent = world.content
    for index: int in range(1,content.library.models.size()):
        var model: VoxelBlockyModel = content.library.models[index]
        var material: ShaderMaterial = model.get_material_override(0) as ShaderMaterial
        if index == content.water_id:
            water_materials.append(material)
        else:
            if bool(material.get_shader_parameter("block_cutout")) and not plants.has(material):
                plants.append(material)
            if not materials.has(material):
                materials.append(material)

## World readiness follows converged native results and completed page publication.
func is_ready() -> bool:
    return world != null and world.cache_coordinator.native.call("is_ready")

## Explicit camera cut, including short cuts that do not exceed motion thresholds.
func reset_camera_history() -> void:
    motion.reset_history()
    post.reset_history()
    _previous_camera = _camera.global_transform

func _process(delta: float) -> void:
    if world == null: return
    var diagnostic_start: int = Time.get_ticks_usec() if diagnostics_enabled else 0
    _local_fog.global_position = _camera.global_position
    _clock += delta
    _timer += delta
    var metrics: Dictionary = world.cache_coordinator.metrics
    var publications: int = int(metrics.get("page_uploads",0))
    if int(metrics.get("source_revision",0)) != _source_revision:
        _source_revision = int(metrics.get("source_revision",0))
        _emitters = world.cache_coordinator.native.call("get_light_sources")
        _allocate_lights()
    field_publications = publications
    if _settings.cycle_enabled:
        _settings.hour = fposmod(_settings.hour+delta*24.0/_settings.day_seconds,24.0)
    var weather_changed: bool = weather.tick(delta,_settings,_camera.global_position)
    if weather_changed: _update_weather()
    if _settings.cycle_enabled or weather_changed: _update_daylight()
    if _settings.clouds_enabled: _cloud_clock += delta*_settings.cloud_speed
    clouds.tick(_cloud_clock,_camera.global_position)
    if _settings.water_enabled and _settings.waves_enabled: _water_clock += delta*_settings.wave_speed
    for material: ShaderMaterial in water_materials: material.set_shader_parameter("clock",_water_clock)
    if _settings.wind_enabled:
        for material: ShaderMaterial in plants: material.set_shader_parameter("wind_clock",_clock)
    var wet: bool = _settings.water_enabled and _settings.underwater_enabled and world.voxel_tool.get_voxel(Vector3i(_camera.global_position.floor())) == world.content.water_id
    if wet != _underwater:
        _underwater = wet
        _apply_fog()
    moving.global_transform = _camera.global_transform
    moving.position += _camera.global_basis*Vector3(0.35,-0.25,-0.5)
    if _settings.moving_mode == 2:
        moving.global_position = world.player.global_position+Vector3(cos(_clock*_settings.moving_speed)*5,3,sin(_clock*_settings.moving_speed)*5)
    if int(_clock*5.0) != int((_clock-delta)*5.0): _allocate_lights()
    glass.tick(_settings,_sun,_camera.global_position)
    planar.water_bounds = AABB(Vector3(_camera.global_position.x-world.horizontal_distance,world.WATER_SURFACE_HEIGHT-1.0,_camera.global_position.z-world.horizontal_distance),Vector3(world.horizontal_distance*2,2,world.horizontal_distance*2))
    planar.tick(delta,_settings)
    if _camera.global_position.distance_to(_previous_camera.origin)>3.0 or _camera.global_basis.z.dot(_previous_camera.basis.z)<0.7:
        motion.reset_history()
        post.reset_history()
    _previous_camera = _camera.global_transform
    motion.update(_settings,_camera,_sun)
    post.update(_settings,_camera,_sun)
    shafts.tick(_settings,_sun,clouds,weather.cloud_weight)
    if _settings.dof_mode == 2:
        var hit: VoxelRaycastResult = world.voxel_tool.raycast(_camera.global_position,-_camera.global_basis.z,100.0)
        effects.update_focus(_settings,hit.distance if hit != null else 100.0,delta)
    _fps.visible = _settings.show_fps
    _fps.sampling_enabled = _settings.show_fps and field_publications > 0
    var managed_bytes: int = int(metrics.get("voxel_bytes",0))+int(metrics.get("light_bytes",0))+int(metrics.get("derived_bytes",0))+int(metrics.get("weather_cpu_bytes",0))+int(metrics.get("temporary_bytes",0))
    _fps.context_text = "F6 光影设置 | 光照页 %d | 队列 %d | CPU 缓存 %.1f MiB | 命中 %d%s" % [int(metrics.get("pages",0)),int(metrics.get("queue",0)),float(managed_bytes)/1048576.0,int(metrics.get("map_hits",0))," | 缓存容量不足" if bool(metrics.get("unreclaimable_over_budget",false)) or bool(metrics.get("capacity_blocked",false)) else ""]

    if diagnostics_enabled: diagnostic_timing.emit(&"effects",diagnostic_start,Time.get_ticks_usec()-diagnostic_start)

func _allocate_lights() -> void:
    _emitters.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
        return Vector3(a.position).distance_squared_to(_camera.global_position)<Vector3(b.position).distance_squared_to(_camera.global_position))
    var limit: int = mini(_settings.light_budget,_settings.local_point_budget if _settings.local_lighting_mode == 4 else _settings.light_budget)
    var count: int = mini(limit,_emitters.size()) if _settings.local_lighting_mode >= 2 else 0
    while _lights.size()<count:
        var lamp: OmniLight3D = OmniLight3D.new()
        add_child(lamp)
        _lights.append(lamp)
    budget.clear_requests()
    for index: int in range(_lights.size()):
        var lamp: OmniLight3D = _lights[index]
        lamp.light_energy = 0.0
        if index >= count: continue
        var item: Dictionary = _emitters[index]
        var definition: AstraeonBlockLightAppearance = world.content.light_definitions.get(int(item.state))
        if definition == null: continue
        lamp.global_position = Vector3(item.position)+Vector3.ONE*0.5+world.content.light_offsets.get(int(item.state),Vector3.ZERO)
        lamp.light_color = definition.color
        lamp.omni_range = definition.range * _settings.local_light_range / 8.0
        lamp.omni_attenuation = definition.attenuation
        lamp.light_size = definition.source_radius
        lamp.light_volumetric_fog_energy = _settings.volume_local_energy if _settings.rays_mode == 2 else 0.0
        lamp.shadow_blur = 1.0 if _settings.hard_shadows else maxf(_settings.shadow_blur,0.001)
        var shadows: bool = _settings.local_lighting_mode == 2 or (_settings.local_lighting_mode == 4 and index<_settings.local_shadow_budget)
        budget.register(lamp,definition.energy*_settings.local_light_energy,shadows and definition.shadow_policy == 0)
    budget.register(moving.light,moving.energy,moving.request_shadows,moving.priority)
    budget.allocate(_camera.global_position,_settings.light_budget,_settings.light_shadow_budget,_settings.light_hysteresis)

## Scene objects with transparent appearance register explicitly; no per-voxel glass nodes.
func register_transparent_caster(mesh: MeshInstance3D) -> void:
    glass.add_caster(mesh)

func unregister_transparent_caster(mesh: MeshInstance3D) -> void:
    glass.remove_caster(mesh)

func _make_ui() -> void:
    var layer: CanvasLayer = CanvasLayer.new()
    layer.layer = 31
    layer.process_mode = Node.PROCESS_MODE_ALWAYS
    add_child(layer)
    _fps = FrameTimeLabel.new()
    _fps.add_theme_font_size_override("font_size",16)
    _fps.position = Vector2(24,130)
    layer.add_child(_fps)
    _menu = PanelContainer.new()
    layer.add_child(_menu)
    _menu.theme = preload("res://game/ui/resources/menu_theme.tres")
    var background: StyleBoxFlat = StyleBoxFlat.new()
    background.bg_color = Color(0.09, 0.105, 0.115, 1.0)
    background.content_margin_left = 32
    background.content_margin_right = 32
    background.content_margin_top = 24
    background.content_margin_bottom = 24
    _menu.add_theme_stylebox_override("panel", background)
    _menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    _menu.anchor_top = 0.08
    _menu.anchor_bottom = 0.92
    _menu.offset_left = -480
    _menu.offset_right = 480
    _menu.offset_top = 0
    _menu.offset_bottom = 0
    var frame: VBoxContainer = VBoxContainer.new()
    _menu.add_child(frame)
    var heading: Label = Label.new()
    heading.text = "设置"
    heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    heading.add_theme_font_size_override("font_size", 36)
    frame.add_child(heading)
    var scroll: ScrollContainer = ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.follow_focus = true
    frame.add_child(scroll)
    var box: VBoxContainer = VBoxContainer.new()
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(box)
    world.dropped_items.add_settings(box)
    panel.build(box,_settings,_changed)
    # Fixture-only actions and per-step budgets are not production settings.
    for key: StringName in panel.rows.keys():
        if String(key).begins_with("avatar_") or String(key).begins_with("test_") or key in [&"work_cells",&"work_usec",&"lamp_emission_color",&"gloss_metal_roughness",&"gloss_metal_metallic",&"gloss_metal_specular"]:
            panel.rows[key].queue_free()
            panel.rows.erase(key)
            panel.widgets.erase(key)
    var reset: Button = Button.new()
    reset.text = "恢复默认"
    reset.pressed.connect(func() -> void:
        _settings = profile.duplicate(true) as Profile
        panel.profile = _settings
        _changed())
    box.add_child(reset)
    world.cache_coordinator.add_settings(box)
    var back: Button = Button.new()
    back.text = "返回暂停菜单"
    back.custom_minimum_size.y = 64
    back.pressed.connect(func() -> void: world.pause_menu.close_settings())
    frame.add_child(back)
    _menu.hide()
    if not InputMap.has_action("shading_settings"):
        InputMap.add_action("shading_settings")
        var key: InputEventKey = InputEventKey.new()
        key.physical_keycode = KEY_F6
        InputMap.action_add_event("shading_settings",key)

func _input(event: InputEvent) -> void:
    if world != null and event.is_action_pressed("shading_settings") and not event.is_echo():
        world.pause_menu.open_settings()
        get_viewport().set_input_as_handled()

## Pause menu owns input and pause state; this view only exposes its controls.
func set_settings_visible(value: bool) -> void:
    _menu.visible = value
    if value:
        await get_tree().process_frame
        if _menu.visible:
            panel.category.grab_focus()
            var scroll: ScrollContainer = panel.category.get_parent().get_parent() as ScrollContainer
            scroll.scroll_vertical = 0

func _changed() -> void:
    _apply_lighting()
    panel.sync(_settings)
    var error: Error = _settings.save_settings(settings_path)
    if error != OK: push_error("Could not save shading settings: " + error_string(error))

func _exit_tree() -> void:
    if world != null:
        Engine.max_fps = _previous_max_fps
        DisplayServer.window_set_vsync_mode(_previous_vsync)

## Settings changes only; daily animation must never reapply renderer configuration.
func _apply_lighting() -> void:
    Engine.max_fps = _settings.max_fps
    if _sun == null: return
    _sun.visible = _settings.direct_enabled
    _sun.shadow_enabled = _settings.shadows_enabled and _settings.direct_enabled
    _sun.directional_shadow_max_distance = _settings.shadow_distance
    _sky_material.set_shader_parameter("enhanced", _settings.sky_enhanced)
    _sky_material.set_shader_parameter("celestial_mode", _settings.celestial_mode)
    _sky_material.set_shader_parameter("celestial_shape", _settings.celestial_shape)
    _sky_material.set_shader_parameter("sun_radius", deg_to_rad(_settings.celestial_sun_size * 0.5))
    _sky_material.set_shader_parameter("moon_radius", deg_to_rad(_settings.celestial_moon_size * 0.5))
    _sky_material.set_shader_parameter("disc_edge", deg_to_rad(_settings.celestial_edge))
    _sky_material.set_shader_parameter("halo_strength", _settings.celestial_halo)
    _sky_material.set_shader_parameter("sun_tint", _settings.celestial_sun_color)
    _sky_material.set_shader_parameter("moon_tint", _settings.celestial_moon_color)
    _sky_material.set_shader_parameter("sun_energy", _settings.celestial_sun_energy)
    _sky_material.set_shader_parameter("moon_energy", _settings.celestial_moon_energy)
    _sky_material.set_shader_parameter("sun_texture", preload("res://game/shading/assets/celestial/sun.svg") if _settings.celestial_shape == 0 else preload("res://game/shading/assets/celestial/sun_square.svg"))
    _sky_material.set_shader_parameter("moon_texture", preload("res://game/shading/assets/celestial/moon.svg") if _settings.celestial_shape == 0 else preload("res://game/shading/assets/celestial/moon_square.svg"))
    _cloud_profile = _settings.duplicate() as Profile
    _apply_modules()
    _update_weather()
    _update_daylight()
    planar.apply(_settings,_environment)

## Only values driven by time/weather; no resource allocation or quality configuration.
func _update_daylight() -> void:
    var solar_angle: float = (_settings.hour - 6.0) * PI / 12.0
    var altitude: float = sin(solar_angle)
    var moon: bool = altitude < 0.0
    _sun.rotation = Vector3(-solar_angle + (PI if moon else 0.0), -0.5, 0.0)
    var palette: Dictionary[String, Variant] = Palette.sample(_settings)
    var overcast: float = weather.cloud_weight
    _sun.light_color = palette.direct
    _sun.light_energy = pow(absf(altitude), 0.4) * float(palette.energy) * lerpf(1.0,0.35,overcast)
    var zenith: Color = palette.zenith
    var horizon: Color = palette.horizon
    zenith = zenith.lerp(Color(0.19,0.23,0.28),overcast*0.8)
    horizon = horizon.lerp(Color(0.32,0.36,0.4),overcast*0.8)
    _sky_material.set_shader_parameter("zenith",zenith)
    _sky_material.set_shader_parameter("horizon",horizon)
    var sun_direction: Vector3 = Basis.from_euler(Vector3(-solar_angle,-0.5,0.0)).z.normalized()
    _sky_material.set_shader_parameter("sun_direction", sun_direction)
    _sky_material.set_shader_parameter("moon_direction", -sun_direction)
    _fog_color = (palette.fog as Color).lerp(Color(0.32,0.36,0.4),overcast*0.8)
    for material: ShaderMaterial in materials:
        material.set_shader_parameter("sky_color",palette.ambient)
    for material: ShaderMaterial in water_materials:
        material.set_shader_parameter("sky_color",palette.ambient)
        material.set_shader_parameter("horizon",horizon)
    clouds.update_lighting(horizon,_sun.global_basis.z.normalized())
    WaterBinding.apply(water_materials,_settings,_sky_material,horizon.lerp(Color.WHITE,0.5))
    _apply_fog()
    planar.update_atmosphere(_environment)

func _update_weather() -> void:
    _cloud_profile.cloud_coverage = lerpf(_settings.cloud_coverage,_settings.weather_cloud,weather.cloud_weight)
    clouds.apply(_cloud_profile,Color.WHITE,_sun.global_basis.z.normalized())
    for material: ShaderMaterial in plants:
        material.set_shader_parameter("wind_strength",_settings.wind_strength*lerpf(1.0,_settings.weather_wind,weather.cloud_weight))


## Swap the mesher dependency to invalidate warm meshes and reject old task results.
## Logical voxels, lighting and persistence are unaffected by this appearance change.
func _apply_foliage() -> void:
    var mode: int = _settings.foliage_mode
    if mode == _foliage_mode: return
    if mode > 0 and _foliage_mode > 0:
        for model: VoxelBlockyModel in world.content.library.models:
            if Foliage.is_foliage(model): Foliage.apply_material(model.get_material_override(0), mode)
    else:
        var library: VoxelBlockyLibrary = Foliage.with_mode(world.content.library, mode)
        world.content.library = library
        var mesher: VoxelMesherBlocky = world.terrain.mesher.duplicate() as VoxelMesherBlocky
        mesher.library = library
        world.terrain.mesher = mesher
    _foliage_mode = mode

func _apply_modules() -> void:
    _apply_foliage()
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if _settings.vsync_enabled else DisplayServer.VSYNC_DISABLED)
    get_viewport().use_taa = _settings.aa_mode == 2
    get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if _settings.aa_mode == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
    _sun.shadow_bias = _settings.shadow_bias
    _sun.shadow_normal_bias = _settings.shadow_normal_bias
    _sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
    _sun.directional_shadow_blend_splits = true
    _sun.shadow_blur = 1.0 if _settings.hard_shadows else maxf(_settings.shadow_blur,0.001)
    var qualities: Array[RenderingServer.ShadowQuality] = [RenderingServer.SHADOW_QUALITY_SOFT_LOW,RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,RenderingServer.SHADOW_QUALITY_SOFT_HIGH,RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,RenderingServer.SHADOW_QUALITY_SOFT_ULTRA]
    var quality: int = RenderingServer.SHADOW_QUALITY_HARD if _settings.hard_shadows else qualities[_settings.shadow_quality]
    RenderingServer.directional_soft_shadow_filter_set_quality(quality)
    RenderingServer.positional_soft_shadow_filter_set_quality(quality)
    RenderingServer.directional_shadow_atlas_set_size(1024 << _settings.shadow_resolution,false)
    _environment.ambient_light_energy = _settings.ambient_strength
    _environment.glow_enabled = _settings.bloom_enabled
    _environment.glow_intensity = _settings.bloom_strength
    _environment.adjustment_enabled = true
    _environment.adjustment_saturation = _settings.color_saturation
    _environment.adjustment_contrast = _settings.color_contrast
    _local_fog.visible = _settings.rays_mode == 2 and _settings.volume_local_density > 0.0
    (_local_fog.material as FogMaterial).density = _settings.volume_local_density
    (_local_fog.material as FogMaterial).albedo = _settings.volume_albedo
    effects.apply(_settings,_camera,_environment,_sun)
    weather.apply(_settings)
    moving.apply(_settings)
    for material: ShaderMaterial in materials:
        for key: StringName in [&"light_filter_mode",&"block_smoothing",&"block_response_mode",&"ambient_smoothing",&"ambient_strength",&"ambient_minimum",&"ambient_minimum_color",&"ambient_curve",&"block_grid_strength",&"block_color",&"block_energy",&"block_curve"]:
            material.set_shader_parameter(key,_settings.get(key))
        material.set_shader_parameter("indirect_strength",_settings.effective_block_strength())
        material.set_shader_parameter("ao_strength",_settings.ao_strength if _settings.ao_enabled else 0.0)
        material.set_shader_parameter("emission_multiplier",_settings.lamp_emission_strength)
        material.set_shader_parameter("material_metallic",_settings.gloss_block_metallic if _settings.gloss_enabled else 0.0)
        material.set_shader_parameter("material_roughness",_settings.gloss_block_roughness if _settings.gloss_enabled else 1.0)
        material.set_shader_parameter("material_specular",_settings.gloss_block_specular if _settings.gloss_enabled else 0.0)
    for material: ShaderMaterial in plants:
        material.set_shader_parameter("wind_enabled",_settings.wind_enabled)
        material.set_shader_parameter("translucency",_settings.translucency_strength if _settings.translucency_enabled else 0.0)
    _apply_water()
    _allocate_lights()

func _apply_water() -> void:
    for material: ShaderMaterial in water_materials:
        var shader: Shader = preload("res://game/shading/shaders/water.gdshader")
        if _settings.water_reflection_mode == 1: shader = preload("res://game/shading/shaders/water_reflective.gdshader")
        if _settings.water_reflection_mode == 2: shader = preload("res://game/shading/shaders/water_planar.gdshader")
        if material.shader != shader: material.shader = shader
        for key: StringName in [&"water_shallow_color",&"water_deep_color",&"water_absorption",&"water_opacity",&"water_low_opacity",&"water_roughness",&"water_specular",&"wave_scale",&"water_sky_strength",&"water_ssr_strength",&"water_ssr_steps",&"water_ssr_distance",&"water_ssr_tolerance",&"water_ssr_edge_fade",&"water_ssr_refinements",&"water_ssr_normal_offset",&"planar_strength",&"planar_distortion",&"planar_blur_pixels",&"planar_edge_fade",&"wave_strength"]:
            material.set_shader_parameter(key,_settings.get(key))
        material.set_shader_parameter("water_visible",_settings.water_enabled)
        material.set_shader_parameter("depth_absorption",_settings.water_quality == 1)
        material.set_shader_parameter("waves_enabled",_settings.waves_enabled)
        material.set_shader_parameter("reflection_enabled",_settings.water_reflection)
        material.set_shader_parameter("water_bounds_min",world.terrain.bounds.position)
        material.set_shader_parameter("water_bounds_max",Vector3(world.terrain.bounds.end.x,world.WATER_SURFACE_HEIGHT,world.terrain.bounds.end.z))

func _apply_fog() -> void:
    preload("res://game/shading/gdscript/distance_fog.gd").apply(_environment, _settings, _underwater, _fog_color)
    _underwater_tint.apply(_settings, _underwater)
