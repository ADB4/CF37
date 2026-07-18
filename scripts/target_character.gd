class_name TargetCharacter
extends CharacterBody3D

signal hit_zone_entered(zone: String, body: Node3D)

@onready var _hit_zone_head: Area3D = $Pivot/HitZoneHead
@onready var _hit_zone_body: Area3D = $Pivot/HitZoneBody

func _ready() -> void:
	_hit_zone_head.body_entered.connect(_on_hit_zone_entered.bind("head"))
	_hit_zone_body.body_entered.connect(_on_hit_zone_entered.bind("body"))

func _on_hit_zone_entered(body: Node3D, zone: String) -> void:
	print("[TargetCharacter] %s zone hit by %s" % [zone, body.name])
	hit_zone_entered.emit(zone, body)
