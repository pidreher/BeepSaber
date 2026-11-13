extends Node3D
class_name MissIndicator

# A large red "MISS" (or "BAD CUT") that pops up where a note was missed or badly cut,
# rises a little and fades out. It is drawn over everything so it is never hidden.

const LIFETIME := 0.9
const RISE := 0.3
# Never closer or further than this in front of the player.
const NEAREST_Z := Constants.PLAYER_Z - 1.6
const FARTHEST_Z := Constants.PLAYER_Z - 4.0

var _mesh := TextMesh.new()
var _material := StandardMaterial3D.new()
var _instance := MeshInstance3D.new()
var _tween: Tween

func _ready() -> void:
	_mesh.text = "MISS"
	_mesh.font_size = 64
	_mesh.pixel_size = 0.005
	_mesh.depth = 0.0
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_material.render_priority = 8
	_material.albedo_color = Color(1.0, 0.15, 0.12)
	_mesh.material = _material
	_instance.mesh = _mesh
	_instance.layers = 3
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_instance)
	visible = false

func show_miss(at: Vector3, text := "MISS") -> void:
	_mesh.text = text
	at.z = clampf(at.z, FARTHEST_Z, NEAREST_Z)
	at.y = clampf(at.y, 0.6, 2.2)
	global_position = at
	visible = true
	if _tween != null: _tween.kill()
	_instance.position = Vector3.ZERO
	_instance.scale = Vector3.ONE * 0.5
	_material.albedo_color.a = 1.0
	_tween = create_tween().set_parallel()
	_tween.tween_property(_instance, ^"scale", Vector3.ONE * 1.15, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_instance, ^"scale", Vector3.ONE, 0.15).set_delay(0.1)
	_tween.tween_property(_instance, ^"position:y", RISE, LIFETIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_material, ^"albedo_color:a", 0.0, 0.45).set_delay(LIFETIME - 0.45)
	_tween.chain().tween_callback(hide)
