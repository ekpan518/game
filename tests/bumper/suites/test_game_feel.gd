extends RefCounted

const FEEDBACK_SCRIPT = preload("res://scripts/bumper/impact_feedback.gd")
const FEEDBACK_RULES_SCRIPT = preload("res://scripts/bumper/impact_feedback_rules.gd")
const MATCH_CONTROLLER_SCRIPT = preload("res://scripts/game/match_controller.gd")
const CAR_SCENE = preload("res://scenes/vehicles/bumper_car.tscn")
const SOUND_FACTORY_PATH = "res://scripts/audio/arcade_sound_factory.gd"
const BURST_SCENE_PATH = "res://scenes/effects/impact_burst.tscn"
const DIRECTOR_PATH = "res://scripts/game/game_feel_director.gd"

class PresentationRecorder:
	extends RefCounted
	var cameras: Array[Array] = []
	var cues: Array[Array] = []
	func camera(strength: float, delivered: bool, received: bool) -> void:
		cameras.append([strength, delivered, received])
	func cue(message: String, priority: int) -> void:
		cues.append([message, priority])

class FeedbackRecorder:
	extends RefCounted
	var values: Array[ImpactFeedback] = []
	func record(feedback: ImpactFeedback) -> void:
		values.append(feedback)

class BurstRecorder:
	extends RefCounted
	var count := 0
	func record(_effect: Node3D) -> void:
		count += 1

func run(tree: SceneTree) -> Array[String]:
	await tree.process_frame
	var failures: Array[String] = []
	var rules = FEEDBACK_RULES_SCRIPT
	var feedback = FEEDBACK_SCRIPT.new()
	_expect(feedback is ImpactFeedback, "Feedback data must be an ImpactFeedback", failures)
	feedback.stable_a = 4
	feedback.stable_b = 8
	feedback.world_position = Vector3(1, 2, 3)
	feedback.direction = Vector3.RIGHT
	feedback.impulse_magnitude = 7.0
	feedback.normalized_strength = 0.5
	feedback.tier = ImpactFeedback.Tier.HEAVY
	feedback.player_delivered = true
	feedback.player_received = false
	_expect(feedback.stable_a == 4 and feedback.stable_b == 8, "Feedback must retain stable pair IDs", failures)
	_expect(feedback.world_position == Vector3(1, 2, 3) and feedback.direction == Vector3.RIGHT, "Feedback must retain impact vectors", failures)
	_expect(is_equal_approx(feedback.impulse_magnitude, 7.0) and is_equal_approx(feedback.normalized_strength, 0.5), "Feedback must retain magnitude and strength", failures)
	_expect(feedback.tier == ImpactFeedback.Tier.HEAVY and feedback.player_delivered and not feedback.player_received, "Feedback must retain tier and player roles", failures)
	_expect(is_equal_approx(rules.normalized_strength(-1.0), 0.0), "Negative impulse must normalize to zero", failures)
	_expect(is_equal_approx(rules.normalized_strength(0.0), 0.0), "Zero impulse must normalize to zero", failures)
	_expect(is_equal_approx(rules.normalized_strength(7.0), 0.5), "Half-cap impulse must normalize to half strength", failures)
	_expect(is_equal_approx(rules.normalized_strength(14.0), 1.0), "Max impulse must normalize to one", failures)
	_expect(is_equal_approx(rules.normalized_strength(20.0), 1.0), "Oversized impulse must normalize to one", failures)
	_expect(rules.tier_for_strength(0.2199) == ImpactFeedback.Tier.LIGHT, "Strength below 0.22 must be light", failures)
	_expect(rules.tier_for_strength(0.22) == ImpactFeedback.Tier.HEAVY, "Strength at 0.22 must be heavy", failures)
	_expect(rules.tier_for_strength(0.5499) == ImpactFeedback.Tier.HEAVY, "Strength below 0.55 must be heavy", failures)
	_expect(rules.tier_for_strength(0.55) == ImpactFeedback.Tier.SMASH, "Strength at 0.55 must be smash", failures)
	_expect(is_equal_approx(rules.cooldown_for_tier(ImpactFeedback.Tier.LIGHT), 0.16), "Light cooldown must be 0.16 seconds", failures)
	_expect(is_equal_approx(rules.cooldown_for_tier(ImpactFeedback.Tier.HEAVY), 0.10), "Heavy cooldown must be 0.10 seconds", failures)
	_expect(is_equal_approx(rules.cooldown_for_tier(ImpactFeedback.Tier.SMASH), 0.10), "Smash cooldown must be 0.10 seconds", failures)
	_expect(rules.should_present(0.0, -1.0, 0.0, 0.1, ImpactFeedback.Tier.LIGHT), "Missing previous timestamp must present immediately", failures)
	_expect(not rules.should_present(0.159, 0.0, 0.5, 0.5, ImpactFeedback.Tier.LIGHT), "Light impact before cooldown must be suppressed", failures)
	_expect(rules.should_present(0.16, 0.0, 0.5, 0.5, ImpactFeedback.Tier.LIGHT), "Light impact at cooldown must present", failures)
	_expect(not rules.should_present(0.099, 0.0, 0.5, 0.5, ImpactFeedback.Tier.HEAVY), "Heavy impact before cooldown must be suppressed", failures)
	_expect(rules.should_present(0.10, 0.0, 0.5, 0.5, ImpactFeedback.Tier.HEAVY), "Heavy impact at cooldown must present", failures)
	_expect(not rules.should_present(0.099, 0.0, 0.5, 0.5, ImpactFeedback.Tier.SMASH), "Smash impact before cooldown must be suppressed", failures)
	_expect(rules.should_present(0.10, 0.0, 0.5, 0.5, ImpactFeedback.Tier.SMASH), "Smash impact at cooldown must present", failures)
	_expect(not rules.should_present(0.01, 0.0, 0.0, 0.179, ImpactFeedback.Tier.LIGHT), "Early impact below 0.18 improvement must be suppressed", failures)
	_expect(rules.should_present(0.01, 0.0, 0.0, 0.18, ImpactFeedback.Tier.LIGHT), "Early impact at 0.18 improvement must present", failures)
	await _test_resolved_light_contact(tree, failures)
	_test_impact_audio(failures)
	await _test_impact_burst_played_before_entering_tree(tree, failures)
	await _test_impact_burst(tree, failures)
	if not ResourceLoader.exists(DIRECTOR_PATH):
		failures.append("GameFeelDirector is missing: director behavior and slow-motion lifecycle cannot run")
	else:
		await _test_director_contact_and_pool(tree, failures)
		await _test_director_rebinding_and_rewards(tree, failures)
		await _test_director_slow_motion(tree, failures)
	_expect(is_equal_approx(Engine.time_scale, 1.0), "Feel scope must leave Engine.time_scale at 1.0", failures)
	return failures

