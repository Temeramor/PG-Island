extends MeshInstance3D
class_name ProceduralIsland

## Procedural island with an approximately exact target land area.
## The mesh includes the island, continental shelf and deep seabed.

@export_group("Island")
@export_range(0, 999999, 1) var seed: int = 18427
@export_range(0.25, 12.0, 0.25) var land_area_km2: float = 4.0
@export_range(1000.0, 10000.0, 100.0) var world_size: float = 3200.0
@export_range(128, 768, 1) var resolution: int = 384
@export_range(100.0, 1200.0, 10.0) var peak_height: float = 460.0
@export_range(50.0, 500.0, 10.0) var ocean_depth: float = 260.0
@export_range(0.0, 100.0, 1.0) var coastline_roughness: float = 32.0

@export_group("Generation")
@export var generate_on_ready: bool = true
@export var create_collision: bool = true
@export var create_ocean: bool = true

var actual_land_area_km2: float = 0.0
var _shape_noise := FastNoiseLite.new()
var _height_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
var _ridge_noise := FastNoiseLite.new()
var _boundary_scale: float = 1.0
var _height_samples := PackedFloat32Array()

func _ready() -> void:
	if generate_on_ready:
		generate(seed)

func generate(new_seed: int = -1) -> void:
	if new_seed >= 0:
		seed = new_seed
	_setup_noise()
	_boundary_scale = _calibrate_land_area()
	_build_surface()
	if create_ocean:
		_build_ocean()
	print("PG-Island | seed=", seed, " | land area ≈ ", snappedf(actual_land_area_km2, 0.01), " km²")

func _setup_noise() -> void:
	_shape_noise.seed = seed
	_shape_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_shape_noise.frequency = 0.0018
	_shape_noise.fractal_octaves = 3

	_height_noise.seed = seed + 101
	_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_height_noise.frequency = 0.0017
	_height_noise.fractal_octaves = 5
	_height_noise.fractal_lacunarity = 2.05
	_height_noise.fractal_gain = 0.48

	_detail_noise.seed = seed + 202
	_detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_detail_noise.frequency = 0.012
	_detail_noise.fractal_octaves = 3

	_ridge_noise.seed = seed + 303
	_ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge_noise.frequency = 0.0032
	_ridge_noise.fractal_octaves = 4
	_ridge_noise.fractal_gain = 0.52

func _base_boundary(nx: float, nz: float) -> float:
	var angle := atan2(nz, nx)
	var broad := 0.735 + 0.105 * sin(angle * 3.0 + float(seed % 97))
	broad += 0.065 * sin(angle * 5.0 - float(seed % 31) * 0.13)
	broad += 0.035 * sin(angle * 9.0 + 1.7)
	var irregularity := _shape_noise.get_noise_2d(nx * 850.0 + float(seed), nz * 850.0) * 0.105
	return maxf(0.35, broad + irregularity)

func _is_land(nx: float, nz: float, scale: float) -> bool:
	var radial := Vector2(nx, nz).length()
	if radial < 0.0001:
		return true
	var boundary := _base_boundary(nx, nz) * scale
	var edge_noise := _shape_noise.get_noise_2d(nx * 1800.0 + 900.0, nz * 1800.0) * (coastline_roughness / world_size)
	return radial <= boundary + edge_noise

func _calibrate_land_area() -> float:
	var target_cells := land_area_km2 * 1000000.0
	var step_area := (world_size / float(resolution)) ** 2
	var low := 0.1
	var high := 1.8
	for iteration in range(22):
		var mid := (low + high) * 0.5
		var count := 0
		for z in range(resolution):
			var nz := (float(z) / float(resolution - 1)) * 2.0 - 1.0
			for x in range(resolution):
				var nx := (float(x) / float(resolution - 1)) * 2.0 - 1.0
				if _is_land(nx, nz, mid):
					count += 1
		var measured := float(count) * step_area
		if measured < target_cells:
			low = mid
		else:
			high = mid
	_boundary_scale = (low + high) * 0.5
	var count_final := 0
	for z in range(resolution):
		var nz := (float(z) / float(resolution - 1)) * 2.0 - 1.0
		for x in range(resolution):
			var nx := (float(x) / float(resolution - 1)) * 2.0 - 1.0
			if _is_land(nx, nz, _boundary_scale):
				count_final += 1
	actual_land_area_km2 = float(count_final) * step_area / 1000000.0
	return _boundary_scale

