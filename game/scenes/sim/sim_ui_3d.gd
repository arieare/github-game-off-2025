extends CanvasLayer

@export var car: CarModel
@export var battery_indicator: TextureProgressBar
@export var controller: SimulationController

func _ready() -> void:
	controller.state_updated.connect(_on_state_updated)

func _on_state_updated(car_id:Variant, data: Dictionary) -> void:
	battery_indicator.value = data.get("battery", 100.0)
