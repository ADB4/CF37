class_name DebugEval
extends CanvasLayer
## TEMPORARY instrumentation for the core-loop fun evaluation (greybox stage).
##
## Provides:
##   - a center-dot crosshair
##   - a live charge bar + percentage readout
##   - a per-throw logger (charge ratio, speed, scored zone or miss, range)
##   - CF37-73: per-archetype attribution + a charge-bucket × archetype table
##     (the anti-pattern evidence for CF37-62/63/35)
##   - CF37-73: log_event() so "not throwing" (CF37-64 anti-targets) is measurable
##
## Press L at any time to print a session summary to the console.
##
## Built entirely in code (no .tscn) so removal is clean: delete this file and
## the "Evaluation instrumentation" block in main.gd — including the
## register_target() call in _wire_targets().
##
## Web-export safe: CanvasLayer + Control nodes render fine under the
## Compatibility renderer, and nothing here touches threads or file I/O.

## A throw whose pie has scored no zone after this many seconds is a miss.
@export var miss_timeout := 2.0

const _BAR_WIDTH := 14.0
const _BAR_HEIGHT := 120.0
const _BAR_MARGIN := 24.0  # distance from the bottom-right corner

var _charge_label: Label
var _charge_fill: ColorRect
var _last_ratio := 0.0
var _throws: Array[Dictionary] = []

## CF37-73: the archetypes DebugEval may attribute a throw to. Populated once, at
## wiring time, by main.gd._wire_targets() calling register_target() per child —
## the hub hands us the refs (signals-not-references stays intact; we never reach
## into the scene tree). Held only to read each body's global_position at event
## time; never polled in _process (AC3). This set is also what guarantees AC2:
## every registered archetype gets a summary row even if nothing resolved to it.
## AC: (1) attribution denominator, (2) never-hit archetype still shows a row.
var _targets: Array[TargetBase] = []

## CF37-73: named measurement events (CF37-64 anti-target crossings / held fire).
## Appended by log_event(); summarised in _print_event_summary(). Stays empty and
## silent until CF37-64 calls log_event().
## AC: (4) summary prints crossings / anti-target hits / held fire.
var _events: Array[Dictionary] = []


func _ready() -> void:
	layer = 10
	_build_ui()


func _build_ui() -> void:
	# Center-dot crosshair.
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.9)
	_anchor_center(dot, Vector2(4, 4), Vector2.ZERO)
	add_child(dot)

	# Charge bar: vertical, anchored to the bottom-right corner.
	# Fill grows upward from the bottom of the background.
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.4)
	_anchor_bottom_right(bar_bg, Vector2(_BAR_WIDTH, _BAR_HEIGHT),
			Vector2(_BAR_MARGIN, _BAR_MARGIN + 26.0))
	add_child(bar_bg)

	_charge_fill = ColorRect.new()
	_charge_fill.color = Color(1.0, 0.85, 0.2, 0.95)
	_charge_fill.position = Vector2(0, _BAR_HEIGHT)
	_charge_fill.size = Vector2(_BAR_WIDTH, 0)
	bar_bg.add_child(_charge_fill)

	# Percentage readout below the bar.
	_charge_label = Label.new()
	_charge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor_bottom_right(_charge_label, Vector2(60, 22),
			Vector2(_BAR_MARGIN - 23.0, _BAR_MARGIN))
	add_child(_charge_label)


## Anchors a Control to screen center with a given pixel size and offset.
func _anchor_center(c: Control, size: Vector2, offset: Vector2) -> void:
	c.anchor_left = 0.5
	c.anchor_top = 0.5
	c.anchor_right = 0.5
	c.anchor_bottom = 0.5
	c.offset_left = offset.x - size.x * 0.5
	c.offset_top = offset.y - size.y * 0.5
	c.offset_right = offset.x + size.x * 0.5
	c.offset_bottom = offset.y + size.y * 0.5


