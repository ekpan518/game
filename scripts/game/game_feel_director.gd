class_name GameFeelDirector
extends Node3D

signal camera_feedback_requested(strength: float, delivered: bool, received: bool, direction: Vector3, tier: int)
signal hud_cue_requested(text: String, priority: int)

const PRIORITY_HEAVY := 10
const PRIORITY_POWER := 20
const PRIORITY_KNOCKOUT := 30
const MAX_ACTIVE_BURSTS := 16
const BURST_SCENE = preload("res://scenes/effects/impact_burst.tscn")

var _controller: MatchController
var _player: BumperCar
var _presented_pairs: Dictionary = {}
var _bursts: Array[Node3D] = []
var _active_bursts: Array[Node3D] = []
var _pending_camera_strength := 0.0
var _pending_camera_delivered := false
var _pending_camera_received := false
var _pending_camera_direction := Vector3.ZERO
var _pending_camera_tier := ImpactFeedback.Tier.LIGHT
var _camera_scheduled := false
var _camera_generation := 0
var _slow_motion_tween: Tween

func bind_match(controller: MatchController, player: BumperCar) -> void:
	_unbind_match()
	reset_presentation()
	_controller = controller if is_instance_valid(controller) else null
	_player = player if is_instance_valid(player) else null
	if _controller == null:
		return
	_controller.impact_resolved.connect(_on_impact_resolved)
	_controller.eliminations_resolved.connect(_on_eliminations_resolved)
	_controller.restart_accepted.connect(reset_presentation)
	_controller.match_ended.connect(_on_match_ended)

func reset_presentation() -> void:
	_restore_time_scale()
	_presented_pairs.clear()
	_camera_generation += 1
	_camera_scheduled = false
	_pending_camera_strength = 0.0
	_pending_camera_delivered = false
	_pending_camera_received = false
	_pending_camera_direction = Vector3.ZERO
	_pending_camera_tier = ImpactFeedback.Tier.LIGHT
	for burst in _bursts:
		if is_instance_valid(burst):
			burst.reset_for_pool()
	_active_bursts.clear()

func _exit_tree() -> void:
	_unbind_match()
	reset_presentation()

func _unbind_match() -> void:
	if is_instance_valid(_controller):
		if _controller.impact_resolved.is_connected(_on_impact_resolved):
			_controller.impact_resolved.disconnect(_on_impact_resolved)
		if _controller.eliminations_resolved.is_connected(_on_eliminations_resolved):
			_controller.eliminations_resolved.disconnect(_on_eliminations_resolved)
		if _controller.restart_accepted.is_connected(reset_presentation):
			_controller.restart_accepted.disconnect(reset_presentation)
		if _controller.match_ended.is_connected(_on_match_ended):
			_controller.match_ended.disconnect(_on_match_ended)
	_controller = null
	_player = null

func _on_impact_resolved(feedback: ImpactFeedback) -> void:
	if feedback == null:
		return
	var strength := clampf(feedback.normalized_strength, 0.0, 1.0)
	var key := BumperRules.pair_key(feedback.stable_a, feedback.stable_b)
	var now := float(Time.get_ticks_usec()) / 1000000.0
	var previous: Dictionary = _presented_pairs.get(key, {})
	if not ImpactFeedbackRules.should_present(now, previous.get("time", -1.0), previous.get("strength", 0.0), strength, feedback.tier):
		return
	_presented_pairs[key] = {"time": now, "strength": strength}
	_play_burst(feedback)
	if feedback.tier != ImpactFeedback.Tier.LIGHT and (feedback.player_delivered or feedback.player_received):
		_pending_camera_strength = minf(1.0, _pending_camera_strength + strength)
		_pending_camera_delivered = _pending_camera_delivered or feedback.player_delivered
		_pending_camera_received = _pending_camera_received or feedback.player_received
		var direction := Vector3(feedback.direction.x, 0.0, feedback.direction.z)
		if not direction.is_zero_approx():
			var role_weight := 1.0 if feedback.player_received else 0.65
			_pending_camera_direction += direction.normalized() * strength * role_weight
		_pending_camera_tier = maxi(_pending_camera_tier, feedback.tier)
		if not _camera_scheduled:
			_camera_scheduled = true
			call_deferred("_flush_camera_feedback", _camera_generation)
	if feedback.player_delivered and feedback.tier != ImpactFeedback.Tier.LIGHT:
		hud_cue_requested.emit("重击！", PRIORITY_HEAVY)

func _play_burst(feedback: ImpactFeedback) -> void:
	var burst: Node3D
	for candidate in _bursts:
		if not candidate.visible:
			burst = candidate
			break
	if burst == null and _bursts.size() < MAX_ACTIVE_BURSTS:
		burst = BURST_SCENE.instantiate() as Node3D
		_bursts.append(burst)
		add_child(burst)
		burst.finished.connect(_on_burst_finished)
	if burst == null:
		burst = _active_bursts.pop_front()
		burst.reset_for_pool()
	_active_bursts.erase(burst)
	_active_bursts.append(burst)
	burst.play(feedback)

func _on_burst_finished(burst: Node3D) -> void:
	_active_bursts.erase(burst)

func _flush_camera_feedback(generation: int) -> void:
	if generation != _camera_generation or not _camera_scheduled:
		return
	_camera_scheduled = false
	var strength := _pending_camera_strength
	var delivered := _pending_camera_delivered
	var received := _pending_camera_received
	var direction := _pending_camera_direction.normalized() if not _pending_camera_direction.is_zero_approx() else Vector3.ZERO
	var tier := _pending_camera_tier
	_pending_camera_strength = 0.0
	_pending_camera_delivered = false
	_pending_camera_received = false
	_pending_camera_direction = Vector3.ZERO
	_pending_camera_tier = ImpactFeedback.Tier.LIGHT
	camera_feedback_requested.emit(strength, delivered, received, direction, tier)

func _on_eliminations_resolved(batch: EliminationBatchResult) -> void:
	if batch == null or not is_instance_valid(_player) or not _player.alive:
		return
	var player_id := _player.stable_id
	if player_id <= 0 or player_id in batch.eliminated_ids:
		return
	var credited_kill := false
	for killer_id in batch.killers_by_victim.values():
		if killer_id == player_id:
			credited_kill = true
			break
	if player_id in batch.buffed_killer_ids:
		hud_cue_requested.emit("强化 +1", PRIORITY_POWER)
	if credited_kill:
		hud_cue_requested.emit("击落！", PRIORITY_KNOCKOUT)
		_start_slow_motion()

func _on_match_ended(result: StringName) -> void:
	if result == &"defeat":
		_restore_time_scale()

func _start_slow_motion() -> void:
	_restore_time_scale()
	Engine.time_scale = 0.38
	_slow_motion_tween = create_tween().set_ignore_time_scale(true)
	_slow_motion_tween.tween_interval(0.24)
	_slow_motion_tween.tween_callback(_restore_time_scale)

func _restore_time_scale() -> void:
	if _slow_motion_tween != null and _slow_motion_tween.is_running():
		_slow_motion_tween.kill()
	_slow_motion_tween = null
	Engine.time_scale = 1.0
