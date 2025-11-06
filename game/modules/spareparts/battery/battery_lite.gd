extends BatteryBase
class_name BatteryLite

func _init() -> void:
	super()
	name_id = "battery_lite"
	# set_from_specs(mAh: float, mass_kg: float, regen_factor: float)
	# 950 mAh pack, ~0.048 kg (two AA NiMH ≈ 24 g each), mild recovery
	set_from_specs(950.0, 0.048, 0.04)