## Anchors a Control to the bottom-right corner. `inset` is the distance
## from the corner to the control's bottom-right edge, in pixels.
func _anchor_bottom_right(c: Control, size: Vector2, inset: Vector2) -> void:
	c.anchor_left = 1.0
	c.anchor_top = 1.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_right = -inset.x
	c.offset_bottom = -inset.y
	c.offset_left = -inset.x - size.x
	c.offset_top = -inset.y - size.y


# ---------------------------------------------------------------------------
# Wiring (called from main.gd — the hub hands us the target refs).
# ---------------------------------------------------------------------------

## CF37-73: register one archetype so misses can be attributed to the nearest
## one and every archetype earns a summary row. Called once per TargetManager
## child from main.gd._wire_targets(); costs nothing per frame.
## AC: (1) attribution denominator, (2) never-hit archetype still shows a row.
func register_target(t: TargetBase) -> void:
	if t == null:
		return
	if not _targets.has(t):
		_targets.append(t)


# ---------------------------------------------------------------------------
# Signal handlers (wired from main.gd — signals-not-references convention).
# ---------------------------------------------------------------------------

func on_charge_updated(ratio: float) -> void:
	_last_ratio = ratio
	var fill_h := _BAR_HEIGHT * ratio
	_charge_fill.size = Vector2(_BAR_WIDTH, fill_h)
	_charge_fill.position = Vector2(0, _BAR_HEIGHT - fill_h)
	_charge_label.text = "%d%%" % roundi(ratio * 100.0)


func on_charge_released() -> void:
	# Leave the last value on screen so it can be read after the throw.
	pass


func on_pie_thrown(pie: PieProjectile) -> void:
	_throws.append({
		"pie_id": pie.get_instance_id(),
		"spawn": pie.global_position,
		"range": -1.0,
		"ratio": _last_ratio,
		"speed": pie.linear_velocity.length(),
		"zone": "",
		"time": Time.get_ticks_msec() / 1000.0,
		# CF37-73 attribution slots, resolved later on this same record:
		"attr_id": &"",   # nearest archetype at splat — miss attribution / fallback
		"hit_id": &"",    # archetype actually scored — set on a hit, wins over attr_id
		"points": 0,      # points awarded on a hit; stays 0 for a miss
	})
	pie.splattered.connect(_on_pie_splattered.bind(pie))

## Fills the throw's range at splat. CF37-73: also captures the nearest archetype
## AT THIS MOMENT into `attr_id`. This runs BEFORE on_hit_zone_entered (target_base
## calls pie.splat() before hit_zone_entered.emit — 73.5), so on a hit the value
## captured here is a fallback that on_hit_zone_entered overwrites with the real
## target. Capturing here is exactly what makes miss attribution use the moving
## dummy's position at splat, with nothing added to _process.
## AC: (1) miss attribution, (3) zero steady-state cost.
func _on_pie_splattered(pie: PieProjectile) -> void:
	var landed := pie.global_position
	for i in range(_throws.size() -1, -1, -1):
		var t: Dictionary = _throws[i]
		if t["pie_id"] == pie.get_instance_id() and t["range"] < 0.0:
			var flat := Vector3(landed.x - t["spawn"].x, 0.0, landed.z - t["spawn"].z)
			t["range"] = flat.length()
			t["attr_id"] = _nearest_archetype(landed)
			return

## Records the scored zone. CF37-73: also records WHICH archetype scored and the
## points for that zone, read straight off the target's public exports — no
## signal-signature change (73.2/73.3). The param arrives from CF37-61 spelled
## `_target` (it was unused there); consuming it is CF37-73's job, so DROP the
## underscore to `target` as you fill the body — the CONTRACTS Current line is
## promoted to the `target` spelling at the done-gate (finding 73.e). It
## defaults to null only for the back-compat shape; live wiring always passes it.
## AC: (1) hits attributed by the actual target, (points-per-attempt source).
func on_hit_zone_entered(zone: String, body: Node3D, target: TargetBase = null) -> void:
	var id := body.get_instance_id()
	# Walk backwards: the most recent unscored throw by this pie is the match.
	for i in range(_throws.size() - 1, -1, -1):
		var t: Dictionary = _throws[i]
		if t["pie_id"] == id and t["zone"] == "":
			t["zone"] = zone
			if target != null:
				t["hit_i"] = target.archetype_id
				t["points"] = target.head_points if zone == "head" else target.body_points
			return


