extends MotorBase
class_name MotorStandardKit

func _init() -> void:
	super()
	name_id = "motor_standard_kit"
	priority = 0
	# Real-world midpoints (RPM, mN·m, A)
	# 13,500 rpm, 1.8 mN·m load torque, 1.85 A current
	set_from_specs(13500.0, 1.8, 1.85)
	# Keep feel knobs neutral in the base motor:
	kv_speed_scale = 1.0
	kF_force_scale = 1.0
