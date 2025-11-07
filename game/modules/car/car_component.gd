extends Node
class_name CarComponent

signal params_changed(params: Dictionary)
signal assembled(car_model: CarModel)

const SLOT_MOTOR := "motor"
const SLOT_BATTERY := "battery"
const SLOT_WHEEL := "wheel"
const SLOT_ROLLER := "roller"
const SLOT_BODY := "body"

#const SparePartData := preload("res://modules/spareparts/spare_part_data.gd")
const SLOT_TO_BLUEPRINT_KEY := {
	SLOT_BODY: "body",
	SLOT_MOTOR: "motor",
	SLOT_BATTERY: "battery"
}
const MULTI_SLOT_TO_BLUEPRINT_KEY := {
	SLOT_WHEEL: "wheels",
	SLOT_ROLLER: "rollers"
}

@export var body_sparepart: Script
@export var motor_sparepart: Script
@export var roller_sparepart: Script
@export var battery_sparepart: Script
@export var wheel_sparepart: Script

@export var start_enabled: bool = false:
	set = set_start_enabled,
	get = is_started
@export var base_mass: float = 0.12
@export var base_drive_force_max: float = 0.0
@export var base_battery_capacity: float = 0.0
@export var base_drag_coefficient: float = 0.0
@export var base_frontal_area: float = 0.0
@export var base_rolling_resistance: float = 0.0
@export var base_regen_factor: float = 0.0
@export var base_lateral_friction_scale: float = 0.0
@export var base_downforce_lateral: float = 0.0
# Strict validation toggle: if true, missing/extra parts abort assembly and push errors
@export var strict_validation: bool = false

#
# --- Stat clamping constants and allowed keys ---
const MIN_MASS: float = 0.02
const MAX_MASS: float = 2.5
const MIN_FRONTAL_AREA: float = 0.0001
const MAX_FRONTAL_AREA: float = 0.2
const MIN_DRAG_COEFF: float = 0.0
const MAX_DRAG_COEFF: float = 3.0
const MIN_CRR: float = 0.0
const MAX_CRR: float = 0.2
const MIN_BATTERY: float = 0.0
const MAX_BATTERY: float = 10000.0
const MIN_REGEN: float = 0.0
const MAX_REGEN: float = 1.0
const MIN_LAT_FRIC_SCALE: float = 0.0
const MAX_LAT_FRIC_SCALE: float = 5.0
const MIN_DOWNFORCE_LAT: float = 0.0
const MAX_DOWNFORCE_LAT: float = 5.0
const MIN_DRIVE_FORCE: float = 0.0
const MAX_DRIVE_FORCE: float = 50.0
# --- Added stat clamps ---
const MIN_FREE_SPEED: float = 0.1
const MAX_FREE_SPEED: float = 200.0
const MIN_ROLLER_BONUS: float = 0.0
const MAX_ROLLER_BONUS: float = 5.0
const MIN_LATERAL_MARGIN: float = 0.0
const MAX_LATERAL_MARGIN: float = 5.0
const MIN_RAIL_PENALTY: float = 0.1
const MAX_RAIL_PENALTY: float = 1.0
const MIN_RAIL_SOFT: float = 0.0
const MAX_RAIL_SOFT: float = 10000.0
const MIN_DRAG_AREA: float = 1e-6
const MAX_DRAG_AREA: float = 1.0

const ALLOWED_ADD_KEYS := [
	"drive_force_max_add", "mass_add", "battery_capacity_add", "rolling_resistance_add",
	"drag_coefficient_add", "frontal_area_add", "regen_factor_add", "lateral_friction_scale_add",
	"downforce_lateral_add",
	# New stat keys
	"free_speed_add", "roller_bonus_add", "lateral_margin_add",
	"rail_hit_penalty_add", "rail_hit_soft_threshold_add", "max_rail_hits_add",
	"drag_area_add"
]
const ALLOWED_MUL_KEYS := [
	"drive_force_max_mul", "drive_force_max_multiplier", "mass_mul", "battery_capacity_mul",
	"rolling_resistance_mul", "drag_coefficient_mul", "frontal_area_mul", "regen_factor_mul",
	"lateral_friction_scale_mul", "downforce_lateral_mul",
	# New stat keys
	"free_speed_mul", "roller_bonus_mul", "lateral_margin_mul",
	"rail_hit_penalty_mul", "rail_hit_soft_threshold_mul", "drag_area_mul"
]

# --- Runtime part flags/keys ---
const RUNTIME_FLOAT_KEYS := [ "throttle_limit" ]
const RUNTIME_BOOL_KEYS := [ "stability_assist", "boost_on_straight" ]

