shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

void fragment() {
	ALBEDO = COLOR.rgb * 1.6;
	ALPHA = COLOR.a;
}
