extends VehicleBody3D
class_name PlayerCar

## Semi-realistic drivetrain on top of Godot VehicleBody3D / VehicleWheel3D.
## Engine RPM + torque curve, gearbox (R + 1-5), speed-sensitive steering,
## progressive keyboard steer, brakes / handbrake, suspension, tire slip,
## anti-spin, cabin driver + steering wheel, crash on hard impact / cliff fall.

signal telemetry(speed_kmh: float, rpm: float, gear: int, slipping: float)
signal crashed()

const IDLE_RPM := 900.0
const REDLINE_RPM := 7500.0
const STALL_RPM := 600.0
const PEAK_TORQUE := 400.0  # N·m — planted, less snap-oversteer
const PEAK_TORQUE_RPM := 4800.0
const FINAL_DRIVE := 3.55
const DRIVELINE_EFFICIENCY := 0.90
const WHEEL_RADIUS := 0.34
const VISUAL_SCALE := 2.0
const MAX_ENGINE_FORCE := 7800.0
const MAX_YAW_RATE := 2.15  # rad/s hard cap

# R, 1, 2, 3, 4, 5
const GEAR_RATIOS: Array[float] = [-3.42, 3.58, 2.16, 1.48, 1.12, 0.86]

@export var auto_shift: bool = true
@export var max_steer_angle: float = 0.48
@export var min_steer_angle: float = 0.12
@export var brake_force: float = 34.0
@export var handbrake_force: float = 22.0
@export var steer_accumulate_rate: float = 2.6
@export var steer_return_rate: float = 3.4

var gear: int = 1  # 0 = reverse, 1-5 = forward
var rpm: float = IDLE_RPM
var throttle_input: float = 0.0
var brake_input: float = 0.0
var steer_input: float = 0.0
var handbrake_input: float = 0.0
var speed_kmh: float = 0.0
var slipping: float = 0.0
var is_crashed: bool = false
var _shift_lock: float = 0.0
var _spawn_transform: Transform3D
var _manual_override: bool = false
var _prev_velocity: Vector3 = Vector3.ZERO
var _engine_force_smoothed: float = 0.0
var _steer_wheel: Node3D
var _driver_root: Node3D
var _crash_smoke: GPUParticles3D
var _crash_audio: AudioStreamPlayer3D
var _damage_overlays: Array[MeshInstance3D] = []

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
	mass = 1320.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.32, 0.06)
	linear_damp = 0.14
	angular_damp = 1.85
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 6
	_setup_wheels()
	_attach_visuals()
	_attach_driver_and_wheel()
	_setup_smoke()
	_setup_crash_fx()
	_setup_audio()
	_setup_skid_marks()
	body_entered.connect(_on_body_entered)


func set_spawn(xf: Transform3D) -> void:
	_spawn_transform = xf
	reset_vehicle()


func reset_vehicle() -> void:
	is_crashed = false
	freeze = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_prev_velocity = Vector3.ZERO
	_engine_force_smoothed = 0.0
	sleeping = false
	global_transform = _spawn_transform
	gear = 1
	rpm = IDLE_RPM
	engine_force = 0.0
	brake = 8.0
	steering = 0.0
	steer_input = 0.0
	_shift_lock = 0.2
	_manual_override = false
	if skid_marks:
		skid_marks.clear_marks()
	if _crash_smoke:
		_crash_smoke.emitting = false
	for mi in _damage_overlays:
		mi.visible = false
	if engine_player and not engine_player.playing:
		engine_player.play()


