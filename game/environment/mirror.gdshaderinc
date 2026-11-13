// Reflective floor areas, set by the stage preset: x = half width, y = strength,
// z..w = z range. A strength of 0 disables an area.
global uniform vec4 mirror_area_a;
global uniform vec4 mirror_area_b;
global uniform float glow_fog_density;

vec3 mirror_point(vec3 p) {
	return vec3(p.x, -p.y, p.z);
}

float mirror_area(vec3 hit, vec4 area) {
	if (abs(hit.x) > area.x || hit.z < area.z || hit.z > area.w) return 0.0;
	return area.y;
}

// How strongly a mirrored point is reflected, seen from the camera. Zero outside the areas.
float mirror_visibility(vec3 mirrored_pos, vec3 camera) {
	vec3 ray = mirrored_pos - camera;
	if (camera.y <= 0.0 || ray.y >= -1e-4) return 0.0;
	vec3 hit = camera + ray * (-camera.y / ray.y);
	return max(mirror_area(hit, mirror_area_a), mirror_area(hit, mirror_area_b));
}