func _height_at(nx: float, nz: float) -> float:
	var radial := Vector2(nx, nz).length()
	var boundary := _base_boundary(nx, nz) * _boundary_scale
	var coast_noise := _shape_noise.get_noise_2d(nx * 1800.0 + 900.0, nz * 1800.0) * (coastline_roughness / world_size)
	var signed_distance := boundary + coast_noise - radial
	var world_distance := signed_distance * world_size
	var broad := _height_noise.get_noise_2d(nx * world_size, nz * world_size)
	var detail := _detail_noise.get_noise_2d(nx * world_size, nz * world_size)
	var ridge := 1.0 - absf(_ridge_noise.get_noise_2d(nx * world_size, nz * world_size))
	var interior := clampf(world_distance / 950.0, 0.0, 1.0)
	if signed_distance >= 0.0:
		var massif := pow(interior, 0.78) * peak_height
		var mountain_belt := smoothstep(0.12, 0.78, interior) * smoothstep(0.95, 0.48, radial)
		var ridged_peaks := pow(maxf(ridge, 0.0), 2.3) * peak_height * 0.30 * mountain_belt
		var rolling := broad * 72.0 + detail * 13.0
		var foothills := sin(nx * 13.0 + broad * 3.0) * sin(nz * 11.0) * 12.0 * interior
		return maxf(1.5, massif + ridged_peaks + rolling * interior + foothills)
	var depth_distance := -world_distance
	var shelf := -minf(depth_distance * 0.19, 48.0)
	var basin := -maxf(depth_distance - 260.0, 0.0) * 0.12
	return maxf(-ocean_depth, shelf + basin + broad * 8.0 + detail * 2.0)

func _build_surface() -> void:
	var vertex_count := resolution * resolution
	_height_samples.resize(vertex_count)
	var half := world_size * 0.5
	var step := world_size / float(resolution - 1)
	for z in range(resolution):
		var nz := (float(z) / float(resolution - 1)) * 2.0 - 1.0
		for x in range(resolution):
			var nx := (float(x) / float(resolution - 1)) * 2.0 - 1.0
			_height_samples[z * resolution + x] = _height_at(nx, nz)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	colors.resize(vertex_count)
	uvs.resize(vertex_count)

	for z in range(resolution):
		for x in range(resolution):
			var i := z * resolution + x
			var px := -half + float(x) * step
			var pz := -half + float(z) * step
			var h := _height_samples[i]
			vertices[i] = Vector3(px, h, pz)
			var left := _height_samples[z * resolution + maxi(x - 1, 0)]
			var right := _height_samples[z * resolution + mini(x + 1, resolution - 1)]
			var up := _height_samples[maxi(z - 1, 0) * resolution + x]
			var down := _height_samples[mini(z + 1, resolution - 1) * resolution + x]
			var dx := (right - left) / (step * (2.0 if x > 0 and x < resolution - 1 else 1.0))
			var dz := (down - up) / (step * (2.0 if z > 0 and z < resolution - 1 else 1.0))
			var normal := Vector3(-dx, 1.0, -dz).normalized()
			normals[i] = normal
			colors[i] = _terrain_color(h, normal)
			uvs[i] = Vector2(float(x) / float(resolution - 1), float(z) / float(resolution - 1))

	for z in range(resolution - 1):
		for x in range(resolution - 1):
			var a := z * resolution + x
			var b := a + 1
			var c := a + resolution
			var d := c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/terrain.gdshader")
	array_mesh.surface_set_material(0, material)
	mesh = array_mesh

	if create_collision:
		for child in get_children():
			if child is StaticBody3D:
				child.queue_free()
		var body := StaticBody3D.new()
		body.name = "TerrainCollision"
		var collision := CollisionShape3D.new()
		collision.shape = array_mesh.create_trimesh_shape()
		body.add_child(collision)
		add_child(body)

func _terrain_color(height: float, normal: Vector3) -> Color:
	if height < 0.0:
		var depth_t := clampf(-height / ocean_depth, 0.0, 1.0)
		return Color(0.035, 0.19, 0.24).lerp(Color(0.012, 0.045, 0.095), depth_t)
	var slope := 1.0 - normal.y
	if height < 7.0:
		return Color(0.76, 0.68, 0.48)
	if slope > 0.48:
		return Color(0.34, 0.33, 0.30).lerp(Color(0.72, 0.72, 0.68), clampf((height - 180.0) / 260.0, 0.0, 1.0))
	if height > 330.0:
		return Color(0.78, 0.79, 0.76)
	if height > 170.0:
		return Color(0.34, 0.36, 0.31)
	if height > 65.0:
		return Color(0.20, 0.31, 0.19)
	return Color(0.30, 0.39, 0.22)

func _build_ocean() -> void:
	var old := get_node_or_null("Ocean")
	if old:
		old.queue_free()
	var ocean := MeshInstance3D.new()
	ocean.name = "Ocean"
	var plane := PlaneMesh.new()
	plane.size = Vector2(world_size * 2.8, world_size * 2.8)
	plane.subdivide_width = 128
	plane.subdivide_depth = 128
	ocean.mesh = plane
	ocean.position.y = 0.0
	var water_material := ShaderMaterial.new()
	water_material.shader = preload("res://shaders/ocean.gdshader")
	ocean.material_override = water_material
	add_child(ocean)
