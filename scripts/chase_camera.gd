extends Camera3D
class_name ChaseCamera

enum Mode { CHASE, HOOD }

@export var chase_distance: float = 7.6
@export var chase_height: float = 2.45
@export var chase_look_height: float = 1.05
## Driver-eye height above vehicle origin (seat, not roof / dash glue).
@export var hood_height: float = 1.05
## Positive Z = toward cabin rear (VehicleBody faces -Z).
@export var hood_back: float = 0.52
## Slight right offset for right-hand / driver seat feel.
@export var hood_lateral: float = 0.28
@export var follow_speed: float = 5.4
@export var look_speed: float = 7.5
@export var base_fov: float = 70.0
@export var hood_fov: float = 68.0
@export var max_fov: float = 82.0

var target: Node3D
var mode: Mode = Mode.CHASE
var _look_point: Vector3 = Vector3.ZERO
var _look_ready: bool = false


func _ready() -> void:
	near = 0.08
	far = 2000.0
	fov = base_fov


func toggle_mode() -> void:
	mode = Mode.HOOD if mode == Mode.CHASE else Mode.CHASE
	_look_ready = false


func mode_name() -> String:
	return "HOOD" if mode == Mode.HOOD else "CHASE"


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var speed := 0.0
	var vel := Vector3.ZERO
	if target is RigidBody3D:
		vel = (target as RigidBody3D).linear_velocity
		speed = vel.length()
	var fwd := -target.global_transform.basis.z
	var right := target.global_transform.basis.x
	var steer := 0.0
	if target is PlayerCar:
		steer = (target as PlayerCar).steering
	var travel := fwd
	if speed > 5.0:
		var vd := vel.normalized()
		if vd.dot(fwd) > -0.15:
			travel = fwd.lerp(vd, 0.42).normalized()

	var speed_kmh := speed * 3.6

	if mode == Mode.HOOD:
		# Cabin eye-point: back in the seat, below the roof line, looking down the hood at asphalt.
		var local_pos := Vector3(hood_lateral + steer * 0.04, hood_height, hood_back)
		var desired: Vector3 = target.global_transform * local_pos
		global_position = global_position.lerp(desired, 1.0 - exp(-delta * 18.0))
		# Look ~12–18 m ahead and well below eye height so the road fills the lower frame.
		var look_local := Vector3(hood_lateral * 0.35 - steer * 1.2, 0.22, -14.0)
		var look: Vector3 = target.global_transform * look_local
		if not _look_ready:
			_look_point = look
			_look_ready = true
		_look_point = _look_point.lerp(look, 1.0 - exp(-delta * 16.0))
		look_at(_look_point, Vector3.UP)
		# Keep a slight extra downward pitch so the horizon is not glued to mid-frame.
		rotate_object_local(Vector3.RIGHT, deg_to_rad(-4.5))
		var fov_t := clampf(speed_kmh / 210.0, 0.0, 1.0)
		var hood_target := lerpf(hood_fov, minf(max_fov, 76.0), fov_t)
		fov = lerpf(fov, hood_target, 1.0 - exp(-delta * 2.4))
	else:
		var fov_t := clampf(speed_kmh / 210.0, 0.0, 1.0)
		fov = lerpf(fov, lerpf(base_fov, max_fov, fov_t), 1.0 - exp(-delta * 2.2))
		var dist := chase_distance + clampf(speed_kmh * 0.012, 0.0, 3.2)
		var height := chase_height + clampf(speed_kmh * 0.004, 0.0, 0.8)
		var desired: Vector3 = target.global_position - travel * dist + Vector3.UP * height
		desired.y = maxf(desired.y, target.global_position.y + 1.35)
		global_position = global_position.lerp(desired, 1.0 - exp(-delta * follow_speed))
		var look: Vector3 = (
			target.global_position
			+ Vector3.UP * chase_look_height
			+ travel * (5.5 + clampf(speed_kmh * 0.04, 0.0, 8.0))
			+ -right * steer * (7.5 + speed_kmh * 0.02)
		)
		if not _look_ready:
			_look_point = look
			_look_ready = true
		_look_point = _look_point.lerp(look, 1.0 - exp(-delta * look_speed))
		look_at(_look_point, Vector3.UP)
