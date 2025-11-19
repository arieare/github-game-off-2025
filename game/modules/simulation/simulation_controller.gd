extends Node
class_name SimulationController

## Coordinates track, cars, and time-stepping for the race simulation.

const DEFAULT_DT: float = 1.0 / 240.0
const MAX_SUBSTEPS: int = 8
const GRAVITY: float = 9.80665
const STABILITY_OK := 0
const STABILITY_RAIL_HIT := 1
const STABILITY_DERAIL := 2
const STABILITY_AIRBORNE := 3
const MIN_BATTERY_CHARGE := 1e-3
const REFERENCE_MASS := 0.14
const DEFAULT_BUMP_HEIGHT := 0.05
const LATERAL_FATAL_MULTIPLIER := 3.0
const AIR_STABILITY_COOLDOWN := 0.15
const AIR_MU_LONG := 1.25
const AIR_MU_LAT := 0.2
const LANDING_RETENTION_MIN := 0.55
const LANDING_RETENTION_MAX := 0.95
const LANDING_RETENTION_K := 0.06
const CONTROL_STATE_STOPPED := 0
const CONTROL_STATE_STARTED := 1
const CarRuntime = CarRuntimeManager.CarRuntime

var fixed_dt: float = DEFAULT_DT
var max_time: float = 0.0

var _is_running: bool = false
var _clock: SimulationClock = SimulationClock.new()
var _runtime_manager: CarRuntimeManager = CarRuntimeManager.new()
var _track_context: SimulationTrackContext = SimulationTrackContext.new()
var _event_bus: SimulationEventBus = SimulationEventBus.new()

func _ready() -> void:
	add_child(_event_bus)

func get_event_bus() -> SimulationEventBus:
	return _event_bus

func set_track_model(model: TrackModel) -> void:
	_track_context.set_track_model(model)
	_reset_all_segments()
	if _track_context.has_track():
		for runtime: CarRuntime in _runtime_manager.iter_runtimes():
			if runtime == null:
				continue
			var s_value: float = 0.0
			if runtime.model != null:
				s_value = runtime.model.get_car_state().position_s
				runtime.model.divider_height = _track_context.get_divider_height()
			_refresh_runtime_pose(runtime, s_value, runtime.current_hint)

func clear_cars() -> void:
	_runtime_manager.clear()
	_is_running = false
	_clock.stop()
	_clock.reset(0.0)

func add_car(car_id: Variant, model: CarModel) -> void:
	if model == null:
		push_error("SimulationController: add_car called with null model.")
		return
	var runtime := _runtime_manager.add_car(car_id, model)
	if runtime == null:
		return
	if _track_context.has_track():
		runtime.current_hint = -1
		model.divider_height = _track_context.get_divider_height()
		_refresh_runtime_pose(runtime, model.get_car_state().position_s, runtime.current_hint)
	runtime.control_state = CONTROL_STATE_STOPPED

func remove_car(car_id: Variant) -> void:
	if _runtime_manager.get_runtime(car_id) == null:
		return
	_runtime_manager.remove_car(car_id)
	_check_global_running()

func reset_all_cars() -> void:
	_runtime_manager.reset_all()
	for runtime: CarRuntime in _runtime_manager.iter_runtimes():
		if runtime == null or runtime.model == null:
			continue
		_refresh_runtime_pose(runtime, runtime.model.get_car_state().position_s, runtime.current_hint)
	_clock.stop()
	_clock.reset(0.0)
	_is_running = false

func start_car(car_id: Variant, reset_state: bool = true) -> void:
	var runtime := _runtime_manager.get_runtime(car_id)
	if runtime == null:
		push_warning("SimulationController: start_car unknown id %s" % str(car_id))
		return
	if runtime.model == null:
		return
	_runtime_manager.start_car(car_id, reset_state)
	_refresh_runtime_pose(runtime, runtime.model.get_car_state().position_s, runtime.current_hint)
	_is_running = true
	if not _clock.is_running():
		_clock.start()

func stop_car(car_id: Variant, mark_finished: bool = false) -> void:
	_runtime_manager.stop_car(car_id, mark_finished)
	_check_global_running()

func is_car_running(car_id: Variant) -> bool:
	var runtime: CarRuntime = _runtime_manager.get_runtime(car_id)
	if runtime == null:
		return false
	return runtime.running and runtime.control_state == CONTROL_STATE_STARTED

