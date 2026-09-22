class_name AstraeonBlockStateDefinition
extends Resource
## One explicitly authored, finite state. Keys are stable identifiers, not runtime IDs.
@export var key: StringName = &"default"
@export var properties: Dictionary[StringName, StringName] = {}

## Allowed rotation for this state, relative to canonical up +Y. Instance selects a state; never mutate it.
@export var orientation: Basis = Basis.IDENTITY
