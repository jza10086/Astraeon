extends RefCounted
## Sample only the right arm after locomotion; retain leg, trunk and left arm motion.
const BONES: Array[StringName] = [&"RightScapula", &"RightShoulder", &"RightUpperArm", &"RightLowerArm", &"Grip_R"]
var clip: Animation
var tracks: Array[Dictionary] = []
var time: float = 0.0
var weight: float = 0.0

func _init(model: Node3D, animation: Animation) -> void:
	clip = animation
	for track: int in range(clip.get_track_count()):
		var path: NodePath = clip.track_get_path(track)
		if path.get_subname_count() != 1:
			continue
		var target: Node = model.get_node(NodePath(path.get_concatenated_names()))
		var name: StringName = path.get_subname(0)
		if target is Skeleton3D and name in BONES:
			tracks.append({"track": track, "target": target, "index": (target as Skeleton3D).find_bone(name)})
		elif target is MeshInstance3D and String(name).begins_with("RightShoulder_"):
			tracks.append({"track": track, "target": target, "index": (target as MeshInstance3D).find_blend_shape_by_name(name)})

func apply(delta: float, enabled: bool) -> void:
	weight = move_toward(weight, 1.0 if enabled else 0.0, delta / 0.12)
	time = fposmod(time + delta, clip.length)
	if weight <= 0.0:
		return
	for entry: Dictionary in tracks:
		var track: int = entry.track
		var index: int = entry.index
		match clip.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				var rig: Skeleton3D = entry.target
				rig.set_bone_pose_position(index, rig.get_bone_pose_position(index).lerp(clip.position_track_interpolate(track, time), weight))
			Animation.TYPE_ROTATION_3D:
				var rig: Skeleton3D = entry.target
				rig.set_bone_pose_rotation(index, rig.get_bone_pose_rotation(index).slerp(clip.rotation_track_interpolate(track, time), weight))
			Animation.TYPE_SCALE_3D:
				var rig: Skeleton3D = entry.target
				rig.set_bone_pose_scale(index, rig.get_bone_pose_scale(index).lerp(clip.scale_track_interpolate(track, time), weight))
			Animation.TYPE_BLEND_SHAPE:
				var mesh: MeshInstance3D = entry.target
				mesh.set_blend_shape_value(index, lerpf(mesh.get_blend_shape_value(index), clip.blend_shape_track_interpolate(track, time), weight))
