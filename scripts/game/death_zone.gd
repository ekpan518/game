class_name DeathZone
extends Area3D

signal car_entered_death_zone(car: BumperCar)

func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	var car := body as BumperCar
	if car != null:
		car_entered_death_zone.emit(car)
