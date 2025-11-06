@abstract
extends SparePartBase
class_name RollerBase

func _init() -> void:
	slot_type = "roller"
	base_stats = {
		"roller_bonus_add": 0.2,
		"lateral_margin_add": 0.02,
		"rail_hit_penalty_mul": 0.95
	}
