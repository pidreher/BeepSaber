shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.38, 0.44, 0.5, 1.0);
uniform float metallic_value = 0.85;
uniform float roughness_value = 0.23;
uniform float dark_visibility = 0.035;
uniform float reflection_strength = 0.8;

void fragment() {
	vec3 n = normalize(NORMAL);
	float facing = clamp(dot(n, normalize(VIEW)), 0.0, 1.0);
	// Broad virtual studio reflections keep the rounded machining readable in
	// an unlit lightshow, while real stage lighting still shades the metal.
	float strip = pow(max(dot(n, normalize(vec3(-0.45, 0.35, 0.82))), 0.0), 15.0);
	float rim = pow(1.0 - facing, 3.0);
	ALBEDO = base_color.rgb;
	METALLIC = metallic_value;
	ROUGHNESS = roughness_value;
	EMISSION = base_color.rgb * dark_visibility
		+ vec3(0.11, 0.14, 0.18) * strip * reflection_strength
		+ vec3(0.06, 0.085, 0.12) * rim * reflection_strength * 0.45;
}
