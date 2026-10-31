shader_type spatial;
// Traffic light pole and head (MultiMesh). INSTANCE_CUSTOM.x = state:
// 0 red, 1 amber, 2 green. Material ids in UV.x (see VehicleModels):
// 0 pole, 1 housing, 2 red, 3 amber, 4 green lamp.

global uniform float night_factor;

varying float v_mat;
varying float v_state;

void vertex() {
	v_mat = UV.x;
	v_state = INSTANCE_CUSTOM.x;
}

void fragment() {
	int m = int(v_mat + 0.5);
	vec3 col = vec3(0.42, 0.44, 0.46);
	vec3 emit = vec3(0.0);
	float rough = 0.55;
	if (m == 1) {
		col = vec3(0.06, 0.065, 0.07);
		rough = 0.7;
	} else if (m >= 2) {
		vec3 lamp = m == 2 ? vec3(1.0, 0.12, 0.08) : (m == 3 ? vec3(1.0, 0.65, 0.05) : vec3(0.15, 1.0, 0.35));
		bool on = abs(float(m - 2) - v_state) < 0.5;
		col = on ? lamp : lamp * 0.12;
		emit = on ? lamp * mix(2.0, 4.0, night_factor) : vec3(0.0);
		rough = 0.25;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = emit;
}
