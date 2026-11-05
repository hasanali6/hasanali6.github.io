// Water shapes shared by the terrain and water shaders; mirrors MapWater.distance().
uniform vec2 river_points[96];
uniform int river_count = 0;
uniform float river_half = 40.0;
uniform vec4 lakes[4];
uniform int lake_count = 0;
uniform float coast_z = 1e9;       // sea south of the wavy shoreline (MapWater.coast_at)
// Baked distance field (tools/gen_water_sdf.py): one texel read instead of a
// search over every river segment per pixel.
uniform sampler2D water_sdf : filter_linear, repeat_disable;
uniform bool sdf_ready = false;
uniform float sdf_extent = 8192.0;
uniform float sdf_range = 64.0;
uniform vec3 coast_waves[2];       // amplitude, wavelength, phase

// Signed distance to the sea shore (negative = sea).
float coast_distance(vec2 p) {
	if (coast_z > 1e8) {
		return 1e9;
	}
	float z = coast_z;
	float slope = 0.0;
	for (int k = 0; k < 2; k++) {
		vec3 w = coast_waves[k];
		float a = p.x * 6.2831853 / w.y + w.z;
		z += w.x * sin(a);
		slope += w.x * 6.2831853 / w.y * cos(a);
	}
	return (z - p.y) / sqrt(1.0 + slope * slope);
}

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
	return length(pa - ba * h);
}

// Signed distance to the nearest water edge in metres (negative = water).
float water_distance(vec2 p) {
	if (sdf_ready) {
		vec2 uv = p / sdf_extent + 0.5;
		if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) {
			return (texture(water_sdf, uv).r - 0.5) * 2.0 * sdf_range;
		}
		// Beyond the baked area only the open sea is near enough to matter.
		return min(coast_distance(p), sdf_range);
	}
	// Out at sea the river and lakes are far away: the shore is all that
	// matters, and the per-pixel river search is skipped.
	float sea = coast_distance(p);
	if (sea < -120.0) {
		return sea;
	}
	float d = 1e9;
	// Coarse pass over every 4th point; skip the fine pass when far away.
	for (int i = 0; i < 92; i += 4) {
		if (i + 4 >= river_count) {
			d = min(d, segment_distance(p, river_points[i], river_points[river_count - 1]));
			break;
		}
		d = min(d, segment_distance(p, river_points[i], river_points[i + 4]));
	}
	if (d - river_half < 160.0) {
		d = 1e9;
		for (int i = 0; i < 95; i++) {
			if (i + 1 >= river_count) {
				break;
			}
			d = min(d, segment_distance(p, river_points[i], river_points[i + 1]));
		}
	}
	d -= river_half;
	for (int j = 0; j < 4; j++) {
		if (j >= lake_count) {
			break;
		}
		vec4 l = lakes[j];
		d = min(d, (length((p - l.xy) / l.zw) - 1.0) * min(l.z, l.w));
	}
	return min(d, sea);
}
