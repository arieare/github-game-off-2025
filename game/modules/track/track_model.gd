extends Resource
class_name TrackModel

## Encapsulates preprocessed track geometry and metadata for simulation queries.

const EPSILON := 1e-9

class TrackSignal:
	extends RefCounted

	var curvature: float = 0.0
	var grade: float = 0.0
	var bank: float = 0.0
	var friction: float = 1.0
	var lateral_friction: float = 1.0
	var surface_drag: float = 1.0

	func reset() -> void:
		curvature = 0.0
		grade = 0.0
		bank = 0.0
		friction = 1.0
		lateral_friction = 1.0
		surface_drag = 1.0


class TrackSegment:
	extends RefCounted

	var type: StringName = &"UNKNOWN"
	var s_start: float = 0.0
	var s_end: float = 0.0
	var length: float = 0.0
	var curvature: float = 0.0
	var grade: float = 0.0
	var bank: float = 0.0
	var friction: float = 1.0
	var lateral_friction: float = 1.0
	var blend_in: float = 0.0
	var blend_out: float = 0.0
	var lane_from: int = -1
	var lane_to: int = -1
	var metadata: Dictionary = {}
	var index: int = -1

	func _init(data: Dictionary = {}) -> void:
		if data.is_empty():
			return
		configure(data)

	func configure(data: Dictionary) -> void:
		type = StringName(data.get("type", "UNKNOWN"))
		s_start = float(data.get("s_start", 0.0))
		if data.has("s_end"):
			s_end = float(data.get("s_end"))
			length = max(0.0, s_end - s_start)
		else:
			length = max(0.0, float(data.get("length", 0.0)))
			s_end = s_start + length
		curvature = float(data.get("curvature", 0.0))
		grade = float(data.get("grade", 0.0))
		bank = float(data.get("bank", 0.0))
		friction = float(data.get("friction", 1.0))
		lateral_friction = float(data.get("lateral_friction", friction))
		if data.has("mu_lat"):
			lateral_friction = float(data.get("mu_lat"))
		elif data.has("metadata"):
			var meta_data: Variant = data.get("metadata")
			if typeof(meta_data) == TYPE_DICTIONARY:
				var meta_dict: Dictionary = meta_data
				if meta_dict.has("mu_lat"):
					lateral_friction = float(meta_dict["mu_lat"])
		blend_in = max(0.0, float(data.get("blend_in", 0.0)))
		blend_out = max(0.0, float(data.get("blend_out", 0.0)))
		lane_from = int(data.get("lane_from", -1))
		lane_to = int(data.get("lane_to", -1))
		metadata = data.get("metadata", {}).duplicate(true)
		if data.has("surface_drag"):
			var _sd: float = float(data["surface_drag"]) 
			metadata["surface_drag"] = _sd

	func contains(s: float, inclusive_end: bool = false) -> bool:
		if s < s_start - EPSILON:
			return false
		if inclusive_end:
			return s <= s_end + EPSILON
		if length <= EPSILON:
			return absf(s - s_start) <= EPSILON
		return s <= s_end + EPSILON

	func normalized_position(s: float) -> float:
		if length <= EPSILON:
			return 0.0
		return clamp((s - s_start) / length, 0.0, 1.0)

	func get_signal(u: float, out_signal: TrackSignal = null) -> TrackSignal:
		var result: TrackSignal = out_signal if out_signal != null else TrackSignal.new()
		result.curvature = curvature
		result.grade = grade
		result.bank = bank
		result.friction = friction
		result.lateral_friction = lateral_friction
		if metadata.has("surface_drag"):
			result.surface_drag = float(metadata["surface_drag"]) 
		else:
			result.surface_drag = 1.0
		return result


class TrackLocation:
	extends RefCounted

	var segment: TrackSegment = null
	var index: int = -1
	var s: float = 0.0
	var u: float = 0.0

	func set_data(seg: TrackSegment, index_value: int, s_value: float, u_value: float) -> TrackLocation:
		segment = seg
		index = index_value
		s = s_value
		u = u_value
		return self

	func reset() -> void:
		segment = null
		index = -1
		s = 0.0
		u = 0.0


var _meta: Dictionary = {}
var _segments: Array[TrackSegment] = []
var _segment_starts: PackedFloat32Array = PackedFloat32Array()
var _segment_ends: PackedFloat32Array = PackedFloat32Array()
var _segment_start_positions: Array[Vector2] = []
var _segment_start_headings: Array[float] = []
var _length: float = 0.0
var _is_endless: bool = false
var divider_height: float = 0.05

