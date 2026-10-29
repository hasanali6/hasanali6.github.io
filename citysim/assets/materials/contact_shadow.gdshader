shader_type spatial;
// Cheap ambient-occlusion "skirt" under buildings (the Mobile renderer has no
// SSAO). A ground quad slightly larger than the footprint multiplies the
// ground darker near the walls. INSTANCE_CUSTOM.xy = footprint size in metres.
render_mode blend_mul, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float spread = 4.0;
uniform float strength = 0.45;

varying vec2 v_local;
varying vec2 v_half;

void vertex() {
	vec2 scale = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	v_local = VERTEX.xz * scale;
	v_half = INSTANCE_CUSTOM.xy * 0.5;
}

void fragment() {
	vec2 d = max(abs(v_local) - v_half, vec2(0.0));
	float dist = length(d);
	float occ = (1.0 - smoothstep(0.0, spread, dist)) * strength;
	ALBEDO = vec3(1.0 - occ);
}
