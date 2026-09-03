extends Node3D

@onready var world: WorldBuilder = $World
@onready var car: PlayerCar = $Car
@onready var camera: ChaseCamera = $ChaseCamera
@onready var hud: DrivingHUD = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu

var _hint_timer: float = 8.0


func _ready() -> void:
	world.build()
	car.set_spawn(world.spawn_transform)
	camera.target = car
	camera.current = true
	hud.set_camera_name(camera.mode_name())
	car.telemetry.connect(_on_telemetry)
	pause_menu.resumed.connect(_set_paused.bind(false))
	pause_menu.restarted.connect(_restart)
	pause_menu.quit_requested.connect(func(): get_tree().quit())


func _process(delta: float) -> void:
	if _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			hud.hide_hint()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reset") and not get_tree().paused:
		_restart()
	elif event.is_action_pressed("camera_toggle") and not get_tree().paused:
		camera.toggle_mode()
		hud.set_camera_name(camera.mode_name())
	elif event.is_action_pressed("toggle_fullscreen"):
		var mode := DisplayServer.window_get_mode()
		if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _on_telemetry(speed_kmh: float, rpm: float, gear: int, slipping: float) -> void:
	var g := "R" if gear == 0 else str(gear)
	hud.update_telemetry(speed_kmh, rpm, g, slipping)


func _set_paused(p: bool) -> void:
	get_tree().paused = p
	if p:
		pause_menu.show_menu()
	else:
		pause_menu.hide_menu()


func _restart() -> void:
	_set_paused(false)
	car.reset_vehicle()
