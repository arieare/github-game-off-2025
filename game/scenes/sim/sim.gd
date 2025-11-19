extends Node

@export var track_renderer: TrackRenderer
@export var controller: SimulationController
@export var car_component_paths: Array[NodePath] = []
@export var sim_ui_path: NodePath
@export_file("*.tres") var track_blueprint_path: String = "res://modules/track/assets/debug_loop.tres"

var _track: TrackModel = null
var _compiler: TrackCompiler = TrackCompiler.new()
var _simulation_active: bool = false
var _car_components: Array[CarComponent] = []
var _car_models: Dictionary = {}
var _car_ids: Array = []
var _component_to_car_id: Dictionary = {}
var _car_infos: Array = []
var _sim_ui: SimUI = null
var _telemetry_prev: Dictionary = {}
var _telemetry_data: Dictionary = {}

func _ready() -> void:
	if controller == null:
		push_warning("Main: SimulationController export is not assigned.")
		return
	if sim_ui_path != NodePath(""):
		_sim_ui = get_node_or_null(sim_ui_path) as SimUI
	var blueprint: TrackBlueprint = null
	if track_blueprint_path != "":
		blueprint = _compiler.load_blueprint(track_blueprint_path)
	if blueprint == null:
		blueprint = _compiler.load_blueprint("res://modules/track/assets/debug_loop.tres")
		if blueprint != null:
			track_blueprint_path = "res://modules/track/assets/debug_loop.tres"
	if blueprint == null:
		push_warning("Main: Failed to load track blueprint.")
		return
	_track = _compiler.compile_blueprint(blueprint)
	#_track.set_endless(true)
	if track_renderer != null:
		track_renderer.set_track_model(_track)

	if controller != null:
		controller.set_track_model(_track)
		controller.clear_cars()

	_car_components = _collect_car_components()
	if _car_components.is_empty():
		push_warning("Main: No car components configured for simulation.")
		return

	var assembled_count: int = _assemble_scene_cars()
	if assembled_count <= 0:
		push_warning("Main: Failed to assemble any cars from provided components.")
		return

	_apply_track_start_lanes()
	if track_renderer != null and controller != null:
		track_renderer.update_car_snapshots(controller.get_snapshots())

	for comp in _car_components:
		if comp == null:
			continue
		var callable := Callable(self, "_on_car_component_assembled").bind(comp)
		if comp.assembled.is_connected(callable):
			comp.assembled.disconnect(callable)
		comp.assembled.connect(callable)

	if controller != null:
		controller.reset_all_cars()
	_apply_track_start_lanes()

	var auto_started: bool = false
	for info in _car_infos:
		if bool(info.get("start_enabled", false)):
			var car_id: Variant = info.get("id", "")
			start_car(car_id, true)
			auto_started = true

	_simulation_active = controller != null and controller.is_running()
	if track_renderer != null and controller != null:
		track_renderer.update_car_snapshots(controller.get_snapshots())

	if _sim_ui != null:
		_sim_ui.setup_controls(self, _car_infos)

	if not auto_started:
		push_warning("Main: All cars are idle; use the UI toggles to start them.")

	_update_telemetry_ui()

	var events := controller.get_event_bus()
	if events != null:
		if not events.segment_entered.is_connected(_on_segment_entered):
			events.segment_entered.connect(_on_segment_entered)
		if not events.lap_completed.is_connected(_on_lap_completed):
			events.lap_completed.connect(_on_lap_completed)
		if not events.car_finished.is_connected(_on_car_finished):
			events.car_finished.connect(_on_car_finished)
		if not events.rail_hit.is_connected(_on_rail_hit):
			events.rail_hit.connect(_on_rail_hit)
		if not events.car_derailed.is_connected(_on_car_derailed):
			events.car_derailed.connect(_on_car_derailed)
		if not events.state_updated.is_connected(_on_state_updated):
			events.state_updated.connect(_on_state_updated)

func _process(delta: float) -> void:
	if controller == null or not controller.is_running():
		_simulation_active = false
		return
	controller.step(delta)
	_simulation_active = controller.is_running()
	if track_renderer != null:
		track_renderer.queue_redraw()

func _exit_tree() -> void:
	if controller != null and _simulation_active:
		controller.stop()
		_simulation_active = false

