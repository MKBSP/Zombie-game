shader_type spatial;
// Commander fog of war, drawn as a full-screen quad by scripts/3d/commander_fog.gd
// on the commander-only render layer. Each pixel's world XZ (from depth) looks up
// what the horde sees now (vis_tex) and has ever seen (seen_tex).
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D vis_tex : filter_linear;
uniform sampler2D seen_tex : filter_linear;
uniform vec4 map_rect;                 // x0, z0, width, depth in metres
uniform float unexplored = 0.05;       // brightness never seen
uniform float explored = 0.3;          // seen before, not now
uniform float building_floor = 0.3;    // the commander knows the city
uniform float glow_through = 0.7;      // bright light still reads in the fog

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

vec2 sample_fog(vec2 xz) {
	vec2 uv = (xz - map_rect.xy) / map_rect.zw;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return vec2(0.0);
	}
	return vec2(texture(vis_tex, uv).r, texture(seen_tex, uv).r);
}

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	float depth = texture(depth_tex, SCREEN_UV).x;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	vec2 f = sample_fog(world.xz);
	bool building = world.y > 0.3;
	if (building) {
		// a wall sits on the footprint edge: look a metre around so the side
		// facing a seen street lights up
		f = max(f, sample_fog(world.xz + vec2(1.2, 0.0)));
		f = max(f, sample_fog(world.xz - vec2(1.2, 0.0)));
		f = max(f, sample_fog(world.xz + vec2(0.0, 1.2)));
		f = max(f, sample_fog(world.xz - vec2(0.0, 1.2)));
	}
	float k = mix(unexplored, explored, clamp(f.y, 0.0, 1.0));
	k = mix(k, 1.0, clamp(f.x, 0.0, 1.0));
	if (building) {
		k = max(k, building_floor);
	}
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 glow = col * smoothstep(0.25, 0.9, lum) * glow_through;
	ALBEDO = col * k + glow * (1.0 - k);
}
