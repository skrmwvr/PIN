extends Node

var beam_path: Path3D

# Register the beam path node when it enters the tree
func register_beam(path: Path3D) -> void:
	beam_path = path

# Returns the gravity force vector pointing OUTWARD away from the beam
func get_gravity_vector(global_pos: Vector3, gravity_strength: float = 25.0) -> Vector3:
	if not is_instance_valid(beam_path):
		# Fallback: pull standard down
		return Vector3.DOWN * gravity_strength
		
	var local_pos := beam_path.to_local(global_pos)
	var local_closest := beam_path.curve.get_closest_point(local_pos)
	var global_closest := beam_path.to_global(local_closest)
	
	var to_pos := global_pos - global_closest
	var dist := to_pos.length()
	
	if dist > 0.001:
		return to_pos.normalized() * gravity_strength
	else:
		# Fallback at exact center: push in a default direction
		return Vector3.UP * gravity_strength