func _setup_wheels() -> void:
	var wheels: Array[VehicleWheel3D] = [wheel_fl, wheel_fr, wheel_bl, wheel_br]
	for w in wheels:
		w.wheel_radius = WHEEL_RADIUS
		w.wheel_rest_length = 0.12
		w.wheel_friction_slip = 4.6
		w.suspension_stiffness = 82.0
		w.suspension_max_force = 17000.0
		w.damping_compression = 3.05
		w.damping_relaxation = 3.95
		w.wheel_roll_influence = 0.06
	wheel_fl.use_as_steering = true
	wheel_fr.use_as_steering = true
	wheel_bl.use_as_steering = false
	wheel_br.use_as_steering = false
	wheel_fl.use_as_traction = false
	wheel_fr.use_as_traction = false
	wheel_bl.use_as_traction = true
	wheel_br.use_as_traction = true
	# Front slightly grippier than rear for planted understeer bias (no snap spin).
	wheel_fl.wheel_friction_slip = 4.85
	wheel_fr.wheel_friction_slip = 4.85
	wheel_bl.wheel_friction_slip = 4.55
	wheel_br.wheel_friction_slip = 4.55


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


func _setup_crash_fx() -> void:
	var tex: Texture2D = load("res://assets/textures/smoke.png")
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var quad := QuadMesh.new()
	quad.size = Vector2(2.2, 2.2)
	quad.material = mat
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 80.0
	proc.initial_velocity_min = 0.6
	proc.initial_velocity_max = 2.8
	proc.gravity = Vector3(0, 1.1, 0)
	proc.scale_min = 0.8
	proc.scale_max = 2.4
	proc.color = Color(0.25, 0.25, 0.25, 0.7)
	_crash_smoke = GPUParticles3D.new()
	_crash_smoke.name = "CrashSmoke"
	_crash_smoke.amount = 48
	_crash_smoke.lifetime = 2.2
	_crash_smoke.emitting = false
	_crash_smoke.process_material = proc
	_crash_smoke.draw_pass_1 = quad
	_crash_smoke.position = Vector3(0, 0.9, 0.6)
	add_child(_crash_smoke)

	_crash_audio = AudioStreamPlayer3D.new()
	_crash_audio.name = "CrashAudio"
	_crash_audio.bus = "Master"
	_crash_audio.max_distance = 80.0
	_crash_audio.unit_size = 4.0
	add_child(_crash_audio)

	# Simple blackened "damage" panels that flip on after a crash.
	for i in 3:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.2, 0.08, 0.55)
		mi.mesh = box
		var dmat := StandardMaterial3D.new()
		dmat.albedo_color = Color(0.08, 0.08, 0.09)
		dmat.roughness = 0.95
		mi.material_override = dmat
		mi.position = Vector3(0.0, 0.55 + float(i) * 0.12, -0.9 + float(i) * 0.35)
		mi.visible = false
		visual.add_child(mi)
		_damage_overlays.append(mi)


func _setup_skid_marks() -> void:
	skid_marks = SkidMarks.new()
	skid_marks.name = "SkidMarks"
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


