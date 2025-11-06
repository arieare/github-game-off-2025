extends MotorBase
class_name MotorWildcard

func _init() -> void:
	super()
	name_id = "motor_wildcard"
	priority = 0
	# Aggressive motor: high speed/launch, heavy drain.
	set_direct(30.0, 2.50, -120.0)
