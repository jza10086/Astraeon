extends SceneTree
## Offline build/deploy used by development and export validation, never by game startup.
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var manifest: Resource = load("res://game/data/content/authoring/astraeon/pack.tres")
	var compiler: RefCounted = load("res://tools/content/compiler.gd").new()
	var result: Dictionary = compiler.build(manifest, "res://game/data/content/packages/astraeon.aebpack")
	if result.has("error"):
		printerr(result)
		quit(1)
		return
	var error: Error = OK
	print("BUILTIN_CONTENT_DONE ", result, " deploy=", error)
	quit(0 if error == OK else 1)
