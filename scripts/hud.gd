extends CanvasLayer
class_name DrivingHUD

@onready var speed_label: Label = $Root/SpeedBox/VBox/Speed
@onready var gear_label: Label = $Root/GearBox/Gear
@onready var rpm_bar: ProgressBar = $Root/RpmBox/RpmBar
@onready var rpm_text: Label = $Root/RpmBox/RpmText
@onready var cam_label: Label = $Root/CamLabel
@onready var hint: Label = $Root/Hint
@onready var tach: Tachometer = $Root/Tach


func update_telemetry(speed_kmh: float, rpm: float, gear_text: String, slipping: float) -> void:
	speed_label.text = str(int(round(absf(speed_kmh))))
	gear_label.text = gear_text
	rpm_bar.max_value = 7500.0
	rpm_bar.value = rpm
	rpm_text.text = "%d RPM" % int(rpm)
	var fill := rpm_bar.get("theme_override_styles/fill") as StyleBoxFlat
	if fill:
		if rpm > 6800.0:
			fill.bg_color = Color(0.92, 0.18, 0.22)
		elif rpm > 5400.0:
			fill.bg_color = Color(0.95, 0.72, 0.15)
		else:
			fill.bg_color = Color(0.25, 0.85, 0.55)
	if slipping > 0.55:
		gear_label.modulate = Color(1.0, 0.55, 0.35)
	else:
		gear_label.modulate = Color.WHITE
	if tach:
		tach.set_reading(rpm, gear_text, slipping)


func set_camera_name(cam_name: String) -> void:
	cam_label.text = "CAM  %s  (C)" % cam_name


func hide_hint() -> void:
	hint.visible = false
