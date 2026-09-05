class_name TargetBase
extends CharacterBody3D
## Shared base for every carnival target archetype: owns the hit zones, the
## scoring flow + double-count guard (CF37-18), path locomotion, and the seams
## archetypes/feature stories fill in later.
##
## Template Method — the base owns the invariant skeleton; subclasses override
## the seams only: `_patrol` (movement personality, CF37-12) and
## `_on_hit_feedback` (the hit flash, CF37-15). Never override `_physics_process`
## or the scoring flow.


## Emitted exactly once per scoring pie, after every guard has passed.
## `target` is the archetype that was hit (self) so score/HUD attribute value
## to the right target; CF37-73 reads `target.archetype_id`.
signal hit(points: int, zone: String, target: TargetBase)

## Instrumentation view of the same event, carrying the pie (`body`) and the
## archetype (`target`). DebugEval binds it for range attribution.
signal hit_zone_entered(zone: String, body: Node3D, target: TargetBase)


## How this archetype moves. STATIONARY holds position; PATH ping-pongs along X
## between path_min_x/path_max_x at patrol_speed.
enum MovementMode { STATIONARY, PATH }


@export_group("Identity")

## Stable id for instrumentation/attribution (CF37-73). e.g. "clown", "dummy".
@export var archetype_id: StringName = &""

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

@export_group("Movement")

## STATIONARY or PATH. Only PATH bodies patrol.
@export var movement_mode: MovementMode = MovementMode.STATIONARY

## Rail lower bound (X, in TargetManager space). Placeholder — CF37-12 owns it.
@export var path_min_x := -2.5

## Rail upper bound (X, in TargetManager space). Placeholder — CF37-12 owns it.
@export var path_max_x := 2.5

## Patrol speed along the rail (m/s). Placeholder — CF37-12 owns it.
@export var patrol_speed := 1.5


## True once knocked out; hits are rejected and movement halts while set. The
## knockout *signal* is CF37-15 (`knocked_out`) — this stays a variable
## (GDScript forbids a signal of the same name).
var defeated := false

## Current rail direction for the default ping-pong (+1 → +X, -1 → -X).
var _patrol_dir := 1.0


@onready var _hit_zone_head: Area3D = $Pivot/HitZoneHead
@onready var _hit_zone_body: Area3D = $Pivot/HitZoneBody


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	if path_min_x > path_max_x:
		push_warning("rail-guard triggered")
	_hit_zone_head.body_entered.connect(_on_hit_zone_body_entered.bind("head"))
	_hit_zone_body.body_entered.connect(_on_hit_zone_body_entered.bind("body"))

# ---------------------------------------------------------------------------
# Path locomotion  (AC4: a PATH instance honours its exports)
# ---------------------------------------------------------------------------

## AC4: PATH archetypes patrol; STATIONARY and defeated bodies hold still.
## Mechanics only — the *decision* of where to go is the `_patrol` seam.
func _physics_process(delta: float) -> void:
	if movement_mode != MovementMode.PATH or defeated:
		velocity = Vector3.ZERO; return
	_patrol(delta)
	velocity.y = 0.0
	move_and_slide()
	position.x = clampf(position.x, path_min_x, path_max_x)


## AC4: movement-personality seam. Default = a straight, metronomic ping-pong
## that reverses at each bound. CF37-12 overrides THIS (random pauses, mid-rail
## reversals), not `_physics_process`. Default ignores `_delta` (velocity is
## integrated by move_and_slide); the override uses it for pause timing.
func _patrol(_delta: float) -> void:
	# Absolute direction per bound: can't double-flip and buzz at an edge if a
	# frame's displacement doesn't clear it (unlike a combined-OR `*= -1`).
	if position.x <= path_min_x:
		_patrol_dir = 1.0
	elif position.x >= path_max_x:
		_patrol_dir = -1.0
	velocity.x = _patrol_dir * patrol_speed

## AC1/AC3: the CF37-18 scoring flow, now emitting `self` as the third arg.
func _on_hit_zone_body_entered(body: Node3D, zone: String) -> void:
	if defeated:
		return
	var pie := body as PieProjectile
	if pie == null:
		return
	if pie.scored or pie.is_splatted():
		return
	pie.scored = true
	pie.splat()  # BEFORE the emits (73.5)

	_apply_damage(_damage_for_zone(zone))
	_on_hit_feedback(zone)

	hit_zone_entered.emit(zone, pie, self)
	hit.emit(_points_for_zone(zone), zone, self)


## AC-none: empty feedback seam (no flash exists yet). CF37-15 fills it.
func _on_hit_feedback(_zone: String) -> void:
	pass


func _points_for_zone(zone: String) -> int:
	match zone:
		"head": return head_points
		"body": return body_points
	push_warning("[TargetBase] unknown hit zone: %s" % zone)
	return 0


func _damage_for_zone(zone: String) -> int:
	match zone:
		"head": return head_damage
		"body": return body_damage
	return 0


## Spends zone damage against the health pool. Inert until CF37-15.
func _apply_damage(_amount: int) -> void:
	pass


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

## Return the target to a fresh, in-play state. Extracted for CF37-15's
## knockout-keeps-the-node-alive flow; NOT wired into a round yet (AC1: existing
## behaviour identical).
func reset() -> void:
	defeated = false
	velocity = Vector3.ZERO
	_patrol_dir = 1.0
