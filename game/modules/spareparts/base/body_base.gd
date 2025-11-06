@abstract
extends SparePartBase
class_name BodyBase

func _init() -> void:
	slot_type = "body"
	base_stats = {
		"mass_add": 0.01,
		"drag_coefficient_add": -0.05,
		"frontal_area_add": 0.0003,
		# optional direct Cd·A editing supported by your car component
		# "drag_area_mul": 0.98
	}
