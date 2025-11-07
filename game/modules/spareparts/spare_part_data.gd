extends Node
class_name SparePartData

enum SparePartType {
	MOTOR,
	BODY,
	ROLLER,
	BATTERY,
	WHEEL
}

static var sparepart: Dictionary = {
	"motor_standard_kit": {
		"id": "motor_standard_kit",
		"name": "Motor Standard Kit",
		"type": SparePartType.MOTOR,
		"source-path": "res://modules/spareparts/motor/motor_standard_kit.gd",
		"mesh-path": "res://assets/model/car/motor/spoiler.obj"
	},
	"motor_hyper_dash_3": {
		"id": "motor_hyper_dash_3",
		"name": "Motor Hyper Dash 3",
		"type": SparePartType.MOTOR,
		"source-path": "res://modules/spareparts/motor/motor_hyper_dash_3.gd",
		"mesh-path": "res://assets/model/car/motor/spoiler.obj"
	},
	"battery_lite": {
		"id": "battery_lite",
		"name": "Battery Lite",
		"type": SparePartType.BATTERY,
		"source-path": "res://modules/spareparts/battery/battery_lite.gd",
		"mesh-path": "res://assets/model/car/motor/spoiler.obj"
	},
	"body_standard_kit": {
		"id": "body_standard_kit",
		"name": "Body Standard Kit",
		"type": SparePartType.BODY,
		"source-path": "res://modules/spareparts/body/body_standard_kit.gd",
		"mesh-path": "res://assets/model/car/motor/spoiler.obj"
	},
	"wheel_standard_kit": {
		"id": "wheel_standard_kit",
		"name": "Wheel Standard Kit",
		"type": SparePartType.WHEEL,
		"source-path": "res://modules/spareparts/wheel/wheel_standard_kit.gd",
		"mesh-path": "res://assets/model/car/motor/spoiler.obj"
	},
	"roller_standard_kit": {
		"id": "roller_standard_kit",
		"name": "Roller Standard Kit",
		"type": SparePartType.ROLLER,
		"source-path": "res://modules/spareparts/roller/roller_standard_kit.gd",
		"mesh-path": "res://assets/model/car/motor/spoiler.obj"
	}
}
