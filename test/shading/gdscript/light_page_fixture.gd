extends RefCounted
## Test-only packing of the full reference solver into the production page layout.
## Production worlds feed the C++ incremental cache directly.
var banks: Array[Texture2DArray] = []
var table: ImageTexture
var origin: Vector3i
var size: Vector3i
var section_origin: Vector3i
var section_size: Vector3i
var layers: int
static func bind_fixture(material: ShaderMaterial, texture: ImageTexture3D, map_origin: Vector3i, map_size: Vector3i) -> void:
    var fixture: RefCounted = texture.get_meta("test_light_pages") as RefCounted if texture.has_meta("test_light_pages") else null
    if fixture == null:
        fixture = load("res://test/shading/gdscript/light_page_fixture.gd").new()
        fixture.origin = map_origin
        fixture.size = map_size
        fixture.section_origin = Vector3i(floori(map_origin.x/16.0),floori(map_origin.y/16.0),floori(map_origin.z/16.0))
        var end: Vector3i = map_origin + map_size - Vector3i.ONE
        fixture.section_size = Vector3i(floori(end.x/16.0),floori(end.y/16.0),floori(end.z/16.0)) - fixture.section_origin + Vector3i.ONE
        fixture.layers = ceili(float(fixture.section_size.x*fixture.section_size.y*fixture.section_size.z)/64.0)*16
        texture.set_meta("test_light_pages",fixture)
        fixture.repack(texture.get_data())
    for bank: int in range(4): material.set_shader_parameter("light_pages_%d" % bank,fixture.banks[bank])
    material.set_shader_parameter("light_page_layers",fixture.layers)
    material.set_shader_parameter("light_page_table",fixture.table)
    material.set_shader_parameter("light_table_origin",Vector3(fixture.section_origin))
    material.set_shader_parameter("light_table_size",Vector3(fixture.section_size))
static func update_fixture(texture: ImageTexture3D, images: Array[Image]) -> void:
    var fixture: RefCounted = texture.get_meta("test_light_pages") as RefCounted if texture.has_meta("test_light_pages") else null
    if fixture != null: fixture.repack(images)
func repack(images: Array[Image]) -> void:
    var pages: Array[Image] = []
    var mapping: Image = Image.create_empty(section_size.x,section_size.y*section_size.z,false,Image.FORMAT_RGBA8)
    for z: int in range(section_size.z):
        for y: int in range(section_size.y):
            for x: int in range(section_size.x):
                var page: Image = Image.create_empty(16,256,false,Image.FORMAT_RGBA8)
                for lz: int in range(16):
                    for ly: int in range(16):
                        for lx: int in range(16):
                            var p: Vector3i = (section_origin+Vector3i(x,y,z))*16+Vector3i(lx,ly,lz)-origin
                            if p.x >= 0 and p.y >= 0 and p.z >= 0 and p.x < size.x and p.y < size.y and p.z < size.z:
                                page.set_pixel(lx,ly+16*lz,images[p.z].get_pixel(p.x,p.y))
                var encoded: int = pages.size()+1
                mapping.set_pixel(x,y+section_size.y*z,Color(float(encoded&255)/255.0,float(encoded>>8)/255.0,0,0))
                pages.append(page)
    if table == null: table = ImageTexture.create_from_image(mapping)
    else: table.update(mapping)
    while pages.size() < layers*4: pages.append(Image.create_empty(16,256,false,Image.FORMAT_RGBA8))
    var packed: Array[Image] = []
    for layer: int in range(layers*4/16):
        var image: Image = Image.create_empty(256,256,false,Image.FORMAT_RGBA8)
        for page: int in range(16): image.blit_rect(pages[layer*16+page],Rect2i(0,0,16,256),Vector2i(page*16,0))
        packed.append(image)
    if banks.is_empty():
        for bank: int in range(4):
            var texture: Texture2DArray = Texture2DArray.new()
            texture.create_from_images(packed.slice(bank*layers/16,(bank+1)*layers/16))
            banks.append(texture)
    else:
        for index: int in range(packed.size()): banks[index/(layers/16)].update_layer(packed[index],index%(layers/16))
