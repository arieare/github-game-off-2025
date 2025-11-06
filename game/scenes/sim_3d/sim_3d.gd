extends Node3D
class_name Controller3D

signal car_assembled(car: CarModel)

@export var renderer: TrackRenderer3D
@export var sim: SimulationController
@export var car_build: CarComponent
var car: CarModel = null

func _ready() -> void:
	# 1) Build the track once in the renderer (keeps visuals + path in sync)
	renderer.set_track_model(renderer.track)               # uses exported TrackBlueprint
	# Share the *same* TrackModel instance with the sim to avoid drift
	sim.set_track_model(renderer.track_model)

	# 2) Register cars (example — use your real CarModel factory)
	#car.assemble()
	car = car_build.get_car_model()	
	sim.add_car("rapidash", car)
	
	# 3) Stream sim states into the renderer (adapter to drop the first arg)
	sim.state_updated.connect(func(_car_id, state: Dictionary) -> void:
		state.lane = 3
		renderer.update_car_snapshot(state)
	)

	# (Optional) Also watch finish/lap/derail for UI
	sim.car_finished.connect(func(id, t): print("Finished", id, t))
	sim.car_derailed.connect(func(id, t, f): print("Derailed", id, t, f))

	# 4) Start
	#sim.start()

func _physics_process(delta: float) -> void:
	# Advance the simulation at your engine rate
	sim.step(delta)
