extends StaticBody3D
class_name ComponentPickable3D
#attach this to a 3d node to make it drag droppable
#this should subscribe to some kind of signal to notify it being drag or dropped

@export var entity: Node3D
@export var pickable_id: String = ""

var mouse_ray_origin: Vector3
var mouse_ray_direction: Vector3
var ray_length: float = 1000.0
var is_picked: bool = false
var drag_offset: Vector3
var original_position: Vector3
var original_rotation: Vector3
var original_scale: Vector3

func _ready() -> void:
	assert(entity)
	DragDropController.object_picked.connect(_on_object_picked)
	DragDropController.object_dropped.connect(_on_object_dropped)
	original_position = entity.position
	original_rotation = entity.rotation_degrees
	original_scale = entity.scale

func _on_object_picked(component: ComponentPickable3D) -> void:
	if component == self:
		is_picked = true
		entity.visible = false
		print("Component picked:", entity)

func _on_object_dropped(component: ComponentPickable3D, _target: ComponentDroppable3D) -> void:
	if component == self:
		is_picked = false
		entity.visible = true
