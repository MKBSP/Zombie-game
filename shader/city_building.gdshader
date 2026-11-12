shader_type spatial;
// Procedural facades + roofs for the OSM city. OSM has no doors/windows/shops,
// so they are laid out from data baked by assets/blender/maps/build_small_city.py:
//   UV   = (metres along this wall, metres above ground)
//   UV2  = (wall length, building height)
//   COLOR.rg = per-building random seeds;  `side` = what the wall faces.
// Floors from the real OSM height, bays from the wall length; street walls get
// doors + (sometimes) shopfronts, backs get plain windows, party walls none.
render_mode cull_disabled;

uniform bool is_roof = false;
uniform int side = 0; // 0 back, 1 alley, 2 street, 3 main (shop) street, 4 party wall
uniform bool use_tint = false; // OSM building:colour was set
uniform vec3 tint : source_color = vec3(0.8);
uniform float lit_windows : hint_range(0.0, 1.0) = 0.26;
uniform float window_glow = 3.5;
uniform float shop_glow = 1.8;
uniform float sign_glow = 2.2;
uniform float shop_chance : hint_range(0.0, 1.0) = 0.35; // side-street buildings with a shop

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float h1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float h3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1.0, 0.0)), u.x), mix(h2(i + vec2(0.0, 1.0)), h2(i + vec2(1.0, 1.0)), u.x), u.y);
}
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
vec3 pick4(float t, vec3 a, vec3 b, vec3 c, vec3 d) { return t < 0.25 ? a : (t < 0.5 ? b : (t < 0.75 ? c : d)); }
// 1 inside [a, b], anti-aliased over w
float band(float x, float a, float b, float w) {
	return clamp(smoothstep(a - w, a + w, x) - smoothstep(b - w, b + w, x), 0.0, 1.0);
}
float rect(vec2 p, vec2 a, vec2 b, float w) { return band(p.x, a.x, b.x, w) * band(p.y, a.y, b.y, w); }

vec3 sign_color(float t) {
	return t < 0.2 ? vec3(0.85, 0.12, 0.10) : (t < 0.4 ? vec3(0.10, 0.65, 0.30) : (t < 0.6 ? vec3(0.05, 0.55, 0.70)
		: (t < 0.8 ? vec3(0.95, 0.65, 0.10) : vec3(0.25, 0.30, 0.85))));
}

