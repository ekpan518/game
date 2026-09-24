extends RefCounted

func run(tree: SceneTree) -> Array[String]:
	await tree.process_frame
	var failures: Array[String] = []
	var command_script = load("res://scripts/bumper/drive_command.gd")
	var rules = load("res://scripts/bumper/bumper_rules.gd")
	_expect(command_script != null, "DriveCommand script must load", failures)
	_expect(rules != null, "BumperRules script must load", failures)
	if command_script == null or rules == null:
		return failures
	var command = command_script.create(2.0, -2.0)
	_expect(is_equal_approx(command.throttle, 1.0), "Throttle must clamp to 1", failures)
	_expect(is_equal_approx(command.steering, -1.0), "Steering must clamp to -1", failures)
	_expect(is_equal_approx(rules.outgoing_multiplier(3), 1.45), "Three stacks must deal 1.45x", failures)
	_expect(is_equal_approx(rules.incoming_multiplier(3), 0.76), "Three stacks must receive 0.76x", failures)
	_expect(rules.clamp_stacks(-3) == 0 and rules.clamp_stacks(9) == 3, "Stacks must clamp to 0 through 3", failures)
	_expect(rules.pair_key(9, 2) == rules.pair_key(2, 9), "Pair keys must be unordered", failures)
	var direct = rules.calculate_attack(Vector3(8, 0, 0), Vector3.ZERO, Vector3.RIGHT, 0, 0)
	_expect(direct.effective, "Fast direct approach must be effective", failures)
	_expect(direct.impulse.dot(Vector3.RIGHT) > 0.0, "Direct impulse must point toward defender", failures)
	var graze = rules.calculate_attack(Vector3(0, 0, 8), Vector3.ZERO, Vector3.RIGHT, 0, 0)
	_expect(not graze.effective, "Tangential motion must not be an effective attack", failures)
	_expect(graze.impulse.is_zero_approx(), "Tangential motion must not create directional knockback", failures)
	var below = rules.calculate_attack(Vector3(1.99, 0, 0), Vector3.ZERO, Vector3.RIGHT, 0, 0)
	_expect(not below.effective, "Approach below 2 m/s must not refresh credit", failures)
	var stationary = rules.calculate_attack(Vector3.ZERO, Vector3(8, 0, 0), Vector3.LEFT, 0, 0)
	_expect(not stationary.effective and stationary.impulse.is_zero_approx(), "A stationary defender must not become the attacker", failures)
	var zero_direction = rules.calculate_attack(Vector3(8, 0, 0), Vector3.ZERO, Vector3.ZERO, 0, 0)
	_expect(not zero_direction.effective and zero_direction.impulse.is_zero_approx(), "Zero direction must be safe", failures)
	var capped = rules.calculate_attack(Vector3(100, 0, 0), Vector3.ZERO, Vector3.RIGHT, 3, 0)
	_expect(capped.impulse.length() <= rules.MAX_KNOCKBACK_SPEED + 0.001, "Knockback must be capped", failures)
	return failures

func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
