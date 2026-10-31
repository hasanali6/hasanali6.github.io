shader_type spatial;
// Floating warning badge (MultiMesh of quads): a coloured disc with a white
// rim and a white icon, always facing the camera. Its size grows with camera
// distance so it stays readable when zoomed out, and it bobs gently.
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D icon : source_color, filter_linear;
uniform vec4 badge_color : source_color = vec4(0.95, 0.6, 0.1, 1.0);
uniform float size_per_m = 0.036;
uniform float min_size = 6.0;
uniform float max_size = 40.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float dist = length(CAMERA_POSITION_WORLD - origin);
	float s = clamp(dist * size_per_m, min_size, max_size);
	origin.y += s * 0.5 + sin(TIME * 2.6 + origin.x * 0.05) * s * 0.06;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, vec4(origin, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float aa = fwidth(r) * 1.5;
	float rim = smoothstep(0.84 - aa, 0.84 + aa, r);
	vec4 ic = texture(icon, (UV - 0.5) * 1.55 + 0.5);
	float inside = 1.0 - smoothstep(0.78, 0.8, r);
	vec3 col = mix(badge_color.rgb, vec3(1.0), rim);
	col = mix(col, vec3(1.0), ic.a * inside);
	// Soft shadow ring under the rim for contrast on light ground.
	col *= mix(1.0, 0.75, smoothstep(0.93, 1.0, r));
	ALBEDO = col;
}
