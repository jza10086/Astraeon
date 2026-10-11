extends SceneTree
const EDITOR_SCENE = preload("res://addons/astraeon_content/scenes/content_editor.tscn")
var checks: int = 0
var failures: int = 0
var panel: Control
var surface: SubViewport
func _initialize() -> void:
 run.call_deferred()
func check(ok: bool,label: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  print("FAIL: ",label)
func frames(count: int = 4) -> void:
 for i: int in range(count): await process_frame
func ready_preview() -> void:
 var limit: int = Time.get_ticks_msec()+15000
 while (panel.preview.pending != null or panel.preview.busy) and Time.get_ticks_msec()<limit: await process_frame
 check(panel.preview.pending == null and not panel.preview.busy and panel.preview.bundle != null,"preview " + panel.preview.caption.text)
 await frames(12)
func capture(name: String) -> void:
 await RenderingServer.frame_post_draw
 var picture: Image = surface.get_texture().get_image()
 check(picture.save_png("res://tmp/content/editor_"+name+".png")==OK,"capture "+name)
func select_type(index: int) -> void:
 panel.type_select.select(index)
 panel.type_select.item_selected.emit(index)
func run() -> void:
 surface = SubViewport.new()
 surface.size = Vector2i(1920,1080)
 surface.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 surface.gui_embed_subwindows = true
 root.add_child(surface)
 panel = EDITOR_SCENE.instantiate()
 panel.auto_open = false
 panel.layout_path = "res://tmp/content/editor_layout_test.cfg"
 surface.add_child(panel)
 panel.open_document("res://game/data/content/authoring/astraeon/pack.tres")
 await ready_preview()
 check(panel.list.item_count == 5,"block list")
 check((panel.preview.camera.cull_mask & 524288)==0,"preview camera excludes reflection marker")
 var compiled: Dictionary = panel.preview.record.duplicate(true)
 var baseline: PackedByteArray = panel.preview.viewport.get_texture().get_image().get_data()
 panel.preview.cracks.selected = 10
 panel.preview.draw_record()
 await frames(20)
 check(panel.preview.viewport.get_texture().get_image().get_data() != baseline,"crack stage affects render")
 await capture("cracks_common")
 panel.preview.cracks.selected = 0
 panel.preview.draw_record()
 panel.form.go_to_item.emit(0)
 await frames()
 check(panel.selected.kind=="paired" and panel.selected.index==0,"block to paired item")
 panel.form.go_to_block.emit(0)
 await ready_preview()
 check(panel.selected.kind=="block" and panel.selected.index==0,"paired item to block")
 check(panel.preview.record==compiled,"recompiled preview equals exported record")
 await capture("block_1080")
 panel.list.select(2)
 panel.select_index(2)
 await ready_preview()
 check(panel.preview.record.surface.alpha == 1,"cutout production record")
 await capture("leaves_1080")
 var before: int = panel.preview.generation
 panel.set_active(false)
 panel.session.edit(panel.session.project.blocks[2].block.appearance.default_surface,"roughness",0.4)
 await create_timer(0.4).timeout
 check(panel.preview.generation==before,"hidden preview paused")
 panel.set_active(true)
 await ready_preview()
 panel.select_index(3)
 await ready_preview()
 panel.preview.cracks.selected = 10
 panel.preview.draw_record()
 await frames(20)
 await capture("cracks_wood")
 panel.preview.cracks.selected = 0
 panel.select_index(4)
 await ready_preview()
 await capture("emission")
 select_type(1)
 await ready_preview()
 check(panel.list.item_count == 9,"independent and paired items")
 check(panel.preview.icon.texture != null,"item icon native load")
 await capture("item_1080")
 select_type(2)
 await ready_preview()
 check(panel.preview.water_material != null,"production water material")
 await capture("water_1080")
 var clock: float = panel.preview.water_clock
 panel.preview.paused = true
 await frames(12)
 check(panel.preview.water_clock==clock,"wave pause")
 for dimensions: Vector2i in [Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160),Vector2i(3440,1440),Vector2i(830,640)]:
  surface.size = dimensions
  await frames(8)
  check(panel.size == Vector2(dimensions),"root layout " + str(dimensions))
  for control: Control in [panel.list,panel.form.get_parent(),panel.preview,panel.report,panel.toolbar]:
   var bounds: Rect2 = control.get_global_rect()
   check(bounds.position.x>=0 and bounds.end.x <= dimensions.x+1 and bounds.end.y<=dimensions.y+1,"layout bounds " + control.name + str(dimensions))
  await capture("layout_"+str(dimensions.x))
 surface.size = Vector2i(1920,1080)
 panel.theme = Theme.new()
 panel.theme.default_font_size = 24
 await frames(8)
 check(panel.form.get_parent().get_global_rect().end.x <= 1920,"large editor font layout")
 await capture("scale_150")
 panel.form.filter("underwater_color")
 await frames(4)
 var color: ColorPickerButton
 for row: Control in panel.form.field_rows:
  if row.get_meta("property","")=="underwater_color": color=row.get_child(1)
 check(color != null,"Chinese water color field")
 color.get_popup().popup()
 color.get_popup().position = Vector2i(1800,1000)
 panel.form.clamp_popup(color.get_popup())
 await frames(4)
 check(color.get_popup().position.x+color.get_popup().size.x<=1920 and color.get_popup().position.y+color.get_popup().size.y<=1080,"color popup clamped")
 check(color.get_picker().get_parent() is ScrollContainer,"oversized color content scrolls")
 await capture("color_popup")
 color.get_popup().hide()
 var used: Dictionary = {"ran":false}
 panel.guarded(func() -> void: used.ran=true)
 check(panel.unsaved.visible and not used.ran,"dirty switch confirmation")
 panel.unsaved.canceled.emit()
 panel.unsaved.hide()
 check(not panel.pending_action.is_valid(),"cancel keeps session")
 panel.guarded(func() -> void: used.ran=true)
 panel.unsaved.custom_action.emit(&"discard")
 check(used.ran,"explicit discard continues")
 panel.save_layout()
 var saved_fold: Dictionary = panel.form.folds.duplicate()
 check(panel.load_layout() and panel.form.folds==saved_fold,"fold state roundtrip")
 panel.queue_free()
 await frames()
 var bad_path: String = "res://tmp/content/editor_bad_layout.cfg"
 var bad: ConfigFile = ConfigFile.new()
 bad.set_value("editor","format",999)
 bad.save(bad_path)
 var before_bad: String = FileAccess.get_sha256(bad_path)
 var invalid_panel: Control = EDITOR_SCENE.instantiate()
 invalid_panel.auto_open = false
 invalid_panel.layout_path = bad_path
 surface.add_child(invalid_panel)
 await frames()
 check(not invalid_panel.layout_writable,"unsupported layout rejected")
 invalid_panel.queue_free()
 await frames()
 check(FileAccess.get_sha256(bad_path)==before_bad,"unsupported layout preserved")
 print("CONTENT_EDITOR_RENDER_DONE checks=",checks," failures=",failures)
 quit(0 if failures==0 else 1)

