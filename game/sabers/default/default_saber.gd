extends Node3D
class_name DefaultSaber

var is_extended := false
var _hilt: SaberHilt

@onready var _anim := $AnimationPlayer as AnimationPlayer
@onready var light_mesh := $LightSaber_Mesh as MeshInstance3D
@onready var _mat := light_mesh.material_override as ShaderMaterial
@onready var tip := $tip as Marker3D
@onready var tail := $tail as SaberTail
@onready var hitsound := $hitsound as AudioStreamPlayer3D

func _ready() -> void:
	_hilt = preload("res://game/sabers/default/SaberHilt.gd").new()
	_hilt.name = &"HiltDetail"
	add_child(_hilt)
	$Hilt_Mesh.hide()
	quickhide()

func set_color(color: Color) -> void:
	_mat.set_shader_parameter(&"color", color)
	var glow := light_mesh.get_node_or_null(^"Glow") as MeshInstance3D
	if glow != null:
		(glow.material_override as ShaderMaterial).set_shader_parameter(&"color", color)
	tail.set_color(color)
	if _hilt != null: _hilt.set_color(color)

func set_thickness(value: float) -> void:
	light_mesh.scale.x = value
	light_mesh.scale.z = value

func set_trail(enabled: bool = true) -> void:
	tail.visible = enabled

func _show() -> void:
	#if Settings.claws:
		#$Hilt_Mesh.rotation_degrees.x = 90
		#$Hilt_Mesh.position.y = .02
		#$Hilt_Mesh.position.z = -.02
		#rotation_degrees.x = -90
	#else:
		#$Hilt_Mesh.rotation_degrees.x = 0
		#$Hilt_Mesh.position.y = -.03
		#$Hilt_Mesh.position.z = 0
		#tip.rotation_degrees.x = 0
		#rotation_degrees.x = 0
	_anim.play(&"ShowShort" if Settings.claws else &"Show")
	is_extended = true
	
func _hide() -> void:
	#$Hilt_Mesh.show()
	_anim.play(&"HideShort" if Settings.claws else &"Hide")
	is_extended = false
	
func quickhide() -> void:
	#$Hilt_Mesh.show()
	_anim.play(&"QuickHide")
	is_extended = false

const BAD_CUT_SOUND := preload("res://game/data/sfx/bad_cut.wav")
var _bad_cut_player: AudioStreamPlayer3D

# A wrong-saber cut plays the bad cut sound right away, at full volume.
func _play_bad_cut() -> void:
	if _bad_cut_player == null:
		_bad_cut_player = AudioStreamPlayer3D.new()
		_bad_cut_player.stream = BAD_CUT_SOUND
		_bad_cut_player.bus = hitsound.bus
		_bad_cut_player.attenuation_model = hitsound.attenuation_model
		_bad_cut_player.volume_db = -3.0
		hitsound.add_sibling(_bad_cut_player)
		_bad_cut_player.position = hitsound.position
	_bad_cut_player.pitch_scale = randf_range(0.97, 1.03)
	_bad_cut_player.play()

func hit(time_offset: float, strength := 1.0, wrong_saber := false) -> void:
	if wrong_saber:
		_play_bad_cut()
		return
	# a little variation so rapid hits don't sound like a machine gun
	hitsound.pitch_scale = randf_range(0.93, 1.07)
	if strength < 0.02: return
	hitsound.volume_db = linear_to_db(strength)
	if time_offset>0.2 or time_offset<-0.05:
		hitsound.play()
	else:
		if time_offset <= 0:
			hitsound.play(-time_offset)
		else:
			await get_tree().create_timer(time_offset).timeout
			hitsound.play()