func _apply_track_start_lanes() -> void:
	if _track == null or _car_ids.is_empty():
		return
	var meta: Dictionary = _track.get_track_meta()
	var lane_count: int = int(meta.get("lanes", 1))
	if lane_count <= 0:
		lane_count = 1
	for i in range(_car_ids.size()):
		var car_id : Variant = _car_ids[i]
		var model: CarModel = _car_models.get(car_id, null)
		if model == null:
			continue
		var state: CarModel.CarState = model.get_car_state()
		state.lane = clamp(i + 1, 1, lane_count)

# ---- signal handlers ----
func _on_segment_entered(car_id: Variant, idx: int, seg_type: String, s_start: float) -> void:

func _on_lap_completed(car_id: Variant, lap: int, total_time: float) -> void:

func _on_car_finished(car_id: Variant, total_time: float) -> void:
	print("Car %s finished at %.3fs" % [str(car_id), total_time])
	if _sim_ui != null:
		_sim_ui.refresh_button_states()
	if _telemetry_data.has(car_id):
		var entry: Dictionary = _telemetry_data[car_id]
		entry["status"] = "Finished"
		entry["time"] = total_time
		entry["acceleration"] = 0.0
		entry["airborne_speed"] = 0.0
		entry["in_air"] = false
		entry["speed"] = 0.0
		_telemetry_data[car_id] = entry
	_update_telemetry_ui()

func _on_state_updated(car_id: Variant, state: Dictionary) -> void:
	if track_renderer != null:
		track_renderer.update_car_snapshot(state)
	var time: float = float(state.get("time", 0.0))
	var speed: float = float(state.get("v", 0.0))
	var prev: Dictionary = _telemetry_prev.get(car_id, {})
	var prev_time: float = float(prev.get("time", 0.0))
	var prev_speed: float = float(prev.get("speed", 0.0))
	var dt: float = time - prev_time
	var acceleration: float = 0.0
	if dt > 1e-5:
		acceleration = (speed - prev_speed) / dt
	var distance: float = float(state.get("s", 0.0))
	var battery: float = float(state.get("battery", 0.0))
	var laps: int = int(state.get("laps", 0))
	var rail_hits: int = int(state.get("rail_hits", 0))
	var altitude: float = float(state.get("altitude", 0.0))
	var in_air: bool = bool(state.get("in_air", false))
	var airborne_speed: float = 0.0
	if in_air:
		airborne_speed = speed
	var display_name: String = str(car_id)
	for info in _car_infos:
		if info.get("id", null) == car_id:
			display_name = String(info.get("name", car_id))
			break
	if not _telemetry_data.has(car_id):
		_telemetry_data[car_id] = _make_default_telemetry(car_id, display_name)
	var status: String = "Running"
	if _telemetry_data.has(car_id):
		status = String(_telemetry_data[car_id].get("status", "Running"))
	if controller != null and controller.is_car_running(car_id):
		status = "Running"
	elif status != "Finished" and status != "Derailed" and status != "Stopped":
		if in_air:
			status = "Airborne"
	_telemetry_data[car_id] = {
		"id": car_id,
		"name": display_name,
		"speed": speed,
		"acceleration": acceleration,
		"distance": distance,
		"time": time,
		"battery": battery,
		"laps": laps,
		"rail_hits": rail_hits,
		"altitude": altitude,
		"airborne_speed": airborne_speed,
		"in_air": in_air,
		"status": status
	}
	_telemetry_prev[car_id] = {
		"time": time,
		"speed": speed
	}
	_update_telemetry_ui()

func _on_rail_hit(car_id: Variant, overshoot_force: float, hit_count: int) -> void:
	print("Car %s rail hit overshoot=%.2fN hits=%d" % [str(car_id), overshoot_force, hit_count])

func _on_car_derailed(car_id: Variant, total_time: float, overshoot_force: float) -> void:
	print("Car %s derailed at %.3fs (overshoot %.2fN)" % [str(car_id), total_time, overshoot_force])
	if track_renderer != null:
		track_renderer.remove_car(car_id)
	if _sim_ui != null:
		_sim_ui.refresh_button_states()
	if _telemetry_data.has(car_id):
		var entry: Dictionary = _telemetry_data[car_id]
		entry["status"] = "Derailed"
		entry["time"] = total_time
		entry["acceleration"] = 0.0
		entry["airborne_speed"] = 0.0
		entry["in_air"] = false
		entry["speed"] = 0.0
		_telemetry_data[car_id] = entry
	_update_telemetry_ui()

