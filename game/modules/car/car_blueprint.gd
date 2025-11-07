extends Resource
class_name CarBlueprint

@export_group("Metadata")
@export var car_name: String = ""
@export var designed_by: String = ""
@export var metadata: Dictionary = {}
@export var version: int = 1

@export_group("Car Composition")
@export var sparepart_slot: Dictionary = {
	"body": {},
	"motor": {},
	"battery": {},
	"wheels": [],
	"rollers": []
}

func set_slot_data(slot_name: String, value: Variant) -> void:
	if slot_name == "":
		return
	sparepart_slot[slot_name] = _deep_copy(value)

func get_slot_data(slot_name: String, default_value: Variant = null) -> Variant:
	if sparepart_slot.has(slot_name):
		return _deep_copy(sparepart_slot[slot_name])
	return _deep_copy(default_value)

func to_dict() -> Dictionary:
	return {
		"version": version,
		"car_name": car_name,
		"designed_by": designed_by,
		"metadata": _deep_copy(metadata),
		"slots": _deep_copy(sparepart_slot)
	}

func from_dict(data: Dictionary) -> void:
	version = int(data.get("version", version))
	car_name = String(data.get("car_name", car_name))
	designed_by = String(data.get("designed_by", designed_by))
	var meta = data.get("metadata", metadata)
	if meta is Dictionary:
		metadata = _deep_copy(meta)
	var slots = data.get("slots", sparepart_slot)
	if slots is Dictionary:
		sparepart_slot = _deep_copy(slots)

func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	if value is PackedStringArray:
		return PackedStringArray(value)
	return value
