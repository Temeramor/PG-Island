extends Node3D

const GRID_SIZE := 512
const TARGET_AREA_M2 := 4_000_000.0
const WATER_SIZE := 20_000.0
const CAMERA_SIZE_PER_HEIGHT := 1.28 / 1.8
const CAMERA_MIN_HEIGHT := 500.0
const CAMERA_MAX_HEIGHT := 12_000.0
const CAMERA_MOVE_FACTOR := 0.65
const MOUSE_LOOK_SENSITIVITY := 0.004
const CAMERA_MIN_PITCH := -1.48
const CAMERA_MAX_PITCH := -0.12

var island_mesh_instance: MeshInstance3D
var camera: Camera3D
var camera_pivot: Node3D
var rotating_camera := false
var info_label: Label
var generation_number := 0

func _ready() -> void:
	_create_world()
	_create_camera()
	_create_hud()
	generate_island()

func _process(delta: float) -> void:
	if camera == null:
		return
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		move.z += 1.0
	if Input.is_key_pressed(KEY_A):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		move.x += 1.0
	if move.length_squared() > 0.0:
		move = move.normalized()
		var horizontal_speed := camera.size * CAMERA_MOVE_FACTOR
		camera_pivot.position.x += move.x * horizontal_speed * delta
		camera_pivot.position.z += move.z * horizontal_speed * delta

	var vertical := 0.0
	if Input.is_key_pressed(KEY_SPACE):
		vertical += 1.0
	if Input.is_key_pressed(KEY_SHIFT):
		vertical -= 1.0
	if vertical != 0.0:
		var vertical_speed := camera.position.z * CAMERA_MOVE_FACTOR
		camera.position.z = clampf(camera.position.z + vertical * vertical_speed * delta, CAMERA_MIN_HEIGHT, CAMERA_MAX_HEIGHT)
		# Orthographic projection: changing altitude also changes map scale.
		camera.size = camera.position.z * CAMERA_SIZE_PER_HEIGHT
		camera.far = camera.position.z + 5000.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		rotating_camera = event.pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and rotating_camera:
		camera_pivot.rotation.y -= event.relative.x * MOUSE_LOOK_SENSITIVITY
		camera_pivot.rotation.x = clampf(camera_pivot.rotation.x - event.relative.y * MOUSE_LOOK_SENSITIVITY, CAMERA_MIN_PITCH, CAMERA_MAX_PITCH)
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		generate_island()
		get_viewport().set_input_as_handled()

func _create_world() -> void:
	var environment := WorldEnvironment.new()
	var world := Environment.new()
	world.background_mode = Environment.BG_COLOR
	world.background_color = Color(0.055, 0.22, 0.31)
	world.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.ambient_light_color = Color(0.72, 0.82, 0.91)
	world.ambient_light_energy = 0.8
	environment.environment = world
	add_child(environment)

	var water := MeshInstance3D.new()
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2(WATER_SIZE, WATER_SIZE)
	water.mesh = water_mesh
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(0.055, 0.22, 0.31)
	water_material.roughness = 0.82
	water_material.metallic = 0.05
	water.material_override = water_material
	water.position.y = -2.0
	add_child(water)

	island_mesh_instance = MeshInstance3D.new()
	add_child(island_mesh_instance)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)

func _create_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.rotation.x = -PI * 0.5
	add_child(camera_pivot)

	camera = Camera3D.new()
	camera.name = "SurveyCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(0.0, 0.0, 6000.0)
	camera.current = true
	camera_pivot.add_child(camera)

func _create_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)

	var heading := Label.new()
	heading.text = "ISLAND SURVEY  /  PROCEDURAL STUDY"
	heading.add_theme_font_size_override("font_size", 17)
	heading.add_theme_color_override("font_color", Color(0.88, 0.94, 0.94))
	column.add_child(heading)

	info_label = Label.new()
	info_label.text = "Generating landmass..."
	info_label.add_theme_font_size_override("font_size", 13)
	info_label.add_theme_color_override("font_color", Color(0.65, 0.78, 0.8))
	column.add_child(info_label)

	var hint := Label.new()
	hint.text = "WASD — move    RMB + drag — orbit    SPACE / SHIFT — altitude    R — regenerate"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.9, 0.72, 0.43))
	column.add_child(hint)

