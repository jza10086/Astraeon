extends SceneTree
var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene: PackedScene = load("res://game/core/main.tscn")
	world = scene.instantiate()
	world.set("world_directory", "res://tmp/natural-startup/" + str(Time.get_ticks_usec()))
	root.add_child(world)
	var deadline: int = Time.get_ticks_msec() + 30000
	while not bool(world.get("ready_to_play")) and Time.get_ticks_msec() < deadline:
		await process_frame
	var ready: bool = bool(world.get("ready_to_play"))
	var stream: AstraeonNativeStream = world.get("stream") as AstraeonNativeStream
	print("NATURAL_STARTUP ready=", ready, " error=", stream.get_last_error())
	if ready and stream.get_last_error().is_empty():
		world.call("save_world", true)
	else:
		quit(1)