func start() -> void:
	if not _track_context.has_track():
		push_error("SimulationController: track model not assigned.")
		return
	if _runtime_manager.runtime_count() == 0:
		push_error("SimulationController: no cars registered.")
		return
	_runtime_manager.reset_all()
	for runtime: CarRuntime in _runtime_manager.iter_runtimes():
		if runtime == null or runtime.model == null:
			continue
		runtime.control_state = CONTROL_STATE_STARTED
		runtime.running = true
		_refresh_runtime_pose(runtime, runtime.model.get_car_state().position_s, runtime.current_hint)
	_clock.reset(0.0)
	_sync_clock_settings()
	_is_running = _runtime_manager.active_count() > 0
	if _is_running:
		_clock.start()
	else:
		_clock.stop()

func stop() -> void:
	_is_running = false
	_clock.stop()
	for car_id in _runtime_manager.get_all_ids():
		_runtime_manager.stop_car(car_id)

func step(delta: float) -> void:
	if not _is_running:
		return
	_sync_clock_settings()

	var steps: int = _clock.accumulate(delta)
	for i in range(steps):
		_integrate_step(_clock.fixed_dt)
		_clock.advance_time()

	if max_time > 0.0 and _clock.has_reached_time_limit():
		_force_finish_all()

func get_snapshot(car_id: Variant = null) -> Dictionary:
	if _runtime_manager.runtime_count() == 0:
		return {}
	var target_id: Variant = car_id
	if target_id == null:
		var ids := _runtime_manager.get_all_ids()
		if ids.is_empty():
			return {}
		target_id = ids[0]
	var runtime: CarRuntime = _runtime_manager.get_runtime(target_id)
	if runtime == null:
		return {}
	if runtime.model == null:
		return {}
	var state: CarModel.CarState = runtime.model.get_car_state()
	return {
		"car_id": target_id,
		"time": _clock.total_time(),
		"s": state.position_s,
		"v": state.velocity,
		"battery": state.battery_charge,
		"lane": state.lane,
		"laps": state.laps_completed,
		"finished": state.finished,
		"rail_hits": state.rail_hits,
		"in_air": state.in_air,
		"altitude": state.altitude,
		"vertical_velocity": state.vertical_velocity,
		"air_time": state.air_time,
		"airborne_heading": state.airborne_heading,
		"airborne_origin": state.airborne_origin,
		"above_divider": state.above_divider,
		"stability_cooldown": state.stability_cooldown,
		"segment_index": runtime.current_segment_index,
		"world_position": runtime.world_position,
	}

func get_snapshots() -> Dictionary:
	var result: Dictionary = {}
	for car_id in _runtime_manager.get_all_ids():
		result[car_id] = get_snapshot(car_id)
	return result

func is_running() -> bool:
	return _is_running

func _integrate_step(dt: float) -> void:
	for car_id in _runtime_manager.get_all_ids():
		var runtime: CarRuntime = _runtime_manager.get_runtime(car_id)
		if runtime == null or runtime.model == null or runtime.control_state != CONTROL_STATE_STARTED or not runtime.running:
			continue
		_integrate_car(car_id, runtime, dt)
	_check_global_running()

