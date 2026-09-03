extends VehicleBody3D
class_name PlayerCar

## Semi-realistic drivetrain on top of Godot VehicleBody3D / VehicleWheel3D.
## Engine RPM + torque curve, gearbox (R + 1-5), speed-sensitive steering,
## brakes / handbrake, suspension, tire slip, weight transfer.

signal telemetry(speed_kmh: float, rpm: float, gear: int, slipping: float)

const IDLE_RPM := 900.0
const REDLINE_RPM := 7500.0
const STALL_RPM := 600.0
const PEAK_TORQUE := 455.0  # N·m — planted sports-car punch
const PEAK_TORQUE_RPM := 4800.0
const FINAL_DRIVE := 3.73
const DRIVELINE_EFFICIENCY := 0.91
const WHEEL_RADIUS := 0.34
const VISUAL_SCALE := 2.0

# R, 1, 2, 3, 4, 5
const GEAR_RATIOS: Array[float] = [-3.42, 3.58, 2.16, 1.48, 1.12, 0.86]

@export var auto_shift: bool = true
@export var max_steer_angle: float = 0.50
@export var min_steer_angle: float = 0.14
@export var brake_force: float = 34.0
@export var handbrake_force: float = 24.0

var gear: int = 1  # 0 = reverse, 1-5 = forward
var rpm: float = IDLE_RPM
var throttle_input: float = 0.0
var brake_input: float = 0.0
var steer_input: float = 0.0
var handbrake_input: float = 0.0
var speed_kmh: float = 0.0
var slipping: float = 0.0
var _shift_lock: float = 0.0
var _spawn_transform: Transform3D
var _manual_override: bool = false

@onready var wheel_fl: VehicleWheel3D = $WheelFL
@onready var wheel_fr: VehicleWheel3D = $WheelFR
@onready var wheel_bl: VehicleWheel3D = $WheelBL
@onready var wheel_br: VehicleWheel3D = $WheelBR
@onready var visual: Node3D = $Visual
@onready var engine_player: AudioStreamPlayer = $EngineAudio
@onready var skid_player: AudioStreamPlayer3D = $SkidAudio
var smoke_fl: GPUParticles3D
var smoke_fr: GPUParticles3D
var smoke_bl: GPUParticles3D
var smoke_br: GPUParticles3D
var skid_marks: SkidMarks


func _ready() -> void:
	_spawn_transform = global_transform
	mass = 1280.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.28, 0.08)
	linear_damp = 0.10
	angular_damp = 0.92
	continuous_cd = true
	_setup_wheels()
	_attach_visuals()
	_setup_smoke()
	_setup_audio()
	_setup_skid_marks()


func set_spawn(xf: Transform3D) -> void:
	_spawn_transform = xf
	reset_vehicle()


func reset_vehicle() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false
	global_transform = _spawn_transform
	gear = 1
	rpm = IDLE_RPM
	engine_force = 0.0
	brake = 8.0
	steering = 0.0
	_shift_lock = 0.2
	_manual_override = false
	if skid_marks:
		skid_marks.clear_marks()


func _setup_wheels() -> void:
	var wheels: Array[VehicleWheel3D] = [wheel_fl, wheel_fr, wheel_bl, wheel_br]
	for w in wheels:
		w.wheel_radius = WHEEL_RADIUS
		w.wheel_rest_length = 0.12
		w.wheel_friction_slip = 4.0
		w.suspension_stiffness = 78.0
		w.suspension_max_force = 16000.0
		w.damping_compression = 2.85
		w.damping_relaxation = 3.70
		w.wheel_roll_influence = 0.08
	wheel_fl.use_as_steering = true
	wheel_fr.use_as_steering = true
	wheel_bl.use_as_steering = false
	wheel_br.use_as_steering = false
	wheel_fl.use_as_traction = false
	wheel_fr.use_as_traction = false
	wheel_bl.use_as_traction = true
	wheel_br.use_as_traction = true
	wheel_fl.wheel_friction_slip = 4.35
	wheel_fr.wheel_friction_slip = 4.35
	wheel_bl.wheel_friction_slip = 3.95
	wheel_br.wheel_friction_slip = 3.95


