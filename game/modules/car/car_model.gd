extends Resource
class_name CarModel

## Holds car runtime state and derived parameters for the simulation.

const DEFAULT_MASS: float = 0.14
const DEFAULT_CRR: float = 0.03
const DEFAULT_DRAG_COEFF: float = 0.9
const DEFAULT_FRONTAL_AREA: float = 0.008
const DEFAULT_BATTERY_CAPACITY: float = 100.0
const GRAVITY: float = 9.80665
const AIR_DENSITY: float = 1.225
const AIR_DRAG_SCALE: float = 1.2
const AIR_PENALTY_FACTOR: float = 0.5
const DEFAULT_FREE_SPEED: float = 8.0

class CarParams:
	extends RefCounted

	var mass: float = DEFAULT_MASS
	var rolling_resistance: float = DEFAULT_CRR
	var drag_coefficient: float = DEFAULT_DRAG_COEFF
	var frontal_area: float = DEFAULT_FRONTAL_AREA
	var drive_force_max: float = 0.8
	var free_speed: float = DEFAULT_FREE_SPEED
	var battery_capacity: float = DEFAULT_BATTERY_CAPACITY
	var regen_factor: float = 0.0
	var drag_area: float = DEFAULT_DRAG_COEFF * DEFAULT_FRONTAL_AREA
	var lateral_friction_scale: float = 1.0
	var downforce_lateral: float = 0.0
	var roller_bonus: float = 0.0
	var lateral_margin: float = 0.05
	var rail_hit_penalty: float = 0.75
	var rail_hit_soft_threshold: float = 5.0
	var max_rail_hits: int = 3

	func _init(data: Dictionary = {}) -> void:
		if not data.is_empty():
			configure(data)

	func configure(data: Dictionary) -> void:
		mass = float(data.get("mass", mass))
		rolling_resistance = float(data.get("rolling_resistance", rolling_resistance))
		drag_coefficient = float(data.get("drag_coefficient", drag_coefficient))
		frontal_area = float(data.get("frontal_area", frontal_area))
		drive_force_max = float(data.get("drive_force_max", drive_force_max))
		free_speed = float(data.get("free_speed", free_speed))
		battery_capacity = float(data.get("battery_capacity", battery_capacity))
		regen_factor = float(data.get("regen_factor", regen_factor))
		# Allow explicit drag_area override; reconcile with Cd/A if one is missing
		if data.has("drag_area"):
			drag_area = max(0.0, float(data["drag_area"]))
			var has_cd: bool = data.has("drag_coefficient")
			var has_A: bool = data.has("frontal_area")
			if has_A and not has_cd:
				drag_coefficient = drag_area / max(1e-6, frontal_area)
			elif has_cd and not has_A:
				frontal_area = drag_area / max(1e-6, drag_coefficient)
			# if both provided, trust caller; if neither, keep current Cd/A
		else:
			drag_area = drag_coefficient * frontal_area
		lateral_friction_scale = float(data.get("lateral_friction_scale", lateral_friction_scale))
		downforce_lateral = float(data.get("downforce_lateral", downforce_lateral))
		roller_bonus = float(data.get("roller_bonus", roller_bonus))
		lateral_margin = float(data.get("lateral_margin", lateral_margin))
		rail_hit_penalty = clamp(float(data.get("rail_hit_penalty", rail_hit_penalty)), 0.1, 1.0)
		rail_hit_soft_threshold = max(0.0, float(data.get("rail_hit_soft_threshold", rail_hit_soft_threshold)))
		max_rail_hits = max(0, int(data.get("max_rail_hits", max_rail_hits)))

