class_name AstraeonWorldShading
extends Node3D
## Scene-local assembly. Terrain is authoritative; worker input is an immutable disposable snapshot.
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
const Palette: Script = preload("res://game/shading/gdscript/day_palette.gd")
const Clouds: Script = preload("res://game/shading/gdscript/block_clouds.gd")
const Weather: Script = preload("res://game/shading/gdscript/weather_effects.gd")
const Glass: Script = preload("res://game/shading/gdscript/colored_shadows.gd")
const Moving: Script = preload("res://game/shading/gdscript/moving_light.gd")
const Budget: Script = preload("res://game/shading/gdscript/light_budget.gd")
const Effects: Script = preload("res://game/shading/gdscript/camera_effects.gd")
const Post: Script = preload("res://game/shading/gdscript/camera_post.gd")
const Planar: Script = preload("res://game/shading/gdscript/planar_reflection.gd")
const SettingsPanel: Script = preload("res://game/shading/gdscript/settings_panel.gd")
@export var profile: Profile = preload("res://game/shading/resources/default_profile.tres")
@export var settings_path: String = "user://settings.cfg"
var world: Node3D
var _settings: Profile
var _camera: Camera3D
var _sun: DirectionalLight3D
var _environment: Environment
var _sky_material: ShaderMaterial
var _fog_color: Color
var _underwater: bool = false
var materials: Array[ShaderMaterial] = []
var plants: Array[ShaderMaterial] = []
var water_materials: Array[ShaderMaterial] = []
var clouds: Clouds = Clouds.new()
var weather: Weather = Weather.new()
var glass: Glass = Glass.new()
var moving: Moving = Moving.new()
var budget: Budget = Budget.new()
var effects: Effects = Effects.new()
var motion: Post = Post.new()
var post: Post = Post.new()
var planar: Planar = Planar.new()
var panel: SettingsPanel = SettingsPanel.new()
var _menu: PanelContainer
var _fps: Label
var _worker: Thread
var _dirty: bool = true
var _timer: float = 0.0
var _clock: float = 0.0
var _water_clock: float = 0.0
var _cloud_clock: float = 0.0
var _origin: Vector3i
var _requested_origin: Vector3i
var _size: Vector3i
var _texture: ImageTexture3D
var _viewer: VoxelViewer
var _revision: int = 0
var field_publications: int = 0
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
    glass.configure(receivers)
    planar.water_height = world.WATER_SURFACE_HEIGHT
    planar.configure(_camera,water_materials,materials)
    _local_fog.size = Vector3(24,16,24)
    _local_fog.material = FogMaterial.new()
    add_child(_local_fog)
    motion.configure_stage(true)
    post.configure_stage(false)
    var compositor: Compositor = Compositor.new()
    compositor.compositor_effects = [motion,post]
    _camera.compositor = compositor
    _camera.far = maxf(_camera.far,1600.0)
    _previous_camera = _camera.global_transform
    _viewer = VoxelViewer.new()
    _viewer.requires_visuals = false
    _viewer.requires_collisions = false
    _viewer.view_distance = world.horizontal_distance + 32
    _viewer.view_distance_vertical_ratio = 144.0 / _viewer.view_distance
    add_child(_viewer)
    _size = Vector3i((world.horizontal_distance+32)*2,256,(world.horizontal_distance+32)*2)
    _size.x = ceili(_size.x/16.0)*16
    _size.z = ceili(_size.z/16.0)*16
    world.terrain.block_loaded.connect(_invalidate_block)
    world.terrain.block_unloaded.connect(_invalidate_block)
    _make_ui()
    _apply_lighting()