func _setup_smoke() -> void:
	var tex: Texture2D = load("res://assets/textures/smoke.png")
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var quad := QuadMesh.new()
	quad.size = Vector2(1.05, 1.05)
	quad.material = mat
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 55.0
	proc.initial_velocity_min = 0.25
	proc.initial_velocity_max = 1.8
	proc.gravity = Vector3(0, 0.7, 0)
	proc.scale_min = 0.4
	proc.scale_max = 1.35
	proc.color = Color(0.72, 0.72, 0.72, 0.5)
	var created: Array[GPUParticles3D] = []
	for w in [wheel_fl, wheel_fr, wheel_bl, wheel_br]:
		var pfx := GPUParticles3D.new()
		pfx.name = "Smoke"
		pfx.amount = 22
		pfx.lifetime = 0.75
		pfx.emitting = false
		pfx.process_material = proc
		pfx.draw_pass_1 = quad
		w.add_child(pfx)
		created.append(pfx)
	smoke_fl = created[0]
	smoke_fr = created[1]
	smoke_bl = created[2]
	smoke_br = created[3]


func _setup_skid_marks() -> void:
	skid_marks = SkidMarks.new()
	skid_marks.name = "SkidMarks"
	# World-space so marks stay on the tarmac after the car moves.
	call_deferred("_parent_skid_marks")


func _parent_skid_marks() -> void:
	if skid_marks == null:
		return
	var host := get_parent()
	if host:
		host.add_child(skid_marks)
	else:
		add_child(skid_marks)


func _attach_visuals() -> void:
	var packed: PackedScene = load("res://assets/models/cars/sedan-sports.glb")
	if packed == null:
		push_warning("Missing sedan-sports.glb")
		return
	var inst: Node3D = packed.instantiate()
	visual.add_child(inst)
	# Kenney cars face +Z; Godot vehicles face -Z. Scale to a ~4 m sports car.
	inst.rotation.y = PI
	inst.scale = Vector3(VISUAL_SCALE, VISUAL_SCALE, VISUAL_SCALE)
	inst.position = Vector3(0.0, -0.06, 0.02)

	var wheel_nodes := {
		"wheel-front-left": wheel_fl,
		"wheel-front-right": wheel_fr,
		"wheel-back-left": wheel_bl,
		"wheel-back-right": wheel_br,
	}
	for mesh_name in wheel_nodes.keys():
		var mesh: Node = inst.find_child(mesh_name, true, false)
		if mesh == null:
			continue
		mesh.visible = false
		var dup: Node = mesh.duplicate()
		dup.visible = true
		wheel_nodes[mesh_name].add_child(dup)
		if dup is Node3D:
			(dup as Node3D).position = Vector3.ZERO
			(dup as Node3D).rotation = Vector3.ZERO
			(dup as Node3D).scale = Vector3.ONE * 1.15


func _setup_audio() -> void:
	var engine_stream: AudioStream = load("res://assets/audio/engine_loop_3.wav")
	if engine_stream is AudioStreamWAV:
		var wav := engine_stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = -1
	engine_player.stream = engine_stream
	engine_player.bus = "Engine"
	engine_player.volume_db = -8.0
	engine_player.play()

	var skid_stream: AudioStream = load("res://assets/audio/tires_squal_loop.wav")
	if skid_stream is AudioStreamWAV:
		var sw := skid_stream as AudioStreamWAV
		sw.loop_mode = AudioStreamWAV.LOOP_FORWARD
		sw.loop_end = -1
	skid_player.stream = skid_stream
	skid_player.bus = "Tires"
	skid_player.volume_db = -40.0
	skid_player.play()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("shift_up"):
		_manual_override = true
		_change_gear(gear + 1)
	elif event.is_action_pressed("shift_down"):
		_manual_override = true
		_change_gear(gear - 1)


func _physics_process(delta: float) -> void:
	_read_input()
	var forward := -global_transform.basis.z
	var speed_ms := linear_velocity.dot(forward)
	speed_kmh = speed_ms * 3.6

	_shift_lock = maxf(_shift_lock - delta, 0.0)
	_update_gearbox(speed_ms)
	_update_engine(delta, speed_ms)
	_apply_steering(delta)
	_apply_brakes()
	_apply_weight_transfer()
	_apply_aero(speed_ms)
	_apply_anti_roll(delta)
	_update_slip_fx()
	_update_audio()
	telemetry.emit(speed_kmh, rpm, gear, slipping)


