extends SceneTree
const Models: Script = preload("res://game/entities/common/gdscript/character_models.gd")
const Library: Script = preload("res://game/entities/common/gdscript/character_library.gd")
const Fixture: Script = preload("res://test/entities/gdscript/fixtures/character_pair_fixture.gd")
const Page: Script = preload("res://game/ui/main_menu/gdscript/character_select.gd")
const Player: PackedScene = preload("res://game/entities/player/scenes/player.tscn")
var failures: int = 0
var checks: int = 0
func _initialize() -> void:
 call_deferred("run")
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error(message)
func run() -> void:
 root.get_node("MCPRuntimeServer").call("_stop_server")
 create_timer(60).timeout.connect(func() -> void: quit(2))
 var base: String = "res://tmp/paired_import_%d" % Time.get_ticks_usec()
 Library.set_directory(base.path_join("installed"))
 Fixture.install(Library.directory, "basic_voxel")
 Fixture.install(base.path_join("sources"), "scout")
 var source: String = base.path_join("sources/scout")
 var settings: String = base.path_join("settings.cfg")
 var page: Control = Page.new()
 page.theme = preload("res://game/ui/resources/menu_theme.tres")
 root.add_child(page)
 page.open(settings)
 check(page.model_buttons.size() == 1 and page.model_buttons.has(&"basic_voxel"), "One button per complete pair")
 check(page.import_dialog.file_mode == FileDialog.FILE_MODE_OPEN_DIR, "Import selects a folder")
 await page.import_character(source)
 check(page.selected_id == &"scout" and page.model_buttons.size() == 2, "Folder import adds one named selection: " + page.message.text)
 if page.selected_id != &"scout":
  quit(1)
  return
 check(page.fp_preview_model.get_node("AnimationPlayer").current_animation == "FP_Idle", "FP preview has independent animation")
 check(page.preview_model.get_node("AnimationPlayer").current_animation == "Idle", "TP preview retains locomotion asset")
 check(page.model_folder() == ProjectSettings.globalize_path(Library.directory.path_join("scout")), "Folder button opens selected pair")
 page.confirm()
 check(Models.load_id(settings) == &"scout", "One ID persists both views")
 var player: CharacterMotor = Player.instantiate() as CharacterMotor
 player.get_node("Visual").settings_path = settings
 player.get_node("Controller").input_enabled = false
 root.add_child(player)
 check(player.get_node("Visual").model_id == &"scout" and player.get_node("Visual").first_person_animation.has_animation("FP_HoldBlock_R"), "World uses FP model from the selected pair")
 player.queue_free()
 await process_frame
 var again: Dictionary = Library.import_folder(source)
 check(again.get("id", &"") == &"scout" and Library.entries.size() == 2, "Identical pair import is idempotent")
 page.delete_selected()
 check(not DirAccess.dir_exists_absolute(Library.directory.path_join("scout")) and FileAccess.file_exists(source.path_join("scout_fp.glb")), "Delete removes installed pair and preserves source")
 check(Models.load_id(settings) == &"basic_voxel", "Deleting current pair selects remaining pair")
 Fixture.install(Library.directory, "missing")
 DirAccess.remove_absolute(Library.directory.path_join("missing/missing_fp.glb"))
 Library.scan()
 check(Library.definition(&"missing").is_empty() and not Library.errors.is_empty(), "Incomplete folder is rejected")
 var invalid: Dictionary = Library.import_folder(Library.directory.path_join("missing"))
 check(invalid.has("error"), "Import refuses a missing partner")
 DirAccess.copy_absolute(source.path_join("scout_tp.glb"), Library.directory.path_join("flat.glb"))
 Library.scan()
 check(Library.entries.size() == 1 and Library.errors.size() == 2, "Flat old layout is rejected without fallback")
 var saved: ConfigFile = ConfigFile.new()
 saved.set_value("character", "model", "user/scout.glb")
 saved.save(settings)
 check(Models.load_id(settings).is_empty(), "Old per-file ID is rejected")
 check(Models.remove_id(&"basic_voxel", base.path_join("fresh.cfg")) == ERR_INVALID_PARAMETER, "Last complete pair is protected")
 page.queue_free()
 await process_frame
 print("CHARACTER_PAIR_IMPORT checks=%d failures=%d" % [checks, failures])
 quit(1 if failures else 0)
