extends Node

func _ready() -> void:
	SceneManager.main_scene = self
	SceneManager.change_scene_to(&"main_menu")
