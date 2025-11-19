extends RefCounted
class_name SimulationClock

## Fixed-step accumulator with clamping and time tracking.
##
## This helper mirrors the bookkeeping that SimulationController currently
## performs in step().  It can be adopted gradually without touching the
## integration logic itself: call accumulate(delta) each frame, run the
## returned number of fixed_dt steps, and query total_time() / has_time_limit().

var fixed_dt: float = 1.0 / 240.0
var max_substeps: int = 8
var max_time: float = 0.0

var _accumulator: float = 0.0
var _total_time: float = 0.0
var _running: bool = false

func start() -> void:
	_running = true

func stop() -> void:
	_running = false
	_accumulator = 0.0

func reset(total_time: float = 0.0) -> void:
	_total_time = total_time
	_accumulator = 0.0

func set_total_time(value: float) -> void:
	_total_time = max(value, 0.0)

func accumulate(delta: float) -> int:
	if not _running:
		return 0
	if delta <= 0.0:
		return 0

	_accumulator += delta
	var steps: int = 0

	while _accumulator >= fixed_dt:
		if steps >= max_substeps:
			_accumulator = 0.0
			break
		_accumulator -= fixed_dt
		steps += 1

	return steps

func advance_time(step_count: int = 1) -> void:
	if step_count <= 0:
		return
	_total_time += fixed_dt * float(step_count)

func force_finish() -> void:
	_accumulator = 0.0

func is_running() -> bool:
	return _running

func total_time() -> float:
	return _total_time

func accumulator() -> float:
	return _accumulator

func has_reached_time_limit() -> bool:
	return max_time > 0.0 and _total_time >= max_time