func _integrate_car(car_id: Variant, runtime: CarRuntime, dt: float) -> void:
	if not _track_context.has_track():
		return
	var model: CarModel = runtime.model
	var car_state: CarModel.CarState = model.get_car_state()
	if car_state.finished:
		runtime.running = false
		return

	var remaining: float = dt
	var safety: int = 0
	while remaining > 1e-8:
		safety += 1
		if safety > 32:
			break

		if car_state.finished:
			runtime.running = false
			break

		var loc: TrackModel.TrackLocation = _track_context.locate(car_state.position_s, runtime.current_hint)
		if loc == null or loc.segment == null:
			runtime.running = false
			push_error("SimulationController: unable to locate segment for car %s at s=%.3f" % [str(car_id), car_state.position_s])
			break

		_refresh_runtime_pose(runtime, car_state.position_s, runtime.current_hint)

		if loc.index != runtime.current_segment_index:
			runtime.current_segment_index = loc.index
			runtime.current_hint = runtime.current_segment_index
			_event_bus.emit_segment_entered(car_id, runtime.current_segment_index, str(loc.segment.type), loc.segment.s_start)
			runtime.last_logged_segment = runtime.current_segment_index

		if is_zero_approx(loc.segment.length):
			_handle_lane_events(loc.segment, car_state)
			_handle_finish(car_id, runtime, loc.segment, car_state)
			if not runtime.running:
				break
			var next_index: int = min(runtime.current_segment_index + 1, _track_context.get_segment_count() - 1)
			if next_index == runtime.current_segment_index:
				break
			runtime.current_hint = next_index
			continue

		if car_state.in_air:
			var air_consumed: float = _step_air(car_id, runtime, car_state, remaining, loc)
			remaining -= air_consumed
			if runtime.running and model.is_battery_depleted(MIN_BATTERY_CHARGE):
				_trigger_finish(car_id, runtime)
			if not runtime.running:
				break
			continue

		var sig: TrackModel.TrackSignal = _track_context.sample_signal(car_state.position_s, runtime.current_hint)
		var step_time: float = remaining
		var to_end: float = loc.segment.s_end - car_state.position_s
		if to_end < 0.0:
			to_end = 0.0
		if car_state.velocity > 0.0 and to_end > TrackModel.EPSILON:
			var a_est: float = model.update_force(sig, 0.0)
			var t_edge: float = _time_to_cover(car_state.velocity, a_est, to_end)
			if t_edge > 0.0 and t_edge < step_time:
				step_time = t_edge
		if step_time <= 0.0:
			break

		var a: float = model.update_force(sig, step_time)
		car_state.velocity = max(0.0, car_state.velocity + a * step_time)
		if car_state.stability_cooldown > 0.0:
			car_state.stability_cooldown = max(0.0, car_state.stability_cooldown - step_time)

		var stability_result: int = STABILITY_OK
		if not car_state.in_air and car_state.stability_cooldown <= 0.0:
			stability_result = _handle_lateral_stability(car_id, runtime, loc.segment, sig)
			if stability_result == STABILITY_DERAIL or not runtime.running:
				remaining = 0.0
				break
			if stability_result == STABILITY_AIRBORNE:
				continue

		var ds_step: float = car_state.velocity * step_time
		car_state.position_s += ds_step
		_refresh_runtime_pose(runtime, car_state.position_s, runtime.current_hint)
		remaining -= step_time

		var crossed: bool = false
		if car_state.position_s >= loc.segment.s_end - TrackModel.EPSILON:
			car_state.position_s = loc.segment.s_end
			runtime.current_hint = min(runtime.current_segment_index + 1, _track_context.get_segment_count() - 1)
			crossed = true
			if _track_context.is_endless():
				var track_len: float = _track_context.get_total_length()
				if track_len > 0.0 and loc.index >= _track_context.get_segment_count() - 1:
					car_state.position_s = fposmod(car_state.position_s, track_len)
					if is_equal_approx(car_state.position_s, track_len):
						car_state.position_s = 0.0
				runtime.current_hint = 0
				runtime.current_segment_index = -1
				crossed = true

		if not car_state.in_air:
			_handle_lane_events(loc.segment, car_state)
		_handle_finish(car_id, runtime, loc.segment, car_state)
		if loc.segment.type == "BUMP" and not car_state.in_air and runtime.running:
			_handle_bump_progress(model, runtime, loc.segment, car_state)
			if runtime.running and model.is_battery_depleted(MIN_BATTERY_CHARGE):
				_trigger_finish(car_id, runtime)
		if not runtime.running:
			break
		if not crossed:
			runtime.current_hint = runtime.current_segment_index
		_refresh_runtime_pose(runtime, car_state.position_s, runtime.current_hint)

		_event_bus.emit_state_updated(car_id, get_snapshot(car_id))

func _handle_lane_events(segment: TrackModel.TrackSegment, car_state: CarModel.CarState) -> void:
	if segment.type == "LANE_SWITCH":
		var from_lane: int = segment.lane_from
		var to_lane: int = segment.lane_to
		if from_lane >= 0 and car_state.lane == from_lane and to_lane >= 0:
			car_state.lane = to_lane

