shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float wave_speed = 1.0;
uniform float wave_height = 1.0;
uniform float wave_steepness : hint_range(0.0, 1.0) = 0.34;
uniform float wave_scale = 1.0;
uniform float refraction_strength = 0.015;
uniform float foam_width = 3.2;
uniform vec3 shallow_color : source_color = vec3(0.08, 0.42, 0.42);
uniform vec3 deep_color : source_color = vec3(0.006, 0.045, 0.095);
uniform vec3 absorption = vec3(0.20, 0.075, 0.035);

varying vec3 water_world_position;
varying vec3 water_world_normal;

const float TAU = 6.28318530718;
const vec4 WAVE_DATA[4] = vec4[4](
	vec4(1.00, 0.12, 0.92, 250.0),
	vec4(0.58, 0.82, 0.66, 150.0),
	vec4(-0.36, 0.93, 0.42, 88.0),
	vec4(0.91, -0.48, 0.26, 82.0)
);

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
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

vec3 gerstner_waves(vec2 position, float time, out vec3 surface_normal) {
	vec3 offset = vec3(0.0);
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	for (int i = 0; i < 4; i++) {
		vec2 direction = normalize(WAVE_DATA[i].xy);
		float wavelength = WAVE_DATA[i].w * wave_scale;
		float k = TAU / wavelength;
		float phase_speed = sqrt(9.81 / k);
		float amplitude = wave_height * WAVE_DATA[i].z * wavelength / 150.0;
		float phase = k * (dot(direction, position) - phase_speed * time * wave_speed);
		float sine = sin(phase);
		float cosine = cos(phase);
		float qa = wave_steepness * k * amplitude;
		if (qa > 0.95) {
			qa = 0.95;
		}
		offset.x += wave_steepness * amplitude * direction.x * cosine;
		offset.z += wave_steepness * amplitude * direction.y * cosine;
		offset.y += amplitude * sine;
		tangent += vec3(-qa * direction.x * direction.x * sine, direction.x * k * amplitude * cosine, -qa * direction.x * direction.y * sine);
		binormal += vec3(-qa * direction.x * direction.y * sine, direction.y * k * amplitude * cosine, -qa * direction.y * direction.y * sine);
	}
	surface_normal = normalize(cross(binormal, tangent));
	return offset;
}

vec3 reconstruct_view_position(vec2 uv, float depth) {
	vec4 view_position = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, depth, 1.0);
	return view_position.xyz / max(view_position.w, 0.00001);
}

void vertex() {
	vec3 base_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wave_normal;
	vec3 displacement = gerstner_waves(base_world.xz, TIME, wave_normal);
	VERTEX += displacement;
	NORMAL = wave_normal;
	water_world_position = base_world + displacement;
	water_world_normal = normalize((MODEL_MATRIX * vec4(wave_normal, 0.0)).xyz);
}

void fragment() {
	vec3 scene_view_position = reconstruct_view_position(SCREEN_UV, texture(scene_depth, SCREEN_UV).r);
	float water_view_z = (VIEW_MATRIX * vec4(water_world_position, 1.0)).z;
	float thickness = max(water_view_z - scene_view_position.z, 0.0);

	float ripple_a = value_noise(water_world_position.xz * 0.025 + vec2(TIME * 0.06, -TIME * 0.045));
	float ripple_b = value_noise(water_world_position.xz * 0.11 + vec2(-TIME * 0.10, TIME * 0.08) + 17.4);
	vec2 normal_detail = vec2(dFdx(ripple_a + ripple_b), dFdy(ripple_a + ripple_b));
	vec3 world_n = normalize(water_world_normal + vec3(-normal_detail.x * 2.5, 0.0, -normal_detail.y * 2.5));
	vec3 view_n = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);

	vec2 refracted_uv = SCREEN_UV + view_n.xy * refraction_strength * clamp(thickness / 30.0, 0.0, 1.0);
	vec3 refracted_scene = reconstruct_view_position(refracted_uv, texture(scene_depth, refracted_uv).r);
	if (refracted_scene.z > water_view_z) {
		refracted_uv = SCREEN_UV;
		refracted_scene = scene_view_position;
	}
	float optical_depth = max(water_view_z - refracted_scene.z, 0.0);
	vec3 transmitted = textureLod(scene_color, refracted_uv, 0.0).rgb * exp(-absorption * optical_depth);

	float depth_mix = 1.0 - exp(-max(optical_depth, 0.0) * 0.055);
	vec3 scattering = mix(shallow_color, deep_color, depth_mix);
	vec3 water_color = mix(transmitted, scattering, clamp(1.0 - exp(-optical_depth * 0.12), 0.0, 0.88));

	float foam_noise = value_noise(water_world_position.xz * 0.19 + vec2(TIME * 0.07, -TIME * 0.05));
	float shore_foam = 1.0 - smoothstep(0.2, foam_width, thickness);
	shore_foam *= smoothstep(0.48, 0.82, foam_noise + 0.18 * sin(thickness * 2.2 - TIME * 1.4));
	float crest_foam = smoothstep(1.8, 3.0, water_world_position.y) * smoothstep(0.72, 0.94, foam_noise) * 0.35;
	float foam = clamp(shore_foam + crest_foam, 0.0, 1.0);

	float fresnel = pow(1.0 - clamp(dot(view_n, VIEW), 0.0, 1.0), 5.0);
	water_color = mix(water_color, deep_color, fresnel * 0.32);
	water_color = mix(water_color, vec3(0.9, 0.95, 0.96), foam);

	ALBEDO = water_color;
	ROUGHNESS = mix(0.12, 0.78, foam);
	SPECULAR = 0.65;
	ALPHA = clamp(0.79 + fresnel * 0.15 + foam * 0.10, 0.0, 0.97);
	NORMAL = view_n;
}
