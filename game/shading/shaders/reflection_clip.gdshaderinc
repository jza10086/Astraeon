// Layer 20 is a camera-only marker reserved for the lab reflection capture.
// Material clipping is used because this engine build has no custom oblique projection API.
uniform float reflection_clip_height = 0.77;
bool reflection_clipped(vec3 position, uint camera_layers) {
	return (camera_layers & 524288u) != 0u && position.y < reflection_clip_height;
}