func _new_feedback(first: int, second: int, strength: float, delivered: bool = false, received: bool = false) -> ImpactFeedback:
	var feedback := ImpactFeedback.new()
	feedback.stable_a = first
	feedback.stable_b = second
	feedback.world_position = Vector3(first, 1.0, second)
	feedback.normalized_strength = strength
	feedback.tier = ImpactFeedbackRules.tier_for_strength(strength)
	feedback.player_delivered = delivered
	feedback.player_received = received
	return feedback

func _new_director(tree: SceneTree, controller: MatchController, player: BumperCar) -> Node:
	var director: Node = load(DIRECTOR_PATH).new()
	tree.root.add_child(director)
	director.bind_match(controller, player)
	return director

func _active_bursts(director: Node) -> Array[Node3D]:
	var active: Array[Node3D] = []
	for child in director.get_children():
		if child is Node3D and child.has_method("reset_for_pool") and child.visible:
			active.append(child)
	return active

func _test_director_contact_and_pool(tree: SceneTree, failures: Array[String]) -> void:
	var controller := MATCH_CONTROLLER_SCRIPT.new()
	var director := _new_director(tree, controller, null)
	controller.impact_resolved.emit(_new_feedback(90, 91, 0.30))
	_expect(_active_bursts(director).size() == 1, "Missing camera/HUD listeners and null player must not block a burst", failures)
	director.reset_presentation()
	var recorder := PresentationRecorder.new()
	director.camera_feedback_requested.connect(recorder.camera)
	controller.impact_resolved.emit(_new_feedback(1, 2, 0.30, true))
	_expect(_active_bursts(director).size() == 1, "First impact must present synchronously without camera or HUD listeners", failures)
	for index in range(65):
		controller.impact_resolved.emit(_new_feedback(1, 2, 0.30, true))
		await tree.create_timer(0.032, true, false, true).timeout
	_expect(_active_bursts(director).size() <= 4 and director.get_child_count() <= 4, "Two-second sustained contact must not fill the effect pool", failures)
	var prior_count := _active_bursts(director).size()
	controller.impact_resolved.emit(_new_feedback(1, 2, 0.31, true))
	_expect(_active_bursts(director).size() <= maxi(prior_count, 1), "Same-pair impact inside cooldown must be suppressed", failures)
	controller.impact_resolved.emit(_new_feedback(1, 2, 0.50, true))
	_expect(_active_bursts(director).size() > prior_count, "Strength improvement of at least 0.18 must bypass pair cooldown", failures)
	controller.impact_resolved.emit(_new_feedback(3, 4, 0.30, false, true))
	_expect(_active_bursts(director).size() > prior_count + 1, "A second pair must have an independent presentation cooldown", failures)
	director.reset_presentation()
	controller.impact_resolved.emit(_new_feedback(10, 11, 0.0))
	var before_upgrade := _active_bursts(director).size()
	controller.impact_resolved.emit(_new_feedback(10, 11, 0.18))
	_expect(_active_bursts(director).size() == before_upgrade + 1, "An exact 0.18 improvement must bypass the pair cooldown", failures)
	director.reset_presentation()
	recorder.cameras.clear()
	for index in range(5, 21):
		controller.impact_resolved.emit(_new_feedback(index, index + 100, 1.0, index % 2 == 0, index % 2 == 1))
	var oldest := _active_bursts(director)[0]
	controller.impact_resolved.emit(_new_feedback(21, 121, 1.0))
	_expect(oldest.global_position.is_equal_approx(Vector3(21, 1.0, 121)), "A seventeenth impact must recycle the oldest active burst", failures)
	for index in range(22, 25):
		controller.impact_resolved.emit(_new_feedback(index, index + 100, 1.0, index % 2 == 0, index % 2 == 1))
	_expect(_active_bursts(director).size() == 16, "At most 16 bursts must be active after a same-frame impact wave", failures)
	var burst_count := 0
	for child in director.get_children():
		if child is Node3D and child.has_method("reset_for_pool"):
			burst_count += 1
	_expect(burst_count == 16, "Capacity must recycle the oldest burst rather than allocate a seventeenth", failures)
	await tree.process_frame
	_expect(recorder.cameras.size() == 1 and is_equal_approx(recorder.cameras[0][0], 1.0) and recorder.cameras[0][1] and recorder.cameras[0][2], "Same-frame camera requests must aggregate roles to strength at most one", failures)
	director.reset_presentation()
	_expect(_active_bursts(director).is_empty(), "Reset must return all active bursts to the pool", failures)
	director.queue_free()
	controller.queue_free()
	await tree.process_frame

