extends RefCounted
## Shared allocator. Energy zero disables a lamp without hiding its emissive child.
## Priorities precede distance; hysteresis retains previously selected nearby lights.
var entries: Dictionary[int, Dictionary] = {}
var selected: Dictionary[int, bool] = {}
func register(light: OmniLight3D, energy: float, shadows: bool, priority: int = 0) -> void:
	entries[light.get_instance_id()] = {"light": light, "energy": energy, "shadows": shadows, "priority": priority}
func clear_requests() -> void:
	entries.clear()
func allocate(observer: Vector3, point_limit: int, shadow_limit: int, hysteresis: float) -> void:
	var order: Array[int] = []
	order.assign(entries.keys())
	order.sort_custom(func(a: int, b: int) -> bool:
		var ea: Dictionary = entries[a]
		var eb: Dictionary = entries[b]
		if ea.priority != eb.priority: return ea.priority > eb.priority
		var da: float = ea.light.global_position.distance_to(observer) - (hysteresis if selected.has(a) else 0.0)
		var db: float = eb.light.global_position.distance_to(observer) - (hysteresis if selected.has(b) else 0.0)
		return a < b if is_equal_approx(da, db) else da < db)
	var next: Dictionary[int, bool] = {}
	var shadows: int = 0
	for id: int in order:
		var entry: Dictionary = entries[id]
		var light: OmniLight3D = entry.light
		var active: bool = entry.energy > 0.0 and next.size() < point_limit
		light.light_energy = entry.energy if active else 0.0
		light.shadow_enabled = active and entry.shadows and shadows < shadow_limit
		if active: next[id] = true
		if light.shadow_enabled: shadows += 1
	selected = next
