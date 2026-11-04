// Shader-driven island landmass and bathymetry.
// Technique references: Red Blob Games (separate island mask/height shaping),
// Inigo Quilez (domain warping + morenoise-style slope damping),
// The Book of Shaders ch.13 (fBm/ridged multifractal), Godot spatial shaders.
shader_type spatial;
render_mode specular_schlick_ggx, cull_back;

uniform sampler2D island_sdf : filter_linear, repeat_disable;
uniform sampler2D erosion_field : filter_linear, repeat_disable;
uniform float world_size = 6400.0;
uniform float terrain_seed = 1.0;
uniform int mountain_count = 0;
uniform vec4 mountain_data[6];   // xz centre, ridge angle, peak height
uniform vec4 mountain_shapes[6]; // long radius, short radius, ridge frequency, phase

uniform float sea_floor_depth = 560.0;
uniform float shelf_depth = 18.0;
uniform float erosion_strength = 1.0;
uniform float normal_step = 2.5;

uniform vec3 beach_sand : source_color = vec3(0.76, 0.68, 0.49);
uniform vec3 wet_sand : source_color = vec3(0.43, 0.39, 0.31);
uniform vec3 grass_low : source_color = vec3(0.20, 0.34, 0.13);
uniform vec3 grass_high : source_color = vec3(0.34, 0.43, 0.19);
uniform vec3 rock_low : source_color = vec3(0.30, 0.29, 0.27);
uniform vec3 rock_high : source_color = vec3(0.53, 0.49, 0.43);
uniform vec3 snow_color : source_color = vec3(0.88, 0.92, 0.96);
uniform vec3 shallow_seabed : source_color = vec3(0.39, 0.34, 0.25);
uniform vec3 deep_seabed : source_color = vec3(0.075, 0.12, 0.15);

varying vec3 world_position;
varying vec3 world_normal;
varying float terrain_height;
varying float coast_distance;

const mat2 ROT = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Quintic value noise with first derivatives. Value range is approximately [-1, 1].
vec3 noised(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	float k1 = b - a;
	float k2 = c - a;
	float k4 = a - b - c + d;
	float value = a + k1 * u.x + k2 * u.y + k4 * u.x * u.y;
	vec2 gradient = du * vec2(k1 + k4 * u.y, k2 + k4 * u.x);
	return vec3(value * 2.0 - 1.0, gradient * 2.0);
}

float fbm(vec2 p, int octaves) {
	float sum = 0.0;
	float amplitude = 0.5;
	float norm = 0.0;
	for (int i = 0; i < 7; i++) {
		if (i >= octaves) { break; }
		sum += noised(p).x * amplitude;
		norm += amplitude;
		p = ROT * p * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.5;
	}
	return sum / max(norm, 0.0001);
}

// fBm inspired by iq's morenoise: later octaves are damped by accumulated slope.
float morenoise_fbm(vec2 p, int octaves) {
	float sum = 0.0;
	float amplitude = 0.55;
	float norm = 0.0;
	vec2 accumulated_gradient = vec2(0.0);
	mat2 jacobian = mat2(vec2(1.0, 0.0), vec2(0.0, 1.0));
	for (int i = 0; i < 7; i++) {
		if (i >= octaves) { break; }
		vec3 n = noised(jacobian * p);
		vec2 gradient = n.yz * jacobian;
		accumulated_gradient += amplitude * gradient;
		float slope_fade = 1.0 / (1.0 + 1.7 * dot(accumulated_gradient, accumulated_gradient));
		sum += amplitude * n.x * slope_fade;
		norm += amplitude;
		jacobian = ROT * jacobian * 2.0;
		amplitude *= 0.5;
	}
	return sum / max(norm, 0.0001);
}

// Ridged multifractal: abs -> invert -> square, with octave feedback.
float ridged_mf(vec2 p) {
	float sum = 0.0;
	float amplitude = 0.5;
	float feedback = 1.0;
	for (int i = 0; i < 6; i++) {
		float ridge = 1.0 - abs(noised(p).x);
		ridge *= ridge;
		sum += ridge * amplitude * feedback;
		feedback = clamp(ridge * 2.1, 0.0, 1.0);
		p = ROT * p * 2.0 + vec2(3.7, 11.2);
		amplitude *= 0.5;
	}
	return sum / 0.97;
}