func _compile_materials() -> void:
    var content: AstraeonWorldContent = world.content
    for index: int in range(1,content.library.models.size()):
        var model: VoxelBlockyModel = content.library.models[index]
        var material: ShaderMaterial = ShaderMaterial.new()
        if index == content.water_id:
            material.shader = preload("res://game/shading/shaders/water.gdshader")
            water_materials.append(material)
        else:
            var source: ORMMaterial3D = model.get_material_override(0) as ORMMaterial3D
            var plant: bool = source.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
            material.shader = preload("res://game/shading/shaders/plant.gdshader") if plant else preload("res://game/shading/shaders/voxel_light.gdshader")
            material.set_shader_parameter("use_block_atlas",true)
            material.set_shader_parameter("base_color",Color.WHITE)
            material.set_shader_parameter("block_atlas",source.albedo_texture)
            material.set_shader_parameter("block_cutout",plant)
            material.set_shader_parameter("block_alpha_cutoff",source.alpha_scissor_threshold)
            material.set_shader_parameter("authored_surface",true)
            material.set_shader_parameter("authored_orm",source.orm_texture)
            material.set_shader_parameter("authored_specular",source.metallic_specular)
            material.set_shader_parameter("authored_emission",source.emission_texture)
            material.set_shader_parameter("authored_emission_energy",source.emission_energy_multiplier if source.emission_enabled else 0.0)
            if plant: plants.append(material)
            materials.append(material)
        model.set_material_override(0,material)
    content.library.bake()

## Initial gameplay readiness includes the latest loaded-data publication.
func is_ready() -> bool:
    return field_publications > 0 and not _dirty and _worker == null

func invalidate() -> void:
    _dirty = true

func _invalidate_block(_position: Vector3i) -> void:
    invalidate()

func _solve(snapshot: Dictionary) -> Dictionary:
    var solver: AstraeonLightField = AstraeonLightField.new()
    return solver.solve(snapshot.buffer,snapshot.opacity,snapshot.emission,snapshot.sources,snapshot.known,16,snapshot.origin)

func _publish() -> void:
    var result: Dictionary = _worker.wait_to_finish()
    _worker = null
    if result.is_empty():
        push_error("Native shading field failed")
        return
    var texture: ImageTexture3D = ImageTexture3D.new()
    var images: Array[Image] = []
    images.assign(result.images)
    if texture.create(Image.FORMAT_RGBA8,_size.x,_size.y,_size.z,false,images) != OK:
        push_error("Could not allocate world light field")
        return
    _texture = texture
    _origin = _requested_origin
    for material: ShaderMaterial in materials:
        material.set_shader_parameter("light_volume",_texture)
        material.set_shader_parameter("volume_origin",Vector3(_origin))
        material.set_shader_parameter("volume_size",Vector3(_size))
    _revision += 1
    weather.set_surface_map(result.height,Vector2(_origin.x,_origin.z),Vector2(_size.x,_size.z),_revision)
    _emitters = result.emitters
    field_publications += 1
    _allocate_lights()

func _process(delta: float) -> void:
    if world == null: return
    _local_fog.global_position = _camera.global_position
    _clock += delta
    _timer += delta
    _viewer.global_position = Vector3(_camera.global_position.x,64.0,_camera.global_position.z)
    var next_origin: Vector3i = Vector3i(floori(_camera.global_position.x/16.0)*16-_size.x/2,-64,floori(_camera.global_position.z/16.0)*16-_size.z/2)
    if next_origin != _requested_origin: _dirty = true
    if _worker != null and not _worker.is_alive(): _publish()
    if _dirty and _worker == null and _timer >= 0.5:
        _timer = 0.0
        _dirty = false
        _requested_origin = next_origin
        var snapshot: Dictionary = world.capture_shading_snapshot(next_origin,_size)
        _worker = Thread.new()
        if _worker.start(_solve.bind(snapshot)) != OK:
            _worker = null
            push_error("Could not start shading worker")
    if _settings.cycle_enabled:
        _settings.hour = fposmod(_settings.hour+delta*24.0/_settings.day_seconds,24.0)
        _apply_lighting()
    if weather.tick(delta,_settings,_camera.global_position): _apply_lighting()
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
    if _settings.dof_mode == 2:
        var hit: VoxelRaycastResult = world.voxel_tool.raycast(_camera.global_position,-_camera.global_basis.z,100.0)
        effects.update_focus(_settings,hit.distance if hit != null else 100.0,delta)
    _fps.visible = _settings.show_fps
    _fps.text = "%d FPS · %.2f ms | F6 光影设置 | 光照发布 %d" % [Engine.get_frames_per_second(),1000.0/maxf(Engine.get_frames_per_second(),1),field_publications]

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
    add_child(layer)
    _fps = Label.new()
    _fps.position = Vector2(24,130)
    layer.add_child(_fps)
    _menu = PanelContainer.new()
    _menu.position = Vector2(24,180)
    _menu.custom_minimum_size = Vector2(410,580)
    layer.add_child(_menu)
    var scroll: ScrollContainer = ScrollContainer.new()
    _menu.add_child(scroll)
    var box: VBoxContainer = VBoxContainer.new()
    box.custom_minimum_size.x = 380
    scroll.add_child(box)
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
    _menu.hide()
    if not InputMap.has_action("shading_settings"):
        InputMap.add_action("shading_settings")
        var key: InputEventKey = InputEventKey.new()
        key.physical_keycode = KEY_F6
        InputMap.action_add_event("shading_settings",key)

