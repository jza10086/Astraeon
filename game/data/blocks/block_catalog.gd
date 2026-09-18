class_name AstraeonBlockCatalog
extends Resource
## Editor-authored collection. Authoring example only; not the active native block ID table.
const DEFINITION: Script = preload("res://game/data/blocks/block_definition.gd")
@export var definitions: Array[AstraeonBlockDefinition] = []