void fragment() {
	float seed = COLOR.r;
	float seed2 = COLOR.g;
	vec3 alb;
	vec3 emit = vec3(0.0);
	float rough = 0.92;
	float spec = 0.35;

	if (is_roof) {
		vec2 w = wpos.xz;
		float g = vnoise(w * 0.6) * 0.5 + vnoise(w * 3.0) * 0.3 + h2(floor(w * 22.0)) * 0.2;
		vec3 base = use_tint ? lin(tint) : lin(mix(vec3(0.24, 0.24, 0.25), vec3(0.40, 0.36, 0.31), seed));
		alb = base * (0.7 + 0.6 * g);
	} else {
		float u = UV.x;
		float z = UV.y;
		float L = UV2.x;
		float H = UV2.y;
		float fw = max(fwidth(u), fwidth(z)) + 1e-4; // metres per pixel
		float near = 1.0 - smoothstep(0.006, 0.03, fw); // fine detail fades with distance

		// --- wall material: brick or painted stucco/stone ---
		bool brick = seed2 < 0.62;
		vec3 wallc;
		if (use_tint) {
			wallc = lin(tint);
		} else if (brick) {
			wallc = lin(pick4(h1(seed * 3.1), vec3(0.47, 0.20, 0.14), vec3(0.55, 0.28, 0.18),
				vec3(0.38, 0.16, 0.12), vec3(0.36, 0.24, 0.18)));
		} else {
			wallc = lin(pick4(h1(seed * 5.7), vec3(0.74, 0.69, 0.60), vec3(0.58, 0.58, 0.55),
				vec3(0.68, 0.54, 0.40), vec3(0.82, 0.80, 0.76)));
		}
		alb = wallc;
		if (brick) {
			float row = floor(z / 0.077);
			float bx = u / 0.23 + 0.5 * mod(row, 2.0);
			alb *= 0.88 + 0.24 * h2(vec2(floor(bx), row) + seed * 17.0);
			float mortar = max(1.0 - smoothstep(0.0, 0.07, min(fract(bx), 1.0 - fract(bx))),
				1.0 - smoothstep(0.0, 0.12, min(fract(z / 0.077), 1.0 - fract(z / 0.077))));
			alb = mix(alb, lin(vec3(0.55, 0.53, 0.50)), mortar * near * 0.6);
		} else {
			float joint = band(fract(z / 0.6) * 0.6, -0.01, 0.012, fw);
			alb *= 1.0 - joint * near * 0.25;
			alb *= 0.92 + 0.16 * vnoise(vec2(u, z) * 1.5);
		}
		alb *= 0.9 + 0.1 * vnoise(vec2(u * 0.8, z * 0.12 + seed * 9.0)); // rain streaks
		alb *= mix(0.55, 1.0, smoothstep(0.0, 1.6, z));                    // street grime

		// --- layout ---
		bool shop = side == 3 || (side == 2 && seed < shop_chance);
		float gf = (side >= 2 && side <= 3) ? 4.0 : 3.2;          // ground floor height
		float fh = 3.0 + 0.35 * h1(seed * 11.0);                   // upper floor height
		float top = H - 0.75;                                      // parapet line
		float nb = floor(L / mix(2.6, 3.6, h1(seed * 7.0)));
		bool openings = side != 4 && nb >= 1.0 && L >= 1.6;
		float bw = L / max(nb, 1.0);
		float bi = floor(u / bw);
		float wx = (fract(u / bw) - 0.5) * bw;                    // metres from bay centre
		float wallseed = h1(seed * 31.0 + L * 0.731);              // differs per wall
		float door_bay = floor(wallseed * max(nb, 1.0));

		// cornice + parapet cap
		float cornice = band(z, top, top + 0.28, fw);
		alb = mix(alb, wallc * (brick ? 0.55 : 0.75), cornice);
		alb = mix(alb, lin(vec3(0.30)), band(z, H - 0.12, H + 1.0, fw));

		// ghost sign on blank party walls: a landmark you can steer by
		if (side == 4 && h1(seed * 13.0) < 0.25 && z > 4.0 && z < top - 1.0) {
			float s = rect(vec2(u / max(L, 0.1), (z - 4.0) / max(top - 5.0, 0.1)), vec2(0.12, 0.15), vec2(0.88, 0.85), fw / max(L, 1.0));
			alb = mix(alb, lin(sign_color(h1(seed * 19.0))) * 0.6, s * 0.65 * (0.7 + 0.3 * vnoise(vec2(u, z) * 0.8)));
		}

		if (openings) {
			// upper floors
			float k = floor((z - gf) / fh);
			float fy = z - gf - k * fh;
			bool in_upper = z >= gf && gf + (k + 1.0) * fh <= top + 0.25;
			bool small = side == 0 || side == 1;
			if (in_upper) {
				float ww = min((small ? 0.9 : 1.15) + 0.35 * h1(seed * 23.0), bw - 0.6);
				float sill = small ? 1.0 : 0.8;
				float wh = small ? 1.3 : 1.75;
				float win = rect(vec2(wx, fy), vec2(-ww * 0.5, sill), vec2(ww * 0.5, sill + wh), fw);
				float frame = rect(vec2(wx, fy), vec2(-ww * 0.5 - 0.09, sill - 0.12), vec2(ww * 0.5 + 0.09, sill + wh + 0.09), fw) - win;
				vec3 framec = brick ? lin(vec3(0.80, 0.78, 0.72)) : wallc * 0.6;
				alb = mix(alb, framec, frame);
				float r = h3(vec3(seed * 91.0, bi, k + float(side) * 13.0));
				float lit = step(r, lit_windows * (small ? 0.5 : 1.0));
				float boarded = step(0.94, r);
				float bars = max(band(wx, -0.025, 0.025, fw), band(fy - sill, wh * 0.5 - 0.025, wh * 0.5 + 0.025, fw));
				vec3 glass = lin(vec3(0.05, 0.06, 0.08));
				vec3 wood = lin(vec3(0.35, 0.25, 0.16)) * (0.8 + 0.2 * h1(floor((fy - sill) / 0.22) + bi));
				vec3 wcol = boarded > 0.5 ? wood : mix(glass, framec, bars);
				alb = mix(alb, wcol, win);
				if (boarded < 0.5) {
					rough = mix(rough, 0.08, win * (1.0 - bars));
					spec = mix(spec, 0.7, win);
					float blinds = 0.7 + 0.3 * step(0.5, fract((fy - sill) * 9.0)) * step(0.6, h1(r * 77.0));
					vec3 warm = h1(r * 51.0) < 0.15 ? vec3(0.55, 0.70, 1.0) : vec3(1.0, 0.62, 0.30);
					emit += warm * window_glow * lit * win * (1.0 - bars) * blinds * (0.6 + 0.4 * h1(r * 33.0));
				}
			}

			// ground floor
			if (z < gf) {
				if (shop) {
					float shop_id = floor(bi / 2.0) + seed * 57.0;
					float hs = h1(shop_id);
					bool shutter = hs < 0.35;
					bool is_door = mod(bi, 2.0) == 0.0;
					float glass_m = rect(vec2(wx, z), vec2(-bw * 0.5 + 0.15, 0.45), vec2(bw * 0.5 - 0.15, gf - 1.0), fw);
					float door_m = is_door ? rect(vec2(wx, z), vec2(-0.55, 0.0), vec2(0.55, 2.45), fw) : 0.0;
					float open_m = max(glass_m, door_m);
					float signb = band(z, gf - 0.9, gf - 0.2, fw);
					// shopfront frame + kickplate in dark painted metal
					alb = mix(alb, lin(vec3(0.10, 0.11, 0.11)), band(z, 0.0, gf - 0.1, fw) * (1.0 - signb));
					vec3 sc = lin(sign_color(h1(shop_id * 3.0)));
					alb = mix(alb, sc * 0.7, signb);
					// fake lettering: blocky cells in the middle of the sign band
					float cell = floor(u / 0.28);
					float letters = step(0.35, h2(vec2(cell, shop_id))) * band(z, gf - 0.75, gf - 0.35, fw)
						* band(wx, -bw * 0.5 + 0.4, bw * 0.5 - 0.4, fw) * band(fract(u / 0.28), 0.15, 0.85, fw / 0.28);
					alb = mix(alb, lin(vec3(0.92, 0.90, 0.82)), letters);
					if (h1(shop_id * 5.0) < 0.5) {
						emit += (sc * (1.0 - letters) + vec3(1.0, 0.95, 0.85) * letters) * sign_glow * signb;
					}
					if (shutter) {
						float corr = 0.8 + 0.2 * step(0.5, fract(z / 0.09));
						alb = mix(alb, lin(vec3(0.42, 0.43, 0.44)) * mix(1.0, corr, near) * (0.85 + 0.3 * vnoise(vec2(u, z) * 2.0)), open_m);
					} else {
						vec3 inside = lin(vec3(0.06, 0.06, 0.07));
						alb = mix(alb, inside, open_m);
						rough = mix(rough, 0.06, open_m);
						spec = mix(spec, 0.75, open_m);
						float lit_shop = step(h1(shop_id * 7.0), 0.5);
						float goods = 0.55 + 0.45 * smoothstep(1.0, 2.2, z) * (0.6 + 0.4 * vnoise(vec2(u * 3.0, z * 2.0)));
						emit += vec3(1.0, 0.86, 0.66) * shop_glow * lit_shop * open_m * goods;
					}
				} else if (side == 2 || side == 3) {
					// residential street: ground-floor windows + one front door per wall
					bool door = bi == door_bay;
					if (door) {
						float d = rect(vec2(wx, z), vec2(-0.55, 0.0), vec2(0.55, 2.5), fw);
						float surround = rect(vec2(wx, z), vec2(-0.75, 0.0), vec2(0.75, 2.95), fw) - d;
						vec3 dc = lin(pick4(wallseed, vec3(0.22, 0.08, 0.06), vec3(0.06, 0.16, 0.10), vec3(0.05, 0.05, 0.06), vec3(0.30, 0.20, 0.12)));
						alb = mix(alb, lin(vec3(0.70, 0.67, 0.60)), surround);
						float panel = rect(vec2(abs(wx), z), vec2(0.12, 0.25), vec2(0.42, 2.2), fw) * 0.25 * near;
						alb = mix(alb, dc * (1.0 - panel), d);
						float transom = rect(vec2(wx, z), vec2(-0.5, 2.55), vec2(0.5, 2.88), fw);
						alb = mix(alb, lin(vec3(0.05)), transom);
						emit += vec3(1.0, 0.7, 0.4) * window_glow * 0.8 * transom * step(wallseed, 0.6);
						rough = mix(rough, 0.5, d);
					} else {
						float ww = min(1.1, bw - 0.6);
						float win = rect(vec2(wx, z), vec2(-ww * 0.5, 1.0), vec2(ww * 0.5, 2.7), fw);
						float r = h3(vec3(seed * 91.0, bi, 99.0));
						alb = mix(alb, lin(vec3(0.05, 0.06, 0.08)), win);
						rough = mix(rough, 0.08, win);
						emit += vec3(1.0, 0.62, 0.30) * window_glow * step(r, lit_windows) * win;
					}
					alb = mix(alb, wallc * 0.5, band(z, 0.0, 0.5, fw) * 0.7); // stone plinth
				} else if (side == 1 || (side == 0 && bi == door_bay && wallseed < 0.4)) {
					// alley / back: one grey-green service door
					if (bi == door_bay) {
						float d = rect(vec2(wx, z), vec2(-0.5, 0.0), vec2(0.5, 2.2), fw);
						alb = mix(alb, lin(vec3(0.20, 0.25, 0.22)) * (0.8 + 0.3 * vnoise(vec2(u, z) * 4.0)), d);
						rough = mix(rough, 0.6, d);
						float lamp = rect(vec2(wx, z), vec2(-0.12, 2.45), vec2(0.12, 2.6), fw);
						emit += vec3(1.0, 0.75, 0.4) * 4.0 * lamp * step(wallseed, 0.5);
					}
				}
			}
		}
	}
	ALBEDO = alb;
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = emit;
}