func _handle_finish(car_id: Variant, runtime: CarRuntime, segment: TrackModel.TrackSegment, car_state: CarModel.CarState) -> void:
	if _track_context.is_endless():
		return
	if segment.type != "FINISH":
		return
	car_state.laps_completed += 1
	_event_bus.emit_lap_completed(car_id, car_state.laps_completed, _clock.total_time())
	var laps_required: int = 1
	var retention: float = 1.0
	var total_len: float = 0.0
	if _track_context.has_track():
		var meta: Dictionary = _track_context.get_track_meta()
		laps_required = int(meta.get("laps_required", laps_required))
		retention = float(meta.get("finish_velocity_retention", retention))
		total_len = _track_context.get_total_length()
	retention = clamp(retention, 0.0, 1.0)
	car_state.velocity *= retention
	if total_len > 0.0:
		car_state.position_s = fposmod(car_state.position_s, total_len)
		if car_state.position_s < 0.0:
			car_state.position_s += total_len
	runtime.current_segment_index = -1
	if total_len > 0.0 and _track_context.has_track():
		runtime.current_hint = 0
	else:
		runtime.current_hint = -1
	if car_state.laps_completed >= laps_required:
		_trigger_finish(car_id, runtime)

func _trigger_finish(car_id: Variant, runtime: CarRuntime) -> void:
	if runtime == null or runtime.model == null:
		return
	var car_state: CarModel.CarState = runtime.model.get_car_state()
	if car_state.finished:
		runtime.running = false
		return
	car_state.finished = true
	runtime.running = false
	runtime.control_state = CONTROL_STATE_STOPPED
	runtime.finished_time = _clock.total_time()
	_event_bus.emit_car_finished(car_id, _clock.total_time())
	_check_global_running()

func _handle_lateral_stability(car_id: Variant, runtime: CarRuntime, segment: TrackModel.TrackSegment, track_signal: TrackModel.TrackSignal) -> int:
	var model: CarModel = runtime.model
	var car_state: CarModel.CarState = model.get_car_state()
	if car_state.in_air:
		return STABILITY_OK
	var kappa: float = abs(track_signal.curvature)
	if kappa <= 0.0:
		if car_state.rail_hits > 0:
			model.reset_rail_hits()
		return STABILITY_OK
	var velocity: float = car_state.velocity
	if velocity <= 0.0:
		if car_state.rail_hits > 0:
			model.reset_rail_hits()
		return STABILITY_OK

	var bank: float = track_signal.bank
	var slope: float = track_signal.grade
	var demand_per_mass: float = velocity * velocity * kappa - GRAVITY * tan(bank)
	var demand_force: float = abs(demand_per_mass) * model.base_params.mass
	var normal: float = model.base_params.mass * (GRAVITY * cos(slope) + velocity * velocity * kappa * sin(bank))
	if normal < 0.0:
		normal = 0.0

	var mu_lat: float = model.get_lateral_mu(track_signal)
	var capacity: float = mu_lat * normal + model.base_params.downforce_lateral * velocity * velocity
	var margin: float = max(0.0, model.base_params.lateral_margin)

	if capacity <= 0.0:
		capacity = 0.0

	var threshold: float = capacity * (1.0 + margin)
	if demand_force <= threshold:
		if car_state.rail_hits > 0 and demand_force < capacity:
			model.reset_rail_hits()
		return STABILITY_OK

	var overshoot: float = max(0.0, demand_force - capacity)
	var soft_threshold: float = model.base_params.rail_hit_soft_threshold
	if soft_threshold > 0.0 and overshoot > 0.0 and overshoot <= soft_threshold:
		model.apply_speed_penalty(model.base_params.rail_hit_penalty)
		model.register_rail_hit()
		_event_bus.emit_rail_hit(car_id, overshoot, car_state.rail_hits)
		if model.base_params.max_rail_hits > 0 and car_state.rail_hits >= model.base_params.max_rail_hits:
			model.mark_derailed()
			runtime.running = false
			runtime.control_state = CONTROL_STATE_STOPPED
			_event_bus.emit_car_derailed(car_id, _clock.total_time(), overshoot)
			_trigger_finish(car_id, runtime)
			return STABILITY_DERAIL
		car_state.stability_cooldown = max(car_state.stability_cooldown, AIR_STABILITY_COOLDOWN * 0.5)
		return STABILITY_RAIL_HIT

	var fatal_threshold: float = soft_threshold * LATERAL_FATAL_MULTIPLIER if soft_threshold > 0.0 else threshold * LATERAL_FATAL_MULTIPLIER
	if fatal_threshold > 0.0 and overshoot >= fatal_threshold:
		model.mark_derailed()
		runtime.running = false
		runtime.control_state = CONTROL_STATE_STOPPED
		_event_bus.emit_car_derailed(car_id, _clock.total_time(), overshoot)
		_trigger_finish(car_id, runtime)
		return STABILITY_DERAIL

	model.register_rail_hit()
	_event_bus.emit_rail_hit(car_id, overshoot, car_state.rail_hits)
	var heading_launch: float = runtime.last_heading
	var origin_launch: Vector2 = _surface_world_position(runtime, car_state)
	_launch_due_to_lateral(model, overshoot, car_state, heading_launch, origin_launch)
	if car_state.in_air:
		runtime.control_state = CONTROL_STATE_STARTED
	return STABILITY_AIRBORNE