func _attach_driver_and_wheel() -> void:
	## Clearly posed low-poly seated driver (CC0 / original) + cabin steering wheel.
	_driver_root = Node3D.new()
	_driver_root.name = "Driver"
	# Right-ish seat, cabin height for scaled Kenney sedan.
	_driver_root.position = Vector3(0.28, 0.62, 0.22)
	visual.add_child(_driver_root)

	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color(0.12, 0.14, 0.22)
	suit.roughness = 0.72
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.86, 0.68, 0.54)
	skin.roughness = 0.55
	var helmet := StandardMaterial3D.new()
	helmet.albedo_color = Color(0.82, 0.12, 0.14)
	helmet.roughness = 0.35
	helmet.metallic = 0.15

	# Torso (seated)
	_add_part(_driver_root, BoxMesh.new(), Vector3(0.34, 0.42, 0.22), Vector3(0, 0.28, 0.02), suit)
	# Pelvis
	_add_part(_driver_root, BoxMesh.new(), Vector3(0.32, 0.16, 0.28), Vector3(0, 0.06, 0.06), suit)
	# Head / helmet
	_add_part(_driver_root, SphereMesh.new(), Vector3(0.22, 0.22, 0.22), Vector3(0, 0.58, 0.0), helmet)
	# Visor
	_add_part(_driver_root, BoxMesh.new(), Vector3(0.16, 0.06, 0.04), Vector3(0, 0.56, -0.09), skin)
	# Upper arms reaching wheel
	_add_part(_driver_root, CapsuleMesh.new(), Vector3(0.07, 0.22, 0.07), Vector3(-0.22, 0.34, -0.12), suit, Vector3(deg_to_rad(70), 0, deg_to_rad(25)))
	_add_part(_driver_root, CapsuleMesh.new(), Vector3(0.07, 0.22, 0.07), Vector3(0.22, 0.34, -0.12), suit, Vector3(deg_to_rad(70), 0, deg_to_rad(-25)))
	# Forearms
	_add_part(_driver_root, CapsuleMesh.new(), Vector3(0.06, 0.18, 0.06), Vector3(-0.18, 0.22, -0.28), skin, Vector3(deg_to_rad(20), 0, 0))
	_add_part(_driver_root, CapsuleMesh.new(), Vector3(0.06, 0.18, 0.06), Vector3(0.18, 0.22, -0.28), skin, Vector3(deg_to_rad(20), 0, 0))
	# Thighs (bent sitting)
	_add_part(_driver_root, CapsuleMesh.new(), Vector3(0.09, 0.26, 0.09), Vector3(-0.10, 0.02, -0.18), suit, Vector3(deg_to_rad(85), 0, 0))
	_add_part(_driver_root, CapsuleMesh.new(), Vector3(0.09, 0.26, 0.09), Vector3(0.10, 0.02, -0.18), suit, Vector3(deg_to_rad(85), 0, 0))
	# Shins down to pedals
	_add_part(_driver_root, CapsuleMesh.new(), Vector3(0.07, 0.22, 0.07), Vector3(-0.10, -0.10, -0.42), suit, Vector3(deg_to_rad(10), 0, 0))
	_add_part(_driver_root, CapsuleMesh.new(), Vector3(0.07, 0.22, 0.07), Vector3(0.10, -0.10, -0.42), suit, Vector3(deg_to_rad(10), 0, 0))

	# Steering wheel (torus) — rotates with steer angle.
	_steer_wheel = Node3D.new()
	_steer_wheel.name = "SteeringWheel"
	_steer_wheel.position = Vector3(0.28, 0.92, -0.18)
	_steer_wheel.rotation_degrees = Vector3(-28, 0, 0)
	visual.add_child(_steer_wheel)
	var rim := TorusMesh.new()
	rim.inner_radius = 0.015
	rim.outer_radius = 0.17
	var rim_mi := MeshInstance3D.new()
	rim_mi.mesh = rim
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.08, 0.08, 0.09)
	wmat.roughness = 0.4
	wmat.metallic = 0.2
	rim_mi.material_override = wmat
	_steer_wheel.add_child(rim_mi)
	# Hub + spokes
	var hub := CylinderMesh.new()
	hub.top_radius = 0.035
	hub.bottom_radius = 0.035
	hub.height = 0.03
	var hub_mi := MeshInstance3D.new()
	hub_mi.mesh = hub
	hub_mi.rotation_degrees = Vector3(90, 0, 0)
	hub_mi.material_override = wmat
	_steer_wheel.add_child(hub_mi)
	for ang in [0.0, 60.0, 120.0]:
		var spoke := BoxMesh.new()
		spoke.size = Vector3(0.02, 0.14, 0.012)
		var smi := MeshInstance3D.new()
		smi.mesh = spoke
		smi.rotation_degrees = Vector3(0, 0, ang)
		smi.material_override = wmat
		_steer_wheel.add_child(smi)


func _add_part(parent: Node3D, mesh: Mesh, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> void:
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	elif mesh is SphereMesh:
		(mesh as SphereMesh).radius = size.x * 0.5
		(mesh as SphereMesh).height = size.y
	elif mesh is CapsuleMesh:
		(mesh as CapsuleMesh).radius = size.x * 0.5
		(mesh as CapsuleMesh).height = maxf(size.y, size.x + 0.01)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)


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
	if is_crashed:
		return
	if event.is_action_pressed("shift_up"):
		_manual_override = true
		_change_gear(gear + 1)
	elif event.is_action_pressed("shift_down"):
		_manual_override = true
		_change_gear(gear - 1)