func _test_director_rebinding_and_rewards(tree: SceneTree, failures: Array[String]) -> void:
	var first := MATCH_CONTROLLER_SCRIPT.new()
	var second := MATCH_CONTROLLER_SCRIPT.new()
	var player := CAR_SCENE.instantiate() as BumperCar
	player.set_physics_process(false)
	tree.root.add_child(player)
	var director := _new_director(tree, first, player)
	var recorder := PresentationRecorder.new()
	director.camera_feedback_requested.connect(recorder.camera)
	director.hud_cue_requested.connect(recorder.cue)
	director.bind_match(first, player)
	_expect(first.impact_resolved.get_connections().size() == 1, "Repeated binding must not duplicate impact subscriptions", failures)
	director.bind_match(second, player)
	_expect(first.impact_resolved.get_connections().is_empty() and second.impact_resolved.get_connections().size() == 1, "Rebinding must disconnect the old match", failures)
	first.impact_resolved.emit(_new_feedback(1, 2, 0.8, true))
	_expect(_active_bursts(director).is_empty(), "Old match impacts must not present after rebind", failures)
	second.impact_resolved.emit(_new_feedback(1, 2, 0.8, true))
	_expect(_active_bursts(director).size() == 1, "New match impact must present immediately", failures)
	recorder.cues.clear()
	var no_player_reward := EliminationBatchResult.new()
	no_player_reward.eliminated_ids = [3]
	no_player_reward.killers_by_victim = {3: 2}
	no_player_reward.buffed_killer_ids = [2]
	second.eliminations_resolved.emit(no_player_reward)
	_expect(recorder.cues.is_empty(), "AI kills and AI power must not request player HUD rewards", failures)
	player.stable_id = 1
	var credited := EliminationBatchResult.new()
	credited.eliminated_ids = [3]
	credited.killers_by_victim = {3: 1}
	credited.buffed_killer_ids = [1]
	second.eliminations_resolved.emit(credited)
	_expect(recorder.cues.any(func(value: Array) -> bool: return value[0] == "强化 +1" and value[1] == 20), "A surviving player buff must request the power cue", failures)
	_expect(recorder.cues.any(func(value: Array) -> bool: return value[1] == 30), "A surviving player kill must request the knockout cue", failures)
	var count_before := recorder.cues.size()
	var capped := EliminationBatchResult.new()
	capped.eliminated_ids = [4]
	capped.killers_by_victim = {4: 1}
	second.eliminations_resolved.emit(capped)
	for index in range(count_before, recorder.cues.size()):
		_expect(recorder.cues[index][0] != "强化 +1", "A full-stack kill must not claim another power gain", failures)
	var simultaneous := EliminationBatchResult.new()
	simultaneous.eliminated_ids = [1, 5]
	simultaneous.killers_by_victim = {5: 1}
	simultaneous.result = &"defeat"
	count_before = recorder.cues.size()
	second.eliminations_resolved.emit(simultaneous)
	_expect(recorder.cues.size() == count_before, "A player killed in the same batch must receive no reward", failures)
	director.reset_presentation()
	director.queue_free()
	first.queue_free()
	second.queue_free()
	player.queue_free()
	await tree.process_frame

