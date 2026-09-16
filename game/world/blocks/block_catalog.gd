class_name AstraeonBlockCatalog
extends Resource
## Editor-authored collection. Build a fresh registry for each independent world/session.
const DEFINITION: Script = preload("res://game/world/blocks/block_definition.gd")
@export var definitions: Array[AstraeonBlockDefinition] = []
