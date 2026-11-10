shader_type spatial;
// Placeholder building facade for a unit cube scaled per instance (MultiMesh).
// INSTANCE_CUSTOM: x = random seed, y = window width ratio, z = window spacing (m),
// w = curtain-wall amount (0 = punched windows, 1 = full glass tower).
// Windows are sized in metres from the instance scale, glass is reflective,
// walls get floor slabs, grime and per-floor tone shifts, and windows light up
// at night from the global `night_factor`. Detail fades to an average colour
// before it can alias in the distance.

global uniform float night_factor;
global uniform float wetness;
global uniform float snow_cover;
global uniform float surface_detail;

uniform sampler2D brick_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D brick_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D plaster_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D plaster_normal : hint_normal, filter_linear_mipmap, repeat_enable;

uniform vec3 glass_color : source_color = vec3(0.3, 0.36, 0.4);
uniform vec3 light_color : source_color = vec3(1.0, 0.8, 0.54);
uniform float light_energy = 2.4;
uniform float floor_height = 3.2;
uniform float ground_floor_height = 4.5;
uniform float lit_ratio = 0.3;

varying vec3 v_local;
varying vec3 v_size;
varying vec3 v_normal;
varying vec4 v_style;
varying vec3 v_wall;

float hash12(vec2 p) {
	uvec2 q = uvec2(ivec2(p + 32768.0)) * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	return float(n) / 4294967295.0;
}

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_local = (VERTEX + vec3(0.5)) * scale;
	v_size = scale;
	v_normal = NORMAL;
	v_style = INSTANCE_CUSTOM;
	v_wall = COLOR.rgb;
}

