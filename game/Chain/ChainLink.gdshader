shader_type spatial;
render_mode cull_disabled,diffuse_burley,specular_schlick_ggx;

const float sub_emission_energy = 0.18;
const float cut_white_margin = 0.04;

uniform vec4 color : source_color;
uniform bool cutted = false;
uniform vec3 cut_plane_normal = vec3(1.0, 0.0, 0.0);
uniform float cut_plane_dist = 0.0;
uniform float cut_vanish = 0.0;

varying float cut_interp;
varying vec3 object_position;
void vertex() {
	object_position = VERTEX;
	if (cutted) {
		cut_interp = dot(VERTEX, cut_plane_normal) - cut_plane_dist;
	} else {
		// not cut, ensure no discard later
		cut_interp = 1.0;
	}
}

void fragment() {
	if (cutted) {
		vec3 cell = floor(object_position * 65.0);
		float noise = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		if (noise < smoothstep(0.12, 1.0, cut_vanish)) discard;
	}
	// Discard all pixels "in the cut"
	if (cut_interp < 0.0) {
		discard;
	}

	ALBEDO = color.rgb;
	METALLIC = 0.3;
	ROUGHNESS = 0.2;
	if (FRONT_FACING) {
		float x_centered = UV.x - 0.25;
		float y_centered = UV.y - 0.25;
		float dist_from_center_squared = x_centered * x_centered + y_centered * y_centered;
		if (dist_from_center_squared <= 0.001) {
			EMISSION = cutted ? mix(color.rgb, vec3(1.0), 0.25) * (1.0 - cut_vanish) : vec3(1.0);
		} else {
			EMISSION = color.rgb * sub_emission_energy;
			if (cutted){
				// Colored light at the exposed edge fades with the body.
				EMISSION += mix(color.rgb, vec3(1.0), 0.25) * (1.0 - smoothstep(0.0, cut_white_margin, cut_interp)) * 2.0 * (1.0 - cut_vanish);
			}
		}
	} else {
		EMISSION = cutted ? mix(color.rgb, vec3(1.0), 0.25) * (1.0 - cut_vanish) : vec3(1.0);
	}
}
