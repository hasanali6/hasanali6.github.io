shader_type spatial;
// Flat ground for the 4 km playable map. All variation is world-space so the
// terrain mesh stays a single cheap quad: two noise scales break up tiling,
// a dirt/dry-grass mask adds imperfection, the locked area outside the map is
// desaturated, and an optional 8 m zoning grid fades out with distance.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 grass_a : source_color = vec3(0.36, 0.42, 0.27);
uniform vec3 grass_b : source_color = vec3(0.44, 0.45, 0.31);
uniform vec3 dry_grass : source_color = vec3(0.54, 0.5, 0.37);
uniform vec3 dirt : source_color = vec3(0.42, 0.35, 0.27);
uniform vec3 border_color : source_color = vec3(0.85, 0.82, 0.75);
uniform vec3 grid_color : source_color = vec3(0.95, 0.94, 0.9);
uniform float playable_half = 2000.0;
uniform float locked_darken = 0.78;
uniform float locked_desaturate = 0.55;
uniform float cell_size = 8.0;
uniform float grid_strength = 0.0;
uniform float grid_fade_distance = 900.0;
uniform float base_roughness = 0.93;
uniform float normal_strength = 0.55;
uniform bool detail_enabled = true;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_line(vec2 p, float width_px) {
	vec2 g = p / cell_size;
	vec2 w = fwidth(g);
	vec2 d = abs(fract(g - 0.5) - 0.5) / max(w, vec2(1e-5));
	float line = 1.0 - clamp(min(d.x, d.y) - width_px + 1.0, 0.0, 1.0);
	// Fade before the lines become sub-pixel to avoid moire.
	return line * clamp(1.5 - max(w.x, w.y) * 4.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = world_pos.xz;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	// Small-scale breakup fades out with distance so the map view stays calm;
	// beyond that range the extra texture reads are skipped entirely.
	float near = detail_enabled ? 1.0 - smoothstep(250.0, 1400.0, dist) : 0.0;
	float macro = texture(noise_tex, p / 1300.0).r;
	float mid = texture(noise_tex, p / 113.0 + vec2(0.37, 0.11)).r;
	float fine = 0.5;
	if (near > 0.0) {
		fine = texture(noise_tex, p / 17.0 + vec2(0.71, 0.53)).r;
		NORMAL_MAP = texture(noise_normal, p / 9.0).xyz;
		NORMAL_MAP_DEPTH = normal_strength * near;
	}

	vec3 col = mix(grass_a, grass_b, smoothstep(0.25, 0.75, macro));
	col = mix(col, dry_grass, smoothstep(0.62, 0.85, mid * 0.5 + macro * 0.5) * 0.45);
	float dirt_mask = smoothstep(0.7, 0.84, mid * 0.55 + fine * 0.45) * near;
	col = mix(col, dirt, dirt_mask * 0.6);
	col *= 1.0 + (fine - 0.5) * 0.2 * near;

	// Locked land outside the playable square.
	float outside = max(abs(p.x), abs(p.y)) - playable_half;
	float locked = smoothstep(0.0, 60.0, outside);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, mix(col, vec3(lum), locked_desaturate) * locked_darken, locked);
	float border_w = fwidth(outside) * 1.5 + 0.6;
	float border = 1.0 - smoothstep(border_w, border_w * 2.0, abs(outside));
	col = mix(col, border_color, border * 0.55);

	float grid = grid_line(p, 1.0) * grid_strength * (1.0 - smoothstep(grid_fade_distance * 0.5, grid_fade_distance, dist));
	grid *= 1.0 - locked;
	col = mix(col, grid_color, grid);

	ALBEDO = col;
	ROUGHNESS = clamp(base_roughness - fine * 0.06 + dirt_mask * 0.03, 0.0, 1.0);
	SPECULAR = 0.35;
}
