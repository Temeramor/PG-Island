extends RefCounted
class_name TerrainErosionFilter

## A multi-octave, slope-aligned gully/ridge filter inspired by Rune Skovbo Johansen's
## "Fast and Gorgeous Erosion Filter" and the Godot community prototype by Henry1.
## This is evaluated into a small procedural displacement texture; the terrain mesh
## still gets displaced and shaded on the GPU by terrain.gdshader.

const WORLD_SIZE := 6400.0
const RESOLUTION := 384
const OCTAVES := 3


func build_texture(
	seed_value: int,
	sdf_image: Image,
	mountain_data: PackedVector4Array,
	mountain_shapes: PackedVector4Array,
	mountain_count: int
) -> Texture2D:
	var terrain_noise := FastNoiseLite.new()
	terrain_noise.seed = seed_value + 1201
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	terrain_noise.frequency = 0.0017
	terrain_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	terrain_noise.fractal_octaves = 4
	terrain_noise.fractal_lacunarity = 2.0
	terrain_noise.fractal_gain = 0.5

	var jitter_noise := FastNoiseLite.new()
	jitter_noise.seed = seed_value + 2203
	jitter_noise.noise_type = FastNoiseLite.TYPE_VALUE
	jitter_noise.frequency = 0.017
	jitter_noise.fractal_type = FastNoiseLite.FRACTAL_NONE

	var count := RESOLUTION * RESOLUTION
	var heights := PackedFloat32Array()
	heights.resize(count)
	var step := WORLD_SIZE / float(RESOLUTION - 1)

	# The base gradient is a low-frequency proxy for the large hills and mountain masses.
	for y in range(RESOLUTION):
		var wz := (float(y) / float(RESOLUTION - 1) - 0.5) * WORLD_SIZE
		for x in range(RESOLUTION):
			var wx := (float(x) / float(RESOLUTION - 1) - 0.5) * WORLD_SIZE
			var sdf_x := clampi(int(round(float(x) / float(RESOLUTION - 1) * float(sdf_image.get_width() - 1))), 0, sdf_image.get_width() - 1)
			var sdf_y := clampi(int(round(float(y) / float(RESOLUTION - 1) * float(sdf_image.get_height() - 1))), 0, sdf_image.get_height() - 1)
			var signed_distance := sdf_image.get_pixel(sdf_x, sdf_y).r
			var inland := _smoothstep(0.0, 650.0, signed_distance)
			var h := 66.0 * inland + terrain_noise.get_noise_2d(wx, wz) * 31.0
			for m in range(mountain_count):
				var a := mountain_data[m]
				var b := mountain_shapes[m]
				var d := Vector2(wx - a.x, wz - a.y).rotated(-a.z)
				var r := Vector2(d.x / b.x, d.y / b.y).length()
				var body := 1.0 - _smoothstep(0.52, 1.18, r)
				h += a.w * body * 0.68
			heights[x + y * RESOLUTION] = h

	var erosion := PackedFloat32Array()
	erosion.resize(count)
	for y in range(RESOLUTION):
		var wz := (float(y) / float(RESOLUTION - 1) - 0.5) * WORLD_SIZE
		for x in range(RESOLUTION):
			var wx := (float(x) / float(RESOLUTION - 1) - 0.5) * WORLD_SIZE
			var index := x + y * RESOLUTION
			var left := heights[maxi(x - 1, 0) + y * RESOLUTION]
			var right := heights[mini(x + 1, RESOLUTION - 1) + y * RESOLUTION]
			var down := heights[x + maxi(y - 1, 0) * RESOLUTION]
			var up := heights[x + mini(y + 1, RESOLUTION - 1) * RESOLUTION]
			var gradient := Vector2(right - left, up - down) / (2.0 * step)
			var slope := gradient.length()
			var slope_mask := _smoothstep(0.018, 0.13, slope)
			var sdf_x := clampi(int(round(float(x) / float(RESOLUTION - 1) * float(sdf_image.get_width() - 1))), 0, sdf_image.get_width() - 1)
			var sdf_y := clampi(int(round(float(y) / float(RESOLUTION - 1) * float(sdf_image.get_height() - 1))), 0, sdf_image.get_height() - 1)
			var signed_distance := sdf_image.get_pixel(sdf_x, sdf_y).r
			var land_mask := _smoothstep(20.0, 190.0, signed_distance)
			if slope_mask <= 0.001 or land_mask <= 0.001:
				erosion[index] = 0.0
				continue

			var tangent := Vector2(-gradient.y, gradient.x).normalized()
			var position := Vector2(wx, wz)
			var displacement := 0.0
			for octave in range(OCTAVES):
				var frequency := 0.034 * pow(2.0, float(octave))
				var amplitude := 5.0 * pow(0.5, float(octave))
				var cell_size := 420.0 / pow(2.0, float(octave))
				var cell := Vector2(floor(wx / cell_size), floor(wz / cell_size))
				var stripe_sum := 0.0
				var weight_sum := 0.0
				for ny in range(-1, 2):
					for nx in range(-1, 2):
						var cx := int(cell.x) + nx
						var cy := int(cell.y) + ny
						var jx := 0.5 + 0.5 * jitter_noise.get_noise_2d(float(cx) * 67.1 + float(seed_value), float(cy) * 67.1 + float(octave) * 19.7)
						var jy := 0.5 + 0.5 * jitter_noise.get_noise_2d(float(cx) * 67.1 + 83.3, float(cy) * 67.1 - float(seed_value) * 0.37)
						var pivot := Vector2(float(cx), float(cy)) * cell_size + Vector2(jx, jy) * cell_size
						var weight := pow(1.0 - _smoothstep(0.0, cell_size * 1.5, position.distance_to(pivot)), 2.0)
						if weight > 0.001:
							stripe_sum += sin((position - pivot).dot(tangent) * frequency) * weight
							weight_sum += weight
				if weight_sum > 0.0001:
					displacement += (stripe_sum / weight_sum) * amplitude
			erosion[index] = displacement * slope_mask * land_mask

	var image := Image.create_from_data(
		RESOLUTION,
		RESOLUTION,
		false,
		Image.FORMAT_RF,
		erosion.to_byte_array()
	)
	var texture := ImageTexture.create_from_image(image)
	texture.resource_name = "Generated Slope-Aligned Erosion Field"
	return texture


func _smoothstep(edge_a: float, edge_b: float, value: float) -> float:
	var t := clampf((value - edge_a) / (edge_b - edge_a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