class CarState:
	extends RefCounted

	var position_s: float = 0.0
	var velocity: float = 0.0
	var battery_charge: float = 0.0
	var lane: int = 1
	var laps_completed: int = 0
	var finished: bool = false
	var rail_hits: int = 0

	# Airborne/vertical
	var in_air: bool = false
	var altitude: float = 0.0
	var vertical_velocity: float = 0.0
	var air_time: float = 0.0
	var stability_cooldown: float = 0.0
	var airborne_heading: float = 0.0
	var airborne_origin: Vector2 = Vector2.ZERO
	var above_divider: bool = false

	func reset(battery_capacity: float) -> void:
		position_s = 0.0
		velocity = 0.0
		battery_charge = max(0.0, battery_capacity)
		lane = 1
		laps_completed = 0
		finished = false
		rail_hits = 0
		in_air = false
		altitude = 0.0
		vertical_velocity = 0.0
		air_time = 0.0
		stability_cooldown = 0.0
		airborne_heading = 0.0
		airborne_origin = Vector2.ZERO
		above_divider = false

var base_params: CarParams = CarParams.new()
var state: CarState = CarState.new()
var parts: Dictionary = {}
var battery_drain_rate: float = 0.05
var drag_factor: float = 0.001
var divider_height: float = 0.05

func mass() -> float:
	return base_params.mass

func lateral_bonus(speed: float) -> float:
	# Simple model: downforce_lateral scales with v^2; roller_bonus is a flat reserve
	var v2: float = speed * speed
	return max(0.0, base_params.downforce_lateral * v2 + base_params.roller_bonus)

func _init(params_data: Dictionary = {}, parts_data: Dictionary = {}) -> void:
	if not params_data.is_empty():
		base_params.configure(params_data)
		divider_height = float(params_data.get("divider_height", divider_height))
	parts = parts_data.duplicate(true)
	state.battery_charge = base_params.battery_capacity

func set_params(params_data: Dictionary) -> void:
	base_params.configure(params_data)
	divider_height = float(params_data.get("divider_height", divider_height))

func set_parts(parts_data: Dictionary) -> void:
	parts = parts_data.duplicate(true)

func get_car_state() -> CarState:
	return state

func set_car_state(new_state: CarState) -> void:
	state = new_state

func reset_car_state() -> void:
	# Reset car state using the base battery capacity.
	state.reset(base_params.battery_capacity)

func get_lateral_mu(track_signal: TrackModel.TrackSignal) -> float:
	return max(0.0, base_params.lateral_friction_scale * max(track_signal.lateral_friction, 0.0))

func apply_speed_penalty(factor: float) -> void:
	state.velocity = max(0.0, state.velocity * clamp(factor, 0.0, 1.0))

func register_rail_hit() -> void:
	state.rail_hits += 1

func reset_rail_hits() -> void:
	state.rail_hits = 0

func mark_derailed() -> void:
	state.in_air = true
	state.altitude = max(state.altitude, 0.0)
	state.vertical_velocity = 0.0
	state.airborne_heading = 0.0
	state.airborne_origin = Vector2.ZERO
	state.above_divider = true

func set_airborne(altitude: float, vertical_velocity: float, launch_heading: float = 0.0, launch_origin: Vector2 = Vector2.ZERO, above_divider: bool = false) -> void:
	state.altitude = max(altitude, 0.0)
	state.vertical_velocity = vertical_velocity
	state.in_air = true
	state.air_time = 0.0
	state.stability_cooldown = max(state.stability_cooldown, 0.0)
	state.airborne_heading = launch_heading
	state.airborne_origin = launch_origin
	state.above_divider = above_divider

func add_air_time(duration: float) -> void:
	if duration <= 0.0:
		return
	state.air_time += duration

func apply_air_penalty(duration: float, impact_speed: float) -> void:
	if duration <= 0.0 and impact_speed <= 0.0:
		return
	var penalty: float = duration * battery_drain_rate * AIR_PENALTY_FACTOR + impact_speed * 0.02
	if penalty <= 0.0:
		return
	state.battery_charge = max(0.0, state.battery_charge - penalty)

func land(impact_speed: float = 0.0, air_duration: float = 0.0, retention: float = 1.0) -> void:
	state.in_air = false
	state.altitude = 0.0
	state.vertical_velocity = 0.0
	state.airborne_heading = 0.0
	state.airborne_origin = Vector2.ZERO
	state.above_divider = false
	if retention < 1.0:
		retention = clamp(retention, 0.0, 1.0)
		apply_speed_penalty(retention)
	elif impact_speed > 0.0:
		var penalty: float = clamp(1.0 - impact_speed * 0.05, 0.5, 1.0)
		apply_speed_penalty(penalty)
	apply_air_penalty(air_duration, impact_speed)
	state.air_time = 0.0
	state.stability_cooldown = max(state.stability_cooldown, 0.0)
	reset_rail_hits()

