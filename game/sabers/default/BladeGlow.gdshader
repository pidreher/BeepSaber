shader_type spatial;
// One narrow strip faces the camera; all expansion happens in world space.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.05, 0.08, 1.0);
uniform float blade_length = 1.0;
uniform float width = 0.14;

void vertex() {
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	vec3 center = (MODEL_MATRIX * vec4(0.0, VERTEX.y * (blade_length + 0.06), 0.0, 1.0)).xyz;
	vec3 side = cross(axis, normalize(CAMERA_POSITION_WORLD - center));
	// Preserve a valid billboard when looking directly along the blade.
	if (length(side) < 0.001) side = cross(axis, INV_VIEW_MATRIX[0].xyz);
	side = normalize(side);
	float thickness = length(MODEL_MATRIX[0].xyz);
	vec3 world = center + side * (UV.x - 0.5) * width * thickness;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float soft = exp(-across * across * 5.5) * (1.0 - smoothstep(0.72, 1.0, across));
	float end_distance = min(UV.y, 1.0 - UV.y) * (blade_length + 0.06);
	float ends = smoothstep(0.0, 0.055, end_distance);
	float extension = smoothstep(0.003, 0.06, blade_length);
	ALBEDO = color.rgb * soft * ends * extension * 0.65;
}
