extends Resource
## Local gameplay settings, independent of shading and world saves.
@export_range(1.0, 20.0, 0.5) var strength: float = 6.0
@export_range(0.0, 10.0, 0.5) var mining_player_strength: float = 0.0

func load_settings(path: String) -> Error:
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(path)
	if error == ERR_FILE_NOT_FOUND:
		return OK
	if error != OK:
		return error
	var next_strength: float = 6.0
	var next_mining_strength: float = 0.0
	if config.has_section("throwing"):
		if config.get_value("throwing", "format", 0) != 1:
			return ERR_FILE_UNRECOGNIZED
		var value: Variant = config.get_value("throwing", "strength")
		if not _valid_strength(value, 1.0, 20.0):
			return ERR_INVALID_DATA
		next_strength = float(value)
	if config.has_section("mining_drops"):
		if config.get_value("mining_drops", "format", 0) != 1:
			return ERR_FILE_UNRECOGNIZED
		var value: Variant = config.get_value("mining_drops", "player_strength")
		if not _valid_strength(value, 0.0, 10.0):
			return ERR_INVALID_DATA
		next_mining_strength = float(value)
	strength = next_strength
	mining_player_strength = next_mining_strength
	return OK

func save_settings(path: String) -> Error:
	if not _valid_strength(strength, 1.0, 20.0) or not _valid_strength(mining_player_strength, 0.0, 10.0):
		return ERR_INVALID_DATA
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		return error
	config.set_value("throwing", "format", 1)
	config.set_value("throwing", "strength", strength)
	config.set_value("mining_drops", "format", 1)
	config.set_value("mining_drops", "player_strength", mining_player_strength)
	var temporary: String = path + ".tmp"
	error = config.save(temporary)
	if error != OK:
		return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))

static func _valid_strength(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum
