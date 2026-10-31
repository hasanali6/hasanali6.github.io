shader_type spatial;
// Ground of a building lot, one quad per lot (MultiMesh). INSTANCE_CUSTOM.x
// picks the look: 0 garden (lush grass, hedge border, path to the street),
// 1 plaza (light paving tiles), 2 parking (asphalt with painted bays),
// 3 yard (concrete with stains), 4 sports (pitch with white lines behind a
// paved forecourt), 5 dirt (landfill earth with tyre tracks), 6 cemetery
// (lawn with gravel walks), 7 gravel (plant yards), 8 lawn (plain grass with
// a few walks). Local +z points to the street.

global uniform float night_factor;
global uniform float overlay_dim;
global uniform float wetness;
global uniform float snow_cover;
global uniform float autumn;

uniform vec3 grass : source_color = vec3(0.38, 0.7, 0.3);
uniform vec3 hedge : source_color = vec3(0.17, 0.45, 0.2);
uniform vec3 paving : source_color = vec3(0.84, 0.82, 0.78);
uniform vec3 asphalt : source_color = vec3(0.27, 0.28, 0.31);
uniform vec3 concrete : source_color = vec3(0.66, 0.64, 0.6);
uniform vec3 paint : source_color = vec3(0.95, 0.95, 0.92);
uniform vec3 pitch : source_color = vec3(0.3, 0.62, 0.27);
uniform vec3 dirt : source_color = vec3(0.47, 0.38, 0.27);
uniform vec3 gravel : source_color = vec3(0.6, 0.58, 0.55);
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
	} else if (kind == 3) {
		col = concrete * (0.82 + n * 0.3);
		col = mix(col, asphalt * 1.3, smoothstep(0.62, 0.7, n) * 0.5);
	} else if (kind == 4) {
		// Paved forecourt along the street, pitch behind it.
		float fore = step(v_size.y * 0.58, p.y);
		vec2 q = p - vec2(v_size.x * 0.5, v_size.y * 0.29);
		vec2 half_pitch = vec2(v_size.x * 0.5 - 1.6, v_size.y * 0.29 - 1.2);
		float stripes = step(0.5, fract(p.x / 3.0));
		col = pitch * (0.9 + stripes * 0.08 + n * 0.12);
		vec2 d = abs(q) - half_pitch;
		float outline = band(abs(max(d.x, d.y)), 0.12, aa);
		float centre_line = band(abs(q.x), 0.1, aa) * step(max(d.x, d.y), 0.0);
		float circle = band(abs(length(q) - min(half_pitch.x, half_pitch.y) * 0.32), 0.1, aa);
		col = mix(col, paint, clamp(outline + centre_line + circle, 0.0, 1.0) * 0.9);
		col = mix(col, paving * (0.9 + n * 0.12), fore);
		rough = 0.85;
	} else if (kind == 5) {
		col = dirt * (0.78 + n * 0.4);
		float track = band(abs(fract((p.x + p.y * 0.35) / 6.0) - 0.5) * 6.0, 0.35, aa) * smoothstep(0.35, 0.55, n);
		col = mix(col, dirt * 0.62, track * 0.6);
		col = mix(col, hedge * 0.9, band(edge, 0.7, aa));
	} else if (kind == 6) {
		col = grass * (0.82 + n * 0.22);
		float walk = band(abs(p.x - v_size.x * 0.5), 0.7, aa);
		walk = max(walk, band(abs(fract(p.y / 6.0) - 0.5) * 6.0, 0.45, aa) * step(1.5, p.x) * step(p.x, v_size.x - 1.5));
		col = mix(col, gravel * (0.95 + n * 0.1), walk);
		col = mix(col, hedge * (0.8 + n * 0.3), band(edge, 0.8, aa));
	} else if (kind == 7) {
		col = gravel * (0.8 + n * 0.3);
		col = mix(col, concrete, band(edge, 0.6, aa));
		rough = 0.95;
	} else {
		col = grass * (0.86 + n * 0.26);
		float walk = band(abs(p.x - v_size.x * 0.5), 0.9, aa) * step(v_size.y * 0.3, p.y);
		walk = max(walk, band(abs(p.y - v_size.y * 0.3), 0.8, aa));
		col = mix(col, paving * 0.95, walk);
	}
	if (kind == 0 || kind == 6 || kind >= 8) {
		col = mix(col, col * vec3(1.15, 0.95, 0.6), autumn * 0.45);
	}
	col *= 1.0 - wetness * 0.2;
	float snow_amt = snow_cover * clamp(0.7 + (n - 0.5) * 0.6, 0.0, 1.0);
	col = mix(col, vec3(0.9, 0.92, 0.95), snow_amt);
	rough = mix(mix(rough, 0.3, wetness * 0.8), 0.75, snow_amt);
	col = mix(col, vec3(dot(col, vec3(0.3, 0.55, 0.15))) * 0.85, overlay_dim * 0.8);
	ALBEDO = col * mix(1.0, 0.85, night_factor);
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
