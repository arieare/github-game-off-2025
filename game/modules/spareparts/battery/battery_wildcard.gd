extends BatteryBase
class_name BatteryWildcard

func _init() -> void:
	super()
	name_id = "battery_wildcard"
	#priority = 0
	# Light and low-capacity pack for sprint setups.
	set_from_specs(900.0, 0.030, 0.00)
