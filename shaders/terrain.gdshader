// Procedural island terrain: warped island geometry, layered relief and geology-aware materials.
// Height is clamped to 0..200 m on land. Mountain ranges are independently optional per seed.
shader_type spatial;

group_uniforms Shape;
uniform float seed = 7.0;
uniform float island_radius = 1580.0;
uniform float coast_warp : hint_range(0.0, 2.0) = 1.15;
uniform float coast_detail : hint_range(0.0, 0.12) = 0.035;
uniform float shore_s : hint_range(0.25, 0.7) = 0.46;
uniform float mountain_chance : hint_range(0.0, 1.0) = 0.58;
uniform float mountain_strength : hint_range(0.0, 1.5) = 1.0;

group_uniforms Relief;
uniform float max_height = 200.0;
uniform float sea_floor_depth = 82.0;
uniform float shelf_depth = 12.0;
uniform float normal_eps = 2.0;
uniform float hill_strength : hint_range(0.0, 2.0) = 1.0;
uniform float erosion_damping : hint_range(0.0, 4.0) = 1.35;

group_uniforms Colors;
uniform vec3 wet_sand : source_color = vec3(0.48, 0.43, 0.34);
uniform vec3 dry_sand : source_color = vec3(0.78, 0.69, 0.51);
uniform vec3 pale_sand : source_color = vec3(0.88, 0.81, 0.66);
uniform vec3 grass_low : source_color = vec3(0.22, 0.34, 0.16);
uniform vec3 grass_high : source_color = vec3(0.37, 0.43, 0.22);
uniform vec3 scrub_color : source_color = vec3(0.34, 0.37, 0.20);
uniform vec3 rock_dark : source_color = vec3(0.27, 0.28, 0.27);
uniform vec3 rock_light : source_color = vec3(0.48, 0.45, 0.39);
uniform vec3 seabed_shallow : source_color = vec3(0.34, 0.37, 0.32);
uniform vec3 seabed_deep : source_color = vec3(0.12, 0.19, 0.20);
uniform float cliff_slope : hint_range(0.05, 0.6) = 0.22;
group_uniforms;

varying vec3 v_world;
varying vec3 v_wnormal;

const mat2 ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Quintic value noise with analytic derivatives.
vec3 noised(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	float k1 = b - a;
	float k2 = c - a;
	float k4 = a - b - c + d;
	float v = a + k1 * u.x + k2 * u.y + k4 * u.x * u.y;
	vec2 dv = du * vec2(k1 + k4 * u.y, k2 + k4 * u.x);
	return vec3(v * 2.0 - 1.0, 2.0 * dv);
}

// Slope-aware fBm: fine-scale noise is attenuated on steep terrain.
float terrain_fbm(vec2 p, int octaves) {
	float sum = 0.0;
	float amp = 1.0;
	float norm = 0.0;
	vec2 deriv = vec2(0.0);
	mat2 jac = mat2(vec2(1.0, 0.0), vec2(0.0, 1.0));
	for (int i = 0; i < 8; i++) {
		if (i >= octaves) {
			break;
		}
		vec3 n = noised(jac * p);
		vec2 grad = n.yz * jac;
		deriv += amp * grad;
		float damp = 1.0 / (1.0 + erosion_damping * dot(deriv, deriv));
		sum += amp * n.x * damp;
		norm += amp;
		jac = ROT * jac * 2.0;
		amp *= 0.5;
	}
	return sum / max(norm, 0.0001);
}

float ridged(vec2 p) {
	float sum = 0.0;
	float amp = 0.58;
	float weight = 1.0;
	for (int i = 0; i < 6; i++) {
		float n = 1.0 - abs(noised(p).x);
		n = n * n;
		sum += amp * n * weight;
		weight = clamp(n * 2.1, 0.0, 1.0);
		p = ROT * p * 2.03 + vec2(1.7, 9.2);
		amp *= 0.49;
	}
	return sum / 0.94;
}

float coast_distance(vec2 q, vec2 so) {
	vec2 w1 = vec2(
		noised(q * 1.35 + so).x,
		noised(q * 1.35 + so + vec2(5.2, 1.3)).x
	);
	vec2 w2 = vec2(
		noised(q * 3.4 + so + 9.7).x,
		noised(q * 3.4 + so + vec2(2.9, 6.1)).x
	);
	vec2 warped = q + coast_warp * (0.19 * w1 + 0.065 * w2);
	float radial = length(warped);
	float edge_noise = noised(q * 8.5 + so + 21.0).x * coast_detail;
	return radial + edge_noise;
}

