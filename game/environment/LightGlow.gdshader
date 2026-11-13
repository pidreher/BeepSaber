shader_type spatial;
// Soft halo around a light bar. Each vertex sits on the bar's axis, NORMAL is the axis
// direction and UV.x runs across. Vertices are pushed sideways so the strip faces the camera.
// With `mirrored` the halo is drawn as its reflection in the floor (see Reflection.gdshader).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://game/environment/mirror.gdshaderinc"

uniform vec3 color : source_color = vec3(1.0);
uniform float intensity = 1.0;
uniform float width = 1.0;
uniform float strength = 0.75;
uniform bool mirrored = false;

varying vec3 world_pos;
varying float across;

void vertex() {
	vec3 axis = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 center = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 camera = mirrored ? mirror_point(CAMERA_POSITION_WORLD) : CAMERA_POSITION_WORLD;
	vec3 side = cross(axis, normalize(camera - center));
	side = length(side) < 1e-4 ? vec3(1.0, 0.0, 0.0) : normalize(side);
	vec3 world = center + side * (UV.x - 0.5) * width;
	if (mirrored) world = mirror_point(world);
	world_pos = world;
	across = UV.x * 2.0 - 1.0;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float reflect_factor = 1.0;
	if (mirrored) reflect_factor = mirror_visibility(world_pos, CAMERA_POSITION_WORLD);
	if (reflect_factor <= 0.0) discard;
	float falloff = exp(-across * across * 7.0) - 0.0009;
	float haze = exp(-distance(world_pos, CAMERA_POSITION_WORLD) * glow_fog_density);
	ALBEDO = color * (intensity * strength * falloff * haze * reflect_factor);
}
