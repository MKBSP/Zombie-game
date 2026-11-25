// Test museum floor: mid grey with world-aligned 1 m lines and bold 5 m lines,
// so sizes and distances read at a glance (scripts/museum/museum.gd).
shader_type spatial;

uniform vec3 base : source_color = vec3(0.34, 0.34, 0.35);
uniform vec3 line_color : source_color = vec3(0.1, 0.1, 0.1);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 1 on a grid line `every` metres apart, `px` pixels wide, anti-aliased
float grid(vec2 p, float every, float px) {
	vec2 q = p / every;
	vec2 d = abs(fract(q - 0.5) - 0.5) / fwidth(q);
	return 1.0 - clamp(min(d.x, d.y) - px, 0.0, 1.0);
}

void fragment() {
	float l = max(grid(wpos.xz, 1.0, 0.5) * 0.45, grid(wpos.xz, 5.0, 1.5));
	ALBEDO = mix(base, line_color, l);
	ROUGHNESS = 0.92;
}
