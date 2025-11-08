extends Node3D

var mouse_ray_origin: Vector3
var mouse_ray_direction: Vector3
var ray_length: float = 1000.0
var selected_pickable: ComponentPickable3D = null
var is_dragging: bool = false
var drag_offset: Vector3 = Vector3(0, 1.5, 0)
var ray_collision: Dictionary
var drag_plane: StaticBody3D
var drag_collision_shape: CollisionShape3D
var fake_mesh_instance: MeshInstance3D
var center_stage_position: Vector3 = Vector3.ZERO

signal object_picked(component: ComponentPickable3D)
signal object_dropped(component: ComponentPickable3D, drop_target: ComponentDroppable3D)
var picked_object: ComponentPickable3D = null
var hovered_droppable: ComponentDroppable3D = null
var _hover_position: Vector3 = Vector3.ZERO
var _mouse_press_position: Vector2 = Vector2.ZERO
var _is_click_candidate: bool = false
var _drag_threshold: float = 6.0
var _candidate_pickable: ComponentPickable3D = null

#this is data driven drag and drop controller, so we don't actually need continuous drag tracking,
#when we click on a 3d object with ComponentPickable3D script attached, we will emit signal
#the actual object will be hidden and the pointer child will spawn a mesh instance of the picked object
#same when dropping, we will emit another signal, hide and destroy the pointer child mesh, and show the object in the drop position.
#while dragging we will carry data only, no actual object movement.

func _ready() -> void:
	#spawn a rectangular collider plane which cover the camera in a certain distance (e.g 10 units perpendicular from camera)
	#this collider will only be shown when is_dragging is true
	
	spawn_drag_plane()
	if get_viewport().get_camera_3d():
		center_stage_position = get_viewport().get_camera_3d().transform.origin + get_viewport().get_camera_3d().transform.basis.z * -3.0
	else:
		center_stage_position = global_transform.origin
	
	fake_mesh_instance = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(1, 1, 1)
	fake_mesh_instance.mesh = mesh
	add_child(fake_mesh_instance)
	fake_mesh_instance.visible = false
	pass

func spawn_drag_plane() -> void:
	if get_viewport().get_camera_3d():
		drag_plane = StaticBody3D.new()
		var plane_shape = BoxShape3D.new()
		plane_shape.size = Vector3(100, 100, 1)
		
		drag_collision_shape = CollisionShape3D.new()
		drag_collision_shape.shape = plane_shape
		drag_plane.add_child(drag_collision_shape)
		add_child(drag_plane)
		drag_plane.position = get_viewport().get_camera_3d().transform.origin + get_viewport().get_camera_3d().transform.basis.z * -5
		drag_plane.look_at(get_viewport().get_camera_3d().transform.origin, Vector3.UP)
		drag_plane.visible = false
		drag_collision_shape.disabled = true	

func check_mouse_ray_collision(ray_origin: Vector3, ray_direction: Vector3) -> Dictionary:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.new()
	query.from = ray_origin
	query.to = ray_origin + ray_direction * ray_length
	var result = space_state.intersect_ray(query)
	return result