func _get_part_priority(node: Node) -> int:
	# Lower numbers = applied earlier. Default 0 if unspecified.
	if node == null:
		return 0
	if node.has_method("get_priority"):
		var p: int = node.get_priority()
		return int(p)
	if node.has_meta("priority"):
		return int(node.get_meta("priority"))
	if "priority" in node:
		return int(node.priority)
	return 0

func _sort_parts_array(arr_in: Array) -> Array:
	var arr := arr_in.duplicate()
	arr.sort_custom(Callable(self, "_compare_part"))
	return arr

func _compare_part(a: Node, b: Node) -> bool:
	var pa: int = _get_part_priority(a)
	var pb: int = _get_part_priority(b)
	if pa == pb:
		# Stable tie-breaker: instance id (consistent ordering)
		return a.get_instance_id() < b.get_instance_id()
	return pa < pb

# --- Stat helpers ---
func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

func _sanitize_stats(stats_in: Dictionary) -> Dictionary:
	var stats: Dictionary = {}
	# Warn on unknown keys, copy only allowed add/mul keys
	for k in stats_in.keys():
		var ks: String = String(k)
		if ks in ALLOWED_ADD_KEYS or ks in ALLOWED_MUL_KEYS or ks == "drive_force_max":
			var val: float = stats_in[k]
			if not _is_number(val):
				push_warning("Part stat '%s' is non-numeric; ignoring." % ks)
				continue
			stats[ks] = float(val)
		else:
			push_warning("Unknown part stat key '%s' ignored." % ks)
	# Basic range sanity for multipliers (must be >= 0)
	for mk in ALLOWED_MUL_KEYS:
		if stats.has(mk) and float(stats[mk]) < 0.0:
			push_warning("Multiplier '%s' < 0; clamped to 0." % mk)
			stats[mk] = 0.0
	return stats

# --- Extract runtime flags from part stats ---
func _extract_runtime_flags(raw_stats: Dictionary) -> Dictionary:
	var flags: Dictionary = {}
	if raw_stats == null or raw_stats.is_empty():
		return flags
	# Prefer a dedicated runtime dictionary if present
	if raw_stats.has("runtime") and raw_stats["runtime"] is Dictionary:
		var rt: Dictionary = raw_stats["runtime"]
		for k in rt.keys():
			flags[k] = rt[k]
	# Fall back to picking well-known runtime keys from the raw stats
	for f_key in RUNTIME_FLOAT_KEYS:
		if raw_stats.has(f_key) and _is_number(raw_stats[f_key]):
			flags[f_key] = float(raw_stats[f_key])
	for b_key in RUNTIME_BOOL_KEYS:
		if raw_stats.has(b_key):
			flags[b_key] = bool(raw_stats[b_key])
	return flags

var car_model: CarModel = CarModel.new()

# Private cache for last built params
var _last_params: Dictionary = {}

var _pending_rebuild: bool = false
var _started: bool = false
var _watched_parts: Dictionary = {}

const REQUIRED_WHEELS := 4
const REQUIRED_ROLLERS := 4

func _ready() -> void:
	if body_sparepart != null:
		self.add_child(body_sparepart.new())
	if motor_sparepart != null:
		self.add_child(motor_sparepart.new())
	if battery_sparepart != null:
		self.add_child(battery_sparepart.new())		
	if roller_sparepart != null:
		for i in 3:
			self.add_child(roller_sparepart.new())
	if wheel_sparepart != null:
		for i in 3:
			self.add_child(wheel_sparepart.new())			
	
	child_entered_tree.connect(_on_child_entered_tree)
	child_exiting_tree.connect(_on_child_exiting_tree)
	for child in get_children():
		_watch_part(child)
	if _started and not _has_equipped_parts():
		push_error("CarComponent: Cannot start — no spare parts equipped.")
		set_start_enabled(false)
	_queue_assemble()

