shader_type spatial;
// Info overlay cell (MultiMesh): a solid tint with a slightly darker rim so
// neighbouring cells stay readable. Colour and opacity per instance.
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled, cull_disabled, fog_disabled;

global uniform float night_factor;

varying vec4 v_color;

void vertex() {
	v_color = COLOR;
}

void fragment() {
	vec2 e = min(UV, 1.0 - UV);
	float edge = min(e.x, e.y);
	float aa = fwidth(edge);
	float rim = 1.0 - smoothstep(0.06 - aa, 0.06 + aa, edge);
	ALBEDO = v_color.rgb * mix(1.0, 0.78, rim) * mix(1.0, 0.55, night_factor);
	ALPHA = v_color.a;
}
