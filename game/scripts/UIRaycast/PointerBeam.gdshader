shader_type spatial;
// Menu pointer beam: a thin bright core with a soft coloured glow, always facing the
// camera. The mesh is a strip along its axis (vertices on the axis, NORMAL = axis
// direction, UV.x across, UV.y from the controller (0) to the end (1)).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0);
uniform float width = 0.022;
uniform float brightness = 1.0;

varying float across;
varying float along;

void vertex() {
	vec3 axis = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 center = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 side = cross(axis, normalize(CAMERA_POSITION_WORLD - center));
	side = length(side) < 1e-4 ? vec3(1.0, 0.0, 0.0) : normalize(side);
	across = UV.x * 2.0 - 1.0;
	along = UV.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(center + side * across * width * 0.5, 1.0);
}

void fragment() {
	float core = exp(-across * across * 40.0);
	float glow = exp(-across * across * 5.0) * 0.45;
	// fades in just in front of the controller and dims a little toward the end
	float fade = smoothstep(0.0, 0.03, along) * mix(1.0, 0.6, along);
	ALBEDO = (vec3(0.85) * core + color * (core + glow)) * fade * brightness;
}
