extends Node
# Central player profile and inventory/autosave helper.

var profile: Dictionary = {
	"currency": 0,
	"inventory": {
		"spare_parts": {}  # part_id -> { owned: int, available: int }
	},
	"garage": {
		"cars": []  # array of car definitions (see _make_car_entry)
	},
	"progress": {
		"unlocked_tracks": [],  # array of track ids or resource paths
		"track_stats": {}  # track_id -> { best_time, attempts, last_car_id }
	}
}

func _ready() -> void:
	_add_dummy_player_data()
	_validate_inventory()

# -- Inventory management ----------------------------------------------------

func add_spare_part(part_id: String, count: int = 1) -> void:
	if count <= 0:
		return
	if not _is_known_part(part_id):
		push_warning("PlayerData: Unknown spare part id '%s'." % part_id)
		return
	var entry : Dictionary = profile["inventory"]["spare_parts"].get(part_id, { "owned": 0, "available": 0 })
	entry["owned"] = int(entry.get("owned", 0)) + count
	entry["available"] = int(entry.get("available", 0)) + count
	profile["inventory"]["spare_parts"][part_id] = entry

func remove_spare_part(part_id: String, count: int = 1) -> bool:
	if count <= 0:
		return true
	var entry : Dictionary = profile["inventory"]["spare_parts"].get(part_id, null)
	if entry == null:
		return false
	if int(entry.get("available", 0)) < count:
		return false
	entry["owned"] = max(0, int(entry.get("owned", 0)) - count)
	entry["available"] = max(0, int(entry.get("available", 0)) - count)
	if entry["owned"] <= 0:
		profile["inventory"]["spare_parts"].erase(part_id)
	else:
		profile["inventory"]["spare_parts"][part_id] = entry
	return true

func get_available_parts(part_id: String) -> int:
	var entry : Dictionary = profile["inventory"]["spare_parts"].get(part_id, null)
	if entry == null:
		return 0
	return int(entry.get("available", 0))

func has_parts_for_blueprint(blueprint: CarBlueprint) -> bool:
	var needed : Dictionary = blueprint.get_slot_data("motor", {})
	return true  # placeholder detection intentionally simple; actual equip happens in equip_car_parts

# -- Garage management -------------------------------------------------------

func create_car(car_name: String, blueprint: CarBlueprint) -> Dictionary:
	var car_entry := _make_car_entry(car_name, blueprint)
	profile["garage"]["cars"].append(car_entry)
	return car_entry

func assign_parts_to_car(car_id: String, part_allocations: Dictionary) -> bool:
	var car := _find_car(car_id)
	if car == null:
		return false
	for slot_name in part_allocations.keys():
		var ids: Array = part_allocations[slot_name]
		if not _consume_parts(ids):
			return false
		car["slots"][slot_name] = ids
	return true

func dismantle_car(car_id: String) -> bool:
	var car := _find_car(car_id)
	if car == null:
		return false
	for slot_ids in car["slots"].values():
		for part_id in slot_ids:
			add_spare_part(part_id, 1)
	car["slots"].clear()
	return true

func get_cars() -> Array:
	return profile["garage"]["cars"]

# -- Progress tracking -------------------------------------------------------

func unlock_track(track_id: String) -> void:
	var tracks: Array = profile["progress"]["unlocked_tracks"]
	if track_id in tracks:
		return
	tracks.append(track_id)

func record_track_result(track_id: String, time_seconds: float, car_id: String) -> void:
	if track_id == "":
		return
	var stats : Dictionary = profile["progress"]["track_stats"].get(track_id, {
		"best_time": INF,
		"attempts": 0,
		"last_car_id": ""
	})
	stats["attempts"] = int(stats.get("attempts", 0)) + 1
	if time_seconds > 0.0 and time_seconds < float(stats.get("best_time", INF)):
		stats["best_time"] = time_seconds
	stats["last_car_id"] = car_id
	profile["progress"]["track_stats"][track_id] = stats

# -- Helpers -----------------------------------------------------------------

func _make_car_entry(car_name: String, blueprint: CarBlueprint) -> Dictionary:
	var car_id := "%s_%s" % [car_name, str(Time.get_ticks_msec())]
	var blueprint_data := blueprint.to_dict()
	return {
		"id": car_id,
		"name": car_name,
		"blueprint": blueprint_data,
		"slots": {}  # slot_name -> [part_id,...] currently installed
	}

func _find_car(car_id: String) -> Dictionary:
	for car in profile["garage"]["cars"]:
		if car.get("id", "") == car_id:
			return car
	return {}

func _consume_parts(part_ids: Array) -> bool:
	for pid in part_ids:
		if get_available_parts(pid) <= 0:
			return false
	for pid in part_ids:
		remove_spare_part(pid, 1)
	return true

func _validate_inventory() -> void:
	var spare_parts : Dictionary = profile["inventory"]["spare_parts"]
	for part_id in spare_parts.keys():
		if not _is_known_part(part_id):
			push_warning("PlayerData: removing unknown part '%s' from inventory." % part_id)
			spare_parts.erase(part_id)

func _is_known_part(part_id: String) -> bool:
	return SparePartData.sparepart.has(part_id)

func _add_dummy_player_data() -> void:
	if not profile["inventory"]["spare_parts"].is_empty():
		return
	add_spare_part("motor_standard_kit", 2)
	add_spare_part("motor_hyper_dash_3", 1)
	add_spare_part("body_standard_kit", 1)
	add_spare_part("battery_lite", 1)
	add_spare_part("wheel_standard_kit", 4)
	add_spare_part("roller_standard_kit", 4)
