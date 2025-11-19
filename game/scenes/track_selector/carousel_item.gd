extends Control
class_name CarouselItem

@export var highlight_tint: Color = Color(0.52, 0.7, 0.95, 1)
@export var locked_tint: Color = Color(0.7, 0.7, 0.72, 1)
@export var default_tint: Color = Color(0.92, 0.93, 0.96, 1)

@export var _background : ColorRect
@export var _title_label : Label
@export var _status_label : Label

var track_info := {}

func configure(info: Dictionary, selected: bool) -> void:
	track_info = info.duplicate()
	_title_label.text = str(info.get("name", "Track"))
	var unlocked := bool(info.get("unlocked", false))
	_status_label.visible = not unlocked
	if not unlocked:
		_status_label.text = "Locked"
	else:
		_status_label.text = ""
	_update_visuals(selected, unlocked)

func set_selected(value: bool) -> void:
	_update_visuals(value, bool(track_info.get("unlocked", false)))

func get_track_info() -> Dictionary:
	return track_info

func _update_visuals(selected: bool, unlocked: bool) -> void:
	var base_color: Color
	if unlocked:
		base_color = default_tint
	else:
		base_color = locked_tint
	if selected:
		_background.color = base_color.lerp(highlight_tint, 0.35)
	else:
		_background.color = base_color
	#_title_label.add_color_override("font_color", Color(0.1, 0.1, 0.15, 1))
	#_status_label.add_color_override("font_color", Color(0.45, 0.2, 0.2, 1))
