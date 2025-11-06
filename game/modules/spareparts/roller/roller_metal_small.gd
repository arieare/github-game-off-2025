extends RollerBase
class_name RollerMetalSmall

func _init() -> void:
	super()
	name_id = "roller_metal_small"
	priority = 0
	base_stats = {
		"mass_add": 0.020,
		"roller_bonus_add": 0.25,
		"lateral_margin_add": 0.030,
		"rail_hit_penalty_mul": 0.92
	}
