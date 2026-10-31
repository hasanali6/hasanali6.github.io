shader_type spatial;
// Smoke or steam plume (MultiMesh of quads). Each quad turns around the
// vertical axis to face the camera, leans with the wind and shows billowing
// puffs scrolling upwards. COLOR = tint and opacity, INSTANCE_CUSTOM.x = seed.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

global uniform float night_factor;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float rise_speed = 0.07;

varying vec4 v_color;
varying float v_seed;

void vertex() {
	v_color = COLOR;
	v_seed = INSTANCE_CUSTOM.x;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float w = length(MODEL_MATRIX[0].xyz);
	float h = length(MODEL_MATRIX[1].xyz);
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	to_cam.y = 0.0;
	vec3 fwd = normalize(to_cam + vec3(0.0001, 0.0, 0.0));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	float up = VERTEX.y + 0.5;
	vec3 world = origin + right * VERTEX.x * w * mix(0.55, 1.25, up) + vec3(0.0, VERTEX.y * h, 0.0);
	world += vec3(0.8, 0.0, 0.35) * up * up * h * 0.45;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float up = 1.0 - UV.y;
	float x = UV.x - 0.5;
	float t = TIME * rise_speed;
	float n1 = texture(noise_tex, vec2(UV.x * 0.9 + v_seed, up * 0.8 - t)).r;
	float n2 = texture(noise_tex, vec2(UV.x * 1.7 - v_seed * 0.5, up * 1.6 - t * 1.7)).r;
	float n = n1 * 0.65 + n2 * 0.35;
	float half_w = mix(0.16, 0.48, sqrt(up));
	float body = 1.0 - smoothstep(half_w * 0.45, half_w, abs(x + (n - 0.5) * 0.18));
	float density = body * smoothstep(0.0, 0.06, up) * pow(1.0 - up, 1.3);
	density *= smoothstep(0.28, 0.72, n + (1.0 - up) * 0.25);
	ALBEDO = v_color.rgb * mix(0.62, 1.04, smoothstep(0.3, 0.8, n)) * mix(1.0, 0.3, night_factor);
	ALPHA = clamp(density * v_color.a * 2.6, 0.0, 0.95);
}
