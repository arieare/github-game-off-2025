extends SparePartBase
class_name MotorBase

# Reference parameters for converting real-world specs
@export var ref_wheel_radius: float = 0.013      # meters (≈26 mm diameter)
@export var ref_gear_ratio: float = 3.5          # unitless
@export var ref_gear_eff: float = 0.85           # 0..1
@export var ref_load_ratio: float = 0.5          # load speed / free speed
@export var ref_I_ref: float = 1.85              # A; baseline current for penalties

# Feel calibration knobs
@export var kv_speed_scale: float = 1.0          # scales computed free_speed
@export var kF_force_scale: float = 1.0          # scales computed drive force
@export var kI_penalty_gain: float = 25.0        # capacity units per amp over ref

func _init() -> void:
	# This is a base for concrete motors; provide mild defaults
	slot_type = "motor"
	base_stats = {
		"drive_force_max_add": 0.4,
		"free_speed_add": 2.0,
		"regen_factor_add": 0.0
	}

# --- Public API ---
# Directly set additive stats (bypasses converter)
func set_direct(free_speed_add: float, drive_force_max_add: float, battery_capacity_add: float = 0.0) -> void:
	var stats: Dictionary = {}
	stats["free_speed_add"] = free_speed_add
	stats["drive_force_max_add"] = drive_force_max_add
	stats["battery_capacity_add"] = battery_capacity_add
	base_stats = stats
	emit_signal("stats_changed")

# Use real-world specs (RPM, torque mN·m, current A) with exported references
func set_from_specs(rpm_free: float, torque_load_mNm: float, current_A: float) -> void:
	var stats: Dictionary = specs_to_stats(rpm_free, torque_load_mNm, current_A)
	base_stats = stats
	emit_signal("stats_changed")

# Convert real-world specs to game stats using current references
func specs_to_stats(rpm_free: float, torque_load_mNm: float, current_A: float) -> Dictionary:
	var wheel_radius: float = ref_wheel_radius
	var gear_ratio: float = ref_gear_ratio
	var gear_eff: float = ref_gear_eff
	var load_ratio: float = ref_load_ratio
	var I_ref: float = ref_I_ref
	var kI: float = kI_penalty_gain
	return compute_specs_to_stats(rpm_free, torque_load_mNm, current_A, wheel_radius, gear_ratio, gear_eff, load_ratio, I_ref, kI, kv_speed_scale, kF_force_scale)

# Static utility if you want to call with explicit parameters from tools
static func compute_specs_to_stats(
		rpm_free: float,
		torque_load_mNm: float,
		current_A: float,
		wheel_radius: float,
		gear_ratio: float,
		gear_eff: float,
		load_ratio: float,
		I_ref: float,
		kI: float,
		kv_speed_scale: float = 1.0,
		kF_force_scale: float = 1.0
	) -> Dictionary:
	# Free speed (m/s): rpm -> rad/s -> linear / ratio
	var v_free: float = (rpm_free / 60.0) * TAU * wheel_radius / gear_ratio
	v_free = v_free * kv_speed_scale

	# Stall torque estimate from load torque and load speed ratio
	var denom: float = 1.0 - load_ratio
	if denom < 0.05:
		denom = 0.05
	var tau_stall: float = (torque_load_mNm * 1e-3) / denom   # N·m

	# Drive force at wheel (N)
	var F_drive: float = (tau_stall * gear_ratio * gear_eff) / max(1e-6, wheel_radius)
	F_drive = F_drive * kF_force_scale

	# Battery capacity penalty (units)
	var cap_penalty: float = -kI * (current_A - I_ref)

	var out: Dictionary = {}
	out["free_speed_add"] = v_free
	out["drive_force_max_add"] = F_drive
	out["battery_capacity_add"] = cap_penalty
	return out
