class_name MatchState
extends RefCounted

const ELIMINATION_BATCH_RESULT_SCRIPT = preload("res://scripts/game/elimination_batch_result.gd")

const KILL_CREDIT_SECONDS := 4.0

var _player_flags: Dictionary[int, bool] = {}
var _alive: Dictionary[int, bool] = {}
var _power_stacks: Dictionary[int, int] = {}
var _last_hits: Dictionary[int, Dictionary] = {}
var _player_id := -1

func register_car(stable_id: int, is_player: bool) -> void:
	if stable_id <= 0 or _alive.has(stable_id):
		return
	_player_flags[stable_id] = is_player
	_alive[stable_id] = true
	_power_stacks[stable_id] = 0
	if is_player and _player_id < 0:
		_player_id = stable_id

func record_attack(attacker_id: int, victim_id: int, at_time: float) -> void:
	if attacker_id == victim_id or not is_alive(attacker_id) or not is_alive(victim_id):
		return
	var existing: Dictionary = _last_hits.get(victim_id, {})
	if not existing.is_empty():
		var existing_time: float = existing.time
		var existing_attacker: int = existing.attacker_id
		if at_time < existing_time or (at_time == existing_time and attacker_id >= existing_attacker):
			return
	_last_hits[victim_id] = {
		"attacker_id": attacker_id,
		"time": at_time,
	}

func resolve_eliminations(victim_ids: Array[int], at_time: float) -> EliminationBatchResult:
	var batch := EliminationBatchResult.new()
	var accepted_lookup: Dictionary[int, bool] = {}
	for victim_id in victim_ids:
		if not is_alive(victim_id) or accepted_lookup.has(victim_id):
			continue
		accepted_lookup[victim_id] = true
		batch.eliminated_ids.append(victim_id)
	batch.eliminated_ids.sort()
	batch.accepted_any = not batch.eliminated_ids.is_empty()

	for victim_id in batch.eliminated_ids:
		var hit: Dictionary = _last_hits.get(victim_id, {})
		if hit.is_empty():
			continue
		var age := at_time - float(hit.time)
		var attacker_id: int = hit.attacker_id
		if age >= 0.0 and age <= KILL_CREDIT_SECONDS and _alive.has(attacker_id):
			batch.killers_by_victim[victim_id] = attacker_id

	for victim_id in batch.eliminated_ids:
		_alive[victim_id] = false

	var buffed_lookup: Dictionary[int, bool] = {}
	for victim_id in batch.eliminated_ids:
		var killer_id: int = batch.killers_by_victim.get(victim_id, -1)
		if killer_id < 0 or not is_alive(killer_id):
			continue
		var old_stacks := get_power_stacks(killer_id)
		var new_stacks := BumperRules.clamp_stacks(old_stacks + 1)
		if new_stacks == old_stacks:
			continue
		_power_stacks[killer_id] = new_stacks
		if not buffed_lookup.has(killer_id):
			buffed_lookup[killer_id] = true
			batch.buffed_killer_ids.append(killer_id)
	batch.buffed_killer_ids.sort()
	batch.result = _current_result()
	return batch

func is_registered(stable_id: int) -> bool:
	return _alive.has(stable_id)

func is_alive(stable_id: int) -> bool:
	return _alive.get(stable_id, false)

func get_power_stacks(stable_id: int) -> int:
	return _power_stacks.get(stable_id, 0)

func get_alive_count() -> int:
	var count := 0
	for alive_value in _alive.values():
		if alive_value:
			count += 1
	return count

func get_total_count() -> int:
	return _alive.size()

func _current_result() -> StringName:
	if _player_id > 0 and not is_alive(_player_id):
		return &"defeat"
	if _player_id > 0 and is_alive(_player_id) and get_alive_count() == 1:
		return &"victory"
	return &"playing"
