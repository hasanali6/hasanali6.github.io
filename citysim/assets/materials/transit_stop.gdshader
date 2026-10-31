shader_type spatial;
// Bus shelter / tram platform (MultiMesh). Material ids in UV.x (see
// VehicleModels.bus_stop): 0 metal, 1 glass, 2 line colour (COLOR),
// 3 bench, 4 concrete.

global uniform float night_factor;

varying float v_mat;
varying vec3 v_line;

void vertex() {
	v_mat = UV.x;
	v_line = COLOR.rgb;
}

void fragment() {
	int m = int(v_mat + 0.5);
	vec3 col = vec3(0.35, 0.37, 0.4);
	float rough = 0.4;
	float metal = 0.6;
	vec3 emit = vec3(0.0);
	if (m == 1) {
		col = vec3(0.45, 0.6, 0.65);
		rough = 0.08;
		metal = 0.1;
		emit = vec3(1.0, 0.9, 0.7) * night_factor * 0.35;
	} else if (m == 2) {
		col = v_line;
		rough = 0.3;
		metal = 0.0;
		emit = v_line * night_factor * 0.8;
	} else if (m == 3) {
		col = vec3(0.55, 0.38, 0.22);
		rough = 0.7;
		metal = 0.0;
	} else if (m == 4) {
		col = vec3(0.74, 0.73, 0.7);
		rough = 0.9;
		metal = 0.0;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
