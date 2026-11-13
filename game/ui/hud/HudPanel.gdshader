shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

uniform vec4 accent : source_color = vec4(0.25, 0.55, 1.0, 1.0);
uniform bool multiplier_panel = false;
uniform float ring_progress : hint_range(0.0, 1.0) = 0.0;
uniform float song_progress : hint_range(0.0, 1.0) = 0.0;

float rounded_box(vec2 p, vec2 half_size, float radius) {
	vec2 q = abs(p) - half_size + radius;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void fragment() {
	vec2 p = vec2(UV.x - 0.5, 0.5 - UV.y) * vec2(1.4, 0.8);
	float edge = rounded_box(p, vec2(0.697, 0.397), 0.055);
	float aa = max(fwidth(edge), 0.001);
	float coverage = 1.0 - smoothstep(-aa, aa, edge);
	if (coverage < 0.01) { discard; }
	vec3 ink = vec3(0.035, 0.046, 0.072);
	float border = smoothstep(-0.009 - aa, -0.009 + aa, edge);
	ink = mix(ink, mix(vec3(0.18, 0.21, 0.28), accent.rgb, 0.25), border);
	float header = 1.0 - smoothstep(0.003, 0.003 + aa, abs(p.y - 0.36));
	header *= 1.0 - smoothstep(0.54, 0.58, abs(p.x));
	ink = mix(ink, accent.rgb, header * 0.85);

	if (multiplier_panel) {
		vec2 r = p - vec2(-0.34, 0.08);
		float radius = length(r);
		float ring = 1.0 - smoothstep(0.011, 0.011 + aa, abs(radius - 0.205));
		float angle = mod(atan(r.x, r.y) + TAU, TAU) / TAU;
		float filled = step(angle, ring_progress) * step(0.001, ring_progress);
		ink = mix(ink, mix(vec3(0.17, 0.20, 0.27), accent.rgb, filled), ring);
		float bar = 1.0 - smoothstep(-aa, aa, rounded_box(p - vec2(0.0, -0.205), vec2(0.55, 0.014), 0.012));
		float elapsed = step(p.x, -0.55 + 1.1 * song_progress) * step(0.001, song_progress);
		ink = mix(ink, mix(vec3(0.17, 0.20, 0.27), accent.rgb, elapsed), bar);
	} else {
		float divider = (1.0 - smoothstep(0.001, 0.001 + aa, abs(p.y + 0.015))) * step(abs(p.x), 0.55);
		ink = mix(ink, vec3(0.18, 0.21, 0.28), divider);
	}
	ALBEDO = ink;
	ALPHA = coverage * 0.94;
}
