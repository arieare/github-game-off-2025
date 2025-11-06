extends RollerBase
class_name RollerWildcard

func _init() -> void:
	super()
	name_id = "roller_wildcard"
	priority = 0
	base_stats = {
		"mass_add": 0.002,
		"roller_bonus_add": 0.00,
		"lateral_margin_add": -0.015,
		"rail_hit_penalty_mul": 1.15,
		"rail_hit_soft_threshold_add": -30.0,
		"max_rail_hits_add": 1
	}
