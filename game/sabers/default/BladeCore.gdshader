shader_type spatial;
// A bright center and saturated silhouette stay readable without bloom or lights.
render_mode unshaded, fog_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.05, 0.08, 1.0);

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = smoothstep(0.12, 0.62, facing);
	vec3 hot = mix(color.rgb, vec3(1.0), 0.94);
	ALBEDO = mix(color.rgb, hot, core);
}