func is_battery_depleted(threshold: float = 1e-3) -> bool:
	return state.battery_charge <= threshold

func update_force(track_signal: TrackModel.TrackSignal, delta: float) -> float:
	# Update forces and return longitudinal acceleration (m/s^2).
	if base_params.mass <= 0.0:
		return 0.0

	var signal_data: TrackModel.TrackSignal = track_signal
	if signal_data == null:
		signal_data = TrackModel.TrackSignal.new()

	var drag_force: float = 0.5 * AIR_DENSITY * base_params.drag_area * state.velocity * state.velocity
	drag_force *= signal_data.surface_drag

	if state.in_air:
		return update_force_air(delta)

	var throttle: float = _compute_throttle()
	var soc: float = _soc()
	# DC motor back-EMF: torque ~ (1 - v/v_free)
	var v_free: float = max(0.1, base_params.free_speed)
	var speed_ratio: float = clamp(state.velocity / v_free, 0.0, 1.0)
	var drive_force: float = throttle * base_params.drive_force_max * (1.0 - speed_ratio) * soc

	var normal_force: float = base_params.mass * GRAVITY * cos(signal_data.grade)
	var friction_scale: float = signal_data.friction
	if friction_scale <= 0.0:
		friction_scale = 1.0
	var rolling_force: float = normal_force * base_params.rolling_resistance * friction_scale
	var grade_force: float = base_params.mass * GRAVITY * sin(signal_data.grade)

	var net_force: float = drive_force - drag_force - rolling_force - grade_force
	var acceleration: float = net_force / base_params.mass

	_consume_battery(throttle, delta, drive_force)
	_maybe_regen(net_force, delta)

	return acceleration

func update_force_air(delta: float) -> float:
	var speed: float = state.velocity
	if abs(speed) < 1e-4:
		return 0.0
	var drag_force: float = 0.5 * AIR_DENSITY * base_params.drag_area * speed * speed
	var directional: float = -sign(speed) * drag_force * AIR_DRAG_SCALE
	var damping_force: float = -speed * base_params.mass * 0.3
	var total_force: float = directional + damping_force
	return total_force / base_params.mass

func get_part_stat(stat_name: String, default_value: float = 0.0) -> float:
	if not parts.has(stat_name):
		return default_value
	return float(parts[stat_name])

func _compute_throttle() -> float:
	if state.battery_charge <= 0.0:
		return 0.0
	var desired: float = 1.0
	if parts.has("throttle_limit"):
		desired = clamp(float(parts["throttle_limit"]), 0.0, 1.0)
	return clamp(desired, 0.0, 1.0)

func _soc() -> float:
	# Return normalized battery state of charge (0.0 to 1.0).
	return state.battery_charge / max(1.0, base_params.battery_capacity)

func _consume_battery(throttle: float, delta: float, drive_force: float) -> void:
	# Consume battery charge based on throttle effort and velocity.
	if base_params.battery_capacity <= 0.0:
		return
	var eff: float = 1.0 # placeholder for future motor efficiency
	var effort: float = drive_force / max(0.001, base_params.drive_force_max)
	var drain: float = (battery_drain_rate * effort * effort + drag_factor * state.velocity * state.velocity) * delta / eff
	state.battery_charge = clamp(state.battery_charge - drain, 0.0, base_params.battery_capacity)

func _maybe_regen(net_force: float, delta: float) -> void:
	# Apply regenerative charging when coasting or braking with minimal throttle.
	if net_force < 0.0 and state.velocity > 0.0 and base_params.regen_factor > 0.0 and _compute_throttle() < 0.1:
		var regen: float = base_params.regen_factor * abs(net_force) * state.velocity * delta * 0.001
		state.battery_charge = clamp(state.battery_charge + regen, 0.0, base_params.battery_capacity)