func start_car(car_id: Variant, reset_state: bool = true) -> void:
	if controller == null:
		return
	controller.start_car(car_id, reset_state)
	var lane_count: int = 1
	if _track != null:
		lane_count = int(_track.get_track_meta().get("lanes", lane_count))
	if lane_count <= 0:
		lane_count = 1
	var lane_index := _car_ids.find(car_id)
	if lane_index != -1 and _car_models.has(car_id):
		var model: CarModel = _car_models[car_id]
		if model != null:
			var state := model.get_car_state()
			state.lane = clamp(lane_index + 1, 1, lane_count)
	_telemetry_prev[car_id] = {}
	_simulation_active = controller.is_running()
	if track_renderer != null:
		track_renderer.update_car_snapshot(controller.get_snapshot(car_id))
	if _sim_ui != null:
		_sim_ui.refresh_button_states()
	for info in _car_infos:
		if info.get("id", null) == car_id:
			info["start_enabled"] = true
			break
	if _telemetry_data.has(car_id):
		var entry: Dictionary = _telemetry_data[car_id]
		entry["status"] = "Running"
		_telemetry_data[car_id] = entry
	_update_telemetry_ui()

func stop_car(car_id: Variant) -> void:
	if controller == null:
		return
	controller.stop_car(car_id)
	_simulation_active = controller.is_running()
	if track_renderer != null:
		track_renderer.update_car_snapshots(controller.get_snapshots())
	_update_telemetry_ui()
	if _sim_ui != null:
		_sim_ui.refresh_button_states()
	for info in _car_infos:
		if info.get("id", null) == car_id:
			info["start_enabled"] = false
			break
	if _telemetry_data.has(car_id):
		var entry: Dictionary = _telemetry_data[car_id]
		if entry.get("status", "") not in ["Finished", "Derailed"]:
			entry["status"] = "Stopped"
		entry["acceleration"] = 0.0
		entry["airborne_speed"] = 0.0
		entry["in_air"] = false
		entry["speed"] = 0.0
		_telemetry_data[car_id] = entry
	_update_telemetry_ui()

func is_car_running(car_id: Variant) -> bool:
	if controller == null:
		return false
	return controller.is_car_running(car_id)

func _update_telemetry_ui() -> void:
	if _sim_ui == null:
		return
	_sim_ui.update_telemetry(_telemetry_data)

func _make_default_telemetry(car_id: Variant, display_name: String) -> Dictionary:
	return {
		"id": car_id,
		"name": display_name,
		"speed": 0.0,
		"acceleration": 0.0,
		"distance": 0.0,
		"time": 0.0,
		"battery": 0.0,
		"laps": 0,
		"rail_hits": 0,
		"altitude": 0.0,
		"airborne_speed": 0.0,
		"in_air": false,
		"status": "Idle"
	}

func _base_params_snapshot(params: CarModel.CarParams) -> Dictionary:
	if params == null:
		return {}
	return {
		"mass": params.mass,
		"drive_force_max": params.drive_force_max,
		"battery_capacity": params.battery_capacity,
		"rolling_resistance": params.rolling_resistance,
		"drag_coefficient": params.drag_coefficient,
		"frontal_area": params.frontal_area,
		"drag_area": params.drag_area,
		"regen_factor": params.regen_factor,
		"free_speed": params.free_speed,
		"lateral_friction_scale": params.lateral_friction_scale,
		"downforce_lateral": params.downforce_lateral,
		"roller_bonus": params.roller_bonus,
		"lateral_margin": params.lateral_margin,
		"rail_hit_penalty": params.rail_hit_penalty,
		"rail_hit_soft_threshold": params.rail_hit_soft_threshold,
		"max_rail_hits": params.max_rail_hits
	}

func _start_simulation() -> void:
	if controller == null:
		return
	if _car_ids.is_empty():
		push_warning("Main: No cars registered with simulation controller.")
		return
	controller.reset_all_cars()
	for car_id in _car_ids:
		_telemetry_prev[car_id] = {}
	_apply_track_start_lanes()
	var auto_started := false
	for info in _car_infos:
		if bool(info.get("start_enabled", false)):
			var car_id: Variant = info.get("id", "")
			start_car(car_id, true)
			auto_started = true
	_simulation_active = controller.is_running()
	if track_renderer != null:
		track_renderer.update_car_snapshots(controller.get_snapshots())
	if not auto_started:
		push_warning("Main: No cars enabled for auto-start; use UI toggles to run.")
	_update_telemetry_ui()

