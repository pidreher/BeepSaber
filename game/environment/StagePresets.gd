extends RefCounted
class_name StagePresets

# Stage layouts chosen by a map's environment name. Distances along the track are metres
# in front of the player. Names that are not listed use DEFAULT.
#
# rings: rows of SpinningRings. Shape keys are described in RingShapes. Ring keys:
#   count, step (spacing), height, distance (first ring), zoom (closest step, widest
#   step, speed; zero = no zoom), rotation_angle (default 90), rotation_step (random
#   per-ring twist), step_type (SpinningRings.StepType), flexy_speed, startup_step.
# mirrors: up to two reflective floor areas (half_width, near, far, strength).
# glass_track: draw the track as dark glass. glass_floor: a large glass floor area.

const ALL_OR_NOTHING := 2

const SMALL_RINGS := {
	shape = &"square", count = 24, step = 4.2, startup_step = 5.0, rotation_step = 10.0,
	flexy_speed = 4.0, outer = 5.16, inner = 4.98, depth = 0.28, height = 1.4, distance = 14.0,
	zoom = Vector3(1.0, 3.5, 5.0),
	lights = &"edge_strips", light_length = 3.2, light_thickness = 0.055,
}
const BIG_RINGS := {
	shape = &"square", count = 12, step = 8.0, startup_step = 0.0, rotation_step = 5.0,
	flexy_speed = 2.0, outer = 24.83, inner = 24.35, depth = 0.45, height = 5.0, distance = 7.0,
	zoom = Vector3.ZERO, lights = &"edge_strips", light_length = 6.0, light_thickness = 0.14,
}

# The track is 4.76 m wide and starts 7.65 m in front of the player, after an open gap.
# Its reflective part starts at 7.75 m.
const TRACK_HALF_WIDTH := 2.38
const TRACK_NEAR := 7.65
const TRACK_LENGTH := 100.0
const TRACK_FAR := TRACK_NEAR + TRACK_LENGTH
const TRACK_MIRROR := { half_width = TRACK_HALF_WIDTH, near = 7.75, far = TRACK_FAR, strength = 1.0 }
const NARROW_TRACK_MIRROR := { half_width = 1.15, near = TRACK_NEAR, far = TRACK_FAR, strength = 1.0 }
const PAD_MIRROR := { half_width = 1.5, near = -1.0, far = 1.0, strength = 1.0 }

const DEFAULT := {
	rings = [SMALL_RINGS, BIG_RINGS],
	mirrors = [PAD_MIRROR, TRACK_MIRROR],
	glass_track = true,
}

# Stages without rings or a reflective track.
const PLAIN := {
	rings = [],
	mirrors = [PAD_MIRROR],
	glass_track = false,
}