float height_at(vec2 xz) {
	vec2 so = vec2(seed * 17.13, seed * 29.71);
	vec2 q = xz / island_radius;
	float edge = coast_distance(q, so);
	float mask = 1.0 - smoothstep(0.665, 0.735, edge);
	float land_t = clamp((0.735 - edge) / 0.07, 0.0, 1.0);
	float sea_t = clamp((edge - 0.665) / 0.07, 0.0, 1.0);

	if (mask > 0.5) {
		// Broad coastal shelf rises gently into interior terraces and low uplands.
		float interior = smoothstep(0.0, 0.78, land_t);
		float plateau = 8.0 + 27.0 * pow(interior, 1.35);
		float hills_a = terrain_fbm(q * vec2(5.1, 4.2) + so + 3.0, 7);
		float hills_b = terrain_fbm(q * vec2(12.0, 10.0) + so + 41.0, 5);
		float rolling = (hills_a * 15.0 + hills_b * 3.8) * hill_strength;
		// A separate per-island switch makes some seeds genuinely low-relief islands.
		float has_mountains = step(hash12(vec2(seed * 0.731 + 19.1, seed * 1.917 + 7.3)), mountain_chance);
		// Long, broken mountain spine with noisy foothills rather than isolated conical peaks.
		vec2 ridge_p = vec2(q.x * 2.15 + q.y * 0.38, q.y * 5.8) + so * 0.07;
		float ridge_field = ridged(ridge_p * 2.0 + vec2(11.0, 3.0));
		float ridge_zone_noise = terrain_fbm(q * vec2(3.0, 6.5) + so + 67.0, 5);
		float spine = smoothstep(0.22, 0.58, ridge_field + ridge_zone_noise * 0.19);
		float mountain_zone = smoothstep(0.16, 0.40, interior) * (1.0 - smoothstep(0.76, 0.96, interior));
		float mountain_relief = spine * mountain_zone * (72.0 + 72.0 * ridge_field) * mountain_strength * has_mountains;
		// Carved drainage-like valleys: broad warped negative channels interrupt the ridges.
		float drainage = abs(terrain_fbm(q * vec2(8.0, 3.0) + so + 103.0, 5));
		float valley_cut = smoothstep(0.0, 0.12, drainage) * mountain_relief * 0.16;
		float h = plateau + rolling + mountain_relief - valley_cut;
		// Beaches remain close to sea level; the cap is a hard physical limit, not an amplitude hint.
		h *= smoothstep(0.015, 0.20, land_t);
		return clamp(h, 0.0, max_height);
	}

	// Underwater shelf follows the same warped coast, then falls away into a deeper basin.
	float shelf = shelf_depth * sea_t;
	float basin = (sea_floor_depth - shelf_depth) * smoothstep(0.12, 0.92, sea_t);
	float seabed_noise = terrain_fbm(q * 6.0 + so + 131.0, 4) * 2.8;
	return -shelf - basin + seabed_noise * smoothstep(0.08, 0.55, sea_t);
}

void vertex() {
	vec2 xz = VERTEX.xz;
	float e = normal_eps;
	float h = height_at(xz);
	float hx = height_at(xz + vec2(e, 0.0));
	float hz = height_at(xz + vec2(0.0, e));
	VERTEX.y = h;
	vec3 nrm = normalize(vec3((h - hx) / e, 1.0, (h - hz) / e));
	NORMAL = nrm;
	v_wnormal = (MODEL_MATRIX * vec4(nrm, 0.0)).xyz;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(v_wnormal);
	float h = v_world.y;
	float slope = 1.0 - n.y;
	vec2 p = v_world.xz;
	float broad = noised(p * 0.012 + seed).x;
	float medium = noised(p * 0.075 + 17.0).x;
	float fine = noised(p * 0.48 + 31.0).x;

	vec3 sand = mix(dry_sand, pale_sand, smoothstep(-0.2, 0.55, broad + medium * 0.18));
	vec3 grass = mix(grass_low, grass_high, clamp(0.48 + broad * 0.30 + medium * 0.18, 0.0, 1.0));
	vec3 rock = mix(rock_dark, rock_light, clamp(0.5 + medium * 0.32 + fine * 0.12, 0.0, 1.0));
	vec3 seabed = mix(seabed_shallow, seabed_deep, 1.0 - smoothstep(-78.0, -12.0, h));

	float grass_w = smoothstep(3.0, 8.0, h);
	float scrub_w = smoothstep(35.0, 75.0, h) * (1.0 - smoothstep(0.30, 0.55, slope));
	float cliff_w = smoothstep(cliff_slope, cliff_slope + 0.17, slope);
	float high_rock = smoothstep(105.0, 165.0, h) * (1.0 - smoothstep(0.42, 0.68, slope)) * 0.55;

	vec3 col = seabed;
	col = mix(col, sand, smoothstep(-4.0, 0.5, h));
	col = mix(col, grass, grass_w);
	col = mix(col, scrub_color, scrub_w * 0.42);
	col = mix(col, rock, max(cliff_w, high_rock));
	// Darker damp strip at the waterline and fine mineral variation in the sand.
	float wet = (1.0 - smoothstep(0.15, 1.5, h)) * (1.0 - cliff_w);
	col = mix(col, wet_sand, wet * 0.72);
	col *= 0.985 + fine * 0.025;

	ALBEDO = col;
	ROUGHNESS = mix(0.94, 0.78, cliff_w);
	SPECULAR = 0.18;
}
