class_name PlayerController
extends Node3D

signal charge_started
signal charge_updated(ratio: float)
signal charge_released
signal pie_thrown(pie: PieProjectile)

var active := true:
	set(value):
		active = value
		if not value and _charging:
			_cancel_charge()

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
@export var throw_cooldown := 0.25

var _charging := false
var _charge_time := 0.0
var _cooldown_remaining := 0.0

@onready var _camera: Camera3D = $Camera3D
@onready var _spawn_point: Marker3D = $Camera3D/SpawnPoint

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	if not active:
		return
	_handle_movement(delta)
	_handle_throw(delta)
		
func _handle_movement(delta: float) -> void:
	var axis := Input.get_axis("move_left", "move_right")
	position.x = clampf(position.x + axis * move_speed * delta, min_x, max_x)

func _unhandled_input(event: InputEvent) -> void:
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
	
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
		
	if not active:
		return
		
	if event.is_action_pressed("throw") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _cooldown_remaining <= 0.0 and not _charging:
			_charging = true
			_charge_time = 0.0
			charge_started.emit()
			charge_updated.emit(0.0)
			
	if event.is_action_released("throw") and _charging:
		_throw()

# throwing logic
func _handle_throw(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta
		
	if _charging:
		_charge_time = minf(_charge_time + delta, full_charge_time)
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
	_charging = false
	_charge_time = 0.0
	charge_released.emit()
	
func reset_for_round() -> void:
	if _charging:
		_cancel_charge()
	_cooldown_remaining = 0.3
