extends RollerBase
class_name RollerMetalMedium

func _init() -> void:
	super()
	name_id = "roller_metal_medium"
	priority = 0
	base_stats = {
		"mass_add": 0.030,
		"roller_bonus_add": 0.30,
		"lateral_margin_add": 0.035,
		"rail_hit_penalty_mul": 0.90
	}
