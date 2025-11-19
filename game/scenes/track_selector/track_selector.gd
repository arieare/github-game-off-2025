extends CanvasLayer

@export var carousel_ui: CarouselUI
@export var track_name: RichTextLabel
@export var button_select_track: Button
@export var button_back: Button
var info: Dictionary = {}

func _ready() -> void:
	carousel_ui.current_focused.connect(_on_carousel_focused)
	button_back.pressed.connect(_on_button_back_pressed)
	button_select_track.pressed.connect(_on_button_select_track_pressed)
	
func _on_carousel_focused(track_info: Dictionary) -> void:
	info = track_info
	button_select_track.text = "Select " + info["name"]
	if info["unlocked"]:
		button_select_track.disabled = false
	else: button_select_track.disabled = true

func _on_button_back_pressed() -> void:
	SceneManager.change_scene_to(&"main_menu")	

func _on_button_select_track_pressed() -> void:
	print(info)
	Global.selected_track = load(info["id"])
	SceneManager.change_scene_to(&"simulation")	