func assemble() -> void:
	_pending_rebuild = false
	var parts := _gather_parts()

	var counts_ok: bool = _validate_part_counts(parts)
	if strict_validation and not counts_ok:
		return

	var params: Dictionary = {
		"mass": base_mass,
		"drive_force_max": base_drive_force_max,
		"battery_capacity": base_battery_capacity,
		"drag_coefficient": base_drag_coefficient,
		"frontal_area": base_frontal_area,
		"rolling_resistance": base_rolling_resistance,
		"regen_factor": base_regen_factor,
		"lateral_friction_scale": base_lateral_friction_scale,
		"downforce_lateral": base_downforce_lateral,
		# Added stats default to zero to rely on equipped parts
		"free_speed": 0.0,
		"roller_bonus": 0.0,
		"lateral_margin": 0.0,
		"rail_hit_penalty": 0.0,
		"rail_hit_soft_threshold": 0.0,
		"max_rail_hits": 0.0,
		"drag_area": base_drag_coefficient * base_frontal_area,
		"_drag_area_overridden": false,
	}

	var parts_payload: Dictionary = {}

	for part in parts["all"]:
		var raw_stats: Dictionary = _extract_stats(part)
		if raw_stats.is_empty():
			continue
		# Merge runtime flags from raw_stats into parts_payload
		var rt: Dictionary = _extract_runtime_flags(raw_stats)
		if not rt.is_empty():
			for k in rt.keys():
				parts_payload[k] = rt[k]
		var stats: Dictionary = _sanitize_stats(raw_stats)
		if stats.is_empty():
			continue
		_apply_stats(params, stats)

	# Final clamps to keep params physically plausible
	params["mass"] = clampf(float(params["mass"]), MIN_MASS, MAX_MASS)
	params["battery_capacity"] = clampf(float(params["battery_capacity"]), MIN_BATTERY, MAX_BATTERY)
	params["rolling_resistance"] = clampf(float(params["rolling_resistance"]), MIN_CRR, MAX_CRR)
	params["drag_coefficient"] = clampf(float(params["drag_coefficient"]), MIN_DRAG_COEFF, MAX_DRAG_COEFF)
	params["frontal_area"] = clampf(float(params["frontal_area"]), MIN_FRONTAL_AREA, MAX_FRONTAL_AREA)
	params["regen_factor"] = clampf(float(params["regen_factor"]), MIN_REGEN, MAX_REGEN)
	params["lateral_friction_scale"] = clampf(float(params["lateral_friction_scale"]), MIN_LAT_FRIC_SCALE, MAX_LAT_FRIC_SCALE)
	params["downforce_lateral"] = clampf(float(params["downforce_lateral"]), MIN_DOWNFORCE_LAT, MAX_DOWNFORCE_LAT)
	params["drive_force_max"] = clampf(float(params["drive_force_max"]), MIN_DRIVE_FORCE, MAX_DRIVE_FORCE)
	# --- Clamp new fields ---
	params["free_speed"] = clampf(float(params["free_speed"]), MIN_FREE_SPEED, MAX_FREE_SPEED)
	params["roller_bonus"] = clampf(float(params["roller_bonus"]), MIN_ROLLER_BONUS, MAX_ROLLER_BONUS)
	params["lateral_margin"] = clampf(float(params["lateral_margin"]), MIN_LATERAL_MARGIN, MAX_LATERAL_MARGIN)
	params["rail_hit_penalty"] = clampf(float(params["rail_hit_penalty"]), MIN_RAIL_PENALTY, MAX_RAIL_PENALTY)
	params["rail_hit_soft_threshold"] = clampf(float(params["rail_hit_soft_threshold"]), MIN_RAIL_SOFT, MAX_RAIL_SOFT)
	params["max_rail_hits"] = int(max(0, int(params["max_rail_hits"])) )
	# --- Guarded drag_area recompute ---
	var da_overridden: bool = bool(params.get("_drag_area_overridden", false))
	if not da_overridden:
		params["drag_area"] = float(params["drag_coefficient"]) * float(params["frontal_area"]) 
	params.erase("_drag_area_overridden")
	_last_params = params.duplicate(true)
	car_model.set_params(params)
	car_model.set_parts(parts_payload)
	emit_signal("params_changed", params)
	emit_signal("assembled", car_model)

func get_car_model() -> CarModel:
	return car_model

func set_start_enabled(value: bool) -> void:
	if _started == value:
		return
	if value and is_inside_tree() and not _has_equipped_parts():
		push_error("CarComponent: Cannot start — no spare parts equipped.")
		return
	_started = value
	if _started and is_inside_tree():
		_queue_assemble()

func is_started() -> bool:
	return _started

# -- internal -------------------------------------------------------

func _queue_assemble() -> void:
	if _pending_rebuild:
		return
	_pending_rebuild = true
	call_deferred("assemble")

func _has_equipped_parts() -> bool:
	for child in get_children():
		if _get_slot_type(child) != "":
			return true
	return false

func _on_child_entered_tree(node: Node) -> void:
	if node.get_parent() != self:
		return
	_watch_part(node)
	_queue_assemble()

func _on_child_exiting_tree(node: Node) -> void:
	if not _watched_parts.has(node):
		return
	_unwatch_part(node)
	_queue_assemble()