func _physics_process(delta: float) -> void:
	if is_crashed:
		engine_force = 0.0
		brake = 40.0
		steering = 0.0
		telemetry.emit(speed_kmh, rpm, gear, 0.0)
		return

	_read_input(delta)
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
	_apply_stability(delta)
	_update_slip_fx()
	_update_steering_wheel()
	_update_audio()
	_check_crash()
	_prev_velocity = linear_velocity
	telemetry.emit(speed_kmh, rpm, gear, slipping)


func _read_input(delta: float) -> void:
	throttle_input = Input.get_action_strength("accelerate")
	throttle_input = maxf(throttle_input, _axis_trigger(JOY_AXIS_TRIGGER_RIGHT))

	var reverse_axis := Input.get_action_strength("brake")
	reverse_axis = maxf(reverse_axis, _axis_trigger(JOY_AXIS_TRIGGER_LEFT))
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		reverse_axis = maxf(reverse_axis, 1.0)

	# Progressive steer: hold A/D accumulates; release returns. Gamepad blends toward axis.
	var key_axis := 0.0
	if Input.is_action_pressed("steer_left") or Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		key_axis -= 1.0
	if Input.is_action_pressed("steer_right") or Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		key_axis += 1.0
	key_axis = clampf(key_axis, -1.0, 1.0)

	var pad_x := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	if absf(pad_x) < 0.18:
		pad_x = 0.0
	else:
		pad_x = clampf(pad_x, -1.0, 1.0)

	if absf(pad_x) > 0.05:
		var pad_rate := steer_accumulate_rate * 1.35
		steer_input = move_toward(steer_input, pad_x, pad_rate * delta)
	elif absf(key_axis) > 0.01:
		steer_input = move_toward(steer_input, key_axis, steer_accumulate_rate * delta)
	else:
		steer_input = move_toward(steer_input, 0.0, steer_return_rate * delta)
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

	# Soft-cap and smooth torque to avoid sudden rear snap.
	wheel_force = clampf(wheel_force, -MAX_ENGINE_FORCE, MAX_ENGINE_FORCE)
	_engine_force_smoothed = lerpf(_engine_force_smoothed, wheel_force, 1.0 - exp(-delta * 7.0))
	engine_force = _engine_force_smoothed


func _apply_steering(delta: float) -> void:
	var speed_factor := clampf(absf(speed_kmh) / 170.0, 0.0, 1.0)
	var max_steer := lerpf(max_steer_angle, min_steer_angle, speed_factor)
	# VehicleBody3D: positive steering rotates +Y = turn LEFT (vehicle faces -Z).
	# steer_input negative on A / positive on D, so negate.
	var target := -steer_input * max_steer
	# Rate-limit the VehicleBody steer so it cannot slam full lock in one frame.
	var steer_rate := lerpf(7.5, 4.2, speed_factor)
	steering = lerp_angle(steering, target, 1.0 - exp(-delta * steer_rate))


func _apply_brakes() -> void:
	var front := brake_input * brake_force * 0.64
	var rear := brake_input * brake_force * 0.36
	rear += handbrake_input * handbrake_force
	wheel_fl.brake = front
	wheel_fr.brake = front
	wheel_bl.brake = rear
	wheel_br.brake = rear
	# Handbrake reduces rear grip, but never to ice — avoid 180° spins.
	var rear_grip := lerpf(4.55, 2.35, handbrake_input)
	wheel_bl.wheel_friction_slip = rear_grip
	wheel_br.wheel_friction_slip = rear_grip
	brake = brake_input * 2.0


func _apply_weight_transfer() -> void:
	var local_vel := global_transform.basis.inverse() * linear_velocity
	var long_a := clampf((-local_vel.z) * 0.018 + engine_force * 0.00003 - brake_input * 0.32, -1.0, 1.0)
	var lat_a := clampf(local_vel.x * 0.028, -1.0, 1.0)
	center_of_mass = Vector3(lat_a * 0.06, -0.32 - long_a * 0.03, 0.06 - long_a * 0.10)


