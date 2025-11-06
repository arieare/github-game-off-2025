extends CanvasLayer
class_name SimUI

@export var start_button_group: BoxContainer
@export var telemetry_log: RichTextLabel

var _sim: Node = null
var _buttons: Dictionary = {}
var _updating: bool = false

func setup_controls(sim_ref: Node, car_infos: Array) -> void:
	_sim = sim_ref
	_buttons.clear()
	if start_button_group == null:
		return
	for child in start_button_group.get_children():
		child.queue_free()
	_updating = true
	for info in car_infos:
		var car_id: Variant = info.get("id", "car")
		var label: String = String(info.get("name", car_id))
		var button := CheckButton.new()
		button.text = label
		button.toggle_mode = true
		button.button_pressed = bool(info.get("start_enabled", false))
		button.toggled.connect(_on_car_toggle.bind(car_id))
		start_button_group.add_child(button)
		_buttons[car_id] = button
	_updating = false
	refresh_button_states()

func refresh_button_states() -> void:
	if start_button_group == null:
		return
	if _sim == null or not _sim.has_method("is_car_running"):
		return
	_updating = true
	for car_id in _buttons.keys():
		var button: CheckButton = _buttons[car_id]
		if button == null:
			continue
		var pressed: bool = _sim.is_car_running(car_id)
		button.button_pressed = pressed
	_updating = false

func _on_car_toggle(button_pressed: bool, car_id: Variant) -> void:
	if _updating or _sim == null:
		return
	if button_pressed:
		if _sim.has_method("start_car"):
			_sim.start_car(car_id, true)
	else:
		if _sim.has_method("stop_car"):
			_sim.stop_car(car_id)

func update_telemetry(data: Dictionary) -> void:
	if telemetry_log == null:
		return
	var lines: Array[String] = []
	var ids: Array = []
	if start_button_group != null and start_button_group.get_child_count() > 0:
		for child in start_button_group.get_children():
			for car_id in _buttons.keys():
				if _buttons[car_id] == child:
					ids.append(car_id)
					break
	else:
		ids = data.keys()
		ids.sort()
	var seen: Dictionary = {}
	for car_id in ids:
		seen[car_id] = true
	for car_id in data.keys():
		if not seen.has(car_id):
			ids.append(car_id)
	for car_id in ids:
		var entry = data[car_id]
		if not (entry is Dictionary):
			continue
		var name: String = String(entry.get("name", car_id))
		lines.append(name)
		lines.append("  status: %s" % String(entry.get("status", "")))
		lines.append("  current speed: %.2f m/s" % float(entry.get("speed", 0.0)))
		lines.append("  current acceleration: %.2f m/s^2" % float(entry.get("acceleration", 0.0)))
		lines.append("  current distance: %.2f m" % float(entry.get("distance", 0.0)))
		lines.append("  running time: %.2f s" % float(entry.get("time", 0.0)))
		lines.append("  battery: %.2f" % float(entry.get("battery", 0.0)))
		lines.append("  laps: %d" % int(entry.get("laps", 0)))
		lines.append("  rail hits: %d" % int(entry.get("rail_hits", 0)))
		lines.append("  altitude: %.2f m" % float(entry.get("altitude", 0.0)))
		var in_air: bool = bool(entry.get("in_air", false))
		if in_air:
			lines.append("  in air: Yes")
		else:
			lines.append("  in air: No")
		lines.append("  airborne speed: %.2f m/s" % float(entry.get("airborne_speed", 0.0)))
		lines.append("")
	telemetry_log.text = "\n".join(lines)
