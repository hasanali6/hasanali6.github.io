shader_type spatial;
// Concrete sidewalk with tile joints. Segment sidewalks use UV = (lateral,
// along) so joints follow the road; junction corners (UV2.y = 1) use world
// space.
render_mode cull_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.79, 0.8, 0.83);
uniform float tile = 1.6;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = UV2.y > 0.5 ? v_world.xz : UV;
	vec2 g = p / tile;
	vec2 w = fwidth(g);
	vec2 d = abs(fract(g - 0.5) - 0.5) / max(w, vec2(1e-4));
	float joint = (1.0 - clamp(min(d.x, d.y) - 0.5, 0.0, 1.0)) * clamp(1.5 - max(w.x, w.y) * 6.0, 0.0, 1.0);
	float n = texture(noise_tex, v_world.xz / 13.0).r;
	vec3 col = base_color * (0.93 + n * 0.12);
	ALBEDO = col * (1.0 - joint * 0.18);
	ROUGHNESS = 0.9;
	SPECULAR = 0.4;
}
