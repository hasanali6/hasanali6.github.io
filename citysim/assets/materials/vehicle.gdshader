shader_type spatial;
// Vehicles drawn and moved on the GPU (one MultiMesh per model). The CPU
// only writes an instance when a vehicle enters a new lane piece or its stop
// position changes; the vertex shader works out where it is now:
//   s(t) = s0 + v * (tau - accel * T * (1 - exp(-tau / T))), tau = t - t0
// eased into a stop at s_stop (softplus), then looked up on the lane
// polyline stored in the `lanes` texture (RGF, 1024 texels per row).
// Mirrors TrafficRules.position_at.
//
// Instance data (precision-critical values in the transform, which is
// stored as 32-bit floats by every renderer):
//   MODEL_MATRIX[0]  = (piece offset, sample count, length); count < 2 = hidden
//   MODEL_MATRIX[1]  = (next piece offset, count, length)
//   MODEL_MATRIX[2]  = (s0, t0, v)
//   MODEL_MATRIX[3]  = (s_stop, accel, 0)
//   INSTANCE_CUSTOM  = (second colour rgb, seed)
//   COLOR            = (paint rgb, beacon on)
// Material id per face in UV.x (see VehicleModels).

global uniform float traffic_time;
global uniform float night_factor;

uniform sampler2D lanes : filter_nearest;
uniform sampler2D lane_heights : filter_nearest;   // deck height per texel (overpasses)
uniform float hide_distance = 1100.0;
uniform float accel_time = 1.4;
uniform float stop_softness = 2.5;
uniform float road_height = 0.06;

varying float v_mat;
varying vec3 v_paint;
varying vec3 v_second;
varying float v_beacon;
varying float v_brake;
varying float v_seed;

vec2 lane_point(float offset, float k) {
	int i = int(offset + k + 0.5);
	return texelFetch(lanes, ivec2(i % 1024, i / 1024), 0).xy;
}

float lane_height(float offset, float k) {
	int i = int(offset + k + 0.5);
	return texelFetch(lane_heights, ivec2(i % 1024, i / 1024), 0).r;
}

void vertex() {
	vec3 piece = MODEL_MATRIX[0].xyz;
	vec3 next = MODEL_MATRIX[1].xyz;
	vec3 motion = MODEL_MATRIX[2].xyz;
	vec3 extra = MODEL_MATRIX[3].xyz;
	float tau = max(traffic_time - motion.y, 0.0);
	float lin = motion.x + motion.z * (tau - extra.y * accel_time * (1.0 - exp(-tau / accel_time)));
	float x = (extra.x - lin) / stop_softness;
	float s = x > 20.0 ? lin : extra.x - stop_softness * log(1.0 + exp(x));
	float offset = piece.x;
	float count = piece.y;
	float len = piece.z;
	if (s > len && next.y > 1.5) {
		s -= len;
		offset = next.x;
		count = next.y;
		len = next.z;
	}
	s = clamp(s, 0.0, len);
	float u = (count - 1.0) * s / max(len, 0.001);
	float k = clamp(floor(u), 0.0, max(count - 2.0, 0.0));
	vec2 a = lane_point(offset, k);
	vec2 b = lane_point(offset, k + 1.0);
	vec2 p = mix(a, b, clamp(u - k, 0.0, 1.0));
	float lift = mix(lane_height(offset, k), lane_height(offset, k + 1.0), clamp(u - k, 0.0, 1.0));
	vec2 d = b - a;
	d = dot(d, d) > 1e-8 ? normalize(d) : vec2(0.0, 1.0);
	vec3 fwd = vec3(d.x, 0.0, d.y);
	vec3 side = vec3(d.y, 0.0, -d.x);
	vec3 pos = vec3(p.x, road_height + lift, p.y);
	float scale = (piece.y < 1.5 || length(CAMERA_POSITION_WORLD - pos) > hide_distance) ? 0.0 : 1.0;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side * scale, 0.0), vec4(0.0, scale, 0.0, 0.0), vec4(fwd * scale, 0.0), vec4(pos, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(VIEW_MATRIX) * mat3(side, vec3(0.0, 1.0, 0.0), fwd);
	v_mat = UV.x;
	v_paint = COLOR.rgb;
	v_beacon = COLOR.a;
	v_second = INSTANCE_CUSTOM.rgb;
	v_seed = INSTANCE_CUSTOM.a;
	v_brake = (extra.x < 1e5 && extra.x - s < 8.0) ? 1.0 : 0.0;
}

void fragment() {
	int m = int(v_mat + 0.5);
	vec3 col = v_paint;
	float rough = 0.32;
	float metal = 0.35;
	vec3 emit = vec3(0.0);
	if (m == 1) {
		col = vec3(0.07, 0.09, 0.12);
		rough = 0.1;
		metal = 0.1;
	} else if (m == 2) {
		col = vec3(0.92, 0.92, 0.86);
		rough = 0.2;
		emit = vec3(1.0, 0.9, 0.7) * night_factor * 2.5;
	} else if (m == 3) {
		col = vec3(0.5, 0.05, 0.05);
		emit = vec3(1.0, 0.08, 0.06) * (night_factor * 0.9 + v_brake * 1.6);
	} else if (m == 4) {
		col = vec3(0.05, 0.05, 0.055);
		rough = 0.9;
		metal = 0.0;
	} else if (m == 5) {
		col = vec3(0.16, 0.17, 0.18);
		rough = 0.6;
		metal = 0.2;
	} else if (m == 6) {
		col = v_second;
	} else if (m == 7) {
		col = vec3(0.0);
		rough = 1.0;
		metal = 0.0;
	} else if (m == 8) {
		float flash = step(0.0, sin(TIME * 10.0 + v_seed * 6.2831));
		col = mix(vec3(0.9, 0.08, 0.08), vec3(0.1, 0.25, 1.0), flash);
		emit = col * 3.0 * v_beacon;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
