# extend the RayCast node and add additional RayCasts that help detect
# collisions with objects while swinging at high velocities.
extends RayCast3D
class_name SwingableRayCast

signal area_collided(area: Area3D)

@export var num_collision_raycasts: int = 8

const DEBUG := false
const DEBUG_TRAIL_SEGMENTS := 5

# this constant is used to prevent unnecessary raycast collision computations
# when the ray's 'cast_to' vector length is below this threshold. it seems like
# Godot's physics engine never picks up on collisions when the vector's length
# is below this threshold. this vlaue was imperically found by logging the
# minimum length when using the node in-game.
const MIN_SWEPT_LENGTH_THRESHOLD := 0.035

var core_ray_collision_count := 0
var aux_ray_collision_count := 0
var adjust_segments := true
var collision_filter: Callable
var _has_sweep_history := false

var _prev_ray_positions: Array[Vector3] = []
var _rays: Array[RayCast3D]
var _debug_curr_balls: Array[MeshInstance3D] = []
var _debug_raycast_trail := LinkedList.new()
@onready var _sw := StopwatchFactory.create(name, 10, true)

func _ready() -> void:
	await get_tree().physics_frame
	
	# use discrete RayCasts for continuous collision detection between _physics_process()
	for _i in range(num_collision_raycasts):
		var new_ray := RayCast3D.new()
		# inherit properties of parent
		new_ray.collision_mask = collision_mask
		new_ray.collide_with_areas = collide_with_areas
		new_ray.collide_with_bodies = collide_with_bodies
		new_ray.enabled = enabled
		add_child(new_ray)
		_prev_ray_positions.append(Vector3())
		_rays.append(new_ray)
		
		if DEBUG:
			var new_ball := $debug_ball.duplicate() as MeshInstance3D
			new_ball.visible = true
			add_child(new_ball)
			_debug_curr_balls.append(new_ball)
	
	# no longer need original instance
	$debug_ball.queue_free()

# override so that we can update child segments too
func _set_collision_mask_value(bit: int, value: bool) -> void:
	#collision_mask = 0x0
	#collision_mask = collision_mask | (int(value) << bit)
	set_collision_mask_value(bit, value)
	for ray in _rays:
		#ray.collision_mask = 0x0
		ray.set_collision_mask_value(bit,value)

func reset_counters() -> void:
	core_ray_collision_count = 0
	aux_ray_collision_count = 0

func set_raycasts_enabled(value: bool) -> void:
	enabled = value
	_has_sweep_history = false

func _update_element_positions() -> void:
	# generate new locations for ray casters
	var saber_base := transform.origin
	var saber_tip := saber_base + target_position
	var step_dist := (saber_tip - saber_base) / (num_collision_raycasts - 1)
	
	var next_local_pos := transform.origin
	for i in range(num_collision_raycasts):
		var next_global_pos := global_transform * (next_local_pos)
			
		# update ray's newest location for next physics frame processing
		var ray : RayCast3D = _rays[i]
		ray.global_transform.origin = next_global_pos
		if DEBUG:
			_debug_curr_balls[i].global_transform.origin = next_global_pos
			
		next_local_pos += step_dist

# A rejected generous hitbox must not shield the small hitbox or a later note.
# Exceptions are local to this query, so another saber still sees every collider.
func _check_ray(ray: RayCast3D) -> bool:
	var skipped: Array[CollisionObject3D] = []
	ray.force_raycast_update()
	var coll := ray.get_collider()
	var hit := false
	while coll is Area3D:
		if not collision_filter.is_valid() or collision_filter.call(coll):
			area_collided.emit(coll)
			hit = true
			break
		ray.add_exception(coll)
		skipped.append(coll)
		ray.force_raycast_update()
		coll = ray.get_collider()
	for area in skipped:
		ray.remove_exception(area)
	return hit

func _physics_process(_delta: float) -> void:
	if not enabled: return
	_sw.start()
	# see if 'core' ray is colliding with anything
	if _check_ray(self):
		core_ray_collision_count += 1
	
	# ---------------------
	
	# update positions of segmented ray casts and check for collisions on them
	if adjust_segments or not _has_sweep_history:
		_update_element_positions()
	
	for i in range(num_collision_raycasts):
		var ray: RayCast3D = _rays[i]
			
		# cast a ray to the newest location and check for collisions
		ray.target_position = ray.to_local(_prev_ray_positions[i])
		if _has_sweep_history and ray.target_position.length() > MIN_SWEPT_LENGTH_THRESHOLD:
			if _check_ray(ray):
				aux_ray_collision_count += 1
		
		_prev_ray_positions[i] = ray.global_transform.origin
	_has_sweep_history = true
		
	if DEBUG:
		var old_slice := _debug_raycast_trail.pop_back() as Array[RayCast3D]

		# update oldest slide with newest ray casts
		for i in range(num_collision_raycasts):
			old_slice[i].global_transform = _rays[i].global_transform
			old_slice[i].target_position = _rays[i].target_position

		_debug_raycast_trail.push_front(old_slice)
	_sw.stop()

func _on_SwingableRayCast_tree_entered() -> void:
	if DEBUG:
		var root := get_tree().get_root()
		var scene_root := root.get_child(root.get_child_count() - 1)
		for _t in range(DEBUG_TRAIL_SEGMENTS):
			var trail_slice: Array[RayCast3D] = []
			for _i in range(num_collision_raycasts):
				var new_ray := RayCast3D.new()
				new_ray.enabled = true
				new_ray.collision_mask = collision_mask
				scene_root.add_child(new_ray)
				trail_slice.append(new_ray)
			_debug_raycast_trail.push_front(trail_slice)
