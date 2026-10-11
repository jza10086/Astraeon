@tool
extends RefCounted
## Development check only: refresh the tool dependency closure in an already verified editor.
## Caller must first disable astraeon_content after resolving its unsaved document.
static func refresh() -> Dictionary:
 var paths: PackedStringArray = [
  "game/shading/blocks/gdscript/block_surface.gd", "game/shading/blocks/gdscript/block_light_appearance.gd",
  "game/shading/blocks/gdscript/breaking_texture_group.gd", "game/shading/blocks/gdscript/block_appearance.gd",
  "game/shading/water/gdscript/water_appearance.gd", "game/data/block/gdscript/block_state_definition.gd",
  "game/data/block/gdscript/block_definition.gd", "game/data/item/gdscript/item_definition.gd",
  "game/data/fluid/gdscript/fluid_definition.gd", "game/data/content/gdscript/block_asset.gd",
  "game/data/content/gdscript/item_asset.gd", "game/data/content/gdscript/content_manifest.gd",
  "game/data/content/gdscript/content_bundle.gd", "game/shading/blocks/gdscript/compiled_block_builder.gd",
  "tools/content/project_resolver.gd", "tools/content/compiler.gd",
  "addons/astraeon_content/gdscript/content_session.gd", "addons/astraeon_content/gdscript/content_form.gd",
  "addons/astraeon_content/gdscript/content_preview.gd", "addons/astraeon_content/gdscript/content_editor.gd",
  "addons/astraeon_content/export_guard.gd", "addons/astraeon_content/plugin.gd"]
 for file: String in paths:
  var path: String = "res://"+file
  var script: GDScript = ResourceLoader.load(path) as GDScript
  if script == null: return {"error": "Cannot load " + path}
  var current: String = FileAccess.get_file_as_string(path)
  if script.source_code == current: continue
  script.source_code = current
  var status: Error = script.reload(true)
  if status != OK: return {"error": path + ": " + error_string(status)}
 var scene: PackedScene = ResourceLoader.load("res://addons/astraeon_content/scenes/content_editor.tscn","PackedScene",ResourceLoader.CACHE_MODE_REPLACE)
 return {"scripts": paths.size(), "scene": scene != null}
