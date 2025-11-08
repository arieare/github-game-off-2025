extends StaticBody3D
class_name ComponentDroppable3D

@export var entity: Node3D
@export var accept_ids: PackedStringArray = []
@export var highlight_material: StandardMaterial3D

var is_hovering: bool = false
var _mesh_instance: MeshInstance3D = null
var _original_material: Material = null

func _ready() -> void:
	if entity == null:
		entity = self
	_mesh_instance = entity.get_node_or_null("MeshInstance3D") if entity else null
	if _mesh_instance:
		_original_material = _mesh_instance.material_override

func accepts(component: ComponentPickable3D) -> bool:
	if component == null:
		return false
	if accept_ids.is_empty():
		return true
	return component.pickable_id in accept_ids

func set_hover(state: bool) -> void:
	if is_hovering == state:
		return
	is_hovering = state
	_update_highlight()

func handle_drop(component: ComponentPickable3D, position: Vector3) -> void:
	if not accepts(component):
		return
	if component.entity:
		var target_transform := entity.global_transform if entity else global_transform
		var new_transform := component.entity.global_transform
		new_transform.origin = target_transform.origin
		component.entity.global_transform = new_transform
		component.entity.visible = true

func _update_highlight() -> void:
	if _mesh_instance == null or highlight_material == null:
		return
	if is_hovering:
		_mesh_instance.material_override = highlight_material
	else:
		_mesh_instance.material_override = _original_material
