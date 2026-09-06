extends Node3D
const ROUND_DURATION := 60

enum GameState { READY, PLAYING, ROUND_OVER }

var _state: GameState = GameState.READY
var _score := 0
var _time_left := 0.0
var _last_printed_second := -1
var _debug_eval: DebugEval

@onready var _player: PlayerController = %PlayerController
@onready var _target_manager: Node3D = %TargetManager

func _ready() -> void:
	_player.pointer_lock_changed.connect(_on_pointer_lock_changed)
	_player.charge_updated.connect(_on_charge_updated)
	_debug_eval = DebugEval.new()
	add_child(_debug_eval)
	_player.charge_updated.connect(_debug_eval.on_charge_updated)
	_player.charge_released.connect(_debug_eval.on_charge_released)
	_player.pie_thrown.connect(_debug_eval.on_pie_thrown)
	_wire_targets()
	_enter_ready()
	
func _wire_targets():
	for child in _target_manager.get_children():
		var target := child as TargetBase
		if target == null: continue
		target.hit.connect(_on_target_hit)
		target.hit_zone_entered.connect(_debug_eval.on_hit_zone_entered)
		_debug_eval.register_target(target)
		
func _enter_ready() -> void:
	_state = GameState.READY
	_player.active = false
	print("[Main] READY - click to start")
	
func _start_round() -> void:
	_score = 0
	_time_left = ROUND_DURATION
	_last_printed_second = -1
	_state = GameState.PLAYING
	_player.reset_for_round()
	_player.active = true
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_player.capture_mouse()
	_report_score(_score)
	_report_time(_time_left)
	print("[Main] round start")

func _end_round() -> void:
	_state = GameState.ROUND_OVER
	_player.active = false
	_player.release_mouse()
	print("[Main] ROUND OVER - final score: %d - click to play again" % _score)
	
func restart() -> void:
	_start_round()
	
func _process(delta: float) -> void:
	if _state != GameState.PLAYING:
		return
	_time_left = maxf(_time_left - delta, 0.0)
	_report_time(_time_left)
	if _time_left <= 0.0:
		_end_round()
		
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		restart()
		get_viewport().set_input_as_handled()

func _on_pointer_lock_changed(captured: bool) -> void:
	if captured and _state != GameState.PLAYING:
		_start_round()
		
func _on_target_hit(points: int, zone: String, _target: TargetBase) -> void:
	if _state != GameState.PLAYING:
		return
	_score += points
	_report_score(_score)
	print("[Main] +%d (%s) -> %d" % [points, zone, _score])
	
func _on_charge_updated(ratio: float) -> void:
	_report_power(ratio)
	
func _report_score(value: int) -> void:
	print("[HUD] score %d" % value)

func _report_time(seconds: float) -> void:
	var whole := ceili(seconds)
	if whole != _last_printed_second:
		_last_printed_second = whole
		print("[HUD] time: %d" % whole)
		
func _report_power(_ratio: float) -> void:
	pass
