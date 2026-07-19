class_name PlayerController
extends Node3D

signal charge_started
signal charge_updated(ratio: float)
signal charge_released
signal pie_thrown(pie: PieProjectile)
signal pointer_lock_changed(captured: bool)

var active := true:
	set(value):
		active = value
		if not value and _charging:
			_cancel_charge()

var _pointer_captured := false

@export_group("Look")
@export var mouse_sensitivity := 0.0022
@export var yaw_limit_deg := 75.0
@export var pitch_min_deg := -50.0
@export var pitch_max_deg := 40.0
var _yaw := 0.0
var _pitch := 0.0

@export_group("Movement")
@export var move_speed := 3.0
@export var min_x := -3.2
@export var max_x := 3.2

@export_group("Throw")
@export var pie_scene: PackedScene
@export var projectile_parent: Node3D
@export var min_throw_speed := 8.0
@export var max_throw_speed := 22.0
@export var full_charge_time := 0.6
## Grace window at the start of a hold during which charge stays at 0.
## Any release inside this window is a true zero-charge (min speed) throw.
## Charge only starts accumulating after the buffer elapses, so a full
## charge takes charge_buffer_time + full_charge_time of total hold.
@export var charge_buffer_time := 0.15
@export var throw_cooldown := 0.25

var _charging := false
var _hold_time := 0.0
var _charge_time := 0.0
var _cooldown_remaining := 0.0

@onready var _camera: Camera3D = $Camera3D
@onready var _spawn_point: Marker3D = $Camera3D/SpawnPoint

func _ready() -> void:
	pass

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if _pointer_captured:
			release_mouse()

func _process(delta: float) -> void:
	if not active:
		return
	_handle_movement(delta)
	_handle_throw(delta)
	if _pointer_captured and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_on_pointer_lock_lost()

func _handle_movement(delta: float) -> void:
	var axis := Input.get_axis("move_left", "move_right")
	position.x = clampf(position.x + axis * move_speed * delta, min_x, max_x)

# runs once per input event
# godot processes input in a pipeline with multiple stages, each stage gives first dibs
# the order is generally: _shortcut_input -> _input -> gui controls -> _unhandled_key_input -> _unhandled_input
func _unhandled_input(event: InputEvent) -> void:
	# pause
	if event.is_action_pressed("pause"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			release_mouse()
		get_viewport().set_input_as_handled()
		return

	# click to recapture
	if event.is_action_pressed("throw") and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		capture_mouse()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw = clampf(
			_yaw - event.relative.x * mouse_sensitivity,
			-deg_to_rad(yaw_limit_deg),
			deg_to_rad(yaw_limit_deg)
		)
		_pitch = clampf(
			_pitch - event.relative.y * mouse_sensitivity,
			deg_to_rad(pitch_min_deg),
			deg_to_rad(pitch_max_deg)
		)
		rotation.y = _yaw
		_camera.rotation.x = _pitch

	if active and event.is_action_pressed("throw"):
		if _cooldown_remaining <= 0.0 and not _charging:
			_charging = true
			_hold_time = 0.0
			_charge_time = 0.0
			charge_started.emit()
			charge_updated.emit(0.0)

	if event.is_action_released("throw") and _charging:
		_throw()

func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_pointer_captured = true
	_cooldown_remaining = 0.2
	pointer_lock_changed.emit(true)

func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pointer_captured = false
	_cancel_charge()
	pointer_lock_changed.emit(false)

func _on_pointer_lock_lost() -> void:
	_pointer_captured = false
	if _charging:
		_cancel_charge()
	pointer_lock_changed.emit(false)

# throwing logic
func _handle_throw(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta

	if _charging:
		_hold_time += delta
		# Charge stays at 0 until the buffer elapses, then accumulates.
		_charge_time = clampf(_hold_time - charge_buffer_time, 0.0, full_charge_time)
		var ratio := _charge_time / full_charge_time
		charge_updated.emit(ratio)

		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			_cancel_charge()

func _throw() -> void:
	_charging = false
	var ratio := _charge_time / full_charge_time
	charge_released.emit()

	if pie_scene == null or projectile_parent == null:
		return

	var pie: PieProjectile = pie_scene.instantiate()
	projectile_parent.add_child(pie)
	pie.global_transform = _spawn_point.global_transform

	var speed := lerpf(min_throw_speed, max_throw_speed, ratio)
	pie.launch(-_camera.global_transform.basis.z, speed)

	pie_thrown.emit(pie)
	_cooldown_remaining = throw_cooldown


func _cancel_charge() -> void:
	if not _charging:
		return
	_charging = false
	_hold_time = 0.0
	_charge_time = 0.0
	charge_released.emit()

func reset_for_round() -> void:
	if _charging:
		_cancel_charge()
	_cooldown_remaining = 0.3
