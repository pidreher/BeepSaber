shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform vec3 half_size = vec3(0.25);
uniform vec3 plane_normal = vec3(1.0, 0.0, 0.0);
uniform vec3 plane_tangent = vec3(0.0, 0.0, 1.0);
uniform float plane_dist = 0.0;
uniform float cut_vanish = 0.0;
uniform bool is_chain_head = false;
varying vec3 object_position;

void vertex() {
	vec3 bitangent = cross(plane_normal, plane_tangent);
	VERTEX = plane_normal * (plane_dist + 0.0005) + plane_tangent * VERTEX.x + bitangent * VERTEX.y;
	object_position = VERTEX;
}

void fragment() {
	if (is_chain_head && object_position.y < -0.1) discard;
	// Clip the planar cap to the rounded body; no CSG or runtime mesh rebuild.
	float rounding = min(0.035, min(half_size.x, min(half_size.y, half_size.z)) * 0.5);
	vec3 q = abs(object_position) - half_size + vec3(rounding);
	float edge = length(max(q, vec3(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0) - rounding;
	if (edge > 0.0) discard;
	vec3 cell = floor(object_position * 65.0);
	float noise = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	if (noise < smoothstep(0.12, 1.0, cut_vanish)) discard;
	float rim = smoothstep(-0.045, 0.0, edge);
	ALBEDO = mix(color.rgb * 0.4, mix(color.rgb, vec3(1.0), 0.25) * 1.8, rim) * (1.0 - cut_vanish);
}
