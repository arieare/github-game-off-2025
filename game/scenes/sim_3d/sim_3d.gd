extends Node3D
class_name Controller3D

signal car_assembled(car: CarModel)

@export var renderer: TrackRenderer3D
@export var sim_controller: SimulationController
@export var cars: Array[CarBlueprint] = []
@export var selected_car_index: int = 0
@export var auto_start: bool = false
var car_array: Array[CarModel] = []
const PLAYER_CAR_ID := "player"
var _pending_auto_start: bool = false
var _car_builder: CarComponent = null

func _ready() -> void:
	# 1) Build the track once in the renderer (keeps visuals + path in sync)
	renderer.set_track_model(renderer.track)               # uses exported TrackBlueprint
	# Share the *same* TrackModel instance with the sim_controller to avoid drift
	sim_controller.set_track_model(renderer.track_model)
	_pending_auto_start = auto_start

	if not _initialize_car_builder():
		push_error("Controller3D: Unable to initialize internal CarComponent builder.")
		return
	if not _car_builder.is_connected("assembled", Callable(self, "_on_car_component_assembled")):
		_car_builder.assembled.connect(_on_car_component_assembled)

	# 2) Assemble and register the selected car blueprint
	_assemble_selected_car()
	
	# 3) Stream sim_controller states into the renderer (adapter to drop the first arg)
	sim_controller.state_updated.connect(func(_car_id, state: Dictionary) -> void:
		state.lane = 3
		renderer.update_car_snapshot(state)
	)

	# (Optional) Also watch finish/lap/derail for UI
	sim_controller.car_finished.connect(_on_car_finished)
	sim_controller.car_derailed.connect(func(id, t, f): print("Derailed", id, t, f))

func _physics_process(delta: float) -> void:
	# Advance the sim_controllerulation at your engine rate
	sim_controller.step(delta)

func _on_car_finished(car_id: Variant, time: float):
	print("Finished", car_id, str(time))

func _assemble_selected_car() -> void:
	if _car_builder == null and not _initialize_car_builder():
		push_error("Controller3D: Unable to initialize car builder.")
		return

	if cars.is_empty():
		push_warning("Controller3D: No car blueprints assigned; cannot assemble car.")
		return

	var idx := clampi(selected_car_index, 0, cars.size() - 1)
	var blueprint: CarBlueprint = cars[idx]
	if blueprint == null:
		push_warning("Controller3D: Selected car blueprint is null, rebuilding with current parts.")
		_car_builder.assemble()
		return

	var ok: bool = _car_builder.apply_blueprint(blueprint)
	if not ok:
		push_warning("Controller3D: Failed to apply blueprint %s, rebuilding existing configuration." % str(blueprint.car_name))
		_car_builder.assemble()

func _on_car_component_assembled(model: CarModel) -> void:
	if model == null:
		return
	sim_controller.clear_cars()
	sim_controller.add_car(PLAYER_CAR_ID, model)
	car_array = [model]
	emit_signal("car_assembled", model)
	if _pending_auto_start:
		sim_controller.start()
		_pending_auto_start = false

func _initialize_car_builder() -> bool:
	if _car_builder != null:
		return true
	_car_builder = CarComponent.new()
	_car_builder.name = "RuntimeCarBuilder"
	add_child(_car_builder)
	return _car_builder != null
