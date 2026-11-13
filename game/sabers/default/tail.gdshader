shader_type spatial;
// UV.x is sample age; UV.y runs from the hilt to the tip of the ribbon.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0);

void fragment() {
	float age = clamp(UV.x, 0.0, 1.0);
	float remaining = 1.0 - age;
	float fade = remaining * remaining * (1.0 - smoothstep(0.72, 1.0, age));
	float edges = smoothstep(0.0, 0.12, UV.y) * (1.0 - smoothstep(0.83, 1.0, UV.y));
	// A broad, gentle center avoids a hard sheet while keeping the sweep visible.
	float silk = mix(0.35, 1.0, sin(clamp(UV.y, 0.0, 1.0) * 3.14159265));
	ALBEDO = mix(color.rgb, vec3(1.0), remaining * 0.08) * fade * edges * silk * 0.72;
}
