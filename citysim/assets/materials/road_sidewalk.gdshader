shader_type spatial;
// Concrete sidewalk with tile joints. Segment sidewalks use UV = (lateral,
// along) so joints follow the road; junction corners (UV2.y = 1) use world
// space.
render_mode cull_disabled;

global uniform float wetness;
global uniform float snow_cover;
global uniform float surface_detail;

uniform sampler2D detail_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.79, 0.8, 0.83);
uniform float tile = 1.6;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = UV2.y > 0.5 ? v_world.xz : UV;
	vec2 g = p / tile;
	vec2 w = fwidth(g);
	vec2 d = abs(fract(g - 0.5) - 0.5) / max(w, vec2(1e-4));
	float joint = (1.0 - clamp(min(d.x, d.y) - 0.5, 0.0, 1.0)) * clamp(1.5 - max(w.x, w.y) * 6.0, 0.0, 1.0);
	float n = texture(noise_tex, v_world.xz / 13.0).r;
	vec3 col = base_color * (0.93 + n * 0.12);
	float detail_rough = 0.9;
	vec3 nmap = vec3(0.0, 0.0, 1.0);
	if (surface_detail > 0.5) {
		vec4 d = texture(detail_tex, v_world.xz / 2.2);
		col *= mix(vec3(1.0), d.rgb * 2.0, 0.8);
		detail_rough = d.a;
		nmap = texture(detail_normal, v_world.xz / 2.2).xyz * 2.0 - 1.0;
	}
	col *= (1.0 - joint * 0.18) * (1.0 - wetness * 0.28);
	float snow_amt = snow_cover * clamp(0.6 + (n - 0.5) * 0.8, 0.0, 1.0);
	ALBEDO = mix(col, vec3(0.9, 0.92, 0.95), snow_amt);
	ROUGHNESS = mix(mix(detail_rough, 0.25, wetness), 0.75, snow_amt);
	float near = (1.0 - smoothstep(80.0, 350.0, length(v_world - CAMERA_POSITION_WORLD))) * surface_detail;
	float bump = near * 0.7 * (1.0 - snow_amt);
	vec3 nw = normalize(vec3(nmap.x * bump, 1.0, -nmap.y * bump));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	SPECULAR = 0.4;
}