float height_at(vec2 xz) {
	vec2 uv = clamp(xz / world_size + vec2(0.5), vec2(0.001), vec2(0.999));
	float sdf = textureLod(island_sdf, uv, 0.0).r;
	float erosion = textureLod(erosion_field, uv, 0.0).r;
	vec2 p = xz / 520.0;
	vec2 seed_offset = vec2(terrain_seed * 0.173, terrain_seed * 0.291);

	// Coastline is an independent field. Relief is only blended after its land mask.
	if (sdf >= 0.0) {
		float inland = smoothstep(0.0, 760.0, sdf);
		float shore_shelf = 3.5 + 13.0 * smoothstep(0.0, 115.0, sdf);
		float broad_uplift = 49.0 * pow(inland, 1.35);
		float hills = morenoise_fbm(p * 0.72 + seed_offset + 2.4, 6) * 24.0;
		float rolling = fbm(p * 2.4 + seed_offset + 17.0, 5) * 5.5;
		float fine = fbm(p * 12.0 + seed_offset + 31.0, 3) * 1.15;
		float height = shore_shelf + broad_uplift + hills * smoothstep(25.0, 260.0, sdf) + rolling + fine;

		// Local anisotropic mountain ranges. Each descriptor is placed by the CPU seed.
		for (int i = 0; i < 6; i++) {
			if (i >= mountain_count) { break; }
			vec4 md = mountain_data[i];
			vec4 ms = mountain_shapes[i];
			vec2 local = (xz - md.xy);
			float ca = cos(md.z);
			float sa = sin(md.z);
			local = mat2(vec2(ca, -sa), vec2(sa, ca)) * local;
			vec2 ellipse = vec2(local.x / max(ms.x, 1.0), local.y / max(ms.y, 1.0));
			float radius = length(ellipse);
			float massif = 1.0 - smoothstep(0.68, 1.30, radius);
			float ridges = ridged_mf(local * ms.z + vec2(ms.w, terrain_seed * 0.037));
			float summit_warp = fbm(local * 0.003 + seed_offset + md.z, 4);
			float summit = 0.56 + 0.44 * ridges + summit_warp * 0.15;
			height += md.w * massif * max(summit, 0.0);
		}

		// Erosion filter field is a signed, slope-aligned gully/ridge displacement.
		height += erosion * erosion_strength;
		return max(height, 0.0);
	}

	// Offshore bathymetry: broad shallow shelf, continental slope, then irregular abyss.
	float offshore = clamp(-sdf, 0.0, 2200.0);
	float shelf = shelf_depth * smoothstep(0.0, 150.0, offshore);
	float slope = (sea_floor_depth - shelf_depth) * smoothstep(120.0, 1650.0, offshore);
	float bathy_noise = morenoise_fbm(p * 1.7 + seed_offset + 73.0, 5) * 21.0;
	float trench_noise = ridged_mf(p * 0.44 + seed_offset + 91.0) * 18.0 * smoothstep(550.0, 1800.0, offshore);
	return -(shelf + slope + bathy_noise + trench_noise);
}

void vertex() {
	vec2 xz = VERTEX.xz;
	float e = normal_step;
	float h = height_at(xz);
	float hx = height_at(xz + vec2(e, 0.0));
	float hz = height_at(xz + vec2(0.0, e));
	VERTEX.y = h;
	vec3 local_normal = normalize(vec3((h - hx) / e, 1.0, (h - hz) / e));
	NORMAL = local_normal;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(local_normal, 0.0)).xyz);
	terrain_height = h;
	vec2 uv = clamp(xz / world_size + vec2(0.5), vec2(0.001), vec2(0.999));
	coast_distance = textureLod(island_sdf, uv, 0.0).r;
}

void fragment() {
	vec3 n = normalize(world_normal);
	float h = terrain_height;
	float slope = 1.0 - clamp(n.y, 0.0, 1.0);
	vec2 p = world_position.xz;
	float macro = fbm(p * 0.006 + terrain_seed * 0.17, 4);
	float medium = fbm(p * 0.045 + 21.0, 4);
	float fine = noised(p * 0.32 + 7.0).x;

	vec3 color;
	if (h < 0.0) {
		float depth = clamp(-h / sea_floor_depth, 0.0, 1.0);
		color = mix(shallow_seabed, deep_seabed, smoothstep(0.02, 0.82, depth));
		color *= 0.94 + 0.10 * macro + 0.035 * medium;
	} else {
		float beach_mask = 1.0 - smoothstep(2.0, 12.5, h + medium * 1.4);
		vec3 sand = mix(beach_sand, wet_sand, smoothstep(0.0, 4.2, h) * 0.55);
		vec3 grass = mix(grass_low, grass_high, clamp(0.5 + macro * 0.58 + medium * 0.16, 0.0, 1.0));
		color = mix(grass, sand, beach_mask);

		float rock_by_slope = smoothstep(0.16, 0.43, slope + medium * 0.035);
		float rock_by_height = smoothstep(125.0, 235.0, h + macro * 28.0) * 0.78;
		float rock_mask = max(rock_by_slope, rock_by_height);
		vec3 rock = mix(rock_low, rock_high, clamp(0.52 + macro * 0.38 + fine * 0.09, 0.0, 1.0));
		color = mix(color, rock, rock_mask);

		float snow_mask = smoothstep(285.0, 345.0, h + macro * 22.0 + medium * 5.0);
		snow_mask *= 1.0 - smoothstep(0.22, 0.52, slope);
		color = mix(color, snow_color, snow_mask);

		float wet_edge = 1.0 - smoothstep(0.15, 1.8, h);
		color *= 1.0 - wet_edge * (1.0 - beach_mask) * 0.20;
		color *= 0.96 + fine * 0.045;
	}

	ALBEDO = color;
	ROUGHNESS = h < 0.0 ? 0.96 : mix(0.93, 0.68, smoothstep(0.15, 0.48, slope));
	SPECULAR = 0.18;
}
