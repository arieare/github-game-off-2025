extends WheelBase
class_name WheelHard1

func _init() -> void:
	super()
	name_id = "wheel_hard_1"
	priority = 0
	base_stats = {
		"mass_add": 0.018,
		"rolling_resistance_add": 0.0045,
		"lateral_friction_scale_add": -0.020
	}
