// Animated ocean surface: Gerstner waves, depth absorption, refraction and shore foam.
// Reference approach: GPU Gems 1 (Gerstner waves), Godot depth/screen textures,
// Boujie Water Shader (MIT) and Godot water-shader examples.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float wave_speed = 1.0;
uniform float wave_height = 1.0;
uniform float wave_steepness : hint_range(0.0, 1.0) = 0.38;
uniform float wave_scale = 1.0;
uniform float refraction_strength = 0.018;
uniform float foam_width = 2.6;
uniform float foam_scale = 0.19;
uniform vec3 shallow_tint : source_color = vec3(0.08, 0.48, 0.47);
uniform vec3 deep_tint : source_color = vec3(0.008, 0.055, 0.12);
uniform vec3 absorption = vec3(0.22, 0.075, 0.035);
uniform float scatter_rate = 0.055;

varying vec3 water_world_position;
varying vec3 water_world_normal;

const float TWO_PI = 6.28318530718;
// Direction xz, relative amplitude, wavelength (metres).
const vec4 WAVES[4] = vec4[4](
	vec4(1.0, 0.16, 0.95, 245.0),
	vec4(0.55, 0.82, 0.62, 147.0),
	vec4(-0.36, 0.93, 0.43, 86.0),
	vec4(0.91, -0.48, 0.28, 48.0)
);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

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
	float v = a + k1 * u.x + k2 * u.y + k4 * u.x * u.y;
	vec2 g = du * vec2(k1 + k4 * u.y, k2 + k4 * u.x);
	return vec3(v * 2.0 - 1.0, g * 2.0);
}

vec3 gerstner(vec2 p, float time, out vec3 normal) {
	vec3 offset = vec3(0.0);
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	for (int i = 0; i < 4; i++) {
		vec2 direction = normalize(WAVES[i].xy);
		float wavelength = WAVES[i].w * wave_scale;
		float k = TWO_PI / wavelength;
		float phase_speed = sqrt(9.81 / k);
		float amplitude = wave_height * WAVES[i].z * wavelength / 150.0;
		float phase = k * (dot(direction, p) - phase_speed * time * wave_speed);
		float s = sin(phase);
		float c = cos(phase);
		float q = wave_steepness;
		float ka = k * amplitude;
		offset.x += q * amplitude * direction.x * c;
		offset.z += q * amplitude * direction.y * c;
		offset.y += amplitude * s;
		tangent += vec3(-q * direction.x * direction.x * ka * s, direction.x * ka * c, -q * direction.x * direction.y * ka * s);
		binormal += vec3(-q * direction.x * direction.y * ka * s, direction.y * ka * c, -q * direction.y * direction.y * ka * s);
	}
	normal = normalize(cross(binormal, tangent));
	return offset;
}

vec3 view_position_from_depth(vec2 uv) {
	float raw_depth = texture(depth_texture, uv).x;
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw_depth);
	vec4 view_position = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	return view_position.xyz / max(view_position.w, 0.00001);
}

void vertex() {
	vec3 base_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wave_normal;
	vec3 displacement = gerstner(base_world.xz, TIME, wave_normal);
	VERTEX += displacement;
	NORMAL = wave_normal;
	water_world_position = base_world + displacement;
	water_world_normal = normalize((MODEL_MATRIX * vec4(wave_normal, 0.0)).xyz);
}

void fragment() {
	vec3 scene_view = view_position_from_depth(SCREEN_UV);
	float water_view_z = (VIEW_MATRIX * vec4(water_world_position, 1.0)).z;
	float thickness = max(water_view_z - scene_view.z, 0.0);

	vec3 large_detail = noised(water_world_position.xz * 0.035 + vec2(TIME * 0.07, -TIME * 0.04));
	vec3 fine_detail = noised(water_world_position.xz * 0.13 + vec2(-TIME * 0.11, TIME * 0.09) + 13.7);
	vec2 ripple = (large_detail.yz * 0.38 + fine_detail.yz * 0.28);
	vec3 normal_world = normalize(water_world_normal + vec3(-ripple.x, 0.0, -ripple.y));
	vec3 normal_view = normalize((VIEW_MATRIX * vec4(normal_world, 0.0)).xyz);

	vec2 refracted_uv = SCREEN_UV + normal_view.xy * refraction_strength * clamp(thickness / 30.0, 0.0, 1.0);
	vec3 refracted_view = view_position_from_depth(refracted_uv);
	if (refracted_view.z > water_view_z) {
		refracted_uv = SCREEN_UV;
		refracted_view = scene_view;
	}
	// View-space Z is negative in front of the camera; depth increases as Z becomes more negative.
	float optical_depth = max(water_view_z - refracted_view.z, 0.0);
	vec3 refracted_color = textureLod(screen_texture, refracted_uv, 0.0).rgb;
	vec3 transmittance = exp(-absorption * optical_depth);

	vec3 scene_world = (INV_VIEW_MATRIX * vec4(scene_view, 1.0)).xyz;
	float vertical_depth = max(water_world_position.y - scene_world.y, 0.0);
	float depth_blend = 1.0 - exp(-vertical_depth * 0.018);
	vec3 scatter_color = mix(shallow_tint, deep_tint, depth_blend);
	vec3 in_scatter = scatter_color * (1.0 - exp(-optical_depth * scatter_rate));

	float noise_value = noised(water_world_position.xz * foam_scale + vec2(TIME * 0.08, -TIME * 0.055)).x * 0.5 + 0.5;
	float shore_fade = 1.0 - smoothstep(0.0, foam_width, vertical_depth);
	float foam_band = 0.5 + 0.5 * sin(vertical_depth * 2.5 - TIME * 1.5 + noise_value * 5.0);
	float shore_foam = shore_fade * smoothstep(0.53, 0.86, noise_value * 0.65 + foam_band * 0.48);
	float crest_foam = smoothstep(2.0, 3.0, water_world_position.y) * smoothstep(0.65, 0.92, noise_value) * 0.45;
	float foam = clamp(shore_foam + crest_foam, 0.0, 1.0);

	float fresnel = pow(1.0 - clamp(dot(normal_view, VIEW), 0.0, 1.0), 5.0);
	vec3 water_color = refracted_color * transmittance + in_scatter;
	water_color = mix(water_color, deep_tint, fresnel * 0.38);
	water_color = mix(water_color, vec3(0.88, 0.94, 0.95), foam);

	ALBEDO = water_color;
	ROUGHNESS = mix(0.12, 0.72, foam);
	METALLIC = 0.0;
	SPECULAR = 0.62;
	ALPHA = clamp(0.78 + fresnel * 0.18 + foam * 0.12, 0.0, 0.97);
	NORMAL = normal_view;
}
