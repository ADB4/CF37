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


## Canonical animation names (CF37-14) — the contract every future rig must
## match. Not every archetype ships all six; a name the backend lacks is a
## silent no-op, never an error (decision 14.1). `duck` = drop-into-cover
## (redefined from the archived CF37-13 dodge; owned by CF37-62).
const ANIM_IDLE := &"idle"
const ANIM_WALK := &"walk"
const ANIM_DUCK := &"duck"
const ANIM_COWER := &"cower"
const ANIM_HIT := &"hit"
const ANIM_TAUNT := &"taunt"


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

## Animation backend, detected once in `_detect_animation_backend` (CF37-14).
## Exactly one shape wins: a state-machine AnimationTree sets `_anim_playback`
## and `_anim_sm_root`; a plain AnimationPlayer sets `_anim_player`; all three
## null means no backend, so `_play_anim` routes to the placeholder path.
## AC: AC1 (no backend → placeholder), AC2/AC3 (backend → travel/play or no-op).
var _anim_player: AnimationPlayer = null
var _anim_playback: AnimationNodeStateMachinePlayback = null
var _anim_sm_root: AnimationNodeStateMachine = null


@onready var _hit_zone_head: Area3D = $Pivot/HitZoneHead
@onready var _hit_zone_body: Area3D = $Pivot/HitZoneBody


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	if path_min_x > path_max_x:
		push_warning("rail-guard triggered")
	_hit_zone_head.body_entered.connect(_on_hit_zone_body_entered.bind("head"))
	_hit_zone_body.body_entered.connect(_on_hit_zone_body_entered.bind("body"))
	_detect_animation_backend()

# ---------------------------------------------------------------------------
# Animation backend  (CF37-14: rig-swap insurance)
# ---------------------------------------------------------------------------

## AC1/AC2/AC3: detect the animation backend once, at spawn. Prefer an
## AnimationTree whose `tree_root` is an AnimationNodeStateMachine (cache its
## playback object + root, activate the tree); else the first AnimationPlayer;
## else leave every cache null so `_play_anim` falls through to the placeholder.
## Search with owned=false so an AnimationTree inside an imported rig (owned by
## the rig root, not this scene) is still found — capability, not configuration.
func _detect_animation_backend() -> void:
	for node in find_children("*", "AnimationTree", true, false):
		var tree := node as AnimationTree
		var state_machine := tree.tree_root as AnimationNodeStateMachine
		if state_machine == null:
			continue
		_anim_sm_root = state_machine
		_anim_playback = tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		tree.active = true
		return
	for node in find_children("*", "AnimationPlayer", true, false):
		_anim_player = node as AnimationPlayer
		return

## AC2/AC3: route one canonical anim name to whatever backend exists — state
## machine first (guard `travel` with the cached root's `has_node`), then
## AnimationPlayer (guard `play` with `has_animation`), then placeholder. A
## detected backend that lacks the name is a SILENT no-op, no error (14.1).
## Param is `anim`, not `name`: `name` shadows Node.name (SHADOWED_VARIABLE_
## BASE_CLASS at parse — the CF37-73 `event_name` precedent).
func _play_anim(anim: StringName) -> void:
	if _anim_sm_root != null:
		if _anim_sm_root.has_node(anim):
			_anim_playback.travel(anim)
		return
	if _anim_player != null:
		if _anim_player.has_animation(anim):
			_anim_player.play(anim)
		return
	_play_placeholder(anim)


## AC1: fallback when no backend answers. STUB until CF37-23 — a print here is
## the AC1/AC2 evidence ("logger, not vibes"). Do NOT implement the tween now;
## CF37-23 fills the body and keeps this signature.
func _play_placeholder(anim: StringName) -> void:
	print("No animation for ", anim)

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
