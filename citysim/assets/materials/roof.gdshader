shader_type spatial;
// Pitched roofs, roof boxes and chimneys (vertex / instance colour). Rain
// makes them darker and glossier; snow settles on the faces turned up.

global uniform float wetness;
global uniform float snow_cover;

global uniform float surface_detail;

uniform float roughness = 0.85;
uniform bool tiles = false;
uniform sampler2D tile_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tile_normal : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 v_world;
varying float v_rise;   // 0 at the eaves, 1 at the ridge (gable mesh height)

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_rise = VERTEX.y;
	// The unit roof is stretched differently along each axis per instance,
	// and instance transforms turn normals with the plain matrix. Dividing
	// by the squared scale first gives the true surface direction, so the
	// slopes are lit as slopes (and not as near-vertical walls).
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	NORMAL = normalize(NORMAL / max(s * s, vec3(1e-6)));
}

void fragment() {
	vec3 col = COLOR.rgb * (1.0 - wetness * 0.22);
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float up = wn.y;
	float rough = roughness;
	if (tiles && up > 0.2 && up < 0.95) {
		// Shape that reads from far away: a shaded strip along the eaves
		// and a lighter ridge cap.
		col *= mix(0.78, 1.0, smoothstep(0.0, 0.1, v_rise));
		col = mix(col, col * 1.18 + 0.03, smoothstep(0.9, 0.96, v_rise));
		// Fired clay keeps its colour in full sun: a little deeper and more
		// saturated, so sunlit slopes do not wash out to cream.
		col = mix(vec3(dot(col, vec3(0.299, 0.587, 0.114))), col, 1.3) * 0.85;
	}
	if (tiles && surface_detail > 0.5 && up > 0.2 && up < 0.95) {
		// Tile rows run along the ridge: v follows height, u runs across the
		// slope. The tiles are drawn larger than life (rows about 45 cm) so
		// they still read at the game camera's distance on a phone.
		vec2 slope = normalize(wn.xz + vec2(1e-4));
		vec2 uv = vec2(dot(v_world.xz, vec2(-slope.y, slope.x)) / 2.5, -v_world.y / 2.0);
		float fade = clamp(1.6 - max(fwidth(uv.x), fwidth(uv.y)) * 9.0, 0.0, 1.0);
		vec4 d = texture(tile_tex, uv);
		// Far away the tiles average out: keep that average tone instead of
		// jumping back to the plain colour.
		col *= mix(vec3(0.46), d.rgb * 2.0, fade);
		rough = mix(rough, d.a, fade);
		vec3 nm = texture(tile_normal, uv).xyz * 2.0 - 1.0;
		vec3 up_v = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
		vec3 t = normalize(cross(up_v, NORMAL));
		vec3 b = cross(NORMAL, t);
		NORMAL = normalize(NORMAL + (t * nm.x + b * nm.y) * fade * 0.8);
	}
	float snow = snow_cover * smoothstep(0.3, 0.65, up);
	ALBEDO = mix(col, vec3(0.9, 0.92, 0.95), snow);
	ROUGHNESS = mix(mix(rough, 0.3, wetness), 0.75, snow);
}
