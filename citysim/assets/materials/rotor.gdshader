shader_type spatial;
// Wind turbine rotor (MultiMesh): spins the blades around the local z axis.
// INSTANCE_CUSTOM.x = phase seed so turbines do not turn in lockstep.

uniform float speed = 1.3;

void vertex() {
	float a = TIME * speed + INSTANCE_CUSTOM.x * 6.2831;
	mat2 r = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	VERTEX.xy = r * VERTEX.xy;
	NORMAL.xy = r * NORMAL.xy;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.45;
	SPECULAR = 0.5;
}