const PRESETS := {
	&"BigMirrorEnvironment": {
		rings = [BIG_RINGS],
		# One large mirror floor around the track.
		mirrors = [PAD_MIRROR, { half_width = 7.85, near = 7.76, far = 100.0, strength = 1.0 }],
		glass_track = true,
		glass_floor = { half_width = 7.85, near = 7.76, far = 100.0 },
	},
	&"NiceEnvironment": {
		rings = [
			{ shape = &"square", count = 30, step = 3.5, startup_step = 5.0, rotation_step = 10.0,
				flexy_speed = 4.0, outer = 5.16, inner = 4.68, depth = 0.6, height = 4.2,
				distance = 13.2, zoom = Vector3(0.5, 3.5, 5.0) },
			{ shape = &"square", count = 10, step = 1.7, startup_step = 0.0, rotation_step = 5.0,
				flexy_speed = 2.0, outer = 24.83, inner = 23.04, depth = 0.8, height = 4.5,
				distance = 35.0, zoom = Vector3.ZERO, lights = &"edge_strips", light_length = 6.0 },
		],
		mirrors = [PAD_MIRROR],
		glass_track = false,
	},
	&"TriangleEnvironment": {
		rings = [
			{ shape = &"triangle", count = 30, step = 4.0, startup_step = 5.0, rotation_step = 10.0,
				flexy_speed = 4.0, outer = 12.39, inner = 0.5, depth = 0.8, height = 2.0,
				distance = 20.0, zoom = Vector3(4.0, 8.0, 5.0), lights = &"outline",
				light_thickness = 0.08 },
			BIG_RINGS,
		],
		mirrors = [PAD_MIRROR, TRACK_MIRROR],
		glass_track = true,
	},
	&"OriginsEnvironment": {
		rings = [
			# Light bars only, no frame.
			{ shape = &"none", count = 15, step = 8.0, startup_step = 0.0, rotation_step = 5.0,
				flexy_speed = 4.0, outer = 12.0, height = 5.0, distance = 7.0, zoom = Vector3.ZERO,
				lights = &"square_bars", light_length = 24.0, light_thickness = 0.28 },
		],
		mirrors = [PAD_MIRROR, { half_width = 3.25, near = 7.75, far = TRACK_FAR, strength = 1.0 }],
		glass_track = true,
	},
	&"KaleidoscopeEnvironment": {
		rings = [
			# Pairs of long arms pointing up and down.
			{ shape = &"spokes", count = 20, step = 3.0, startup_step = 5.0, rotation_step = 30.0,
				flexy_speed = 8.0, radius = 4.0, outer = 30.0, bar = 1.6, depth = 1.0,
				height = 1.4, distance = 14.0, zoom = Vector3(1.0, 3.0, 5.0),
				lights = &"panel_lights", light_length = 3.0, light_thickness = 0.3 },
		],
		mirrors = [PAD_MIRROR, NARROW_TRACK_MIRROR],
		glass_track = true,
	},
	&"PanicEnvironment": {
		rings = [
			{ shape = &"panels", count = 30, step = 1.0, startup_step = 5.0, rotation_step = 22.5,
				flexy_speed = 4.0, panels = 4, radius = 3.85, panel_size = Vector2(1.0, 0.5),
				depth = 0.3, height = 1.0, distance = 10.0, zoom = Vector3(0.25, 2.0, 5.0),
				lights = &"panel_lights", light_length = 1.0, light_thickness = 0.1 },
		],
		mirrors = [PAD_MIRROR, { half_width = 1.15, near = 7.8, far = TRACK_FAR, strength = 1.0 }],
		glass_track = true,
	},
	&"FitBeatEnvironment": {
		rings = [
			{ shape = &"panels", count = 15, step = 2.0, startup_step = 5.0, rotation_step = 22.5,
				flexy_speed = 4.0, panels = 2, radius = 3.9, panel_size = Vector2(2.0, 0.5),
				depth = 0.5, height = 1.0, distance = 20.0, zoom = Vector3(0.25, 2.0, 5.0),
				lights = &"panel_beams", light_length = 100.0, light_thickness = 0.15 },
			{ shape = &"square", count = 15, step = 8.0, startup_step = 0.0, rotation_step = 5.0,
				flexy_speed = 2.0, outer = 24.83, inner = 23.04, depth = 0.8, height = 5.0,
				distance = 7.0, zoom = Vector3.ZERO, lights = &"center_beams",
				light_start = 0.0, light_length = 100.0, light_thickness = 0.15 },
		],
		mirrors = [PAD_MIRROR, { half_width = 1.15, near = 7.8, far = TRACK_FAR, strength = 1.0 }],
		glass_track = true,
	},
	&"TimbalandEnvironment": {
		rings = [
			{ shape = &"rect", count = 10, step = 1.5, startup_step = 5.0, rotation_angle = 45.0,
				rotation_step = 2.0, step_type = ALL_OR_NOTHING, flexy_speed = 4.0,
				half_w = 3.4, half_h = 5.16, bar = 0.3, depth = 0.3, height = 1.4, distance = 32.0,
				zoom = Vector3(1.5, 3.0, 5.0), lights = &"edge_strips", light_length = 3.0,
				light_thickness = 0.1 },
		],
		mirrors = [PAD_MIRROR, TRACK_MIRROR],
		glass_track = true,
	},
	&"CrabRaveEnvironment": {
		rings = [
			{ shape = &"square", count = 20, step = 5.0, startup_step = 5.0, rotation_step = 10.0,
				flexy_speed = 4.0, outer = 5.16, inner = 4.68, depth = 0.6, height = 1.4,
				distance = 17.0, zoom = Vector3.ZERO },
		],
		mirrors = [PAD_MIRROR, TRACK_MIRROR],
		glass_track = true,
	},
	&"TheSecondEnvironment": { rings = [], mirrors = [PAD_MIRROR, TRACK_MIRROR], glass_track = true },
	&"BTSEnvironment": { rings = [], mirrors = [PAD_MIRROR, NARROW_TRACK_MIRROR], glass_track = true },
	&"ColliderEnvironment": {
		rings = [],
		mirrors = [PAD_MIRROR, { half_width = 1.86, near = 8.3, far = 98.0, strength = 1.0 }],
		glass_track = true,
	},
	&"BillieEnvironment": {
		rings = [],
		mirrors = [PAD_MIRROR, { half_width = 2.25, near = 7.85, far = TRACK_FAR, strength = 1.0 }],
		glass_track = true,
	},
	# Large mirror floors all around.
	&"KDAEnvironment": {
		rings = [],
		mirrors = [PAD_MIRROR, { half_width = 30.0, near = 1.1, far = 100.0, strength = 0.8 }],
		glass_track = true,
		glass_floor = { half_width = 30.0, near = 1.1, far = 100.0 },
	},
	&"RocketEnvironment": {
		rings = [],
		mirrors = [PAD_MIRROR, { half_width = 30.0, near = 7.76, far = 100.0, strength = 0.8 }],
		glass_track = true,
		glass_floor = { half_width = 30.0, near = 7.76, far = 100.0 },
	},
	&"WeaveEnvironment": PLAIN,
	&"LatticeEnvironment": PLAIN,
	&"MetallicaEnvironment": PLAIN,
	&"HalloweenEnvironment": PLAIN,
}

# The preset of the map being played.
static var current: Dictionary = DEFAULT

static func for_environment(environment_name: String) -> Dictionary:
	return PRESETS.get(StringName(environment_name), DEFAULT)

# Sets the reflective floor areas used by the light shaders. Distances become world z.
static func apply_mirrors(preset: Dictionary) -> void:
	var areas: Array = preset.mirrors
	for i in 2:
		var value := Vector4.ZERO
		if i < areas.size() and Settings.reflections:
			var area: Dictionary = areas[i]
			value = Vector4(area.half_width, area.strength,
				Constants.PLAYER_Z - float(area.far), Constants.PLAYER_Z - float(area.near))
		RenderingServer.global_shader_parameter_set(&"mirror_area_a" if i == 0 else &"mirror_area_b", value)