func _watch_part(node: Node) -> void:
	if node == null or _watched_parts.has(node):
		return
	_watched_parts[node] = true
	if node.has_signal("stats_changed"):
		node.connect("stats_changed", Callable(self, "_queue_assemble"), CONNECT_REFERENCE_COUNTED)

func _unwatch_part(node: Node) -> void:
	if node == null:
		return
	if node.has_signal("stats_changed") and node.is_connected("stats_changed", Callable(self, "_queue_assemble")):
		node.disconnect("stats_changed", Callable(self, "_queue_assemble"))
	_watched_parts.erase(node)

func _gather_parts() -> Dictionary:
	var result := {
		"motor": null,
		"battery": null,
		"body": null,
		"wheels": [],
		"rollers": [],
		"others": [],
		"all": []
	}

	for child in get_children():
		var slot := _get_slot_type(child)
		match slot:
			SLOT_MOTOR:
				if result["motor"] == null:
					result["motor"] = child
				else:
					push_warning("Multiple motors detected. Only the first will be used.")
					result["others"].append(child)
			SLOT_BATTERY:
				if result["battery"] == null:
					result["battery"] = child
				else:
					push_warning("Multiple batteries detected. Only the first will be used.")
					result["others"].append(child)
			SLOT_BODY:
				if result["body"] == null:
					result["body"] = child
				else:
					push_warning("Multiple bodies detected. Only the first will be used.")
					result["others"].append(child)
			SLOT_WHEEL:
				(result["wheels"] as Array).append(child)
			SLOT_ROLLER:
				(result["rollers"] as Array).append(child)
			_:
				result["others"].append(child)

	# Cap wheels/rollers to required counts to avoid double-counting stats
	var wheels_arr := result["wheels"] as Array
	if wheels_arr.size() > REQUIRED_WHEELS:
		push_warning("Extra wheels detected (%d). Only the first %d will be used." % [wheels_arr.size(), REQUIRED_WHEELS])
		wheels_arr = wheels_arr.slice(0, REQUIRED_WHEELS)
		result["wheels"] = wheels_arr

	var rollers_arr := result["rollers"] as Array
	if rollers_arr.size() > REQUIRED_ROLLERS:
		push_warning("Extra rollers detected (%d). Only the first %d will be used." % [rollers_arr.size(), REQUIRED_ROLLERS])
		rollers_arr = rollers_arr.slice(0, REQUIRED_ROLLERS)
		result["rollers"] = rollers_arr

	# Deterministic ordering for stat application
	if result["wheels"] is Array:
		result["wheels"] = _sort_parts_array(result["wheels"] as Array)
	if result["rollers"] is Array:
		result["rollers"] = _sort_parts_array(result["rollers"] as Array)
	if result["others"] is Array:
		result["others"] = _sort_parts_array(result["others"] as Array)
	# Singletons wrapped for uniform sort (in case you later allow multiples with priority)
	var singletons: Array = []
	if result["motor"] != null:
		singletons.append(result["motor"])
	if result["battery"] != null:
		singletons.append(result["battery"])
	if result["body"] != null:
		singletons.append(result["body"])
	singletons = _sort_parts_array(singletons)

	for node in singletons:
		result["all"].append(node)
	for wheel in result["wheels"]:
		result["all"].append(wheel)
	for roller in result["rollers"]:
		result["all"].append(roller)
	for extra in result["others"]:
		result["all"].append(extra)

	return result

func _get_slot_type(node: Node) -> String:
	if node == null:
		return ""
	if node.has_method("get_slot_type"):
		return String(node.get_slot_type()).to_lower()
	if node.has_meta("slot_type"):
		return String(node.get_meta("slot_type")).to_lower()
	if "slot_type" in node:
		return String(node.slot_type).to_lower()
	if node.is_in_group("slot_motor"):
		return SLOT_MOTOR
	if node.is_in_group("slot_battery"):
		return SLOT_BATTERY
	if node.is_in_group("slot_wheel"):
		return SLOT_WHEEL
	if node.is_in_group("slot_roller"):
		return SLOT_ROLLER
	if node.is_in_group("slot_body"):
		return SLOT_BODY
	return ""

func _extract_stats(node: Node) -> Dictionary:
	if node == null:
		return {}
	if node.has_method("get_part_stats"):
		var stats = node.get_part_stats()
		if stats is Dictionary:
			return stats.duplicate()
	if node.has_meta("stats"):
		var meta_stats = node.get_meta("stats")
		if meta_stats is Dictionary:
			return meta_stats.duplicate()
	if node.has_method("get_stats"):
		var alt_stats = node.get_stats()
		if alt_stats is Dictionary:
			return alt_stats.duplicate()
	return {}

