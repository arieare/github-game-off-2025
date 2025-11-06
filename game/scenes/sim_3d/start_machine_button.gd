extends CheckButton

@export var sim: SimulationController
@export var controller3d: Controller3D
@export var car_id: String

func _ready() -> void:
	self.toggled.connect(_on_car_toggle)

func _on_car_toggle(button_pressed: bool) -> void:
	if sim == null:
		return
	if button_pressed:
		sim.start_car(car_id, false)
	else:
		sim.stop_car(car_id)
	