func _step_air(car_id: Variant, runtime: CarRuntime, car_state: CarModel.CarState, remaining: float, loc: TrackModel.TrackLocation) -> float:
	var model: CarModel = runtime.model
	if model == null:
		return 0.0

	var divider: float = max(model.divider_height, 0.0)
	var follow_track: bool = (car_state.altitude <= divider) and not car_state.above_divider

	var step_time: float = max(0.0, remaining)
	if step_time <= 0.0:
		return 0.0

	var accel_air_est: float = model.update_force_air(0.0)
	if follow_track:
		var to_end: float = loc.segment.s_end - car_state.position_s
		if to_end < 0.0:
			to_end = 0.0
		if to_end > TrackModel.EPSILON:
			var t_boundary: float = _air_time_to_cover(car_state.velocity, accel_air_est, to_end)
			if t_boundary > 0.0:
				step_time = min(step_time, t_boundary)
		var min_increment: float = min(remaining, TrackModel.EPSILON)
		if min_increment > 0.0:
			step_time = max(step_time, min_increment)

	var accel_air: float = model.update_force_air(step_time)
	car_state.velocity = max(0.0, car_state.velocity + accel_air * step_time)

	var ds: float = car_state.velocity * step_time
	if follow_track:
		car_state.position_s += ds
		if car_state.position_s >= loc.segment.s_end - TrackModel.EPSILON:
			car_state.position_s = loc.segment.s_end
			runtime.current_hint = min(runtime.current_segment_index + 1, _track_context.get_segment_count() - 1)
			if _track_context.is_endless():
				var track_len: float = _track_context.get_total_length()
				if track_len > 0.0 and loc.index >= _track_context.get_segment_count() - 1:
					car_state.position_s = fposmod(car_state.position_s, track_len)
					if is_equal_approx(car_state.position_s, track_len):
						car_state.position_s = 0.0
					runtime.current_hint = 0
					runtime.current_segment_index = -1
			_refresh_runtime_pose(runtime, car_state.position_s, runtime.current_hint)
		else:
			var heading: float = car_state.airborne_heading
			car_state.airborne_origin += Vector2(ds * cos(heading), ds * sin(heading))
			car_state.position_s += ds
			if _track_context.is_endless():
				var track_len_free: float = _track_context.get_total_length()
				if track_len_free > 0.0:
					car_state.position_s = fposmod(car_state.position_s, track_len_free)
					if is_equal_approx(car_state.position_s, track_len_free):
						car_state.position_s = 0.0
					runtime.current_hint = 0
					runtime.current_segment_index = -1
			runtime.last_position_s = car_state.position_s
			runtime.last_heading = heading
			runtime.world_position = car_state.airborne_origin

	var was_above_divider: bool = car_state.above_divider
	_update_airborne(model, car_state, step_time)
	if car_state.stability_cooldown > 0.0:
		car_state.stability_cooldown = max(0.0, car_state.stability_cooldown - step_time)

	if was_above_divider and car_state.in_air and car_state.altitude <= divider + TrackModel.EPSILON:
		_reconcile_reentry(runtime)

	if not car_state.in_air:
		_handle_lane_events(loc.segment, car_state)
	_handle_finish(car_id, runtime, loc.segment, car_state)
	return clamp(step_time, 0.0, remaining)

