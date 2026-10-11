@tool
extends EditorPlugin
## One main-screen tool; resource editing is isolated from the host editor.
var panel: Control
var exporter: EditorExportPlugin
func _enter_tree() -> void:
	panel = preload("res://addons/astraeon_content/scenes/content_editor.tscn").instantiate()
	get_editor_interface().get_editor_main_screen().add_child(panel)
	panel.set_active(false)
	exporter = preload("res://addons/astraeon_content/export_guard.gd").new()
	add_export_plugin(exporter)

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return "内容编辑器"

func _get_plugin_icon() -> Texture2D:
	return get_editor_interface().get_editor_theme().get_icon("VoxelGI","EditorIcons")

func _make_visible(value: bool) -> void:
	if is_instance_valid(panel): panel.set_active(value)

func _get_unsaved_status(_for_scene: String) -> String:
	if is_instance_valid(panel) and panel.session.dirty(): return "内容包工程：" + panel.session.path
	return ""

func _save_external_data() -> void:
	if is_instance_valid(panel) and panel.session.dirty(): panel.save_current()

func _exit_tree() -> void:
	if exporter != null: remove_export_plugin(exporter)
	if is_instance_valid(panel): panel.queue_free()
