extends "res://test/shading/gdscript/test_foliage_layers.gd"
## Atlas content/rotation checks plus inherited native geometry and optional visual checks.
func _run() -> void:
	_atlas_checks()
	await super._run()

func _atlas_checks() -> void:
	var appearance: AstraeonBlockAppearance = AstraeonBlockAppearance.new()
	appearance.default_surface = AstraeonBlockSurface.new()
	var colors: Array[Color] = [Color.RED,Color.GREEN,Color.BLUE,Color.YELLOW,Color.MAGENTA,Color.CYAN]
	for face: int in range(6):
		var surface: AstraeonBlockSurface = AstraeonBlockSurface.new()
		surface.base_color = colors[face]
		surface.roughness = float(face)/5.0
		surface.emission_color = colors[face]
		surface.emission_energy = float(face)+1.0
		appearance.face_surfaces[face] = surface
	var definition: AstraeonBlockDefinition = AstraeonBlockDefinition.new()
	definition.key = &"shading_test_atlas"
	definition.appearance = appearance
	check(appearance.texture_resolution == 32,"Default face resolution is 32")
	for resolution: int in [1,8,16,32,48,64,128]:
		appearance.texture_resolution = resolution
		var model: VoxelBlockyModelCube = AstraeonBlockLibraryBuilder.build_block(definition,Basis.IDENTITY)
		check(model != null,"Compile resolution %d" % resolution)
		var material: ORMMaterial3D = model.get_material_override(0) as ORMMaterial3D
		var albedo: Image = material.albedo_texture.get_image()
		var orm: Image = material.orm_texture.get_image()
		var emission: Image = material.emission_texture.get_image()
		check(albedo.get_size() == Vector2i(6*resolution,resolution) and orm.get_size() == albedo.get_size() and emission.get_size() == albedo.get_size(),"All atlases use requested resolution %d" % resolution)
		var valid: bool = true
		for face: int in range(6):
			var x: int = face*resolution+resolution/2
			var y: int = resolution/2
			valid = valid and albedo.get_pixel(x,y).is_equal_approx(colors[face])
			valid = valid and absf(orm.get_pixel(x,y).g-float(face)/5.0) < 0.005
			var glow: Color = emission.get_pixel(x,y)
			valid = valid and absf(maxf(glow.r,maxf(glow.g,glow.b))-(float(face)+1.0)/6.0) < 0.001
		check(valid,"Six face colors/roughness/emission preserved at %d" % resolution)
		# Whole-cube rotation still maps authored RIGHT to world FRONT.
		var rotated: VoxelBlockyModelCube = AstraeonBlockLibraryBuilder.build_block(definition,Basis(Vector3.UP,PI/2.0))
		var rotated_material: ORMMaterial3D = rotated.get_material_override(0) as ORMMaterial3D
		check(rotated_material.albedo_texture.get_image().get_pixel(2*resolution,0).is_equal_approx(Color.CYAN),"Orientation maps face correctly at %d" % resolution)
	appearance.texture_resolution = 64
	var pattern: Image = Image.create_empty(2,1,false,Image.FORMAT_RGBA8)
	pattern.set_pixel(0,0,Color.RED)
	pattern.set_pixel(1,0,Color.BLUE)
	var top: AstraeonBlockSurface = appearance.face_surfaces[AstraeonBlockAppearance.Face.TOP]
	top.base_color = Color.WHITE
	top.albedo_texture = ImageTexture.create_from_image(pattern)
	appearance.face_uv_rotations[AstraeonBlockAppearance.Face.TOP] = 90
	var textured: VoxelBlockyModelCube = AstraeonBlockLibraryBuilder.build_block(definition,Basis.IDENTITY)
	var texture: Image = (textured.get_material_override(0) as ORMMaterial3D).albedo_texture.get_image()
	check(texture.get_pixel(32,1).is_equal_approx(Color.BLUE) and texture.get_pixel(32,62).is_equal_approx(Color.RED),"Source texture resampling honors UV rotation at 64")
	check(pattern.get_size() == Vector2i(2,1),"Compiler preserves source dimensions")
	for invalid: int in [0,-1,1025]:
		appearance.texture_resolution = invalid
		check(not appearance.validate().is_empty(),"Reject invalid atlas resolution %d" % invalid)
