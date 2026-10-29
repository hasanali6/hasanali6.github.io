shader_type spatial;
// Placeholder asphalt: world-space noise for wear, darker patch repairs and
// slightly glossier tyre-polished areas.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.17, 0.17, 0.18);
uniform vec3 patch_color : source_color = vec3(0.11, 0.11, 0.12);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float wear = texture(noise_tex, p / 41.0).r;
	float grain = texture(noise_tex, p / 2.3).r;
	float patch = smoothstep(0.68, 0.7, texture(noise_tex, p / 23.0 + vec2(0.3, 0.7)).r);
	vec3 col = base_color * (0.85 + wear * 0.3) * (0.92 + grain * 0.16);
	col = mix(col, patch_color, patch * 0.8);
	ALBEDO = col;
	ROUGHNESS = clamp(0.9 - wear * 0.12 - patch * 0.05, 0.0, 1.0);
	SPECULAR = 0.4;
}
