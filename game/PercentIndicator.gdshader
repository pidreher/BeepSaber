shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform vec3 color = vec3(1.0);
uniform float how_full;
uniform bool energy_bar_mode = false;

void fragment() {
	if (energy_bar_mode) {
		vec2 p = (UV - 0.5) * vec2(2.6, 0.32);
		vec2 q = abs(p) - vec2(1.25, 0.11);
		float edge = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - 0.04;
		float aa = max(fwidth(edge), 0.001);
		float coverage = 1.0 - smoothstep(-aa, aa, edge);
		if (coverage < 0.01) { discard; }
		float fill = step(UV.x, 0.025 + 0.95 * how_full) * step(0.001, how_full);
		float inset = 1.0 - smoothstep(-0.018 - aa, -0.018 + aa, edge);
		ALBEDO = mix(vec3(0.055, 0.075, 0.11), color, fill * inset);
		ALPHA = coverage * 0.96;
	} else {
		if (how_full < 0.005) { discard; }
		float x = UV.x - 0.5;
		float y = UV.y - 0.5;
		float distance_squared = x*x + y*y;
		if (distance_squared <= 0.125 || distance_squared > 0.25) { discard; }
		if (how_full < 0.995 && atan(x,y) + PI > how_full * TAU) { discard; }
		ALBEDO = color;
		ALPHA = 1.0;
	}
}
