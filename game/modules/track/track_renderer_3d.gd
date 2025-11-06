extends Node3D
class_name TrackRenderer3D

@export var m_to_units: float = 1.0   # keep 1.0 if your track lengths are already in meters
@export var sample_step: float = 0.1  # meters per sample
@export var lane_width_m: float = 0.08
@export var start_lane: int = 1
@export var show_lanes: bool = true
@export var draw_per_lane: bool = true
@export var lane_seam_m: float = 0.002  # small gap to avoid z-fighting between lanes
@export var divider_width_m: float = 0.006
var lane_csgs: Array[CSGPolygon3D] = []
var divider_csgs: Array[CSGPolygon3D] = []
var _compiler: TrackCompiler = TrackCompiler.new()
@export var track: TrackBlueprint
@onready var car_mesh = load("res://modules/car/car_models/car_gear.tscn").instantiate()

var track_model: TrackModel
var path: Path3D
var curve := Curve3D.new()

# car_id -> nodes
var followers := {}
var lane_offsets_cache: Array[float] = []
var lane_count := 1

func _ready() -> void:
	if path == null:
		path = Path3D.new()
		add_child(path)
		path.curve = curve
	set_track_model(track)

func set_track_model(blueprint: TrackBlueprint) -> void:
	var _track = _compiler.compile_blueprint(blueprint)	
	track_model = _track
	_build_curve_from_model()
	_rebuild_lane_offsets()
	_ensure_track_mesh(lane_count * lane_width_m + 0.06, 0.02) # width = lanes + margins	
	if draw_per_lane:
		_ensure_lane_meshes()
		_ensure_lane_dividers()
	_refresh_followers_transforms()

func clear() -> void:
	curve.clear_points()
	for c in lane_csgs:
		c.queue_free()
	lane_csgs.clear()
	for d in divider_csgs:
		d.queue_free()
	divider_csgs.clear()
	if track_csg:
		track_csg.queue_free()
		track_csg = null
	for f in followers.values():
		f.queue_free()
	followers.clear()

var track_csg: CSGPolygon3D

func _ensure_track_mesh(width_m := 0.115, thickness_m := 0.05) -> void:
	if track_csg == null:
		track_csg = CSGPolygon3D.new()
		add_child(track_csg)

	# 1) Extrude along the Path3D
	track_csg.mode = CSGPolygon3D.MODE_PATH
	track_csg.path_node = path.get_path()  # << important: a NodePath to your Path3D
	track_csg.path_interval = max(sample_step * m_to_units, 0.02)  # sampling along the curve
	track_csg.path_joined = true  # close the loop if your track is closed
	track_csg.path_rotation = CSGPolygon3D.PATH_ROTATION_PATH  # orient polygon with tangent

	# 2) Cross-section polygon (XY plane). X = width, Y = thickness
	var w := width_m * m_to_units
	var t := thickness_m * m_to_units
	# Counter-clockwise rectangle; flip order if it renders “inside-out”
	track_csg.polygon = PackedVector2Array([
		Vector2(-w * 0.5, 0.0),
		Vector2( w * 0.5, 0.0),
		Vector2( w * 0.5, -t),
		Vector2(-w * 0.5, -t),
	])

	# 3) Keep it fast & visible
	track_csg.use_collision = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.341)
	track_csg.material = mat
	track_csg.flip_faces = true
	#track_csg.position.z += 0.05

func _ensure_lane_meshes() -> void:
	# Ensure we have one CSG band per lane following the Path3D
	# Trim extras
	while lane_csgs.size() > lane_count:
		var c :CSGPolygon3D= lane_csgs.pop_back()
		c.queue_free()
	# Grow to need
	while lane_csgs.size() < lane_count:
		var c :CSGPolygon3D= CSGPolygon3D.new()
		add_child(c)
		lane_csgs.append(c)

	for i in lane_csgs.size():
		var c := lane_csgs[i]
		c.mode = CSGPolygon3D.MODE_PATH
		c.path_node = path.get_path()
		c.path_interval = max(sample_step * m_to_units, 0.02)
		c.path_joined = true
		c.path_rotation = CSGPolygon3D.PATH_ROTATION_PATH

		# Each lane ribbon: width ~ lane_width minus seam; small thickness above base
		var w :float= max(0.0, (lane_width_m - lane_seam_m)) * m_to_units
		var t := 0.015 * m_to_units
		var off := lane_offsets_cache[i]  # lateral offset along X in cross-section

		c.polygon = PackedVector2Array([
			Vector2(off - w * 0.5, 0.0),
			Vector2(off + w * 0.5, 0.0),
			Vector2(off + w * 0.5, -t),
			Vector2(off - w * 0.5, -t),
		])

		c.use_collision = false
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		# Alternate subtle tones per lane
		if (i % 2) == 0:
			mat.albedo_color = Color(0.34, 0.34, 0.34, 1.0)
		else:
			mat.albedo_color = Color(0.22, 0.22, 0.22, 1.0)
		c.material = mat

