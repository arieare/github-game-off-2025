extends RefCounted
class_name SimulationTrackContext

## Wraps access to TrackModel so SimulationController (and tests) can interact
## with a single object rather than juggling temporary structs everywhere.

var track_model: TrackModel = null
var _temp_signal: TrackModel.TrackSignal = TrackModel.TrackSignal.new()
var _temp_location: TrackModel.TrackLocation = TrackModel.TrackLocation.new()
var _temp_pose: Dictionary = {}

func set_track_model(model: TrackModel) -> void:
	track_model = model

func has_track() -> bool:
	return track_model != null and not track_model.is_empty()

func is_endless() -> bool:
	return track_model != null and track_model.is_endless()

func get_total_length() -> float:
	return track_model.get_total_length() if track_model != null else 0.0

func get_track_meta() -> Dictionary:
	return track_model.get_track_meta() if track_model != null else {}

func get_divider_height() -> float:
	return track_model.divider_height if track_model != null else 0.0

func locate(position_s: float, hint: int) -> TrackModel.TrackLocation:
	if track_model == null:
		return null
	return track_model.at(position_s, hint, _temp_location)

func sample_signal(position_s: float, hint: int) -> TrackModel.TrackSignal:
	if track_model == null:
		return null
	return track_model.sample_signal(position_s, hint, _temp_signal)

func get_segment_count() -> int:
	return track_model.get_segment_count() if track_model != null else 0

func get_segment(index: int) -> TrackModel.TrackSegment:
	if track_model == null:
		return null
	return track_model.get_segment(index)

func clamp_distance(distance_s: float) -> float:
	if track_model == null:
		return distance_s
	return track_model.clamp_distance(distance_s)

func pose_at(position_s: float, hint: int) -> Dictionary:
	if track_model == null:
		return {}
	return track_model.pose_at(position_s, hint, _temp_pose)
