extends RefCounted
class_name TrackCompiler

# Converts tokenized track descriptions into a TrackModel instance.

#const TrackModel := preload("res://modules/track/track_model.gd")
#const TrackBlueprint := preload("res://modules/track/track_blueprint.gd")

const DEFAULT_STRAIGHT_LEN := 1.0
const DEFAULT_CORNER_RADIUS := 1.2
const DEFAULT_CORNER_ANGLE_DEG := 45.0
const DEFAULT_BANK_DEG := 0.0
const DEFAULT_FRICTION := 1.0
const DEFAULT_RAISE_LEN := 0.5
const DEFAULT_RAISE_ANGLE_DEG := 6.0
const DEFAULT_SURFACE_DRAG := 1.0
const DEFAULT_LAT_FRICTION := 1.0
const DEFAULT_BUMP_HEIGHT := 0.05

func compile(meta: Dictionary, tokens: Array) -> TrackModel:
	# Defensive copy of meta so callers can reuse their dictionary.
	var meta_copy: Dictionary = meta.duplicate(true)
	var segments: Array[TrackModel.TrackSegment] = []
	var s_cursor: float = 0.0

	for token: Variant in tokens:
		if typeof(token) != TYPE_STRING:
			push_error("TrackCompiler: token must be String, got %s" % type_string(typeof(token)))
			continue

		var raw_data: Dictionary = _make_segment_data(String(token).strip_edges())
		if raw_data.is_empty():
			push_error("TrackCompiler: unable to parse token '%s'." % token)
			continue

		var data_dict: Dictionary = raw_data
		data_dict["s_start"] = s_cursor
		if not data_dict.has("s_end"):
			var length: float = float(data_dict.get("length", 0.0))
			data_dict["s_end"] = s_cursor + max(length, 0.0)
		elif not data_dict.has("length"):
			data_dict["length"] = max(float(data_dict["s_end"]) - s_cursor, 0.0)

		var segment: TrackModel.TrackSegment = TrackModel.TrackSegment.new()
		segment.configure(data_dict)
		segment.s_start = s_cursor
		segment.s_end = float(data_dict["s_end"])
		segment.length = max(segment.s_end - segment.s_start, 0.0)
		s_cursor = segment.s_end
		segments.append(segment)

	return TrackModel.new(meta_copy, segments)

func compile_blueprint(bp: TrackBlueprint) -> TrackModel:
	if bp == null:
		push_error("TrackCompiler: Provided blueprint is null.")
		return TrackModel.new({}, [])
	var meta := bp.to_meta()
	var tokens := bp.to_tokens()
	return compile(meta, tokens)

func load_blueprint(path: String) -> TrackBlueprint:
	if not ResourceLoader.exists(path):
		push_warning("TrackCompiler: Blueprint path '%s' not found." % path)
		return null
	var bp: Resource = ResourceLoader.load(path)
	if bp is TrackBlueprint:
		return bp
	push_warning("TrackCompiler: Resource at '%s' is not a TrackBlueprint." % path)
	return null

func debug_print_track(path: String = "res://modules/track/assets/debug_loop.tres") -> void:
	var bp := load_blueprint(path)
	if bp == null:
		push_warning("TrackCompiler: Cannot debug-print track; blueprint missing.")
		return
	var model: TrackModel = compile_blueprint(bp)
	for seg: TrackModel.TrackSegment in model.get_segments():
		var grade_deg: float = rad_to_deg(seg.grade)
		var bank_deg: float = rad_to_deg(seg.bank)
		var surf_drag: float = DEFAULT_SURFACE_DRAG
		if seg.metadata.has("surface_drag"):
			surf_drag = float(seg.metadata.surface_drag)
		elif seg.has("surface_drag"):
			surf_drag = float(seg.surface_drag)
		print("%02d | %-8s | s:[%.3f, %.3f] len=%.3f | kappa=%.4f | grade=%.2f° | bank=%.2f° | mu=%.2f | mL=%.2f" % [
			seg.index,
			str(seg.type),
			seg.s_start,
			seg.s_end,
			seg.length,
			seg.curvature,
			grade_deg,
			bank_deg,
			seg.friction,
			surf_drag,
		])

