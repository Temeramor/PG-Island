shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
 vec3 base = COLOR.rgb;
 float broad_noise = sin(world_position.x * 0.017 + sin(world_position.z * 0.013)) * 0.025;
 float fine_noise = sin(world_position.x * 0.19) * sin(world_position.z * 0.17) * 0.018;
 ALBEDO = clamp(base + vec3(broad_noise + fine_noise), vec3(0.0), vec3(1.0));
 ROUGHNESS = 0.92; SPECULAR = 0.22;
}
