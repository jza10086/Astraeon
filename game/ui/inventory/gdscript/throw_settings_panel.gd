extends VBoxContainer
## Reused by title settings and the paused world; caller owns persistence.
const Settings: Script = preload("res://game/gameplay/inventory/gdscript/throw_settings.gd")
var settings: Settings
var strength: SpinBox
var mining_player_strength: SpinBox

func configure(value: Settings) -> void:
	settings = value
	if strength == null:
		var label: Label = Label.new()
		label.text = "物品投掷 · 扔出力度（m/s）"
		add_child(label)
		strength = SpinBox.new()
		strength.min_value = 1.0
		strength.max_value = 20.0
		strength.step = 0.5
		strength.custom_minimum_size.y = 44
		strength.tooltip_text = "从右手朝指针方向投掷的初速度；之后受重力影响。"
		add_child(strength)
		strength.value_changed.connect(func(number: float) -> void: settings.strength = number)
		var mining_label: Label = Label.new()
		mining_label.text = "挖掘掉落 · 朝玩家力度（m/s）"
		add_child(mining_label)
		mining_player_strength = SpinBox.new()
		mining_player_strength.min_value = 0.0
		mining_player_strength.max_value = 10.0
		mining_player_strength.step = 0.5
		mining_player_strength.custom_minimum_size.y = 44
		mining_player_strength.tooltip_text = "挖掘掉落瞬间朝玩家水平方向增加的初速度；0 表示不偏向玩家，仍随机散开并向上弹起。"
		add_child(mining_player_strength)
		mining_player_strength.value_changed.connect(func(number: float) -> void: settings.mining_player_strength = number)
	strength.set_value_no_signal(settings.strength)
	mining_player_strength.set_value_no_signal(settings.mining_player_strength)
