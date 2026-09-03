extends Node3D
class_name WorldBuilder

## Builds a closed asphalt circuit, grass, HDRI sky, and CC0 props.

var spawn_transform: Transform3D = Transform3D.IDENTITY

const TRACK_HALF_WIDTH := 6.2
const CURB_WIDTH := 0.45
const SEGMENTS := 280

func build() -> void:
	_setup_environment()
	var centerline := _make_centerline()
	_build_ground()
	_build_track(centerline)
	_place_props(centerline)
	_place_parked_cars(centerline)
	_compute_spawn(centerline)


func _setup_environment() -> void:
	var hdri: Texture2D = load("res://assets/hdri/kloofendal_43d_clear_2k.hdr")
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = hdri
	sky_mat.energy_multiplier = 1.05
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.75
	env.ambient_light_energy = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.8
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.82, 0.92)
	env.fog_density = 0.00055
	env.fog_aerial_perspective = 0.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	sun.light_specular = 0.7
	add_child(sun)


func _make_centerline() -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in SEGMENTS:
		var a := float(i) / float(SEGMENTS) * TAU
		var rx := 82.0
		var rz := 52.0
		var pwr := 0.42
		var x := rx * signf(cos(a)) * pow(absf(cos(a)), pwr)
		var z := rz * signf(sin(a)) * pow(absf(sin(a)), pwr)
		# Infield kink / chicane on the southern straight
		var ch := smoothstep(3.2, 3.55, a) * (1.0 - smoothstep(4.55, 4.9, a))
		x += sin(a * 7.0) * 9.0 * ch
		z += cos(a * 3.5) * 3.0 * ch
		var y := 0.18 + 1.4 * sin(a * 2.0) * 0.55 + 0.35 * sin(a * 5.0)
		pts.append(Vector3(x, y, z))
	return pts


func _frame_at(pts: PackedVector3Array, i: int) -> Dictionary:
	var n := pts.size()
	var p: Vector3 = pts[i]
	var prev: Vector3 = pts[(i - 1 + n) % n]
	var nxt: Vector3 = pts[(i + 1) % n]
	var tangent: Vector3 = (nxt - prev)
	tangent.y = 0.0
	if tangent.length() < 0.0001:
		tangent = Vector3.FORWARD
	tangent = tangent.normalized()
	var right: Vector3 = Vector3.UP.cross(tangent).normalized()
	var up: Vector3 = tangent.cross(right).normalized()
	return {"p": p, "tangent": tangent, "right": right, "up": up}


func _build_ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(420, 420)
	mesh.subdivide_width = 8
	mesh.subdivide_depth = 8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position.y = 0.0
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/aerial_grass_rock_diff_1k.jpg")
	mat.normal_enabled = true
	mat.normal_texture = load("res://assets/textures/aerial_grass_rock_nor_gl_1k.jpg")
	mat.roughness_texture = load("res://assets/textures/aerial_grass_rock_rough_1k.jpg")
	mat.uv1_scale = Vector3(42, 42, 1)
	mat.roughness = 1.0
	mi.material_override = mat
	add_child(mi)

	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(420, 1.0, 420)
	col.shape = box
	col.position.y = -0.5
	body.add_child(col)
	add_child(body)


