@abstract
extends Node
class_name SparePartBase

signal stats_changed

var slot_type: String = ""          # "motor","battery","wheel","roller","body"
var priority: int = 0               # lower = applied earlier
var name_id: String = ""            # stable id for saves/catalogs

var base_stats: Dictionary = {}     # authoring defaults
var overrides: Dictionary = {}      # per-instance tweaks
var runtime: Dictionary = {}        # flags like { throttle_limit = 0.7 }

func _ready() -> void:
	var group_name: String = ""
	if slot_type != "":
		group_name = "slot_" + slot_type.to_lower()
	if group_name != "" and not is_in_group(group_name):
		add_to_group(group_name)

func get_slot_type() -> String:
	return slot_type.to_lower()

func get_priority() -> int:
	return priority

func get_part_stats() -> Dictionary:
	# Merge base_stats + overrides; include runtime under a namespaced key.
	var merged: Dictionary = {}
	for k in base_stats.keys():
		merged[k] = base_stats[k]
	for k in overrides.keys():
		merged[k] = overrides[k]
	if not runtime.is_empty():
		merged["runtime"] = runtime.duplicate(true)
	return merged

func set_stats(new_stats: Dictionary) -> void:
	base_stats = new_stats.duplicate(true)
	emit_signal("stats_changed")

func set_overrides(new_overrides: Dictionary) -> void:
	overrides = new_overrides.duplicate(true)
	emit_signal("stats_changed")

func set_runtime(new_runtime: Dictionary) -> void:
	runtime = new_runtime.duplicate(true)
	emit_signal("stats_changed")
