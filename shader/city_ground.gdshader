shader_type spatial;
// Procedural ground surfaces for the OSM city. Road/sidewalk strips carry
// UV = (metres along, metres across from centreline) from
// assets/blender/maps/build_small_city.py; the bare ground plane uses world
// position plus a baked distance-to-street mask: paved near streets, backlot
// (cracked concrete, gravel, puddles, weeds) behind the buildings.
render_mode cull_disabled;

uniform int mode = 0; // 0 ground, 1 sidewalk, 2 crossing, 3 street, 4 main street, 5 alley, 6 bike lane, 7 plaza
uniform float half_width = 4.5; // road strip half width (m) — curb / gutter position
uniform sampler2D street_mask : hint_default_black, filter_linear, repeat_disable;
uniform vec4 mask_rect = vec4(0.0, 0.0, 1.0, 1.0); // Blender x0, y0, width, height
uniform float mask_range = 16.0;
uniform float paved_width = 4.0; // metres of paving out from the street before backlot

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1.0, 0.0)), u.x), mix(h2(i + vec2(0.0, 1.0)), h2(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) { return vnoise(p) * 0.55 + vnoise(p * 2.3) * 0.3 + vnoise(p * 5.1) * 0.15; }
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
float band(float x, float a, float b, float w) {
	return clamp(smoothstep(a - w, a + w, x) - smoothstep(b - w, b + w, x), 0.0, 1.0);
}
// thin dark lines where noise crosses 0.5: cracks
float cracks(vec2 p, float fw) {
	float n = fbm(p * 0.35);
	return 1.0 - smoothstep(0.0, 0.012 + fw * 0.4, abs(n - 0.5));
}

vec3 asphalt(vec2 w, float near, float fw) {
	float n = fbm(w * 0.25);
	vec3 c = lin(vec3(0.20, 0.20, 0.21)) * (0.75 + 0.5 * n);
	c *= 0.85 + 0.3 * h2(floor(w * 30.0)) * near;               // aggregate
	c = mix(c, lin(vec3(0.13, 0.13, 0.14)), step(0.68, vnoise(w * 0.08 + 3.0)) * 0.7); // patch repairs
	c *= 1.0 - 0.5 * cracks(w, fw) * near;
	return c;
}

vec3 slabs(vec2 p, float size, vec3 base, float near, float fw, out float joint) {
	vec2 f = fract(p / size) * size;
	joint = max(band(f.x, -0.02, 0.02, fw), band(f.y, -0.02, 0.02, fw)) * near;
	vec2 cell = floor(p / size);
	vec3 c = base * (0.88 + 0.2 * h2(cell)) * (0.85 + 0.3 * fbm(p * 0.6));
	c = mix(c, base * 0.45, smoothstep(0.62, 0.8, fbm(p * 0.3 + 7.0)) * 0.6); // stains
	return c * (1.0 - joint * 0.5);
}

void fragment() {
	vec2 w = wpos.xz;
	vec2 p = UV;
	float fw = max(fwidth(w.x), fwidth(w.y)) + 1e-4;
	float near = 1.0 - smoothstep(0.01, 0.05, fw);
	vec3 c;
	float rough = 0.9;
	float joint = 0.0;

	if (mode == 1) { // sidewalk
		c = slabs(p, 1.5, lin(vec3(0.56, 0.55, 0.52)), near, fw, joint);
		float curb = 1.0 - band(abs(p.y), -1.0, half_width - 0.25, fw);
		c = mix(c, lin(vec3(0.66, 0.66, 0.64)), curb);
		c *= 1.0 - 0.6 * step(0.985, h2(floor(w * 6.0))) * near; // gum
		rough = 0.8;
	} else if (mode == 2) { // crosswalk: zebra bars across the walking line
		c = asphalt(w, near, fw);
		float bar = band(fract(p.x / 1.2), 0.0, 0.55, fw / 1.2) * band(abs(p.y), -1.0, half_width - 0.3, fw);
		float worn = 0.65 + 0.35 * fbm(w * 1.7);
		c = mix(c, lin(vec3(0.85, 0.85, 0.82)) * worn, bar * smoothstep(0.25, 0.45, worn));
		rough = 0.8;
	} else if (mode >= 3 && mode <= 6) { // roads
		c = asphalt(w, near, fw);
		float worn = smoothstep(0.2, 0.5, fbm(w * 1.3));
		if (mode == 3) { // side street: dashed white lane line
			float dash = band(abs(p.y), -1.0, 0.07, fw) * band(fract(p.x / 6.0), 0.0, 0.5, fw / 6.0);
			c = mix(c, lin(vec3(0.80, 0.80, 0.77)), dash * worn);
		} else if (mode == 4) { // main street: double yellow + white lane dashes
			float yel = band(abs(abs(p.y) - 0.13), -1.0, 0.055, fw);
			float lanes = band(abs(abs(p.y) - 2.8), -1.0, 0.07, fw) * band(fract(p.x / 6.0), 0.0, 0.5, fw / 6.0);
			c = mix(c, lin(vec3(0.85, 0.62, 0.10)), yel * worn);
			c = mix(c, lin(vec3(0.80, 0.80, 0.77)), lanes * worn);
		} else if (mode == 5) { // alley: patched concrete + centre drain + oil
			c = mix(c, lin(vec3(0.36, 0.35, 0.33)) * (0.8 + 0.3 * fbm(w * 0.5)), step(0.5, vnoise(w * 0.15)));
			c = mix(c, lin(vec3(0.15, 0.15, 0.15)), band(abs(p.y), -1.0, 0.18, fw));
		} else { // bike lane
			c = mix(c, lin(vec3(0.16, 0.42, 0.22)) * (0.8 + 0.3 * fbm(w)), worn * 0.9);
		}
		// gutter along both curbs
		c = mix(c, c * 0.6, 1.0 - band(abs(p.y), -1.0, half_width - 0.4, fw));
		// manhole covers every ~23 m along the lane
		vec2 mh = vec2(p.x - (floor(p.x / 23.0) + 0.5) * 23.0, abs(p.y) - half_width * 0.45);
		float cover = 1.0 - smoothstep(0.33, 0.33 + fw, length(mh));
		c = mix(c, lin(vec3(0.12, 0.11, 0.10)) * (0.8 + 0.3 * step(0.5, fract(length(mh) * 14.0)) * near), cover);
		rough = mix(0.88, 0.45, cover);
	} else if (mode == 7) { // plaza: brick pavers
		float row = floor(w.y / 0.1);
		vec2 q = vec2(w.x / 0.2 + 0.5 * mod(row, 2.0), w.y / 0.1);
		float j = max(band(fract(q.x), -0.05, 0.05, fw / 0.2), band(fract(q.y), -0.08, 0.08, fw / 0.1)) * near;
		c = lin(vec3(0.45, 0.27, 0.20)) * (0.85 + 0.25 * h2(floor(q))) * (1.0 - 0.5 * j);
		rough = 0.85;
	} else { // bare ground: paved frontage near streets, backlot further in
		vec2 muv = vec2((w.x - mask_rect.x) / mask_rect.z, 1.0 + (w.y + mask_rect.y) / mask_rect.w);
		float d = texture(street_mask, muv).r * mask_range;
		float paved = 1.0 - smoothstep(paved_width - 0.6, paved_width + 0.6, d + (fbm(w * 0.4) - 0.5) * 1.5);
		vec3 pave = slabs(w, 1.5, lin(vec3(0.50, 0.49, 0.46)), near, fw, joint);
		// backlot: broken concrete, gravel, weeds, puddles
		float g = fbm(w * 0.5);
		vec3 back = mix(lin(vec3(0.30, 0.29, 0.27)), lin(vec3(0.22, 0.20, 0.17)), smoothstep(0.4, 0.7, g));
		back *= 0.8 + 0.35 * h2(floor(w * 25.0)) * near;
		back *= 1.0 - 0.6 * cracks(w * 1.4, fw) * near;
		float weeds = smoothstep(0.62, 0.75, fbm(w * 0.9 + 11.0));
		back = mix(back, lin(vec3(0.16, 0.22, 0.10)) * (0.7 + 0.5 * vnoise(w * 6.0)), weeds);
		float puddle = smoothstep(0.70, 0.74, fbm(w * 0.2 + 5.0)) * (1.0 - weeds);
		back = mix(back, back * 0.35, puddle);
		c = mix(back, pave, paved);
		rough = mix(mix(0.95, 0.05, puddle), 0.8, paved);
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
}
