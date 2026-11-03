// Ocean surface: Gerstner waves + depth-based absorption + shore foam.
//
// Sources:
//  * Gerstner wave position/normal formulas - GPU Gems ch.1 "Effective Water Simulation from Physical Models"
//  * Depth texture reconstruction            - Godot docs, "Advanced post-processing" / depth_texture
//  * Reference for structure and parameters  - godotshaders.com "Water shader 3D (Godot 4.3)" (Gerstner + foam)
//                                              and github.com/Chrisknyfe/boujie_water_shader (MIT):
//                                              refraction, depth fog, shore foam
//  * Hash without sine                       - Dave Hoskins (shadertoy 4djSRW)
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

group_uniforms Waves;
uniform float wave_speed = 1.0;
uniform float wave_height = 1.0;
uniform float wave_steepness : hint_range(0.0, 1.0) = 0.45;
uniform float wave_scale = 1.0;
uniform float detail_normal = 0.35;

group_uniforms Color;
uniform vec3 shallow_tint : source_color = vec3(0.10, 0.62, 0.64);
uniform vec3 deep_tint : source_color = vec3(0.01, 0.09, 0.20);
uniform vec3 absorption = vec3(0.40, 0.085, 0.045); // per meter, R G B
uniform float scatter_rate = 0.08;
uniform float refraction_strength = 0.04;

group_uniforms Shore;
uniform float foam_width = 1.6;
uniform float foam_scale = 0.45;
group_uniforms;

varying vec3 v_wpos;
varying vec3 v_wnormal;

const float TWO_PI = 6.28318530718;
// xy = direction, z = relative amplitude, w = wavelength (m)
const vec4 WAVES[4] = vec4[4](
	vec4(1.0, 0.2, 0.9, 62.0),
	vec4(0.6, 0.9, 0.7, 37.0),
	vec4(-0.4, 0.8, 0.5, 21.0),
	vec4(0.9, -0.5, 0.35, 12.0)
);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

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

vec3 gerstner(vec2 p, float t, out vec3 normal) {
	vec3 offs = vec3(0.0);
	vec3 T = vec3(1.0, 0.0, 0.0);
	vec3 B = vec3(0.0, 0.0, 1.0);
	for (int i = 0; i < 4; i++) {
		vec2 d = normalize(WAVES[i].xy);
		float L = WAVES[i].w * wave_scale;
		float k = TWO_PI / L;
		float c = sqrt(9.81 / k);
		float A = wave_height * WAVES[i].z * L / 60.0;
		float f = k * (dot(d, p) - c * t * wave_speed);
		float s = sin(f);
		float co = cos(f);
		float Q = wave_steepness;
		float WA = k * A;
		offs.x += Q * A * d.x * co;
		offs.z += Q * A * d.y * co;
		offs.y += A * s;
		T += vec3(-Q * d.x * d.x * WA * s, d.x * WA * co, -Q * d.x * d.y * WA * s);
		B += vec3(-Q * d.x * d.y * WA * s, d.y * WA * co, -Q * d.y * d.y * WA * s);
	}
	normal = normalize(cross(B, T));
	return offs;
}

vec3 scene_view_pos(vec2 uv, mat4 inv_proj) {
	float raw = texture(depth_texture, uv).x;
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw);
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return v.xyz / v.w;
}

void vertex() {
	vec3 base = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n;
	vec3 o = gerstner(base.xz, TIME, n);
	VERTEX += o;
	NORMAL = n;
	v_wpos = base + o;
	v_wnormal = n;
}

void fragment() {
	vec2 wp = v_wpos.xz;

	// small ripples on top of the big waves (works at any distance)
	vec3 d1 = noised(wp * 0.35 + vec2(TIME * 0.6, TIME * 0.35));
	vec3 d2 = noised(wp * 0.9 + vec2(-TIME * 0.5, TIME * 0.8) + 7.3);
	vec2 g = (d1.yz * 0.35 + d2.yz * 0.6) * detail_normal;
	vec3 wn = normalize(v_wnormal + vec3(-g.x, 0.0, -g.y));
	vec3 vn = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// water thickness along the view ray
	vec3 sp = scene_view_pos(SCREEN_UV, INV_PROJECTION_MATRIX);
	float thick0 = max(VERTEX.z - sp.z, 0.0);

	// refraction; fall back if the distorted sample lands on something in front of the water
	vec2 ruv = SCREEN_UV + vn.xy * refraction_strength * clamp(thick0 / 6.0, 0.0, 1.0);
	vec3 rp = scene_view_pos(ruv, INV_PROJECTION_MATRIX);
	if (rp.z > VERTEX.z) {
		ruv = SCREEN_UV;
		rp = sp;
	}
	float thick = max(VERTEX.z - rp.z, 0.0);

	// vertical depth below the sea level (for color and foam)
	vec3 sw = (INV_VIEW_MATRIX * vec4(sp, 1.0)).xyz;
	float vdepth = max(MODEL_MATRIX[3].y - sw.y, 0.0);

	vec3 refr = textureLod(screen_texture, ruv, 0.0).rgb;
	vec3 trans = exp(-absorption * thick);
	float depth_mix = 1.0 - exp(-vdepth * 0.07);
	vec3 scatter_col = mix(shallow_tint, deep_tint, depth_mix);
	vec3 inscatter = scatter_col * (1.0 - exp(-thick * scatter_rate)) * 0.6;

	// shore foam: animated bands that fade out with depth, plus whitecaps on wave crests
	float shore = 1.0 - smoothstep(0.0, foam_width, vdepth);
	float fn = noised(wp * foam_scale + vec2(TIME * 0.2, -TIME * 0.15)).x * 0.5 + 0.5;
	float bands = 0.5 + 0.5 * sin(vdepth * 4.0 - TIME * 1.8 + fn * 4.0);
	float foam = shore * smoothstep(0.35, 0.8, fn * 0.6 + bands * 0.5);
	float crest = smoothstep(1.1, 1.8, v_wpos.y - MODEL_MATRIX[3].y) * smoothstep(0.4, 0.8, fn);
	foam = clamp(foam + crest * 0.6, 0.0, 1.0);

	float fres = pow(1.0 - clamp(dot(vn, VIEW), 0.0, 1.0), 5.0);

	ALBEDO = vec3(foam);
	EMISSION = (refr * trans + inscatter) * (1.0 - foam) * (1.0 - fres * 0.5);
	ROUGHNESS = mix(0.03, 0.6, foam);
	METALLIC = 0.0;
	NORMAL = vn;
}