func _make_segment_data(token: String) -> Dictionary:
	if token.is_empty():
		return {}

	var parts: PackedStringArray = token.split(":")
	var tag: String = parts[0]

	match tag:
		"ST":
			return {
				"type": "START",
				"length": 0.0,
				"curvature": 0.0,
				"grade": 0.0,
				"bank": 0.0,
				"friction": DEFAULT_FRICTION,
				"surface_drag": DEFAULT_SURFACE_DRAG,
			}
		"FN":
			return {
				"type": "FINISH",
				"length": 0.0,
				"curvature": 0.0,
				"grade": 0.0,
				"bank": 0.0,
				"friction": DEFAULT_FRICTION,
				"surface_drag": DEFAULT_SURFACE_DRAG,
			}
		"S":
			return _build_straight(parts)
		"CL", "CR":
			return _build_corner(tag, parts)
		"R":
			return _build_raiser(parts)
		"BP":
			return _build_bump(parts)
		"LS":
			if parts.size() > 1:
				return _build_lane_switch("LS" + parts[1])
			return _build_lane_switch(tag)
		_:
			if tag.begins_with("LS"):
				return _build_lane_switch(tag)

	push_error("TrackCompiler: unrecognized token '%s'." % token)
	return {}

func _build_straight(parts: PackedStringArray) -> Dictionary:
	var length: float = DEFAULT_STRAIGHT_LEN
	var friction: float = DEFAULT_FRICTION
	var lateral_friction: float = DEFAULT_LAT_FRICTION
	var surface_drag: float = DEFAULT_SURFACE_DRAG
	if parts.size() > 1 and not parts[1].is_empty():
		for chunk: String in parts[1].split(",", false):
			if chunk.is_empty():
				continue
			if chunk.begins_with("mu"):
				friction = max(float(chunk.substr(2)), 0.0)
			elif chunk.begins_with("mul"):
				lateral_friction = max(float(chunk.substr(3)), 0.0)
			elif chunk.begins_with("mL"):
				surface_drag = max(float(chunk.substr(2)), 0.1)
			else:
				length = max(float(chunk), 0.0)

	if lateral_friction == DEFAULT_LAT_FRICTION:
		lateral_friction = friction

	return {
		"type": "STRAIGHT",
		"length": length,
		"curvature": 0.0,
		"grade": 0.0,
		"bank": 0.0,
		"friction": friction,
		"lateral_friction": lateral_friction,
		"surface_drag": surface_drag,
		"metadata": {
			"mu_lat": lateral_friction,
		},
	}

func _build_corner(tag: String, parts: PackedStringArray) -> Dictionary:
	var radius: float = DEFAULT_CORNER_RADIUS
	var bank_deg: float = DEFAULT_BANK_DEG
	var angle_deg: float = DEFAULT_CORNER_ANGLE_DEG
	var friction: float = DEFAULT_FRICTION
	var lateral_friction: float = DEFAULT_LAT_FRICTION
	var surface_drag: float = DEFAULT_SURFACE_DRAG

	if parts.size() > 1:
		for chunk: String in parts[1].split(",", false):
			if chunk.is_empty():
				continue
			if chunk.begins_with("r"):
				radius = max(float(chunk.substr(1)), 0.001)
			elif chunk.begins_with("b"):
				bank_deg = float(chunk.substr(1))
			elif chunk.begins_with("a"):
				angle_deg = max(float(chunk.substr(1)), 1e-3)
			elif chunk.begins_with("mu"):
				friction = max(float(chunk.substr(2)), 0.0)
			elif chunk.begins_with("mul"):
				lateral_friction = max(float(chunk.substr(3)), 0.0)
			elif chunk.begins_with("mL"):
				surface_drag = max(float(chunk.substr(2)), 0.1)

	if parts.size() > 2 and not parts[2].is_empty():
		angle_deg = max(float(parts[2]), 1e-3)

	var angle_rad: float = deg_to_rad(angle_deg)
	var curvature: float = 0.0
	var length: float = radius * angle_rad
	if radius > 0.0:
		curvature = 1.0 / radius
	if tag == "CR":
		curvature *= -1.0
	var type_name: String = "CORNER_RIGHT"
	if tag == "CL":
		type_name = "CORNER_LEFT"
	if lateral_friction == DEFAULT_LAT_FRICTION:
		lateral_friction = friction

	return {
		"type": type_name,
		"length": length,
		"curvature": curvature,
		"grade": 0.0,
		"bank": deg_to_rad(bank_deg),
		"friction": friction,
		"lateral_friction": lateral_friction,
		"surface_drag": surface_drag,
		"metadata": {
			"radius": radius,
			"angle_deg": angle_deg,
			"mu_lat": lateral_friction,
		},
	}