func _test_director_slow_motion(tree: SceneTree, failures: Array[String]) -> void:
	var controller := MATCH_CONTROLLER_SCRIPT.new()
	var player := CAR_SCENE.instantiate() as BumperCar
	player.stable_id = 1
	player.set_physics_process(false)
	tree.root.add_child(player)
	var director := _new_director(tree, controller, player)
	var credited := EliminationBatchResult.new()
	credited.eliminated_ids = [2]
	credited.killers_by_victim = {2: 1}
	credited.buffed_killer_ids = [1]
	controller.eliminations_resolved.emit(credited)
	_expect(is_equal_approx(Engine.time_scale, 0.38), "Surviving player kill must synchronously start 0.38 slow motion", failures)
	await tree.create_timer(0.28, true, false, true).timeout
	_expect(is_equal_approx(Engine.time_scale, 1.0), "Slow motion must restore after 0.24 real seconds", failures)
	controller.eliminations_resolved.emit(credited)
	director.reset_presentation()
	_expect(is_equal_approx(Engine.time_scale, 1.0), "Reset during slow motion must restore scale exactly to 1", failures)
	controller.eliminations_resolved.emit(credited)
	await tree.create_timer(0.12, true, false, true).timeout
	controller.eliminations_resolved.emit(credited)
	_expect(is_equal_approx(Engine.time_scale, 0.38), "Repeated kills must restart slow motion without stacking scale", failures)
	await tree.create_timer(0.15, true, false, true).timeout
	_expect(is_equal_approx(Engine.time_scale, 0.38), "First kill's recovery must not cancel the replacement slow motion", failures)
	var other := MATCH_CONTROLLER_SCRIPT.new()
	director.bind_match(other, player)
	_expect(is_equal_approx(Engine.time_scale, 1.0), "Rebinding during slow motion must restore scale", failures)
	other.eliminations_resolved.emit(credited)
	director.get_parent().remove_child(director)
	_expect(is_equal_approx(Engine.time_scale, 1.0), "Exit tree during slow motion must restore scale", failures)
	tree.root.add_child(director)
	director.bind_match(other, player)
	other.eliminations_resolved.emit(credited)
	director.queue_free()
	await tree.process_frame
	_expect(is_equal_approx(Engine.time_scale, 1.0), "Deleting director during slow motion must restore scale", failures)
	controller.queue_free()
	other.queue_free()
	player.queue_free()
	await tree.process_frame

