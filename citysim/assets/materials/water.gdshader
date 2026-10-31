shader_type spatial;
// River and lake surface: colour from shallow (turquoise) to deep (blue) by
// distance from the shore, two scrolling wave normal layers, a broken foam
// line along the banks and glossy sky reflections.
#include "res://assets/materials/water_common.gdshaderinc"

global uniform float night_factor;

uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.12, 0.43, 0.6);
uniform vec3 shallow_color : source_color = vec3(0.25, 0.72, 0.79);
uniform vec3 foam_color : source_color = vec3(0.91, 0.96, 0.97);
uniform float depth_scale = 30.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz;
	float d = water_distance(p);
	float depth = clamp(-d / depth_scale, 0.0, 1.0);
	vec3 col = mix(shallow_color, deep_color, sqrt(depth));
	vec2 uv1 = p / 70.0 + TIME * vec2(0.012, 0.007);
	vec2 uv2 = p / 27.0 - TIME * vec2(0.009, 0.014);
	vec3 n1 = texture(wave_normal, uv1).xyz;
	vec3 n2 = texture(wave_normal, uv2).xyz;
	NORMAL_MAP = normalize(n1 + n2 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.55;
	float breakup = texture(noise_tex, p / 9.0 + TIME * 0.02).r;
	float foam = (1.0 - smoothstep(0.0, 3.5, -d)) * smoothstep(0.35, 0.65, breakup + (1.0 - smoothstep(0.0, 1.2, -d)) * 0.5);
	ALBEDO = mix(col, foam_color, foam * 0.8) * mix(1.0, 0.55, night_factor);
	ROUGHNESS = mix(0.04, 0.6, foam);
	SPECULAR = 0.65;
}
