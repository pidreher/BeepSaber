shader_type spatial;
// Stereo-correct light ribbons: no screen textures, volumetric fog or bloom required.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
#include "res://game/environment/mirror.gdshaderinc"

uniform vec3 light_0 : source_color = vec3(0.0);
uniform vec3 light_1 : source_color = vec3(0.0);
uniform vec3 light_2 : source_color = vec3(0.0);
uniform vec3 light_3 : source_color = vec3(0.0);
uniform vec3 light_4 : source_color = vec3(0.0);
uniform float stage_time = 0.0;
uniform float halo_strength = 1.0;
uniform bool mirrored = false;

varying vec3 tint;
varying vec3 world_pos;
varying float style;
varying float energy;

vec3 sweep(vec3 point, float seed, float along) {
	// A coherent slow sweep; its base remains anchored to each floor fixture.
	point.x += sin(stage_time * 0.24 + seed * 1.8) * along * 2.0 * sign(point.x);
	point.z += sin(stage_time * 0.19 + seed * 2.0) * along * 3.0;
	return point;
}

void vertex() {
	int group = int(round(COLOR.r * 4.0));
	tint = group == 0 ? light_0 : (group == 1 ? light_1 : (group == 2 ? light_2 : (group == 3 ? light_3 : light_4)));
	style = UV2.y;
	energy = COLOR.b;
	vec3 center = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 axis = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (style < 0.5) {
		vec3 moved = sweep(center, COLOR.g, UV.y);
		axis = normalize(axis + (moved - center) / 45.0);
		center = moved;
	}
	vec3 camera = mirrored ? mirror_point(CAMERA_POSITION_WORLD) : CAMERA_POSITION_WORLD;
	vec3 side = cross(axis, normalize(camera - center));
	side = length(side) < 0.0001 ? vec3(1.0, 0.0, 0.0) : normalize(side);
	float taper = style < 0.5 ? mix(0.25, 1.0, UV.y) : 1.0;
	vec3 world = center + side * (UV.x - 0.5) * UV2.x * taper;
	if (mirrored) world = mirror_point(world);
	world_pos = world;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float reflect_factor = mirrored ? mirror_visibility(world_pos, CAMERA_POSITION_WORLD) : 1.0;
	if (reflect_factor <= 0.0) discard;
	float across = abs(UV.x * 2.0 - 1.0);
	float halo = exp(-across * across * 8.0) * 0.32 * halo_strength;
	float aa = max(fwidth(across), 0.01);
	float core = 1.0 - smoothstep(0.04 - aa, 0.18 + aa, across);
	float ends = smoothstep(0.0, 0.025, UV.y) * (1.0 - smoothstep(0.9, 1.0, UV.y));
	float flow = 1.0;
	if (style > 0.5 && style < 1.5) {
		// A gentle travelling highlight down the edge, never across the note lanes.
		float pulse = pow(max(0.0, sin(UV.y * 65.0 + stage_time * 2.8)), 12.0);
		flow = 0.45 + pulse * 0.8;
	}
	float haze = exp(-distance(world_pos, CAMERA_POSITION_WORLD) * 0.012);
	vec3 hot_core = mix(tint, vec3(max(tint.r, max(tint.g, tint.b))), 0.32);
	ALBEDO = (tint * halo + hot_core * core * 1.8) * (energy * ends * flow * haze * reflect_factor);
}
