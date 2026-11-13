extends MeshInstance3D
## Shares the animated blade transform and reads its changing capsule height.

var _blade: CapsuleMesh
var _material: ShaderMaterial
var _last_height := -1.0

func _ready() -> void:
	var blade_instance := get_parent() as MeshInstance3D
	_blade = blade_instance.mesh as CapsuleMesh
	_material = material_override as ShaderMaterial
	_sync_height()

func _process(_delta: float) -> void:
	_sync_height()

func _sync_height() -> void:
	if _blade == null or is_equal_approx(_last_height, _blade.height):
		return
	_last_height = _blade.height
	_material.set_shader_parameter(&"blade_length", _last_height)
	# CapsuleMesh clamps height to its diameter even when the animation requests 0.001.
	visible = _last_height > _blade.radius * 2.0 + 0.001
