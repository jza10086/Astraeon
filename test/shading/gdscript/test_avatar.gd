extends Node3D
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
## Procedural reflection subject, not a gameplay controller. Feet define the anchor.
var materials: Array[ShaderMaterial] = []
var anchor: Vector3 = Vector3(23,1,-26)
var phase: float = 0.0
var limbs: Array[Node3D] = []

func configure(texture: ImageTexture3D, origin: Vector3i, size: Vector3i) -> void:
	for color: Color in [Color(0.8,0.48,0.3),Color(0.05,0.3,0.8),Color(0.08,0.1,0.15)]:
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = preload("res://game/shading/shaders/voxel_light.gdshader")
		material.set_shader_parameter("base_color",color)
		material.set_shader_parameter("light_volume",texture)
		material.set_shader_parameter("volume_origin",Vector3(origin))
		material.set_shader_parameter("volume_size",Vector3(size))
		materials.append(material)
	_part(self,Vector3(0,1.63,0),Vector3(0.42,0.42,0.42),materials[0])
	_part(self,Vector3(0,1.1,0),Vector3(0.55,0.64,0.3),materials[1])
	for side: float in [-1.0,1.0]:
		var arm: Node3D = Node3D.new()
		arm.position = Vector3(side*0.39,1.36,0)
		add_child(arm)
		_part(arm,Vector3(0,-0.28,0),Vector3(0.2,0.62,0.24),materials[0])
		limbs.append(arm)
		var leg: Node3D = Node3D.new()
		leg.position = Vector3(side*0.15,0.8,0)
		add_child(leg)
		_part(leg,Vector3(0,-0.4,0),Vector3(0.24,0.8,0.28),materials[2])
		limbs.append(leg)
	position = anchor

func _part(parent: Node3D, at: Vector3, size: Vector3, material: ShaderMaterial) -> void:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)

func apply(settings: Profile) -> void:
	visible = settings.avatar_visible
	scale = Vector3.ONE * settings.avatar_scale
	for material: ShaderMaterial in materials:
		material.set_shader_parameter("block_grid_strength",0.0)
		material.set_shader_parameter("ao_strength",0.0)

func move_to(at: Vector3) -> void:
	anchor = at
	position = at
	phase = 0.0

func tick(delta: float, settings: Profile) -> void:
	if not visible or not settings.avatar_animate or settings.avatar_speed <= 0.0:
		return
	phase += delta * settings.avatar_speed
	position = anchor + Vector3(sin(phase)*settings.avatar_travel,0,0)
	for i: int in range(limbs.size()):
		limbs[i].rotation.x = sin(phase*4.0) * 0.45 * (1.0 if i == 0 or i == 3 else -1.0)
