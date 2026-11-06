shader_type spatial;
// Burning building (MultiMesh of upright quads, one per flame or smoke puff):
// always turned to the camera around the vertical axis. Flames are additive
// and flicker; smoke puffs rise, grow and fade on a loop.
// INSTANCE_CUSTOM: r = seed 0..1, g = size in metres, b = 1 for smoke.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;

varying float v_seed;
varying float v_smoke;
varying float v_phase;

void vertex() {
	v_seed = INSTANCE_CUSTOM.r;
	float size = INSTANCE_CUSTOM.g;
	v_smoke = INSTANCE_CUSTOM.b;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = size;
	if (v_smoke > 0.5) {
		// Each puff loops: rises 3 sizes while growing and fading.
		v_phase = fract(TIME * 0.18 + v_seed);
		origin.y += v_phase * size * 3.0;
		origin.x += sin(TIME * 0.5 + v_seed * 20.0) * size * 0.3 * v_phase;
		h = size * (0.6 + v_phase * 1.2);
	} else {
		v_phase = 0.0;
		h = size * (0.85 + 0.25 * sin(TIME * 9.0 + v_seed * 31.0));
	}
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	vec3 fwd = normalize(vec3(to_cam.x, 0.0, to_cam.z) + vec3(1e-4, 0.0, 0.0));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	float w = v_smoke > 0.5 ? h : size * 0.7;
	// Upright billboard standing on the origin (the quad's bottom edge).
	VERTEX.y += 0.5;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * w, 0.0), vec4(0.0, h, 0.0, 0.0), vec4(fwd, 0.0), vec4(origin, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	if (v_smoke > 0.5) {
		float r = length(uv * 2.0 - 1.0);
		float puff = (1.0 - smoothstep(0.3, 1.0, r)) * (0.75 + 0.25 * noise(uv * 4.0 + v_seed * 9.0));
		ALBEDO = vec3(0.18, 0.17, 0.17) + vec3(0.2) * v_phase;
		ALPHA = puff * 0.8 * (1.0 - v_phase) * smoothstep(0.0, 0.15, v_phase);
	} else {
		// Flame: a tapering tongue (wide at the bottom), broken up by
		// upward-scrolling noise; white-yellow core, orange-red edge.
		float y = 1.0 - uv.y;
		float n = noise(vec2(uv.x * 5.0 + v_seed * 13.0, y * 4.0 - TIME * 3.5));
		float width = mix(0.48, 0.05, pow(y, 0.8)) * (0.75 + 0.5 * n);
		float d = abs(uv.x - 0.5) / max(width, 1e-3);
		float flame = (1.0 - smoothstep(0.45, 1.0, d)) * (1.0 - smoothstep(0.75, 1.0, y + n * 0.25));
		if (flame < 0.02) {
			discard;
		}
		vec3 col = mix(vec3(1.0, 0.25, 0.05), vec3(1.0, 0.85, 0.35), smoothstep(0.3, 0.9, flame * (1.0 - y)));
		ALBEDO = col * 2.2;
		ALPHA = flame;
	}
}
