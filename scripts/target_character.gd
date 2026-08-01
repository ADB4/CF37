## CF37-18 reference — scripts/target_character.gd
##
## Key decisions:
##
## 1. ONE handler, two connections. Both zones bind their tag at connect
##    time, so the scoring flow exists in exactly one place. Adding a third
##    zone later is a connect line, not a new branch.
##
## 2. `pie.scored = true` is set BEFORE `pie.splat()`. The head and body
##    zones overlap; both `body_entered` callbacks are dispatched inside the
##    same physics step, and `splat()` emits `splattered`, which may run
##    arbitrary listener code. Claiming the pie first is what makes
##    "first zone wins" true regardless of what runs next. Reverse the two
##    lines and the guarantee becomes a timing accident.
##
## 3. The guard ladder is ordered cheapest-and-most-disqualifying first:
##    defeated (whole target is out) → wrong node type → this pie is spent.
##    `is_splatted()` is the CF37-18 addition to PieProjectile; a pie that
##    splatted on the floor and rolled into a zone must not pay out.
##
## 4. `hit_zone_entered` is emitted POST-guard. CF37-8 introduced it and
##    DebugEval still listens to it (see CF37-61, which owns rewiring it),
##    so keeping the name preserves that instrumentation. Moving it behind
##    the guards is what makes the DebugEval summary a statement about
##    *scored* hits rather than raw zone traffic.
##
## 5. `defeated` is a plain flag here, never set. CF37-15 owns the health
##    pool that flips it. NOTE for the board: CF37-15/CF37-61 also want a
##    `defeated` SIGNAL — GDScript cannot have both under one name, so one
##    of the two has to be renamed before CF37-15 starts.

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

	# Claim first — see decision 2 in the header.
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
