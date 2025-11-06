extends Resource
class_name TrackBlueprint

@export_group("Metadata")
@export var direction: String = "CW"
@export var lanes: int = 2
@export var lane_width: float = 0.085
@export var start_lane: int = 1
@export var laps_required: int = 3
@export var lap_lane_goal: String = "ALL"
@export var strict_finish_lane: bool = false
@export var divider_height: float = 0.05

@export_group("Layout")
@export var tokens: PackedStringArray = []

func to_meta() -> Dictionary:
	return {
		"direction": direction,
		"lanes": lanes,
		"lane_width": lane_width,
		"start_lane": start_lane,
		"laps_required": laps_required,
		"lap_lane_goal": lap_lane_goal,
		"strict_finish_lane": strict_finish_lane,
		"divider_height": divider_height,
	}

func to_tokens() -> Array[String]:
	var arr: Array[String] = []
	for token in tokens:
		arr.append(String(token))
	return arr
