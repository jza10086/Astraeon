class_name AstraeonBlockStateDefinition
extends Resource
## One explicitly authored, finite state. Keys are stable identifiers, not runtime IDs.
@export var key: StringName = &"default"
@export var properties: Dictionary[StringName, StringName] = {}