func _input(event: InputEvent) -> void:
    if world != null and event.is_action_pressed("shading_settings"):
        _menu.visible = not _menu.visible
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _menu.visible else Input.MOUSE_MODE_CAPTURED
        world.controller.input_enabled = not _menu.visible
        get_viewport().set_input_as_handled()

func _changed() -> void:
    _apply_lighting()
    panel.sync(_settings)
    var error: Error = _settings.save_settings(settings_path)
    if error != OK: push_error("Could not save shading settings: " + error_string(error))

func _exit_tree() -> void:
    if _worker != null: _worker.wait_to_finish()
    if world != null:
        Engine.max_fps = _previous_max_fps
        DisplayServer.window_set_vsync_mode(_previous_vsync)

func _apply_lighting() -> void:
    Engine.max_fps = _settings.max_fps
    if _sun == null:
        return
    var solar_angle: float = (_settings.hour - 6.0) * PI / 12.0
    var altitude: float = sin(solar_angle)
    var day: float = smoothstep(-0.12, 0.3, altitude)
    var sunset: float = (1.0 - smoothstep(0.05, 0.5, absf(altitude))) * day
    var moon: bool = altitude < 0.0
    _sun.rotation = Vector3(-solar_angle + (PI if moon else 0.0), -0.5, 0.0)
    _sun.visible = _settings.direct_enabled
    var palette: Dictionary[String, Variant] = Palette.sample(_settings)
    var overcast: float = weather.cloud_weight
    _sun.light_color = palette.direct
    _sun.light_energy = pow(absf(altitude), 0.4) * float(palette.energy) * lerpf(1.0,0.35,overcast)
    _sun.shadow_enabled = _settings.shadows_enabled and _settings.direct_enabled
    _sun.directional_shadow_max_distance = _settings.shadow_distance
    var zenith: Color = palette.zenith
    var horizon: Color = palette.horizon
    zenith = zenith.lerp(Color(0.19,0.23,0.28),overcast*0.8)
    horizon = horizon.lerp(Color(0.32,0.36,0.4),overcast*0.8)
    _sky_material.set_shader_parameter("enhanced", _settings.sky_enhanced)
    _sky_material.set_shader_parameter("zenith",zenith)
    _sky_material.set_shader_parameter("horizon",horizon)
    var sun_direction: Vector3 = Basis.from_euler(Vector3(-solar_angle,-0.5,0.0)).z.normalized()
    _sky_material.set_shader_parameter("sun_direction", sun_direction)
    _sky_material.set_shader_parameter("moon_direction", -sun_direction)
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
    _fog_color = (palette.fog as Color).lerp(Color(0.32,0.36,0.4),overcast*0.8)
    _apply_modules(palette.ambient,horizon)