func _apply_aero(speed_ms: float) -> void:
	var v2 := speed_ms * speed_ms
	apply_central_force(Vector3.DOWN * v2 * 3.8)
	apply_central_force(global_transform.basis.z * v2 * 0.30 * signf(speed_ms))


func _apply_anti_roll(_delta: float) -> void:
	var up := global_transform.basis.y
	var tilt := up.cross(Vector3.UP)
	var amount := tilt.length()
	if amount > 0.02 and up.dot(Vector3.UP) > 0.25:
		apply_torque(tilt.normalized() * amount * 6200.0)


func _apply_stability(delta: float) -> void:
	# Soft yaw-rate cap that tightens with speed.
	var max_yaw := lerpf(MAX_YAW_RATE, 1.15, clampf(absf(speed_kmh) / 160.0, 0.0, 1.0))
	if absf(angular_velocity.y) > max_yaw:
		angular_velocity.y = signf(angular_velocity.y) * max_yaw

	# Extra yaw damping + torque cut when rear grip is gone.
	if slipping > 0.28 and absf(speed_kmh) > 12.0:
		var damp_k := clampf((slipping - 0.28) / 0.5, 0.0, 1.0)
		angular_velocity.y = lerpf(angular_velocity.y, 0.0, 1.0 - exp(-delta * (3.5 + damp_k * 7.0)))
		engine_force *= lerpf(1.0, 0.28, damp_k)
		# Counter-steer assist when spinning opposite to wheel steer.
		if signf(angular_velocity.y) == signf(steering) and absf(steering) > 0.05:
			angular_velocity.y *= 0.92


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


func _update_steering_wheel() -> void:
	if _steer_wheel == null:
		return
	# Visual wheel rotates with steer; ~450° lock-to-lock feel scaled to max_steer.
	var wheel_deg := rad_to_deg(steering) * (450.0 / rad_to_deg(max_steer_angle))
	_steer_wheel.rotation.z = deg_to_rad(wheel_deg)


func _check_crash() -> void:
	# Freefall past the cliff rim / deep void.
	if global_position.y < -6.0:
		_trigger_crash()
		return
	# High delta-v impact (landing after freefall, barrier smash).
	var delta_v := (_prev_velocity - linear_velocity).length()
	if delta_v > 24.0 and _prev_velocity.length() > 10.0:
		_trigger_crash()
		return
	# Hard downward slam after airborne.
	if _prev_velocity.y < -16.0 and linear_velocity.y > _prev_velocity.y + 8.0:
		_trigger_crash()


func _on_body_entered(body: Node) -> void:
	if is_crashed:
		return
	if body is StaticBody3D and (body as StaticBody3D).name == "CrashFloor":
		_trigger_crash()
		return
	# Fast hits against barriers / world.
	if linear_velocity.length() > 28.0 and body is StaticBody3D:
		var name_s := (body as StaticBody3D).name
		if name_s == "OuterBarrier" or name_s == "CrashFloor":
			_trigger_crash()


func _trigger_crash() -> void:
	if is_crashed:
		return
	is_crashed = true
	engine_force = 0.0
	brake = 60.0
	steering = 0.0
	linear_velocity *= 0.35
	angular_velocity *= 0.4
	# Freeze shortly after impact so the car limps then locks.
	if _crash_smoke:
		_crash_smoke.emitting = true
	for mi in _damage_overlays:
		mi.visible = true
	_play_crash_sound()
	if engine_player:
		engine_player.stop()
	crashed.emit()
	get_tree().create_timer(0.35).timeout.connect(func():
		if is_crashed:
			freeze = true
	)


func _play_crash_sound() -> void:
	if _crash_audio == null:
		return
	var paths := [
		"res://assets/audio/crash_metal_0.ogg",
		"res://assets/audio/crash_metal_1.ogg",
		"res://assets/audio/crash_plate_0.ogg",
	]
	var path: String = paths[randi() % paths.size()]
	var stream: AudioStream = load(path)
	if stream:
		_crash_audio.stream = stream
		_crash_audio.pitch_scale = randf_range(0.9, 1.08)
		_crash_audio.volume_db = -2.0
		_crash_audio.play()


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
