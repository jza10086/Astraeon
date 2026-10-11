class_name AstraeonPlayerState
extends RefCounted
## Scene-local state. Rules decide whether to call mutations; these APIs are mode-neutral.
signal changed()
enum Mode { SURVIVAL, CREATIVE }
const MAX_HEALTH: int = 10
const MAX_HUNGER: int = 10
var before_commit: Callable
var can_change: Callable
var _mode: Mode = Mode.SURVIVAL
var _health: int = MAX_HEALTH
var _hunger: int = MAX_HUNGER
var mode: Mode:
	get: return _mode
var health: int:
	get: return _health
var hunger: int:
	get: return _hunger

func is_creative() -> bool:
	return _mode == Mode.CREATIVE

func snapshot() -> Dictionary:
	return {"mode": int(_mode), "health": _health, "hunger": _hunger}

## Restore only during load, before installing the durable commit guard.
func restore(data: Dictionary) -> bool:
	for key: String in ["mode", "health", "hunger"]:
		var value: Variant = data.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floorf(float(value)):
			return false
	if int(data.mode) not in [Mode.SURVIVAL, Mode.CREATIVE] or int(data.health) < 0 or int(data.health) > MAX_HEALTH or int(data.hunger) < 0 or int(data.hunger) > MAX_HUNGER:
		return false
	_mode = int(data.mode) as Mode
	_health = int(data.health)
	_hunger = int(data.hunger)
	changed.emit()
	return true

func set_mode(value: int) -> bool:
	if value not in [Mode.SURVIVAL, Mode.CREATIVE]:
		return false
	return _commit(value, _health, _hunger)

func increase_health(amount: int) -> bool:
	return false if amount < 0 else _commit(_mode, _health + mini(amount, MAX_HEALTH), _hunger)

func decrease_health(amount: int) -> bool:
	return false if amount < 0 else _commit(_mode, _health - mini(amount, MAX_HEALTH), _hunger)

func increase_hunger(amount: int) -> bool:
	return false if amount < 0 else _commit(_mode, _health, _hunger + mini(amount, MAX_HUNGER))

func decrease_hunger(amount: int) -> bool:
	return false if amount < 0 else _commit(_mode, _health, _hunger - mini(amount, MAX_HUNGER))

func _commit(next_mode: int, next_health: int, next_hunger: int) -> bool:
	if can_change.is_valid() and not bool(can_change.call()):
		return false
	var candidate: Dictionary = {"mode": next_mode, "health": clampi(next_health, 0, MAX_HEALTH), "hunger": clampi(next_hunger, 0, MAX_HUNGER)}
	if candidate == snapshot():
		return true
	if before_commit.is_valid() and not bool(before_commit.call(candidate)):
		return false
	return restore(candidate)
