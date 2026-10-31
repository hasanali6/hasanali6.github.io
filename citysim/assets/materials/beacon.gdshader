shader_type spatial;
// Red aircraft warning light on tall buildings: blinks once every two
// seconds (phase per building in INSTANCE_CUSTOM.x), bright at night.
render_mode unshaded, shadows_disabled;

global uniform float night_factor;

varying float v_phase;

void vertex() {
	v_phase = INSTANCE_CUSTOM.x;
}

void fragment() {
	float t = fract(TIME * 0.5 + v_phase);
	float on = smoothstep(0.0, 0.05, t) * (1.0 - smoothstep(0.35, 0.45, t));
	vec3 red = vec3(1.0, 0.08, 0.05);
	ALBEDO = red * mix(0.35, 1.0, on);
	EMISSION = red * on * mix(0.6, 5.0, night_factor);
}