func _apply_stats(params: Dictionary, stats: Dictionary) -> void:
	# --- drive_force_max ---
	# Back-compat: allow legacy keys: "drive_force_max" (add) and "drive_force_max_multiplier" (mul)
	params["drive_force_max"] += float(stats.get("drive_force_max_add", stats.get("drive_force_max", 0.0)))
	params["drive_force_max"] *= float(stats.get("drive_force_max_mul", stats.get("drive_force_max_multiplier", 1.0)))

	# --- mass ---
	params["mass"] += float(stats.get("mass_add", stats.get("mass", 0.0)))
	params["mass"] *= float(stats.get("mass_mul", 1.0))

	# --- battery_capacity ---
	params["battery_capacity"] += float(stats.get("battery_capacity_add", stats.get("battery_capacity", 0.0)))
	params["battery_capacity"] *= float(stats.get("battery_capacity_mul", 1.0))

	# --- rolling_resistance ---
	params["rolling_resistance"] += float(stats.get("rolling_resistance_add", stats.get("rolling_resistance", 0.0)))
	params["rolling_resistance"] *= float(stats.get("rolling_resistance_mul", 1.0))

	# --- drag_coefficient ---
	params["drag_coefficient"] += float(stats.get("drag_coefficient_add", stats.get("drag_coefficient", 0.0)))
	params["drag_coefficient"] *= float(stats.get("drag_coefficient_mul", 1.0))

	# --- frontal_area ---
	params["frontal_area"] += float(stats.get("frontal_area_add", stats.get("frontal_area", 0.0)))
	params["frontal_area"] *= float(stats.get("frontal_area_mul", 1.0))

	# --- regen_factor ---
	params["regen_factor"] += float(stats.get("regen_factor_add", stats.get("regen_factor", 0.0)))
	params["regen_factor"] *= float(stats.get("regen_factor_mul", 1.0))

	# --- lateral_friction_scale ---
	params["lateral_friction_scale"] += float(stats.get("lateral_friction_scale_add", stats.get("lateral_friction_scale", 0.0)))
	params["lateral_friction_scale"] *= float(stats.get("lateral_friction_scale_mul", 1.0))

	# --- downforce_lateral ---
	params["downforce_lateral"] += float(stats.get("downforce_lateral_add", stats.get("downforce_lateral", 0.0)))
	params["downforce_lateral"] *= float(stats.get("downforce_lateral_mul", 1.0))

	# --- free_speed ---
	params["free_speed"] += float(stats.get("free_speed_add", 0.0))
	params["free_speed"] *= float(stats.get("free_speed_mul", 1.0))

	# --- roller_bonus ---
	params["roller_bonus"] += float(stats.get("roller_bonus_add", 0.0))
	params["roller_bonus"] *= float(stats.get("roller_bonus_mul", 1.0))

	# --- lateral_margin ---
	params["lateral_margin"] += float(stats.get("lateral_margin_add", 0.0))
	params["lateral_margin"] *= float(stats.get("lateral_margin_mul", 1.0))

	# --- rail_hit_penalty ---
	params["rail_hit_penalty"] += float(stats.get("rail_hit_penalty_add", 0.0))
	params["rail_hit_penalty"] *= float(stats.get("rail_hit_penalty_mul", 1.0))

	# --- rail_hit_soft_threshold ---
	params["rail_hit_soft_threshold"] += float(stats.get("rail_hit_soft_threshold_add", 0.0))
	params["rail_hit_soft_threshold"] *= float(stats.get("rail_hit_soft_threshold_mul", 1.0))

	# --- max_rail_hits (additive only; cast to int) ---
	if stats.has("max_rail_hits_add"):
		var add_hits: int = int(stats["max_rail_hits_add"])
		params["max_rail_hits"] = int(max(0, int(params.get("max_rail_hits", 0)) + add_hits))

	# --- drag_area (optional direct Cd·A control) ---
	if stats.has("drag_area_add"):
		params["drag_area"] = float(params.get("drag_area", base_drag_coefficient * base_frontal_area)) + float(stats["drag_area_add"]) 
		params["_drag_area_overridden"] = true
	if stats.has("drag_area_mul"):
		params["drag_area"] = float(params.get("drag_area", base_drag_coefficient * base_frontal_area)) * float(stats["drag_area_mul"]) 
		params["_drag_area_overridden"] = true

