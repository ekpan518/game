extends RefCounted

const FEEDBACK_SCRIPT = preload("res://scripts/bumper/impact_feedback.gd")
const FEEDBACK_RULES_SCRIPT = preload("res://scripts/bumper/impact_feedback_rules.gd")
const MATCH_CONTROLLER_SCRIPT = preload("res://scripts/game/match_controller.gd")
const CAR_SCENE = preload("res://scenes/vehicles/bumper_car.tscn")
const SOUND_FACTORY_PATH = "res://scripts/audio/arcade_sound_factory.gd"
const BURST_SCENE_PATH = "res://scenes/effects/impact_burst.tscn"

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
	return failures

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
