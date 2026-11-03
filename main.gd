extends Node3D
## Procedural island scene: generated terrain, ocean, sky and free-fly camera.
## Controls: RMB + mouse = look, WASD = move, Q/E = down/up, Shift = fast,
## mouse wheel = speed, R = new island, Esc = release mouse.

@export var terrain_size := 3600.0
@export var subdivisions := 640
@export var water_size := 8000.0
@export var water_subdivisions := 640
@export var seed_value := 7.0

var terrain_mat: ShaderMaterial
var water_mat: ShaderMaterial
var env: Environment
var cam: Camera3D
var hud: Label

var yaw := 0.0
var pitch := -0.12
var speed := 85.0

const FOG_AIR := Color(0.66, 0.77, 0.88)
const FOG_WATER := Color(0.025, 0.12, 0.19)


func _ready() -> void:
	_build_environment()
	_build_terrain()
	_build_water()
	_build_camera()
	_build_hud()


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.20, 0.39, 0.70)
	sky_mat.sky_horizon_color = Color(0.72, 0.79, 0.83)
	sky_mat.ground_horizon_color = Color(0.60, 0.68, 0.72)
	sky_mat.ground_bottom_color = Color(0.13, 0.22, 0.29)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = FOG_AIR
	env.fog_density = 0.00035
	env.glow_enabled = true

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 1800.0
	add_child(sun)


func _build_terrain() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(terrain_size, terrain_size)
	mesh.subdivide_width = subdivisions - 1
	mesh.subdivide_depth = subdivisions - 1

	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = load("res://shaders/terrain.gdshader")
	terrain_mat.set_shader_parameter("seed", seed_value)
	mesh.material = terrain_mat

	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	# The heightfield is displaced on the GPU; include the full 200 m relief and seabed.
	mi.custom_aabb = AABB(
		Vector3(-terrain_size * 0.5, -100.0, -terrain_size * 0.5),
		Vector3(terrain_size, 310.0, terrain_size)
	)
	add_child(mi)


func _build_water() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(water_size, water_size)
	mesh.subdivide_width = water_subdivisions - 1
	mesh.subdivide_depth = water_subdivisions - 1

	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/water.gdshader")
	mesh.material = water_mat

	var mi := MeshInstance3D.new()
	mi.name = "Ocean"
	mi.mesh = mesh
	mi.custom_aabb = AABB(
		Vector3(-water_size * 0.5, -5.0, -water_size * 0.5),
		Vector3(water_size, 10.0, water_size)
	)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_camera() -> void:
	cam = Camera3D.new()
	cam.far = 12000.0
	cam.near = 0.3
	cam.fov = 68.0
	cam.position = Vector3(0.0, 150.0, 1700.0)
	cam.rotation = Vector3(pitch, yaw, 0.0)
	add_child(cam)
	cam.make_current()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(12.0, 8.0)
	hud.add_theme_color_override("font_color", Color(1, 1, 1))
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(hud)
	_update_hud()


func _update_hud() -> void:
	hud.text = "RMB + mouse: look   WASD/QE: move   Shift: fast   Wheel: speed\nR: new island (seed %.1f)   Mountains vary by seed   Esc: release mouse" % seed_value


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			speed = minf(speed * 1.15, 1800.0)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			speed = maxf(speed / 1.15, 2.0)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.0025
		pitch = clampf(pitch - event.relative.y * 0.0025, -1.5, 1.5)
		cam.rotation = Vector3(pitch, yaw, 0.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			seed_value = snappedf(randf_range(1.0, 500.0), 0.1)
			terrain_mat.set_shader_parameter("seed", seed_value)
			_update_hud()
		elif event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	var b := cam.global_transform.basis
	if Input.is_key_pressed(KEY_W):
		dir -= b.z
	if Input.is_key_pressed(KEY_S):
		dir += b.z
	if Input.is_key_pressed(KEY_A):
		dir -= b.x
	if Input.is_key_pressed(KEY_D):
		dir += b.x
	if Input.is_key_pressed(KEY_E):
		dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		dir -= Vector3.UP
	if dir != Vector3.ZERO:
		var mult := 4.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
		cam.global_position += dir.normalized() * speed * mult * delta

	var under := cam.global_position.y < 0.0
	env.fog_light_color = FOG_WATER if under else FOG_AIR
	env.fog_density = 0.035 if under else 0.00035