func _read_input() -> void:
	throttle_input = Input.get_action_strength("accelerate")
	throttle_input = maxf(throttle_input, _axis_trigger(JOY_AXIS_TRIGGER_RIGHT))

	var reverse_axis := Input.get_action_strength("brake")
	reverse_axis = maxf(reverse_axis, _axis_trigger(JOY_AXIS_TRIGGER_LEFT))
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		reverse_axis = maxf(reverse_axis, 1.0)

	steer_input = Input.get_axis("steer_left", "steer_right")
	var pad_x := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	if absf(pad_x) > absf(steer_input):
		steer_input = pad_x
	steer_input = clampf(steer_input, -1.0, 1.0)

	handbrake_input = Input.get_action_strength("handbrake")
	if Input.is_physical_key_pressed(KEY_SHIFT):
		handbrake_input = 1.0

	var space_brake := 1.0 if Input.is_physical_key_pressed(KEY_SPACE) else 0.0

	if reverse_axis > 0.1 and speed_kmh > 8.0 and gear >= 1:
		brake_input = reverse_axis
		throttle_input = 0.0
	elif reverse_axis > 0.4 and speed_kmh < 12.0:
		if gear != 0:
			_change_gear(0)
		throttle_input = reverse_axis
		brake_input = space_brake
	else:
		brake_input = maxf(space_brake, reverse_axis if speed_kmh > 4.0 and throttle_input < 0.1 else 0.0)
		if gear == 0 and throttle_input > 0.15 and reverse_axis < 0.1:
			_change_gear(1)

	brake_input = clampf(maxf(brake_input, handbrake_input * 0.35), 0.0, 1.0)
	throttle_input = clampf(throttle_input, 0.0, 1.0)


func _axis_trigger(axis: int) -> float:
	var v := Input.get_joy_axis(0, axis)
	if v < 0.0:
		v = (v + 1.0) * 0.5
	return clampf(v, 0.0, 1.0)


func _change_gear(next: int) -> void:
	next = clampi(next, 0, 5)
	if next == gear:
		return
	gear = next
	_shift_lock = 0.16
	rpm = lerpf(rpm, IDLE_RPM + 400.0, 0.35)


func _update_gearbox(speed_ms: float) -> void:
	if not auto_shift or _manual_override or _shift_lock > 0.0:
		return
	if gear == 0:
		return
	if rpm > 6400.0 and gear < 5 and throttle_input > 0.2:
		_change_gear(gear + 1)
	elif rpm < 2200.0 and gear > 1 and speed_kmh > 8.0:
		_change_gear(gear - 1)
	elif speed_kmh < 4.0 and throttle_input < 0.05 and gear > 1:
		_change_gear(1)


func _torque_at(engine_rpm: float) -> float:
	var n := clampf(engine_rpm, 700.0, REDLINE_RPM + 400.0)
	var x := (n - PEAK_TORQUE_RPM) / 2600.0
	var shape := exp(-x * x * 1.05)
	var idle_fill := clampf((n - 700.0) / 1300.0, 0.40, 1.0)
	return PEAK_TORQUE * lerpf(0.58, 1.0, shape) * idle_fill


func _update_engine(delta: float, speed_ms: float) -> void:
	var ratio: float = GEAR_RATIOS[gear]
	var driven_rpm := 0.0
	driven_rpm += absf(wheel_bl.get_rpm())
	driven_rpm += absf(wheel_br.get_rpm())
	driven_rpm *= 0.5

	var target_rpm: float
	if absf(ratio) < 0.01:
		target_rpm = lerpf(IDLE_RPM, 3500.0, throttle_input)
	else:
		target_rpm = driven_rpm * absf(ratio) * FINAL_DRIVE
		if absf(speed_ms) < 0.4 and throttle_input < 0.05:
			target_rpm = IDLE_RPM

	if _shift_lock > 0.0:
		target_rpm = lerpf(rpm, IDLE_RPM + throttle_input * 1800.0, 0.4)

	var rpm_lerp := 8.0 if target_rpm < rpm else 13.0
	rpm = lerpf(rpm, clampf(target_rpm, IDLE_RPM * 0.85, REDLINE_RPM + 350.0), 1.0 - exp(-delta * rpm_lerp))

	var throttle_eff := throttle_input
	if rpm > REDLINE_RPM:
		throttle_eff *= 0.12
	if _shift_lock > 0.08:
		throttle_eff *= 0.05

	var torque := _torque_at(rpm) * throttle_eff
	var wheel_force := torque * absf(ratio) * FINAL_DRIVE / WHEEL_RADIUS * DRIVELINE_EFFICIENCY
	if gear == 0:
		wheel_force = -wheel_force
	if throttle_eff < 0.02:
		wheel_force = 0.0

	engine_force = wheel_force