## CF37-73: nearest registered archetype to `point` by HORIZONTAL distance (x/z
## only — y ignored, matching the range math). Reads global_position live, so
## callers must call this at event time for moving (PATH) archetypes. Returns
## &"" when no targets are registered.
## AC: (1) the nearest-archetype attribution rule.
func _nearest_archetype(point: Vector3) -> StringName:
	var flat_point := Vector2(point.x, point.z)
	var nearest: TargetBase = null
	var nearest_dist_sq := INF
	for t in _targets:
		if t != null:
			var t_pos := t.global_position
			var t_dist_sq := Vector2(t_pos.x, t_pos.z).distance_squared_to(flat_point)
			if t_dist_sq < nearest_dist_sq:
				nearest_dist_sq = t_dist_sq
				nearest = t
	if nearest == null:
		return &""
	else:
		return nearest.archetype_id


# ---------------------------------------------------------------------------
# Named events (CF37-73 — the CF37-64 "not throwing" instrument, D4).
# ---------------------------------------------------------------------------

## Record a named measurement event. CF37-64 calls this on anti-target
## crossing-start / crossing-end / hit so "held fire" becomes measurable. Just
## appends (inert until something calls it); the tally lives in the summary.
## AC: (4) summary prints crossings / anti-target hits / held fire.
func log_event(name: StringName) -> void:
	_events.append({"name": name, "timestamp": Time.get_ticks_msec()})


# ---------------------------------------------------------------------------
# Session summary (press L).
# ---------------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_L:
				_print_summary()
			KEY_C:
				_throws.clear()
				_events.clear()
				print("[DebugEval] clear throws")


func _print_summary() -> void:
	log_event(&"crossing-start")
	var total := _throws.size()
	if total == 0:
		print("[DebugEval] no throws logged yet")
		return

	var now := Time.get_ticks_msec() / 1000.0
	var buckets := [0, 0, 0, 0]
	var full := 0
	var head := 0
	var body := 0
	var miss := 0
	var pending := 0
	var ratio_sum := 0.0

	var range_sum := [0.0, 0.0, 0.0, 0.0]   # one slot per charge bucket
	var range_cnt := [0, 0, 0, 0]
	var range_min := INF                     # starts at +infinity so first value wins
	var range_max := 0.0
	var range_total := 0.0
	var range_n := 0                          # how many resolved ranges we counted
	for t in _throws:
		var r: float = t["ratio"]
		var b := clampi(int(r * 4.0), 0, 3)
		buckets[b] += 1
		ratio_sum += r
		if r > 0.9:
			full += 1
		match t["zone"]:
			"head":
				head += 1
			"body":
				body += 1
			_:
				if now - t["time"] > miss_timeout:
					miss += 1
				else:
					pending += 1
		var rng: float = t["range"]
		if rng >= 0.0:
			range_sum[b] += rng
			range_cnt[b] += 1
			range_total += rng
			range_n += 1
			range_min = minf(range_min, rng)
			range_max = maxf(range_max, rng)

	var resolved := maxi(total - pending, 1)

	print("[DebugEval] ---- session summary ----")
	print("  throws: %d   mean charge: %.2f   full-charge (>0.9): %d (%.0f%%)"
			% [total, ratio_sum / total, full, 100.0 * full / total])
	print("  charge histogram   0-25%%: %d   25-50%%: %d   50-75%%: %d   75-100%%: %d"
			% buckets)
	print("  hits   head: %d   body: %d   misses: %d   in-flight: %d"
			% [head, body, miss, pending])
	print("  hit rate (resolved throws): %.0f%%"
			% (100.0 * float(head + body) / float(resolved)))

	if range_n > 0:
		print("  range (m)   min: %.2f   mean: %.2f   max: %.2f   (splat, n=%d)"
				% [range_min, range_total / range_n, range_max, range_n])
		var parts: Array[String] = []
		for i in 4:
			if range_cnt[i] > 0:
				parts.append("%d-%d%%: %.2f" % [i * 25, i * 25 + 25, range_sum[i] / range_cnt[i]])
			else:
				parts.append("%d-%d%%: --" % [i * 25, i * 25 + 25])
		print("  mean range by charge   " + "   ".join(parts))
	else:
		print("  range (m): no resolved throws yet")

	# CF37-73 additions: the anti-pattern evidence, then the "not throwing" section.
	_print_archetype_table()
	_print_event_summary()


