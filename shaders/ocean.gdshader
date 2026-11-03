shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
uniform vec4 shallow_color : source_color = vec4(0.12, 0.48, 0.52, 0.88);
uniform vec4 deep_color : source_color = vec4(0.012, 0.105, 0.19, 0.94);
uniform float wave_height = 1.15;
uniform float wave_frequency = 0.012;
uniform float wave_speed = 0.75;
varying vec2 ocean_uv;
void vertex() {
 ocean_uv = VERTEX.xz; float t = TIME * wave_speed;
 float a = sin((VERTEX.x + VERTEX.z * 0.42) * wave_frequency + t);
 float b = cos((VERTEX.z - VERTEX.x * 0.31) * wave_frequency * 1.7 - t * 1.23);
 VERTEX.y += (a * 0.65 + b * 0.35) * wave_height;
}
void fragment() {
 float p = sin(ocean_uv.x * 0.025 + TIME * 0.12) * cos(ocean_uv.y * 0.021);
 float d = clamp(0.62 + p * 0.12, 0.0, 1.0);
 ALBEDO = mix(shallow_color.rgb, deep_color.rgb, d); ROUGHNESS = 0.19; METALLIC = 0.12; SPECULAR = 0.82;
 ALPHA = mix(shallow_color.a, deep_color.a, d);
}
