shader_type spatial;
// One asphalt shader for every road type and junction. Per-vertex data:
//   CUSTOM0 = (lanes per direction, one-way flag, median width, lane width)
//             all zero for junction patches -> no lane markings
//   UV      = (lateral offset from the centre line, distance along the road) metres
//   UV2.x   = distance to the nearest junction mouth (crosswalk zone)
render_mode cull_disabled;

global uniform float wetness;
global uniform float snow_cover;
global uniform float surface_detail;

uniform sampler2D detail_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float detail_scale = 3.5;

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

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
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
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float near = (1.0 - smoothstep(120.0, 520.0, dist)) * surface_detail;
	float detail_rough = 0.86;
	vec3 nmap = vec3(0.0, 0.0, 1.0);
	if (surface_detail > 0.5) {
		vec4 d = texture(detail_tex, v_world.xz / detail_scale);
		col *= mix(vec3(1.0), d.rgb * 2.0, 0.85);
		detail_rough = d.a;
		nmap = texture(detail_normal, v_world.xz / detail_scale).xyz * 2.0 - 1.0;
	}
	// Wear and repairs ("decals" drawn in the shader): darker, smoother wheel
	// paths and an oil line in each lane, patched rectangles of newer
	// asphalt and the odd manhole cover.
	float in_road = lanes > 0.5 ? 1.0 - step(half_road - 0.3, abs(x)) : 0.0;
	if (in_road > 0.0) {
		float hm = oneway ? -half_road : median * 0.5;
		float lx = oneway ? x - hm : abs(x) - hm;
		float lane_id = floor(lx / lane_w);
		float lc = lx - (lane_id + 0.5) * lane_w;
		float tracks = exp(-pow(abs(lc) - 0.85, 2.0) / 0.05);
		float oil = exp(-lc * lc / 0.12) * smoothstep(0.35, 0.7, grain);
		col *= 1.0 - tracks * 0.07 - oil * 0.12;
		detail_rough -= tracks * 0.06 - oil * 0.0;
		vec2 cell = vec2(floor(s / 7.0), lane_id + (x < 0.0 ? 17.0 : 0.0));
		float h = hash12(cell);
		if (h < 0.07) {
			vec2 fc = vec2(fract(s / 7.0) * 7.0, lc + lane_w * 0.5);
			vec2 lo = vec2(0.8 + h * 10.0, 0.25);
			vec2 hi = vec2(4.5 + h * 20.0, lane_w - 0.35);
			float inside = step(lo.x, fc.x) * step(fc.x, hi.x) * step(lo.y, fc.y) * step(fc.y, hi.y);
			float seam = inside * (1.0 - smoothstep(0.0, 0.08, min(min(fc.x - lo.x, hi.x - fc.x), min(fc.y - lo.y, hi.y - fc.y))));
			col = mix(col, col * 0.78, inside);
			col *= 1.0 - seam * 0.35;
			detail_rough = mix(detail_rough, 0.92, inside);
		}
		float mh = hash12(vec2(floor(s / 41.0), lane_id + 3.0));
		if (mh < 0.35) {
			vec2 c = vec2(fract(s / 41.0) * 41.0 - 20.5, lc);
			float r = length(c);
			float lid = 1.0 - smoothstep(0.34, 0.36, r);
			float ring = smoothstep(0.3, 0.32, r) * lid;
			float grid = step(0.5, fract((c.x + c.y) * 5.0)) * 0.15;
			col = mix(col, vec3(0.2, 0.2, 0.21) * (0.9 + grid), lid);
			col = mix(col, vec3(0.32, 0.32, 0.33), ring);
			detail_rough = mix(detail_rough, 0.55, lid);
		}
	}
	float paint = clamp(white + yellow, 0.0, 1.0) * (0.85 + wear * 0.15);
	vec3 paint_col = yellow > white ? center_color : marking_color;
	vec3 base = mix(col, paint_col, paint);
	float rough = mix(detail_rough - wear * 0.1, 0.6, paint);
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
	// Road surfaces are flat: bend the up normal by the detail map directly
	// (works without mesh tangents). Puddles and snow smooth it out.
	float bump = near * 0.9 * (1.0 - paint * 0.7) * (1.0 - snow_amt) * (1.0 - puddle);
	vec3 nw = normalize(vec3(nmap.x * bump, 1.0, -nmap.y * bump));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
