class_name TargetCharacter
extends CharacterBody3D
## The greybox target: owns its hit zones, the scoring flow and the
## double-count guard.


## Emitted exactly once per scoring pie, after every guard has passed.
signal hit(points: int, zone: String)

## Instrumentation view of the same event, carrying the pie itself so
## DebugEval can attribute the hit back to the throw that produced it.
signal hit_zone_entered(zone: String, body: Node3D)


@export_group("Scoring")

## Points awarded for a head-zone hit.
@export var head_points := 25

## Points awarded for a body-zone hit.
@export var body_points := 10

@export_group("Damage")

## Damage a head hit deals to the health pool (consumed by CF37-15).
@export var head_damage := 15

## Damage a body hit deals to the health pool. See `head_damage`.
@export var body_damage := 10


## True once the target has been knocked out; hits are rejected while set.
## Always false in CF37-18.
var defeated := false


@onready var _hit_zone_head: Area3D = $Pivot/HitZoneHead
@onready var _hit_zone_body: Area3D = $Pivot/HitZoneBody


func _ready() -> void:
	_hit_zone_head.body_entered.connect(_on_hit_zone_body_entered.bind("head"))
	_hit_zone_body.body_entered.connect(_on_hit_zone_body_entered.bind("body"))


# ---------------------------------------------------------------------------
# Scoring flow
# ---------------------------------------------------------------------------

func _on_hit_zone_body_entered(body: Node3D, zone: String) -> void:
	if defeated:
		return

	# `as` yields null instead of erroring when the cast fails, which keeps
	# this a single expression. The zones only mask layer 2 today, so this
	# is cheap insurance for CF37-33's non-pie projectiles.
	var pie := body as PieProjectile
	if pie == null:
		return

	if pie.scored or pie.is_splatted():
		return
	pie.scored = true
	pie.splat()

	_apply_damage(_damage_for_zone(zone))

	hit_zone_entered.emit(zone, pie)
	hit.emit(_points_for_zone(zone), zone)


func _points_for_zone(zone: String) -> int:
	match zone:
		"head":
			return head_points
		"body":
			return body_points
	push_warning("[TargetCharacter] unknown hit zone: %s" % zone)
	return 0


func _damage_for_zone(zone: String) -> int:
	match zone:
		"head":
			return head_damage
		"body":
			return body_damage
	return 0


## Spends zone damage against the health pool.
## Inert until CF37-15 introduces the pool.
func _apply_damage(_amount: int) -> void:
	pass
