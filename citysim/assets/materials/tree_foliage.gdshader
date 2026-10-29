shader_type spatial;
// Tree crown placeholder: wobbles the merged sphere lumps so silhouettes are
// irregular, darkens the underside/interior (fake ambient occlusion) and adds
// per-instance colour (MultiMesh COLOR) plus soft backlight.

uniform float crown_base = 2.6;
uniform float crown_top = 7.0;
uniform float wobble = 0.35;
uniform float ao_min = 0.45;

varying float v_height;
varying vec3 v_color;
varying float v_noise;

void vertex() {
	v_height = VERTEX.y;
	v_color = COLOR.rgb;
	float seed = MODEL_MATRIX[3].x * 0.37 + MODEL_MATRIX[3].z * 0.61;
	float w = sin(VERTEX.x * 2.9 + seed) * sin(VERTEX.y * 3.3 + VERTEX.z * 1.7) + sin(VERTEX.z * 4.1 - seed * 1.3) * 0.5;
	v_noise = w;
	VERTEX += NORMAL * w * wobble;
}

void fragment() {
	float ao = mix(ao_min, 1.0, smoothstep(crown_base, crown_top, v_height));
	ao *= 0.88 + v_noise * 0.12;
	ALBEDO = v_color * ao;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	BACKLIGHT = v_color * 0.35;
}
