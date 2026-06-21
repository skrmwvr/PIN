extends CharacterBody3D

@export var speed: float = 20.0
@export var jump_velocity: float = 15.0
@export var gravity_strength: float = 30.0

func _physics_process(delta: float) -> void:
	# 1. Query beam_manager to get the outward gravity force
	var gravity_vec := beam_manager.get_gravity_vector(global_position, gravity_strength)
	var gravity_dir := gravity_vec.normalized()
	
	# Local UP points toward the beam (opposite of gravity)
	var local_up := -gravity_dir

	# 2. Align transform basis with the curvature of the beam
	var target_forward := Vector3(0.0, 0.0, 1.0)
	if is_instance_valid(beam_manager.beam_path):
		var local_pos := beam_manager.beam_path.to_local(global_position)
		var offset := beam_manager.beam_path.curve.get_closest_offset(local_pos)
		# sample_baked_with_rotation returns a Transform3D aligned with the curve tangent
		var curve_trans := beam_manager.beam_path.curve.sample_baked_with_rotation(offset, true)
		target_forward = beam_manager.beam_path.to_global(curve_trans.basis.z).normalized()
	
	var target_right := local_up.cross(target_forward).normalized()
	target_forward = target_right.cross(local_up).normalized()
	
	# Update the rotation basis
	global_basis = Basis(target_right, local_up, target_forward)
	
	# Critical: Tell Godot's physics engine which direction is "up" so it knows what is the floor
	up_direction = local_up

	# 3. Apply custom gravity (outward)
	if not is_on_floor():
		velocity += gravity_vec * delta

	# 4. Handle Jump (inward)
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity += local_up * jump_velocity

	# 5. Handle Movement
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var move_dir := target_right * input_dir.x + target_forward * -input_dir.y
	
	var radial_vel := velocity.project(local_up)
	var tangential_vel := velocity - radial_vel
	
	if move_dir.length_squared() > 0.001:
		tangential_vel = move_dir * speed
	else:
		tangential_vel = tangential_vel.move_toward(Vector3.ZERO, speed * 5.0 * delta)
		
	velocity = tangential_vel + radial_vel

	move_and_slide()
