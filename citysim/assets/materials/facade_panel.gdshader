shader_type spatial;
// A building's street face painted from an AI front elevation (school,
// hospital). Instance colour tints it (abandoned buildings go grey); cut-out
// pixels (alpha) are dropped. At night some of the glass glows warm.

global uniform float night_factor;

uniform sampler2D facade_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 window_grid = vec2(10.0, 6.0);  // cells used to pick lit windows

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 t = texture(facade_tex, UV);
	if (t.a < 0.5) {
		discard;
	}
	vec3 col = t.rgb * COLOR.rgb;
	ALBEDO = col;
	ROUGHNESS = 0.8;
	// Glass: bluish and not too bright. Lit in about half of the cells.
	float glass = smoothstep(0.04, 0.14, t.b - t.r) * (1.0 - smoothstep(0.5, 0.7, dot(t.rgb, vec3(0.333))));
	float lit = step(0.45, hash12(floor(UV * window_grid)));
	EMISSION = vec3(1.0, 0.82, 0.52) * glass * lit * night_factor * 0.75;
}
