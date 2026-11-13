shader_type spatial;
render_mode cull_disabled,diffuse_burley,specular_schlick_ggx;

uniform vec4 color : source_color;
uniform sampler2D texture_emission : hint_default_black;

uniform float metallic;
uniform float roughness;
uniform float sub_emission_energy;

uniform bool cutted = false;
uniform float cut_vanish = 0.0;
uniform float cut_white_margin = 0.04;

uniform bool is_dot = false;
uniform bool arrows_enabled = true;
uniform bool is_chain_head = false;

uniform vec3 cut_plane_normal = vec3(0,0,0);
uniform float cut_plane_dist = 0;

// fake environment reflection: the scene has no light sources, so the metal
// look comes from a procedural "studio" (dark floor, bright horizon strip,
// soft top light) reflected in the surface
uniform float shine : hint_range(0.0, 2.0) = 1.25;

// The arrow and the dot are drawn as exact shapes (in the 256 px layout of the old
// emission texture) so their edges stay sharp at any distance.
float chevron_coverage(vec2 uv) {
	vec2 p = uv * 256.0;
	float d = abs(p.x - 64.0);
	const float slope = 0.49;
	const float norm = 1.1136; // sqrt(1 + slope^2)
	float below_bottom = (p.y - (47.0 - slope * d)) / norm;
	float above_top = max(((26.5 - slope * d) - p.y) / norm, 16.0 - p.y);
	float sd = max(max(below_bottom, above_top), d - 48.0);
	return clamp(0.5 - sd / max(fwidth(sd), 1e-4), 0.0, 1.0);
}

float ring_coverage(vec2 uv) {
	float r = length(uv * 256.0 - vec2(191.5, 63.5));
	float sd = max(r - 32.0, 10.5 - r);
	return clamp(0.5 - sd / max(fwidth(sd), 1e-4), 0.0, 1.0);
}

varying vec3 object_position;
varying float cut_interp;
varying float chain_interp;
varying vec3 obj_normal;
void vertex() {
	obj_normal = NORMAL;
	object_position = VERTEX;
	if (is_chain_head) {
		chain_interp = 0.1 + VERTEX.y;
	}
	if (cutted) {
		cut_interp = dot(VERTEX, cut_plane_normal) - cut_plane_dist;
	}
}

void fragment() {
	// Object-space cells remain attached to the tumbling half. Opaque discard
	// avoids another transparent surface and its stereo sorting/fill cost.
	if (cutted) {
		vec3 cell = floor(object_position * 65.0);
		float noise = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		if (noise < smoothstep(0.12, 1.0, cut_vanish)) discard;
	}
	// Discard all pixels "in the cut"
	if (
		(cutted && cut_interp < 0.0)
		|| (is_chain_head && chain_interp < 0.0)
	) {
		discard;
	}

	ALBEDO = color.rgb * 0.7;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	if (FRONT_FACING) {
		vec2 dot_uv = vec2(UV.x+0.5, UV.y);
		// UVs are a planar projection, only show the symbol on the front face
		float front = smoothstep(0.75, 0.95, obj_normal.z);
		EMISSION = color.rgb * sub_emission_energy;
		if (is_dot || arrows_enabled)
			EMISSION += vec3(is_dot ? ring_coverage(dot_uv) : chevron_coverage(UV)) * front;

		vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 v_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		vec3 r = reflect(-v_world, n_world);
		float up = r.y;
		// Broad, soft bands only: a narrow bright strip turns into a thin line
		// along the tight rounded edges, where the normal sweeps through it.
		vec3 env = mix(vec3(0.008), vec3(0.22), smoothstep(-0.4, 0.8, up));
		float band = (up - 0.3) / 0.38;
		env += vec3(0.7) * exp(-band * band);
		env += vec3(0.8) * smoothstep(0.6, 1.0, up);
		float fresnel = pow(1.0 - clamp(dot(n_world, v_world), 0.0, 1.0), 5.0);
		// metal: reflections tinted strongly by the note colour
		vec3 f0 = mix(vec3(0.35), color.rgb * 1.2 + vec3(0.15), 0.75);
		EMISSION += env * mix(f0, vec3(1.0), fresnel) * shine;

		if (is_chain_head) {
			EMISSION += vec3( smoothstep(cut_white_margin+0.01,cut_white_margin,chain_interp) );
		}

		if (cutted){
			float band = 1.0 - smoothstep(0.0, cut_white_margin, cut_interp);
			EMISSION += mix(color.rgb, vec3(1.0), 0.25) * band * 2.0 * (1.0 - cut_vanish);
		}
	} else {
		EMISSION = cutted ? mix(color.rgb, vec3(1.0), 0.25) * (1.0 - cut_vanish) : vec3(1.0);
	}
}
