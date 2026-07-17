extends Node3D

func _process(_delta: float) -> void:
	var axis := Input.get_axis("move_left", "move_right")
	if absf(axis) > 0.01:
		print("Move axis: %.1f" % axis)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("throw"):
		print("throw pressed")
	if event.is_action_pressed("restart"):
		print("restart pressed")
	if event.is_action_pressed("pause"):
		print("pause pressed")
