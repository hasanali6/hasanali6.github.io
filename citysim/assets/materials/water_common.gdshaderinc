// Water shapes shared by the terrain and water shaders; mirrors MapWater.distance().
uniform vec2 river_points[96];
uniform int river_count = 0;
uniform float river_half = 40.0;
uniform vec4 lakes[4];
uniform int lake_count = 0;

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
	return length(pa - ba * h);
}

// Signed distance to the nearest water edge in metres (negative = water).
float water_distance(vec2 p) {
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
	return d;
}
