@abstract
extends SparePartBase
class_name BatteryBase

const CAPACITY_UNITS_PER_MAH := 0.25

func _init() -> void:
	slot_type = "battery"
	base_stats = {
		"battery_capacity_add": 80.0,
		"regen_factor_add": 0.05,
		"mass_add": 0.01
	}

func set_from_specs(capacity_mAh: float, mass_add: float = 0.01, regen_factor_add: float = 0.05) -> void:
	var capacity_units :float= max(0.0, capacity_mAh) * CAPACITY_UNITS_PER_MAH
	base_stats = {
		"battery_capacity_add": capacity_units,
		"regen_factor_add": regen_factor_add,
		"mass_add": mass_add
	}
	emit_signal("stats_changed")
