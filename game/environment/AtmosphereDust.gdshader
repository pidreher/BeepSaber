shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 left_tint : source_color = vec3(0.008, 0.010, 0.018);
uniform vec3 right_tint : source_color = vec3(0.008, 0.010, 0.018);
uniform float motion = 1.0;

varying vec3 mote_color;
varying float visibility;

void vertex() {
	vec4 seed = INSTANCE_CUSTOM;
	float time = TIME * motion;
	vec3 anchor = MODEL_MATRIX[3].xyz;
	vec3 drift = vec3(0.018 + seed.w * 0.012, 0.025, -0.012) * time;
	drift.xz += vec2(sin(time * 0.19 + seed.y * 6.283),
		cos(time * 0.16 + seed.x * 6.283)) * 0.12;
	// Wrap world positions around the head, using one shared centre for both XR eyes.
	vec3 offset = mod(seed.xyz * 6.0 + drift - anchor + 3.0, 6.0) - 3.0;
	vec3 center = anchor + offset;
	float edge = max(abs(offset.x), max(abs(offset.y), abs(offset.z)));
	float distance_to_head = length(offset);
	float sparkle = 0.72 + 0.28 * sin(time * (0.7 + seed.w) + seed.z * 31.0);
	visibility = (1.0 - smoothstep(2.5, 3.0, edge))
		* smoothstep(0.55, 1.0, distance_to_head) * sparkle;
	// Dim the note corridor; the peripheral motes supply most of the depth cues.
	float corridor = (1.0 - smoothstep(0.8, 1.5, abs(offset.x)))
		* (1.0 - smoothstep(0.9, 1.4, abs(offset.y)));
	visibility *= mix(1.0, 0.28, corridor);
	float size = mix(0.006, 0.014, seed.w);
	vec3 world = center + (INV_VIEW_MATRIX[0].xyz * VERTEX.x
		+ INV_VIEW_MATRIX[1].xyz * VERTEX.y) * size;
	mote_color = mix(left_tint, right_tint, smoothstep(-2.0, 2.0, offset.x));
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float soft_disc = max(1.0 - dot(p, p), 0.0);
	ALBEDO = mote_color * (0.16 * soft_disc * soft_disc * visibility);
}
