extends RollerBase
class_name RollerStandardKit

func _init() -> void:
	super()
	name_id = "roller_standard_kit"
	priority = 0
	# ~3 g each; modest stability assist; soften small rail hits
	base_stats = {
		"mass_add": 0.0030,
		"roller_bonus_add": 0.9,
		"lateral_margin_add": 0.120,
		"rail_hit_penalty_mul": 0.96
	}
