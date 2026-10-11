extends RefCounted
## Opt-in graphical regression, no save/settings writes and no performance benchmark.
var checks: int = 0
var failures: int = 0
var rows: PackedStringArray = []
func _check(ok: bool, message: String) -> void:
    checks += 1
    if not ok: failures += 1
    rows.append("| %s | %s |" % [message,"PASS" if ok else "FAIL"])
    print("WATER_RAYS ", "PASS " if ok else "FAIL ",message)
func _frames(sample: Node, count: int = 40) -> void:
    for index: int in range(count): await sample.get_tree().process_frame
    await RenderingServer.frame_post_draw
func _shot(sample: Node, name: String) -> Image:
    await RenderingServer.frame_post_draw
    var image: Image = sample.get_viewport().get_texture().get_image()
    image.save_png("res://tmp/water_rays/"+name+".png")
    image.resize(64,36,Image.INTERPOLATE_BILINEAR)
    return image
func _difference(a: Image, b: Image) -> float:
    var total: float = 0.0
    for y: int in range(36):
        for x: int in range(16,64):
            var first: Color = a.get_pixel(x,y)
            var second: Color = b.get_pixel(x,y)
            total += absf(first.r-second.r)+absf(first.g-second.g)+absf(first.b-second.b)
    return total/(48.0*36.0*3.0)
func run(sample: Node3D) -> void:
    DirAccess.make_dir_recursive_absolute("res://tmp/water_rays")
    var saved: Resource = sample._settings.duplicate()
    var transform: Transform3D = sample._camera.global_transform
    var p: Resource = sample._settings
    p.set("cycle_enabled",false)
    p.set("avatar_animate",false)
    p.set("cloud_speed",0.0)
    p.set("hour",16.6)
    p.set("rays_mode",0)
    sample._apply_lighting()
    sample._view(Vector3(20,2,25),Vector3(65,38,-57))
    await _frames(sample)
    var off: Image = await _shot(sample,"shafts_off")
    p.set("rays_mode",1)
    sample._apply_lighting()
    await _frames(sample)
    var depth: Image = await _shot(sample,"makeup_depth")
    _check(_difference(off,depth)>0.001,"Depth shafts alter the rendered image")
    var captures: int = sample._extensions.shafts.captures
    await _frames(sample,5)
    _check(captures==sample._extensions.shafts.captures,"Depth shafts do not render the shadow capture")
    p.set("rays_mode",3)
    sample._apply_lighting()
    await _frames(sample)
    var volume: Image = await _shot(sample,"makeup_volume")
    _check(_difference(off,volume)>0.001,"Volumetric shafts alter the rendered image")
    _check(sample._extensions.shafts.captures>captures,"Volumetric shafts update scene occlusion")
    _check(not sample._environment.volumetric_fog_enabled,"MakeUp volume does not enable global volumetric fog")
    _check(not sample._extensions.shafts.effect._failed and not sample._extensions.shafts.capture_effect._failed,"Both GPU programs compile")
    p.set("rays_mode",0)
    sample._apply_lighting()
    await _frames(sample)
    captures = sample._extensions.shafts.captures
    await _frames(sample,5)
    _check(captures==sample._extensions.shafts.captures and not sample._extensions.shafts.effect.enabled,"Off stops dedicated work")
    sample._view(Vector3(20,3,-5),Vector3(20,0,-20))
    p.set("hour",12.0)
    p.set("wave_speed",0.0)
    p.set("water_reflection_mode",1)
    p.set("water_refraction",true)
    sample._apply_lighting()
    await _frames(sample)
    await _shot(sample,"water_ssr")
    _check(sample._details.water_materials[0].get_shader_parameter("water_refraction"),"Water refraction binding")
    p.set("water_refraction",false)
    p.set("water_reflection_mode",0)
    sample._apply_lighting()
    await _frames(sample)
    await _shot(sample,"water_sky")
    p.set("water_reflection_mode",2)
    sample._apply_lighting()
    await _frames(sample)
    await _shot(sample,"water_planar")
    _check(sample._planar._valid,"Planar reflection remains valid")
    sample._view(Vector3(23,-2,-14),Vector3(25,-2,-22))
    await _frames(sample)
    await _shot(sample,"water_underwater")
    _check(sample._underwater,"Underwater transition still works")
    sample._view(Vector3(23,3,-14),Vector3(25,0,-22))
    await _frames(sample)
    _check(not sample._underwater,"Leaving water restores atmosphere")
    sample._settings = saved
    sample._camera.global_transform = transform
    sample._apply_lighting()
    var report: FileAccess = FileAccess.open("res://tmp/water_rays/results.md",FileAccess.WRITE)
    report.store_string("# Water and light shafts graphical regression\n\nNo formal performance measurements.\n\n| Check | Result |\n|---|---|\n"+ "\n".join(rows)+"\n\nChecks: %d; failures: %d.\n" % [checks,failures])
    print("WATER_RAYS_DONE checks=",checks," failures=",failures)
