shader_type spatial;
// Solar panel row (MultiMesh of thin boxes): deep blue cells with silver
// gaps on the top face, a light frame on the sides. Glossy so it catches
// the sun.

global uniform float night_factor;

uniform vec3 cell_color : source_color = vec3(0.1, 0.22, 0.55);
uniform vec3 frame_color : source_color = vec3(0.78, 0.8, 0.84);
uniform vec2 cells = vec2(14.0, 3.0);

varying vec3 v_local;
varying vec3 v_normal;

void vertex() {
	v_local = VERTEX;
	v_normal = NORMAL;
}

void fragment() {
	vec2 g = (v_local.xz + 0.5) * cells;
	vec2 f = abs(fract(g) - 0.5);
	vec2 fw = fwidth(g);
	vec2 line = smoothstep(vec2(0.43) - fw, vec2(0.43), f);
	// Far away the gaps shrink below a pixel: fade them into an average tint.
	float far = smoothstep(0.15, 0.45, max(fw.x, fw.y));
	float gap = mix(max(line.x, line.y), 0.12, far);
	float top = step(0.5, v_normal.y);
	vec3 col = mix(frame_color, mix(cell_color, frame_color * 0.9, gap), top);
	ALBEDO = col * mix(1.0, 0.8, night_factor);
	METALLIC = mix(0.2, 0.1, top);
	ROUGHNESS = mix(0.5, 0.32, top * (1.0 - gap));
	SPECULAR = 0.6;
}
