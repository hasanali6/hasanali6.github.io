shader_type spatial;
// Horizon mountains: grass on low slopes, rock on steep or high ground,
// snow on the peaks. Vertex height drives the bands.

uniform vec3 grass_color : source_color = vec3(0.37, 0.56, 0.27);
uniform vec3 rock_color : source_color = vec3(0.49, 0.48, 0.45);
uniform vec3 snow_color : source_color = vec3(0.95, 0.96, 0.97);
uniform float snow_height = 620.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 v_world;
varying vec3 v_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = NORMAL;
}

void fragment() {
	float n = texture(noise_tex, v_world.xz / 300.0).r;
	float slope = 1.0 - clamp(v_normal.y, 0.0, 1.0);
	float rock = smoothstep(0.25, 0.5, slope + (v_world.y / snow_height) * 0.35 + (n - 0.5) * 0.2);
	vec3 col = mix(grass_color * (0.85 + n * 0.3), rock_color * (0.9 + n * 0.2), rock);
	float snow = smoothstep(snow_height - 60.0, snow_height + 40.0, v_world.y + (n - 0.5) * 120.0) * (1.0 - smoothstep(0.55, 0.8, slope));
	ALBEDO = mix(col, snow_color, snow);
	ROUGHNESS = 0.9;
}
