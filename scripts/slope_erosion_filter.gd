extends RefCounted

## Multi-scale slope-aligned channel/ridge displacement.
## The method follows the published idea of aligning procedural gullies to terrain
## gradients (Rune Skovbo Johansen, 2026; Godot prototype discussion by Henry1).
## This is an original lightweight approximation, not a source-code port of the
## full advanced filter and not a hydraulic/thermal simulation.

const WORLD_SIZE := 10000.0
const RESOLUTION := 512
const OCTAVES := 4


func apply(
	base_heights: PackedFloat32Array,
	coast_sdf: PackedFloat32Array,
	seed_value: int
) -> PackedFloat32Array:
	var current := base_heights.duplicate()
	var world_step := WORLD_SIZE / float(RESOLUTION - 1)

	for octave in range(OCTAVES):
		var previous := current
		var next_heights := previous.duplicate()
		var cell_size := 520.0 / pow(2.0, float(octave))
		var stripe_period := cell_size * 0.23
		var stripe_frequency := TAU / stripe_period
		var amplitude := 3.8 / pow(2.0, float(octave))

		for y in range(1, RESOLUTION - 1):
			var world_z := (float(y) / float(RESOLUTION - 1) - 0.5) * WORLD_SIZE
			for x in range(1, RESOLUTION - 1):
				var index := x + y * RESOLUTION
				var terrain_height := previous[index]
				if terrain_height < 18.0:
					continue

				var gradient_x := (previous[index + 1] - previous[index - 1]) / (2.0 * world_step)
				var gradient_z := (previous[index + RESOLUTION] - previous[index - RESOLUTION]) / (2.0 * world_step)
				var gradient := Vector2(gradient_x, gradient_z)
				var slope := gradient.length()
				if slope < 0.018:
					continue

				var tangent := Vector2(-gradient.y, gradient.x) / maxf(slope, 0.0001)
				var world_x := (float(x) / float(RESOLUTION - 1) - 0.5) * WORLD_SIZE
				var position := Vector2(world_x, world_z)
				var cell_x := int(floor(world_x / cell_size))
				var cell_y := int(floor(world_z / cell_size))
				var stripe_sum := 0.0
				var weight_sum := 0.0

				# Blend four jittered neighbouring pivots to avoid visible cell seams.
				for oy in range(2):
					for ox in range(2):
						var cx := cell_x + ox
						var cy := cell_y + oy
						var jitter_x := _hash01(cx, cy, seed_value, octave, 0)
						var jitter_y := _hash01(cx, cy, seed_value, octave, 1)
						var pivot := Vector2(
							(float(cx) + 0.20 + jitter_x * 0.60) * cell_size,
							(float(cy) + 0.20 + jitter_y * 0.60) * cell_size
						)
						var distance_weight := 1.0 - clampf(position.distance_to(pivot) / (cell_size * 1.65), 0.0, 1.0)
						var weight := distance_weight * distance_weight
						if weight > 0.0001:
							var phase_offset := _hash01(cx, cy, seed_value, octave, 2) * TAU
							var phase := (position - pivot).dot(tangent) * stripe_frequency + phase_offset
							var channel := pow(maxf(cos(phase), 0.0), 8.0)
							var shoulder := pow(maxf(-cos(phase), 0.0), 5.0)
							stripe_sum += (-channel + shoulder * 0.12) * weight
							weight_sum += weight

				if weight_sum > 0.0001:
					var coast_x := int(round(float(x) / float(RESOLUTION - 1) * 1023.0))
					var coast_y := int(round(float(y) / float(RESOLUTION - 1) * 1023.0))
					var coast_index := coast_x + coast_y * 1024
					var inland := _smoothstep(30.0, 220.0, coast_sdf[coast_index])
					var steepness := _smoothstep(0.025, 0.19, slope)
					var displacement := stripe_sum / weight_sum * amplitude * inland * steepness
					next_heights[index] = maxf(terrain_height + displacement, 0.2)

		current = next_heights
	return current


func _hash01(x: int, y: int, seed_value: int, octave: int, lane: int) -> float:
	var reduced_seed := seed_value % 65521
	var value: int = (x * 374761393 + y * 668265263 + reduced_seed * 69069 + octave * 362437 + lane * 1013904223) & 0x7fffffff
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff
	value = value ^ (value >> 16)
	return float(value & 0x7fffffff) / 2147483647.0


func _smoothstep(edge_a: float, edge_b: float, value: float) -> float:
	var t := clampf((value - edge_a) / (edge_b - edge_a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
