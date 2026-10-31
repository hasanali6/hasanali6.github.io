shader_type spatial;
// Street lamp head: plain diffuser by day, glowing at night.
global uniform float night_factor;
uniform vec3 body_color : source_color = vec3(0.85, 0.87, 0.9);
uniform vec3 light_color : source_color = vec3(1.0, 0.85, 0.63);
uniform float light_energy = 3.0;

void fragment() {
	ALBEDO = mix(body_color, light_color, 0.5);
	ROUGHNESS = 0.5;
	EMISSION = light_color * light_energy * night_factor;
}
