shader_type spatial;
// Camera-facing soft disc for the cut splash (ring_width > 0 draws a ring instead).
// Colour and fade come from the particle colour.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform float ring_width = 0.0;
uniform float intensity = 1.0;

void vertex() {
	mat4 billboard = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float scale = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard * mat4(vec4(scale, 0, 0, 0), vec4(0, scale, 0, 0),
		vec4(0, 0, scale, 0), vec4(0, 0, 0, 1));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a;
	if (ring_width > 0.0) {
		float x = (d - 0.78) / ring_width;
		a = exp(-x * x);
	} else {
		float c = clamp(1.0 - d, 0.0, 1.0);
		a = c * c * (0.6 + 0.4 * c);
	}
	ALBEDO = COLOR.rgb * a * intensity;
	ALPHA = COLOR.a;
}
