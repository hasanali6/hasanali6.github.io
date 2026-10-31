shader_type spatial;
// Low-poly tree foliage: flat-shaded facets from the mesh, colour per
// instance (MultiMesh COLOR), a soft darkening towards the bottom and a gentle
// wind sway that grows with height.

uniform float sway = 0.12;
uniform float crown_height = 8.0;

varying vec3 v_color;
varying float v_height;

void vertex() {
	v_color = COLOR.rgb;
	v_height = VERTEX.y;
	float phase = MODEL_MATRIX[3].x * 0.13 + MODEL_MATRIX[3].z * 0.17;
	float bend = pow(clamp(VERTEX.y / crown_height, 0.0, 1.0), 2.0) * sway;
	VERTEX.x += sin(TIME * 1.3 + phase) * bend;
	VERTEX.z += cos(TIME * 1.1 + phase * 1.3) * bend * 0.6;
}

void fragment() {
	ALBEDO = v_color * mix(0.72, 1.05, clamp(v_height / crown_height, 0.0, 1.0));
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	BACKLIGHT = v_color * 0.25;
}
