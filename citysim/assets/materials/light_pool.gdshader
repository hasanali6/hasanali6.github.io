shader_type spatial;
// Fake pool of light under a street lamp (no real lights: they are too
// expensive on phones). Additive radial glow on the ground, only at night.
render_mode blend_add, unshaded, depth_draw_never, shadows_disabled, fog_disabled, cull_disabled;

global uniform float night_factor;
uniform vec3 light_color : source_color = vec3(1.0, 0.85, 0.63);
uniform float strength = 0.55;

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float glow = pow(clamp(1.0 - r, 0.0, 1.0), 2.0);
	ALBEDO = light_color * glow * strength * night_factor;
}