func _test_impact_burst_played_before_entering_tree(tree: SceneTree, failures: Array[String]) -> void:
	var scene: PackedScene = load(BURST_SCENE_PATH)
	if scene == null:
		failures.append("Impact burst scene must load for pre-ready playback")
		return
	var burst: Node3D = scene.instantiate()
	var feedback := ImpactFeedback.new()
	feedback.world_position = Vector3(2.0, 1.0, -3.0)
	feedback.normalized_strength = 0.45
	feedback.tier = ImpactFeedback.Tier.HEAVY
	var recorder := BurstRecorder.new()
	burst.finished.connect(recorder.record)
	burst.play(feedback)
	tree.root.add_child(burst)
	await tree.process_frame
	_expect(burst.visible and burst.global_position.is_equal_approx(feedback.world_position), "Play before entering tree must activate the burst once ready", failures)
	await tree.create_timer(0.35).timeout
	_expect(recorder.count == 1 and not burst.visible, "Pre-ready playback must finish once and return to the pool", failures)
	burst.queue_free()
	await tree.process_frame

func _test_impact_audio(failures: Array[String]) -> void:
	if not ResourceLoader.exists(SOUND_FACTORY_PATH):
		failures.append("Procedural impact sound factory must exist")
		return
	var factory: Script = load(SOUND_FACTORY_PATH)
	if factory == null or not factory.can_instantiate():
		failures.append("Procedural impact sound factory must load")
		return
	var previous_energy := -1.0
	for tier in [ImpactFeedback.Tier.LIGHT, ImpactFeedback.Tier.HEAVY, ImpactFeedback.Tier.SMASH]:
		var stream: AudioStreamWAV = factory.get_impact_stream(tier)
		_expect(stream != null, "Every impact tier must have a WAV stream", failures)
		if stream == null:
			continue
		_expect(stream == factory.get_impact_stream(tier), "Impact WAVs must be cached by tier", failures)
		_expect(stream.mix_rate == 22050 and not stream.stereo, "Impact WAVs must be 22050 Hz mono", failures)
		_expect(stream.get_length() > 0.0 and stream.get_length() < 0.40, "Impact WAVs must be nonempty and shorter than 0.40 seconds", failures)
		var samples: PackedByteArray = stream.data
		_expect(samples.size() > 0, "Impact WAVs must contain PCM data", failures)
		if samples.is_empty():
			continue
		var sum_of_squares := 0.0
		for offset in range(0, samples.size() - 1, 2):
			var amplitude := float(samples.decode_s16(offset)) / 32768.0
			sum_of_squares += amplitude * amplitude
		var energy := sqrt(sum_of_squares / float(samples.size() / 2))
		_expect(energy > previous_energy, "Impact tier RMS energy must increase", failures)
		previous_energy = energy
	var master_bus := AudioServer.get_bus_index("Master")
	var was_muted := AudioServer.is_bus_mute(master_bus)
	AudioServer.set_bus_mute(master_bus, true)
	_expect(factory.get_impact_stream(ImpactFeedback.Tier.SMASH) != null, "Muted audio must still provide an impact stream", failures)
	AudioServer.set_bus_mute(master_bus, was_muted)

