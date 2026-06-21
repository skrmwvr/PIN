extends Area3D

@export var gravity_strength: float = 50.0
@export var bounce_coefficient: float = 0.85
@export var friction_damping: float = 0.05
@export var radius: float = 2.0

var velocity: Vector3 = Vector3.ZERO
var spawn_position: Vector3

# Boundaries matching the 6000m scale cylinder
const INNER_WALL_RADIUS: float = 5998.0
const TUBE_HALF_LENGTH: float = 6000.0

func _ready() -> void:
	spawn_position = global_position
	# Connect collision signal
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	# 1. Reset check
	if Input.is_key_pressed(KEY_R):
		global_position = spawn_position
		velocity = Vector3.ZERO
		return

	# 2. Look up the Beam Path in the "beam" group for custom gravity
	var beam_path: Path3D = get_tree().get_first_node_in_group("beam") as Path3D
	var gravity_vec: Vector3 = Vector3.DOWN * gravity_strength # Default fallback
	
	if is_instance_valid(beam_path):
		var local_pos: Vector3 = beam_path.to_local(global_position)
		var local_closest: Vector3 = beam_path.curve.get_closest_point(local_pos)
		var global_closest: Vector3 = beam_path.to_global(local_closest)
		
		# Gravity pulls OUTWARD away from the beam
		var to_pos: Vector3 = global_position - global_closest
		var dist: float = to_pos.length()
		if dist > 0.001:
			gravity_vec = to_pos.normalized() * gravity_strength

	# Apply custom gravity
	velocity += gravity_vec * delta
	
	# Apply basic drag/friction damping
	velocity = velocity.move_toward(Vector3.ZERO, friction_damping * velocity.length() * delta)

	# 3. Apply translation
	global_position += velocity * delta

	# 4. Programmatic clamping and bounces
	# Radial wall clamp (stands at INNER_WALL_RADIUS = 5998m)
	var radial_pos: Vector3 = Vector3(global_position.x, global_position.y, 0.0)
	var radial_dist: float = radial_pos.length()
	var max_radius: float = INNER_WALL_RADIUS - radius # 5996m
	
	if radial_dist > max_radius:
		var normal: Vector3 = radial_pos.normalized()
		global_position.x = normal.x * max_radius
		global_position.y = normal.y * max_radius
		
		# Bounce velocity off the curved wall normal
		velocity = velocity.bounce(normal) * bounce_coefficient

	# End cap Z-axis clamps
	var max_z: float = TUBE_HALF_LENGTH - radius
	if global_position.z > max_z:
		global_position.z = max_z
		velocity = velocity.bounce(Vector3.BACK) * bounce_coefficient
	elif global_position.z < -max_z:
		global_position.z = -max_z
		velocity = velocity.bounce(Vector3.FORWARD) * bounce_coefficient

# Handles collision when touching the player capsule
func _on_body_entered(body: Node3D) -> void:
	if body.name == "Player" or body is CharacterBody3D:
		# Calculate contact direction (from player to ball)
		var to_ball: Vector3 = (global_position - body.global_position).normalized()
		
		# Transfer player's current speed into the ball's deflection
		var player_vel: Vector3 = body.velocity
		var relative_vel: Vector3 = velocity - player_vel
		
		# Bounce ball away based on relative speed + direct launch force
		velocity = (relative_vel.bounce(to_ball) * bounce_coefficient) + (player_vel * 1.5) + (to_ball * 15.0)
		
		# Apply knockback to the player in the opposite direction
		if body.has_method("apply_knockback"):
			body.apply_knockback(-to_ball * 25.0)