func _build_track(pts: PackedVector3Array) -> void:
	var n := pts.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var asphalt: StandardMaterial3D = StandardMaterial3D.new()
	asphalt.albedo_texture = load("res://assets/textures/asphalt_02_diff_1k.jpg")
	asphalt.normal_enabled = true
	asphalt.normal_texture = load("res://assets/textures/asphalt_02_nor_gl_1k.jpg")
	asphalt.roughness_texture = load("res://assets/textures/asphalt_02_rough_1k.jpg")
	asphalt.uv1_scale = Vector3(1, 1, 1)
	asphalt.roughness = 0.85

	var dist := 0.0
	for i in n:
		var a := _frame_at(pts, i)
		var b := _frame_at(pts, (i + 1) % n)
		var w := TRACK_HALF_WIDTH
		var a_l: Vector3 = a["p"] - a["right"] * w + a["up"] * 0.04
		var a_r: Vector3 = a["p"] + a["right"] * w + a["up"] * 0.04
		var b_l: Vector3 = b["p"] - b["right"] * w + b["up"] * 0.04
		var b_r: Vector3 = b["p"] + b["right"] * w + b["up"] * 0.04
		var step: float = (b["p"] as Vector3).distance_to(a["p"])
		var uv_y0 := dist * 0.12
		var uv_y1 := (dist + step) * 0.12
		_quad(st, a_l, a_r, b_r, b_l, Vector2(0, uv_y0), Vector2(1, uv_y0), Vector2(1, uv_y1), Vector2(0, uv_y1))
		dist += step

	st.generate_normals()
	st.generate_tangents()
	var road_mesh := st.commit()
	var road_mi := MeshInstance3D.new()
	road_mi.mesh = road_mesh
	road_mi.material_override = asphalt
	add_child(road_mi)

	var road_body := StaticBody3D.new()
	var road_col := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(road_mesh.get_faces())
	road_col.shape = concave
	road_body.add_child(road_col)
	add_child(road_body)

	_build_curbs(pts)
	_build_center_line(pts)
	_build_start_finish(pts)
	_build_walls(pts)


func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, uv0: Vector2, uv1: Vector2, uv2: Vector2, uv3: Vector2) -> void:
	st.set_uv(uv0)
	st.add_vertex(p0)
	st.set_uv(uv1)
	st.add_vertex(p1)
	st.set_uv(uv2)
	st.add_vertex(p2)
	st.set_uv(uv0)
	st.add_vertex(p0)
	st.set_uv(uv2)
	st.add_vertex(p2)
	st.set_uv(uv3)
	st.add_vertex(p3)