func _test_impact_burst(tree: SceneTree, failures: Array[String]) -> void:
	if not ResourceLoader.exists(BURST_SCENE_PATH):
		failures.append("Reusable impact burst scene must exist")
		return
	var scene: PackedScene = load(BURST_SCENE_PATH)
	if scene == null or not scene.can_instantiate():
		failures.append("Reusable impact burst scene must load")
		return
	var burst: Node3D = scene.instantiate()
	tree.root.add_child(burst)
	await tree.process_frame
	_expect(burst.has_method("play") and burst.has_method("reset_for_pool") and burst.has_signal("finished"), "Burst must support pooled playback", failures)
	_inspect_burst_node(burst, failures)
	if not burst.has_method("play") or not burst.has_method("reset_for_pool") or not burst.has_signal("finished"):
		burst.queue_free()
		return
	var recorder := BurstRecorder.new()
	burst.finished.connect(recorder.record)
	var feedback := ImpactFeedback.new()
	feedback.world_position = Vector3(3.0, 1.0, 2.0)
	feedback.direction = Vector3.RIGHT
	feedback.normalized_strength = 0.85
	feedback.tier = ImpactFeedback.Tier.SMASH
	var master_bus := AudioServer.get_bus_index("Master")
	var was_muted := AudioServer.is_bus_mute(master_bus)
	AudioServer.set_bus_mute(master_bus, true)
	burst.play(feedback)
	_expect(burst.visible and burst.global_position.is_equal_approx(feedback.world_position), "Playing a burst must show it at the impact position", failures)
	burst.reset_for_pool()
	AudioServer.set_bus_mute(master_bus, was_muted)
	_expect(not burst.visible and not _any_particles_emitting(burst), "Reset must leave the burst hidden and inactive", failures)
	await tree.create_timer(0.45).timeout
	_expect(recorder.count == 0, "Reset must cancel a pending finished signal", failures)
	burst.play(feedback)
	await tree.create_timer(0.05).timeout
	burst.play(feedback)
	await tree.create_timer(0.45).timeout
	_expect(recorder.count == 1, "Repeated play must finish exactly once after the latest effect", failures)
	_expect(not burst.visible and not _any_particles_emitting(burst), "Finished burst must be pool ready", failures)
	burst.queue_free()
	await tree.process_frame

func _inspect_burst_node(node: Node, failures: Array[String]) -> void:
	_expect(not node is CollisionObject3D, "Impact burst must not contain collision objects", failures)
	if node is GeometryInstance3D:
		_expect(node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Impact burst geometry must not cast shadows", failures)
	for child in node.get_children():
		_inspect_burst_node(child, failures)

func _any_particles_emitting(node: Node) -> bool:
	if node is CPUParticles3D and node.emitting:
		return true
	for child in node.get_children():
		if _any_particles_emitting(child):
			return true
	return false

func _test_resolved_light_contact(tree: SceneTree, failures: Array[String]) -> void:
	var controller = MATCH_CONTROLLER_SCRIPT.new()
	var player := CAR_SCENE.instantiate() as BumperCar
	var opponent := CAR_SCENE.instantiate() as BumperCar
	controller.set_physics_process(false)
	player.set_physics_process(false)
	opponent.set_physics_process(false)
	tree.root.add_child(controller)
	tree.root.add_child(player)
	tree.root.add_child(opponent)
	controller.set_physics_process(false)
	player.set_physics_process(false)
	opponent.set_physics_process(false)
	player.position = Vector3(-1.0, 0.0, 0.0)
	opponent.position = Vector3(1.0, 0.0, 0.0)
	await tree.process_frame
	controller.register_car(player, 1, true)
	controller.register_car(opponent, 2, false)
	var recorder := FeedbackRecorder.new()
	if controller.has_signal("impact_resolved"):
		controller.impact_resolved.connect(recorder.record)
	else:
		failures.append("MatchController is missing impact_resolved for the feel scope")
	player._capture_snapshot(400, Vector3(1.0, 0.0, 0.0))
	opponent._capture_snapshot(400, Vector3.ZERO)
	controller.report_contact(player, opponent, Vector3.RIGHT, Vector3.ZERO, 400)
	await tree.process_frame
	if recorder.values.size() == 1:
		var feedback := recorder.values[0]
		_expect(is_equal_approx(feedback.impulse_magnitude, 0.9) and is_equal_approx(feedback.normalized_strength, 0.9 / 14.0), "A real light separation must publish its applied impulse strength", failures)
		_expect(feedback.tier == ImpactFeedback.Tier.LIGHT, "A real light separation must classify as light", failures)
		_expect(not feedback.player_delivered and not feedback.player_received, "A non-effective separation must not claim an attack", failures)
	else:
		_expect(false, "A real non-effective contact must emit one impact_resolved", failures)
	_expect(opponent.external_velocity.is_equal_approx(Vector3(0.9, 0.0, 0.0)), "Light feedback must preserve actual knockback", failures)
	controller.queue_free()
	player.queue_free()
	opponent.queue_free()
	await tree.process_frame

func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
