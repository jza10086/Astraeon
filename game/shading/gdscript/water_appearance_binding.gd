extends RefCounted
## Shared water controls and sky uniforms for the world and the lighting fixture.
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
static var _noise: NoiseTexture2D
static func apply(materials: Array[ShaderMaterial], p: Profile, sky: ShaderMaterial, cloud_color: Color) -> void:
    if _noise == null:
        _noise = NoiseTexture2D.new()
        _noise.width = 256
        _noise.height = 256
        _noise.seamless = true
        _noise.as_normal_map = true
        _noise.bump_strength = 5.0
        _noise.generate_mipmaps = true
        var noise: FastNoiseLite = FastNoiseLite.new()
        noise.seed = 59127
        noise.frequency = 0.045
        noise.fractal_octaves = 3
        _noise.noise = noise
    for material: ShaderMaterial in materials:
        material.set_shader_parameter("water_noise",_noise)
        for key: StringName in [&"wave_normal_strength",&"wave_detail_strength",&"wave_detail_scale",&"wave_direction",&"wave_fade_distance",&"water_fresnel",&"water_sky_visibility",&"water_refraction",&"water_refraction_strength",&"water_refraction_edge",&"water_cloud_reflection"]:
            material.set_shader_parameter(key,p.get(key))
        for key: StringName in [&"zenith",&"horizon",&"enhanced",&"celestial_mode",&"celestial_shape",&"sun_direction",&"moon_direction",&"sun_radius",&"moon_radius",&"disc_edge",&"halo_strength",&"sun_tint",&"moon_tint",&"sun_energy",&"moon_energy",&"sun_texture",&"moon_texture"]:
            material.set_shader_parameter(key,sky.get_shader_parameter(key))
        material.set_shader_parameter("water_clouds_visible",p.clouds_enabled)
        material.set_shader_parameter("water_cloud_color",cloud_color)
