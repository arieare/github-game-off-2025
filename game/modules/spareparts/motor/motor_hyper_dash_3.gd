extends MotorBase
class_name MotorHyperDash3

func _init() -> void:
	super()
	name_id = "hyper_dash_3"
	priority = 0
	# Target around 10 m/s free speed with moderate punch.
	set_direct(
		22.0,  # free_speed_add → ≈10 m/s top speed
		10.0,   # drive_force_max_add → gentler launch
		0.0    # battery_capacity_add → neutral drain
	)
