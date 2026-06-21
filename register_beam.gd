extends Path3D

func _ready() -> void:
	beam_manager.register_beam(self)
