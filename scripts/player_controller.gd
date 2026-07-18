class_name PlayerController
extends Node3D

var active := true:
	set(value):
		active = value
		if not value:
			# future: cancel in-flight charge
			pass

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

@export_group("Throw (temp)")
@export var pie_scene: PackedScene
@export var projectile_parent: Node3D
@export var test_throw_speed := 18.0

@onready var _camera: Camera3D = $Camera3D
@onready var _spawn_point: Marker3D = $Camera3D/SpawnPoint

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	if not active:
		return
	_handle_movement(delta)
		
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

	if active and event.is_action_pressed("throw") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_test_throw()

func _test_throw() -> void:
	if pie_scene == null or projectile_parent == null:
		return
	var pie: PieProjectile = pie_scene.instantiate()
	projectile_parent.add_child(pie)
	pie.global_transform = _spawn_point.global_transform
	pie.launch(-_camera.global_transform.basis.z, test_throw_speed)
