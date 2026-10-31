shader_type spatial;
// Ground of a building lot, one quad per lot (MultiMesh). INSTANCE_CUSTOM.x
// picks the look: 0 garden (lush grass, hedge border, path to the street),
// 1 plaza (light paving tiles), 2 parking (asphalt with painted bays),
// 3 yard (concrete with stains). Local +z points to the street.

global uniform float night_factor;

uniform vec3 grass : source_color = vec3(0.38, 0.7, 0.3);
uniform vec3 hedge : source_color = vec3(0.17, 0.45, 0.2);
uniform vec3 paving : source_color = vec3(0.84, 0.82, 0.78);
uniform vec3 asphalt : source_color = vec3(0.27, 0.28, 0.31);
uniform vec3 concrete : source_color = vec3(0.66, 0.64, 0.6);
uniform vec3 paint : source_color = vec3(0.95, 0.95, 0.92);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec2 v_local;
varying vec2 v_size;
varying vec4 v_style;
varying vec3 v_world;

void vertex() {
	v_size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	v_local = (VERTEX.xz + 0.5) * v_size;
	v_style = INSTANCE_CUSTOM;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float band(float d, float w, float aa) {
	return 1.0 - smoothstep(w - aa, w + aa, d);
}

void fragment() {
	int kind = int(v_style.x + 0.5);
	vec2 p = v_local;
	float edge = min(min(p.x, v_size.x - p.x), min(p.y, v_size.y - p.y));
	float aa = fwidth(edge) + 0.02;
	float n = texture(noise_tex, v_world.xz / 11.0).r;
	vec3 col;
	float rough = 0.9;
	if (kind == 0) {
		col = grass * (0.88 + n * 0.24);
		float path = band(abs(p.x - v_size.x * 0.5), 0.75, aa) * step(v_size.y * 0.45, p.y);
		col = mix(col, paving * 0.95, path);
		col = mix(col, hedge * (0.85 + n * 0.3), band(edge, 0.55, aa) * (1.0 - path));
	} else if (kind == 1) {
		vec2 g = abs(fract(p / 2.0 - 0.5) - 0.5) / max(fwidth(p / 2.0), vec2(1e-4));
		float joint = 1.0 - clamp(min(g.x, g.y) - 0.5, 0.0, 1.0);
		col = paving * (0.93 + n * 0.1) * (1.0 - joint * 0.12);
		col = mix(col, paving * 0.75, band(edge, 0.35, aa));
		rough = 0.8;
	} else if (kind == 2) {
		col = asphalt * (0.92 + n * 0.14);
		float bays = band(abs(fract(p.x / 2.6) - 0.5) * 2.6, 0.08, aa * 0.5);
		float back_row = step(1.0, p.y) * step(p.y, 5.5);
		float front_row = step(v_size.y - 5.5, p.y) * step(p.y, v_size.y - 1.0);
		float lines = bays * clamp(back_row + front_row, 0.0, 1.0) * step(1.0, p.x) * step(p.x, v_size.x - 1.0);
		col = mix(col, paint, lines * 0.85);
		col = mix(col, concrete, band(edge, 0.4, aa));
		rough = 0.85;
	} else {
		col = concrete * (0.82 + n * 0.3);
		col = mix(col, asphalt * 1.3, smoothstep(0.62, 0.7, n) * 0.5);
	}
	ALBEDO = col * mix(1.0, 0.85, night_factor);
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
