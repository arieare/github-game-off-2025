extends Node2D
class_name TrackRenderer

## Renders a compiled track as a 2D polyline for debugging purposes.

@export var px_per_m: float = 100.0
@export var origin: Vector2 = Vector2.ZERO
@export var sample_step: float = 0.1
@export var line_color: Color = Color(0.2, 0.8, 1.0)
@export var line_width: float = 4.0

#== markers ==#
@export var show_markers: bool = true
@export var marker_radius: float = 6.0
@export var marker_color: Color = Color(1.0, 0.4, 0.2)
@export var show_marker_labels: bool = true
@export var car_color: Color = Color(1.0, 0.8, 0.2)
@export var car_length: float = 22.0
@export var car_width: float = 12.0

#== labels ==#
@export var segment_label_color: Color = Color.BLACK
@export var lane_color: Color = Color(0.6, 0.6, 0.6)
@export var active_lane_color: Color = Color(1.0, 0.3, 0.3)
@export var start_lane_color: Color = Color(0.3, 0.8, 0.3)
@export var lane_line_width: float = 2.0
@export var lane_label_color: Color = Color(0.1, 0.1, 0.1)
@export var show_lane_labels: bool = true

@export var car_palette: Array[Color] = [
	Color(1.0, 0.8, 0.2),
	Color(0.2, 0.7, 1.0),
	Color(1.0, 0.4, 0.4),
	Color(0.6, 1.0, 0.4),
	Color(0.8, 0.5, 1.0)
]

var track_model: TrackModel = null
var _segments: Array[TrackModel.TrackSegment] = []
var _polyline: PackedVector2Array = PackedVector2Array()
var _segment_markers: Array[Vector2] = []
var _segment_labels: Array[String] = []
var _segment_start_positions: Array[Vector2] = []
var _segment_start_headings: Array[float] = []
var _car_visuals: Dictionary = {}  # car_id -> {position, heading, lane, color}
var _car_draw_order: Array = []
var _temp_location: TrackModel.TrackLocation = TrackModel.TrackLocation.new()
var _lane_polylines: Array[PackedVector2Array] = []
var _lane_label_positions: Array[Vector2] = []
var _lane_offsets: Array[float] = []
var _lane_count: int = 1
var _start_lane: int = 1

func set_track_model(model: TrackModel) -> void:
	track_model = model
	if track_model == null:
		var empty_segments: Array[TrackModel.TrackSegment] = []
		_segments = empty_segments
	else:
		_segments = track_model.get_segments()
		_rebuild_polyline()
		_car_visuals.clear()
		_car_draw_order.clear()
	queue_redraw()

func clear() -> void:
	track_model = null
	var empty_segments: Array[TrackModel.TrackSegment] = []
	_segments = empty_segments
	_polyline = PackedVector2Array()
	var empty_markers: Array[Vector2] = []
	_segment_markers = empty_markers
	var empty_labels: Array[String] = []
	_segment_labels = empty_labels
	var empty_positions: Array[Vector2] = []
	var empty_headings: Array[float] = []
	_segment_start_positions = empty_positions
	_segment_start_headings = empty_headings
	_car_visuals.clear()
	_car_draw_order.clear()
	_lane_polylines = []
	_lane_label_positions = []
	_lane_offsets = []
	_lane_count = 1
	_start_lane = 1
	queue_redraw()

func set_segments(segments: Array[TrackModel.TrackSegment]) -> void:
	_segments = segments.duplicate() as Array[TrackModel.TrackSegment]
	_rebuild_polyline()
	_car_visuals.clear()
	_car_draw_order.clear()
	_lane_polylines = []
	_lane_label_positions = []
	queue_redraw()

func _ready() -> void:
	if not _polyline.is_empty():
		queue_redraw()

