extends SceneTree
var world: Node3D
var results: Array[Dictionary] = []
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1920, 1080)
	world = load("res://game/core/main.tscn").instantiate()
	world.world_directory = "res://tmp/content/movement_" + str(Time.get_ticks_usec())
	world.shading_settings_path = "res://tmp/content/no-settings.cfg"
	world.horizontal_distance = 64
	world.content_packages = PackedStringArray(["res://game/data/content/packages/astraeon.aebpack", "res://tmp/content/example_sdk.aebpack"])
	preload("res://test/survival/gdscript/world_fixture.gd").prepare(world)
	root.add_child(world)
	var deadline: int = Time.get_ticks_msec() + 90000
	while not world.ready_to_play and Time.get_ticks_msec() < deadline:
		await process_frame
	if not world.ready_to_play:
		printerr("Content movement startup timeout")
		quit(1)
		return
	world.controller.set_physics_process(false)
	world.player.set_physics_process(false)
	var origin: Vector3 = world.player.global_position + Vector3(0, 8, 0)
	var rare: int = world.content.state_keys.find("example:leaves/default")
	for x: int in [-16, 16]:
		world.set_block(Vector3i(origin) + Vector3i(x, -8, 0), rare)
	for frame: int in range(120): await process_frame
	for speed: float in [0.0, 8.0, 22.0, 40.0]:
		var times: Array[float] = []
		var started: int = Time.get_ticks_usec()
		var last: int = started
		var before: Dictionary = world.content.bundle.visuals.get_metrics()
		while Time.get_ticks_usec() - started < 10000000:
			var t: float = (Time.get_ticks_usec() - started) / 1000000.0
			var distance: float = speed * (t if t < 5 else 10-t)
			world.player.global_position = origin + Vector3(distance, 0, 0)
			world.player.velocity = Vector3(speed if t < 5 else -speed, 0, 0)
			world.camera.rotation.y = t * 0.3
			await process_frame
			var now: int = Time.get_ticks_usec()
			times.append((now-last)/1000.0)
			last = now
		times.sort()
		var sum: float = 0.0
		for frame: float in times: sum += frame
		var slow: int = maxi(1, ceili(times.size()*0.01))
		var worst: float = 0.0
		for index: int in range(times.size()-slow,times.size()): worst += times[index]
		var after: Dictionary = world.content.bundle.visuals.get_metrics()
		var result: Dictionary = {"speed":speed,"frames":times.size(),"fps":1000.0*times.size()/sum,"low_1_percent":1000.0*slow/worst,"p99_ms":times[mini(times.size()-1,int(times.size()*0.99))],"max_ms":times[-1],"visual_before":before,"visual_after":after,"cache":world.cache_coordinator.metrics}
		results.append(result)
		print("CONTENT_MOVEMENT_CASE ",JSON.stringify(result))
	var file: FileAccess = FileAccess.open("res://tmp/content/movement.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"  "))
	file.close()
	await world.save_world(false)
	world.queue_free()
	for frame: int in range(3): await process_frame
	print("CONTENT_MOVEMENT_DONE")
	quit()
