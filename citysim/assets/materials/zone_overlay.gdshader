shader_type spatial;
// Zoning cell overlay: tinted square with a stronger border, colour and
// opacity per instance (MultiMesh COLOR).
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
	float border = 1.0 - smoothstep(0.05 - aa, 0.05 + aa, edge);
	// Unshaded, so dim it by hand at night or it glows like neon.
	ALBEDO = mix(v_color.rgb, v_color.rgb * 0.75 + 0.25, border) * mix(1.0, 0.3, night_factor);
	ALPHA = v_color.a * mix(0.55, 1.0, border);
}
