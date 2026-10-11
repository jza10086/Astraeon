extends Node3D
## MakeUp-style shafts use their own sun-view occlusion capture, not Godot's private atlas.
## This extra scene render is explicit and disabled outside mode 3.
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
const Rays: Script = preload("res://game/shading/gdscript/makeup_rays.gd")
var effect: Rays = Rays.new()
var capture_effect: Rays = Rays.new()
var viewport: SubViewport
var camera: Camera3D
var captures: int = 0
var _source: Camera3D
var _previous_vp: Projection = Projection.IDENTITY
var _previous_transform: Transform3D
var _signature: Array = []
var _frame: int = 0

func configure(source: Camera3D) -> void:
    _source = source
    viewport = SubViewport.new()
    viewport.name = "ShaftOcclusionCapture"
    viewport.world_3d = source.get_world_3d()
    viewport.use_hdr_2d = true
    viewport.size = Vector2i(1024,1024)
    viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
    add_child(viewport)
    camera = Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.near = 0.01
    camera.far = 768.0
    camera.attributes = CameraAttributesPractical.new()
    camera.environment = Environment.new()
    camera.environment.background_mode = Environment.BG_COLOR
    camera.environment.background_color = Color.WHITE
    camera.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    camera.environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
    camera.environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
    viewport.add_child(camera)
    camera.current = true
    capture_effect.capture = true
    capture_effect.enabled = true
    var compositor: Compositor = Compositor.new()
    compositor.compositor_effects = [capture_effect]
    camera.compositor = compositor

func _matrix(values: PackedFloat32Array, matrix: Projection) -> void:
    for column: int in range(4):
        for row: int in range(4): values.append(matrix[column][row])

func tick(p: Profile, sun: DirectionalLight3D, clouds: Node3D, rain: float) -> void:
    effect.enabled = p.rays_mode in [1,3] and p.direct_enabled and p.rays_strength > 0.0
    var active: bool = effect.enabled and p.rays_mode == 3
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
    if not effect.enabled: return
    var direction: Vector3 = sun.global_basis.z.normalized()
    if active:
        var resolution: int = 512 << p.shaft_shadow_resolution
        viewport.size = Vector2i(resolution,resolution)
        camera.size = p.shaft_shadow_range
        camera.far = maxf(768.0,p.shaft_shadow_range*3.0)
        camera.cull_mask = _source.cull_mask & ~((1<<19)|(1<<18)|(1<<16))
        var center: Vector3 = _source.global_position-_source.global_basis.z*p.shaft_distance*0.25
        var local: Vector3 = sun.global_basis.inverse()*center
        var texel: float = p.shaft_shadow_range/resolution
        local.x = snappedf(local.x,texel)
        local.y = snappedf(local.y,texel)
        local.z = snappedf(local.z,1.0)
        camera.global_transform = Transform3D(sun.global_basis,sun.global_basis*local+direction*camera.far*0.5)
        captures += 1
    var values: PackedFloat32Array = PackedFloat32Array()
    _matrix(values,_source.get_camera_projection().inverse())
    _matrix(values,Projection(_source.global_transform))
    _matrix(values,Projection(camera.global_transform.affine_inverse()))
    _matrix(values,_previous_vp)
    var target: Vector3 = _source.global_position+direction*1000.0
    var uv: Vector2 = _source.unproject_position(target)/_source.get_viewport().get_visible_rect().size
    var valid: float = 0.0 if _source.is_position_behind(target) else 1.0
    var sun_strength: float = clampf(sun.light_energy/1.8,0.0,1.0)
    var tint: Color = sun.light_color.srgb_to_linear()*1.2
    values.append_array(PackedFloat32Array([
        direction.x,direction.y,direction.z,p.rays_strength*sun_strength,
        uv.x,uv.y,valid,1.0-rain*p.shaft_weather_fade,
        p.rays_mode,p.shaft_steps if active else p.rays_steps,p.shaft_distance,p.shaft_distribution,
        tint.r,tint.g,tint.b,p.shaft_contrast,
        p.rays_radius,p.rays_decay,p.rays_edge,p.shaft_direction_power,
        p.shaft_shadow_range,camera.far,p.shaft_shadow_bias,1,
        clouds.offset.x,clouds.offset.y,768,90,
        p.shaft_cloud_strength if p.clouds_enabled else 0.0,p.shaft_history if p.shaft_temporal else 0.0,0,_frame % 16,
        _previous_transform.origin.x,_previous_transform.origin.y,_previous_transform.origin.z,0.2]))
    var signature: Array = [p.rays_mode,p.rays_steps,p.shaft_steps,p.rays_strength,p.shaft_cloud_strength,p.cloud_coverage,p.shaft_shadow_range,p.shaft_shadow_resolution]
    var reset: bool = signature != _signature or _source.global_position.distance_to(_previous_transform.origin)>2.0 or _source.global_basis.z.dot(_previous_transform.basis.z)<0.95
    values[94] = 1.0 if reset or _frame == 0 else 0.0
    values[95] = _frame % 16 if p.shaft_temporal else 0
    _signature = signature
    _frame += 1
    _previous_vp = _source.get_camera_projection()*Projection(_source.global_transform.affine_inverse())
    _previous_transform = _source.global_transform
    var cloud_rid: RID = clouds.mask.get_rid() if clouds.mask != null else RID()
    effect.publish(values,p.rays_resolution,viewport.get_texture().get_rid() if active else RID(),cloud_rid)
    if active: capture_effect.publish(values,1.0,RID(),RID())
