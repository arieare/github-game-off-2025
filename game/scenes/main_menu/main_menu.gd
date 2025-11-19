extends CanvasLayer

@export var button_quit: Button
@export var button_start: Button
@export var button_options: Button
@export var button_my_spare_parts: Button

func _ready() -> void:
	button_start.pressed.connect(_on_button_start_pressed)
	button_options.pressed.connect(_on_button_options_pressed)
	button_quit.pressed.connect(_on_button_quit_pressed)
	button_my_spare_parts.pressed.connect(_on_button_my_spare_parts)
	button_start.grab_focus()

func _on_button_start_pressed() -> void:
	SceneManager.change_scene_to(&"track_selector")
	
func _on_button_my_spare_parts() -> void:
	SceneManager.change_scene_to(&"my_spare_parts")	

func _on_button_options_pressed() -> void:
	SceneManager.change_scene_to(&"option_menu")	

func _on_button_quit_pressed() -> void:
	get_tree().quit()
