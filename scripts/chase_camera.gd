extends Camera3D
class_name ChaseCamera

enum Mode { CHASE, HOOD }

@export var chase_distance: float = 6.4
@export var chase_height: float = 2.15
@export var chase_look_height: float = 0.95
@export var hood_height: float = 0.95
@export var hood_forward: float = -0.42
@export var follow_speed: float = 8.5

var target: Node3D
var mode: Mode = Mode.CHASE


func toggle_mode() -> void:
	mode = Mode.HOOD if mode == Mode.CHASE else Mode.CHASE


func mode_name() -> String:
	return "HOOD" if mode == Mode.HOOD else "CHASE"


func _process(delta: float) -> void:
	if target == null:
		return
	if mode == Mode.HOOD:
		var hood_pos: Vector3 = target.global_transform * Vector3(0.0, hood_height, hood_forward)
		global_position = hood_pos
		look_at(target.global_transform * Vector3(0.0, hood_height, hood_forward - 12.0), Vector3.UP)
	else:
		var desired: Vector3 = target.global_transform * Vector3(0.0, chase_height, chase_distance)
		global_position = global_position.lerp(desired, 1.0 - exp(-delta * follow_speed))
		var look := target.global_position + Vector3.UP * chase_look_height
		look_at(look, Vector3.UP)
