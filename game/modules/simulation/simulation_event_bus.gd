extends Node
class_name SimulationEventBus

## Central dispatcher for SimulationController signals.  The controller can
## keep its public signals intact while internally using this node to emit and
## test discrete events.

signal segment_entered(car_id: Variant, segment_index: int, segment_type: String, segment_start: float)
signal lap_completed(car_id: Variant, lap_index: int, total_time: float)
signal car_finished(car_id: Variant, total_time: float)
signal car_derailed(car_id: Variant, total_time: float, overshoot_force: float)
signal rail_hit(car_id: Variant, overshoot_force: float, hit_count: int)
signal state_updated(car_id: Variant, state: Dictionary)

func emit_segment_entered(car_id: Variant, segment_index: int, segment_type: String, segment_start: float) -> void:
	segment_entered.emit(car_id, segment_index, segment_type, segment_start)

func emit_lap_completed(car_id: Variant, lap_index: int, total_time: float) -> void:
	lap_completed.emit(car_id, lap_index, total_time)

func emit_car_finished(car_id: Variant, total_time: float) -> void:
	car_finished.emit(car_id, total_time)

func emit_car_derailed(car_id: Variant, total_time: float, overshoot_force: float) -> void:
	car_derailed.emit(car_id, total_time, overshoot_force)

func emit_rail_hit(car_id: Variant, overshoot_force: float, hit_count: int) -> void:
	rail_hit.emit(car_id, overshoot_force, hit_count)

func emit_state_updated(car_id: Variant, state: Dictionary) -> void:
	state_updated.emit(car_id, state)
