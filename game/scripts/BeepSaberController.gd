# This script contains the button logic for the controller
extends XRController3D
class_name BeepSaberController


var ax := false
var ax_last_frame := false
var by := false
var by_last_frame := false
var trigger := false
var trigger_last_frame := false
var menu := false
var menu_last_frame := false

var movement_aabb := AABB()

func ax_pressed() -> bool:
	return ax

func ax_just_pressed() -> bool:
	return ax and not ax_last_frame

func ax_just_released() -> bool:
	return ax_last_frame and not ax

func menu_pressed() -> bool:
	return menu

func menu_just_pressed() -> bool:
	return menu and not menu_last_frame

func menu_just_released() -> bool:
	return menu_last_frame and not menu

func by_pressed() -> bool:
	return by

func by_just_pressed() -> bool:
	return by and not by_last_frame

func by_just_released() -> bool:
	return by_last_frame and not by

func trigger_pressed() -> bool:
	return trigger

func trigger_just_pressed() -> bool:
	return trigger and not trigger_last_frame

func trigger_just_released() -> bool:
	return trigger_last_frame and not trigger

func _update_buttons_and_sticks() -> void:
	ax_last_frame = ax
	by_last_frame = by
	menu_last_frame = menu
	trigger_last_frame = trigger
	ax = is_button_pressed(&"ax_button")
	by = is_button_pressed(&"by_button")
	trigger = is_button_pressed(&"trigger") or is_button_pressed(&"select_button")
	menu = is_button_pressed(&"menu_button")

func _update_movement_aabb() -> void:
	movement_aabb = movement_aabb.expand(global_transform.origin)

func reset_movement_aabb() -> void:
	movement_aabb = AABB(global_transform.origin, Vector3.ZERO)

var _is_simple_rumbling := false
var _rumble_duration_remaining := 0.0

var _rumble_intensity := 0.0

# OpenXR's basic vibration output accepts one frequency at a time. Interleave
# a deep layer with the original runtime-tuned buzz, rather than sending two
# pulses that immediately replace each other. A slow envelope gives the deep
# layer a gentle breathing feel. Both layers follow the arc's distance ramp.
const ARC_BASS_FREQUENCY := 85.0
const ARC_PULSE_RATE := 2.2
const ARC_LAYER_PERIOD := 0.08
const ARC_BASS_SHARE := 0.7
const ARC_PULSE_DURATION := 0.05
var _arc_strength := 0.0
var _arc_time := 0.0

# Multiple arcs on the same hand contribute their strongest proximity value.
func arc_rumble(intensity: float) -> void:
	_arc_strength = maxf(_arc_strength, clampf(intensity, 0.0, 1.0))

func _process(delta: float) -> void:
	_update_arc_rumble(delta)

func _update_arc_rumble(delta: float) -> void:
	var strength := _arc_strength
	_arc_strength = 0.0
	if Scoreboard.paused or strength <= 0.0:
		_arc_time = 0.0
		return
	_arc_time += delta
	# Preserve the existing hit/clash/failure pulses for their full duration.
	if _is_simple_rumbling: return
	var bass_layer := fposmod(_arc_time, ARC_LAYER_PERIOD) < ARC_LAYER_PERIOD * ARC_BASS_SHARE
	var breath := 0.86 + 0.12 * sin(TAU * ARC_PULSE_RATE * _arc_time)
	_send_rumble(ARC_BASS_FREQUENCY if bass_layer else 0.0,
		strength * breath if bass_layer else strength, ARC_PULSE_DURATION)

func _send_rumble(frequency: float, intensity: float, duration: float) -> void:
	trigger_haptic_pulse("haptic", frequency, intensity, duration, 0)

# like simple_rumble, but only replaces a running rumble if it is not stronger
# (lets continuous effects update every frame without cutting off hit pulses)
func rumble_at_least(intensity: float, duration: float) -> void:
	if not _is_simple_rumbling or intensity >= _rumble_intensity:
		simple_rumble(intensity, duration)

func simple_rumble(intensity: float, duration: float) -> void:
	_rumble_duration_remaining = duration;
	_rumble_intensity = intensity
	_is_simple_rumbling = true
	# a zero amplitude pulse would only cut other vibrations short
	if intensity > 0.0:
		# frequency 0 = XR_FREQUENCY_UNSPECIFIED: the runtime drives the motor at
		# its optimal frequency. The previous 20 Hz is far below the resonance of
		# controller vibration motors and made every hit feel weak.
		_send_rumble(0.0, intensity, duration)
	
func is_simple_rumbling() -> bool:
	return _is_simple_rumbling
	
func _update_rumble(dt: float) -> void:
	if _rumble_duration_remaining > 0.0:
		_rumble_duration_remaining -= dt
	if _rumble_duration_remaining <= 0.0:
		_rumble_duration_remaining = 0.0
		_is_simple_rumbling = false

var first_time := true

func _physics_process(dt: float) -> void:
	if not Scoreboard.paused:
		_update_movement_aabb()
	
	if get_is_active(): # wait for active controller
		_update_rumble(dt)
		_update_buttons_and_sticks()
		# this avoid getting just_pressed events when a key is pressed and the controller becomes
		# active (like it happens on vr.scene_change!)
		if first_time:
			_update_buttons_and_sticks()
			first_time = false
