extends CharacterBody3D

@export var speed: float = 12.0
@export var jump_velocity: float = 12.0
@export var gravity_strength: float = 25.0

func _physics_process(delta: float) -> void:
	# 1. Calculate radial geometry relative to the tube's center line (assuming Z-axis is the center line)
	# Center of the tube at the player's current Z is (0, 0, global_position.z)
	var radial_pos := Vector3(global_position.x, global_position.y, 0.0)
	var radial_dist := radial_pos.length()
	
	# Gravity direction pulls radially OUTWARD to press feet against the inner wall
	var gravity_dir := Vector3.ZERO
	if radial_dist > 0.001:
		gravity_dir = radial_pos.normalized()
	else:
		gravity_dir = Vector3.UP # Fallback if perfectly at center
		
	# Local UP points toward the center axis
	var local_up := -gravity_dir

	# 2. Align transform basis with the tube curvature
	var target_forward := Vector3(0.0, 0.0, 1.0) # Axis of the tube
	var target_right := local_up.cross(target_forward).normalized()
	target_forward = target_right.cross(local_up).normalized()
	
	global_basis = Basis(target_right, local_up, target_forward)

	# 3. Apply custom gravity (pulling outward)
	if not is_on_floor_custom(radial_dist):
		velocity += gravity_dir * gravity_strength * delta

	# 4. Handle Jump (directed toward the center axis, local_up)
	if Input.is_action_just_pressed("ui_accept") and is_on_floor_custom(radial_dist):
		velocity += local_up * jump_velocity

	# 5. Get input and map to movement vectors
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# Horizontal input (left/right) moves circumferentially (along target_right)
	# Vertical input (up/down) moves axially (along target_forward)
	var move_dir := target_right * input_dir.x + target_forward * -input_dir.y
	
	# Separate velocity into local axes (tangential plane vs radial axis)
	var radial_vel := velocity.project(local_up)
	var tangential_vel := velocity - radial_vel
	
	if move_dir.length_squared() > 0.001:
		tangential_vel = move_dir * speed
	else:
		# Smooth deceleration on the tangent plane
		tangential_vel = tangential_vel.move_toward(Vector3.ZERO, speed * 5.0 * delta)
		
	# Reassemble velocity
	velocity = tangential_vel + radial_vel

	move_and_slide()

# Helper to check if player is at/near the tube's inner wall (assumed radius ~14.5m)
func is_on_floor_custom(radial_dist: float) -> bool:
	# True if we are close to or slightly beyond the tube radius
	# (For the prototype, 14.5m is the inner boundary, we check if radial_dist >= 14.2m)
	# Also check if Godot's built-in is_on_floor() triggers (in case of standard collision)
	return radial_dist >= 14.2 or is_on_floor()
