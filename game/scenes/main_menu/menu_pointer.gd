extends TextureRect

func _ready() -> void:
	get_viewport().gui_focus_changed.connect(_on_focus_change)

func _on_focus_change(node:Control) -> void:
	move_pointer_to(node)

#func _process(_delta: float) -> void:
	#if get_viewport().gui_get_hovered_control() == null:
		#return
	#else:
		#var node = get_viewport().gui_get_hovered_control()
		#if node is Button:
			#move_pointer_to(get_viewport().gui_get_hovered_control())

func move_pointer_to(node: Control) -> void:
	var self_size_y = self.get_rect().size.y
	var node_size_y = node.get_rect().size.y
	self.position.y = node.global_position.y + (node_size_y / 2) - (self_size_y / 2)
	self.position.x = node.global_position.x - 36	
