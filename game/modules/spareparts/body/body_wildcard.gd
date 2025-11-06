extends BodyBase
class_name BodyWildcard

func _init() -> void:
	super()
	name_id = "body_wildcard"
	priority = 0
	base_stats = {
		"mass_add": -0.040,
		"drag_area_mul": 0.85,
		"downforce_lateral_add": -0.180,
		"rail_hit_penalty_add": 0.10
	}
