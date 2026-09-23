extends "res://game/shading/gdscript/weather_effects.gd"
## Bounded reference fixture only. Streaming worlds keep weather state and packing in C++.
var roof: Image
var wet: Image
var origin: Vector2
var extent: Vector2
var revision: int = -1
var _has_wet: bool = false
var _fixture_pages: Texture2DArray
var _fixture_table: ImageTexture
func set_surface_map(image: Image, map_origin: Vector2, map_extent: Vector2, new_revision: int) -> void:
	if new_revision == revision: return
	var previous: Image = wet
	wet = Image.create_empty(image.get_width(),image.get_height(),false,Image.FORMAT_RGF)
	for z: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var h: float = image.get_pixel(x,z).r
			var retained: float = 0.0
			if previous != null and previous.get_size() == image.get_size() and map_origin == origin and map_extent == extent:
				var old: Color = previous.get_pixel(x,z)
				if is_equal_approx(old.r,h): retained = old.g
			wet.set_pixel(x,z,Color(h,retained,0.0,1.0))
	roof = image
	origin = map_origin
	extent = map_extent
	revision = new_revision
	_publish_fixture_pages()
func has_surface_data() -> bool:
	return roof != null
func _tick_surface(elapsed: float, p: Profile) -> void:
	if p.wet_enabled and wet != null and (rain_weight > 0.0 or _has_wet):
		_has_wet = false
		var changed: bool = false
		for z: int in range(wet.get_height()):
			for x: int in range(wet.get_width()):
				var value: Color = wet.get_pixel(x,z)
				var amount: float = clampf(value.g+elapsed*(rain_weight*p.wet_accumulation-(1.0-rain_weight)*p.wet_drying),0.0,1.0)
				_has_wet = _has_wet or amount > 0.0
				if not is_equal_approx(value.g,amount):
					value.g = amount
					wet.set_pixel(x,z,value)
					changed = true
		if changed: _publish_fixture_pages()

func _publish_fixture_pages() -> void:
	var base: Vector2i = Vector2i(floori(origin.x/16.0),floori(origin.y/16.0))
	var last: Vector2i = Vector2i(floori((origin.x+extent.x-1)/16.0),floori((origin.y+extent.y-1)/16.0))
	var dimensions: Vector2i = last-base+Vector2i.ONE
	var pages: Array[Image] = []
	var mapping: Image = Image.create_empty(dimensions.x,dimensions.y,false,Image.FORMAT_RGBA8)
	for z: int in range(dimensions.y):
		for x: int in range(dimensions.x):
			var page: Image = Image.create_empty(16,16,false,Image.FORMAT_RGF)
			page.fill(Color(192,0,0,1))
			for lz: int in range(16):
				for lx: int in range(16):
					var p: Vector2i = (base+Vector2i(x,z))*16+Vector2i(lx,lz)-Vector2i(origin)
					if p.x >= 0 and p.y >= 0 and p.x < wet.get_width() and p.y < wet.get_height(): page.set_pixel(lx,lz,wet.get_pixelv(p))
			var encoded: int = pages.size()+1
			mapping.set_pixel(x,z,Color(float(encoded&255)/255.0,float(encoded>>8)/255.0,0,0))
			pages.append(page)
	var packed: Array[Image] = []
	for layer: int in range(ceili(pages.size()/16.0)):
		var image: Image = Image.create_empty(256,16,false,Image.FORMAT_RGF)
		for page: int in range(16):
			if layer*16+page<pages.size(): image.blit_rect(pages[layer*16+page],Rect2i(0,0,16,16),Vector2i(page*16,0))
		packed.append(image)
	if _fixture_pages == null or _fixture_pages.get_layers() != packed.size():
		_fixture_pages = Texture2DArray.new()
		_fixture_pages.create_from_images(packed)
	else:
		for i: int in range(packed.size()): _fixture_pages.update_layer(packed[i],i)
	_fixture_table = ImageTexture.create_from_image(mapping)
	var materials: Array[ShaderMaterial] = receivers.duplicate()
	materials.append(_material)
	for material: ShaderMaterial in materials:
		material.set_shader_parameter("weather_pages",_fixture_pages)
		material.set_shader_parameter("weather_page_table",_fixture_table)
		material.set_shader_parameter("weather_table_origin",Vector2(base))
		material.set_shader_parameter("weather_table_size",Vector2(dimensions))
