extends MeshInstance3D
class_name PercentIndicator

## Opt-in track energy strip; the spectator indicator keeps its circular layout.
@export var energy_bar_mode := false

var how_full := 0.0
var how_full_display := 0.0
var label: TextMesh
var shader: ShaderMaterial
var health: bool

func _ready() -> void:
	shader = material_override as ShaderMaterial
	var label_instance := $PercentLabel as MeshInstance3D
	label = label_instance.mesh as TextMesh
	label_instance.layers = layers
	if energy_bar_mode:
		shader = ShaderMaterial.new()
		shader.shader = preload("res://game/PercentIndicator.gdshader")
		shader.render_priority = 10
		shader.set_shader_parameter(&"energy_bar_mode", true)
		material_override = shader
		var bar := QuadMesh.new()
		bar.size = Vector2(2.6, 0.32)
		mesh = bar
		label_instance.hide()
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		set_health_mode(false)

func set_health_mode(_health: bool) -> void:
	health = _health
	if energy_bar_mode:
		# Game states own visible. Use the render layer so showing the HUD cannot
		# accidentally reveal an energy strip in accuracy mode.
		layers = 1 if health else 0
	if health:
		label.text = ""
	else:
		shader.set_shader_parameter(&"color", Vector3(1.,1.,1.))

func _process(delta: float) -> void:
	if not is_visible_in_tree() or (energy_bar_mode and not health):
		return
	how_full_display = lerpf(how_full_display, how_full, 1.0 - exp(-delta * 8.0))
	shader.set_shader_parameter(&"how_full", how_full_display)
	if health:
		var color := Color(1.0, 0.16, 0.12).lerp(Color(0.32, 0.94, 0.78), how_full)
		shader.set_shader_parameter(&"color", Vector3(color.r, color.g, color.b))

func start_map() -> void:
	how_full = 1.0
	how_full_display = 0.0
	label.text = "" if health else "100%"

func endscore() -> void:
	how_full = 0.0
	how_full_display = 0.0
	label.text = "" if health else "0%"

func update_percent(amount: float) -> void:
	how_full = clampf(amount, 0.0, 1.0)
	var display := "" if health else "%d%%" % int(how_full * 100)
	if label.text != display:
		label.text = display
