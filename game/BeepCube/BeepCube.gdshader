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
uniform float shine : hint_range(0.0, 2.0) = 0.9;

varying float cut_interp;
varying float chain_interp;
varying vec3 obj_normal;
void vertex() {
	obj_normal = NORMAL;
	if (is_chain_head) {
		chain_interp = 0.1 + VERTEX.y;
	}
	if (cutted) {
		cut_interp = dot(VERTEX, cut_plane_normal) - cut_plane_dist - cut_vanish;
	}
}

void fragment() {
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
			EMISSION += texture(texture_emission, is_dot ? dot_uv : UV).rgb * front;

		vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 v_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		vec3 r = reflect(-v_world, n_world);
		float up = r.y;
		vec3 env = mix(vec3(0.015), vec3(0.18), smoothstep(-0.3, 0.7, up));
		env += vec3(1.4) * pow(max(0.0, 1.0 - abs(up - 0.25) * 5.0), 3.0);
		env += vec3(0.9) * smoothstep(0.8, 0.97, up);
		float fresnel = pow(1.0 - clamp(dot(n_world, v_world), 0.0, 1.0), 5.0);
		vec3 f0 = mix(vec3(0.5), color.rgb + vec3(0.25), 0.6);
		EMISSION += env * mix(f0, vec3(1.0), fresnel) * shine;

		if (is_chain_head) {
			EMISSION += vec3( smoothstep(cut_white_margin+0.01,cut_white_margin,chain_interp) );
		}

		if (cutted){
			// soft white margin
			EMISSION += vec3( smoothstep(cut_white_margin+0.01,cut_white_margin,cut_interp) );
			// hard white margin
			//EMISSION += vec3( float(cut_white_margin < cut_interp) );
		}
	} else {
		EMISSION = vec3(1.0);
	}
}
