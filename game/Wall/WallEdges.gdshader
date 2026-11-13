shader_type spatial;
// Twelve camera-facing strips share one draw call, including their soft halos.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

global uniform float glow_fog_density;
uniform vec4 albedo_color : source_color = vec4(1.8, -0.2, -0.2, 0.0);
uniform vec3 size = vec3(1.0);
uniform float glow_radius = 0.11;

varying vec2 beam_position;
varying float beam_length;
varying vec3 world_position;

void vertex() {
	// VERTEX contains unit-box endpoints, NORMAL the edge axis, UV the strip corner.
	vec3 axis_vector = (MODEL_MATRIX * vec4(NORMAL * size, 0.0)).xyz;
	beam_length = max(length(axis_vector), 0.0001);
	// Keep the direction defined even for zero-duration barriers.
	vec3 axis = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 midpoint = (MODEL_MATRIX * vec4((VERTEX - NORMAL * (UV.y - 0.5)) * size, 1.0)).xyz;
	vec3 side = cross(axis, CAMERA_POSITION_WORLD - midpoint);
	if (length(side) < 0.0001) side = cross(axis, INV_VIEW_MATRIX[0].xyz);
	if (length(side) < 0.0001) side = cross(axis, INV_VIEW_MATRIX[1].xyz);
	side = normalize(side);
	vec3 center = (MODEL_MATRIX * vec4(VERTEX * size, 1.0)).xyz;
	world_position = center + side * (UV.x * 2.0 - 1.0) * glow_radius
		+ axis * (UV.y * 2.0 - 1.0) * glow_radius;
	beam_position = vec2((UV.x * 2.0 - 1.0) * glow_radius,
		UV.y * (beam_length + 2.0 * glow_radius) - glow_radius);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_position, 1.0);
}

void fragment() {
	float beyond_end = max(max(-beam_position.y, beam_position.y - beam_length), 0.0);
	float d = length(vec2(beam_position.x, beyond_end));
	float aa = max(fwidth(d), 0.001);
	// A 3.5 cm core in world space; the halo fades to zero at the strip boundary.
	float core = 1.0 - smoothstep(0.0175 - aa, 0.0175 + aa, d);
	float halo = exp(-d * d / 0.0022) * (1.0 - smoothstep(0.07, glow_radius, d));
	vec3 tint = clamp(albedo_color.rgb, vec3(0.0), vec3(1.0));
	float haze = exp(-distance(world_position, CAMERA_POSITION_WORLD) * glow_fog_density);
	ALBEDO = (mix(tint, vec3(1.0), 0.38) * core * 1.25 + tint * halo * 0.32) * haze;
}
