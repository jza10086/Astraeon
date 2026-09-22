extends RefCounted
## Finite sample-only world adapter. Rebuild on edits; production supplies its own map.
static func make_height_map(volume: RefCounted, glass: Array[MeshInstance3D]) -> Image:
	var image: Image = Image.create_empty(volume.size.x,volume.size.z,false,Image.FORMAT_RF)
	for z: int in range(volume.size.z):
		for x: int in range(volume.size.x):
			var height: float = volume.origin.y
			var world_x: int = x+volume.origin.x
			var world_z: int = z+volume.origin.z
			for y: int in range(volume.origin.y+volume.size.y-1,volume.origin.y-1,-1):
				if volume.voxel_at(Vector3i(world_x,y,world_z)) != 0:
					height = y+1.0
					break
			# Fixtures are horizontal glass canopies, with exact axis-aligned bounds.
			for pane: MeshInstance3D in glass:
				var bounds: AABB = pane.global_transform * pane.get_aabb()
				if world_x+0.5 >= bounds.position.x and world_x+0.5 < bounds.end.x and world_z+0.5 >= bounds.position.z and world_z+0.5 < bounds.end.z:
					height = maxf(height,bounds.end.y)
			image.set_pixel(x,z,Color(height,0,0,1))
	return image
