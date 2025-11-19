extends CanvasLayer

@export var sim_controller: SimulationController
@export var car: CarModel

@export var ui_battery_indicator: TextureProgressBar
@export var ui_timer: RichTextLabel

func _ready() -> void:
	var events := sim_controller.get_event_bus() if sim_controller else null
	if events:
		events.state_updated.connect(_on_state_updated)

func _on_state_updated(car_id:Variant, data: Dictionary) -> void:
	ui_battery_indicator.value = data.get("battery", 100.0)
	ui_timer.text = format_time(data.get("time", 00.00))

func format_time(sec: float) -> String:
	var total_ms: int = int(round(sec * 1000.0))
	var minutes: int = total_ms / 60000
	var seconds: int = (total_ms % 60000) / 1000
	var millis: int = total_ms % 1000
	return "%02d:%02d:%03d" % [minutes, seconds, millis]
