extends SceneTree
## Render the real cache panel at each supported canvas size, independent of monitor resolution.
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
    var world: Node3D = (load("res://game/core/main.tscn") as PackedScene).instantiate()
    world.horizontal_distance = 32
    world.world_directory = "res://tmp/cache-ui/world"
    world.shading_settings_path = "res://tmp/cache-ui/settings.cfg"
    world.get_node("Player/Controller").input_enabled = false
    preload("res://test/survival/gdscript/world_fixture.gd").prepare(world)
    root.add_child(world)
    var deadline: int = Time.get_ticks_msec()+60000
    while not world.shading.is_ready() and Time.get_ticks_msec()<deadline: await process_frame
    if not world.shading.is_ready(): failures.append("World did not settle")
    world.controller.set_physics_process(false)
    var menu: Control = world.shading._menu
    var parent: Node = menu.get_parent()
    var viewport: SubViewport = SubViewport.new()
    viewport.transparent_bg = false
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    menu.reparent(viewport)
    menu.show()
    var cache_menu: Control
    for node: Node in menu.find_children("*","VBoxContainer",true,false):
        if node.get_script() != null and node.get_script().resource_path.ends_with("/cache_settings.gd"):
            cache_menu = node as Control
    if cache_menu == null:
        failures.append("Cache settings missing from real F6 menu")
    else:
        cache_menu.body.show()
        await create_timer(0.6).timeout
    var sizes: Array[Vector2i] = [Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160),Vector2i(3440,1440)]
    for size: Vector2i in sizes:
        var scale: float = minf(float(size.x)/1920.0,float(size.y)/1080.0)
        viewport.size = size
        viewport.size_2d_override = Vector2i(Vector2(size)/scale)
        viewport.size_2d_override_stretch = true
        for i: int in range(4): await process_frame
        for node: Node in menu.find_children("*","ScrollContainer",true,false):
            var scroll: ScrollContainer = node as ScrollContainer
            scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
        for i: int in range(4): await process_frame
        if menu.get_global_rect().end.x>viewport.size_2d_override.x+1 or menu.get_global_rect().end.y>viewport.size_2d_override.y+1:
            failures.append("Menu extends outside "+str(size))
        await RenderingServer.frame_post_draw
        viewport.get_texture().get_image().save_png("res://tmp/cache-ui/%dx%d.png" % [size.x,size.y])
    menu.reparent(parent)
    viewport.queue_free()
    world.queue_free()
    for i: int in range(5): await process_frame
    print("CACHE_UI ",JSON.stringify({"failures":failures,"sizes":sizes}))
    quit(0 if failures.is_empty() else 1)
