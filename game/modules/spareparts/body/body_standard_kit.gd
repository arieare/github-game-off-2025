extends BodyBase
class_name BodyStandardKit

func _init() -> void:
	super()
	name_id = "body_standard_kit"
	priority = 0
	base_stats = {
		"mass_add": 0.135,
		"drag_coefficient_add": -0.04,
		"frontal_area_add": 0.0006,
		"drag_area_mul": 0.92,
		"downforce_lateral_add": 0.215
	}
