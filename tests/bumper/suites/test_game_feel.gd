extends RefCounted

const FEEDBACK_SCRIPT = preload("res://scripts/bumper/impact_feedback.gd")
const FEEDBACK_RULES_SCRIPT = preload("res://scripts/bumper/impact_feedback_rules.gd")

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
	return failures

func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
