shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D height_field : filter_linear, repeat_disable;
uniform sampler2D coast_field : filter_linear, repeat_disable;
uniform float world_size = 10000.0;
uniform float heightmap_resolution = 512.0;

uniform vec3 sand_dry : source_color = vec3(0.78, 0.69, 0.49);
uniform vec3 sand_wet : source_color = vec3(0.45, 0.42, 0.34);
uniform vec3 grass_low : source_color = vec3(0.18, 0.31, 0.13);
uniform vec3 grass_high : source_color = vec3(0.34, 0.43, 0.21);
uniform vec3 rock_dark : source_color = vec3(0.26, 0.27, 0.25);
uniform vec3 rock_light : source_color = vec3(0.54, 0.51, 0.45);
uniform vec3 snow : source_color = vec3(0.88, 0.91, 0.94);
uniform vec3 shallow_seabed : source_color = vec3(0.38, 0.34, 0.25);
uniform vec3 deep_seabed : source_color = vec3(0.055, 0.10, 0.13);

varying vec3 world_position;
varying float terrain_height;
varying float signed_coast;
varying float local_slope;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 2.0 - 1.0;
}

float fbm(vec2 p) {
	float result = 0.0;
	float amplitude = 0.5;
	float norm = 0.0;
	for (int i = 0; i < 4; i++) {
		result += value_noise(p) * amplitude;
		norm += amplitude;
		p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.03 + vec2(13.1, 7.7);
		amplitude *= 0.5;
	}
	return result / norm;
}

void vertex() {
	vec2 texel = vec2(1.0 / heightmap_resolution);
	float h = textureLod(height_field, UV, 0.0).r;
	float h_l = textureLod(height_field, clamp(UV - vec2(texel.x, 0.0), vec2(0.0), vec2(1.0)), 0.0).r;
	float h_r = textureLod(height_field, clamp(UV + vec2(texel.x, 0.0), vec2(0.0), vec2(1.0)), 0.0).r;
	float h_d = textureLod(height_field, clamp(UV - vec2(0.0, texel.y), vec2(0.0), vec2(1.0)), 0.0).r;
	float h_u = textureLod(height_field, clamp(UV + vec2(0.0, texel.y), vec2(0.0), vec2(1.0)), 0.0).r;
	float sample_distance = world_size / (heightmap_resolution - 1.0);
	vec2 gradient = vec2(h_r - h_l, h_u - h_d) / (2.0 * sample_distance);
	VERTEX.y = h;
	NORMAL = normalize(vec3(-gradient.x, 1.0, -gradient.y));
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	terrain_height = h;
	signed_coast = textureLod(coast_field, UV, 0.0).r;
	local_slope = length(gradient);
}

void fragment() {
	float h = terrain_height;
	float slope = local_slope;
	vec2 p = world_position.xz;
	float macro = fbm(p * 0.0022);
	float medium = fbm(p * 0.018 + 23.7);
	float fine = value_noise(p * 0.11 + 8.4);
	vec3 color;

	if (h < 0.0) {
		float depth = clamp(-h / 560.0, 0.0, 1.0);
		color = mix(shallow_seabed, deep_seabed, smoothstep(0.02, 0.90, depth));
		color *= 0.95 + macro * 0.07 + medium * 0.025;
	} else {
		float height_beach = 1.0 - smoothstep(3.0, 16.0, h + medium * 1.2);
		float coast_beach = 1.0 - smoothstep(6.0, 55.0, max(signed_coast, 0.0));
		float beach = max(height_beach, coast_beach * 0.72);
		vec3 sand = mix(sand_wet, sand_dry, smoothstep(0.0, 7.0, h));
		vec3 grass = mix(grass_low, grass_high, clamp(0.52 + macro * 0.58 + medium * 0.14, 0.0, 1.0));
		color = mix(grass, sand, beach);

		float rock_slope = smoothstep(0.16, 0.48, slope + medium * 0.025);
		float rock_altitude = smoothstep(150.0, 260.0, h + macro * 24.0) * 0.84;
		float rock_mask = max(rock_slope, rock_altitude);
		vec3 rock = mix(rock_dark, rock_light, clamp(0.54 + macro * 0.35 + fine * 0.08, 0.0, 1.0));
		color = mix(color, rock, rock_mask);

		float snow_mask = smoothstep(320.0, 385.0, h + macro * 18.0);
		snow_mask *= 1.0 - smoothstep(0.26, 0.58, slope);
		color = mix(color, snow, snow_mask);
		color *= 0.97 + fine * 0.035;
	}

	ALBEDO = color;
	ROUGHNESS = h < 0.0 ? 0.96 : mix(0.92, 0.70, smoothstep(0.18, 0.52, slope));
	SPECULAR = 0.19;
}
