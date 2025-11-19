extends RefCounted
class_name CarRuntimeManager

## Owns CarRuntime objects and consolidates the bookkeeping that
## SimulationController currently performs inline.  The manager can be used
## piecemeal—start by delegating add/remove/reset before migrating per-car
## integration.

const CONTROL_STATE_STOPPED := 0
const CONTROL_STATE_STARTED := 1

class CarRuntime:
	extends RefCounted

	var car_id: Variant
	var model: CarModel
	var current_segment_index: int = -1
	var current_hint: int = -1
	var last_logged_segment: int = -1
	var running: bool = false
	var finished_time: float = -1.0
	var control_state: int = CONTROL_STATE_STOPPED
	var last_heading: float = 0.0
	var last_position_s: float = 0.0
	var world_position: Vector2 = Vector2.ZERO

	func _init(id: Variant = null, model_ref: CarModel = null) -> void:
		car_id = id
		model = model_ref

	func reset_state() -> void:
		current_segment_index = -1
		current_hint = -1
		last_logged_segment = -1
		finished_time = -1.0
		control_state = CONTROL_STATE_STOPPED
		running = false
		last_heading = 0.0
		last_position_s = 0.0
		world_position = Vector2.ZERO


var _runtimes: Dictionary = {}
var _default_car_id: Variant = "primary"
var _primary_model: CarModel = null

func set_default_id(value: Variant) -> void:
	_default_car_id = value

func get_default_id() -> Variant:
	return _default_car_id

func clear() -> void:
	_runtimes.clear()
	_primary_model = null

func add_car(car_id: Variant, model: CarModel) -> CarRuntime:
	if model == null:
		return null
	if _runtimes.has(car_id):
		remove_car(car_id)
	var runtime := CarRuntime.new(car_id, model)
	runtime.reset_state()
	model.reset_car_state()
	_runtimes[car_id] = runtime
	if _primary_model == null or car_id == _default_car_id:
		_primary_model = model
	return runtime

func remove_car(car_id: Variant) -> void:
	if not _runtimes.has(car_id):
		return
	_runtimes.erase(car_id)
	if _primary_model != null and car_id == _default_car_id:
		_primary_model = _select_fallback_model()

func _select_fallback_model() -> CarModel:
	for runtime: CarRuntime in _runtimes.values():
		if runtime != null and runtime.model != null:
			return runtime.model
	return null

func get_runtime(car_id: Variant) -> CarRuntime:
	return _runtimes.get(car_id, null)

func get_model(car_id: Variant = null) -> CarModel:
	if car_id == null:
		return _primary_model
	var runtime: CarRuntime = get_runtime(car_id)
	return runtime.model if runtime != null else null

func get_all_ids() -> Array:
	return _runtimes.keys()

func runtime_count() -> int:
	return _runtimes.size()

func reset_all() -> void:
	for runtime: CarRuntime in _runtimes.values():
		if runtime == null or runtime.model == null:
			continue
		runtime.model.reset_car_state()
		runtime.reset_state()

func start_car(car_id: Variant, reset_state: bool = true) -> void:
	var runtime: CarRuntime = get_runtime(car_id)
	if runtime == null or runtime.model == null:
		return
	if reset_state or runtime.model.get_car_state().finished:
		runtime.model.reset_car_state()
		runtime.reset_state()
	runtime.running = true
	runtime.control_state = CONTROL_STATE_STARTED

func stop_car(car_id: Variant, mark_finished: bool = false) -> void:
	var runtime: CarRuntime = get_runtime(car_id)
	if runtime == null:
		return
	runtime.running = false
	runtime.control_state = CONTROL_STATE_STOPPED
	if mark_finished and runtime.model != null:
		runtime.model.get_car_state().finished = true

func active_count() -> int:
	var count := 0
	for runtime: CarRuntime in _runtimes.values():
		if runtime != null and runtime.running and runtime.control_state == CONTROL_STATE_STARTED:
			count += 1
	return count

func iter_runtimes() -> Array:
	return _runtimes.values()
