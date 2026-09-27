class_name BumperArena
extends Node3D

@onready var _arena: Node3D = $Arena
@onready var _match_controller: MatchController = $MatchController
@onready var _hud: MatchHUD = get_node_or_null("HUD")
@onready var _director: GameFeelDirector = get_node_or_null("GameFeelDirector") as GameFeelDirector
@onready var _camera: Node3D = get_node_or_null("PlayerCar/CameraYaw")
@onready var _death_zone: DeathZone = $Arena/DeathZone
@onready var _player: BumperCar = $PlayerCar
@onready var _ai_cars: Array[BumperCar] = [$AI1, $AI2, $AI3]

func _ready() -> void:
	if _hud != null:
		_match_controller.alive_count_changed.connect(_hud.set_alive_count)
		_match_controller.player_power_changed.connect(_hud.set_power_stacks)
		_match_controller.match_ended.connect(_hud.show_result)

	_match_controller.register_car(_player, 1, true)
	for index in range(_ai_cars.size()):
		_match_controller.register_car(_ai_cars[index], index + 2, false)
	if _director != null:
		_director.bind_match(_match_controller, _player)
		if _camera != null:
			_director.camera_feedback_requested.connect(_camera.apply_impact_feedback)
		if _hud != null:
			_director.hud_cue_requested.connect(_hud.show_gameplay_cue)

	for ai_car in _ai_cars:
		var ai_driver := ai_car.get_node("AIDriver") as AIDriver
		ai_driver.bind_match(_match_controller)
		ai_driver.set_arena_center(_arena.global_position)

	_death_zone.car_entered_death_zone.connect(_match_controller.queue_elimination)
	if _hud != null:
		_hud.restart_requested.connect(_match_controller.request_restart)
	_match_controller.restart_accepted.connect(_reload_current_scene)

func _reload_current_scene() -> void:
	if _director != null:
		_director.reset_presentation()
	if _camera != null:
		_camera.reset_feedback()
	if _hud != null:
		_hud.clear_gameplay_cues()
	get_tree().reload_current_scene()