func _physics_process(delta: float) -> void:
	if get_viewport().get_camera_3d():
		mouse_ray_origin = get_viewport().get_camera_3d().project_ray_origin(get_viewport().get_mouse_position())
		mouse_ray_direction = get_viewport().get_camera_3d().project_ray_normal(get_viewport().get_mouse_position())	
		ray_collision = check_mouse_ray_collision(mouse_ray_origin, mouse_ray_direction)
		_update_hover_target()

		if is_dragging and picked_object:
			#update fake mesh position to follow mouse ray on drag plane
			var plane_space_state = drag_plane.get_world_3d().direct_space_state
			var plane_query = PhysicsRayQueryParameters3D.new()
			plane_query.from = mouse_ray_origin
			plane_query.to = mouse_ray_origin + mouse_ray_direction * ray_length
			var plane_result = plane_space_state.intersect_ray(plane_query)
			if plane_result.has("position"):
				fake_mesh_instance.position = plane_result["position"] + drag_offset
				_hover_position = plane_result["position"]


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_mouse_press(event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_handle_mouse_release()
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _handle_mouse_press(position: Vector2) -> void:
	_mouse_press_position = position
	_is_click_candidate = true
	var collider : StaticBody3D = ray_collision.get("collider", null)
	if collider is ComponentPickable3D:
		_candidate_pickable = collider
		fake_mesh_instance.global_position = _candidate_pickable.global_position	

func _handle_mouse_release() -> void:
	if picked_object != null:
		_finish_drag()
		return
	if _candidate_pickable != null:
		if _is_click_candidate:
			_select_pickable(_candidate_pickable)
		_candidate_pickable = null
		return
	if selected_pickable != null:
		_attempt_drop_selected()
	else:
		_clear_selection()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _is_click_candidate and _candidate_pickable != null:
		var distance := event.position.distance_to(_mouse_press_position)
		if distance > _drag_threshold:
			_is_click_candidate = false
			_start_drag(_candidate_pickable)

func _update_hover_target() -> void:
	var active_pickable := picked_object if picked_object != null else selected_pickable
	if active_pickable == null:
		if hovered_droppable:
			hovered_droppable.set_hover(false)
			hovered_droppable = null
		return
	var collider: StaticBody3D = ray_collision.get("collider", null)
	if collider is ComponentDroppable3D and collider.accepts(active_pickable):
		if collider != hovered_droppable:
			if hovered_droppable:
				hovered_droppable.set_hover(false)
			hovered_droppable = collider
			hovered_droppable.set_hover(true)
		if not is_dragging:
			_hover_position = collider.global_transform.origin
	else:
		if hovered_droppable:
			hovered_droppable.set_hover(false)
			hovered_droppable = null

func _start_drag(component: ComponentPickable3D) -> void:
	_clear_selection()
	object_picked.emit(component)
	picked_object = component
	is_dragging = true
	drag_plane.visible = true
	drag_collision_shape.disabled = false
	fake_mesh_instance.visible = true
	_candidate_pickable = null

func _finish_drag() -> void:
	var drop_target: ComponentDroppable3D = null
	if hovered_droppable != null and hovered_droppable.is_hovering:
		drop_target = hovered_droppable
	object_dropped.emit(picked_object, drop_target)
	if drop_target != null:
		drop_target.handle_drop(picked_object, _hover_position)
	if hovered_droppable:
		hovered_droppable.set_hover(false)
		hovered_droppable = null
	picked_object = null
	is_dragging = false
	if drag_plane:
		drag_plane.visible = false
		drag_collision_shape.disabled = true
	if selected_pickable == null:
		fake_mesh_instance.visible = false

func _select_pickable(component: ComponentPickable3D) -> void:
	_clear_selection()
	selected_pickable = component
	object_picked.emit(component)
	fake_mesh_instance.visible = true
	var tween = get_tree().create_tween()
	tween.tween_property(fake_mesh_instance,"position", center_stage_position, 0.3).set_trans(Tween.TRANS_BACK)
	# fake_mesh_instance.position = center_stage_position
	is_dragging = false
	if drag_plane:
		drag_plane.visible = false
		drag_collision_shape.disabled = true

func _attempt_drop_selected() -> void:
	if selected_pickable == null:
		return
	if hovered_droppable != null and hovered_droppable.is_hovering and hovered_droppable.accepts(selected_pickable):
		object_dropped.emit(selected_pickable, hovered_droppable)
		hovered_droppable.handle_drop(selected_pickable, hovered_droppable.global_transform.origin)
		hovered_droppable.set_hover(false)
		hovered_droppable = null
		_clear_selection()

func _clear_selection() -> void:
	if selected_pickable != null:
		if selected_pickable.entity:
			selected_pickable.entity.visible = true
		selected_pickable = null
	if not is_dragging:
		fake_mesh_instance.visible = false
