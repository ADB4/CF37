class_name DebugEval
extends CanvasLayer
## TEMPORARY instrumentation for the core-loop fun evaluation (greybox stage).
##
## Provides:
##   - a center-dot crosshair
##   - a live charge bar + percentage readout
##   - a per-throw logger (charge ratio, speed, scored zone or miss)
##
## Press L at any time to print a session summary to the console.
##
## Built entirely in code (no .tscn) so removal is clean: delete this file
## and the "Evaluation instrumentation" block in main.gd.
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
		"ratio": _last_ratio,
		"speed": pie.linear_velocity.length(),
		"zone": "",
		"time": Time.get_ticks_msec() / 1000.0,
	})


func on_hit_zone_entered(zone: String, body: Node3D) -> void:
	var id := body.get_instance_id()
	# Walk backwards: the most recent unscored throw by this pie is the match.
	for i in range(_throws.size() - 1, -1, -1):
		var t: Dictionary = _throws[i]
		if t["pie_id"] == id and t["zone"] == "":
			t["zone"] = zone
			return


# ---------------------------------------------------------------------------
# Session summary (press L).
# ---------------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_L:
		_print_summary()


func _print_summary() -> void:
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

	for t in _throws:
		var r: float = t["ratio"]
		ratio_sum += r
		buckets[clampi(int(r * 4.0), 0, 3)] += 1
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
