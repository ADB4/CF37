extends Node3D

@onready var _player: PlayerController = $PlayerController

func _ready() -> void:
	_player.charge_started.connect(_on_charge_started)
	_player.charge_updated.connect(_on_charge_updated)
	_player.charge_released.connect(_on_charge_released)
	_player.pie_thrown.connect(_on_pie_thrown)
	
func _on_charge_started() -> void:
	print(">>> charge_started")
	
func _on_charge_updated(ratio: float) -> void:
	if absf(ratio - roundf(ratio * 4.0) / 4.0) < 0.02:
		print("   charge_updated: %.0f%%" % (ratio * 100.0))

func _on_charge_updated_raw(_ratio: float) -> void:
	pass
	
func _on_charge_released() -> void:
	print("<<< charge_released")
	
func _on_pie_thrown(pie: PieProjectile) -> void:
	print("=== pie_thrown (speed %.1f)" % pie.linear_velocity.length())
