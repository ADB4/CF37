class_name TargetClown
extends TargetBase
## The main clown: the cast's baseline aim challenge (CF37-12).
##
## Adds movement *personality* on top of CF37-61's mechanical PATH locomotion by
## overriding the `_patrol` seam ONLY — never `_physics_process`. The base ticks
## the action-lock, calls `_patrol`, moves, clamps `position.x` to the rail and
## runs CF37-22 locomotion anim there; overriding `_physics_process` without
## `super()` silently kills all of that.
##
## De-metronome design (CF37-12 Scope): at each turn, roll `midpoint_chance` to
## sometimes head for a random point inside the rail instead of the far bound, and
## roll `pause_chance` to sometimes linger for a `pause_min`..`pause_max` window.
## With both chances 0, the override reduces to the base ping-pong EXACTLY (AC4).
##
## `patrol_speed` / `path_min_x` / `path_max_x` are re-valued as the baseline
## difficulty on CF37-73 evidence recorded on the ticket (set in the inspector,
## not here). `movement_mode` flips to PATH on `scenes/target_clown.tscn` (editor
## checklist), not in this script.


@export_group("Patrol personality")

## Probability [0,1], rolled at each turn, of lingering in place before setting off
## again instead of turning immediately. 0 disables pauses. Feel-tuned for AC3 (not
## CF37-73-gated); this default is a starting point — tune it on the 30 s watch.
## AC: AC3 (non-mechanical), AC4 (0 → exact base ping-pong).
@export var pause_chance := 0.35

## Probability [0,1], rolled at each turn, of heading for a random point inside the
## rail instead of the far bound. 0 disables midpoint turns. Feel-tuned for AC3.
## AC: AC2 (target stays in bounds), AC3, AC4 (0 → exact base ping-pong).
@export var midpoint_chance := 0.5

## Shortest linger, seconds — lower bound of the pause window (D7 initial default).
## AC: AC3.
@export var pause_min := 0.5

## Longest linger, seconds — upper bound of the pause window (D7 initial default).
## Keep `pause_max` >= `pause_min`.
## AC: AC3.
@export var pause_max := 1.4


## Remaining linger time (s). While > 0 the clown stands still (velocity.x = 0) and
## counts this down in `_patrol`; at 0 it resumes toward `_target_x`.
## AC: AC3 (pauses), AC4 (must never arm when pause_chance == 0).
var _pause_timer := 0.0

## The point on the rail the clown is currently walking toward, repicked on arrival.
## Must always be inside [path_min_x, path_max_x] (AC2). With midpoint_chance == 0
## this is always the far bound, so the motion matches the base ping-pong (AC4).
var _target_x := 0.0


## Seed the personality state so the first leg matches the base's opening move.
## MUST call super() first — the base `_ready` sets motion_mode, wires the hit
## zones and detects the anim backend; skipping it breaks scoring and animation.
func _ready() -> void:
	super()
	_target_x = path_max_x


# ---------------------------------------------------------------------------
# Movement personality  (overrides TargetBase._patrol — NOT _physics_process)
# ---------------------------------------------------------------------------

## Replace the base's turn-at-the-bound ping-pong with a target-driven walk that
## sometimes pauses and sometimes turns at a midpoint. Takes `delta` (the base
## default ignores it) to count the pause down in physics time. Set `velocity.x`
## here only — the base `_physics_process` calls move_and_slide() and clamps
## position.x to the rail after you return.
## AC: AC2 (targets in bounds), AC3 (varied pauses/turns), AC4 (both-0 == base).
func _patrol(delta: float) -> void:
	if _pause_timer > 0.0:
		_pause_timer -= delta
		velocity.x = 0.0
		return
	if _reached_target():
		_pick_next_target()
		if randf() < pause_chance:
			_pause_timer = randf_range(pause_min, pause_max)
			velocity.x = 0.0
			return

	velocity.x = _patrol_dir * patrol_speed


## True once position.x has reached (or passed) _target_x in the current direction
## of travel — so the comparison flips with _patrol_dir. Keep it EPSILON-FREE: with
## _target_x at a bound this then turns at the exact point the base would (the base
## clamps position.x to the bounds each frame, so the far-bound case can't overshoot).
## AC: AC4 (turn point identical to the base ping-pong).
func _reached_target() -> bool:
	if _patrol_dir > 0.0:
		return position.x >= _target_x
	else:
		return position.x <= _target_x


## Turn around and choose the next _target_x: the far bound in the NEW direction,
## or (rolled on midpoint_chance) a random point between here and that bound. The
## pick must stay inside [path_min_x, path_max_x] (AC2) and be ahead in the new
## direction so it isn't an instant re-turn. midpoint_chance == 0 ⇒ always the far
## bound (AC4).
## AC: AC2 (pick in bounds), AC4 (midpoint_chance 0 → far bound only).
func _pick_next_target() -> void:
	_patrol_dir = _patrol_dir * -1.0
	if randf() < midpoint_chance:
		if _patrol_dir > 0.0:
			_target_x = randf_range(position.x, path_max_x)
		else:
			_target_x = randf_range(position.x, path_min_x)
	else:
		_target_x = path_max_x if _patrol_dir > 0.0 else path_min_x


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

## Clear the clown's transient personality state on top of the base reset, so a
## reset restarts a clean first leg. reset() isn't wired into a round until
## CF37-15, but keeping this state consistent with the base lifecycle now avoids a
## stale-state bug when it is. Call super() first (base clears defeated / velocity /
## _patrol_dir).
func reset() -> void:
	super()
	_pause_timer = 0.0
	_target_x = path_max_x
