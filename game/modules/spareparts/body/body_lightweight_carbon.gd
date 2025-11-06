extends BodyBase
class_name BodyLightWeightCarbon

func _init() -> void:
	super()
	name_id = "body_lightweight_carbon"
	priority = 0
	base_stats = {
		"mass_add": 0.005,
		"drag_coefficient_add": -0.04,
		"frontal_area_add": 0.0006,
		"drag_area_mul": 0.92,
		"downforce_lateral_add": 0.215
	}
