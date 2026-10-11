@tool
class_name AstraeonContentManifest
extends Resource
## Editable package project. Images are file indexes, never runtime Texture2D dependencies.
@export var project_format: int = 2
@export var package_id: String = "example"
@export var display_name: String = "Example content"
@export var content_api: int = 1
@export var dependencies: PackedStringArray = []
@export var blocks: Array[AstraeonBlockAsset] = []
@export var fluids: Array[AstraeonFluidDefinition] = []
@export var items: Array[AstraeonItemAsset] = []
@export var creative_groups: Dictionary[StringName, String] = {}
## Absolute file paths or paths relative to this project's .tres directory.
@export var image_sources: Dictionary[StringName, String] = {}
