class_name PieProjectile
extends RigidBody3D

signal splattered

## random spin
@export var spin := 7.0

@export_group("Bounce")

@export var bounciness := 0.45

@export var surface_friction := 0.7

@export var impact_damping := 0.5

@export var crumbs_per_bounce := 5

@export_group("Splat")

@export var splat_speed := 1.2

@export var settle_timeout := 2.0

@export var cleanup_delay := 2.0

@export var lifetime := 6.0


var scored := false

var _has_splatted := false

var _has_touched := false

func _ready() -> void:

	var mat := PhysicsMaterial.new()
	mat.bounce = bounciness
	mat.friction = surface_friction
	physics_material_override = mat

	body_entered.connect(_on_body_entered)

	get_tree().create_timer(lifetime).timeout.connect(_expire)


func _physics_process(_delta: float) -> void:

	if _has_touched and not _has_splatted \
			and linear_velocity.length() < splat_speed:
		splat()

func launch(direction: Vector3, speed: float) -> void:
	linear_velocity = direction.normalized() * speed
	angular_velocity = Vector3(
			randf_range(-spin, spin),
			randf_range(-spin, spin),
			randf_range(-spin, spin))


func _on_body_entered(_body: Node) -> void:
	if _has_splatted:
		return

	call_deferred("_apply_impact_damping")

	_spawn_particles(crumbs_per_bounce, 1.0)

	if not _has_touched:
		_has_touched = true

		get_tree().create_timer(settle_timeout).timeout.connect(splat)


func _apply_impact_damping() -> void:
	if _has_splatted:
		return
	linear_velocity *= impact_damping
	angular_velocity *= impact_damping


func splat() -> void:
	if _has_splatted:
		return
	_has_splatted = true

	splattered.emit()

	set_deferred("freeze", true)

	var tween := create_tween()
	tween.tween_property(
		$MeshInstance3D, "scale",
		Vector3(1.6, 0.05, 1.6), 0.18
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	_spawn_particles(12, 2.0)

	get_tree().create_timer(cleanup_delay).timeout.connect(queue_free)

func _spawn_particles(count: int, speed_scale: float) -> void:
	var crumb := SphereMesh.new()
	crumb.radius = 0.02
	crumb.height = 0.04
	crumb.radial_segments = 6
	crumb.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.9, 0.78)
	crumb.material = mat

	var particles := CPUParticles3D.new()
	particles.mesh = crumb
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = count
	particles.lifetime = 0.5
	particles.direction = Vector3.UP
	particles.spread = 75.0
	particles.initial_velocity_min = 1.5 * speed_scale
	particles.initial_velocity_max = 3.5 * speed_scale
	particles.gravity = Vector3(0, -6, 0)

	add_child(particles)
	particles.emitting = true

func _expire() -> void:
	if _has_splatted:
		return
	queue_free()
