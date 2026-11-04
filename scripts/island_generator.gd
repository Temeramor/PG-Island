extends RefCounted
class_name IslandGenerator

## Generates only deterministic data inputs (SDF + erosion field + mountain descriptors).
## The actual terrain geometry and all surface materials are evaluated by spatial shaders.

const WORLD_SIZE := 6400.0
const MASK_RESOLUTION := 1024
const TARGET_LAND_AREA_M2 := 4_000_000.0
const MAX_MOUNTAINS := 6
const BASE_RADIUS := 1128.4 # sqrt(4,000,000 / PI); final contour is area-calibrated.

const TerrainErosionFilterScript = preload("res://scripts/terrain_erosion_filter.gd")


func generate(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var warp_x := _make_noise(seed_value + 101, 0.00125, 4)
	var warp_z := _make_noise(seed_value + 211, 0.00125, 4)
	var coast_large := _make_noise(seed_value + 307, 0.0048, 3)
	var coast_small := _make_noise(seed_value + 401, 0.014, 2)

	var values := PackedFloat32Array()
	values.resize(MASK_RESOLUTION * MASK_RESOLUTION)
	var angle := rng.randf_range(0.0, TAU)
	var aspect := rng.randf_range(0.82, 1.20)
	var radius_scale := rng.randf_range(0.94, 1.07)

	for y in range(MASK_RESOLUTION):
		var wz := (float(y) / float(MASK_RESOLUTION - 1) - 0.5) * WORLD_SIZE
		for x in range(MASK_RESOLUTION):
			var wx := (float(x) / float(MASK_RESOLUTION - 1) - 0.5) * WORLD_SIZE
			var p := Vector2(wx, wz)
			var warp := Vector2(
				warp_x.get_noise_2d(wx, wz),
				warp_z.get_noise_2d(wx, wz)
			) * 158.0
			var rotated := (p + warp).rotated(angle)
			var elliptical := Vector2(rotated.x / aspect, rotated.y * aspect)
			var radial_distance := elliptical.length()
			var broad_coast := coast_large.get_noise_2d(wx, wz) * 68.0
			var fine_coast := coast_small.get_noise_2d(wx, wz) * 19.0
			var value := BASE_RADIUS * radius_scale - radial_distance + broad_coast + fine_coast
			var index := x + y * MASK_RESOLUTION
			values[index] = value

	# Red Blob's distance-field approach: use an independent signed island mask,
	# then choose the shoreline isovalue that yields the requested land area.
	var pixel_step := WORLD_SIZE / float(MASK_RESOLUTION - 1)
	var pixel_area := pixel_step * pixel_step
	var target_pixels := clampi(int(round(TARGET_LAND_AREA_M2 / pixel_area)), 1, values.size() - 1)
	var sorted_values := values.duplicate()
	sorted_values.sort()
	var threshold := sorted_values[sorted_values.size() - target_pixels] - 0.0001
	sorted_values.clear()

	for i in range(values.size()):
		values[i] -= threshold

	var sdf_image := Image.create_from_data(
		MASK_RESOLUTION,
		MASK_RESOLUTION,
		false,
		Image.FORMAT_RF,
		values.to_byte_array()
	)
	var sdf_texture := ImageTexture.create_from_image(sdf_image)
	sdf_texture.resource_name = "Generated Island Signed Distance Field"

	var mountain_data := PackedVector4Array()
	var mountain_shapes := PackedVector4Array()
	mountain_data.resize(MAX_MOUNTAINS)
	mountain_shapes.resize(MAX_MOUNTAINS)
	var mountain_count := _roll_mountain_count(rng)
	var accepted_centres: Array[Vector2] = []

	for i in range(mountain_count):
		var long_radius := rng.randf_range(210.0, 390.0)
		var short_radius := rng.randf_range(105.0, 195.0)
		var centre := _find_mountain_centre(rng, values, long_radius, accepted_centres)
		if centre.x > WORLD_SIZE:
			break
		accepted_centres.append(centre)
		var ridge_angle := rng.randf_range(0.0, TAU)
		var peak_height := rng.randf_range(235.0, 365.0)
		var ridge_frequency := rng.randf_range(0.0048, 0.0072)
		var ridge_offset := rng.randf_range(0.0, 900.0)
		mountain_data[i] = Vector4(centre.x, centre.y, ridge_angle, peak_height)
		mountain_shapes[i] = Vector4(long_radius, short_radius, ridge_frequency, ridge_offset)

	mountain_count = accepted_centres.size()
	var erosion_filter := TerrainErosionFilterScript.new()
	var erosion_texture: Texture2D = erosion_filter.build_texture(
		seed_value,
		sdf_image,
		mountain_data,
		mountain_shapes,
		mountain_count
	)

	return {
		"sdf_texture": sdf_texture,
		"erosion_texture": erosion_texture,
		"mountain_data": mountain_data,
		"mountain_shapes": mountain_shapes,
		"mountain_count": mountain_count,
		"land_area_m2": float(target_pixels) * pixel_area,
		"seed": seed_value
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


func _roll_mountain_count(rng: RandomNumberGenerator) -> int:
	# Exactly 25% chance to have a first mountain group. Each following group
	# becomes progressively less likely: 15%, 7.5%, 3.75%, 1.875%, 0.9375%.
	if rng.randf() >= 0.25:
		return 0
	var count := 1
	var next_probability := 0.15
	while count < MAX_MOUNTAINS and rng.randf() < next_probability:
		count += 1
		next_probability *= 0.5
	return count


func _find_mountain_centre(
	rng: RandomNumberGenerator,
	signed_distance: PackedFloat32Array,
	long_radius: float,
	accepted: Array[Vector2]
) -> Vector2:
	for attempt in range(240):
		var point := Vector2(
			rng.randf_range(-WORLD_SIZE * 0.29, WORLD_SIZE * 0.29),
			rng.randf_range(-WORLD_SIZE * 0.29, WORLD_SIZE * 0.29)
		)
		var ix := clampi(int(round((point.x / WORLD_SIZE + 0.5) * float(MASK_RESOLUTION - 1))), 0, MASK_RESOLUTION - 1)
		var iy := clampi(int(round((point.y / WORLD_SIZE + 0.5) * float(MASK_RESOLUTION - 1))), 0, MASK_RESOLUTION - 1)
		var signed := signed_distance[ix + iy * MASK_RESOLUTION]
		if signed < long_radius * 0.62 + 130.0:
			continue
		var separated := true
		for other in accepted:
			if point.distance_to(other) < long_radius * 0.9 + 250.0:
				separated = false
				break
		if separated:
			return point
	return Vector2(WORLD_SIZE * 2.0, WORLD_SIZE * 2.0)
