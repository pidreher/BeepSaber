@tool
extends Node3D
class_name OQ_UI2DCanvas

var ui_control: Control

@onready var viewport := $SubViewport as SubViewport
@onready var ui_area := $UIArea as Area3D
var ui_collisionshape: CollisionShape3D

@export var editor_live_update := false

# The viewport has transparent pixels outside rounded panels and controls.
# Preserve those pixels when displaying the viewport on the 3D surface.
@export var transparency: BaseMaterial3D.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
# Transparent UI is drawn after the stage's translucent and additive effects (glass,
# lit floor, light halos, cut splashes), so they never end up on top of text.
const UI_RENDER_PRIORITY := 10

# set to true to prevent UIRayCast marker from colliding with canvas
@export var disable_collision := false
@export var update_only_on_input := false
# The UI is rendered at this multiple of its logical pixel size and sampled
# down on the quad; at 1x small text looks blocky and shimmers in VR.
@export_range(1.0, 3.0, 0.25) var supersample := 2.0
# The panel bends around a vertical axis this far in front of it (in metres, at the
# canvas' world scale), so a panel at that distance from the player wraps around them.
# 0 keeps it flat.
@export var curve_radius := 2.2
const CURVE_SEGMENTS := 32
# Panel size and curve radius in this node's local units (set by update_size()).
var local_size := Vector2.ONE
var local_radius := 0.0

var mesh_material: StandardMaterial3D
@onready var mesh_instance := $UIArea/UIMeshInstance as MeshInstance3D


var ui_size := Vector2.ZERO

func _get_configuration_warnings() -> PackedStringArray:
	if (ui_control == null): return PackedStringArray(["Need a Control node as child."])
	return PackedStringArray()


func _input(event: InputEvent) -> void:
	if (event is InputEventKey):
		viewport.push_input(event)
		_input_update()


func find_child_control() -> void:
	ui_control = null
	for c in get_children():
		if c is Control:
			ui_control = c
			break

func update_size() -> void:
	ui_size = ui_control.get_size()
	if (ui_area != null):
		if Engine.is_editor_hint() or curve_radius <= 0.0:
			local_radius = 0.0
			ui_area.scale.x = ui_size.x * vr.UI_PIXELS_TO_METER
			ui_area.scale.y = ui_size.y * vr.UI_PIXELS_TO_METER
		else:
			_build_curved_surface()
	if (viewport != null):
		viewport.size_2d_override = Vector2i(ui_size)
		viewport.size_2d_override_stretch = true
		viewport.set_size(ui_size * supersample)

func _hide() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	hide()

func _show() -> void:
	if !update_only_on_input:
		viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	else:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_input_update()
	show()

func _ready() -> void:
	mesh_material = mesh_instance.material_override as StandardMaterial3D
	mesh_material.albedo_texture = viewport.get_texture()
	mesh_material.transparency = transparency
	mesh_material.render_priority = UI_RENDER_PRIORITY if transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else 0
	
	if Engine.is_editor_hint():
		return

	find_child_control()

	if (!ui_control):
		vr.log_warning("No UI Control element found in OQ_UI2DCanvas: %s" % get_path())
		return
	
	update_size()
	
	# reparent at runtime so we render to the viewport
	ui_control.get_parent().remove_child(ui_control)
	viewport.add_child(ui_control)
	ui_control.visible = true # set visible here as it might was set invisible for editing multiple controls
	
	ui_collisionshape = $UIArea/UICollisionShape as CollisionShape3D
	
	
func _editor_update_preview() -> void:
	var preview_node := ui_control.duplicate(DUPLICATE_USE_INSTANTIATION) as Control
	preview_node.visible = true
	
	for c in viewport.get_children():
		viewport.remove_child(c)
		c.queue_free()
	
	viewport.add_child(preview_node)

func _input_update() -> void:
	if update_only_on_input:
		($update_once as UpdateViewport).update_once(viewport)
	else:
		viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE

func _process(_dt: float) -> void:
	
	if !Engine.is_editor_hint(): # not in edtior
		if disable_collision:
			ui_collisionshape.disabled = true
		else:
			# if we are invisible we need to disable the collision shape to avoid interaction with the UIRayCast
			ui_collisionshape.disabled = not is_visible_in_tree()
		return

	# Not sure if it is a good idea to do this in the _process but at the moment it seems to 
	# be the easiest to show the actual canvas size inside the editor
	var last := ui_control
	find_child_control()
	if (ui_control != null):
		if (last != ui_control || ui_size != ui_control.get_size()):
			#print("Editor update size of ", name);
			update_size()
			_editor_update_preview()
		elif (editor_live_update):
			_editor_update_preview()

# Replaces the flat quad and box with a cylinder section (and a matching trimesh
# collision shape). The panel faces +z; its sides bend towards the viewer.
func _build_curved_surface() -> void:
	ui_area.scale = Vector3.ONE
	var world_scale := global_transform.basis.get_scale().x
	local_size = ui_size * vr.UI_PIXELS_TO_METER
	local_radius = curve_radius / maxf(world_scale, 0.001)
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in CURVE_SEGMENTS + 1:
		var u := float(i) / CURVE_SEGMENTS
		var p := curve_point(u)
		vertices.append(Vector3(p.x, local_size.y * 0.5, p.y))
		vertices.append(Vector3(p.x, -local_size.y * 0.5, p.y))
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))
		if i > 0:
			var a := (i - 1) * 2
			indices.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = mesh
	mesh_instance.transform = Transform3D.IDENTITY
	var faces := PackedVector3Array()
	for index in indices: faces.append(vertices[index])
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	($UIArea/UICollisionShape as CollisionShape3D).shape = shape

# Point on the curved surface (local x, local z) for a horizontal texture coordinate u.
func curve_point(u: float) -> Vector2:
	var angle := (u - 0.5) * local_size.x / local_radius
	return Vector2(local_radius * sin(angle), local_radius * (1.0 - cos(angle)))

# Texture coordinate of a point (in this node's local space) on the panel.
func local_to_uv(p: Vector3) -> Vector2:
	if local_radius <= 0.0:
		return Vector2(p.x / ui_area.scale.x + 0.5, -p.y / ui_area.scale.y + 0.5)
	var angle := atan2(p.x, local_radius - p.z)
	return Vector2(angle * local_radius / local_size.x + 0.5, 0.5 - p.y / local_size.y)
