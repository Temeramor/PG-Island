extends Node3D

@onready var island: ProceduralIsland = $Island
var _seed_control: SpinBox
var _status_label: Label

func _ready() -> void:
	_create_lighting()
	_create_camera()
	_create_ui()
	_update_status()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_regenerate()

func _create_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.12, 0.27, 0.48)
	sky_material.sky_horizon_color = Color(0.62, 0.76, 0.86)
	sky_material.ground_bottom_color = Color(0.08, 0.10, 0.12)
	sky_material.ground_horizon_color = Color(0.48, 0.57, 0.62)
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ambient_light_energy = 0.75
	world.environment = environment
	add_child(world)

func _create_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "IslandCamera"
	camera.position = Vector3(2050.0, 1750.0, 2200.0)
	camera.far = 12000.0
	camera.look_at(Vector3.ZERO, Vector3.UP)
	add_child(camera)
	camera.current = true

func _create_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size = Vector2(330.0, 0.0)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var title := Label.new()
	title.text = "PG-ISLAND | PROCEDURAL WORLD"
	title.add_theme_font_size_override("font_size", 16)
	column.add_child(title)
	var description := Label.new()
	description.text = "Target land area: 4.00 km²\nRandom coastline • mountains • shelf • seabed"
	column.add_child(description)
	var seed_row := HBoxContainer.new()
	column.add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_row.add_child(seed_label)
	_seed_control = SpinBox.new()
	_seed_control.min_value = 0
	_seed_control.max_value = 999999
	_seed_control.value = island.seed
	_seed_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_control)
	var button := Button.new()
	button.text = "Generate new island"
	button.pressed.connect(_regenerate)
	column.add_child(button)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)
	var hint := Label.new()
	hint.text = "Press R to generate another random island."
	hint.add_theme_color_override("font_color", Color(0.72, 0.78, 0.83))
	column.add_child(hint)

func _regenerate() -> void:
	var next_seed := int(_seed_control.value)
	if next_seed == island.seed:
		next_seed = randi_range(0, 999999)
		_seed_control.value = next_seed
	island.generate(next_seed)
	_update_status()

func _update_status() -> void:
	if _status_label:
		_status_label.text = "Seed: %d\nMeasured land area: %.3f km²\nWorld extent: %.1f × %.1f km" % [island.seed, island.actual_land_area_km2, island.world_size / 1000.0, island.world_size / 1000.0]
