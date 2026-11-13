shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform bool is_dot = false;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	// A broad soft halo with a restrained center keeps the white symbol crisp.
	float halo = exp(-radius * radius * 3.5) * (1.0 - smoothstep(0.65, 1.0, radius));
	float core = is_dot ? 0.32 : 0.26;
	ALBEDO = color.rgb;
	ALPHA = halo * core;
}
