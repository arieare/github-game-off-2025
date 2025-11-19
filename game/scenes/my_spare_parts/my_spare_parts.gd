extends Node

signal item_selected(spare_part_id: String)

@export var spare_part_tab: TabContainer
@export var chassis_tab: GridContainer
@export var body_tab: GridContainer
@export var motor_tab: GridContainer
@export var roller_tab: GridContainer
@export var wheel_tab: GridContainer

@export var description_box: RichTextLabel

@export var btn_back: Button

@export var preview_node: Node3D

var _tab_grids: Dictionary = {}

func _ready() -> void:
	btn_back.pressed.connect(_on_btn_back_pressed)
	_init_tab_grids()
	_populate_inventory()

func _on_btn_back_pressed() -> void:
	SceneManager.change_scene_to(&"main_menu")

func _init_tab_grids() -> void:
	_tab_grids.clear()
	_tab_grids[SparePartData.SparePartType.MOTOR] = motor_tab
	_tab_grids[SparePartData.SparePartType.BODY] = body_tab
	_tab_grids[SparePartData.SparePartType.BATTERY] = chassis_tab
	_tab_grids[SparePartData.SparePartType.WHEEL] = wheel_tab
	_tab_grids[SparePartData.SparePartType.ROLLER] = roller_tab

func _get_grid_from_panel(panel: PanelContainer) -> GridContainer:
	if panel == null:
		return null
	return panel.get_node_or_null("GridContainer")

func _populate_inventory() -> void:
	if PlayerData == null or not _tab_grids:
		return
	for grid in _tab_grids.values():
		if grid == null:
			continue
		for child in grid.get_children():
			child.queue_free()
	var spare_parts: Dictionary = PlayerData.profile["inventory"]["spare_parts"]
	for part_id in spare_parts.keys():
		var entry: Dictionary = spare_parts[part_id]
		var meta: Dictionary = SparePartData.sparepart.get(part_id, {})
		if meta.is_empty():
			continue
		var type : SparePartData.SparePartType= meta.get("type", null)
		var grid: GridContainer = _tab_grids.get(type, null)
		if grid == null:
			continue
		var item := _create_inventory_item(part_id, entry, meta)
		if item != null:
			grid.add_child(item)

func _create_inventory_item(part_id: String, entry: Dictionary, meta: Dictionary) -> VBoxContainer:
	var container := VBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	var button := TextureButton.new()
	#button.expand_icon = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.custom_minimum_size = Vector2(96, 96)
	button.tooltip_text = meta.get("name", part_id)
	var icon_path: String = meta.get("icon-path", "")
	if icon_path != "":
		var tex := load(icon_path)
		if tex:
			button.texture_normal = tex
	button.set_meta("part_id", part_id)
	button.pressed.connect(_on_inventory_item_pressed.bind(button))
	container.add_child(button)

	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	var count_owned := int(entry.get("owned", 0))
	var count_available := int(entry.get("available", 0))
	label.text = "%s\nx%d (%d free)" % [
		meta.get("name", part_id),
		count_owned,
		count_available
	]
	container.add_child(label)
	return container

func _on_inventory_item_pressed(button: TextureButton) -> void:
	var part_id: String = button.get_meta("part_id", "")
	if part_id == "":
		return
	var entry :Dictionary= PlayerData.profile["inventory"]["spare_parts"].get(part_id, {})
	var meta :Dictionary= SparePartData.sparepart.get(part_id, {})
	if meta.is_empty():
		return
	_show_preview(meta)
	_update_description(meta, entry)
	emit_signal("item_selected", part_id)

func _show_preview(meta: Dictionary) -> void:
	for child in preview_node.get_children():
		child.queue_free()
	var mesh_path: String = meta.get("mesh-path", "")
	if mesh_path == "":
		return
	var mesh_resource := load(mesh_path)
	if mesh_resource == null:
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh_resource
	mesh_instance.transform.origin = Vector3.ZERO
	preview_node.add_child(mesh_instance)

func _update_description(meta: Dictionary, entry: Dictionary) -> void:
	var sb := ""
	sb += "[b]%s[/b]\n" % meta.get("name", "Unknown Part")
	sb += "%s\n\n" % meta.get("description", "No description available.")
	sb += "Owned: %d\nAvailable: %d\n\n" % [
		int(entry.get("owned", 0)),
		int(entry.get("available", 0))
	]
	var stats := _load_part_stats(meta.get("source-path", ""))
	if not stats.is_empty():
		sb += "[b]Stats[/b]\n"
		for key in stats.keys():
			sb += "%s: %s\n" % [key, str(stats[key])]
	description_box.text = sb

func _load_part_stats(script_path: String) -> Dictionary:
	if script_path == "":
		return {}
	var script_res := load(script_path)
	if script_res == null:
		return {}
	var node :SparePartBase= script_res.new()
	if node == null:
		return {}
	var stats: Dictionary = {}
	if node.has_method("get_part_stats"):
		stats = node.get_part_stats()
	node.free()
	return stats
