extends CanvasLayer

@export var button_back: Button

func _ready() -> void:
	button_back.pressed.connect(_on_button_back_pressed)
	#button_start.grab_focus()

func _on_button_back_pressed() -> void:
	SceneManager.change_scene_to(&"main_menu")
