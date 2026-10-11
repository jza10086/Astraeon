extends Node
## UI-only reference owner; clipped/hidden icons do not pin textures.
var cache: RefCounted
var hash: String = ""
var texture: Texture2D
var _requested: bool = false
func configure(item: AstraeonItemDefinition) -> void:
	var next_hash: String = String(item.get_meta("content_icon", "")) if item != null else ""
	if next_hash == hash:
		return
	_release()
	hash = next_hash
	cache = item.get_meta("content_cache", null) if item != null else null
func _process(_delta: float) -> void:
	var control: Control = get_parent() as Control
	var visible: bool = control.is_visible_in_tree() and control.get_global_rect().intersects(control.get_viewport_rect())
	var ancestor: Node = control.get_parent()
	while visible and ancestor is Control:
		if (ancestor as Control).clip_contents:
			visible = control.get_global_rect().intersects((ancestor as Control).get_global_rect())
		ancestor = ancestor.get_parent()
	if cache == null or hash.is_empty():
		return
	if not visible:
		_release()
		return
	if not _requested:
		cache.call("request", "ui:" + str(get_instance_id()), PackedStringArray([hash]))
		_requested = true
	var loaded: Texture2D = cache.call("texture", hash)
	if loaded != texture:
		texture = loaded
		control.queue_redraw()
func _release() -> void:
	if cache != null and _requested:
		cache.call("release", "ui:" + str(get_instance_id()))
	_requested = false
	texture = null
func _exit_tree() -> void:
	_release()