func _air_time_to_cover(v0: float, a: float, distance: float) -> float:
	if abs(a) < 1e-8:
		return distance / max(v0, 1e-6)
	var disc: float = v0 * v0 + 2.0 * a * distance
	if disc <= 0.0:
		return 0.0
	return max(0.0, (-v0 + sqrt(disc)) / a)

func _handle_bump_progress(model: CarModel, runtime: CarRuntime, segment: TrackModel.TrackSegment, car_state: CarModel.CarState) -> void:
	if segment.length <= 0.0:
		return
	var meta: Dictionary = segment.metadata if segment.metadata != null else {}
	var bump_height: float = float(meta.get("bump_height", DEFAULT_BUMP_HEIGHT))
	if bump_height <= 0.0:
		return
	var progress: float = clamp((car_state.position_s - segment.s_start) / max(segment.length, 1e-6), 0.0, 1.0)
	var profile: float = sin(progress * PI)
	car_state.altitude = bump_height * profile
	if progress >= 0.95 and not car_state.in_air:
		var mass: float = max(model.base_params.mass, 0.05)
		var base_launch: float = sqrt(max(0.0, 2.0 * GRAVITY * bump_height))
		var speed_factor: float = clamp(car_state.velocity / max(1.0, base_launch), 0.5, 2.0)
		var launch_velocity: float = base_launch * clamp(REFERENCE_MASS / mass, 0.5, 1.5) * speed_factor
		var heading: float = runtime.last_heading
		var origin: Vector2 = _surface_world_position(runtime, car_state)
		var above: bool = bump_height > model.divider_height
		model.set_airborne(bump_height, launch_velocity, heading, origin, above)
		car_state.stability_cooldown = max(car_state.stability_cooldown, AIR_STABILITY_COOLDOWN)
		car_state.velocity = max(0.0, car_state.velocity * clamp(1.0 - launch_velocity * 0.05, 0.5, 1.0))
		model.reset_rail_hits()

func _update_airborne(model: CarModel, car_state: CarModel.CarState, dt: float) -> void:
	if not car_state.in_air:
		return
	model.add_air_time(dt)
	car_state.vertical_velocity -= GRAVITY * dt
	car_state.altitude += car_state.vertical_velocity * dt
	var divider: float = max(model.divider_height, 0.0)
	if car_state.altitude > divider:
		car_state.above_divider = true
	elif car_state.above_divider and car_state.altitude <= divider:
		car_state.above_divider = false
	if car_state.altitude <= 0.0:
		var impact_speed: float = abs(car_state.vertical_velocity)
		var air_duration: float = car_state.air_time
		var landing_retention: float = clamp(1.0 - LANDING_RETENTION_K * impact_speed, LANDING_RETENTION_MIN, LANDING_RETENTION_MAX)
		car_state.velocity = max(0.0, car_state.velocity * landing_retention)
		car_state.in_air = false
		car_state.altitude = 0.0
		car_state.vertical_velocity = 0.0
		car_state.stability_cooldown = max(car_state.stability_cooldown, AIR_STABILITY_COOLDOWN)
		model.land(impact_speed, air_duration, landing_retention)
		return
	if car_state.stability_cooldown > 0.0:
		car_state.stability_cooldown = max(0.0, car_state.stability_cooldown - dt)

func _refresh_runtime_pose(runtime: CarRuntime, s: float, hint: int) -> void:
	if runtime == null or not _track_context.has_track():
		return
	var pose: Dictionary = _track_context.pose_at(s, hint)
	if pose == null:
		return
	var heading_value: float = float(pose.get("heading", runtime.last_heading))
	runtime.last_heading = wrapf(heading_value, -PI, PI)
	var position_value: Vector2 = pose.get("position", runtime.world_position)
	runtime.world_position = position_value
	runtime.last_position_s = s

func _lane_offset_for_lane(lane: int) -> float:
	if not _track_context.has_track():
		return 0.0
	var meta: Dictionary = _track_context.get_track_meta()
	var lane_count: int = max(1, int(meta.get("lanes", 1)))
	var lane_width: float = float(meta.get("lane_width", 0.08))
	if lane_width <= 0.0:
		lane_width = 0.08
	var lane_index: int = clamp(lane - 1, 0, lane_count - 1)
	var half_span: float = (float(lane_count) - 1.0) * 0.5
	return (float(lane_index) - half_span) * lane_width

