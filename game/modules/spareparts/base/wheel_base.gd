@abstract
extends SparePartBase
class_name WheelBase

func _init() -> void:
	slot_type = "wheel"
	base_stats = {
		"rolling_resistance_add": 0.002,
		"mass_add": 0.005,
		# allow lateral tuning via wheel compound
		"lateral_friction_scale_add": 0.05
	}
