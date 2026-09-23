extends SceneTree
## Core contracts can run without importing the GPU compute shader or starting an editor.
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
const Budget: Script = preload("res://game/shading/gdscript/light_budget.gd")
const Weather: Script = preload("res://test/shading/gdscript/weather_fixture.gd")
const Palette: Script = preload("res://game/shading/gdscript/day_palette.gd")
const SettingsPanel: Script = preload("res://game/shading/gdscript/settings_panel.gd")
const CameraEffects: Script = preload("res://game/shading/gdscript/camera_effects.gd")
var failures: int = 0
var checks: int = 0
func _initialize() -> void:
	_run.call_deferred()
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
func _run() -> void:
	var profile: Profile = Profile.new()
	var file: String = "res://tmp/shading-logic-settings.cfg"
	check(profile.save_settings(file)==OK,"Save current settings")
	var restored: Profile = Profile.new()
	check(restored.load_settings(file)==OK,"Reload current settings")
	for property: Dictionary in profile.settings_properties(): check(restored.get(property.name)==profile.get(property.name),"Roundtrip "+str(property.name))
	var invalid: ConfigFile = ConfigFile.new()
	invalid.set_value("shading","format","old")
	invalid.save(file)
	check(restored.load_settings(file)==ERR_FILE_UNRECOGNIZED,"Reject old format")
	var box: VBoxContainer = VBoxContainer.new()
	root.add_child(box)
	var panel: SettingsPanel = SettingsPanel.new()
	panel.build(box,profile,func() -> void: pass)
	for property: Dictionary in profile.settings_properties(): check(panel.widgets.has(property.name),"UI includes "+str(property.name))
	panel.show_setting(&"rays_mode")
	panel._select(&"rays_mode",1)
	check(panel.rows[&"rays_steps"].visible and not panel.rows[&"volume_density"].visible,"Screen ray settings only")
	panel._select(&"rays_mode",2)
	check(not panel.rows[&"rays_steps"].visible and panel.rows[&"volume_density"].visible,"Volume settings only")
	panel._select(&"rays_mode",0)
	check(not panel.rows[&"volume_density"].visible,"Disabled mode hides volume settings")
	profile.hour = 23.999
	var a: Color = Palette.sample(profile).ambient
	profile.hour = 0.001
	check(a.is_equal_approx(Palette.sample(profile).ambient),"Cyclic palette")
	var host: Node3D = Node3D.new()
	root.add_child(host)
	var first: OmniLight3D = OmniLight3D.new()
	var hand: OmniLight3D = OmniLight3D.new()
	host.add_child(first)
	host.add_child(hand)
	hand.position.x = 10.0
	var budget: Budget = Budget.new()
	budget.register(first,2,true)
	budget.register(hand,4,true,10)
	budget.allocate(Vector3.ZERO,1,1,2)
	check(hand.light_energy==4.0 and first.light_energy==0.0,"Priority beats distance")
	budget.allocate(Vector3.ZERO,1,0,2)
	check(not hand.shadow_enabled,"Independent shadow budget")
	budget.allocate(Vector3.ZERO,0,0,2)
	check(hand.light_energy==0.0,"Zero point budget")
	var weather: Weather = Weather.new()
	host.add_child(weather)
	weather.configure([])
	var heights: Image = Image.create_empty(2,2,false,Image.FORMAT_RF)
	heights.fill(Color(1,0,0,1))
	weather.set_surface_map(heights,Vector2.ZERO,Vector2(2,2),1)
	profile.weather_mode = 2
	profile.weather_transition = 0.1
	profile.wet_accumulation = 1.0
	weather.apply(profile)
	weather.tick(1.0,profile,Vector3.ZERO)
	check(weather.wet.get_pixel(0,0).g>0.0,"Rain creates wetness")
	var edited: Image = heights.duplicate() as Image
	edited.set_pixel(0,0,Color(2,0,0,1))
	weather.set_surface_map(edited,Vector2.ZERO,Vector2(2,2),2)
	check(weather.wet.get_pixel(0,0).g==0.0,"New top surface resets wetness")
	check(weather.wet.get_pixel(1,0).g>0.0,"Unchanged surface retains wetness")
	profile.wet_enabled = false
	var before: float = weather.wet.get_pixel(1,0).g
	weather.tick(1.0,profile,Vector3.ZERO)
	check(weather.wet.get_pixel(1,0).g==before,"Wet module disabled stops updates")
	host.free()
	box.free()
	print("SHADING_LOGIC ","PASS" if failures==0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
