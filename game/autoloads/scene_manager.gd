extends Node

#manage scene switching and transitioning

var main_scene: Node
var current_scene: Node
var scene_data: Dictionary = {
	&"main_menu": preload("res://scenes/main_menu/main_menu.tscn"),
	&"simulation": preload("res://scenes/sim_3d/sim_3d.tscn"),
}

func change_scene_to(scene_id: StringName) -> void:
	if current_scene != null and main_scene.get_child_count() > 0:
		main_scene.get_child(0).queue_free()
		await get_tree().process_frame

	current_scene = scene_data[scene_id].instantiate()
	main_scene.add_child(current_scene)
