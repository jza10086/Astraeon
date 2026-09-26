class_name AstraeonInventoryState
extends RefCounted
## All mutations validate a complete candidate before committing. Readers receive stack copies.
signal changed()
var definition: AstraeonInventoryDefinition
var items: Dictionary[StringName, AstraeonItemDefinition] = {}
var selected: int = 0
var revision: int = 0
var locked: bool = false
## Optional durable commit guard(snapshot, edit_context) -> bool. Called before publication.
var before_commit: Callable
var _slots: Array[AstraeonItemStack] = []

func configure(catalog: AstraeonItemCatalog, layout: AstraeonInventoryDefinition) -> bool:
	if definition != null or not catalog.validate().is_empty() or layout.hotbar_slots != 10 or layout.storage_rows != 3:
		return false
	definition = layout
	for item: AstraeonItemDefinition in catalog.definitions:
		items[item.key] = item
	_slots.resize(layout.slot_count())
	return true

func stack_at(index: int) -> AstraeonItemStack:
	return _slots[index].copy() if index >= 0 and index < _slots.size() and _slots[index] != null else null

func snapshot() -> Dictionary:
	return _encode(_slots, selected)

func _encode(slots: Array[AstraeonItemStack], selection: int) -> Dictionary:
	var entries: Array[Dictionary] = []
	for stack: AstraeonItemStack in slots:
		entries.append({} if stack == null else {"item": String(stack.item.key), "count": stack.count})
	return {"selected": selection, "slots": entries}

func restore(data: Dictionary) -> bool:
	var entries: Variant = data.get("slots")
	var choice: Variant = data.get("selected")
	if not entries is Array or entries.size() != _slots.size() or not _integer(choice) or int(choice) < 0 or int(choice) >= definition.hotbar_slots:
		return false
	var candidate: Array[AstraeonItemStack] = []
	for entry: Variant in entries:
		if not entry is Dictionary:
			return false
		if entry.is_empty():
			candidate.append(null)
			continue
		var key: StringName = StringName(str(entry.get("item", "")))
		var quantity: Variant = entry.get("count")
		if not items.has(key) or not _integer(quantity) or int(quantity) < 1 or int(quantity) > items[key].max_stack:
			return false
		candidate.append(AstraeonItemStack.new(items[key], int(quantity)))
	_slots = candidate
	selected = int(choice)
	revision += 1
	changed.emit()
	return true

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))

func _copy_slots() -> Array[AstraeonItemStack]:
	var result: Array[AstraeonItemStack] = []
	for stack: AstraeonItemStack in _slots:
		result.append(stack.copy() if stack != null else null)
	return result

func _commit(candidate: Array[AstraeonItemStack], choice: int, context: Dictionary = {}) -> bool:
	if locked:
		return false
	if before_commit.is_valid() and not bool(before_commit.call(_encode(candidate, choice), context)):
		return false
	_slots = candidate
	selected = choice
	revision += 1
	changed.emit()
	return true

func select(index: int) -> bool:
	if index < 0 or index >= definition.hotbar_slots:
		return false
	return true if selected == index else _commit(_copy_slots(), index)

func capacity(key: StringName) -> int:
	if not items.has(key):
		return 0
	var total: int = 0
	for stack: AstraeonItemStack in _slots:
		if stack == null:
			total += items[key].max_stack
		elif stack.item.key == key:
			total += items[key].max_stack - stack.count
	return total

## Returns uninserted quantity. Guard failure returns the complete original quantity.
func insert(key: StringName, quantity: int, context: Dictionary = {}) -> int:
	if quantity <= 0 or not items.has(key) or locked:
		return quantity
	var candidate: Array[AstraeonItemStack] = _copy_slots()
	var left: int = quantity
	for pass_index: int in range(2):
		for index: int in range(candidate.size()):
			var stack: AstraeonItemStack = candidate[index]
			if (pass_index == 0 and stack == null) or (pass_index == 1 and stack != null):
				continue
			if stack != null and stack.item.key != key:
				continue
			var amount: int = mini(left, items[key].max_stack - (stack.count if stack != null else 0))
			if amount > 0:
				if stack == null:
					stack = AstraeonItemStack.new(items[key], 0)
					candidate[index] = stack
				stack.count += amount
				left -= amount
	if left == quantity:
		return left
	return left if _commit(candidate, selected, context) else quantity

func consume(index: int, quantity: int, context: Dictionary = {}) -> bool:
	var stack: AstraeonItemStack = stack_at(index)
	if quantity <= 0 or stack == null or stack.count < quantity:
		return false
	var candidate: Array[AstraeonItemStack] = _copy_slots()
	candidate[index].count -= quantity
	if candidate[index].count == 0:
		candidate[index] = null
	return _commit(candidate, selected, context)

## Exact revision prevents a stale drag from moving a newly changed stack. Full incompatible stacks swap.
func move(source: int, target: int, quantity: int, expected_revision: int) -> bool:
	if expected_revision != revision or source == target or target < 0 or target >= _slots.size() or quantity <= 0:
		return false
	var from: AstraeonItemStack = stack_at(source)
	if from == null or from.count < quantity:
		return false
	var candidate: Array[AstraeonItemStack] = _copy_slots()
	var to: AstraeonItemStack = candidate[target]
	if to != null and to.item.key != from.item.key:
		if quantity != from.count:
			return false
		candidate[source] = to
		candidate[target] = from
	else:
		var amount: int = mini(quantity, from.item.max_stack - (to.count if to != null else 0))
		if amount == 0:
			return false
		candidate[target] = AstraeonItemStack.new(from.item, amount + (to.count if to != null else 0))
		candidate[source].count -= amount
		if candidate[source].count == 0:
			candidate[source] = null
	return _commit(candidate, selected)

func quick_move(source: int) -> bool:
	var from: AstraeonItemStack = stack_at(source)
	if from == null:
		return false
	var candidate: Array[AstraeonItemStack] = _copy_slots()
	var first: int = 10 if source < 10 else 0
	var last: int = 40 if source < 10 else 10
	var left: int = from.count
	for pass_index: int in range(2):
		for target: int in range(first, last):
			var to: AstraeonItemStack = candidate[target]
			if (pass_index == 0 and to == null) or (pass_index == 1 and to != null) or (to != null and to.item.key != from.item.key):
				continue
			var amount: int = mini(left, from.item.max_stack - (to.count if to != null else 0))
			if amount > 0:
				candidate[target] = AstraeonItemStack.new(from.item, amount + (to.count if to != null else 0))
				left -= amount
	if left == from.count:
		return false
	candidate[source] = AstraeonItemStack.new(from.item, left) if left > 0 else null
	return _commit(candidate, selected)