func _draw() -> void:
	if _polyline.size() < 2:
		return

	if _lane_polylines.size() > 0:
		var start_lane_index: int = clamp(_start_lane - 1, 0, _lane_polylines.size() - 1)
		var lane_highlights: Dictionary = _collect_lane_highlights()
		for lane_index in range(_lane_polylines.size()):
			var color_lane: Color = lane_color
			if lane_index == start_lane_index:
				color_lane = start_lane_color
			if lane_highlights.has(lane_index):
				color_lane = lane_highlights[lane_index]
			draw_polyline(_lane_polylines[lane_index], color_lane, lane_line_width, false)

	draw_polyline(_polyline, line_color, line_width, false)

	var font: Font = null
	var font_size: int = 16
	var default_theme: Theme = ThemeDB.get_default_theme()
	if default_theme != null:
		font = default_theme.get_default_font()
		font_size = default_theme.get_default_font_size()
	if font == null:
		font = ThemeDB.get_fallback_font()
		font_size = ThemeDB.get_fallback_font_size()

	for i in range(_segment_markers.size()):
		var point: Vector2 = _segment_markers[i]
		draw_circle(point, marker_radius, marker_color)
		if show_marker_labels and font != null and i < _segment_labels.size():
			var label: String = _segment_labels[i]
			var offset: Vector2 = Vector2(marker_radius + 4.0, -marker_radius - 2.0)
			draw_string(font, point + offset, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, segment_label_color)

	if show_lane_labels and font != null and _lane_label_positions.size() == _lane_polylines.size():
		var lane_highlights: Dictionary = _collect_lane_highlights()
		for lane_index in range(_lane_label_positions.size()):
			var label_pos: Vector2 = _lane_label_positions[lane_index]
			var text_color: Color = lane_label_color
			if lane_index == clamp(_start_lane - 1, 0, _lane_label_positions.size() - 1):
				text_color = start_lane_color
			if lane_highlights.has(lane_index):
				text_color = lane_highlights[lane_index]
			draw_string(font, label_pos + Vector2(-8.0, -8.0), "L%d" % (lane_index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, text_color)

	for car_id in _car_draw_order:
		if not _car_visuals.has(car_id):
			continue
		var data: Dictionary = _car_visuals[car_id]
		_draw_car(car_id, data)
		if font != null and data.has("position") and data.has("lane"):
			var label_pos: Vector2 = data["position"]
			draw_string(
				font,
				label_pos + Vector2(10.0, -12.0),
				"%s (L%d)" % [str(car_id), int(data["lane"])],
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				font_size,
				Color(data.get("color", car_color))
			)

func _rebuild_polyline() -> void:
	var marker_list: Array[Vector2] = []
	var label_list: Array[String] = []
	var start_positions: Array[Vector2] = []
	var start_headings: Array[float] = []
	var lane_label_positions: Array[Vector2] = []
	var lane_polys_mut: Array = []

	var lane_count: int = 1
	var lane_width_m: float = 0.08
	var start_lane: int = 1
	if track_model != null:
		var meta: Dictionary = track_model.get_track_meta()
		lane_count = max(1, int(meta.get("lanes", lane_count)))
		lane_width_m = float(meta.get("lane_width", lane_width_m))
		start_lane = int(meta.get("start_lane", start_lane))
	if lane_width_m <= 0.0:
		lane_width_m = 0.08
	var lane_offsets: Array[float] = []
	var half_span: float = (float(lane_count) - 1.0) * 0.5
	var lane_width_px: float = lane_width_m * px_per_m
	for i in range(lane_count):
		lane_offsets.append((float(i) - half_span) * lane_width_px)
		lane_polys_mut.append([])

	if _segments.is_empty():
		_polyline = PackedVector2Array()
		_segment_markers = marker_list
		_segment_labels = label_list
		_segment_start_positions = start_positions
		_segment_start_headings = start_headings
		_lane_polylines = []
		_lane_label_positions = []
		_lane_offsets = lane_offsets
		_lane_count = lane_count
		_start_lane = start_lane
		return

	var points: Array[Vector2] = []
	var position: Vector2 = origin
	var heading_angle: float = 0.0
	points.append(position)
	var initial_normal: Vector2 = Vector2.RIGHT.rotated(heading_angle + PI * 0.5)
	for i in range(lane_count):
		var lane_point: Vector2 = position + initial_normal * lane_offsets[i]
		(lane_polys_mut[i] as Array[Vector2]).append(lane_point)
		lane_label_positions.append(lane_point)

	for segment: TrackModel.TrackSegment in _segments:
		start_positions.append(position)
		start_headings.append(heading_angle)

		if segment.length <= 0.0:
			marker_list.append(position)
			label_list.append(str(segment.type))
			continue

		var remaining: float = segment.length
		var step_size: float = sample_step
		if step_size <= 0.0:
			step_size = 0.1
		var steps: int = int(ceil(remaining / step_size))
		if steps <= 0:
			steps = 1
		var ds: float = remaining / float(steps)

		for _i in range(steps):
			var delta_angle: float = segment.curvature * ds
			var mid_angle: float = heading_angle + delta_angle * 0.5
			var direction: Vector2 = Vector2.RIGHT.rotated(mid_angle)
			position += direction * (ds * px_per_m)
			points.append(position)
			heading_angle += delta_angle
			var tangent: Vector2 = Vector2.RIGHT.rotated(heading_angle)
			var normal_vec: Vector2 = tangent.rotated(PI * 0.5)
			for lane_index in range(lane_count):
				var lane_point_step: Vector2 = position + normal_vec * lane_offsets[lane_index]
				(lane_polys_mut[lane_index] as Array[Vector2]).append(lane_point_step)

		marker_list.append(position)
		label_list.append(str(segment.type))

	_polyline = PackedVector2Array(points)
	_segment_markers = marker_list
	_segment_labels = label_list
	_segment_start_positions = start_positions
	_segment_start_headings = start_headings
	var lane_polys_final: Array[PackedVector2Array] = []
	var lane_labels_final: Array[Vector2] = []
	for lane_index in range(lane_count):
		var lane_points_raw: Array = lane_polys_mut[lane_index]
		lane_polys_final.append(PackedVector2Array(lane_points_raw))
		var lane_label_point: Vector2 = lane_label_positions[lane_index] if lane_index < lane_label_positions.size() else origin
		if lane_points_raw.size() > 0:
			lane_label_point = lane_points_raw[0]
		lane_labels_final.append(lane_label_point)
	_lane_polylines = lane_polys_final
	_lane_label_positions = lane_labels_final
	_lane_offsets = lane_offsets
	_lane_count = lane_count
	_start_lane = max(1, start_lane)

func update_car_snapshot(snapshot: Dictionary) -> void:
	if snapshot == null:
		return
	var car_id: Variant = snapshot.get("car_id", "primary")
	if track_model == null or _segments.is_empty():
		_remove_car_visual(car_id)
		queue_redraw()
		return
	var distance: float = float(snapshot.get("s", 0.0))
	var lane: int = int(snapshot.get("lane", _start_lane))
	var location: TrackModel.TrackLocation = track_model.at(distance, -1, _temp_location)
	if location == null or location.segment == null:
		_remove_car_visual(car_id)
		queue_redraw()
		return
	var offset: float = clamp(distance - location.segment.s_start, 0.0, location.segment.length)
	var pose: Dictionary = _segment_pose(location.index, offset)
	var pose_position: Vector2 = pose.get("position", Vector2.ZERO)
	var pose_heading: float = float(pose.get("heading", 0.0))
	var lane_index: int = clamp(lane - 1, 0, max(0, _lane_offsets.size() - 1))
	var lane_offset: float = 0.0
	if lane_index >= 0 and lane_index < _lane_offsets.size():
		lane_offset = _lane_offsets[lane_index]
	var lane_normal: Vector2 = Vector2.RIGHT.rotated(pose_heading + PI * 0.5)
	var in_air: bool = bool(snapshot.get("in_air", false))
	var color: Color = _color_for_car(car_id)
	var altitude: float = float(snapshot.get("altitude", 0.0))
	var heading_draw: float = pose_heading
	var world_position: Vector2 = pose_position + lane_normal * lane_offset
	if in_air:
		var air_origin: Variant = snapshot.get("airborne_origin", null)
		if air_origin is Vector2:
			var air_vec: Vector2 = air_origin
			world_position = origin + air_vec * px_per_m
			heading_draw = float(snapshot.get("airborne_heading", heading_draw))
	_car_visuals[car_id] = {
		"position": world_position,
		"heading": heading_draw,
		"lane": lane,
		"color": color,
		"in_air": in_air,
		"altitude": altitude,
	}
	if not _car_draw_order.has(car_id):
		_car_draw_order.append(car_id)
	queue_redraw()

func update_car_snapshots(snapshots: Dictionary) -> void:
	if snapshots == null:
		return
	for car_id in snapshots.keys():
		var snapshot: Dictionary = snapshots[car_id]
		if snapshot is Dictionary:
			snapshot["car_id"] = car_id
			update_car_snapshot(snapshot)

func remove_car(car_id: Variant) -> void:
	_remove_car_visual(car_id)
	queue_redraw()

func _remove_car_visual(car_id: Variant) -> void:
	if _car_visuals.has(car_id):
		_car_visuals.erase(car_id)
	if _car_draw_order.has(car_id):
		_car_draw_order.erase(car_id)

func _collect_lane_highlights() -> Dictionary:
	var highlights: Dictionary = {}
	if _car_draw_order.is_empty():
		return highlights
	for car_id in _car_draw_order:
		if not _car_visuals.has(car_id):
			continue
		var data: Dictionary = _car_visuals[car_id]
		if not data.has("lane"):
			continue
		var lane_idx: int = clamp(int(data["lane"]) - 1, 0, max(0, _lane_count - 1))
		if lane_idx < 0:
			continue
		highlights[lane_idx] = data.get("color", car_color)
	return highlights

func _color_for_car(car_id: Variant) -> Color:
	if car_palette.is_empty():
		return car_color
	var hash_value: int = String(str(car_id)).hash()
	var idx: int = abs(hash_value) % car_palette.size()
	return car_palette[idx]


func _segment_pose(index: int, offset: float) -> Dictionary:
	if index < 0 or index >= _segments.size():
		return {
			"position": Vector2.ZERO,
			"heading": 0.0,
		}

	var segment: TrackModel.TrackSegment = _segments[index]
	var start_position: Vector2 = _segment_start_positions[index]
	var start_heading: float = _segment_start_headings[index]

	if segment.length <= 0.0:
		return {
			"position": start_position,
			"heading": start_heading,
		}

	var offset_m: float = clamp(offset, 0.0, segment.length)
	var heading: float = start_heading
	var position: Vector2 = start_position
	var curvature: float = segment.curvature

	if absf(curvature) < 1e-6:
		var direction: Vector2 = Vector2.RIGHT.rotated(start_heading)
		position = start_position + direction * (offset_m * px_per_m)
	else:
		var radius_m: float = 1.0 / curvature
		var radius_px: float = radius_m * px_per_m
		var tangent: Vector2 = Vector2.RIGHT.rotated(start_heading)
		var normal_left: Vector2 = tangent.rotated(PI / 2.0)
		var center: Vector2 = start_position + normal_left * radius_px
		var theta: float = curvature * offset_m
		var start_vector: Vector2 = start_position - center
		var rotated: Vector2 = start_vector.rotated(theta)
		position = center + rotated
		heading = start_heading + theta

	heading = wrapf(heading, -PI, PI)
	return {
		"position": position,
		"heading": heading,
	}

func _draw_car(car_id: Variant, data: Dictionary) -> void:
	if data == null or not data.has("position"):
		return
	var position: Vector2 = data.get("position", Vector2.ZERO)
	var heading: float = float(data.get("heading", 0.0))
	var color: Color = data.get("color", car_color)
	var in_air: bool = bool(data.get("in_air", false))
	if in_air:
		color = color.lerp(Color(1.0, 1.0, 1.0, color.a), 0.35)
	var direction: Vector2 = Vector2.RIGHT.rotated(heading).normalized()
	var forward: Vector2 = direction * (car_length * 0.5)
	var base_center: Vector2 = position - forward
	var normal: Vector2 = direction.rotated(PI / 2.0) * (car_width * 0.5)
	var nose: Vector2 = position + forward
	var left: Vector2 = base_center + normal
	var right: Vector2 = base_center - normal
	var points: PackedVector2Array = PackedVector2Array([nose, left, right])
	draw_colored_polygon(points, color)
