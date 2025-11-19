extends Control
class_name CarouselUI

signal current_focused(track_info)

@export var item_scene: PackedScene = preload("res://scenes/track_selector/carousel_item.tscn")
@export var is_wrapping: bool = true
@export var base_track_folder: String = "res://assets/tracks"
@export var track_paths: Array = []

var _track_options: Array = []
var _items: Array = []
var _current_index: int = 0

@export var _left_button : Button
@export var _right_button :  Button
@export var _items_viewport : Control
@export var _items_container : HBoxContainer

func _ready() -> void:
	_left_button.pressed.connect(_on_navigate_left)
	_right_button.pressed.connect(_on_navigate_right)
	refresh_tracks()

func refresh_tracks() -> void:
	_track_options = _build_track_list()
	_rebuild_items()
	_current_index = clamp(_current_index, 0, max(0, _track_options.size() - 1))
	if _track_options.is_empty():
		emit_signal("current_focused", null)
	else:
		call_deferred("_update_focus")

func get_current_track() -> Dictionary:
	if _track_options.is_empty():
		return {}
	return _track_options[_current_index]

func _build_track_list() -> Array:
	var sources := _resolve_track_sources()
	sources.sort_custom(_sort_paths)
	var unlocked : Array = PlayerData.profile.get("progress", {}).get("unlocked_tracks", [])
	var result := []
	for source in sources:
		var entry := _create_track_entry(source, unlocked)
		if entry.is_empty():
			continue
		result.append(entry)
	result.sort_custom(_sort_entries)
	return result

func _resolve_track_sources() -> Array:
	if track_paths.is_empty():
		return _scan_track_folder()
	return track_paths.duplicate()

func _scan_track_folder() -> Array:
	var dir := DirAccess.open(base_track_folder)
	if dir == null:
		push_warning("CarouselMenu: Unable to open track folder '%s'." % base_track_folder)
		return []
	var results := []
	var base_path := base_track_folder
	if not base_path.ends_with("/"):
		base_path += "/"
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if dir.current_is_dir():
			continue
		if name.to_lower().ends_with(".tres"):
			results.append("%s%s" % [base_path, name])
	dir.list_dir_end()
	return results

func _create_track_entry(source, unlocked_list) -> Dictionary:
	var resource: Resource = null
	var path := ""
	if typeof(source) == TYPE_STRING:
		path = str(source)
		resource = ResourceLoader.load(path)
	elif source is Resource:
		resource = source
		path = resource.resource_path
	else:
		return {}
	if resource == null:
		return {}
	if path == "":
		path = str(source)
	var unlocked : bool = path in unlocked_list
	return {
		"id": path,
		"name": _format_track_name(resource, path),
		"resource": resource,
		"unlocked": unlocked
	}

func _format_track_name(resource, path: String) -> String:
	var base := path.get_file().get_basename()
	if base == "":
		base = resource.get_class()
	base = base.replace("_", " ")
	return base.capitalize()

func _sort_paths(a, b):
	var left := str(a)
	var right := str(b)
	if left < right:
		return -1
	elif left > right:
		return 1
	return 0

func _sort_entries(a, b):
	var a_unlocked := bool(a.get("unlocked", false))
	var b_unlocked := bool(b.get("unlocked", false))
	if a_unlocked != b_unlocked:
		return -1 if a_unlocked else 1
	var a_name := str(a.get("name", ""))
	var b_name := str(b.get("name", ""))
	if a_name < b_name:
		return -1
	elif a_name > b_name:
		return 1
	return 0

func _rebuild_items() -> void:
	for child in _items_container.get_children():
		child.queue_free()
	_items.clear()
	for option in _track_options:
		var instantiated := item_scene.instantiate()
		if instantiated == null or not instantiated is Control:
			continue
		var item := instantiated as Control
		if item.has_method("configure"):
			item.call("configure", option, false)
		_items_container.add_child(item)
		_items.append(item)

func _update_focus() -> void:
	if _items.is_empty():
		return
	_current_index = clamp(_current_index, 0, _items.size() - 1)
	for i in range(_items.size()):
		var item : Control = _items[i]
		if item.has_method("set_selected"):
			item.call("set_selected", i == _current_index)
	_scroll_to_current()
	emit_signal("current_focused", _track_options[_current_index])

func _scroll_to_current() -> void:
	if _items.is_empty() or _items_viewport.get_size().x <= 0.0:
		return
	var control_item := _items[_current_index] as Control
	if control_item == null:
		return
	var viewport_width: float = _items_viewport.get_size().x
	var focus_center: float = control_item.get_position().x + control_item.get_size().x * 0.5
	var max_offset: float = max(0.0, _items_container.get_size().x - viewport_width)
	var target_offset: float = clamp(focus_center - viewport_width * 0.5, 0.0, max_offset)
	var container_pos := _items_container.get_position()
	_items_container.set_position(Vector2(-target_offset, container_pos.y))
	
	for items in _items:
		items.modulate.a = 0.2
	
	control_item.modulate.a = 1


func _on_navigate_left() -> void:
	if _track_options.is_empty():
		return
	var next_index := _current_index - 1
	if next_index < 0:
		if is_wrapping:
			next_index = _track_options.size() - 1
		else:
			next_index = 0
	_current_index = next_index
	_update_focus()

func _on_navigate_right() -> void:
	if _track_options.is_empty():
		return
	var next_index := _current_index + 1
	if next_index >= _track_options.size():
		if is_wrapping:
			next_index = 0
		else:
			next_index = _track_options.size() - 1
	_current_index = next_index
	_update_focus()
