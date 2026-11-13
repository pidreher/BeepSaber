shader_type spatial;
// Both sides remain visible when the player enters a barrier. No depth writes:
// opaque notes and scenery still occlude it, while overlapping bodies stay light.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 albedo_color : source_color = vec4(1.8, -0.2, -0.2, 0.0);
uniform vec3 size = vec3(1.0);

varying vec3 local_position;
varying vec3 local_normal;

// Small scrolling value noise, without textures or screen reads.
float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}

void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 tint = clamp(albedo_color.rgb, vec3(0.0), vec3(1.0));
	vec3 border = max(size * 0.5 - abs(local_position), vec3(0.0));
	// Ignore the face's normal axis; the other two distances find its four edges.
	border += abs(local_normal) * 10000.0;
	float edge_distance = min(border.x, min(border.y, border.z));
	float rim = 1.0 - smoothstep(0.015, 0.18, edge_distance);
	float fresnel = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 3.0);
	vec2 flow = vec2(local_position.x + local_position.z, local_position.y) * 3.0;
	float shimmer = noise(flow + vec2(TIME * 0.10, -TIME * 0.22));
	float ripple = sin(local_position.y * 20.0 + shimmer * 2.5 - TIME * 1.4);
	ALBEDO = mix(tint * 0.65, tint + vec3(0.18), rim * 0.5 + fresnel * 0.25);
	ALPHA = 0.065 + shimmer * 0.025 + ripple * 0.006 + rim * 0.095 + fresnel * 0.07;
}