func _init(meta: Dictionary = {}, segments: Array[TrackSegment] = []) -> void:
	_meta = meta.duplicate(true)
	_apply_meta_flags()
	if not segments.is_empty():
		set_segments(segments)

func get_track_meta() -> Dictionary:
	return _meta

func set_track_meta(meta: Dictionary) -> void:
	_meta = meta.duplicate(true)
	_apply_meta_flags()

func is_empty() -> bool:
	return _segments.is_empty()

func get_total_length() -> float:
	return _length

func get_segment_count() -> int:
	return _segments.size()

func get_segment(index: int) -> TrackSegment:
	if index < 0 or index >= _segments.size():
		push_error("TrackModel: segment index out of range: %d" % index)
		return null
	return _segments[index]

func get_segments() -> Array[TrackSegment]:
	return _segments

func set_segments(new_segments: Array[TrackSegment]) -> void:
	_segments.clear()
	_segment_starts = PackedFloat32Array()
	_segment_ends = PackedFloat32Array()
	_segment_start_positions = []
	_segment_start_headings = []
	_length = 0.0

	if new_segments.is_empty():
		return

	var sorted: Array[TrackSegment] = new_segments.duplicate() as Array[TrackSegment]
	sorted.sort_custom(func(a: TrackSegment, b: TrackSegment) -> bool:
		return a.s_start < b.s_start
	)

	var starts: PackedFloat32Array = PackedFloat32Array()
	var ends: PackedFloat32Array = PackedFloat32Array()
	starts.resize(sorted.size())
	ends.resize(sorted.size())
	var start_positions: Array[Vector2] = []
	var start_headings: Array[float] = []
	start_positions.resize(sorted.size())
	start_headings.resize(sorted.size())

	var previous_end: float = 0.0
	var has_previous: bool = false
	var position_accum: Vector2 = Vector2.ZERO
	var heading_accum: float = 0.0

	for i in range(sorted.size()):
		var segment: TrackSegment = sorted[i]
		if segment == null:
			push_error("TrackModel: null segment at index %d" % i)
			continue

		if segment.s_end < segment.s_start - EPSILON:
			push_error("TrackModel: segment '%s' has negative length." % segment.type)
			segment.length = 0.0
			segment.s_end = segment.s_start
		else:
			segment.length = max(segment.s_end - segment.s_start, 0.0)

		if has_previous:
			if segment.s_start < previous_end - EPSILON:
				push_error("TrackModel: segment '%s' starts before previous segment ends." % segment.type)
			elif segment.s_start > previous_end + EPSILON:
				push_warning("TrackModel: gap detected between segments at s=%.6f." % previous_end)

		segment.index = i
		_segments.append(segment)
		starts[i] = segment.s_start
		ends[i] = segment.s_end
		start_positions[i] = position_accum
		start_headings[i] = heading_accum
		if segment.length > 0.0:
			var curvature: float = segment.curvature
			var length: float = segment.length
			if abs(curvature) <= EPSILON:
				var direction: Vector2 = Vector2.RIGHT.rotated(heading_accum)
				position_accum += direction * length
				heading_accum += curvature * length
			else:
				var radius: float = 1.0 / curvature
				var delta_angle: float = curvature * length
				var normal: Vector2 = Vector2.RIGHT.rotated(heading_accum + PI * 0.5)
				var center: Vector2 = position_accum + normal * radius
				heading_accum += delta_angle
				var end_normal: Vector2 = Vector2.RIGHT.rotated(heading_accum + PI * 0.5)
				position_accum = center - end_normal * radius

		previous_end = segment.s_end
		has_previous = true

	_length = previous_end
	_segment_starts = starts
	_segment_ends = ends
	_segment_start_positions = start_positions
	_segment_start_headings = start_headings

func clamp_distance(s: float) -> float:
	if _segments.is_empty():
		return 0.0
	if _is_endless:
		if _length <= 0.0:
			return 0.0
		var wrapped: float = fposmod(s, _length)
		if is_equal_approx(wrapped, _length):
			return 0.0
		return wrapped
	if s <= 0.0:
		return 0.0
	if s >= _length:
		return _length
	return s

