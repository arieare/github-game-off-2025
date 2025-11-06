extends CanvasLayer

@export var button_quit: Button
@export var button_start: Button
@export var button_options: Button

signal focus_change(new_focus: Control)

func _ready() -> void:
	button_start.pressed.connect(_on_button_start_pressed)
	button_options.pressed.connect(_on_button_options_pressed)
	button_quit.pressed.connect(_on_button_quit_pressed)
	button_start.grab_focus()

func _on_button_start_pressed() -> void:
	pass

func _on_button_options_pressed() -> void:
	pass

func _on_button_quit_pressed() -> void:
	get_tree().quit()