func _validate_part_counts(parts: Dictionary) -> bool:
	var ok: bool = true

	# Motor present?
	if parts.has("motor"):
		if parts["motor"] == null:
			var msg_motor: String = "CarComponent: Missing motor part."
			if strict_validation:
				push_error(msg_motor)
			else:
				push_warning(msg_motor)
			ok = false
	else:
		# If key somehow missing, treat as error
		var msg_motor_key: String = "CarComponent: Internal error — 'motor' slot not found in parts dictionary."
		if strict_validation:
			push_error(msg_motor_key)
		else:
			push_warning(msg_motor_key)
		ok = false

	# Battery present?
	if parts.has("battery"):
		if parts["battery"] == null:
			var msg_batt: String = "CarComponent: Missing battery part."
			if strict_validation:
				push_error(msg_batt)
			else:
				push_warning(msg_batt)
			ok = false
	else:
		var msg_batt_key: String = "CarComponent: Internal error — 'battery' slot not found in parts dictionary."
		if strict_validation:
			push_error(msg_batt_key)
		else:
			push_warning(msg_batt_key)
		ok = false

	# Wheels count
	var wheel_count: int = 0
	if parts.has("wheels") and parts["wheels"] is Array:
		wheel_count = (parts["wheels"] as Array).size()
	else:
		var msg_wheels_key: String = "CarComponent: Internal error — 'wheels' array not found in parts dictionary."
		if strict_validation:
			push_error(msg_wheels_key)
		else:
			push_warning(msg_wheels_key)
		ok = false
	if wheel_count != REQUIRED_WHEELS:
		var msg_wheels: String = "CarComponent: Expected %d wheels, found %d." % [REQUIRED_WHEELS, wheel_count]
		if strict_validation:
			push_error(msg_wheels)
		else:
			push_warning(msg_wheels)
		ok = false

	# Rollers count
	var roller_count: int = 0
	if parts.has("rollers") and parts["rollers"] is Array:
		roller_count = (parts["rollers"] as Array).size()
	else:
		var msg_rollers_key: String = "CarComponent: Internal error — 'rollers' array not found in parts dictionary."
		if strict_validation:
			push_error(msg_rollers_key)
		else:
			push_warning(msg_rollers_key)
		ok = false
	if roller_count != REQUIRED_ROLLERS:
		var msg_rollers: String = "CarComponent: Expected %d rollers, found %d." % [REQUIRED_ROLLERS, roller_count]
		if strict_validation:
			push_error(msg_rollers)
		else:
			push_warning(msg_rollers)
		ok = false

	return ok

# Public getter for last built params
func get_params() -> Dictionary:
	return _last_params

# === Garage / API helpers ===
# Programmatic equip: attach a part node and set its slot type (if provided), then rebuild.
func equip(part: Node, slot_type: String = "") -> void:
	if part == null:
		return
	# If a slot is explicitly provided, set it via meta for consistency
	if slot_type != "":
		part.set_meta("slot_type", slot_type)
	# Reparent if needed
	if part.get_parent() != self:
		add_child(part)
	else:
		# Already a child: just ensure we watch and rebuild
		_watch_part(part)
		_queue_assemble()

# Programmatic unequip: detaches a part node from this car.
func unequip(part: Node) -> void:
	if part == null:
		return
	if part.get_parent() == self:
		_unwatch_part(part)
		remove_child(part)
		part.owner = null
		_queue_assemble()

# Remove all equipped parts (keeps CarComponent itself)
func clear_parts() -> void:
	var children: Array = get_children()
	for c in children:
		if c is Node:
			_unwatch_part(c)
			remove_child(c)
	_queue_assemble()

