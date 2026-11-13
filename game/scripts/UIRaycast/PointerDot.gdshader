shader_type spatial;
// Glowing dot where the menu pointer hits a panel; always faces the camera and draws
// over the panel.
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float core = smoothstep(0.32, 0.2, r);
	float glow = exp(-r * r * 6.0) * 0.6;
	ALBEDO = vec3(1.0) * core + color * glow;
}
