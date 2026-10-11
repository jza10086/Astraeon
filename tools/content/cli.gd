extends SceneTree
## godot --headless --path <project> --script res://tools/content/cli.gd -- build <manifest.tres> <output.aebpack>
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2 or args[0] not in ["build", "validate", "inspect"]:
		printerr("Usage: validate <manifest> | build <manifest> <output.aebpack> | inspect <pack>")
		quit(2)
		return
	var result: Dictionary
	if args[0] == "inspect":
		if not ClassDB.class_exists("AstraeonContentPack"):
			printerr("Content compiler DLL not loaded")
			quit(2)
			return
		var reader: RefCounted = ClassDB.instantiate("AstraeonContentPack")
		result = reader.call("open_pack", args[1])
	else:
		if args[0] == "build" and args.size() != 3:
			printerr("build requires output path")
			quit(2)
			return
		var manifest: Resource = load(args[1])
		var compiler: RefCounted = preload("res://tools/content/compiler.gd").new()
		result = compiler.build(manifest, args[2] if args.size() > 2 else "", args[0] == "validate")
	print(JSON.stringify(result, "  "))
	quit(1 if result.has("error") else 0)