func _collect_car_components() -> Array[CarComponent]:
	var comps: Array[CarComponent] = []
	var seen: Dictionary = {}
	for path in car_component_paths:
		if path == NodePath(""):
			continue
		var node := get_node_or_null(path)
		if node is CarComponent:
			if not seen.has(node):
				comps.append(node)
				seen[node] = true
		elif node == null:
			push_warning("Main: CarComponent path '%s' not found." % String(path))
		else:
			push_warning("Main: Node at '%s' is not a CarComponent; ignoring." % String(path))
	if comps.is_empty():
		for child in get_children():
			if child is CarComponent and not seen.has(child):
				comps.append(child)
				seen[child] = true
	if comps.is_empty():
		var direct_components := get_tree().get_nodes_in_group("car_components")
		for node in direct_components:
			if node is CarComponent and not seen.has(node):
				comps.append(node)
				seen[node] = true
	return comps

func _assemble_scene_cars() -> int:
	_car_models.clear()
	_car_ids.clear()
	_component_to_car_id.clear()
	_car_infos.clear()
	_telemetry_prev.clear()
	_telemetry_data.clear()
	if controller != null:
		controller.clear_cars()
	var lane_count: int = 1
	if _track != null:
		lane_count = int(_track.get_track_meta().get("lanes", lane_count))
	if lane_count <= 0:
		lane_count = 1
	var allowed: int = min(_car_components.size(), lane_count)
	if _car_components.size() > lane_count:
		push_warning("Main: %d cars configured but only %d lanes available; ignoring extras." % [_car_components.size(), lane_count])
	var used: int = 0
	for i in range(allowed):
		var comp: CarComponent = _car_components[i]
		if comp == null:
			continue
		comp.assemble()
		var model: CarModel = comp.get_car_model()
		if model == null:
			push_warning("Main: CarComponent '%s' failed to produce a CarModel." % comp.name)
			continue
		var base_name: String = comp.name if comp.name != "" else "car"
		var car_id: Variant = base_name
		var suffix: int = 1
		while _car_models.has(car_id):
			car_id = "%s_%d" % [base_name, suffix]
			suffix += 1
		if controller != null:
			controller.add_car(car_id, model)
		else:
			model.reset_car_state()
		var state: CarModel.CarState = model.get_car_state()
		state.lane = clamp(i + 1, 1, lane_count)
		var base_params_snapshot := _base_params_snapshot(model.base_params)
		print("Car %s base_params => %s" % [str(car_id), JSON.stringify(base_params_snapshot, "\t", true)])
		_car_models[car_id] = model
		_car_ids.append(car_id)
		_component_to_car_id[comp] = car_id
		_car_infos.append({
			"id": car_id,
			"name": base_name,
			"start_enabled": comp.start_enabled
		})
		_telemetry_data[car_id] = _make_default_telemetry(car_id, base_name)
		_telemetry_prev[car_id] = {}
		used += 1
	_update_telemetry_ui()
	return used

func _on_car_component_assembled(model: CarModel, comp: CarComponent) -> void:
	if model == null or comp == null:
		return
	var car_id: Variant = _component_to_car_id.get(comp, null)
	if car_id == null:
		return
	var lane_index := _car_ids.find(car_id)
	if lane_index == -1:
		return
	if controller != null:
		controller.add_car(car_id, model)
	var lane_count: int = 1
	if _track != null:
		lane_count = int(_track.get_track_meta().get("lanes", lane_count))
	if lane_count <= 0:
		lane_count = 1
	var state: CarModel.CarState = model.get_car_state()
	state.lane = clamp(lane_index + 1, 1, lane_count)
	_car_models[car_id] = model
	_telemetry_prev[car_id] = {}
	var display_name: String = str(car_id)
	for info in _car_infos:
		if info.get("id", null) == car_id:
			display_name = String(info.get("name", car_id))
			info["start_enabled"] = comp.start_enabled
			break
	var entry: Dictionary = _make_default_telemetry(car_id, display_name)
	if controller != null and controller.is_car_running(car_id):
		entry["status"] = "Running"
	else:
		entry["status"] = "Idle"
	_telemetry_data[car_id] = entry
	if _simulation_active and controller != null and track_renderer != null:
		track_renderer.update_car_snapshots(controller.get_snapshots())
	_update_telemetry_ui()
	if _sim_ui != null:
		_sim_ui.refresh_button_states()