func _surface_world_position(runtime: CarRuntime, car_state: CarModel.CarState) -> Vector2:
	if runtime == null:
		return Vector2.ZERO
	var offset: float = _lane_offset_for_lane(car_state.lane)
	var normal: Vector2 = Vector2.RIGHT.rotated(runtime.last_heading + PI * 0.5)
	return runtime.world_position + normal * offset

func _reconcile_reentry(runtime: CarRuntime) -> void:
	if runtime == null:
		return
	var model: CarModel = runtime.model
	if model == null:
		return
	var car_state: CarModel.CarState = model.get_car_state()
	if car_state == null or not car_state.in_air:
		return
	var impact_speed: float = abs(car_state.vertical_velocity)
	var air_duration: float = car_state.air_time
	var retention: float = clamp(1.0 - LANDING_RETENTION_K * impact_speed, LANDING_RETENTION_MIN, LANDING_RETENTION_MAX)
	car_state.velocity = max(0.0, car_state.velocity * retention)
	model.land(impact_speed, air_duration, retention)
	car_state.stability_cooldown = max(car_state.stability_cooldown, AIR_STABILITY_COOLDOWN)
	if _track_context.has_track():
		car_state.position_s = _track_context.clamp_distance(car_state.position_s)
		var meta: Dictionary = _track_context.get_track_meta()
		var lane_count: int = max(1, int(meta.get("lanes", car_state.lane)))
		car_state.lane = clamp(car_state.lane, 1, lane_count)
		var reconcile_loc: TrackModel.TrackLocation = _track_context.locate(car_state.position_s, runtime.current_hint)
		if reconcile_loc != null:
			runtime.current_segment_index = reconcile_loc.index
			runtime.current_hint = reconcile_loc.index
	_refresh_runtime_pose(runtime, car_state.position_s, runtime.current_hint)

func _launch_due_to_lateral(model: CarModel, overshoot: float, car_state: CarModel.CarState, heading: float, origin: Vector2) -> void:
	if model == null:
		return
	var mass: float = max(model.base_params.mass, 0.05)
	var ratio: float = clamp(overshoot / (mass * GRAVITY + 1e-6), 0.1, 5.0)
	var launch_velocity: float = car_state.velocity * clamp(ratio * 0.2, 0.1, 0.6)
	var launch_height: float = max(0.02, (launch_velocity * launch_velocity) / (2.0 * GRAVITY))
	var above: bool = launch_height > model.divider_height
	model.set_airborne(launch_height, launch_velocity, heading, origin, above)
	car_state.velocity = max(0.0, car_state.velocity * clamp(1.0 - ratio * 0.1, 0.4, 0.95))
	car_state.stability_cooldown = max(car_state.stability_cooldown, AIR_STABILITY_COOLDOWN * (1.0 + AIR_MU_LAT))

func _time_to_cover(v0: float, a: float, d: float) -> float:
	if abs(a) < 1e-8:
		return d / max(v0, 1e-6)
	var disc: float = v0 * v0 + 2.0 * a * d
	return max(0.0, (-v0 + sqrt(max(0.0, disc))) / a)

func _reset_all_segments() -> void:
	for runtime: CarRuntime in _runtime_manager.iter_runtimes():
		if runtime != null:
			runtime.current_segment_index = -1
			runtime.current_hint = -1
			runtime.last_logged_segment = -1

func _check_global_running() -> void:
	if _runtime_manager.active_count() == 0:
		_is_running = false
		_clock.stop()

func _force_finish_all() -> void:
	if _runtime_manager.runtime_count() == 0:
		_is_running = false
		_clock.stop()
		return
	for car_id in _runtime_manager.get_all_ids():
		var runtime: CarRuntime = _runtime_manager.get_runtime(car_id)
		if runtime != null and runtime.running:
			_trigger_finish(car_id, runtime)
	_is_running = false
	_clock.stop()

func _sync_clock_settings() -> void:
	_clock.fixed_dt = fixed_dt
	_clock.max_substeps = MAX_SUBSTEPS
	_clock.max_time = max_time
