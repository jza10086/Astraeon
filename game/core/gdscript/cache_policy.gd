class_name AstraeonCachePolicy
extends RefCounted
## Scene-local runtime policy, separate from appearance resources and world saves.
const FORMAT: int = 1
const PRESETS: Array[Dictionary] = [
    {"cpu_mib":256,"gpu_mib":32,"retain_m":16,"mesh_seconds":5.0,"region_handles":16},
    {"cpu_mib":512,"gpu_mib":64,"retain_m":32,"mesh_seconds":15.0,"region_handles":32},
    {"cpu_mib":1024,"gpu_mib":128,"retain_m":64,"mesh_seconds":30.0,"region_handles":64}
]
const DEFAULTS: Dictionary = {"format":FORMAT,"cpu_mib":512,"gpu_mib":64,"retain_m":32,"mesh_seconds":15.0,"region_handles":32,"commit_usec":2000,"upload_usec":750,"upload_bytes":2097152,"slice_visits":4096,"slice_usec":2000,"prediction_seconds":0.75,"prediction_max_m":48.0}
var values: Dictionary = DEFAULTS.duplicate()
static func minimum_upload_bytes(horizontal_distance: int) -> int:
    # A section upload plus revoke/publish tables must fit as indivisible operations.
    var diameter: int = 2*(ceili(float(horizontal_distance)/16.0)+1)+1
    return 16384+2*diameter*diameter*17*4
func select_preset(index: int) -> void:
    values = DEFAULTS.duplicate()
    for key: String in PRESETS[index]: values[key] = PRESETS[index][key]
func preset_index() -> int:
    for index: int in range(PRESETS.size()):
        var matches: bool = true
        for key: String in PRESETS[index]:
            if values[key] != PRESETS[index][key]: matches = false
        for key: String in DEFAULTS:
            if not PRESETS[index].has(key) and values[key] != DEFAULTS[key]: matches = false
        if matches: return index
    return 3
func load_settings(path: String) -> Error:
    var config: ConfigFile = ConfigFile.new()
    var error: Error = config.load(path)
    if error != OK: return error
    if not config.has_section("cache"): return OK
    var format_value: Variant = config.get_value("cache","format",null)
    if not format_value is int or format_value != FORMAT: return ERR_FILE_UNRECOGNIZED
    var loaded: Dictionary = values.duplicate()
    for key: String in values:
        loaded[key] = config.get_value("cache",key,values[key])
    if not valid(loaded): return ERR_INVALID_DATA
    values = loaded
    return OK
func save_settings(path: String) -> Error:
    if not valid(values): return ERR_INVALID_DATA
    var config: ConfigFile = ConfigFile.new()
    var error: Error = config.load(path)
    if error != OK and error != ERR_FILE_NOT_FOUND: return error
    for key: String in values: config.set_value("cache",key,values[key])
    return config.save(path)
static func valid(data: Dictionary) -> bool:
    return data.get("format") is int and data.format == FORMAT and int(data.gpu_mib) >= 1 and int(data.gpu_mib) <= 128 and int(data.cpu_mib) >= 64 and int(data.cpu_mib) <= 8192 and int(data.retain_m) >= 0 and int(data.retain_m) <= 256 and int(data.region_handles) >= 1 and int(data.region_handles) <= 256 and float(data.mesh_seconds) >= 0.0 and float(data.mesh_seconds) <= 120.0 and int(data.commit_usec) >= 100 and int(data.commit_usec) <= 10000 and int(data.upload_usec) >= 100 and int(data.upload_usec) <= int(data.commit_usec) and int(data.upload_bytes) >= 16384 and int(data.upload_bytes) <= 16777216 and int(data.slice_visits) >= 64 and int(data.slice_visits) <= 65536 and int(data.slice_usec) >= 100 and int(data.slice_usec) <= 10000 and float(data.prediction_seconds) >= 0.0 and float(data.prediction_seconds) <= 3.0 and float(data.prediction_max_m) >= 0.0 and float(data.prediction_max_m) <= 128.0
