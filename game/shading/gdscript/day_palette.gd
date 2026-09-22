extends RefCounted
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
## Cyclic four-anchor palette shared by sky, surfaces, fog and reflections.
static func sample(p: Profile) -> Dictionary[String, Variant]:
	var phase: float = fposmod(p.hour, 24.0) / 6.0
	var index: int = int(floor(phase))
	var weight: float = smoothstep(0.0, 1.0, phase - index)
	var names: Array[String] = ["night", "dawn", "noon", "dusk"]
	var result: Dictionary[String, Variant] = {}
	for channel: String in ["direct", "zenith", "horizon", "ambient", "fog"]:
		var a: Color = p.get("color_%s_%s" % [names[index], channel])
		var b: Color = p.get("color_%s_%s" % [names[(index + 1) % 4], channel])
		var value: Color = a.lerp(b, weight)
		var night_weight: float = (1.0 - weight if index == 0 else weight if index == 3 else 0.0)
		result[channel] = value * lerpf(1.0, p.color_night_brightness, night_weight)
	result["energy"] = lerpf(p.get("color_" + names[index] + "_energy"), p.get("color_" + names[(index + 1) % 4] + "_energy"), weight)
	return result
