// Procedural island terrain: the whole heightfield is evaluated in the vertex shader.
//
// Techniques and where they come from:
//  * Island mask via falloff curve        - Sebastian Lague, "Procedural Landmass Generation" E11 (falloff map)
//  * Irregular coastline via domain warp  - Inigo Quilez, "Domain Warping" (iquilezles.org/articles/warp)
//  * Hills: fBm with analytic derivatives, amplitude damped by 1/(1+|slope|^2)
//                                         - Inigo Quilez, "Advanced Perlin noise / morenoise" (erosion-like look)
//  * Mountains: ridged multifractal       - Musgrave ridge noise, as in The Book of Shaders ch.13 (abs + invert + square)
//  * Island profile (beach, shelf, drop-off) - Red Blob Games "terrain from noise" idea: separate shape from relief
//  * Hash without sine                    - Dave Hoskins (shadertoy 4djSRW)
//  * Vertex displacement + normal rebuild - Godot docs, "Your first 3D shader"
shader_type spatial;

group_uniforms Shape;
uniform float seed = 7.0;
uniform float island_radius = 400.0;
uniform float falloff_a : hint_range(1.0, 6.0) = 3.0;     // Lague falloff steepness
uniform float falloff_b : hint_range(0.5, 5.0) = 2.2;     // Lague falloff offset
uniform float coast_warp : hint_range(0.0, 2.0) = 1.0;    // domain warp strength of the outline
uniform float coast_detail : hint_range(0.0, 0.1) = 0.025; // small bays and rocks on the shoreline
uniform float shore_s : hint_range(0.2, 0.7) = 0.46;      // mask value where land meets the sea

group_uniforms Relief;
uniform float max_height = 130.0;
uniform float sea_floor_depth = 55.0;
uniform float shelf_depth = 9.0;                          // depth of the shallow shelf around the island
uniform float hill_freq = 3.0;
uniform float mountain_freq = 2.2;
uniform float hill_amp : hint_range(0.0, 0.4) = 0.12;
uniform float mountain_amp : hint_range(0.0, 1.0) = 0.65;
uniform float erosion_damping : hint_range(0.0, 4.0) = 1.2;
uniform float sea_noise_amp = 3.0;
uniform float normal_eps = 1.2;

group_uniforms Colors;
uniform vec3 sand_color : source_color = vec3(0.80, 0.72, 0.52);
uniform vec3 sand_dark : source_color = vec3(0.62, 0.55, 0.40);
uniform vec3 seabed_deep : source_color = vec3(0.30, 0.34, 0.33);
uniform vec3 grass_a : source_color = vec3(0.24, 0.40, 0.14);
uniform vec3 grass_b : source_color = vec3(0.38, 0.48, 0.18);
uniform vec3 rock_a : source_color = vec3(0.37, 0.34, 0.31);
uniform vec3 rock_b : source_color = vec3(0.52, 0.47, 0.41);
uniform float snow_line = 88.0;
uniform float rock_slope_min = 0.12;
uniform float rock_slope_max = 0.30;
group_uniforms;

varying vec3 v_world;
varying vec3 v_wnormal;

const mat2 ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));

// ---------------------------------------------------------------- noise

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Value noise with quintic interpolation and analytic derivatives.
// Returns (value in [-1,1], d/dx, d/dy).
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

// fBm where every octave is damped by the accumulated slope (iq "morenoise" idea):
// steep areas lose small detail, flat areas keep it -> smooth valleys, sharper flanks.
float terrain_fbm(vec2 p, int octaves) {
	float a = 0.0;
	float b = 1.0;
	float norm = 0.0;
	vec2 d = vec2(0.0);
	mat2 J = mat2(vec2(1.0, 0.0), vec2(0.0, 1.0));
	for (int i = 0; i < 10; i++) {
		if (i >= octaves) {
			break;
		}
		vec3 n = noised(J * p);
		vec2 g = n.yz * J; // gradient with respect to the original p
		d += b * g;
		a += b * n.x / (1.0 + erosion_damping * dot(d, d));
		norm += b;
		J = ROT * J * 2.0;
		b *= 0.5;
	}
	return a / norm;
}

// Ridged multifractal: sharp crests, each octave weighted by the previous one.
float ridged(vec2 p) {
	float a = 0.0;
	float b = 0.5;
	float w = 1.0;
	for (int i = 0; i < 6; i++) {
		float n = 1.0 - abs(noised(p).x);
		n *= n;
		a += b * n * w;
		w = clamp(n * 2.0, 0.0, 1.0);
		p = ROT * p * 2.0 + vec2(1.7, 9.2);
		b *= 0.5;
	}
	return a / 0.97;
}

