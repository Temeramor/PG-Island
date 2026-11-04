extends Node3D

## Procedural island study. All geometry is generated at runtime; no imported meshes,
## texture packs, plugins or external libraries are required.
## RMB + mouse: look | WASD: fly | Shift: descend | Space: ascend | R: regenerate | Esc: release cursor

const IslandGeneratorScript = preload("res://scripts/island_generator.gd")

@export_range(128, 768, 32) var terrain_subdivisions: int = 512
@export_range(128, 768, 32) var ocean_subdivisions: int = 320
@export var terrain_size: float = 10000.0
@export var ocean_size: float = 12000.0
@export var flight_speed: float = 210.0
@export var initial_seed: int = 0

const HEIGHT_RESOLUTION := 512.0
const AIR_FOG := Color(0.66, 0.77, 0.87)
const UNDERWATER_FOG := Color(0.018, 0.12, 0.16)

var generator: IslandGenerator
var terrain_material: ShaderMaterial
var water_material: ShaderMaterial
var camera: Camera3D
var environment: Environment
var hud: Label
var active_seed: int = 0
var yaw: float = 0.0
var pitch: float = -0.30


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	generator = IslandGeneratorScript.new()
	_create_environment()
	_create_terrain()
	_create_ocean()
	_create_camera()
	_create_hud()

	if initial_seed == 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		active_seed = rng.randi_range(1, 2_000_000_000)
	else:
		active_seed = initial_seed
	_generate_island(active_seed)


func _create_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.14, 0.31, 0.53)
	sky_material.sky_horizon_color = Color(0.69, 0.79, 0.87)
	sky_material.ground_bottom_color = Color(0.12, 0.18, 0.22)
	sky_material.ground_horizon_color = Color(0.57, 0.68, 0.76)
	var sky := Sky.new()
	sky.sky_material = sky_material

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.fog_enabled = true
	environment.fog_light_color = AIR_FOG
	environment.fog_density = 0.000035
	environment.fog_sky_affect = 0.35
	environment.glow_enabled = true
	environment.glow_intensity = 0.18

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-39.0, -32.0, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 6500.0
	add_child(sun)


func _create_terrain() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(terrain_size, terrain_size)
	plane.subdivide_width = terrain_subdivisions
	plane.subdivide_depth = terrain_subdivisions

	terrain_material = ShaderMaterial.new()
	terrain_material.shader = load("res://shaders/terrain.gdshader") as Shader
	terrain_material.set_shader_parameter("world_size", terrain_size)
	terrain_material.set_shader_parameter("heightmap_resolution", HEIGHT_RESOLUTION)
	plane.material = terrain_material

	var instance := MeshInstance3D.new()
	instance.name = "GPU_Displaced_Terrain_and_Bathymetry"
	instance.mesh = plane
	instance.custom_aabb = AABB(
		Vector3(-terrain_size * 0.5, -650.0, -terrain_size * 0.5),
		Vector3(terrain_size, 1250.0, terrain_size)
	)
	add_child(instance)


func _create_ocean() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(ocean_size, ocean_size)
	plane.subdivide_width = ocean_subdivisions
	plane.subdivide_depth = ocean_subdivisions

	water_material = ShaderMaterial.new()
	water_material.shader = load("res://shaders/water.gdshader") as Shader
	plane.material = water_material

	var instance := MeshInstance3D.new()
	instance.name = "Gerstner_Ocean"
	instance.mesh = plane
	instance.position.y = 0.0
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(
		Vector3(-ocean_size * 0.5, -10.0, -ocean_size * 0.5),
		Vector3(ocean_size, 20.0, ocean_size)
	)
	add_child(instance)


func _create_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Free_Fly_Camera"
	camera.fov = 70.0
	camera.near = 0.12
	camera.far = 18000.0
	camera.position = Vector3(0.0, 720.0, 2300.0)
	camera.rotation = Vector3(pitch, yaw, 0.0)
	add_child(camera)
	camera.make_current()


func _create_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	hud = Label.new()
	hud.position = Vector2(18.0, 14.0)
	hud.add_theme_color_override("font_color", Color(0.97, 0.99, 1.0))
	hud.add_theme_color_override("font_outline_color", Color(0.012, 0.022, 0.034, 0.96))
	hud.add_theme_constant_override("outline_size", 5)
	hud.add_theme_font_size_override("font_size", 16)
	layer.add_child(hud)
	_update_hud(0.0, 0)


func _generate_island(seed_value: int) -> void:
	active_seed = seed_value
	hud.text = "GENERATING ISLAND...  seed: %d" % active_seed
	var generated: Dictionary = generator.generate(active_seed)
	terrain_material.set_shader_parameter("coast_field", generated["coast_texture"])
	terrain_material.set_shader_parameter("height_field", generated["height_texture"])
	_update_hud(float(generated["land_area_m2"]), int(generated["mountain_count"]))


func _update_hud(area_m2: float, mountain_count: int) -> void:
	var area_text := "building..." if area_m2 <= 0.0 else "%.3f km²" % (area_m2 / 1_000_000.0)
	hud.text = (
		"PROCEDURAL ISLAND  |  seed: %d  |  land: %s  |  mountain masses: %d\n" % [active_seed, area_text, mountain_count]
		+ "RMB + mouse: look    WASD: fly    Shift: down    Space: up    R: new island    Esc: release cursor"
	)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.0024
		pitch = clampf(pitch - event.relative.y * 0.0024, -1.50, 1.50)
		camera.rotation = Vector3(pitch, yaw, 0.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			_generate_island(rng.randi_range(1, 2_000_000_000))
		elif event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	var direction := Vector3.ZERO
	var basis := camera.global_transform.basis
	if Input.is_key_pressed(KEY_W):
		direction -= basis.z
	if Input.is_key_pressed(KEY_S):
		direction += basis.z
	if Input.is_key_pressed(KEY_A):
		direction -= basis.x
	if Input.is_key_pressed(KEY_D):
		direction += basis.x
	if Input.is_key_pressed(KEY_SPACE):
		direction += Vector3.UP
	if Input.is_key_pressed(KEY_SHIFT):
		direction -= Vector3.UP
	if direction.length_squared() > 0.0:
		camera.global_position += direction.normalized() * flight_speed * delta

	var underwater := camera.global_position.y < -0.5
	environment.fog_light_color = UNDERWATER_FOG if underwater else AIR_FOG
	environment.fog_density = 0.018 if underwater else 0.000035
