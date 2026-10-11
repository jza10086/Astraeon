@tool
class_name AstraeonBlockAsset
extends Resource
## One editable block file. Nested definitions are private authoring data, not runtime instances.
@export var block: AstraeonBlockDefinition
## Optional corresponding item. Its block field must be empty; compilation binds it to block.
@export var item: AstraeonItemDefinition
## Slots: surface/default, surface/0..5, breaking, item/icon. Values index the package images map.
@export var image_slots: Dictionary[String, StringName] = {}
