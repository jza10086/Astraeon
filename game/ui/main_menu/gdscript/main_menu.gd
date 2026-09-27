extends Control
const Paths: Script = preload("res://game/core/gdscript/project_paths.gd")
## Title navigation owns no world state; the existing world loads only after play.
const CharacterSelect: Script = preload("res://game/ui/main_menu/gdscript/character_select.gd")
var character_page: CharacterSelect
const Profile: Script = preload("res://game/shading/gdscript/shading_profile.gd")
const SettingsPanel: Script = preload("res://game/shading/gdscript/settings_panel.gd")
@export_file("*.tscn") var world_scene_path: String = "res://game/core/main.tscn"
@export var default_profile: Profile = preload("res://game/shading/resources/default_profile.tres")
@export var settings_path: String = Paths.settings_file()
@onready var home: Control = %Home
@onready var play_button: Button = %Play
@onready var settings_button: Button = %Settings
@onready var settings_page: Control = %SettingsPage
@onready var settings_body: VBoxContainer = %SettingsBody
@onready var settings_status: Label = %SettingsStatus
@onready var status: Label = %Status
@onready var quit_dialog: ConfirmationDialog = %QuitDialog
var panel: SettingsPanel
var draft: Profile
var loading: bool = false
var _settings_writable: bool = true

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	%Characters.pressed.connect(_open_characters)
	%Play.pressed.connect(_start_game)
	%Settings.pressed.connect(_open_settings)
	%Quit.pressed.connect(_confirm_quit)
	%Apply.pressed.connect(_apply_settings)
	%Back.pressed.connect(_close_settings)
	quit_dialog.confirmed.connect(func() -> void: get_tree().quit())
	quit_dialog.canceled.connect(func() -> void: %Quit.grab_focus())
	play_button.grab_focus()
	set_process(false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not loading:
		if character_page != null and character_page.visible:
			character_page.cancel()
		elif settings_page.visible:
			_close_settings()
		elif not quit_dialog.visible:
			_confirm_quit()
		get_viewport().set_input_as_handled()

func _confirm_quit() -> void:
	quit_dialog.popup_centered(Vector2i(480, 190))
	quit_dialog.get_cancel_button().grab_focus()

func _open_settings() -> void:
	draft = default_profile.duplicate(true) as Profile
	var error: Error = draft.load_settings(settings_path)
	_settings_writable = error == OK or error == ERR_FILE_NOT_FOUND
	settings_status.text = "修改后点击「保存并返回」；返回或 Esc 放弃本次修改。"
	if not _settings_writable:
		draft = default_profile.duplicate(true) as Profile
		settings_status.text = "设置文件无法读取（%s），未覆盖原文件。" % error_string(error)
	%Apply.disabled = not _settings_writable
	if panel == null:
		panel = SettingsPanel.new()
		panel.build(settings_body, draft, _settings_changed)
		# These controls require a running test fixture, not the title screen.
		for key: StringName in panel.rows.keys():
			if String(key).begins_with("avatar_") or String(key).begins_with("test_") or key in [&"work_cells", &"work_usec", &"lamp_emission_color", &"gloss_metal_roughness", &"gloss_metal_metallic", &"gloss_metal_specular"]:
				panel.rows[key].queue_free()
				panel.rows.erase(key)
				panel.widgets.erase(key)
	else:
		panel.profile = draft
		panel.sync(draft)
	home.hide()
	settings_page.show()
	%SettingsScroll.scroll_vertical = 0
	panel.category.grab_focus()

func _settings_changed() -> void:
	panel.sync(draft)

func _close_settings() -> void:
	settings_page.hide()
	home.show()
	settings_button.grab_focus()

func _apply_settings() -> void:
	if not _settings_writable:
		return
	var error: Error = draft.save_settings(settings_path)
	if error != OK:
		settings_status.text = "保存失败：%s。请重试，或返回放弃修改。" % error_string(error)
		return
	status.text = "设置已保存"
	_close_settings()

func _start_game() -> void:
	if loading:
		return
	var error: Error = ResourceLoader.load_threaded_request(world_scene_path, "PackedScene")
	if error != OK:
		status.text = "无法打开世界：%s。请重试。" % error_string(error)
		return
	loading = true
	%Characters.disabled = true
	%Play.disabled = true
	%Settings.disabled = true
	%Quit.disabled = true
	status.text = "正在载入世界…"
	set_process(true)

func _process(_delta: float) -> void:
	var progress: Array = []
	var state: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(world_scene_path, progress)
	if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		status.text = "正在载入世界… %d%%" % int(float(progress[0]) * 100.0) if not progress.is_empty() else "正在载入世界…"
		return
	if state == ResourceLoader.THREAD_LOAD_LOADED:
		var scene: PackedScene = ResourceLoader.load_threaded_get(world_scene_path) as PackedScene
		if scene != null:
			var error: Error = get_tree().change_scene_to_packed(scene)
			if error == OK:
				set_process(false)
				return
	_finish_loading_error()

func _finish_loading_error() -> void:
	loading = false
	set_process(false)
	%Characters.disabled = false
	%Play.disabled = false
	%Settings.disabled = false
	%Quit.disabled = false
	status.text = "世界载入失败，请重试。"
	play_button.grab_focus()

func _open_characters() -> void:
	if loading:
		return
	if character_page == null:
		character_page = CharacterSelect.new()
		character_page.name = "CharacterSelect"
		add_child(character_page)
		character_page.closed.connect(_close_characters)
	home.hide()
	character_page.open(settings_path)

func _close_characters(selected: bool) -> void:
	home.show()
	if selected:
		status.text = "人物已保存，进入世界后生效"
	%Characters.grab_focus()
