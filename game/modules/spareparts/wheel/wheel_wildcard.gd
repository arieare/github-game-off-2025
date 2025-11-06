extends WheelBase
class_name WheelWildcard

func _init() -> void:
	super()
	name_id = "wheel_wildcard"
	priority = 0
	base_stats = {
		"mass_add": 0.0020,
		"rolling_resistance_add": 0.0003,
		"lateral_friction_scale_add": -0.080,
		"downforce_lateral_add": -0.012
	}
