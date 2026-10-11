extends SceneTree
var scene: Node3D
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1920, 1080)
	for path: String in ["res://test/shading/scenes/content_sample.tscn", "res://test/shading/scenes/shading_sample.tscn"]:
		scene = load(path).instantiate()
		if path.ends_with("shading_sample.tscn"):
			scene.settings_path = "res://tmp/content/no-settings.cfg"
		root.add_child(scene)
		if path.ends_with("shading_sample.tscn"): scene._start()
		var start: int = Time.get_ticks_msec()
		while Time.get_ticks_msec() - start < 90000:
			await process_frame
			if path.ends_with("content_sample.tscn") and Time.get_ticks_msec() - start > 2000: break
			if path.ends_with("shading_sample.tscn") and scene._uploaded_revision == scene._volume.revision and scene._sections.pending_count() == 0: break
		if path.ends_with("shading_sample.tscn") and scene._uploaded_revision != scene._volume.revision:
			printerr("Shading sample did not converge")
			quit(1)
			return
		for frame: int in range(10): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tmp/content/" + path.get_file().get_basename() + ".png")
		print("CONTENT_RENDER_CAPTURE ", path)
		scene.queue_free()
		await process_frame
	print("CONTENT_RENDER_DONE")
	quit()
