extends SceneTree
## Raw shader compilation probe, independent of editor imports and sample bootstrap.
var _compiled: bool = false
var _failure: String = ""
func _initialize() -> void:
	_run.call_deferred()
func _compute_result(error: String) -> void:
	_failure = error
	_compiled = true
func _compile_compute() -> void:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	var source: RDShaderSource = RDShaderSource.new()
	source.source_compute = FileAccess.get_file_as_string("res://game/shading/shaders/camera_post.glsl").replace("#[compute]","")
	var spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(source)
	_compute_result.call_deferred(spirv.compile_error_compute)
func _run() -> void:
	RenderingServer.call_on_render_thread(_compile_compute)
	var host: Node3D = Node3D.new()
	root.add_child(host)
	var camera: Camera3D = Camera3D.new()
	host.add_child(camera)
	camera.position = Vector3(0,3,12)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	camera.cull_mask &= ~(1 << 19)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	host.add_child(sun)
	sun.rotation_degrees = Vector3(-50,-30,0)
	var texture: ImageTexture3D = ImageTexture3D.new()
	var slices: Array[Image] = []
	for i: int in range(16):
		var image: Image = Image.create_empty(16,16,false,Image.FORMAT_RGBA8)
		image.fill(Color(1,0,0,1))
		slices.append(image)
	texture.create(Image.FORMAT_RGBA8,16,16,16,false,slices)
	var names: Array[String] = ["voxel_light","plant","water","water_reflective","water_planar","glass_capture","rain"]
	for index: int in range(names.size()):
		var shader: Shader = load("res://game/shading/shaders/"+names[index]+".gdshader") as Shader
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("light_volume",texture)
		material.set_shader_parameter("volume_origin",Vector3(-8,-8,-8))
		material.set_shader_parameter("volume_size",Vector3(16,16,16))
		var mesh: MeshInstance3D = MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		mesh.position.x = (index-3)*1.5
		mesh.material_override = material
		host.add_child(mesh)
	for frame: int in range(40): await process_frame
	while not _compiled: await process_frame
	if not _failure.is_empty(): push_error(_failure)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/shading-shader-probe.png")
	print("SHADING_COMPUTE ","PASS" if _failure.is_empty() else "FAIL")
	quit(0 if _failure.is_empty() else 1)
