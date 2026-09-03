extends SceneTree

## Headless check: continuous runoff, spawn, and a few physics seconds.

func _init() -> void:
	var code := 0
	var world := WorldBuilder.new()
	root.add_child(world)
	world.build()
	var pts: PackedVector3Array = world._make_centerline()
	if pts.size() < 100:
		push_error("centerline too short: %d" % pts.size())
		code = 1
	var ymin := 1e9
	var ymax := -1e9
	for p in pts:
		ymin = minf(ymin, p.y)
		ymax = maxf(ymax, p.y)
	print("centerline points=", pts.size(), " y=[", snapped(ymin, 0.01), ",", snapped(ymax, 0.01), "]")
	if ymin < 0.5:
		push_error("track dips too low (lip risk vs y=0 grass): ymin=%s" % ymin)
		code = 1
	# Shoulder must match track height (no vertical lip).
	var i := 0
	var max_lip := 0.0
	while i < pts.size():
		var f: Dictionary = world._frame_at(pts, i)
		var ty: float = f["p"].y
		var shoulder_y := world._surface_y(ty, WorldBuilder.TRACK_HALF_WIDTH + 3.0)
		var lip := absf(shoulder_y - ty)
		max_lip = maxf(max_lip, lip)
		i += 30
	print("max shoulder lip vs track: ", snapped(max_lip, 0.001), " m")
	if max_lip > 0.02:
		push_error("shoulder not coplanar with track")
		code = 1
	var apron_y := world._surface_y(2.0, WorldBuilder._APRON_END)
	print("apron outer y @ track 2.0: ", snapped(apron_y, 0.001))
	if apron_y > 0.1:
		push_error("apron does not meet grass")
		code = 1
	var mid_y := world._surface_y(2.0, WorldBuilder._APRON_START + WorldBuilder.APRON_WIDTH * 0.5)
	print("apron mid y: ", snapped(mid_y, 0.001), " (expect ~1.0)")
	if mid_y > 1.8 or mid_y < 0.4:
		push_error("apron slope not gentle")
		code = 1
	if world.spawn_transform.origin.y < 1.0:
		push_error("spawn too low")
		code = 1
	print("spawn: ", world.spawn_transform.origin)
	var driveable := world.find_child("DriveableSurface", true, false)
	if driveable == null:
		push_error("missing DriveableSurface collision")
		code = 1
	else:
		print("DriveableSurface ok")
	var inner_wall := world.find_child("InnerWall", true, false)
	if inner_wall:
		push_error("inner wall should be gone")
		code = 1
	var outer := world.find_child("OuterBarrier", true, false)
	if outer == null:
		push_error("missing OuterBarrier")
		code = 1

	# Load car, sit on spawn, step physics.
	var car_ps: PackedScene = load("res://scenes/car.tscn")
	var car: PlayerCar = car_ps.instantiate()
	root.add_child(car)
	car.set_spawn(world.spawn_transform)
	var frames := 0
	while frames < 90:
		await physics_frame
		frames += 1
	print("car after 90 ticks pos=", car.global_position, " vel=", car.linear_velocity.length())
	if car.global_position.y < 0.3:
		push_error("car fell through world")
		code = 1
	# Nudge onto the shoulder and ensure we don't drop a meter.
	var f0: Dictionary = world._frame_at(pts, 3)
	var shoulder_pos: Vector3 = f0["p"] + f0["right"] * (WorldBuilder.TRACK_HALF_WIDTH + 4.0)
	shoulder_pos.y = f0["p"].y + 0.7
	var xf := Transform3D(world.spawn_transform.basis, shoulder_pos)
	car.set_spawn(xf)
	frames = 0
	var min_y := 1e9
	while frames < 90:
		await physics_frame
		min_y = minf(min_y, car.global_position.y)
		frames += 1
	print("shoulder sit y=", car.global_position.y, " min_y=", min_y, " track_y=", f0["p"].y)
	# Body origin sits ~0.05-0.6 above surface. Must not drop to grass (y~0.1).
	if min_y < f0["p"].y - 0.4:
		push_error("car dropped off shoulder toward grass plane")
		code = 1
	if code == 0:
		print("VERIFY_OK")
	else:
		print("VERIFY_FAIL")
	quit(code)