## CF37-73: the charge-bucket × archetype table — hit rate and points-per-attempt
## per cell. THIS TABLE IS THE ANTI-PATTERN EVIDENCE: a charge column that wins
## against every archetype means the design has collapsed to one dominant throw.
## One row per registered archetype (AC2: a never-resolved archetype still prints,
## as zeros — silence is data). Per-throw attribution: hit_id when set, else
## attr_id (the nearest-archetype rule). In-flight throws don't count as attempts.
## AC: (1) per-bucket per-archetype hit rate + points-per-attempt, (2) silence is data.
func _print_archetype_table() -> void:
	var now := Time.get_ticks_msec() / 1000.0

	# Row set: registered archetypes first (guarantees AC2), then any id that a
	# throw actually resolved to but that wasn't registered (defensive).
	var ids: Array[StringName] = []
	for t in _targets:
		if t == null:
			continue
		var aid: StringName = t.archetype_id
		if aid != &"" and not ids.has(aid):
			ids.append(aid)
	for throw in _throws:
		var aid: StringName = throw["hit_id"] if throw["hit_id"] != &"" else throw["attr_id"]
		if aid != &"" and not ids.has(aid):
			ids.append(aid)

	if ids.is_empty():
		print("  archetype table: no archetypes registered")
		return

	# Per (archetype, bucket): attempts / hits / points. Dicts keyed by id, each
	# value a 4-slot array (one per charge bucket).
	var attempts := {}
	var hits := {}
	var points := {}
	for aid in ids:
		attempts[aid] = [0, 0, 0, 0]
		hits[aid] = [0, 0, 0, 0]
		points[aid] = [0, 0, 0, 0]

	for throw in _throws:
		var is_hit: bool = throw["zone"] != ""
		# An in-flight throw (no zone, not yet past miss_timeout) isn't resolved.
		if not is_hit and now - float(throw["time"]) <= miss_timeout:
			continue
		var aid: StringName = throw["hit_id"] if throw["hit_id"] != &"" else throw["attr_id"]
		if aid == &"":
			continue  # never splatted / unattributed — leave it out of the rates
		var b := clampi(int(float(throw["ratio"]) * 4.0), 0, 3)
		attempts[aid][b] += 1
		if is_hit:
			hits[aid][b] += 1
			points[aid][b] += int(throw["points"])

	print("  ---- charge × archetype  (hit% | pts/attempt) ----")
	print("  %-10s   0-25%%       25-50%%      50-75%%      75-100%%" % "archetype")
	for aid in ids:
		var cells: Array[String] = []
		for b in 4:
			var a: int = attempts[aid][b]
			if a == 0:
				cells.append("   --     ")
			else:
				var hr := 100.0 * float(hits[aid][b]) / float(a)
				var ppa := float(points[aid][b]) / float(a)
				cells.append("%3.0f%% |%5.1f" % [hr, ppa])
		print("  %-10s  %s" % [String(aid), "  ".join(cells)])


## CF37-73: the "not throwing" section — crossings / anti-target hits / held fire
## — tallied from _events. Prints nothing until CF37-64 wires log_event(); a
## zeroed header before then is fine. CF37-64 owns the specific event names and
## the held-fire derivation; keep this a generic tally so we don't implement ahead.
## AC: (4) crossings / anti-target hits / held fire once CF37-64 calls log_event.
func _print_event_summary() -> void:
	if _events.is_empty():
		return
	var counts := {}
	for e in _events:
		var n: StringName = e["name"]
		counts[n] = int(counts.get(n, 0)) + 1
	print("  ---- events (log_event) ----")
	for n in counts:
		print("    %s: %d" % [String(n), counts[n]])
