class_name AstraeonItemStack
extends RefCounted
var item: AstraeonItemDefinition
var count: int

func _init(definition: AstraeonItemDefinition = null, quantity: int = 0) -> void:
	item = definition
	count = quantity

func copy() -> AstraeonItemStack:
	return AstraeonItemStack.new(item, count)