func at(s: float, hint_index: int = -1, out_location: TrackLocation = null) -> TrackLocation:
	if _segments.is_empty():
		return null
	var clamped: float = clamp_distance(s)
	var index: int = _find_segment_index(clamped, hint_index)
	if index < 0:
		return null
	var segment: TrackSegment = _segments[index]
	var u: float = segment.normalized_position(clamped)
	var result: TrackLocation = out_location if out_location != null else TrackLocation.new()
	return result.set_data(segment, index, clamped, u)

func sample_signal(s: float, hint_index: int = -1, out_signal: TrackSignal = null) -> TrackSignal:
	if _segments.is_empty():
		return null
	var location: TrackLocation = at(s, hint_index, null)
	if location == null or location.segment == null:
		return null
	return location.segment.get_signal(location.u, out_signal)

func _find_segment_index(s: float, hint_index: int) -> int:
	var count: int = _segments.size()
	if count == 0:
		return -1

	if hint_index >= 0 and hint_index < count:
		var hint_segment: TrackSegment = _segments[hint_index]
		if _segment_accepts_s(hint_segment, hint_index, s):
			return hint_index
		if hint_index + 1 < count and _segment_accepts_s(_segments[hint_index + 1], hint_index + 1, s):
			return hint_index + 1
		if hint_index > 0 and _segment_accepts_s(_segments[hint_index - 1], hint_index - 1, s):
			return hint_index - 1

	var low: int = 0
	var high: int = count - 1
	while low <= high:
		var mid: int = (low + high) >> 1
		var start_s: float = _segment_starts[mid]
		var end_s: float = _segment_ends[mid]
		var inclusive: bool = mid == count - 1

		if s < start_s - EPSILON and not is_equal_approx(s, start_s):
			high = mid - 1
			continue

		if s > end_s + EPSILON and not is_equal_approx(s, end_s):
			low = mid + 1
			continue

		if (s < end_s - EPSILON) or inclusive or is_equal_approx(s, end_s):
			return mid

		low = mid + 1

	return clamp(low, 0, count - 1)

func _segment_accepts_s(segment: TrackSegment, index: int, s: float) -> bool:
	if segment == null:
		return false
	if s < segment.s_start - EPSILON:
		return false
	var is_last: bool = index == _segments.size() - 1
	if is_last:
		return s <= segment.s_end + EPSILON
	return s < segment.s_end - EPSILON or is_equal_approx(s, segment.s_end)

func is_endless() -> bool:
	return _is_endless

func set_endless(enabled: bool) -> void:
	_is_endless = enabled
	_meta["endless"] = enabled

func _apply_meta_flags() -> void:
	_is_endless = bool(_meta.get("endless", _is_endless))
	if _meta.has("divider_height"):
		divider_height = float(_meta["divider_height"])

func pose_at(s: float, hint_index: int = -1, out_pose: Dictionary = {}) -> Dictionary:
	if _segments.is_empty():
		return {}
	var loc: TrackLocation = at(s, hint_index, null)
	if loc == null or loc.segment == null:
		return {}
	var offset: float = clamp(s - loc.segment.s_start, 0.0, loc.segment.length)
	return _pose_within_segment(loc.segment, offset, loc.index, out_pose)

func _pose_within_segment(segment: TrackSegment, offset: float, index: int, out_pose: Dictionary = {}) -> Dictionary:
	if segment == null:
		return {}
	var position: Vector2 = Vector2.ZERO
	var heading: float = 0.0
	if index >= 0 and index < _segment_start_positions.size():
		position = _segment_start_positions[index]
	if index >= 0 and index < _segment_start_headings.size():
		heading = _segment_start_headings[index]
	if offset <= 0.0:
		return {
			"position": position,
			"heading": heading,
		}
	var curvature: float = segment.curvature
	if abs(curvature) <= EPSILON:
		var direction: Vector2 = Vector2.RIGHT.rotated(heading)
		position += direction * offset
		heading += curvature * offset
	else:
		var radius: float = 1.0 / curvature
		var delta_angle: float = curvature * offset
		var normal_start: Vector2 = Vector2.RIGHT.rotated(heading + PI * 0.5)
		var center: Vector2 = position + normal_start * radius
		heading += delta_angle
		var normal_end: Vector2 = Vector2.RIGHT.rotated(heading + PI * 0.5)
		position = center - normal_end * radius
	heading = wrapf(heading, -PI, PI)
	if out_pose == null:
		return {
			"position": position,
			"heading": heading,
		}
	out_pose.clear()
	out_pose["position"] = position
	out_pose["heading"] = heading
	return out_pose
