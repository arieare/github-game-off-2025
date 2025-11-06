extends WheelBase
class_name WheelStandardKit

func _init() -> void:
	super()
	name_id = "wheel_standard_kit"
	priority = 0
	# Medium grip compound tuned for general-purpose kits.
	base_stats = {
		"mass_add": 0.020,
		"rolling_resistance_add": 0.0030,
		"lateral_friction_scale_add": 0.060,
		"downforce_lateral_add": 0.008
	}
