class_name BumperArena
extends Node3D

@onready var _arena: Node3D = $Arena
@onready var _match_controller: MatchController = $MatchController
@onready var _hud: MatchHUD = $HUD
@onready var _death_zone: DeathZone = $Arena/DeathZone
@onready var _player: BumperCar = $PlayerCar
@onready var _ai_cars: Array[BumperCar] = [$AI1, $AI2, $AI3]

func _ready() -> void:
	_match_controller.alive_count_changed.connect(_hud.set_alive_count)
	_match_controller.player_power_changed.connect(_hud.set_power_stacks)
	_match_controller.match_ended.connect(_hud.show_result)

	_match_controller.register_car(_player, 1, true)
	for index in range(_ai_cars.size()):
		_match_controller.register_car(_ai_cars[index], index + 2, false)

	for ai_car in _ai_cars:
		var ai_driver := ai_car.get_node("AIDriver") as AIDriver
		ai_driver.bind_match(_match_controller)
		ai_driver.set_arena_center(_arena.global_position)

	_death_zone.car_entered_death_zone.connect(_match_controller.queue_elimination)
	_hud.restart_requested.connect(_match_controller.request_restart)
	_match_controller.restart_accepted.connect(_reload_current_scene)

func _reload_current_scene() -> void:
	get_tree().reload_current_scene()
