shader_type spatial;
// Second pass of a light material: draws the geometry mirrored at the floor (y = 0),
// only where the camera sees it through a reflective floor area.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

#include "res://game/environment/mirror.gdshaderinc"

uniform vec3 color : source_color = vec3(1.0);

varying vec3 world_pos;

void vertex() {
	vec3 world = mirror_point((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
	world_pos = world;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float visible = mirror_visibility(world_pos, CAMERA_POSITION_WORLD);
	if (visible <= 0.0) discard;
	float haze = exp(-distance(world_pos, CAMERA_POSITION_WORLD) * glow_fog_density);
	ALBEDO = color * (visible * haze);
}
