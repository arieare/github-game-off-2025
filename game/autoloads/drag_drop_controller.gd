extends Node3D

var mouse_ray_origin: Vector3
var mouse_ray_direction: Vector3
var ray_length: float = 1000.0
var selected_part: Node3D = null
var is_dragging: bool = false
var drag_offset: Vector3
var ray_collision: Dictionary
var drag_plane: StaticBody3D
var drag_collision_shape: CollisionShape3D
var fake_mesh_instance: MeshInstance3D

signal object_picked(component: ComponentPickable3D)
signal object_dropped(component: ComponentPickable3D)
var picked_object: ComponentPickable3D = null

#this is data driven drag and drop controller, so we don't actually need continuous drag tracking,
#when we click on a 3d object with ComponentPickable3D script attached, we will emit signal
#the actual object will be hidden and the pointer child will spawn a mesh instance of the picked object
#same when dropping, we will emit another signal, hide and destroy the pointer child mesh, and show the object in the drop position.
#while dragging we will carry data only, no actual object movement.

func _ready() -> void:
	#spawn a rectangular collider plane which cover the camera in a certain distance (e.g 10 units perpendicular from camera)
	#this collider will only be shown when is_dragging is true
	
	spawn_drag_plane()
	
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
		drag_plane.position = get_viewport().get_camera_3d().transform.origin + get_viewport().get_camera_3d().transform.basis.z * -10
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

		if is_dragging and picked_object:
			#update fake mesh position to follow mouse ray on drag plane
			var plane_space_state = drag_plane.get_world_3d().direct_space_state
			var plane_query = PhysicsRayQueryParameters3D.new()
			plane_query.from = mouse_ray_origin
			plane_query.to = mouse_ray_origin + mouse_ray_direction * ray_length
			var plane_result = plane_space_state.intersect_ray(plane_query)
			if plane_result.has("position"):
				fake_mesh_instance.position = plane_result["position"] + drag_offset


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.is_action_pressed("click"):
			if ray_collision.has("collider") and ray_collision["collider"] is ComponentPickable3D:
				object_picked.emit(ray_collision["collider"])
				picked_object = ray_collision["collider"]
				is_dragging = true
				drag_plane.visible = true
				drag_collision_shape.disabled = false
				fake_mesh_instance.visible = true
				#fake_mesh_instance.mesh = picked_object.entity.get_node_or_null(MeshInstance3D).mesh

		if event.is_action_released("click"):
			object_dropped.emit(picked_object)
			picked_object = null
			is_dragging = false
			if drag_plane:
				drag_plane.visible = false
				drag_collision_shape.disabled = true
			fake_mesh_instance.visible = false