// ---------------------------------------------------------------- island

float height_at(vec2 xz) {
	vec2 so = vec2(seed * 17.13, seed * 29.71);
	vec2 q = xz / island_radius;

	// Outline: domain-warped distance from the center (iq warp).
	vec2 w1 = vec2(noised(q * 1.3 + so).x, noised(q * 1.3 + so + vec2(5.2, 1.3)).x);
	vec2 w2 = vec2(noised(q * 3.1 + so + 9.7).x, noised(q * 3.1 + so + vec2(2.9, 6.1)).x);
	vec2 wq = q + coast_warp * (0.22 * w1 + 0.07 * w2);
	float x = clamp(length(wq), 0.0, 1.0);

	// Lague falloff curve: f(x) = x^a / (x^a + (b - b*x)^a)
	float xa = pow(x, falloff_a);
	float f = xa / (xa + pow(max(falloff_b - falloff_b * x, 0.0), falloff_a));
	float s = 1.0 - f;                                  // 1 in the center, 0 at the edge
	s += coast_detail * noised(q * 9.0 + so + 21.0).x;  // rugged coastline

	float land_t = clamp((s - shore_s) / (1.0 - shore_s), 0.0, 1.0);
	float sea_u = clamp((shore_s - s) / shore_s, 0.0, 1.0);

	float result = 0.0;
	if (s >= shore_s) {
		// ---- land
		float base = pow(land_t, 1.3) * 0.30 * max_height;
		float lw = smoothstep(0.0, 0.25, land_t);       // no relief right at the waterline

		float hills = terrain_fbm(q * hill_freq + so + 3.0, 8);
		float m_mask = smoothstep(0.35, 0.85, land_t + 0.25 * noised(q * 2.0 + so + 3.3).x);
		float peaks = ridged(q * mountain_freq + so + 17.0);

		result = base + lw * (hills * hill_amp * max_height + m_mask * peaks * mountain_amp * max_height);
	} else {
		// ---- sea floor: gentle shelf, then a steeper drop-off
		float prof = shelf_depth * sea_u + (sea_floor_depth - shelf_depth) * smoothstep(0.30, 1.0, sea_u);
		float sw = smoothstep(0.0, 0.2, sea_u);
		float n = terrain_fbm(q * 6.0 + so + 31.0, 4);
		result = -prof + sw * n * sea_noise_amp;
	}
	return result;
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

	float nz1 = noised(p * 0.06 + seed).x;   // large color patches
	float nz2 = noised(p * 0.5).x;           // mid grain
	float nz3 = noised(p * 3.0).x;           // fine grain

	// sea floor / sand
	vec3 sand = mix(sand_color, sand_dark, clamp(nz1 * 0.5 + 0.5, 0.0, 1.0) * 0.6);
	sand *= 0.93 + 0.07 * nz3;
	float depth_f = 1.0 - smoothstep(-35.0, 0.0, h);
	vec3 ground = mix(sand, seabed_deep, depth_f);

	// grass above the beach
	vec3 grass = mix(grass_a, grass_b, clamp(nz1 * 0.5 + 0.5 + nz2 * 0.15, 0.0, 1.0));
	float beach_top = 3.5 + nz1 * 1.5;
	float grass_w = smoothstep(beach_top, beach_top + 3.0, h);
	vec3 col = mix(ground, grass, grass_w);

	// wet sand near the waterline
	float wet = 1.0 - smoothstep(0.2, 1.3, h);
	col *= 1.0 - 0.28 * wet * (1.0 - grass_w);

	// rock on steep faces and at altitude
	vec3 rock = mix(rock_a, rock_b, clamp(nz2 * 0.5 + 0.5, 0.0, 1.0));
	rock *= 0.88 + 0.12 * sin(h * 0.9 + nz1 * 3.0);   // faint strata
	float rock_w = smoothstep(rock_slope_min, rock_slope_max, slope + nz2 * 0.05);
	rock_w = max(rock_w, smoothstep(snow_line * 0.75, snow_line * 1.1, h + nz1 * 10.0) * 0.6);
	col = mix(col, rock, rock_w);

	// snow on high, not-too-steep ground
	float snow_w = smoothstep(snow_line, snow_line + 12.0, h + nz1 * 10.0 + nz2 * 3.0);
	snow_w *= 1.0 - smoothstep(0.18, 0.42, slope);
	col = mix(col, vec3(0.93, 0.95, 0.98), snow_w);

	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.6, snow_w);
	SPECULAR = 0.2;
}
