@tool
class_name AstraeonBlockCatalog
extends Resource
## Editor-authored collection. Static authoring only; not the active native block ID table.
const DEFINITION: Script = preload("res://game/data/block/gdscript/block_definition.gd")
@export var definitions: Array[AstraeonBlockDefinition] = []
