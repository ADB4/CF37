class_name PieProjectile
extends RigidBody3D
## A thrown pie. Physically collides with the world only (layer setup:
## layer = projectile, mask = world). The target's hit zones will be
## Area3Ds that detect the pie in a later story — pies never bounce
## off the target's physics body.

## Random spin applied to each axis on launch, for tumble.
@export var spin := 7.0

## Set by the target the moment it scores this pie, so overlapping hit
## zones (head + body) can never double-count one pie.
var scored := false


## Called by the player controller right after spawning.
func launch(direction: Vector3, speed: float) -> void:
	linear_velocity = direction.normalized() * speed
	angular_velocity = Vector3(
			randf_range(-spin, spin),
			randf_range(-spin, spin),
			randf_range(-spin, spin))
