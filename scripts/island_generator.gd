extends Node3D

const GRID_SIZE := 512
const TARGET_AREA_M2 := 4_000_000.0
const WATER_SIZE := 20_000.0

var island_mesh_instance: MeshInstance3D
var camera: Camera3D
var info_label: Label
var generation_number := 0

func _ready() -> void:
	_create_world()
	_create_camera()
	_create_hud()
	generate_island()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		generate_island()
		get_viewport().set_input_as_handled()

func _create_world() -> void:
	var environment := WorldEnvironment.new()
	var world := Environment.new()
	world.background_mode = Environment.BG_SKY
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
	add_child(sun)

func _create_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(0.0, 6000.0, 0.0)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	camera.current = true
	add_child(camera)

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
	hint.text = "R  —  regenerate island"
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
	var mesh := _build_flat_land_mesh(land, cell_size)
	island_mesh_instance.mesh = mesh

	var land_material := StandardMaterial3D.new()
	land_material.albedo_color = Color(0.48, 0.57, 0.43)
	land_material.roughness = 1.0
	land_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	island_mesh_instance.material_override = land_material

	var extent := float(GRID_SIZE) * cell_size
	camera.size = extent * 1.28
	camera.position = Vector3(0.0, maxf(extent * 1.8, 2500.0), 0.0)
	camera.far = camera.position.y + 5000.0

	info_label.text = "LAND AREA  4.00 km²    /    GRID  %d²    /    STUDY  %03d" % [GRID_SIZE, generation_number]

func _build_flat_land_mesh(land: PackedByteArray, cell_size: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_extent := float(GRID_SIZE) * cell_size * 0.5

	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			if land[y * GRID_SIZE + x] == 0:
				continue
			var x0 := float(x) * cell_size - half_extent
			var x1 := x0 + cell_size
			var z0 := float(y) * cell_size - half_extent
			var z1 := z0 + cell_size
			var a := Vector3(x0, 0.0, z0)
			var b := Vector3(x1, 0.0, z0)
			var c := Vector3(x1, 0.0, z1)
			var d := Vector3(x0, 0.0, z1)
			surface.set_normal(Vector3.UP)
			surface.add_vertex(a)
			surface.set_normal(Vector3.UP)
			surface.add_vertex(c)
			surface.set_normal(Vector3.UP)
			surface.add_vertex(b)
			surface.set_normal(Vector3.UP)
			surface.add_vertex(a)
			surface.set_normal(Vector3.UP)
			surface.add_vertex(d)
			surface.set_normal(Vector3.UP)
			surface.add_vertex(c)

	var result := surface.commit()
	return result
