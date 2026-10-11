@tool
extends EditorExportPlugin
var _source_files: Dictionary[String, bool] = {}
func _get_name() -> String:
	return "AstraeonContentGuard"
func _export_begin(_features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
	_source_files.clear()
	var pack: String = "res://game/data/content/packages/astraeon.aebpack"
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(pack + ".receipt.json")) if FileAccess.file_exists(pack + ".receipt.json") else null
	if not receipt is Dictionary or not FileAccess.file_exists(pack):
		get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR, "Content", "Missing compiled content or build receipt; run the content compiler first.")
		return
	if FileAccess.get_sha256(pack) != receipt.get("pack_sha256", ""):
		get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR, "Content", "Compiled package hash differs from its receipt.")
		return
	for source: String in receipt.sources:
		if not FileAccess.file_exists(source) or FileAccess.get_sha256(source) != receipt.sources[source]:
			get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR, "Content", "Stale content package: " + source)
			return
		# Source resource graphs and indexed images may live anywhere under res://.
		var local: String = ProjectSettings.localize_path(source)
		if local.begins_with("res://") and (source.is_absolute_path() and not source.begins_with("res://") or source.get_extension() in ["tres", "res"]):
			_source_files[local] = true
	add_file(pack, FileAccess.get_file_as_bytes(pack), false)

## Authoring data and original images never accompany runtime content.
func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if _source_files.has(path) or path.begins_with("res://game/data/content/authoring/") or path.begins_with("res://content_sources/") or path.begins_with("res://test/") or path.ends_with(".receipt.json"):
		skip()
