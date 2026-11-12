extends Node

@export var scroll_node_path: NodePath
var scroll_node: Control
var v_scroll: VScrollBar
var is_mouse_in := false
var relpos := 0.0

# Joystick scrolling: deadzone, then a curved response up to the max speed
# (pixels per second at full deflection). The position is kept as a float
# because the scrollbars round small per-frame steps away, which made slow
# scrolling stall and jump.
const JOYSTICK_DEADZONE := 0.15
const JOYSTICK_MAX_SPEED := 3000.0
var _scroll_pos := 0.0
var _was_hovering := false

func _ready() -> void:
	scroll_node = get_node(scroll_node_path) as Control
	
	if scroll_node is ItemList:
		v_scroll = (scroll_node as ItemList).get_v_scroll_bar()
	elif scroll_node is ScrollContainer:
		v_scroll = (scroll_node as ScrollContainer).get_v_scroll_bar()
	elif scroll_node is RichTextLabel:
		v_scroll = (scroll_node as RichTextLabel).get_v_scroll_bar()
	
	@warning_ignore("return_value_discarded")
	scroll_node.connect(&"mouse_entered", Callable(self, &"_mouse_entered"))
	@warning_ignore("return_value_discarded")
	scroll_node.connect(&"mouse_exited", Callable(self, &"_mouse_exited"))

func _process(delta: float) -> void:
	var raycast := _hovering_raycast()
	if raycast == null:
		_was_hovering = false
		return
	var controller := raycast.controller
	var newpos := -controller.rotation_degrees.x - (controller.transform.origin.y * 20.0)
	if not _was_hovering:
		relpos = newpos
		_was_hovering = true
	if absf(_scroll_pos - v_scroll.value) > 1.5:
		_scroll_pos = v_scroll.value # changed elsewhere (mouse wheel, ensure visible, ...)
	if controller.trigger_pressed():
		# scroll via "click & drag"
		_scroll_pos += (relpos - newpos) * 20.0
	else:
		var y_joy := controller.get_vector2("primary").y
		if absf(y_joy) > JOYSTICK_DEADZONE:
			var t := (absf(y_joy) - JOYSTICK_DEADZONE) / (1.0 - JOYSTICK_DEADZONE)
			_scroll_pos -= signf(y_joy) * (0.15 + 0.85 * t * t) * JOYSTICK_MAX_SPEED * delta
	_scroll_pos = clampf(_scroll_pos, v_scroll.min_value, maxf(v_scroll.min_value, v_scroll.max_value - v_scroll.page))
	v_scroll.value = _scroll_pos
	relpos = newpos

# the UI pointer that currently points at this scroll area (or null)
func _hovering_raycast() -> UIRaycast:
	var game := GlobalReferences.main_game_scene
	var canvas := scroll_node.get_viewport().get_parent() as OQ_UI2DCanvas
	if game == null or canvas == null or not scroll_node.is_visible_in_tree():
		return null
	if not scroll_node.get_global_rect().has_point(scroll_node.get_global_mouse_position()):
		return null
	for raycast: UIRaycast in [game.right_ui_raycast, game.left_ui_raycast]:
		if raycast and raycast.visible and raycast.is_colliding and raycast.colliding_with == canvas.ui_area:
			return raycast
	return null

func _mouse_entered() -> void:
	is_mouse_in = true

func _mouse_exited() -> void:
	is_mouse_in = false
