extends RefCounted
class_name IslandGenerator

## Seeded CPU-side data preparation. The visible terrain mesh is displaced on the GPU.
## Coast shape (SDF), elevation and offshore bathymetry are separate fields.

const WORLD_SIZE := 10000.0
const COAST_RESOLUTION := 1024
const HEIGHT_RESOLUTION := 512
const TARGET_LAND_AREA_M2 := 4_000_000.0
const MAX_MOUNTAIN_MASSES := 6

const ErosionFilterScript = preload("res://scripts/slope_erosion_filter.gd")


func generate(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var warp_x := _make_noise(seed_value + 101, 0.00115, 3)
	var warp_z := _make_noise(seed_value + 211, 0.00115, 3)
	var coast_large := _make_noise(seed_value + 307, 0.0038, 4)
	var coast_small := _make_noise(seed_value + 401, 0.0125, 2)

	var coast_values := PackedFloat32Array()
	coast_values.resize(COAST_RESOLUTION * COAST_RESOLUTION)
	var rotation := rng.randf_range(0.0, TAU)
	var aspect := rng.randf_range(0.76, 1.28)
	var radius_scale := rng.randf_range(0.93, 1.08)
	var radius := sqrt(TARGET_LAND_AREA_M2 / PI)

	# Red Blob-style separation: derive a signed coast field independently of elevation.
	# Domain warp + broad and fine Simplex FBM perturb the silhouette without a radial falloff.
	for y in range(COAST_RESOLUTION):
		var world_z := (float(y) / float(COAST_RESOLUTION - 1) - 0.5) * WORLD_SIZE
		for x in range(COAST_RESOLUTION):
			var world_x := (float(x) / float(COAST_RESOLUTION - 1) - 0.5) * WORLD_SIZE
			var point := Vector2(world_x, world_z)
			var warp := Vector2(
				warp_x.get_noise_2d(world_x, world_z),
				warp_z.get_noise_2d(world_x, world_z)
			) * 185.0
			var rotated := (point + warp).rotated(rotation)
			var ellipse_point := Vector2(rotated.x / aspect, rotated.y * aspect)
			var coast_noise := coast_large.get_noise_2d(world_x, world_z) * 76.0
			coast_noise += coast_small.get_noise_2d(world_x, world_z) * 23.0
			coast_values[x + y * COAST_RESOLUTION] = radius * radius_scale - ellipse_point.length() + coast_noise

	# Calibrate the shoreline threshold to the desired sampled land pixel count.
	var coast_step := WORLD_SIZE / float(COAST_RESOLUTION - 1)
	var pixel_area := coast_step * coast_step
	var target_pixels := clampi(
		int(round(TARGET_LAND_AREA_M2 / pixel_area)),
		1,
		coast_values.size() - 1
	)
	var sorted_values := coast_values.duplicate()
	sorted_values.sort()
	var threshold_index := maxi(sorted_values.size() - target_pixels - 1, 0)
	var threshold := sorted_values[threshold_index]
	sorted_values.clear()

	var land_pixels := 0
	for i in range(coast_values.size()):
		coast_values[i] -= threshold
		if coast_values[i] > 0.0:
			land_pixels += 1

	var coast_image := Image.create_from_data(
		COAST_RESOLUTION,
		COAST_RESOLUTION,
		false,
		Image.FORMAT_RF,
		coast_values.to_byte_array()
	)
	var coast_texture := ImageTexture.create_from_image(coast_image)
	coast_texture.resource_name = "Generated signed coastline field"

	var mountain_descriptors := _make_mountains(rng, coast_values)
	var height_values := _make_height_field(seed_value, coast_values, mountain_descriptors)
	var erosion_filter := ErosionFilterScript.new()
	height_values = erosion_filter.apply(height_values, coast_values, seed_value)

	var height_image := Image.create_from_data(
		HEIGHT_RESOLUTION,
		HEIGHT_RESOLUTION,
		false,
		Image.FORMAT_RF,
		height_values.to_byte_array()
	)
	var height_texture := ImageTexture.create_from_image(height_image)
	height_texture.resource_name = "Generated terrain and bathymetry height field"

	return {
		"coast_texture": coast_texture,
		"height_texture": height_texture,
		"land_area_m2": float(land_pixels) * pixel_area,
		"mountain_count": mountain_descriptors.size(),
		"seed": seed_value,
	}


func _make_noise(noise_seed: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	return noise


func _make_mountains(rng: RandomNumberGenerator, coast_values: PackedFloat32Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var desired_count := _roll_mountain_count(rng)
	var accepted_centres: Array[Vector2] = []

	for i in range(desired_count):
		var long_radius := rng.randf_range(245.0, 430.0)
		var short_radius := rng.randf_range(115.0, 220.0)
		var centre := _find_mountain_centre(rng, coast_values, long_radius, accepted_centres)
		if centre.x > WORLD_SIZE:
			break
		accepted_centres.append(centre)
		result.append({
			"centre": centre,
			"angle": rng.randf_range(0.0, TAU),
			"long_radius": long_radius,
			"short_radius": short_radius,
			"peak_height": rng.randf_range(245.0, 390.0),
			"frequency": rng.randf_range(0.0045, 0.0080),
			"phase": rng.randf_range(-1000.0, 1000.0),
		})
	return result


func _roll_mountain_count(rng: RandomNumberGenerator) -> int:
	# P(at least one) = 25%; each additional massif is progressively rarer.
	# Conditional probabilities: 15%, 7.5%, 3.75%, 1.875%, 0.9375%; maximum 6.
	if rng.randf() >= 0.25:
		return 0
	var count := 1
	var next_probability := 0.15
	while count < MAX_MOUNTAIN_MASSES and rng.randf() < next_probability:
		count += 1
		next_probability *= 0.5
	return count


func _find_mountain_centre(
	rng: RandomNumberGenerator,
	coast_values: PackedFloat32Array,
	minimum_separation_radius: float,
	accepted: Array[Vector2]
) -> Vector2:
	for attempt in range(300):
		var point := Vector2(
			rng.randf_range(-WORLD_SIZE * 0.29, WORLD_SIZE * 0.29),
			rng.randf_range(-WORLD_SIZE * 0.29, WORLD_SIZE * 0.29)
		)
		var ix := clampi(int(round((point.x / WORLD_SIZE + 0.5) * float(COAST_RESOLUTION - 1))), 0, COAST_RESOLUTION - 1)
		var iy := clampi(int(round((point.y / WORLD_SIZE + 0.5) * float(COAST_RESOLUTION - 1))), 0, COAST_RESOLUTION - 1)
		var signed_distance := coast_values[ix + iy * COAST_RESOLUTION]
		if signed_distance < maxf(185.0, minimum_separation_radius * 0.54):
			continue
		var separated := true
		for other in accepted:
			if point.distance_to(other) < minimum_separation_radius * 0.75 + 275.0:
				separated = false
				break
		if separated:
			return point
	return Vector2(WORLD_SIZE * 2.0, WORLD_SIZE * 2.0)


func _make_height_field(
	seed_value: int,
	coast_values: PackedFloat32Array,
	mountains: Array[Dictionary]
) -> PackedFloat32Array:
	var broad_noise := _make_noise(seed_value + 503, 0.00135, 5)
	var hill_noise := _make_noise(seed_value + 607, 0.0052, 4)
	var detail_noise := _make_noise(seed_value + 709, 0.023, 3)
	var mountain_noise := _make_noise(seed_value + 811, 1.0, 4)

	var heights := PackedFloat32Array()
	heights.resize(HEIGHT_RESOLUTION * HEIGHT_RESOLUTION)
	var coast_to_height := float(COAST_RESOLUTION - 1) / float(HEIGHT_RESOLUTION - 1)

	for y in range(HEIGHT_RESOLUTION):
		var world_z := (float(y) / float(HEIGHT_RESOLUTION - 1) - 0.5) * WORLD_SIZE
		var coast_y := clampi(int(round(float(y) * coast_to_height)), 0, COAST_RESOLUTION - 1)
		for x in range(HEIGHT_RESOLUTION):
			var world_x := (float(x) / float(HEIGHT_RESOLUTION - 1) - 0.5) * WORLD_SIZE
			var coast_x := clampi(int(round(float(x) * coast_to_height)), 0, COAST_RESOLUTION - 1)
			var sdf := coast_values[coast_x + coast_y * COAST_RESOLUTION]
			var height := 0.0

			if sdf >= 0.0:
				var inland := _smoothstep(0.0, 720.0, sdf)
				var shore_shelf := 2.8 + 12.0 * _smoothstep(0.0, 155.0, sdf)
				var broad_uplift := 47.0 * pow(inland, 1.28)
				var rolling_hills := broad_noise.get_noise_2d(world_x, world_z) * 22.0
				rolling_hills += hill_noise.get_noise_2d(world_x, world_z) * 10.5
				var micro_relief := detail_noise.get_noise_2d(world_x, world_z) * 2.4
				height = shore_shelf + broad_uplift
				height += rolling_hills * _smoothstep(35.0, 260.0, sdf)
				height += micro_relief

				for mountain in mountains:
					var mountain_centre: Vector2 = mountain["centre"]
					var mountain_angle := float(mountain["angle"])
					var local: Vector2 = (Vector2(world_x, world_z) - mountain_centre).rotated(-mountain_angle)
					var radius := Vector2(
						local.x / float(mountain["long_radius"]),
						local.y / float(mountain["short_radius"])
					).length()
					var massif := 1.0 - _smoothstep(0.62, 1.28, radius)
					if massif > 0.0005:
						var frequency := float(mountain["frequency"])
						var phase := float(mountain["phase"])
						var ridge_noise := mountain_noise.get_noise_2d(local.x * frequency + phase, local.y * frequency - phase * 0.37)
						var ridge := pow(1.0 - absf(ridge_noise), 1.65)
						var summit_shape := 0.48 + 0.52 * ridge
						height += float(mountain["peak_height"]) * massif * summit_shape
				height = maxf(height, 0.35)
			else:
				# A broad continental shelf transitions into a steep slope and rough abyss.
				var offshore := minf(-sdf, 2600.0)
				var shelf := 17.0 * _smoothstep(0.0, 180.0, offshore)
				var continental_slope := 505.0 * _smoothstep(130.0, 2150.0, offshore)
				var abyss_noise := broad_noise.get_noise_2d(world_x * 0.75, world_z * 0.75) * 18.0
				abyss_noise += hill_noise.get_noise_2d(world_x, world_z) * 5.0
				height = -(shelf + continental_slope + abyss_noise)

			heights[x + y * HEIGHT_RESOLUTION] = height
	return heights


func _smoothstep(edge_a: float, edge_b: float, value: float) -> float:
	var t := clampf((value - edge_a) / (edge_b - edge_a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
