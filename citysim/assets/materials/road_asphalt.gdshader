shader_type spatial;
// One asphalt shader for every road type and junction. Per-vertex data:
//   CUSTOM0 = (lanes per direction, one-way flag, median width, lane width)
//             all zero for junction patches -> no lane markings
//   UV      = (lateral offset from the centre line, distance along the road) metres
//   UV2.x   = distance to the nearest junction mouth (crosswalk zone)
render_mode cull_disabled;

global uniform float wetness;
global uniform float snow_cover;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 asphalt_color : source_color = vec3(0.23, 0.24, 0.27);
uniform vec3 marking_color : source_color = vec3(0.95, 0.95, 0.93);
uniform vec3 center_color : source_color = vec3(0.95, 0.76, 0.19);
uniform float marking_width = 0.16;
uniform float dash_length = 3.0;
uniform float dash_gap = 5.0;
uniform float crosswalk_length = 3.2;
uniform float crosswalk_stripe = 0.6;

varying vec4 v_lanes;
varying vec3 v_world;

void vertex() {
	v_lanes = CUSTOM0;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float line_at(float x, float centre, float width, float aa) {
	return 1.0 - smoothstep(width * 0.5 - aa, width * 0.5 + aa, abs(x - centre));
}

void fragment() {
	float x = UV.x;
	float s = UV.y;
	float aa = max(fwidth(x), 0.002);
	float lanes = floor(v_lanes.x + 0.5);
	bool oneway = v_lanes.y > 0.5;
	float median = v_lanes.z;
	float lane_w = v_lanes.w;
	float half_road = lanes * lane_w * (oneway ? 0.5 : 1.0) + median * 0.5;
	float dash = step(fract(s / (dash_length + dash_gap)), dash_length / (dash_length + dash_gap));

	float white = 0.0;
	float yellow = 0.0;
	if (lanes > 0.5) {
		float inset = 0.45;
		white += line_at(abs(x), half_road - inset, marking_width, aa);
		if (oneway) {
			for (float k = 1.0; k < 8.0; k += 1.0) {
				if (k >= lanes) break;
				white += line_at(x, -half_road + k * lane_w, marking_width, aa) * dash;
			}
		} else {
			float hm = median * 0.5;
			if (median > 0.01) {
				yellow += line_at(abs(x), hm + 0.35, marking_width, aa);
			} else {
				yellow += line_at(abs(x), 0.14, marking_width, aa);
			}
			for (float k = 1.0; k < 8.0; k += 1.0) {
				if (k >= lanes) break;
				white += line_at(abs(x), hm + k * lane_w, marking_width, aa) * dash;
			}
		}
		// Zebra crossing at junction mouths.
		float zone = 1.0 - smoothstep(crosswalk_length - 0.05, crosswalk_length + 0.05, UV2.x);
		zone *= smoothstep(0.35, 0.45, UV2.x);
		float stripe = step(fract(x / (crosswalk_stripe * 2.0)), 0.5);
		float inside = 1.0 - step(half_road - 0.6, abs(x));
		white = max(white * (1.0 - zone), zone * stripe * inside);
		yellow *= 1.0 - zone;
	}

	float wear = texture(noise_tex, v_world.xz / 37.0).r;
	float grain = texture(noise_tex, v_world.xz / 3.1).r;
	vec3 col = asphalt_color * (0.9 + wear * 0.2) * (0.94 + grain * 0.12);
	float paint = clamp(white + yellow, 0.0, 1.0) * (0.85 + wear * 0.15);
	vec3 paint_col = yellow > white ? center_color : marking_color;
	vec3 base = mix(col, paint_col, paint);
	float rough = mix(0.86 - wear * 0.1, 0.6, paint);
	// Rain: darker, glossy asphalt with puddles in the worn hollows.
	float puddle = smoothstep(0.56, 0.72, wear + (grain - 0.5) * 0.25) * wetness;
	base *= 1.0 - wetness * 0.32 - puddle * 0.25;
	rough = mix(rough, 0.06, clamp(wetness * 0.7 + puddle * 0.8, 0.0, 0.95));
	// Snow: the driven lanes stay mostly clear, the curbs fill up.
	float edge = lanes > 0.5 ? smoothstep(half_road - 1.4, half_road, abs(x)) : 0.2;
	float snow_amt = snow_cover * clamp(0.16 + edge * 0.75 + (wear - 0.5) * 0.35, 0.0, 1.0);
	base = mix(base, vec3(0.9, 0.92, 0.95), snow_amt);
	rough = mix(rough, 0.72, snow_amt);
	ALBEDO = base;
	ROUGHNESS = rough;
	SPECULAR = mix(0.35, 0.6, wetness);
}
