extends CharacterBody3D

@export var speed: float = 40.0
@export var jump_velocity: float = 30.0
@export var gravity_strength: float = 50.0
@export var mouse_sensitivity: float = 0.003
@export var controller_sensitivity: float = 2.0

# Tube radius settings (Tripled scale)
const INNER_WALL_RADIUS: float = 6000.0
const HALF_CAPSULE_HEIGHT: float = 1.0

# 5994m places player origin so feet stand at 5995m.
# This stands cleanly above the flat segments of the 128-sided cylinder (midpoints at 5996.2m).
const PLAYER_STAND_RADIUS: float = 5994.0 

var rot_x: float = 0.0
var rot_y: float = 0.0

@onready var camera_gimbal: Node3D = $CameraGimbal

func _ready() -> void:
	# Capture mouse to allow orbit controls
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Programmatically map WASD and Space to ui_* actions so it works naturally with focus
	_map_key("ui_left", KEY_A)
	_map_key("ui_right", KEY_D)
	_map_key("ui_up", KEY_W)
	_map_key("ui_down", KEY_S)
	_map_key("ui_accept", KEY_SPACE)

func _map_key(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	
	# Check if key is already mapped to prevent duplicates
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return
			
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)

func _input(event: InputEvent) -> void:
	# Toggle mouse capture with Escape key
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			
	# Camera rotation based on mouse movement
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rot_y -= event.relative.x * mouse_sensitivity
		rot_x -= event.relative.y * mouse_sensitivity
		rot_x = clamp(rot_x, -1.2, 1.2) # Limit vertical look angles (cannot look past straight up/down)
		
		if is_instance_valid(camera_gimbal):
			camera_gimbal.rotation = Vector3(rot_x, rot_y, 0.0)

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

	# 2. Handle Controller Right Stick Look Input
	var joy_look := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	)
	var deadzone: float = 0.15
	if joy_look.length() > deadzone:
		# Apply rotation using controller axis values
		rot_y -= joy_look.x * controller_sensitivity * delta
		rot_x -= joy_look.y * controller_sensitivity * delta
		rot_x = clamp(rot_x, -1.2, 1.2)
		
		if is_instance_valid(camera_gimbal):
			camera_gimbal.rotation = Vector3(rot_x, rot_y, 0.0)

	# 3. Align transform basis with curvature
	var target_right: Vector3 = local_up.cross(target_forward).normalized()
	target_forward = target_right.cross(local_up).normalized()
	
	global_basis = Basis(target_right, local_up, target_forward)
	
	# Tell Godot's physics engine which direction is "up"
	up_direction = local_up

	# 4. Detect floor state via radial distance (radius of tube floor is PLAYER_STAND_RADIUS)
	var radial_pos: Vector3 = Vector3(global_position.x, global_position.y, 0.0)
	var radial_dist: float = radial_pos.length()
	var on_floor_custom: bool = radial_dist >= (PLAYER_STAND_RADIUS - 0.1)

	# 5. Apply custom gravity (outward)
	if not on_floor_custom:
		velocity += gravity_vec * delta

	# 6. Handle Jump (inward)
	if Input.is_action_just_pressed("ui_accept") and on_floor_custom:
		velocity += local_up * jump_velocity

	# 7. Handle Movement Relative to Camera
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	var move_dir: Vector3 = Vector3.ZERO
	if is_instance_valid(camera_gimbal):
		var cam_forward: Vector3 = -camera_gimbal.global_transform.basis.z
		var cam_right: Vector3 = camera_gimbal.global_transform.basis.x
		
		# Project camera vectors onto local tangent plane to ensure movement stays on the floor
		var move_forward: Vector3 = (cam_forward - cam_forward.project(local_up)).normalized()
		var move_right: Vector3 = (cam_right - cam_right.project(local_up)).normalized()
		
		move_dir = move_right * input_dir.x + move_forward * -input_dir.y
	else:
		move_dir = target_right * input_dir.x + target_forward * -input_dir.y
	
	var radial_vel: Vector3 = velocity.project(local_up)
	var tangential_vel: Vector3 = velocity - radial_vel
	
	if move_dir.length_squared() > 0.001:
		tangential_vel = move_dir * speed
	else:
		tangential_vel = tangential_vel.move_toward(Vector3.ZERO, speed * 5.0 * delta)
		
	velocity = tangential_vel + radial_vel

	# Apply kinematic movement manually (bypassing standard physics engine collision)
	global_position += velocity * delta

	# 8. Clamp boundaries programmatically to keep player inside the tube bounds
	# Clamp radial distance to PLAYER_STAND_RADIUS (5994m)
	radial_pos = Vector3(global_position.x, global_position.y, 0.0)
	radial_dist = radial_pos.length()
	if radial_dist > PLAYER_STAND_RADIUS:
		var normal: Vector3 = radial_pos.normalized()
		global_position.x = normal.x * PLAYER_STAND_RADIUS
		global_position.y = normal.y * PLAYER_STAND_RADIUS
		# Prevent infinite acceleration outward
		if velocity.dot(normal) > 0.0:
			velocity = velocity - velocity.project(normal)
			
	# Clamp Z (tube length between -6000m and 6000m)
	if global_position.z > 6000.0:
		global_position.z = 6000.0
		velocity.z = 0.0
	elif global_position.z < -6000.0:
		global_position.z = -6000.0
		velocity.z = 0.0