func _apply_modules(sky_color: Color, horizon: Color) -> void:
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
    var cloud_profile: Profile = _settings.duplicate() as Profile
    cloud_profile.cloud_coverage = lerpf(_settings.cloud_coverage,_settings.weather_cloud,weather.cloud_weight)
    clouds.apply(cloud_profile,horizon,_sun.global_basis.z.normalized())
    for material: ShaderMaterial in materials:
        for key: StringName in [&"ambient_smoothing",&"ambient_strength",&"ambient_minimum",&"ambient_minimum_color",&"ambient_curve",&"block_grid_strength",&"block_color",&"block_energy",&"block_curve"]:
            material.set_shader_parameter(key,_settings.get(key))
        material.set_shader_parameter("sky_color",sky_color)
        material.set_shader_parameter("indirect_strength",_settings.effective_block_strength())
        material.set_shader_parameter("ao_strength",_settings.ao_strength if _settings.ao_enabled else 0.0)
        material.set_shader_parameter("emission_multiplier",_settings.lamp_emission_strength)
        material.set_shader_parameter("material_metallic",_settings.gloss_block_metallic if _settings.gloss_enabled else 0.0)
        material.set_shader_parameter("material_roughness",_settings.gloss_block_roughness if _settings.gloss_enabled else 1.0)
        material.set_shader_parameter("material_specular",_settings.gloss_block_specular if _settings.gloss_enabled else 0.0)
    for material: ShaderMaterial in plants:
        material.set_shader_parameter("wind_enabled",_settings.wind_enabled)
        material.set_shader_parameter("wind_strength",_settings.wind_strength*lerpf(1.0,_settings.weather_wind,weather.cloud_weight))
        material.set_shader_parameter("translucency",_settings.translucency_strength if _settings.translucency_enabled else 0.0)
    _apply_water(sky_color,horizon)
    _apply_fog()
    planar.apply(_settings,_environment)
    _allocate_lights()

func _apply_water(sky_color: Color, horizon: Color) -> void:
    for material: ShaderMaterial in water_materials:
        var shader: Shader = preload("res://game/shading/shaders/water.gdshader")
        if _settings.water_reflection_mode == 1: shader = preload("res://game/shading/shaders/water_reflective.gdshader")
        if _settings.water_reflection_mode == 2: shader = preload("res://game/shading/shaders/water_planar.gdshader")
        material.shader = shader
        for key: StringName in [&"water_shallow_color",&"water_deep_color",&"water_absorption",&"water_opacity",&"water_low_opacity",&"water_roughness",&"water_specular",&"wave_scale",&"water_sky_strength",&"water_ssr_strength",&"water_ssr_steps",&"water_ssr_distance",&"water_ssr_tolerance",&"water_ssr_edge_fade",&"water_ssr_refinements",&"water_ssr_normal_offset",&"planar_strength",&"planar_distortion",&"planar_blur_pixels",&"planar_edge_fade",&"wave_strength"]:
            material.set_shader_parameter(key,_settings.get(key))
        material.set_shader_parameter("water_visible",_settings.water_enabled)
        material.set_shader_parameter("depth_absorption",_settings.water_quality == 1)
        material.set_shader_parameter("waves_enabled",_settings.waves_enabled)
        material.set_shader_parameter("reflection_enabled",_settings.water_reflection)
        material.set_shader_parameter("sky_color",sky_color)
        material.set_shader_parameter("horizon",horizon)
        material.set_shader_parameter("water_bounds_min",world.terrain.bounds.position)
        material.set_shader_parameter("water_bounds_max",Vector3(world.terrain.bounds.end.x,world.WATER_SURFACE_HEIGHT,world.terrain.bounds.end.z))

func _apply_fog() -> void:
    _environment.fog_enabled = _settings.fog_enabled or _underwater
    _environment.fog_mode = Environment.FOG_MODE_DEPTH
    _environment.fog_light_color = _settings.underwater_color if _underwater else _fog_color
    _environment.fog_light_energy = 0.6 if _underwater else 1.0
    _environment.fog_sky_affect = 1.0 if _underwater else 0.0
    _environment.fog_depth_begin = 0.0 if _underwater else _settings.fog_start
    _environment.fog_depth_end = _settings.underwater_distance if _underwater else _settings.fog_start + 1.0 / _settings.fog_density
    _environment.fog_depth_curve = 1.0
