extends Camera3D
#free look camera for car builder
#press wasd to move cam, mouse to look around, and up/down to zoom in out (with limits)

func _physics_process(delta: float) -> void:
	if Input.is_action_pressed("cam_move_up"):
		var tween = get_tree().create_tween()
		tween.tween_property(self, "position:z", self.position.z - 1, 0.1)
	if Input.is_action_pressed("cam_move_down"):
		var tween = get_tree().create_tween()
		tween.tween_property(self, "position:z", self.position.z + 1, 0.1)
	if Input.is_action_pressed("cam_move_left"):
		var tween = get_tree().create_tween()
		tween.tween_property(self, "position:x", self.position.x - 1, 0.1)
	if Input.is_action_pressed("cam_move_right"):
		var tween = get_tree().create_tween()
		tween.tween_property(self, "position:x", self.position.x + 1, 0.1)
	if Input.is_action_pressed("cam_rotate_right"):
		var tween = get_tree().create_tween()
		tween.tween_property(self, "rotation:y", self.rotation.y - 0.1, 0.1)
	if Input.is_action_pressed("cam_rotate_left"):
		var tween = get_tree().create_tween()
		tween.tween_property(self, "rotation:y", self.rotation.y + 0.1, 0.1)		
	if Input.is_action_pressed("cam_reset"):
		self.rotation = Vector3.ZERO
		self.rotation.x = deg_to_rad(-60)
		position = Vector3(0.0,4,2)