func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.075, 0.09, 0.88)
	style.border_color = Color(0.25, 0.43, 0.45, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	return style

func generate_island() -> void:
	generation_number += 1
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var aspect := rng.randf_range(0.58, 1.55)
	var angle := rng.randf_range(0.0, TAU)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = rng.randf_range(0.012, 0.021)
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.48

	var warp := FastNoiseLite.new()
	warp.seed = rng.randi()
	warp.noise_type = FastNoiseLite.TYPE_SIMPLEX
	warp.frequency = 0.009

	var notch_count := rng.randi_range(1, 4)
	var notches: Array[Dictionary] = []
	for i in range(notch_count):
		var direction := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(0.28, 0.76)
		notches.append({
			"center": Vector2(cos(direction), sin(direction)) * radius,
			"width": rng.randf_range(0.10, 0.24),
			"depth": rng.randf_range(0.28, 0.72)
		})

	var values := PackedFloat32Array()
	values.resize(GRID_SIZE * GRID_SIZE)
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var p := Vector2(
				(float(x) / float(GRID_SIZE - 1) - 0.5) * 2.0,
				(float(y) / float(GRID_SIZE - 1) - 0.5) * 2.0
			)
			var rotated := Vector2(
				p.x * cos(angle) - p.y * sin(angle),
				p.x * sin(angle) + p.y * cos(angle)
			)
			rotated.x /= aspect
			var wx := warp.get_noise_2d(float(x) + 31.0, float(y) - 17.0)
			var wy := warp.get_noise_2d(float(x) - 83.0, float(y) + 59.0)
			var q := rotated + Vector2(wx, wy) * 0.12

			var radial := sqrt(q.x * q.x + q.y * q.y)
			var field := 1.0 - radial
			field += noise.get_noise_2d(float(x), float(y)) * 0.19

			for cut in notches:
				var delta: Vector2 = q - cut.center
				var width: float = cut.width
				var bite := exp(-delta.length_squared() / (2.0 * width * width))
				field -= bite * float(cut.depth)

			# Small-scale coastal detail, not elevation.
			field += noise.get_noise_2d(float(x) * 2.7 + 400.0, float(y) * 2.7 - 200.0) * 0.035
			values[y * GRID_SIZE + x] = field

	var sorted_values := values.duplicate()
	sorted_values.sort()
	var target_cells := int(float(GRID_SIZE * GRID_SIZE) * rng.randf_range(0.18, 0.34))
	var threshold := sorted_values[sorted_values.size() - target_cells]

	var land := PackedByteArray()
	land.resize(values.size())
	var land_count := 0
	for i in range(values.size()):
		if values[i] >= threshold:
			land[i] = 1
			land_count += 1

	# Each occupied grid cell has the same area; this scale makes their
	# combined horizontal area exactly 4,000,000 square metres.
	var cell_size := sqrt(TARGET_AREA_M2 / float(land_count))
	# Three independent noise bands: geological mass, mountain structure, and detail.
	var macro_noise := _make_noise(rng.randi(), 0.0032, 4, 0.52)
	var hill_noise := _make_noise(rng.randi(), 0.009, 4, 0.48)
	var ridge_noise := _make_noise(rng.randi(), 0.015, 3, 0.5)
	var detail_noise := _make_noise(rng.randi(), 0.045, 2, 0.45)
	var warp_x := _make_noise(rng.randi(), 0.0045, 3, 0.5)
	var warp_y := _make_noise(rng.randi(), 0.0045, 3, 0.5)
	var mountain_angle := rng.randf_range(0.0, TAU)
	var mountain_offset := Vector2(rng.randf_range(-250.0, 250.0), rng.randf_range(-250.0, 250.0))
	var mesh := _build_terrain_mesh(land, cell_size, macro_noise, hill_noise, ridge_noise, detail_noise, warp_x, warp_y, mountain_angle, mountain_offset)
	island_mesh_instance.mesh = mesh

	var land_material := StandardMaterial3D.new()
	land_material.vertex_color_use_as_albedo = true
	land_material.roughness = 1.0
	land_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	island_mesh_instance.material_override = land_material

	var extent := float(GRID_SIZE) * cell_size
	camera.size = extent * 1.28
	camera_pivot.position = Vector3.ZERO
	camera_pivot.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	camera.position = Vector3(0.0, 0.0, maxf(extent * 1.8, 2500.0))
	camera.far = camera.position.z + 5000.0

	info_label.text = "LAND AREA  4.00 km²    /    GRID  %d²    /    STUDY  %03d" % [GRID_SIZE, generation_number]

func _make_noise(seed_value: int, frequency_value: float, octaves: int, gain: float) -> FastNoiseLite:
	var result := FastNoiseLite.new()
	result.seed = seed_value
	result.noise_type = FastNoiseLite.TYPE_SIMPLEX
	result.frequency = frequency_value
	result.fractal_type = FastNoiseLite.FRACTAL_FBM
	result.fractal_octaves = octaves
	result.fractal_lacunarity = 2.0
	result.fractal_gain = gain
	return result

func _height_at(p: Vector2, macro_noise: FastNoiseLite, hill_noise: FastNoiseLite, ridge_noise: FastNoiseLite, detail_noise: FastNoiseLite, warp_x: FastNoiseLite, warp_y: FastNoiseLite, mountain_angle: float, mountain_offset: Vector2) -> float:
	# Warp broad and medium coordinates; keep fine detail stable.
	var warp := Vector2(warp_x.get_noise_2d(p.x, p.y), warp_y.get_noise_2d(p.x + 173.0, p.y - 91.0)) * 105.0
	var q := p + warp
	var macro := macro_noise.get_noise_2d(q.x, q.y)
	var hills := hill_noise.get_noise_2d(q.x * 1.15, q.y * 1.15)
	var rotated := Vector2(q.x * cos(mountain_angle) - q.y * sin(mountain_angle), q.x * sin(mountain_angle) + q.y * cos(mountain_angle)) - mountain_offset
	var mountain_envelope := exp(-pow(rotated.x / 520.0, 2.0) - pow(rotated.y / 260.0, 2.0))
	var ridge_sample := ridge_noise.get_noise_2d(q.x * 0.72 + warp.x * 0.35, q.y * 0.72 + warp.y * 0.35)
	var ridges := pow(1.0 - absf(ridge_sample), 2.4)
	var elevation := 115.0 + macro * 135.0 + hills * 78.0
	elevation += mountain_envelope * ridges * 720.0
	elevation += detail_noise.get_noise_2d(p.x, p.y) * 13.0
	return maxf(elevation, 8.0)

func _height_color(height: float) -> Color:
	if height < 90.0:
		return Color(0.39, 0.52, 0.34).lerp(Color(0.48, 0.56, 0.36), clampf(height / 90.0, 0.0, 1.0))
	if height < 300.0:
		return Color(0.48, 0.56, 0.36).lerp(Color(0.53, 0.49, 0.34), (height - 90.0) / 210.0)
	if height < 700.0:
		return Color(0.53, 0.49, 0.34).lerp(Color(0.43, 0.43, 0.39), (height - 300.0) / 400.0)
	return Color(0.43, 0.43, 0.39).lerp(Color(0.82, 0.84, 0.82), clampf((height - 700.0) / 250.0, 0.0, 1.0))

func _corner_land_weight(land: PackedByteArray, x: int, y: int) -> float:
	var count := 0
	for oy in range(-1, 1):
		for ox in range(-1, 1):
			var cx := x + ox
			var cy := y + oy
			if cx >= 0 and cx < GRID_SIZE and cy >= 0 and cy < GRID_SIZE and land[cy * GRID_SIZE + cx] == 1:
				count += 1
	return float(count) / 4.0

func _build_terrain_mesh(land: PackedByteArray, cell_size: float, macro_noise: FastNoiseLite, hill_noise: FastNoiseLite, ridge_noise: FastNoiseLite, detail_noise: FastNoiseLite, warp_x: FastNoiseLite, warp_y: FastNoiseLite, mountain_angle: float, mountain_offset: Vector2) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_extent := float(GRID_SIZE) * cell_size * 0.5
	var height_cache: Dictionary = {}
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			if land[y * GRID_SIZE + x] == 0:
				continue
			var x0 := float(x) * cell_size - half_extent
			var x1 := x0 + cell_size
			var z0 := float(y) * cell_size - half_extent
			var z1 := z0 + cell_size
			var corner_heights: Array[float] = []
			var corner_colors: Array[Color] = []
			var corners := [Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x + 1, y + 1), Vector2i(x, y + 1)]
			for corner in corners:
				var key := Vector2i(corner.x, corner.y)
				var h: float
				if height_cache.has(key):
					h = float(height_cache[key])
				else:
					var p := Vector2(float(corner.x) - GRID_SIZE * 0.5, float(corner.y) - GRID_SIZE * 0.5) * 18.0
					h = _height_at(p, macro_noise, hill_noise, ridge_noise, detail_noise, warp_x, warp_y, mountain_angle, mountain_offset)
					h *= _corner_land_weight(land, corner.x, corner.y)
					height_cache[key] = h
				corner_heights.append(h)
				corner_colors.append(_height_color(h))
			var a := Vector3(x0, corner_heights[0], z0)
			var b := Vector3(x1, corner_heights[1], z0)
			var c := Vector3(x1, corner_heights[2], z1)
			var d := Vector3(x0, corner_heights[3], z1)
			surface.set_color(corner_colors[0]); surface.add_vertex(a)
			surface.set_color(corner_colors[2]); surface.add_vertex(c)
			surface.set_color(corner_colors[1]); surface.add_vertex(b)
			surface.set_color(corner_colors[0]); surface.add_vertex(a)
			surface.set_color(corner_colors[3]); surface.add_vertex(d)
			surface.set_color(corner_colors[2]); surface.add_vertex(c)
	surface.generate_normals()
	return surface.commit()