void fragment() {
	float seed = v_style.x;
	// Public buildings (services) add 2 to the window ratio: more lit
	// windows at night and a warm floodlight washing the lower walls.
	float public_b = step(1.5, v_style.y);
	float win_ratio = v_style.y - 2.0 * public_b;
	float spacing = max(v_style.z, 1.0);
	float curtain = v_style.w;

	vec3 wall = v_wall;
	float roughness = 0.88;
	float metallic = 0.0;
	vec3 emission = vec3(0.0);
	vec3 nmap = vec3(0.0, 0.0, 1.0);
	float bump = 0.0;

	if (abs(v_normal.y) > 0.5) {
		// Flat roof: dark membrane, lighter parapet rim, large weathering patches.
		vec2 to_edge = min(v_local.xz, v_size.xz - v_local.xz);
		float rim = 1.0 - smoothstep(0.35, 0.45, min(to_edge.x, to_edge.y));
		float patch = hash12(floor(v_local.xz / 5.0) + seed * 97.0);
		wall = mix(vec3(0.1, 0.1, 0.105) * (0.85 + patch * 0.3), v_wall * 0.85, rim);
		roughness = 0.95;
	} else {
		float u = abs(v_normal.x) > 0.5 ? v_local.z : v_local.x;
		float face = abs(v_normal.x) > 0.5 ? (v_normal.x > 0.0 ? 1.0 : 2.0) : (v_normal.z > 0.0 ? 3.0 : 4.0);
		float y = v_local.y - ground_floor_height;
		vec2 cell = vec2(u / spacing, y / floor_height);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		vec2 aa = fwidth(cell);
		float half_w = mix(win_ratio, 0.94, curtain) * 0.5;
		vec2 lo = vec2(0.5 - half_w, mix(0.24, 0.06, curtain));
		vec2 hi = vec2(0.5 + half_w, mix(0.86, 0.97, curtain));
		vec2 inside = smoothstep(lo - aa, lo + aa, f) * (1.0 - smoothstep(hi - aa, hi + aa, f));
		float window = inside.x * inside.y;
		float detail = clamp(1.4 - max(aa.x, aa.y) * 5.0, 0.0, 1.0);
		float coverage = (hi.x - lo.x) * (hi.y - lo.y);
		window = mix(coverage, window, detail);

		// Window surround on punched windows: a light frame, glazing bars and
		// a shadow line under the sill (no extra texture reads).
		float trim = 0.0;
		float sill = 0.0;
		if (curtain < 0.5 && y >= 0.0) {
			vec2 fr = vec2(0.16 / spacing, 0.16 / floor_height);
			vec2 outer = smoothstep(lo - fr - aa, lo - fr + aa, f) * (1.0 - smoothstep(hi + fr - aa, hi + fr + aa, f));
			float bar_x = 1.0 - smoothstep(0.0, 0.05 / spacing + aa.x, abs(f.x - 0.5));
			float bar_y = 1.0 - smoothstep(0.0, 0.05 / floor_height + aa.y, abs(f.y - mix(lo.y, hi.y, 0.58)));
			window *= 1.0 - max(bar_x, bar_y) * detail;
			trim = outer.x * outer.y * (1.0 - window) * detail;
			float below = lo.y - fr.y - f.y;
			sill = outer.x * step(0.0, below) * (1.0 - smoothstep(0.0, 0.14 / floor_height, below)) * detail;
		}

		if (y < 0.0) {
			// Ground floor: tall shop-front glazing with piers.
			float bay = fract(u / 6.0);
			float shop = smoothstep(0.45, 0.6, v_local.y) * (1.0 - smoothstep(3.5, 3.7, v_local.y));
			window = shop * smoothstep(0.06, 0.1, bay) * (1.0 - smoothstep(0.9, 0.94, bay));
			id = vec2(floor(u / 6.0), -1.0);
		}

		// Front door on houses and small blocks (the face turned to the street).
		float door = 0.0;
		float door_frame = 0.0;
		if (face == 3.0 && ground_floor_height < 0.1 && floor_height < 3.5 && v_size.y < 13.0) {
			float du = abs(u - v_size.x * 0.5);
			float daa = fwidth(u) + 0.01;
			float in_h = 1.0 - smoothstep(2.15 - daa, 2.15 + daa, v_local.y);
			door = (1.0 - smoothstep(0.55 - daa, 0.55 + daa, du)) * in_h;
			float around = (1.0 - smoothstep(0.72 - daa, 0.72 + daa, du)) * (1.0 - smoothstep(2.32 - daa, 2.32 + daa, v_local.y));
			door_frame = around * (1.0 - door);
			window *= 1.0 - around;
			trim *= 1.0 - around;
			sill *= 1.0 - around;
		}

		// Imperfection: grime near the ground and below sills, slab lines, tone shifts.
		float grime = mix(0.78, 1.0, smoothstep(0.0, 3.0, v_local.y));
		float streak = 1.0 - (1.0 - smoothstep(0.0, 0.25, f.y)) * 0.06 * detail * (1.0 - curtain);
		float slab = 1.0 - (1.0 - smoothstep(0.0, 0.05 + aa.y, abs(f.y - 0.02))) * 0.14 * detail;
		float tone = 0.93 + hash12(vec2(id.y, seed * 13.0 + face)) * 0.1;
		wall *= tone * slab * grime * streak;

		// Wall material: brick on some low and mid-rise buildings, plaster
		// elsewhere, faded out before it can shimmer in the distance.
		if (surface_detail > 0.5) {
			vec2 wuv = vec2(u, v_local.y);
			bool brick = curtain < 0.5 && fract(seed * 7.13) < 0.38 && v_size.y < 30.0;
			// Bricks are drawn larger than life (courses about 25 cm) so
			// they still read at the game camera's distance on a phone.
			vec2 buv = brick ? wuv / vec2(1.9, 1.75) : wuv / 2.6;
			float wfade = clamp(1.6 - max(fwidth(buv.x), fwidth(buv.y)) * (brick ? 7.0 : 3.0), 0.0, 1.0) * (1.0 - window);
			vec4 det = brick ? texture(brick_tex, buv) : texture(plaster_tex, buv);
			wall *= mix(vec3(1.0), det.rgb * 2.0, wfade * (brick ? 0.95 : 0.7));
			roughness = mix(roughness, det.a, wfade);
			nmap = (brick ? texture(brick_normal, buv) : texture(plaster_normal, buv)).xyz * 2.0 - 1.0;
			bump = wfade * (brick ? 0.9 : 0.5);
		}

		float rnd = hash12(id + vec2(face * 131.0, seed * 71.0));
		float share = mix(lit_ratio, 0.8, public_b);
		float lit = step(rnd, share) * night_factor;
		float warm = hash12(id.yx + seed);
		vec3 lamp = mix(light_color, vec3(0.85, 0.9, 1.0), step(0.8, warm)) * (0.6 + warm * 0.6);
		if (y < 0.0) {
			// Shop fronts stay open in the evening: most are lit, brighter.
			lit = step(rnd, 0.85) * night_factor;
			lamp = mix(light_color, vec3(1.0, 0.95, 0.85), 0.5) * 1.5;
		}
		// Blinds / curtains: some windows read lighter or darker.
		vec3 glass = glass_color * (0.75 + rnd * 0.45) * (1.0 - 0.7 * night_factor);
		// The glass sits back in the wall: shaded under the lintel, a touch
		// of sky towards the bottom.
		float pane = clamp((f.y - lo.y) / max(hi.y - lo.y, 1e-3), 0.0, 1.0);
		glass *= mix(1.12, 0.62, smoothstep(0.7, 1.0, pane) * detail * (1.0 - curtain));
		// Frame, sill shadow and door before the glass goes in.
		vec3 trim_col = mix(v_wall, vec3(0.96, 0.95, 0.92), 0.78);
		wall = mix(wall, trim_col, trim);
		wall *= 1.0 - sill * 0.32;
		vec3 door_col = mix(vec3(0.42, 0.24, 0.14), mix(vec3(0.16, 0.3, 0.42), vec3(0.5, 0.14, 0.12), step(0.5, fract(seed * 3.7))),
			step(0.45, fract(seed * 1.93)));
		wall = mix(wall, trim_col, door_frame);
		wall = mix(wall, door_col * (0.8 + 0.2 * smoothstep(0.0, 2.15, v_local.y)), door);
		wall = mix(wall, glass, window);
		roughness = mix(roughness, 0.06 + rnd * 0.08, window);
		metallic = mix(0.0, 0.35, window);
		// In the distance use a dimmed average instead of noisy per-window hashing;
		// a full average reads as glowing walls rather than scattered lights.
		float lit_window = mix(share * coverage * night_factor * 0.35, lit * window, detail);
		emission = lamp * light_energy * lit_window;
		// Floodlights at the foot of public buildings, fading up the wall.
		float wash = public_b * night_factor * (1.0 - smoothstep(0.0, 9.0, v_local.y)) * (1.0 - window);
		emission += v_wall * light_color * 0.55 * wash;
	}

	// Weather: rain darkens the walls, snow settles on flat roofs.
	wall *= 1.0 - wetness * 0.12;
	roughness = mix(roughness, roughness * 0.6, wetness);
	float roof_snow = snow_cover * step(0.5, v_normal.y);
	wall = mix(wall, vec3(0.9, 0.92, 0.95), roof_snow);
	roughness = mix(roughness, 0.75, roof_snow);
	if (bump > 0.0) {
		vec3 n_view = NORMAL;
		vec3 up_v = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
		vec3 t = normalize(cross(up_v, n_view));
		vec3 b = cross(n_view, t);
		NORMAL = normalize(n_view + (t * nmap.x + b * nmap.y) * bump);
	}
	ALBEDO = wall;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = 0.5;
	EMISSION = emission;
}
