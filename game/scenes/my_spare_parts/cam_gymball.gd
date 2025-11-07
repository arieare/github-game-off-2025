extends Node3D

@export var static_collision_interface: StaticBody3D
var ray_length: float = 2000.0
var drag_sensitivity: float = 0.005
var damping: float = 0.92
var min_speed: float = 0.01

var _mouse_dragging: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _angular_velocity: Vector3 = Vector3.ZERO
var _camera: Camera3D = null
var _space_state: PhysicsDirectSpaceState3D = null
var _pending_press: bool = false
var _pending_press_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	_camera = get_child(0) if get_child_count() > 0 else null
	if _camera is Camera3D:
		_camera = _camera
	else:
		_camera = null
	set_process_input(true)
	update_space_state()

func update_space_state() -> void:
	if static_collision_interface != null and static_collision_interface.get_world_3d() != null:
		_space_state = static_collision_interface.get_world_3d().direct_space_state

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_handle_mouse_press(event.position)
			else:
				_handle_mouse_release()
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _handle_mouse_press(position: Vector2) -> void:
	if _camera == null or static_collision_interface == null:
		return
	_pending_press = true
	_pending_press_position = position

func _handle_mouse_release() -> void:
	_mouse_dragging = false
	_pending_press = false

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _mouse_dragging:
		var delta := event.relative
		if delta.length() == 0:
			return
		var rotation_axis := (Vector3(0, 1, 0) * delta.x) + (_camera.transform.basis.x * delta.y)
		var rot_vec := rotation_axis * drag_sensitivity
		rotate_object_local(Vector3.UP, -rot_vec.y)
		rotate_object_local(Vector3.RIGHT, -rot_vec.x)
		_angular_velocity = rot_vec / max(event.relative.length(), 0.001)
		_last_mouse_pos = event.position
	else:
		_last_mouse_pos = event.position

func _physics_process(delta: float) -> void:
	if _pending_press:
		var collides := _ray_hits_static_body(_pending_press_position)
		print(collides)
		_pending_press = false
		if collides:
			_mouse_dragging = true
			_last_mouse_pos = _pending_press_position
			_angular_velocity = Vector3.ZERO

	if _mouse_dragging:
		return
	if _angular_velocity.length() > min_speed:
		rotate_object_local(Vector3.UP, -_angular_velocity.y)
		rotate_object_local(Vector3.RIGHT, -_angular_velocity.x)
		_angular_velocity *= damping
	else:
		_angular_velocity = Vector3.ZERO

func _ray_hits_static_body(screen_pos: Vector2) -> bool:
	if _camera == null or _space_state == null or static_collision_interface == null:
		return false
	var origin := _camera.project_ray_origin(screen_pos)
	var direction := _camera.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * ray_length)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result := _space_state.intersect_ray(query)
	if result.is_empty():
		return false
	return result.get("collider") == static_collision_interface
