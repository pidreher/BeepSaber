extends Node3D
class_name UIRaycast

# Only one pointer is active at a time. Pulling the trigger on the other controller
# hands the pointer over to it (that press does not click).
@export var active := true:
	set(value):
		active = value
		if not value and is_node_ready(): _release()
@export var ui_raycast_length := 6.0
static var _all: Array[UIRaycast] = []
const BEAM_SHADER := preload("res://game/scripts/UIRaycast/PointerBeam.gdshader")
const DOT_SHADER := preload("res://game/scripts/UIRaycast/PointerDot.gdshader")
const IDLE_BEAM_LENGTH := 1.2
var _beam_material := ShaderMaterial.new()
var _dot_material := ShaderMaterial.new()
var ui_mesh_length := 1.0
@export var controller: BeepSaberController

@onready var ui_raycast := $RayCastPosition/RayCast3D as RayCast3D
@onready var ui_raycast_mesh := $RayCastPosition/RayCastMesh as MeshInstance3D
@onready var ui_raycast_hitmarker := $RayCastPosition/RayCastHitMarker as MeshInstance3D

var is_colliding := false
var colliding_with: Object = null


func _update_raycasts() -> void:
	ui_raycast_hitmarker.visible = false
	
	ui_raycast_mesh.visible = true
	
	ui_raycast.force_raycast_update() # need to update here to get the current position; else the marker laggs behind
	
	var c := ui_raycast.get_collider()
	# the beam reaches the panel it points at
	var beam_length := IDLE_BEAM_LENGTH
	if c is UIRaycastTarget:
		beam_length = ui_raycast.get_collision_point().distance_to(ui_raycast.global_position) / maxf(global_transform.basis.get_scale().z, 0.001)
	ui_raycast_mesh.scale.z = beam_length
	if c != colliding_with and colliding_with != null and colliding_with is UIRaycastTarget:
		(colliding_with as UIRaycastTarget).ui_raycast_exit()
	colliding_with = c
	if c:
		if not c is UIRaycastTarget: return
		
		var pos := ui_raycast.get_collision_point()
		ui_raycast_hitmarker.visible = true
		ui_raycast_hitmarker.global_transform.origin = pos
		
		(c as UIRaycastTarget).ui_raycast_hit_event(pos, controller.trigger_just_pressed(), controller.trigger_just_released())
		is_colliding = true
	else:
		is_colliding = false

func _ready() -> void:
	_all.append(self)
	tree_exiting.connect(func() -> void: _all.erase(self))
	ui_raycast.set_target_position(Vector3(0, 0, -ui_raycast_length))
	_setup_visuals()
	
	Settings.changed.connect(on_settings_changed)

	#setup the mesh
	update_mesh()
	
	ui_raycast_hitmarker.visible = false
	ui_raycast_mesh.visible = false
	
func on_settings_changed(key: StringName) -> void:
	match key:
		&"claws":
			update_mesh()
		&"color_left", &"color_right":
			_update_color()

func update_mesh() -> void:
	ui_mesh_length = 0.3 if Settings.claws else 1.0

# The beam is a camera-facing strip from the controller along -z (scaled to the hit
# distance), the hit marker a glowing dot. Both use the saber colour of this hand.
func _setup_visuals() -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -1), Vector3(0, 0, -1)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 2, 1, 3])
	var strip := ArrayMesh.new()
	strip.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_beam_material.shader = BEAM_SHADER
	_beam_material.render_priority = 11 # over the UI panels (10)
	ui_raycast_mesh.mesh = strip
	ui_raycast_mesh.material_override = _beam_material
	ui_raycast_mesh.position = Vector3.ZERO
	ui_raycast_mesh.extra_cull_margin = ui_raycast_length
	var dot := QuadMesh.new()
	dot.size = Vector2(0.07, 0.07)
	_dot_material.shader = DOT_SHADER
	_dot_material.render_priority = 12
	ui_raycast_hitmarker.mesh = dot
	ui_raycast_hitmarker.material_override = _dot_material
	_update_color()

func _update_color() -> void:
	var saber := get_parent() as LightSaber
	var color := Settings.color_left if saber != null and saber.type == 0 else Settings.color_right
	_beam_material.set_shader_parameter(&"color", color)
	_dot_material.set_shader_parameter(&"color", color)

func _make_current() -> void:
	for other in _all:
		if other != self and other.active:
			other.active = false
	active = true

func _release() -> void:
	if colliding_with is UIRaycastTarget:
		(colliding_with as UIRaycastTarget).ui_raycast_exit()
	colliding_with = null
	is_colliding = false
	ui_raycast_mesh.visible = false
	ui_raycast_hitmarker.visible = false

# we use the physics process here be in sync with the controller position
func _physics_process(_dt: float) -> void:
	if not visible: return
	if not active:
		if controller != null and controller.trigger_just_pressed():
			_make_current()
		return
	_update_raycasts()
