shader_type spatial;
// Pitched roofs, roof boxes and chimneys (vertex / instance colour). Rain
// makes them darker and glossier; snow settles on the faces turned up.

global uniform float wetness;
global uniform float snow_cover;

uniform float roughness = 0.85;

void fragment() {
	vec3 col = COLOR.rgb * (1.0 - wetness * 0.22);
	float up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	float snow = snow_cover * smoothstep(0.3, 0.65, up);
	ALBEDO = mix(col, vec3(0.9, 0.92, 0.95), snow);
	ROUGHNESS = mix(mix(roughness, 0.3, wetness), 0.75, snow);
}