# Preset loader: rebuilds a car from a config dictionary.
# Expected schema:
# {
#   "base": { mass, drive_force_max, battery_capacity, drag_coefficient, frontal_area, rolling_resistance, regen_factor, lateral_friction_scale, downforce_lateral },
#   "parts": [ { "slot_type": "motor", "name": "motor_x", "priority": 0, "stats": { ... } }, ... ]
# }
func load_config(cfg: Dictionary) -> void:
	# Apply base overrides if provided
	if cfg.has("base") and cfg["base"] is Dictionary:
		var b: Dictionary = cfg["base"]
		if b.has("mass"): base_mass = float(b["mass"])
		if b.has("drive_force_max"): base_drive_force_max = float(b["drive_force_max"])
		if b.has("battery_capacity"): base_battery_capacity = float(b["battery_capacity"])
		if b.has("drag_coefficient"): base_drag_coefficient = float(b["drag_coefficient"])
		if b.has("frontal_area"): base_frontal_area = float(b["frontal_area"])
		if b.has("rolling_resistance"): base_rolling_resistance = float(b["rolling_resistance"])
		if b.has("regen_factor"): base_regen_factor = float(b["regen_factor"])
		if b.has("lateral_friction_scale"): base_lateral_friction_scale = float(b["lateral_friction_scale"])
		if b.has("downforce_lateral"): base_downforce_lateral = float(b["downforce_lateral"])
	# Replace all current parts with provided ones (if any)
	if cfg.has("parts") and cfg["parts"] is Array:
		clear_parts()
		for p in cfg["parts"]:
			if not (p is Dictionary):
				continue
			var slot: String = String(p.get("slot_type", "")).to_lower()
			var stats: Dictionary = p.get("stats", {})
			var name_hint: String = String(p.get("name", "part"))
			var priority: int = int(p.get("priority", 0))
			var part_node := Node.new()
			part_node.name = name_hint
			part_node.set_meta("slot_type", slot)
			part_node.set_meta("stats", stats)
			part_node.set_meta("priority", priority)
			equip(part_node)
	else:
		# No parts array: still re-assemble with possibly new bases
		_queue_assemble()

# Optional: dumps current config to a saveable dictionary
func to_config() -> Dictionary:
	var cfg: Dictionary = {
		"base": {
			"mass": base_mass,
			"drive_force_max": base_drive_force_max,
			"battery_capacity": base_battery_capacity,
			"drag_coefficient": base_drag_coefficient,
			"frontal_area": base_frontal_area,
			"rolling_resistance": base_rolling_resistance,
			"regen_factor": base_regen_factor,
			"lateral_friction_scale": base_lateral_friction_scale,
			"downforce_lateral": base_downforce_lateral
		},
		"parts": []
	}
	for child in get_children():
		var slot: String = _get_slot_type(child)
		if slot == "":
			continue
		var part_entry: Dictionary = {
			"slot_type": slot,
			"name": child.name,
			"priority": _get_part_priority(child),
			"stats": _extract_stats(child)
		}
		(cfg["parts"] as Array).append(part_entry)
	return cfg

func to_blueprint(existing: CarBlueprint = null, metadata: Dictionary = {}) -> CarBlueprint:
	var blueprint: CarBlueprint = existing if existing != null else CarBlueprint.new()
	var parts := _gather_parts()
	var slots: Dictionary = {}

	# Single slot payloads
	for slot in SLOT_TO_BLUEPRINT_KEY.keys():
		var key: String = SLOT_TO_BLUEPRINT_KEY[slot]
		slots[key] = _part_to_blueprint_payload(parts.get(slot, null))

	# Multi slot payloads (arrays)
	for slot in MULTI_SLOT_TO_BLUEPRINT_KEY.keys():
		var multi_key: String = MULTI_SLOT_TO_BLUEPRINT_KEY[slot]
		var slot_parts: Array = []
		if parts.has(slot) and parts[slot] is Array:
			slot_parts = parts[slot]
		slots[multi_key] = _parts_to_blueprint_payloads(slot_parts)

	blueprint.sparepart_slot = slots

	if metadata.has("car_name"):
		blueprint.car_name = String(metadata["car_name"])
	if metadata.has("designed_by"):
		blueprint.designed_by = String(metadata["designed_by"])
	if metadata.has("metadata") and metadata["metadata"] is Dictionary:
		blueprint.metadata = (metadata["metadata"] as Dictionary).duplicate(true)
	else:
		for key in metadata.keys():
			if key == "car_name" or key == "designed_by":
				continue
			if key == "metadata":
				continue
			blueprint.metadata[key] = metadata[key]

	return blueprint

func apply_blueprint(blueprint: CarBlueprint, options: Dictionary = {}) -> bool:
	if blueprint == null:
		push_warning("CarComponent: apply_blueprint called with null blueprint.")
		return false

	var catalog: Variant = options.get("catalog", SparePartData.sparepart)
	if not (catalog is Dictionary):
		catalog = {}
	var catalog_dict: Dictionary = catalog
	var allow_missing: bool = bool(options.get("allow_missing", false))

	clear_parts()

	var success: bool = true

	# Single slot payloads
	for slot in SLOT_TO_BLUEPRINT_KEY.keys():
		var key: String = SLOT_TO_BLUEPRINT_KEY[slot]
		var payload: Variant = blueprint.get_slot_data(key, {})
		if payload is Dictionary and not payload.is_empty():
			var node: Node = _instantiate_blueprint_part(payload, catalog_dict)
			if node == null:
				success = false
				if not allow_missing:
					continue
			else:
				equip(node)

	# Multi slot payloads
	for slot in MULTI_SLOT_TO_BLUEPRINT_KEY.keys():
		var multi_key: String = MULTI_SLOT_TO_BLUEPRINT_KEY[slot]
		var payloads: Variant = blueprint.get_slot_data(multi_key, [])
		if payloads is Array:
			for payload in payloads:
				if not (payload is Dictionary) or (payload as Dictionary).is_empty():
					continue
				var part_node: Node = _instantiate_blueprint_part(payload, catalog_dict)
				if part_node == null:
					success = false
					if not allow_missing:
						continue
				else:
					equip(part_node)

	return success