func _build_curbs(pts: PackedVector3Array) -> void:
	var n := pts.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dist := 0.0
	for i in n:
		var a := _frame_at(pts, i)
		var b := _frame_at(pts, (i + 1) % n)
		var step: float = (b["p"] as Vector3).distance_to(a["p"])
		var stripe := 1.0 if int(dist / 2.4) % 2 == 0 else 0.0
		var col := Color(0.92, 0.12, 0.16) if stripe > 0.5 else Color(0.95, 0.95, 0.95)
		for side in [-1.0, 1.0]:
			var inner_a: Vector3 = a["p"] + a["right"] * side * (TRACK_HALF_WIDTH - 0.05) + a["up"] * 0.055
			var outer_a: Vector3 = a["p"] + a["right"] * side * (TRACK_HALF_WIDTH + CURB_WIDTH) + a["up"] * 0.07
			var inner_b: Vector3 = b["p"] + b["right"] * side * (TRACK_HALF_WIDTH - 0.05) + b["up"] * 0.055
			var outer_b: Vector3 = b["p"] + b["right"] * side * (TRACK_HALF_WIDTH + CURB_WIDTH) + b["up"] * 0.07
			st.set_color(col)
			if side > 0.0:
				_quad(st, inner_a, outer_a, outer_b, inner_b, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
			else:
				_quad(st, outer_a, inner_a, inner_b, outer_b, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
		dist += step
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.45
	mi.material_override = mat
	add_child(mi)


func _build_center_line(pts: PackedVector3Array) -> void:
	var n := pts.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dist := 0.0
	var dash := true
	var acc := 0.0
	for i in n:
		var a := _frame_at(pts, i)
		var b := _frame_at(pts, (i + 1) % n)
		var step: float = (b["p"] as Vector3).distance_to(a["p"])
		acc += step
		if acc > 4.0:
			dash = not dash
			acc = 0.0
		if dash:
			var hw := 0.08
			var a_l: Vector3 = a["p"] - a["right"] * hw + a["up"] * 0.06
			var a_r: Vector3 = a["p"] + a["right"] * hw + a["up"] * 0.06
			var b_l: Vector3 = b["p"] - b["right"] * hw + b["up"] * 0.06
			var b_r: Vector3 = b["p"] + b["right"] * hw + a["up"] * 0.06
			st.set_color(Color(0.95, 0.92, 0.55))
			_quad(st, a_l, a_r, b_r, b_l, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
		dist += step
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.6
	mi.material_override = mat
	add_child(mi)


func _build_start_finish(pts: PackedVector3Array) -> void:
	var a := _frame_at(pts, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := TRACK_HALF_WIDTH - 0.2
	var depth := 2.4
	var p0: Vector3 = a["p"] - a["right"] * w - a["tangent"] * depth + a["up"] * 0.07
	var p1: Vector3 = a["p"] + a["right"] * w - a["tangent"] * depth + a["up"] * 0.07
	var p2: Vector3 = a["p"] + a["right"] * w + a["tangent"] * 0.2 + a["up"] * 0.07
	var p3: Vector3 = a["p"] - a["right"] * w + a["tangent"] * 0.2 + a["up"] * 0.07
	_quad(st, p0, p1, p2, p3, Vector2(0, 0), Vector2(8, 0), Vector2(8, 1), Vector2(0, 1))
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/checker.png")
	mat.uv1_scale = Vector3(1, 1, 1)
	mi.material_override = mat
	add_child(mi)


func _build_walls(pts: PackedVector3Array) -> void:
	var n := pts.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var height := 1.15
	var thick := 0.28
	var offset := TRACK_HALF_WIDTH + CURB_WIDTH + 0.35
	for i in n:
		var a := _frame_at(pts, i)
		var b := _frame_at(pts, (i + 1) % n)
		for side in [-1.0, 1.0]:
			var a0: Vector3 = a["p"] + a["right"] * side * offset
			var a1: Vector3 = a["p"] + a["right"] * side * (offset + thick)
			var b0: Vector3 = b["p"] + b["right"] * side * offset
			var b1: Vector3 = b["p"] + b["right"] * side * (offset + thick)
			a0.y = a["p"].y
			a1.y = a["p"].y
			b0.y = b["p"].y
			b1.y = b["p"].y
			var a0t := a0 + Vector3.UP * height
			var a1t := a1 + Vector3.UP * height
			var b0t := b0 + Vector3.UP * height
			var b1t := b1 + Vector3.UP * height
			st.set_color(Color(0.82, 0.82, 0.84))
			_quad(st, a0, b0, b0t, a0t, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
			_quad(st, a1, a1t, b1t, b1, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
			_quad(st, a0t, b0t, b1t, a1t, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.5
	mat.metallic = 0.05
	mi.material_override = mat
	add_child(mi)

	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(mesh.get_faces())
	col.shape = concave
	body.add_child(col)
	add_child(body)


func _spawn_model(path: String, pos: Vector3, rot_y: float, scl: float) -> Node3D:
	var res: Resource = load(path)
	if res == null:
		return null
	var node: Node3D
	if res is PackedScene:
		node = (res as PackedScene).instantiate()
	elif res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res
		node = mi
	else:
		return null
	add_child(node)
	node.global_position = pos
	node.rotation.y = rot_y
	node.scale = Vector3.ONE * scl
	return node


func _place_props(pts: PackedVector3Array) -> void:
	var n := pts.size()
	var trees := [
		"res://assets/models/nature/tree_oak.glb",
		"res://assets/models/nature/tree_detailed.glb",
		"res://assets/models/nature/tree_default.glb",
		"res://assets/models/nature/tree_pineDefaultA.glb",
		"res://assets/models/nature/tree_pineTallA_detailed.glb",
		"res://assets/models/nature/tree_cone.glb",
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260903

	# Trees around the outside
	for i in 70:
		var idx := rng.randi_range(0, n - 1)
		var f := _frame_at(pts, idx)
		var side := 1.0 if rng.randf() > 0.5 else -1.0
		var dist := rng.randf_range(16.0, 46.0)
		var pos: Vector3 = f["p"] + f["right"] * side * dist
		pos.y = 0.0
		var path: String = trees[rng.randi_range(0, trees.size() - 1)]
		_spawn_model(path, pos, rng.randf() * TAU, rng.randf_range(1.6, 2.6))

	# Bushes
	for i in 40:
		var idx := rng.randi_range(0, n - 1)
		var f := _frame_at(pts, idx)
		var side := 1.0 if rng.randf() > 0.5 else -1.0
		var pos: Vector3 = f["p"] + f["right"] * side * rng.randf_range(12.0, 22.0)
		pos.y = 0.0
		var bush := "res://assets/models/nature/plant_bushLarge.glb" if rng.randf() > 0.5 else "res://assets/models/nature/plant_bush.glb"
		_spawn_model(bush, pos, rng.randf() * TAU, rng.randf_range(1.4, 2.2))

	# Rocks
	for i in 18:
		var idx := rng.randi_range(0, n - 1)
		var f := _frame_at(pts, idx)
		var pos: Vector3 = f["p"] + f["right"] * (1.0 if rng.randf() > 0.5 else -1.0) * rng.randf_range(18.0, 40.0)
		pos.y = 0.0
		var rock := "res://assets/models/nature/rock_largeA.glb" if rng.randf() > 0.4 else "res://assets/models/nature/rock_smallA.glb"
		_spawn_model(rock, pos, rng.randf() * TAU, rng.randf_range(1.5, 3.0))

	# Cones near start
	for i in 12:
		var f := _frame_at(pts, (2 + i) % n)
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos: Vector3 = f["p"] + f["right"] * side * (TRACK_HALF_WIDTH - 1.1)
		pos.y = f["p"].y + 0.02
		_spawn_model("res://assets/models/props/cone.glb", pos, f["tangent"].signed_angle_to(Vector3.FORWARD, Vector3.UP), 1.0)

	# Barriers / pylons / lights / grandstand along the main straight
	for i in range(0, 24, 2):
		var f := _frame_at(pts, i)
		var yaw := Vector3.FORWARD.signed_angle_to(f["tangent"], Vector3.UP)
		var pos_l: Vector3 = f["p"] - f["right"] * (TRACK_HALF_WIDTH + 1.6)
		pos_l.y = f["p"].y
		_spawn_model("res://assets/models/track/barrierRed.obj", pos_l, yaw, 1.8)
		if i % 4 == 0:
			var pos_r: Vector3 = f["p"] + f["right"] * (TRACK_HALF_WIDTH + 1.7)
			pos_r.y = f["p"].y
			_spawn_model("res://assets/models/track/pylon.obj", pos_r, yaw, 1.6)

	var start := _frame_at(pts, 8)
	var gs_pos: Vector3 = start["p"] + start["right"] * 18.0
	gs_pos.y = 0.0
	var yaw_s := Vector3.FORWARD.signed_angle_to(start["tangent"], Vector3.UP)
	_spawn_model("res://assets/models/track/grandStand.obj", gs_pos, yaw_s + PI, 2.4)
	_spawn_model("res://assets/models/track/flagCheckers.obj", start["p"] - start["right"] * 8.5 + Vector3(0, start["p"].y, 0), yaw_s, 1.8)
	_spawn_model("res://assets/models/track/lightPostLarge.obj", start["p"] + start["right"] * (TRACK_HALF_WIDTH + 2.5), yaw_s, 1.5)
	_spawn_model("res://assets/models/track/rail.obj", start["p"] + start["right"] * 14.0, yaw_s, 2.0)


func _place_parked_cars(pts: PackedVector3Array) -> void:
	var cars := [
		"res://assets/models/cars/hatchback-sports.glb",
		"res://assets/models/cars/suv.glb",
		"res://assets/models/cars/taxi.glb",
		"res://assets/models/cars/police.glb",
		"res://assets/models/cars/race.glb",
	]
	var f := _frame_at(pts, 12)
	for i in cars.size():
		var pos: Vector3 = f["p"] - f["right"] * (16.0 + float(i) * 3.2) - f["tangent"] * 6.0
		pos.y = 0.0
		var yaw := Vector3.FORWARD.signed_angle_to(f["tangent"], Vector3.UP) + PI * 0.5
		var node := _spawn_model(cars[i], pos, yaw, 1.0)
		if node:
			# Kenney cars face +Z
			node.rotate_y(PI)


func _compute_spawn(pts: PackedVector3Array) -> void:
	var f := _frame_at(pts, 2)
	var origin: Vector3 = f["p"] + Vector3.UP * 0.55
	var basis := Basis()
	# Vehicle forward is -Z, so -Z should align with tangent
	var fwd: Vector3 = f["tangent"]
	var right: Vector3 = f["right"]
	var up: Vector3 = f["up"]
	basis.x = right
	basis.y = up
	basis.z = -fwd
	basis = basis.orthonormalized()
	spawn_transform = Transform3D(basis, origin)