func _apply_steering(delta: float) -> void:
	var speed_factor := clampf(absf(speed_kmh) / 180.0, 0.0, 1.0)
	var max_steer := lerpf(max_steer_angle, min_steer_angle, speed_factor)
	# VehicleBody3D: positive steering rotates +Y = turn LEFT (vehicle faces -Z).
	# get_axis(steer_left, steer_right) is negative on A / positive on D, so negate.
	var target := -steer_input * max_steer
	steering = lerp_angle(steering, target, 1.0 - exp(-delta * 10.0))


func _apply_brakes() -> void:
	var front := brake_input * brake_force * 0.64
	var rear := brake_input * brake_force * 0.36
	rear += handbrake_input * handbrake_force
	wheel_fl.brake = front
	wheel_fr.brake = front
	wheel_bl.brake = rear
	wheel_br.brake = rear
	var rear_grip := lerpf(3.95, 0.80, handbrake_input)
	wheel_bl.wheel_friction_slip = rear_grip
	wheel_br.wheel_friction_slip = rear_grip
	brake = brake_input * 2.0


func _apply_weight_transfer() -> void:
	var local_vel := global_transform.basis.inverse() * linear_velocity
	var long_a := clampf((-local_vel.z) * 0.018 + engine_force * 0.00003 - brake_input * 0.32, -1.0, 1.0)
	var lat_a := clampf(local_vel.x * 0.032, -1.0, 1.0)
	center_of_mass = Vector3(lat_a * 0.08, -0.28 - long_a * 0.03, 0.08 - long_a * 0.12)


func _apply_aero(speed_ms: float) -> void:
	var v2 := speed_ms * speed_ms
	apply_central_force(Vector3.DOWN * v2 * 3.4)
	apply_central_force(global_transform.basis.z * v2 * 0.28 * signf(speed_ms))


func _apply_anti_roll(_delta: float) -> void:
	# Mild uprighting so the car stays planted without fighting jumps.
	var up := global_transform.basis.y
	var tilt := up.cross(Vector3.UP)
	var amount := tilt.length()
	if amount > 0.02 and up.dot(Vector3.UP) > 0.25:
		apply_torque(tilt.normalized() * amount * 5200.0)


func _update_slip_fx() -> void:
	var wheels: Array[VehicleWheel3D] = [wheel_fl, wheel_fr, wheel_bl, wheel_br]
	var smokes: Array[GPUParticles3D] = [smoke_fl, smoke_fr, smoke_bl, smoke_br]
	var worst := 1.0
	var right := global_transform.basis.x
	for i in wheels.size():
		var info := wheels[i].get_skidinfo()
		worst = minf(worst, info)
		var emit := info < 0.48 and absf(speed_kmh) > 10.0
		if smokes[i]:
			smokes[i].emitting = emit
		if skid_marks and emit:
			var contact: Vector3 = wheels[i].global_position
			contact += Vector3.DOWN * (WHEEL_RADIUS * 0.92)
			var strength := clampf((0.48 - info) / 0.48, 0.0, 1.0)
			skid_marks.add_mark(contact, right, strength)
	slipping = clampf(1.0 - worst, 0.0, 1.0)


func _update_audio() -> void:
	var rpm_t := clampf((rpm - IDLE_RPM) / (REDLINE_RPM - IDLE_RPM), 0.0, 1.2)
	engine_player.pitch_scale = lerpf(0.55, 2.22, rpm_t)
	var vol := lerpf(-16.0, -3.5, clampf(throttle_input * 0.7 + rpm_t * 0.3, 0.0, 1.0))
	engine_player.volume_db = vol

	var skid_vol := lerpf(-48.0, -5.0, clampf((slipping - 0.32) / 0.5, 0.0, 1.0))
	if absf(speed_kmh) < 10.0:
		skid_vol = -48.0
	skid_player.volume_db = skid_vol
	skid_player.pitch_scale = lerpf(0.85, 1.18, clampf(slipping, 0.0, 1.0))


func gear_label() -> String:
	if gear == 0:
		return "R"
	return str(gear)
