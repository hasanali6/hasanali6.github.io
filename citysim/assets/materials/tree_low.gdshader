shader_type spatial;
// Low-poly tree foliage: flat-shaded facets from the mesh, colour per
// instance (MultiMesh COLOR), a soft darkening towards the bottom and a gentle
// wind sway that grows with height.

global uniform float overlay_dim;
global uniform float snow_cover;
global uniform float autumn;
uniform float sway = 0.12;
uniform float crown_height = 8.0;

varying vec3 v_color;
varying float v_height;
varying float v_seed;

void vertex() {
	v_color = COLOR.rgb;
	v_height = VERTEX.y;
	v_seed = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453);
	float phase = MODEL_MATRIX[3].x * 0.13 + MODEL_MATRIX[3].z * 0.17;
	float bend = pow(clamp(VERTEX.y / crown_height, 0.0, 1.0), 2.0) * sway;
	VERTEX.x += sin(TIME * 1.3 + phase) * bend;
	VERTEX.z += cos(TIME * 1.1 + phase * 1.3) * bend * 0.6;
}

void fragment() {
	vec3 albedo = v_color * mix(0.72, 1.05, clamp(v_height / crown_height, 0.0, 1.0));
	// Autumn: broadleaf trees turn yellow, orange or red; about a third stay green.
	vec3 leaf = mix(vec3(0.86, 0.62, 0.16), vec3(0.82, 0.36, 0.1), smoothstep(0.3, 0.7, v_seed));
	leaf = mix(leaf, vec3(0.62, 0.16, 0.09), smoothstep(0.82, 0.95, v_seed));
	float turns = step(0.32, v_seed) * autumn;
	albedo = mix(albedo, leaf * (0.75 + 0.3 * clamp(v_height / crown_height, 0.0, 1.0)), turns * 0.85);
	// Snow on the upward facets.
	float up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	albedo = mix(albedo, vec3(0.88, 0.91, 0.95), snow_cover * smoothstep(0.2, 0.65, up) * 0.85);
	ALBEDO = mix(albedo, vec3(dot(albedo, vec3(0.3, 0.55, 0.15))), overlay_dim * 0.8);
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	BACKLIGHT = v_color * 0.25;
}
