extends SceneTree
const Session = preload("res://addons/astraeon_content/gdscript/content_session.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
 run.call_deferred()
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  print("FAIL: ",label)
func run() -> void:
 var directory: String = "res://tmp/content/editor_checks/" + str(Time.get_ticks_usec())
 for original: String in ["res://game/data/content/authoring/astraeon/pack.tres", "res://test/content/resources/example_manifest.tres"]:
  var session: RefCounted = Session.new()
  check(session.open_project(original), "open " + original)
  var sources: Dictionary = session.fingerprints.duplicate()
  var before_name: String = session.project.blocks[0].block.display_name
  session.edit(session.project.blocks[0].block, "display_name", "测试私有修改")
  check(session.dirty(), "dirty after edit")
  session.undo()
  check(session.project.blocks[0].block.display_name == before_name and not session.dirty(), "undo reaches saved state")
  session.redo()
  check(session.project.blocks[0].block.display_name == "测试私有修改", "redo")
  check(ResourceLoader.load(original).blocks[0].block.display_name == before_name, "shared source immutable")
  var isolated: AstraeonContentManifest = session.compiler_input()
  session.project = isolated
  session.path = directory.path_join(isolated.package_id + "/pack.tres")
  for i: int in range(session.block_paths.size()): session.block_paths[i] = session.path.get_base_dir().path_join("blocks/"+str(i)+".tres")
  for i: int in range(session.item_paths.size()): session.item_paths[i] = session.path.get_base_dir().path_join("items/"+str(i)+".tres")
  for i: int in range(session.fluid_paths.size()): session.fluid_paths[i] = session.path.get_base_dir().path_join("fluids/"+str(i)+".tres")
  session.fingerprints.clear()
  var item_rows: Array[Dictionary] = session.rows("item")
  var paired: Dictionary = {}
  for row: Dictionary in item_rows:
   if row.kind == "paired": paired = row; break
  check(not paired.is_empty(), "paired item listed")
  session.edit(paired.data,"max_stack",31)
  check(session.project.blocks[paired.index].item.max_stack == 31, "paired edit owns same file")
  var appearance: AstraeonBlockAppearance = session.project.blocks[0].block.appearance
  appearance.face_surfaces[0] = appearance.default_surface.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
  appearance.face_surfaces[0].metallic = 0.7
  appearance.face_uv_rotations[0] = 90
  appearance.face_uv_mirrors[0] = Vector2i(1,0)
  appearance.authoring_orientation = Basis(Vector3.UP,PI/2)
  var state: AstraeonBlockStateDefinition = AstraeonBlockStateDefinition.new()
  state.key = &"east"
  state.orientation = Basis(Vector3.UP,PI/2)
  session.project.blocks[0].block.states.append(state)
  session.project.blocks[0].block.default_state = &"east"
  if not session.project.fluids.is_empty(): session.project.fluids[0].appearance.absorption = 0.71
  check(session.save_all(), "save isolated: " + session.error)
  check(not session.dirty(), "save clears dirty")
  var again: RefCounted = Session.new()
  check(again.open_project(session.path), "reload sources")
  check(again.block_paths == session.block_paths, "manifest uses final external asset paths")
  check(again.project.blocks[paired.index].item.max_stack == 31, "paired roundtrip")
  var roundtrip: AstraeonBlockAppearance = again.project.blocks[0].block.appearance
  check(roundtrip.face_surfaces[0].metallic == 0.7 and roundtrip.face_uv_rotations[0] == 90 and roundtrip.face_uv_mirrors[0] == Vector2i(1,0), "face override UV roundtrip")
  check(roundtrip.authoring_orientation.is_equal_approx(appearance.authoring_orientation) and again.project.blocks[0].block.default_state == &"east", "orientation/state roundtrip")
  var output: String = session.path.get_base_dir().path_join("test.aebpack")
  var result: Dictionary = again.compile(output)
  check(not result.has("error"), "compile " + str(result))
  check(FileAccess.file_exists(output+".receipt.json"), "build receipt")
  var bundle: AstraeonContentBundle = AstraeonContentBundle.new()
  check(bundle.open(PackedStringArray([output])), "compiled runtime bundle: " + bundle.error)
  check(bundle.blocks[String(again.project.blocks[0].block.key)].states[0].name == "east", "compiled orientation state")
  bundle.shutdown()
  var file: String = again.block_paths[0]
  var external: FileAccess = FileAccess.open(file,FileAccess.READ_WRITE)
  external.seek_end()
  external.store_string("\n; external author edit\n")
  external.close()
  check(again.external_changes().has(file) and not again.save_all(), "external conflict blocks save")
  check(again.save_all(true), "explicit overwrite")
  check(not again.add("block",String(again.project.blocks[0].block.key)), "reject duplicate ID")
  var kept: String = again.block_paths[-1]
  check(again.remove(again.rows("block")[-1]) and FileAccess.file_exists(kept), "remove leaves file")
  again.undo()
  check(again.block_paths.has(kept), "undo remove restores ownership")
  for source: String in sources: check(FileAccess.get_sha256(source) == sources[source], "original file unchanged " + source)
 var fresh: RefCounted = Session.new()
 check(fresh.create_project(directory.path_join("new/pack.tres"),"testing"),"create package")
 check(fresh.add("block","testing:cube",true),"new complete block")
 check(fresh.add("item","testing:tool"),"new standalone item")
 check(fresh.add("fluid","testing:water"),"new water")
 check(fresh.add("block","testing:copy",false,fresh.rows("block")[0]),"copy with new ID")
 check(fresh.project.blocks[1].item == null,"copy without paired item")
 check(fresh.save_all(),"save new project")
 check(not fresh.compile(directory.path_join("new.aebpack")).has("error"),"export new project")
 var image: String = ProjectSettings.globalize_path("res://content_sources/astraeon/leaves_surface_default.png")
 check(fresh.bind_file(fresh.project.blocks[0],"surface/default",image),"external picture binding")
 var key: StringName = fresh.project.blocks[0].image_slots["surface/default"]
 check(fresh.image_path(key) == image,"relative path resolves")
 check(not fresh.remove_image(key),"referenced picture removal blocked")
 fresh.project.image_sources[key] = "absent.png"
 check(fresh.compile("",true).has("error"),"missing indexed picture rejected")
 check(Session.relative_image("F:/a/b","F:/a/c/x.png") == "../c/x.png", "relative same disk")
 check(Session.relative_image("F:/a/b","C:/images/x.png") == "C:/images/x.png", "absolute cross disk")
 print("CONTENT_EDITOR_SESSION_DONE checks=",checks," failures=",failures)
 quit(0 if failures == 0 else 1)
