extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var records: Array[Dictionary] = []
	for count: int in [100, 500, 1000]:
		var source: Array[AstraeonBlockDefinition] = []
		for index: int in range(count):
			var block: AstraeonBlockDefinition = AstraeonBlockDefinition.new()
			block.key = StringName("scale:block_%04d" % index)
			block.appearance = AstraeonBlockAppearance.new()
			block.appearance.default_surface = AstraeonBlockSurface.new()
			var image: Image = Image.create(32,32,false,Image.FORMAT_RGBA8)
			image.fill(Color.from_hsv(float(index)/count,0.7,0.8))
			image.set_pixel(0,0,Color(float(index%256)/255,float(index/256)/255,1))
			block.appearance.default_surface.albedo_texture = ImageTexture.create_from_image(image)
			source.append(block)
		var models: Array[VoxelBlockyModel] = []
		var start: int = Time.get_ticks_usec()
		for block: AstraeonBlockDefinition in source:
			models.append(preload("res://test/content/gdscript/reference_block_builder.gd").build_block(block,Basis.IDENTITY))
		var old_ms: float = (Time.get_ticks_usec()-start)/1000.0
		models.clear()
		await process_frame
		var content: AstraeonWorldContent = AstraeonWorldContent.new()
		start = Time.get_ticks_usec()
		if not content.build(PackedStringArray(["res://tmp/content/scale_%d_preload.aebpack" % count])):
			printerr(content.error)
			quit(1)
			return
		var new_ms: float = (Time.get_ticks_usec()-start)/1000.0
		var record: Dictionary = {"states":count,"old_runtime_atlas_ms":old_ms,"new_metadata_models_ms":new_ms,"new_runtime_source_pixels":0,"old_color_orm_pixel_bytes":count*32*32*6*7,"new_color_pixel_bytes":count*32*32*6*4}
		records.append(record)
		print("CONTENT_COMPARE ",JSON.stringify(record))
		content.bundle.shutdown()
		await process_frame
	var file: FileAccess = FileAccess.open("res://tmp/content/compare.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"  "))
	print("CONTENT_COMPARE_DONE")
	quit()
