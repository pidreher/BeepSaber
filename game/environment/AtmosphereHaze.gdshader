shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 left_tint : source_color = vec3(0.008, 0.010, 0.018);
uniform vec3 right_tint : source_color = vec3(0.008, 0.010, 0.018);
uniform float motion = 1.0;

varying vec3 haze_color;
varying float world_height;
varying float phase;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 toward_camera = CAMERA_POSITION_WORLD - center;
	// Upright billboards keep the band low when the player tilts their head.
	vec3 right = normalize(vec3(toward_camera.z, 0.0, -toward_camera.x));
	vec3 world = center + right * VERTEX.x * length(MODEL_MATRIX[0].xyz)
		+ vec3(0.0, VERTEX.y * length(MODEL_MATRIX[1].xyz), 0.0);
	world_height = world.y;
	haze_color = mix(left_tint, right_tint, INSTANCE_CUSTOM.g);
	phase = INSTANCE_CUSTOM.r * 6.283;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float soft_band = max(1.0 - dot(p, p), 0.0);
	float time = TIME * motion;
	float floor_fade = smoothstep(0.05, 0.65, world_height);
	// Two gentle waves suggest wisps without noise textures or extra passes.
	float wisp = 0.78 + 0.12 * sin(p.x * 8.0 + p.y * 3.0 + phase + time * 0.07)
		+ 0.10 * sin(p.x * 13.0 - p.y * 5.0 + phase - time * 0.04);
	ALBEDO = haze_color * (0.045 * soft_band * soft_band * soft_band * wisp * floor_fade);
}
