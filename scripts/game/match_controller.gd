class_name MatchController
extends Node

const MATCH_STATE_SCRIPT = preload("res://scripts/game/match_state.gd")

signal alive_count_changed(alive: int, total: int)
signal player_power_changed(stacks: int)
signal match_ended(result: StringName)
signal restart_accepted

const FALL_ELIMINATION_Y := -12.0

var _state: MatchState = MatchState.new()
var _cars_by_id: Dictionary[int, BumperCar] = {}
var _ids_by_instance: Dictionary[int, int] = {}
var _player_id := -1
var _player_power_initialized := false
var _contacts_by_frame: Dictionary[int, Dictionary] = {}
var _deaths_by_frame: Dictionary[int, Dictionary] = {}
var _drain_scheduled := false
var _restart_latched := false
var _match_ended := false
var _match_time := 0.0

func register_car(car: BumperCar, stable_id: int, is_player: bool) -> void:
	if car == null or not is_instance_valid(car) or not car.alive or stable_id <= 0:
		return
	var instance_id := car.get_instance_id()
	if _ids_by_instance.has(instance_id) or _cars_by_id.has(stable_id):
		return
	_ids_by_instance[instance_id] = stable_id
	_cars_by_id[stable_id] = car
	car.stable_id = stable_id
	_state.register_car(stable_id, is_player)
	if not car.contact_reported.is_connected(report_contact):
		car.contact_reported.connect(report_contact)
	alive_count_changed.emit(_state.get_alive_count(), _state.get_total_count())
	if is_player and not _player_power_initialized:
		_player_id = stable_id
		_player_power_initialized = true
		player_power_changed.emit(0)

func report_contact(reporter: BumperCar, other: BumperCar, contact_normal: Vector3, reporter_velocity: Vector3, physics_frame: int) -> void:
	if _match_ended or not _is_registered_live_car(reporter) or not _is_registered_live_car(other) or reporter == other:
		return
	var reporter_id: int = _ids_by_instance[reporter.get_instance_id()]
	var other_id: int = _ids_by_instance[other.get_instance_id()]
	var stable_a := mini(reporter_id, other_id)
	var stable_b := maxi(reporter_id, other_id)
	var pair_key := BumperRules.pair_key(stable_a, stable_b)
	var frame_contacts: Dictionary = _contacts_by_frame.get(physics_frame, {})
	var fallback := Vector3(contact_normal.x, 0.0, contact_normal.z)
	if reporter_id == stable_b:
		fallback = -fallback
	if frame_contacts.has(pair_key):
		var existing: Dictionary = frame_contacts[pair_key]
		if (existing.fallback as Vector3).is_zero_approx() and not fallback.is_zero_approx():
			existing.fallback = fallback
			frame_contacts[pair_key] = existing
	else:
		frame_contacts[pair_key] = {
			"stable_a": stable_a,
			"stable_b": stable_b,
			"fallback": fallback,
		}
	_contacts_by_frame[physics_frame] = frame_contacts
	_schedule_drain()

func queue_elimination(car: BumperCar, source: StringName = &"death_zone") -> bool:
	if _match_ended or not _is_registered_live_car(car):
		return false
	var physics_frame := Engine.get_physics_frames()
	var frame_deaths: Dictionary = _deaths_by_frame.get(physics_frame, {})
	var instance_id := car.get_instance_id()
	if frame_deaths.has(instance_id):
		return false
	frame_deaths[instance_id] = car
	_deaths_by_frame[physics_frame] = frame_deaths
	_schedule_drain()
	return true

func get_live_opponents_for(requester: BumperCar) -> Array[BumperCar]:
	var opponents: Array[BumperCar] = []
	if not _is_registered_live_car(requester):
		return opponents
	var requester_id: int = _ids_by_instance[requester.get_instance_id()]
	var stable_ids: Array[int] = []
	stable_ids.assign(_cars_by_id.keys())
	stable_ids.sort()
	for stable_id in stable_ids:
		if stable_id == requester_id or not _state.is_alive(stable_id):
			continue
		var car: BumperCar = _cars_by_id[stable_id]
		if is_instance_valid(car) and car.alive:
			opponents.append(car)
	return opponents

func request_restart() -> bool:
	if _restart_latched:
		return false
	_restart_latched = true
	restart_accepted.emit()
	return true

func advance_match_time(delta: float) -> void:
	_match_time += maxf(delta, 0.0)

func _physics_process(delta: float) -> void:
	if _match_ended:
		return
	advance_match_time(delta)
	var stable_ids: Array[int] = []
	stable_ids.assign(_cars_by_id.keys())
	stable_ids.sort()
	for stable_id in stable_ids:
		if not _state.is_alive(stable_id):
			continue
		var car: BumperCar = _cars_by_id[stable_id]
		if is_instance_valid(car) and car.alive and car.global_position.y < FALL_ELIMINATION_Y:
			queue_elimination(car, &"fall_fallback")

