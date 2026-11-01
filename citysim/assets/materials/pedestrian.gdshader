shader_type spatial;
// Walking people (MultiMesh). Each instance walks there and back along its
// local +z for INSTANCE_CUSTOM.x metres at .y m/s, phase .z; .w hides part of
// them at night. Body part in UV.x: 0 legs, 1 shirt, 2 skin. Clothes colours
// come from the phase so no instance colours are needed.

global uniform float traffic_time;
global uniform float night_factor;

varying flat float v_part;
varying vec3 v_shirt;
varying vec3 v_legs;

vec3 palette(float k) {
	vec3 c[8] = vec3[](vec3(0.85, 0.2, 0.2), vec3(0.2, 0.45, 0.85), vec3(0.95, 0.8, 0.25), vec3(0.25, 0.65, 0.35),
		vec3(0.92, 0.92, 0.9), vec3(0.6, 0.35, 0.75), vec3(0.95, 0.55, 0.2), vec3(0.2, 0.22, 0.26));
	return c[int(k * 7.99)];
}

void vertex() {
	float len = max(INSTANCE_CUSTOM.x, 1.0);
	float speed = INSTANCE_CUSTOM.y;
	float phase = INSTANCE_CUSTOM.z;
	float f = fract((traffic_time * speed / len + phase) * 0.5) * 2.0;
	float back = step(1.0, f);
	float s = (f < 1.0 ? f : 2.0 - f) * len;
	vec3 v = VERTEX;
	// Legs swing a little: shift the lower body forward and back.
	float stride = sin(traffic_time * speed * 3.4 + phase * 40.0);
	if (UV.x < 0.5) {
		v.z += stride * 0.12 * sign(v.x);
	}
	v.y += abs(stride) * 0.035;
	if (back > 0.5) {
		v.x = -v.x;
		v.z = -v.z;
	}
	v.z += s;
	if (INSTANCE_CUSTOM.w < night_factor * 0.75) {
		v *= 0.0;
	}
	VERTEX = v;
	v_part = UV.x;
	v_shirt = palette(fract(phase * 7.31));
	v_legs = mix(vec3(0.16, 0.2, 0.32), vec3(0.3, 0.27, 0.24), step(0.5, fract(phase * 3.7)));
}

void fragment() {
	vec3 col = v_part < 0.5 ? v_legs : (v_part < 1.5 ? v_shirt : vec3(0.87, 0.68, 0.55));
	ALBEDO = col * mix(1.0, 0.6, night_factor);
	ROUGHNESS = 0.85;
}