func _ensure_lane_dividers() -> void:
	# Render thin dividers between lanes (lane_count - 1 bands)
	var needed :int= max(lane_count - 1, 0)
	while divider_csgs.size() > needed:
		var d :CSGPolygon3D= divider_csgs.pop_back()
		d.queue_free()
	while divider_csgs.size() < needed:
		var d := CSGPolygon3D.new()
		add_child(d)
		divider_csgs.append(d)

	for i in divider_csgs.size():
		var d := divider_csgs[i]
		d.mode = CSGPolygon3D.MODE_PATH
		d.path_node = path.get_path()
		d.path_interval = max(sample_step * m_to_units, 0.02)
		d.path_joined = true
		d.path_rotation = CSGPolygon3D.PATH_ROTATION_PATH

		# Divider centered between lane i and i+1
		var left_off := lane_offsets_cache[i]
		var right_off := lane_offsets_cache[i + 1]
		var center := 0.5 * (left_off + right_off)
		var w := (divider_width_m * m_to_units)
		var t := 0.2 * m_to_units

		d.polygon = PackedVector2Array([
			Vector2(center - w * 0.5, 0.0),
			Vector2(center + w * 0.5, 0.0),
			Vector2(center + w * 0.5, -t),
			Vector2(center - w * 0.5, -t),
		])

		d.use_collision = false
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.albedo_color = Color(0.95, 0.95, 0.95, 1.0)  # light stripe
		d.material = mat

func _build_curve_from_model() -> void:
	curve.clear_points()
	if track_model == null or track_model.is_empty():
		return

	# lanes + meta
	var meta := track_model.get_track_meta()
	lane_count = max(1, int(meta.get("lanes", lane_count)))
	lane_width_m = float(meta.get("lane_width", lane_width_m))
	start_lane = int(meta.get("start_lane", start_lane))

	var pos := Vector3.ZERO
	var yaw := 0.0   # around Y (up)
	var pitch := 0.0 # around lateral axis; we keep it as per segment grade
	var up := Vector3.UP

	var points: Array[Vector3] = []
	var tilts: Array[float] = []

	for seg in track_model.get_segments():
		var remaining : float = max(seg.length, 0.0)
		if remaining <= 0.0:
			# still stamp a point for labels/debug
			points.append(pos)
			tilts.append(seg.bank)
			continue

		var steps := int(ceil(remaining / max(sample_step, 0.001)))
		var ds := remaining / float(steps)
		pitch = seg.grade  # constant inside segment
		var roll := seg.bank

		for i in steps:
			# integrate yaw from curvature
			var dyaw := seg.curvature * ds
			yaw += dyaw

			# forward tangent from yaw+pitch (spherical-ish)
			var fwd := Vector3(
				cos(pitch) * cos(yaw),
				sin(pitch),
				cos(pitch) * sin(yaw)
			).normalized()

			pos += fwd * (ds * m_to_units)

			points.append(pos)
			tilts.append(roll)

	# feed Curve3D
	for i in points.size():
		curve.add_point(points[i])
	for i in tilts.size():
		curve.set_point_tilt(i, tilts[i])  # roll around the tangent

	# ensure Path3D has the new curve
	if path == null:
		path = Path3D.new()
		add_child(path)
	path.curve = curve

func _rebuild_lane_offsets() -> void:
	lane_offsets_cache.clear()
	var half := (float(lane_count) - 1.0) * 0.5
	for i in lane_count:
		lane_offsets_cache.append((float(i) - half) * (lane_width_m * m_to_units))

func _ensure_car_nodes(car_id: Variant) -> Node3D:
	if followers.has(car_id):
		return followers[car_id]

	# PathFollow3D drives along the curve orientation/tilt
	var follow := PathFollow3D.new()
	path.add_child(follow)
	follow.rotation_mode = PathFollow3D.ROTATION_ORIENTED

	# child applies lane offset AFTER tilt
	var lane_node := Node3D.new()
	follow.add_child(lane_node)

	# simple car visual; replace with your GLB
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.scale = Vector3(0.105, 0.07, 0.165)  # rough “car” proportions
	
	#lane_node.add_child(mesh)
	lane_node.add_child(car_mesh)

	followers[car_id] = follow
	return follow

func update_car_snapshot(snapshot: Dictionary) -> void:
	if track_model == null or curve.get_point_count() < 2:
		return
	var car_id : String = snapshot.get("car_id", "primary")
	var s := float(snapshot.get("s", 0.0)) * m_to_units
	var lane := int(snapshot.get("lane", start_lane))
	var in_air := bool(snapshot.get("in_air", false))

	var follow := _ensure_car_nodes(car_id) as PathFollow3D
	var lane_node := follow.get_child(0) as Node3D

	if in_air:
		# Detach from rail: place world-space using airborne data
		var origin2d : Vector2 = snapshot.get("airborne_origin", Vector2.ZERO)
		var heading := float(snapshot.get("airborne_heading", 0.0))
		var altitude := float(snapshot.get("altitude", 0.0)) * m_to_units

		# Convert 2D origin to 3D on XZ plane (your 2D RIGHT→X, UP→Z)
		var world := Vector3(origin2d.x * m_to_units, altitude, origin2d.y * m_to_units)
		follow.transform.origin = world
		# Forward from heading on XZ
		var rot_y := heading
		follow.transform.basis = Basis(Vector3.UP, rot_y)
		lane_node.transform.origin = Vector3.ZERO
	else:
		# stick to curve (distance is in local units)
		follow.progress = clamp(s, 0.0, track_model.get_total_length() * m_to_units)
		# lane offset uses the tilted normal at this point
		var lane_idx :int = clamp(lane - 1, 0, max(0, lane_offsets_cache.size() - 1))
		lane_node.transform.origin = Vector3(lane_offsets_cache[lane_idx], 0.0, 0.0)

func update_car_snapshots(snapshots: Dictionary) -> void:
	for id in snapshots.keys():
		var snap :Dictionary= snapshots[id]
		if snap is Dictionary:
			snap["car_id"] = id
			update_car_snapshot(snap)

func _refresh_followers_transforms() -> void:
	for id in followers.keys():
		# no-op; callers will push fresh snapshots anyway
		pass