func _build_raiser(parts: PackedStringArray) -> Dictionary:
	var angle_deg: float = DEFAULT_RAISE_ANGLE_DEG
	var length: float = DEFAULT_RAISE_LEN
	var lateral_friction: float = DEFAULT_LAT_FRICTION
	if parts.size() > 1 and not parts[1].is_empty():
		angle_deg = float(parts[1])
	if parts.size() > 2 and not parts[2].is_empty():
		length = max(float(parts[2]), 0.0)
	if parts.size() > 3 and not parts[3].is_empty():
		for chunk: String in parts[3].split(",", false):
			if chunk.is_empty():
				continue
			if chunk.begins_with("mul"):
				lateral_friction = max(float(chunk.substr(3)), 0.0)

	var type_name: String = "RAISER_DOWN"
	if angle_deg >= 0.0:
		type_name = "RAISER_UP"

	return {
		"type": type_name,
		"length": length,
		"curvature": 0.0,
		"grade": deg_to_rad(angle_deg),
		"bank": 0.0,
		"friction": DEFAULT_FRICTION,
		"lateral_friction": lateral_friction,
		"surface_drag": DEFAULT_SURFACE_DRAG,
		"metadata": {
			"angle_deg": angle_deg,
			"mu_lat": lateral_friction,
		},
	}

func _build_bump(parts: PackedStringArray) -> Dictionary:
	var length: float = DEFAULT_STRAIGHT_LEN * 0.5
	var height: float = DEFAULT_BUMP_HEIGHT
	var friction: float = DEFAULT_FRICTION
	var lateral_friction: float = DEFAULT_LAT_FRICTION
	if parts.size() > 1 and not parts[1].is_empty():
		length = max(float(parts[1]), 0.0)
	if parts.size() > 2 and not parts[2].is_empty():
		height = max(float(parts[2]), 0.0)
	if parts.size() > 3 and not parts[3].is_empty():
		for chunk: String in parts[3].split(",", false):
			if chunk.is_empty():
				continue
			if chunk.begins_with("mu"):
				friction = max(float(chunk.substr(2)), 0.0)
			elif chunk.begins_with("mul"):
				lateral_friction = max(float(chunk.substr(3)), 0.0)

	if lateral_friction == DEFAULT_LAT_FRICTION:
		lateral_friction = friction

	return {
		"type": "BUMP",
		"length": length,
		"curvature": 0.0,
		"grade": 0.0,
		"bank": 0.0,
		"friction": friction,
		"lateral_friction": lateral_friction,
		"surface_drag": DEFAULT_SURFACE_DRAG,
		"metadata": {
			"bump_height": height,
			"mu_lat": lateral_friction,
		},
	}

func _build_lane_switch(tag: String) -> Dictionary:
	var from_lane: int = -1
	var to_lane: int = -1
	var suffix: String = tag.substr(2).strip_edges()
	if suffix.length() >= 1:
		var from_str: String = suffix.substr(0, 1)
		if from_str.is_valid_int():
			from_lane = int(from_str)
	if suffix.length() >= 2:
		var to_str: String = suffix.substr(1)
		if to_str.is_valid_int():
			to_lane = int(to_str)

	return {
		"type": "LANE_SWITCH",
		"length": 0.0,
		"curvature": 0.0,
		"grade": 0.0,
		"bank": 0.0,
		"friction": DEFAULT_FRICTION,
		"surface_drag": DEFAULT_SURFACE_DRAG,
		"lane_from": from_lane,
		"lane_to": to_lane,
	}