func _part_to_blueprint_payload(part: Node) -> Dictionary:
	if part == null:
		return {}
	var payload: Dictionary = {}
	var identifier: String = _extract_part_identifier(part)
	if identifier != "":
		payload["id"] = identifier
	var overrides_dict: Dictionary = _get_overrides_dictionary(part)
	if not overrides_dict.is_empty():
		payload["overrides"] = overrides_dict
	var runtime_dict: Dictionary = _get_runtime_dictionary(part)
	if not runtime_dict.is_empty():
		payload["runtime"] = runtime_dict
	return payload

func _parts_to_blueprint_payloads(parts: Array) -> Array:
	var payloads: Array = []
	for part in parts:
		if part == null:
			continue
		payloads.append(_part_to_blueprint_payload(part))
	return payloads

func _instantiate_blueprint_part(payload: Dictionary, catalog: Dictionary) -> Node:
	if payload.is_empty():
		return null
	var part_id: String = String(payload.get("id", ""))
	if part_id == "":
		push_warning("CarComponent: Blueprint payload missing part id; skipping.")
		return null
	var script_path: String = _lookup_script_path(part_id, catalog)
	if script_path == "":
		push_warning("CarComponent: Unable to resolve script for part id '%s'." % part_id)
		return null
	var script_res: Script = load(script_path)
	if script_res == null:
		push_warning("CarComponent: Failed to load spare part script at '%s'." % script_path)
		return null
	var node : Node = script_res.new()
	if node == null:
		return null
	if payload.has("overrides") and node.has_method("set_overrides"):
		node.set_overrides(_duplicate_variant(payload["overrides"]))
	elif payload.has("overrides") and "overrides" in node:
		node.overrides = _duplicate_variant(payload["overrides"])
	if payload.has("runtime") and node.has_method("set_runtime"):
		node.set_runtime(_duplicate_variant(payload["runtime"]))
	elif payload.has("runtime") and "runtime" in node:
		node.runtime = _duplicate_variant(payload["runtime"])
	return node

func _lookup_script_path(part_id: String, catalog: Dictionary) -> String:
	if part_id == "":
		return ""
	if catalog.has(part_id):
		var entry: Dictionary = catalog[part_id]
		if entry.has("source-path"):
			return String(entry["source-path"])
	if SparePartData.sparepart.has(part_id):
		var fallback_entry: Dictionary = SparePartData.sparepart[part_id]
		if fallback_entry.has("source-path"):
			return String(fallback_entry["source-path"])
	return ""

func _extract_part_identifier(part: Node) -> String:
	if part == null:
		return ""
	if part.has_meta("name_id"):
		return String(part.get_meta("name_id"))
	if "name_id" in part:
		return String(part.name_id)
	if part.has_method("get_name_id"):
		return String(part.get_name_id())
	return ""

func _get_part_script_path(part: Node) -> String:
	if part == null:
		return ""
	var script_resource: Script = part.get_script()
	if script_resource == null:
		return ""
	return script_resource.resource_path

func _get_overrides_dictionary(part: Node) -> Dictionary:
	if part == null:
		return {}
	if "overrides" in part and part.overrides is Dictionary:
		return (part.overrides as Dictionary).duplicate(true)
	if part.has_meta("overrides") and part.get_meta("overrides") is Dictionary:
		return (part.get_meta("overrides") as Dictionary).duplicate(true)
	return {}

func _get_runtime_dictionary(part: Node) -> Dictionary:
	if part == null:
		return {}
	if "runtime" in part and part.runtime is Dictionary:
		return (part.runtime as Dictionary).duplicate(true)
	if part.has_meta("runtime") and part.get_meta("runtime") is Dictionary:
		return (part.get_meta("runtime") as Dictionary).duplicate(true)
	return {}

func _duplicate_variant(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	if value is PackedStringArray:
		return PackedStringArray(value)
	return value
