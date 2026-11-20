shader_type spatial;
// Shop sign board: instance colour with a row of light "letters" on it.
// It glows at night from the global `night_factor`. Small signs far from
// the camera collapse to nothing (detail_hide_distance), like roof clutter.

global uniform float night_factor;
global uniform vec3 view_position;

uniform float detail_hide_distance = 100000.0;

varying vec3 v_local;
varying vec3 v_size;
varying float v_seed;

float hash11(float p) {
	return fract(sin(p * 127.1 + 311.7) * 43758.5453);
}

void vertex() {
	v_local = VERTEX;
	v_size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_seed = INSTANCE_CUSTOM.x;
	vec3 origin = MODEL_MATRIX[3].xyz;
	if (length(view_position - origin) > detail_hide_distance) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	vec3 base = COLOR.rgb;
	// Letters: blocks along the board's width on its front and back faces.
	float across = (v_local.x + 0.5) * v_size.x;
	float cell = floor(across / 0.42);
	float in_cell = fract(across / 0.42);
	float letter = step(0.3, hash11(cell + v_seed * 17.0)) * step(0.12, in_cell) * step(in_cell, 0.82);
	float band = step(abs(v_local.y), 0.24) * step(abs(v_local.x) * v_size.x, v_size.x * 0.5 - 0.25);
	float face = step(0.45, abs(v_local.z));
	float text = letter * band * face;
	vec3 ink = mix(vec3(1.0, 0.97, 0.88), base * 0.25, step(0.75, dot(base, vec3(0.333))));
	vec3 col = mix(base, ink, text);
	ALBEDO = col;
	ROUGHNESS = 0.5;
	EMISSION = col * night_factor * mix(0.9, 2.2, text);
}
