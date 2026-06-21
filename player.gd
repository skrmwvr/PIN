extends CharacterBody3D

@export var speed: float = 40.0
@export var jump_velocity: float = 30.0
@export var gravity_strength: float = 50.0

func _physics_process(delta: float) -> void:
	# 1. Look up the Beam Path in the "beam" group
	var beam_path: Path3D = get_tree().get_first_node_in_group("beam") as Path3D
	
	var gravity_vec: Vector3 = Vector3.DOWN * gravity_strength # Default fallback
	var target_forward: Vector3 = Vector3(0.0, 0.0, 1.0)
	
	if is_instance_valid(beam_path):
		var local_pos: Vector3 = beam_path.to_local(global_position)
		var local_closest: Vector3 = beam_path.curve.get_closest_point(local_pos)
		var global_closest: Vector3 = beam_path.to_global(local_closest)
		
		# Gravity points radially OUTWARD (away from the beam)
		var to_pos: Vector3 = global_position - global_closest
		var dist: float = to_pos.length()
		if dist > 0.001:
			gravity_vec = to_pos.normalized() * gravity_strength
		
		# Get curve tangent direction at player position
		var offset: float = beam_path.curve.get_closest_offset(local_pos)
		var curve_trans: Transform3D = beam_path.curve.sample_baked_with_rotation(offset, true)
		target_forward = beam_path.to_global(curve_trans.basis.z).normalized()

	var gravity_dir: Vector3 = gravity_vec.normalized()
	# Local UP points toward the beam (opposite of gravity)
	var local_up: Vector3 = -gravity_dir

	# 2. Align transform basis with curvature
	var target_right: Vector3 = local_up.cross(target_forward).normalized()
	target_forward = target_right.cross(local_up).normalized()
	
	global_basis = Basis(target_right, local_up, target_forward)
	
	# Tell Godot's physics engine which direction is "up"
	up_direction = local_up

	# 3. Detect floor state via radial distance (radius of tube is 998m)
	var radial_pos: Vector3 = Vector3(global_position.x, global_position.y, 0.0)
	var radial_dist: float = radial_pos.length()
	var on_floor_custom: bool = radial_dist >= 997.9

	# 4. Apply custom gravity (outward)
	if not on_floor_custom:
		velocity += gravity_vec * delta

	# 5. Handle Jump (inward)
	if Input.is_action_just_pressed("ui_accept") and on_floor_custom:
		velocity += local_up * jump_velocity

	# 6. Handle Movement
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var move_dir: Vector3 = target_right * input_dir.x + target_forward * -input_dir.y
	
	var radial_vel: Vector3 = velocity.project(local_up)
	var tangential_vel: Vector3 = velocity - radial_vel
	
	if move_dir.length_squared() > 0.001:
		tangential_vel = move_dir * speed
	else:
		tangential_vel = tangential_vel.move_toward(Vector3.ZERO, speed * 5.0 * delta)
		
	velocity = tangential_vel + radial_vel

	# Apply kinematic movement manually (bypassing standard physics engine collision)
	global_position += velocity * delta

	# 7. Clamp boundaries programmatically to keep player inside the tube bounds
	# Clamp radial distance to 998m
	radial_pos = Vector3(global_position.x, global_position.y, 0.0)
	radial_dist = radial_pos.length()
	if radial_dist > 998.0:
		var normal: Vector3 = radial_pos.normalized()
		global_position.x = normal.x * 998.0
		global_position.y = normal.y * 998.0
		# Prevent infinite acceleration outward
		if velocity.dot(normal) > 0.0:
			velocity = velocity - velocity.project(normal)
			
	# Clamp Z (tube length between -3000m and 3000m)
	if global_position.z > 3000.0:
		global_position.z = 3000.0
		velocity.z = 0.0
	elif global_position.z < -3000.0:
		global_position.z = -3000.0
		velocity.z = 0.0
