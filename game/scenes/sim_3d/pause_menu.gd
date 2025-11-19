extends CanvasLayer

@export var button_pause: TextureButton
@export var button_return: Button
@export var button_main: Button

func _ready() -> void:
	_hide()
	button_pause.pressed.connect(_on_button_pause_pressed)
	button_return.pressed.connect(_on_button_return_pressed)
	button_main.pressed.connect(_on_button_main_pressed)

func _show() -> void:
	self.visible = true

func _hide() -> void:
	self.visible = false

func _on_button_pause_pressed() -> void:
	_show()

func _on_button_return_pressed() -> void:
	_hide()

func _on_button_main_pressed() -> void:
	SceneManager.change_scene_to(&"main_menu")