func _schedule_drain() -> void:
	if _drain_scheduled:
		return
	_drain_scheduled = true
	call_deferred("_drain_pending")

func _drain_pending() -> void:
	var contacts := _contacts_by_frame
	var deaths := _deaths_by_frame
	_contacts_by_frame = {}
	_deaths_by_frame = {}
	var frame_lookup: Dictionary[int, bool] = {}
	for frame in contacts.keys():
		frame_lookup[int(frame)] = true
	for frame in deaths.keys():
		frame_lookup[int(frame)] = true
	var frames: Array[int] = []
	frames.assign(frame_lookup.keys())
	frames.sort()
	for physics_frame in frames:
		_flush_contacts(contacts.get(physics_frame, {}), physics_frame)
		_flush_deaths(deaths.get(physics_frame, {}))
	_drain_scheduled = false
	if not _contacts_by_frame.is_empty() or not _deaths_by_frame.is_empty():
		_schedule_drain()

func _flush_contacts(frame_contacts: Dictionary, physics_frame: int) -> void:
	var pair_keys: Array[String] = []
	pair_keys.assign(frame_contacts.keys())
	pair_keys.sort()
	for pair_key in pair_keys:
		var entry: Dictionary = frame_contacts[pair_key]
		var stable_a: int = entry.stable_a
		var stable_b: int = entry.stable_b
		if not _state.is_alive(stable_a) or not _state.is_alive(stable_b):
			continue
		var car_a: BumperCar = _cars_by_id.get(stable_a)
		var car_b: BumperCar = _cars_by_id.get(stable_b)
		if not is_instance_valid(car_a) or not is_instance_valid(car_b) or not car_a.alive or not car_b.alive:
			continue
		if not car_a.has_snapshot_for_frame(physics_frame) or not car_b.has_snapshot_for_frame(physics_frame):
			continue
		var velocity_a := car_a.get_snapshot_for_frame(physics_frame)
		var velocity_b := car_b.get_snapshot_for_frame(physics_frame)
		var direction := car_b.global_position - car_a.global_position
		direction.y = 0.0
		if direction.is_zero_approx():
			direction = entry.fallback
			direction.y = 0.0
		if direction.is_zero_approx():
			continue
		direction = direction.normalized()
		var attack_a := BumperRules.calculate_attack(velocity_a, velocity_b, direction, _state.get_power_stacks(stable_a), _state.get_power_stacks(stable_b))
		var attack_b := BumperRules.calculate_attack(velocity_b, velocity_a, -direction, _state.get_power_stacks(stable_b), _state.get_power_stacks(stable_a))
		if attack_a.effective:
			_state.record_attack(stable_a, stable_b, _match_time)
		if attack_b.effective:
			_state.record_attack(stable_b, stable_a, _match_time)
		if not attack_a.impulse.is_zero_approx():
			car_b.apply_knockback(attack_a.impulse)
		if not attack_b.impulse.is_zero_approx():
			car_a.apply_knockback(attack_b.impulse)

func _flush_deaths(frame_deaths: Dictionary) -> void:
	var victim_ids: Array[int] = []
	for car_value in frame_deaths.values():
		var car := car_value as BumperCar
		if not _is_registered_live_car(car):
			continue
		var stable_id: int = _ids_by_instance[car.get_instance_id()]
		if stable_id not in victim_ids:
			victim_ids.append(stable_id)
	if victim_ids.is_empty():
		return
	var batch := _state.resolve_eliminations(victim_ids, _match_time)
	if not batch.accepted_any:
		return
	for stable_id in batch.eliminated_ids:
		var eliminated_car: BumperCar = _cars_by_id.get(stable_id)
		if is_instance_valid(eliminated_car):
			eliminated_car.eliminate()
	for killer_id in batch.buffed_killer_ids:
		var killer_car: BumperCar = _cars_by_id.get(killer_id)
		if is_instance_valid(killer_car):
			killer_car.set_power_stacks(_state.get_power_stacks(killer_id))
	alive_count_changed.emit(_state.get_alive_count(), _state.get_total_count())
	if _player_id in batch.buffed_killer_ids:
		player_power_changed.emit(_state.get_power_stacks(_player_id))
	if batch.result != &"playing" and not _match_ended:
		_match_ended = true
		_freeze_survivors()
		match_ended.emit(batch.result)

func _freeze_survivors() -> void:
	for stable_id in _cars_by_id:
		if not _state.is_alive(stable_id):
			continue
		var car: BumperCar = _cars_by_id[stable_id]
		if is_instance_valid(car):
			car.freeze_for_result()

func _is_registered_live_car(car: BumperCar) -> bool:
	if car == null or not is_instance_valid(car) or not car.alive:
		return false
	var instance_id := car.get_instance_id()
	if not _ids_by_instance.has(instance_id):
		return false
	return _state.is_alive(_ids_by_instance[instance_id])
