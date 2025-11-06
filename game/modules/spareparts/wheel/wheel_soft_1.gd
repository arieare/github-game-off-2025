extends WheelBase
class_name WheelSoft1

func _init() -> void:
	super()
	name_id = "wheel_soft_1"
	priority = 0
	base_stats = {
		"mass_add": 0.022,
		"rolling_resistance_add": 0.0020,
		"lateral_friction_scale_add": 0.120,
		"downforce_lateral_add": 0.010
	}
