extends RefCounted

const MATCH_STATE_SCRIPT = preload("res://scripts/game/match_state.gd")
const MATCH_CONTROLLER_SCRIPT = preload("res://scripts/game/match_controller.gd")
const DEATH_ZONE_SCRIPT = preload("res://scripts/game/death_zone.gd")
const CAR_SCENE = preload("res://scenes/vehicles/bumper_car.tscn")
const HUD_SCENE = preload("res://scenes/ui/match_hud.tscn")

class SignalRecorder:
	extends RefCounted

	var values: Array = []

	func record() -> void:
		values.append(true)

	func record_one(value: Variant) -> void:
		values.append(value)

	func record_two(first: Variant, second: Variant) -> void:
		values.append([first, second])

class RestartProbe:
	extends RefCounted

	var target: Variant
	var calls := 0
	var reentrant_results: Array[bool] = []

	func on_restart() -> void:
		calls += 1
		reentrant_results.append(target.request_restart())

class SynchronousDetachProbe:
	extends RefCounted

	var target: Node
	var calls := 0

	func on_restart() -> void:
		calls += 1
		if is_instance_valid(target) and target.get_parent() != null:
			target.get_parent().remove_child(target)

class MatchResultProbe:
	extends RefCounted

	var survivor: BumperCar
	var values: Array[StringName] = []
	var survivor_rejected_knockback: Array[bool] = []

	func record_result(result: StringName) -> void:
		values.append(result)
		survivor.apply_knockback(Vector3.RIGHT)
		survivor_rejected_knockback.append(survivor.external_velocity.is_zero_approx())

class BatchEventProbe:
	extends RefCounted

	var batches: Array = []
	var order: Array[String] = []

	func record_batch(batch: EliminationBatchResult) -> void:
		batches.append(batch)
		order.append("batch")

	func record_result(_result: StringName) -> void:
		order.append("result")

func run(tree: SceneTree) -> Array[String]:
	await tree.process_frame
	var failures: Array[String] = []
	_test_match_state_boundaries(failures)
	_test_match_state_batch_rules(failures)
	_test_match_state_results_and_ties(failures)
	await _test_controller_registration_and_queries(tree, failures)
	await _test_controller_contact_deduplication(tree, failures)
	await _test_controller_contact_edge_cases(tree, failures)
	await _test_controller_dominant_impact(tree, failures)
	await _test_controller_invalid_contact_events(tree, failures)
	await _test_controller_contact_before_death(tree, failures)
	await _test_controller_simultaneous_final_deaths(tree, failures)
	await _test_controller_runtime_clock_expiry(tree, failures)
	await _test_controller_fall_fallback(tree, failures)
	await _test_controller_restart_gate(tree, failures)
	await _test_death_zone(tree, failures)
	await _test_hud(tree, failures)
	return failures

func _test_match_state_boundaries(failures: Array[String]) -> void:
	var state = MATCH_STATE_SCRIPT.new()
	state.register_car(1, true)
	state.register_car(2, false)
	state.register_car(3, false)
	state.register_car(4, false)
	state.record_attack(1, 2, 1.0)
	var victims: Array[int] = [2]
	var boundary = state.resolve_eliminations(victims, 5.0)
	_expect(boundary.accepted_any, "A first live registered victim must be accepted", failures)
	_expect(boundary.killers_by_victim.get(2, -1) == 1, "Exactly four seconds must retain kill credit", failures)
	_expect(state.get_power_stacks(1) == 1, "Living killer must gain one stack", failures)
	_expect(not state.resolve_eliminations(victims, 5.1).accepted_any, "Repeated death must be ignored", failures)

	var expired = MATCH_STATE_SCRIPT.new()
	expired.register_car(1, true)
	expired.register_car(2, false)
	expired.register_car(3, false)
	expired.record_attack(1, 2, 1.0)
	var expired_result = expired.resolve_eliminations(victims, 5.001)
	_expect(expired_result.killers_by_victim.get(2, -1) == -1, "A hit aged 4.001 seconds must not retain kill credit", failures)
	_expect(expired.get_power_stacks(1) == 0, "Expired credit must not grant power", failures)

	var future = MATCH_STATE_SCRIPT.new()
	future.register_car(1, true)
	future.register_car(2, false)
	future.record_attack(1, 2, 5.0)
	var future_result = future.resolve_eliminations(victims, 4.0)
	_expect(future_result.killers_by_victim.get(2, -1) == -1, "A future-dated hit must not receive kill credit", failures)

func _test_match_state_batch_rules(failures: Array[String]) -> void:
	var multi = MATCH_STATE_SCRIPT.new()
	for stable_id in range(1, 6):
		multi.register_car(stable_id, stable_id == 1)
	for victim_id in [2, 3, 4, 5]:
		multi.record_attack(1, victim_id, 1.0)
	var multi_victims: Array[int] = [2, 3, 2, 4]
	var multi_result = multi.resolve_eliminations(multi_victims, 2.0)
	_expect(multi_result.eliminated_ids == [2, 3, 4], "A batch must deduplicate each victim deterministically", failures)
	_expect(multi.get_power_stacks(1) == 3, "One living killer may gain one layer per victim up to three", failures)
	_expect(multi_result.buffed_killer_ids == [1], "A multi-kill must list its buffed killer only once", failures)
	var final_victim: Array[int] = [5]
	var capped_result = multi.resolve_eliminations(final_victim, 2.0)
	_expect(multi.get_power_stacks(1) == 3, "Power must remain capped at three", failures)
	_expect(capped_result.buffed_killer_ids.is_empty(), "A capped killer must not be listed when power did not change", failures)

	var dead_killer = MATCH_STATE_SCRIPT.new()
	dead_killer.register_car(1, true)
	dead_killer.register_car(2, false)
	dead_killer.record_attack(1, 2, 1.0)
	var same_batch: Array[int] = [2, 1]
	var dead_killer_result = dead_killer.resolve_eliminations(same_batch, 2.0)
	_expect(dead_killer_result.killers_by_victim.get(2, -1) == 1, "A same-batch dead killer must retain attribution", failures)
	_expect(dead_killer.get_power_stacks(1) == 0 and dead_killer_result.buffed_killer_ids.is_empty(), "A same-batch dead killer must receive no usable power", failures)

	var previously_dead_killer = MATCH_STATE_SCRIPT.new()
	previously_dead_killer.register_car(1, true)
	previously_dead_killer.register_car(2, false)
	previously_dead_killer.register_car(3, false)
	previously_dead_killer.record_attack(2, 3, 1.0)
	var earlier_killer_death: Array[int] = [2]
	previously_dead_killer.resolve_eliminations(earlier_killer_death, 1.5)
	var later_victim_death: Array[int] = [3]
	var previously_dead_result = previously_dead_killer.resolve_eliminations(later_victim_death, 2.0)
	_expect(previously_dead_result.killers_by_victim.get(3, -1) == 2, "A recently attacking killer dead from an earlier batch must retain attribution", failures)
	_expect(previously_dead_killer.get_power_stacks(2) == 0 and previously_dead_result.buffed_killer_ids.is_empty(), "A killer dead from an earlier batch must receive no usable power", failures)

	var unknown_only: Array[int] = [88, 99, 88]
	var unknown_result = dead_killer.resolve_eliminations(unknown_only, 3.0)
	_expect(not unknown_result.accepted_any and unknown_result.eliminated_ids.is_empty(), "An unknown-only batch must be rejected", failures)

func _test_match_state_results_and_ties(failures: Array[String]) -> void:
	for reverse_hits in [false, true]:
		var tied = MATCH_STATE_SCRIPT.new()
		for stable_id in range(1, 5):
			tied.register_car(stable_id, stable_id == 1)
		if reverse_hits:
			tied.record_attack(2, 4, 1.0)
			tied.record_attack(3, 4, 1.0)
		else:
			tied.record_attack(3, 4, 1.0)
			tied.record_attack(2, 4, 1.0)
		var tied_victim: Array[int] = [4]
		var tied_result = tied.resolve_eliminations(tied_victim, 2.0)
		_expect(tied_result.killers_by_victim.get(4, -1) == 2, "Equal-time hits must choose the lower attacker stable ID", failures)

	for order in [[2, 1], [1, 2]]:
		var simultaneous = MATCH_STATE_SCRIPT.new()
		simultaneous.register_car(1, true)
		simultaneous.register_car(2, false)
		var ordered_victims: Array[int] = []
		ordered_victims.assign(order)
		var simultaneous_result = simultaneous.resolve_eliminations(ordered_victims, 1.0)
		_expect(simultaneous_result.result == &"defeat", "Player death in a simultaneous final batch must always be defeat", failures)

	var progression = MATCH_STATE_SCRIPT.new()
	progression.register_car(1, true)
	progression.register_car(2, false)
	progression.register_car(3, false)
	var first_ai: Array[int] = [2]
	var last_ai: Array[int] = [3]
	_expect(progression.resolve_eliminations(first_ai, 1.0).result == &"playing", "A player with another live opponent must remain playing", failures)
	_expect(progression.resolve_eliminations(last_ai, 2.0).result == &"victory", "Only a sole surviving player may win", failures)

func _test_controller_registration_and_queries(tree: SceneTree, failures: Array[String]) -> void:
	var controller = MATCH_CONTROLLER_SCRIPT.new()
	controller.set_physics_process(false)
	var player := _new_car(Vector3.ZERO)
	var low_ai := _new_car(Vector3(2.0, 0.0, 0.0))
	var high_ai := _new_car(Vector3(4.0, 0.0, 0.0))
	var unknown := _new_car(Vector3(6.0, 0.0, 0.0))
	tree.root.add_child(controller)
	for car in [player, low_ai, high_ai, unknown]:
		tree.root.add_child(car)
	await tree.process_frame
	var alive_events := SignalRecorder.new()
	var power_events := SignalRecorder.new()
	controller.alive_count_changed.connect(alive_events.record_two)
	controller.player_power_changed.connect(power_events.record_one)

	controller.register_car(null, 1, true)
	controller.register_car(player, 0, true)
	controller.register_car(player, 2, true)
	controller.register_car(player, 2, true)
	controller.register_car(player, 9, true)
	controller.register_car(low_ai, 2, false)
	controller.register_car(low_ai, 1, false)
	controller.register_car(high_ai, 3, false)
	_expect(alive_events.values == [[1, 1], [2, 2], [3, 3]], "Only successful registrations must emit current alive totals", failures)
	_expect(power_events.values == [0], "The first player registration must emit power zero exactly once", failures)
	_expect(player.contact_reported.get_connections().size() == 1, "Repeated registration must connect contact_reported exactly once", failures)
	var opponents: Array[BumperCar] = controller.get_live_opponents_for(player)
	_expect(opponents == [low_ai, high_ai], "Live opponents must be sorted by stable ID", failures)
	_expect(controller.get_live_opponents_for(unknown).is_empty(), "An unknown requester must receive no opponents", failures)

	_expect(controller.queue_elimination(low_ai), "The first same-frame elimination queue must be accepted", failures)
	_expect(not controller.queue_elimination(low_ai), "A duplicate same-frame elimination queue must be rejected", failures)
	_expect(not controller.queue_elimination(unknown), "An unregistered car must not enter the elimination queue", failures)
	await tree.process_frame
	_expect(not controller.queue_elimination(low_ai), "An already dead car must not be queued again", failures)
	opponents = controller.get_live_opponents_for(player)
	_expect(opponents == [high_ai], "Dead cars must be filtered from live opponents", failures)
	var high_ai_ref: WeakRef = weakref(high_ai)
	high_ai.queue_free()
	await tree.process_frame
	_expect(controller.get_live_opponents_for(player).is_empty(), "Freed cars must be filtered from live opponents", failures)
	var freed_requester: BumperCar = high_ai_ref.get_ref() as BumperCar
	var freed_requester_opponents: Array[BumperCar] = controller.get_live_opponents_for(freed_requester)
	_expect(freed_requester_opponents.is_empty(), "A freed registered requester must receive no opponents", failures)
	_expect(controller.queue_elimination(player), "A live player must still be queueable", failures)
	await tree.process_frame
	_expect(controller.get_live_opponents_for(player).is_empty(), "A dead requester must receive no opponents", failures)
	await _free_nodes(tree, [controller, player, low_ai, unknown])

func _test_controller_contact_deduplication(tree: SceneTree, failures: Array[String]) -> void:
	var setup := await _make_two_car_match(tree, Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	var controller = setup[0]
	var car_a: BumperCar = setup[1]
	var car_b: BumperCar = setup[2]
	var impacts := SignalRecorder.new()
	if controller.has_signal("impact_resolved"):
		controller.impact_resolved.connect(impacts.record_one)
	else:
		failures.append("MatchController is missing impact_resolved")
	car_a._capture_snapshot(100, Vector3(8.0, 0.0, 0.0))
	car_b._capture_snapshot(100, Vector3.ZERO)
	controller.report_contact(car_a, car_b, Vector3.LEFT, Vector3(-100.0, 0.0, 0.0), 100)
	controller.report_contact(car_b, car_a, Vector3.LEFT, Vector3(100.0, 0.0, 0.0), 100)
	await tree.process_frame
	_expect(car_a.external_velocity.is_zero_approx(), "A stationary defender must not knock back the attacker", failures)
	_expect(car_b.external_velocity.is_equal_approx(Vector3(7.2, 0.0, 0.0)), "Reversed reports in one frame must apply one canonical knockback", failures)
	if impacts.values.size() == 1:
		var feedback: ImpactFeedback = impacts.values[0]
		_expect(feedback.stable_a == 1 and feedback.stable_b == 2, "One canonical event must identify the stable pair", failures)
		_expect(feedback.world_position.is_equal_approx(Vector3.ZERO), "Impact event must use the car midpoint", failures)
		_expect(feedback.direction.is_equal_approx(Vector3.RIGHT), "Dominant A attack must point from A to B", failures)
		_expect(is_equal_approx(feedback.impulse_magnitude, 7.2), "Impact event must use the applied impulse magnitude", failures)
		_expect(is_equal_approx(feedback.normalized_strength, 7.2 / 14.0), "Impact strength must normalize the applied impulse", failures)
		_expect(feedback.tier == ImpactFeedback.Tier.HEAVY, "A 7.2 impulse must classify as heavy", failures)
		_expect(feedback.player_delivered and not feedback.player_received, "A player attack must mark delivery only", failures)
	else:
		_expect(false, "Two reporters must produce exactly one impact_resolved event", failures)
	car_a._capture_snapshot(101, Vector3(8.0, 0.0, 0.0))
	car_b._capture_snapshot(101, Vector3.ZERO)
	controller.report_contact(car_b, car_a, Vector3.LEFT, Vector3.ZERO, 101)
	await tree.process_frame
	_expect(car_b.external_velocity.is_equal_approx(Vector3(14.4, 0.0, 0.0)), "The same pair must be eligible again on the next physics frame", failures)
	_expect(impacts.values.size() == 2, "A new physics frame must produce one new impact_resolved event", failures)
	await _free_nodes(tree, setup)

func _test_controller_invalid_contact_events(tree: SceneTree, failures: Array[String]) -> void:
	var setup := await _make_two_car_match(tree, Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	var controller = setup[0]
	var player: BumperCar = setup[1]
	var opponent: BumperCar = setup[2]
	var unknown := _new_car(Vector3(3.0, 0.0, 0.0))
	var survivor := _new_car(Vector3(5.0, 0.0, 0.0))
	tree.root.add_child(unknown)
	tree.root.add_child(survivor)
	await tree.process_frame
	controller.register_car(survivor, 3, false)
	var impacts := SignalRecorder.new()
	if controller.has_signal("impact_resolved"):
		controller.impact_resolved.connect(impacts.record_one)
	else:
		failures.append("MatchController is missing impact_resolved for invalid-contact checks")
	player._capture_snapshot(300, Vector3(8.0, 0.0, 0.0))
	opponent._capture_snapshot(300, Vector3.ZERO)
	unknown._capture_snapshot(300, Vector3.ZERO)
	controller.report_contact(player, unknown, Vector3.RIGHT, Vector3.ZERO, 300)
	controller.report_contact(null, opponent, Vector3.RIGHT, Vector3.ZERO, 300)
	controller.report_contact(player, player, Vector3.RIGHT, Vector3.ZERO, 300)
	await tree.process_frame
	_expect(impacts.values.is_empty(), "Invalid and unregistered contact reports must emit no impact_resolved", failures)
	_expect(controller.queue_elimination(opponent), "Opponent must be eliminable before dead-contact check", failures)
	await tree.process_frame
	_expect(not controller._match_ended, "Dead-contact check must run while the match is still active", failures)
	controller.report_contact(player, opponent, Vector3.RIGHT, Vector3.ZERO, 301)
	await tree.process_frame
	_expect(impacts.values.is_empty(), "A dead contact partner must emit no impact_resolved", failures)
	await _free_nodes(tree, setup + [unknown, survivor])

func _test_controller_dominant_impact(tree: SceneTree, failures: Array[String]) -> void:
	var setup := await _make_two_car_match(tree, Vector3(-2.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0))
	var controller = setup[0]
	var player: BumperCar = setup[1]
	var first_victim: BumperCar = setup[2]
	var opponent := _new_car(Vector3(2.0, 0.0, 0.0))
	tree.root.add_child(opponent)
	await tree.process_frame
	controller.register_car(opponent, 3, false)
	var impacts := SignalRecorder.new()
	if controller.has_signal("impact_resolved"):
		controller.impact_resolved.connect(impacts.record_one)
	else:
		failures.append("MatchController is missing impact_resolved for dominant-impulse checks")
	var first_frame := Engine.get_physics_frames()
	player._capture_snapshot(first_frame, Vector3(8.0, 0.0, 0.0))
	first_victim._capture_snapshot(first_frame, Vector3.ZERO)
	controller.report_contact(player, first_victim, Vector3.RIGHT, Vector3.ZERO, first_frame)
	controller.queue_elimination(first_victim)
	await tree.process_frame
	_expect(player.power_stacks == 1, "Credited first kill must give the player one stack for unequal impulses", failures)
	impacts.values.clear()
	var second_frame := Engine.get_physics_frames()
	player._capture_snapshot(second_frame, Vector3(8.0, 0.0, 0.0))
	opponent._capture_snapshot(second_frame, Vector3(-8.0, 0.0, 0.0))
	var expected_midpoint := (player.global_position + opponent.global_position) * 0.5
	controller.report_contact(opponent, player, Vector3.LEFT, Vector3.ZERO, second_frame)
	await tree.process_frame
	if impacts.values.size() == 1:
		var feedback: ImpactFeedback = impacts.values[0]
		_expect(feedback.stable_a == 1 and feedback.stable_b == 3, "Dominant impact must retain ordered stable IDs", failures)
		_expect(feedback.world_position.is_equal_approx(expected_midpoint), "Dominant impact must use the current pair midpoint", failures)
		_expect(feedback.direction.is_equal_approx(Vector3.RIGHT), "Stronger player impulse must determine the presentation direction", failures)
		_expect(is_equal_approx(feedback.impulse_magnitude, 14.0) and is_equal_approx(feedback.normalized_strength, 1.0), "Unequal impulses must publish the larger applied magnitude and full strength", failures)
		_expect(feedback.tier == ImpactFeedback.Tier.SMASH, "The stronger capped impulse must classify as smash", failures)
		_expect(feedback.player_delivered and feedback.player_received, "Both effective attackers must mark player delivery and receipt", failures)
	else:
		_expect(false, "Unequal mutual attacks must publish one impact_resolved", failures)
	await _free_nodes(tree, setup + [opponent])

func _test_controller_contact_edge_cases(tree: SceneTree, failures: Array[String]) -> void:
	var missing := await _make_two_car_match(tree, Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	var missing_controller = missing[0]
	var missing_a: BumperCar = missing[1]
	var missing_b: BumperCar = missing[2]
	missing_a._capture_snapshot(200, Vector3(8.0, 0.0, 0.0))
	missing_a._combat_velocity = Vector3(8.0, 0.0, 0.0)
	missing_b._combat_velocity = Vector3.ZERO
	missing_controller.report_contact(missing_a, missing_b, Vector3.RIGHT, Vector3(8.0, 0.0, 0.0), 200)
	await tree.process_frame
	_expect(missing_b.external_velocity.is_zero_approx(), "A pair missing either exact-frame snapshot must be discarded", failures)
	await _free_nodes(tree, missing)

	var coincident := await _make_two_car_match(tree, Vector3.ZERO, Vector3.ZERO)
	var coincident_controller = coincident[0]
	var coincident_a: BumperCar = coincident[1]
	var coincident_b: BumperCar = coincident[2]
	coincident_a._capture_snapshot(210, Vector3(8.0, 0.0, 0.0))
	coincident_b._capture_snapshot(210, Vector3.ZERO)
	coincident_controller.report_contact(coincident_b, coincident_a, Vector3.LEFT, Vector3.ZERO, 210)
	await tree.process_frame
	_expect(coincident_b.external_velocity.x > 7.0, "A high-ID reporter fallback normal must be inverted to canonical A-to-B", failures)
	coincident_b.external_velocity = Vector3.ZERO
	coincident_a._capture_snapshot(211, Vector3(8.0, 0.0, 0.0))
	coincident_b._capture_snapshot(211, Vector3.ZERO)
	coincident_controller.report_contact(coincident_a, coincident_b, Vector3.ZERO, Vector3(8.0, 0.0, 0.0), 211)
	await tree.process_frame
	_expect(coincident_b.external_velocity.is_zero_approx(), "A coincident pair with a zero fallback normal must be discarded", failures)
	await _free_nodes(tree, coincident)

	var bilateral := await _make_two_car_match(tree, Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	var bilateral_controller = bilateral[0]
	var bilateral_a: BumperCar = bilateral[1]
	var bilateral_b: BumperCar = bilateral[2]
	var bilateral_impacts := SignalRecorder.new()
	if bilateral_controller.has_signal("impact_resolved"):
		bilateral_controller.impact_resolved.connect(bilateral_impacts.record_one)
	bilateral_a._capture_snapshot(220, Vector3(8.0, 0.0, 0.0))
	bilateral_b._capture_snapshot(220, Vector3(-8.0, 0.0, 0.0))
	bilateral_controller.report_contact(bilateral_a, bilateral_b, Vector3.RIGHT, Vector3.ZERO, 220)
	await tree.process_frame
	_expect(bilateral_a.external_velocity.x < -13.9 and bilateral_b.external_velocity.x > 13.9, "Both directional attacks must be calculated and applied for a head-on collision", failures)
	if bilateral_impacts.values.size() == 1:
		var feedback: ImpactFeedback = bilateral_impacts.values[0]
		_expect(feedback.player_delivered and feedback.player_received, "Mutual effective attacks must mark both player roles", failures)
		_expect(is_equal_approx(feedback.impulse_magnitude, 14.0), "Mutual impacts must publish the larger capped applied impulse", failures)
	else:
		_expect(false, "A mutual collision must produce one impact_resolved event", failures)
	await _free_nodes(tree, bilateral)

	var received := await _make_two_car_match(tree, Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	var received_controller = received[0]
	var received_player: BumperCar = received[1]
	var received_opponent: BumperCar = received[2]
	var received_impacts := SignalRecorder.new()
	if received_controller.has_signal("impact_resolved"):
		received_controller.impact_resolved.connect(received_impacts.record_one)
	received_player._capture_snapshot(225, Vector3.ZERO)
	received_opponent._capture_snapshot(225, Vector3(-8.0, 0.0, 0.0))
	received_controller.report_contact(received_opponent, received_player, Vector3.LEFT, Vector3.ZERO, 225)
	await tree.process_frame
	if received_impacts.values.size() == 1:
		var feedback: ImpactFeedback = received_impacts.values[0]
		_expect(feedback.direction.is_equal_approx(Vector3.LEFT), "An AI-only hit must point toward the player", failures)
		_expect(not feedback.player_delivered and feedback.player_received, "An AI-only hit must mark player receipt only", failures)
	else:
		_expect(false, "An AI-only hit must publish one impact_resolved", failures)
	await _free_nodes(tree, received)

	var separation := await _make_two_car_match(tree, Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	var separation_controller = separation[0]
	var separation_a: BumperCar = separation[1]
	var separation_b: BumperCar = separation[2]
	separation_a._capture_snapshot(230, Vector3(1.0, 0.0, 0.0))
	separation_b._capture_snapshot(230, Vector3.ZERO)
	separation_controller.report_contact(separation_a, separation_b, Vector3.RIGHT, Vector3.ZERO, 230)
	await tree.process_frame
	_expect(separation_b.external_velocity.is_equal_approx(Vector3(0.9, 0.0, 0.0)), "A non-effective contact must still apply its nonzero separation impulse", failures)
	_expect(separation_controller.queue_elimination(separation_b), "The separated defender must remain eliminable", failures)
	await tree.process_frame
	_expect(separation_a.power_stacks == 0, "A non-effective separation impulse must not create kill credit", failures)
	await _free_nodes(tree, separation)

	var tangential := await _make_two_car_match(tree, Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	var tangential_controller = tangential[0]
	var tangential_a: BumperCar = tangential[1]
	var tangential_b: BumperCar = tangential[2]
	tangential_a._capture_snapshot(240, Vector3(8.0, 0.0, 0.0))
	tangential_b._capture_snapshot(240, Vector3.ZERO)
	tangential_controller.report_contact(tangential_a, tangential_b, Vector3.RIGHT, Vector3.ZERO, 240)
	await tree.process_frame
	tangential_controller.advance_match_time(4.001)
	tangential_a._capture_snapshot(241, Vector3(0.0, 0.0, 8.0))
	tangential_b._capture_snapshot(241, Vector3.ZERO)
	tangential_controller.report_contact(tangential_a, tangential_b, Vector3.RIGHT, Vector3.ZERO, 241)
	await tree.process_frame
	_expect(tangential_controller.queue_elimination(tangential_b), "The tangentially contacted defender must remain eliminable", failures)
	await tree.process_frame
	_expect(tangential_a.power_stacks == 0, "A tangential contact must not refresh expired kill credit", failures)
	await _free_nodes(tree, tangential)

func _test_controller_contact_before_death(tree: SceneTree, failures: Array[String]) -> void:
	var setup := await _make_two_car_match(tree, Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	var controller = setup[0]
	var player: BumperCar = setup[1]
	var victim: BumperCar = setup[2]
	var alive_events := SignalRecorder.new()
	var power_events := SignalRecorder.new()
	var result_probe := MatchResultProbe.new()
	var batch_probe := BatchEventProbe.new()
	result_probe.survivor = player
	controller.alive_count_changed.connect(alive_events.record_two)
	controller.player_power_changed.connect(power_events.record_one)
	controller.match_ended.connect(result_probe.record_result)
	controller.match_ended.connect(batch_probe.record_result)
	if controller.has_signal("eliminations_resolved"):
		controller.eliminations_resolved.connect(batch_probe.record_batch)
	else:
		failures.append("MatchController is missing eliminations_resolved")
	var physics_frame := Engine.get_physics_frames()
	player._capture_snapshot(physics_frame, Vector3(8.0, 0.0, 0.0))
	victim._capture_snapshot(physics_frame, Vector3.ZERO)
	controller.report_contact(player, victim, Vector3.RIGHT, Vector3(8.0, 0.0, 0.0), physics_frame)
	_expect(controller.queue_elimination(victim), "A same-frame contacted victim must enter the death batch", failures)
	await tree.process_frame
	_expect(not victim.alive and player.power_stacks == 1, "Deferred drain must resolve same-frame contacts before deaths", failures)
	_expect(alive_events.values == [[1, 2]], "A final opponent death must emit the final alive-count payload", failures)
	_expect(power_events.values == [1], "A credited final player kill must emit the new player power", failures)
	_expect(result_probe.values == [&"victory"], "Eliminating the final opponent must emit victory exactly once", failures)
	_expect(result_probe.survivor_rejected_knockback == [true], "The survivor must already reject knockback when match_ended listeners run", failures)
	if batch_probe.batches.size() == 1:
		var batch: EliminationBatchResult = batch_probe.batches[0]
		_expect(batch.eliminated_ids == [2] and batch.killers_by_victim == {2: 1}, "Elimination event must preserve the credited victim and killer", failures)
		_expect(batch.buffed_killer_ids == [1] and batch.result == &"victory", "Elimination event must preserve the applied buff and victory", failures)
	else:
		_expect(false, "One accepted death must emit one eliminations_resolved batch", failures)
	_expect(batch_probe.order == ["batch", "result"], "Elimination batch must be available before match_ended", failures)
	await _free_nodes(tree, setup)

func _test_controller_simultaneous_final_deaths(tree: SceneTree, failures: Array[String]) -> void:
	for player_first in [true, false]:
		var setup := await _make_two_car_match(tree, Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
		var controller = setup[0]
		var player: BumperCar = setup[1]
		var opponent: BumperCar = setup[2]
		var alive_events := SignalRecorder.new()
		var result_events := SignalRecorder.new()
		var batch_probe := BatchEventProbe.new()
		controller.alive_count_changed.connect(alive_events.record_two)
		controller.match_ended.connect(result_events.record_one)
		if controller.has_signal("eliminations_resolved"):
			controller.eliminations_resolved.connect(batch_probe.record_batch)
		else:
			failures.append("MatchController is missing eliminations_resolved for simultaneous deaths")
		var first: BumperCar = player if player_first else opponent
		var second: BumperCar = opponent if player_first else player
		_expect(controller.queue_elimination(first), "The first simultaneous final death must be queued", failures)
		_expect(controller.queue_elimination(second), "The second simultaneous final death must be queued", failures)
		await tree.process_frame
		_expect(not player.alive and not opponent.alive, "Both same-frame final deaths must resolve atomically", failures)
		_expect(alive_events.values == [[0, 2]], "Either final-death queue order must emit one zero-alive payload", failures)
		_expect(result_events.values == [&"defeat"], "Either final-death queue order must emit defeat exactly once", failures)
		if batch_probe.batches.size() == 1:
			var batch: EliminationBatchResult = batch_probe.batches[0]
			_expect(batch.eliminated_ids == [1, 2] and batch.killers_by_victim.is_empty(), "Simultaneous final-death event must preserve both victims without invented credit", failures)
			_expect(batch.buffed_killer_ids.is_empty() and batch.result == &"defeat", "Simultaneous player death must publish defeat without buffs", failures)
		else:
			_expect(false, "Simultaneous final deaths must emit one eliminations_resolved batch", failures)
		await _free_nodes(tree, setup)

func _test_controller_runtime_clock_expiry(tree: SceneTree, failures: Array[String]) -> void:
	var setup := await _make_two_car_match(tree, Vector3(-1.0, 1.0, 0.0), Vector3(1.0, 1.0, 0.0))
	var controller = setup[0]
	var player: BumperCar = setup[1]
	var victim: BumperCar = setup[2]
	var physics_frame := Engine.get_physics_frames()
	player._capture_snapshot(physics_frame, Vector3(8.0, 0.0, 0.0))
	victim._capture_snapshot(physics_frame, Vector3.ZERO)
	controller.report_contact(player, victim, Vector3.RIGHT, Vector3.ZERO, physics_frame)
	await tree.process_frame
	controller._physics_process(4.001)
	_expect(player.alive and victim.alive, "The runtime clock path must not eliminate cars above the fall threshold", failures)
	_expect(controller.queue_elimination(victim), "The clock-aged victim must remain eliminable", failures)
	await tree.process_frame
	_expect(player.power_stacks == 0, "The production physics clock must expire kill credit after 4.001 seconds", failures)
	await _free_nodes(tree, setup)

func _test_controller_fall_fallback(tree: SceneTree, failures: Array[String]) -> void:
	var setup := await _make_two_car_match(tree, Vector3.ZERO, Vector3(2.0, -12.0, 0.0))
	var controller = setup[0]
	var falling: BumperCar = setup[2]
	controller._physics_process(0.0)
	await tree.process_frame
	_expect(falling.alive, "The fallback must not eliminate a car exactly at y = -12", failures)
	falling.position.y = -12.001
	controller._physics_process(0.25)
	await tree.process_frame
	_expect(not falling.alive, "The fallback must eliminate a live car strictly below y = -12", failures)
	await _free_nodes(tree, setup)

func _test_controller_restart_gate(tree: SceneTree, failures: Array[String]) -> void:
	var ongoing_setup := await _make_two_car_match(tree, Vector3.ZERO, Vector3.RIGHT * 2.0)
	var ongoing_controller = ongoing_setup[0]
	var ongoing_restart_events := SignalRecorder.new()
	ongoing_controller.restart_accepted.connect(ongoing_restart_events.record)
	_expect(not ongoing_controller.request_restart(), "Controller direct restart must be rejected while the match is still playing", failures)
	_expect(ongoing_restart_events.values.is_empty(), "Rejected in-progress controller restart must not emit restart_accepted", failures)
	await _free_nodes(tree, ongoing_setup)

	var ended_setup := await _make_two_car_match(tree, Vector3.ZERO, Vector3.RIGHT * 2.0)
	var ended_controller = ended_setup[0]
	var opponent: BumperCar = ended_setup[2]
	_expect(ended_controller.queue_elimination(opponent), "A public elimination must be accepted before testing post-match restart", failures)
	await tree.process_frame
	var restart_probe := RestartProbe.new()
	restart_probe.target = ended_controller
	ended_controller.restart_accepted.connect(restart_probe.on_restart)
	_expect(ended_controller.request_restart(), "The controller must accept its first restart request after a real match end", failures)
	_expect(restart_probe.calls == 1 and restart_probe.reentrant_results == [false], "Controller restart latch must be set before emitting", failures)
	_expect(not ended_controller.request_restart() and restart_probe.calls == 1, "Controller restart acceptance must be idempotent", failures)
	await _free_nodes(tree, ended_setup)

func _test_death_zone(tree: SceneTree, failures: Array[String]) -> void:
	var zone = DEATH_ZONE_SCRIPT.new()
	var car := _new_car(Vector3.ZERO)
	var non_car := CharacterBody3D.new()
	var events := SignalRecorder.new()
	zone.car_entered_death_zone.connect(events.record_one)
	tree.root.add_child(zone)
	tree.root.add_child(car)
	tree.root.add_child(non_car)
	await tree.process_frame
	zone.body_entered.emit(car)
	zone.body_entered.emit(non_car)
	_expect(events.values == [car], "DeathZone must emit only for BumperCar bodies", failures)
	_expect(car.alive and car.visible, "DeathZone must never mutate car state directly", failures)
	await _free_nodes(tree, [zone, car, non_car])

func _test_hud(tree: SceneTree, failures: Array[String]) -> void:
	var hud = HUD_SCENE.instantiate()
	tree.root.add_child(hud)
	await tree.process_frame
	var alive_label := hud.find_child("AliveLabel", true, false) as Label
	var power_label := hud.find_child("PowerLabel", true, false) as Label
	var result_panel := hud.find_child("ResultPanel", true, false) as Control
	_expect(alive_label != null and alive_label.text == "剩余车辆：4/4", "HUD must start with the four-car alive copy", failures)
	_expect(power_label != null and power_label.text == "强化：0/3", "HUD must start with zero power copy", failures)
	_expect(result_panel != null and not result_panel.visible, "HUD result panel must start hidden", failures)
	hud.set_alive_count(2, 4)
	hud.set_power_stacks(2)
	_expect(alive_label != null and alive_label.text == "剩余车辆：2/4", "HUD must render alive updates", failures)
	_expect(power_label != null and power_label.text == "强化：2/3", "HUD must render power updates", failures)
	var ongoing_direct_events := SignalRecorder.new()
	hud.restart_requested.connect(ongoing_direct_events.record)
	_expect(not hud.request_restart(), "HUD direct restart must be rejected while the result panel is hidden", failures)
	_expect(ongoing_direct_events.values.is_empty(), "Rejected in-progress HUD direct restart must not emit restart_requested", failures)
	hud.queue_free()
	await tree.process_frame

	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	enter.echo = false
	var ongoing_enter_hud = HUD_SCENE.instantiate()
	tree.root.add_child(ongoing_enter_hud)
	await tree.process_frame
	var ongoing_enter_events := SignalRecorder.new()
	ongoing_enter_hud.restart_requested.connect(ongoing_enter_events.record)
	ongoing_enter_hud._unhandled_input(enter)
	_expect(ongoing_enter_events.values.is_empty(), "Enter must not request restart while the result panel is hidden", failures)
	ongoing_enter_hud.queue_free()
	await tree.process_frame

	var button_hud = HUD_SCENE.instantiate()
	tree.root.add_child(button_hud)
	await tree.process_frame
	button_hud.show_result(&"victory")
	var button_result_panel := button_hud.find_child("ResultPanel", true, false) as Control
	var button_result_label := button_hud.find_child("ResultLabel", true, false) as Label
	_expect(button_result_panel != null and button_result_panel.visible and button_result_label != null and button_result_label.text == "胜利！", "HUD must show Chinese victory copy", failures)
	var button_probe := RestartProbe.new()
	button_probe.target = button_hud
	button_hud.restart_requested.connect(button_probe.on_restart)
	var restart_button := button_hud.find_child("RestartButton", true, false) as Button
	restart_button.pressed.emit()
	_expect(button_probe.calls == 1 and button_probe.reentrant_results == [false], "Visible HUD restart button must accept once and reject signal re-entry", failures)
	restart_button.pressed.emit()
	button_hud._unhandled_input(enter)
	_expect(not button_hud.request_restart() and button_probe.calls == 1, "Visible HUD button, Enter, and direct restart must share one latch", failures)
	button_hud.queue_free()
	await tree.process_frame

	var enter_hud = HUD_SCENE.instantiate()
	tree.root.add_child(enter_hud)
	await tree.process_frame
	enter_hud.show_result(&"defeat")
	var enter_result_label := enter_hud.find_child("ResultLabel", true, false) as Label
	_expect(enter_result_label != null and enter_result_label.text == "失败", "HUD must show Chinese defeat copy", failures)
	var enter_probe := RestartProbe.new()
	enter_probe.target = enter_hud
	enter_hud.restart_requested.connect(enter_probe.on_restart)
	enter_hud._unhandled_input(enter)
	_expect(enter_probe.calls == 1 and enter_probe.reentrant_results == [false], "Visible HUD Enter must accept once and reject signal re-entry", failures)
	enter_hud._unhandled_input(enter)
	_expect(not enter_hud.request_restart() and enter_probe.calls == 1, "Repeated visible HUD Enter and direct restart must be rejected", failures)
	enter_hud.queue_free()
	await tree.process_frame

	var synchronous_viewport := SubViewport.new()
	synchronous_viewport.size = Vector2i(64, 64)
	tree.root.add_child(synchronous_viewport)
	var synchronous_hud = HUD_SCENE.instantiate()
	synchronous_viewport.add_child(synchronous_hud)
	await tree.process_frame
	synchronous_hud.show_result(&"victory")
	var synchronous_detach := SynchronousDetachProbe.new()
	synchronous_detach.target = synchronous_hud
	synchronous_hud.restart_requested.connect(synchronous_detach.on_restart)
	synchronous_hud._unhandled_input(enter)
	_expect(synchronous_detach.calls == 1, "Accepted Enter restart must tolerate a listener detaching the HUD synchronously", failures)
	_expect(synchronous_viewport.is_input_handled(), "Accepted Enter restart must mark the captured viewport handled after synchronous HUD teardown", failures)
	if is_instance_valid(synchronous_hud):
		synchronous_hud.free()
	synchronous_viewport.queue_free()
	await tree.process_frame

func _make_two_car_match(tree: SceneTree, position_a: Vector3, position_b: Vector3) -> Array:
	var controller = MATCH_CONTROLLER_SCRIPT.new()
	controller.set_physics_process(false)
	var car_a := _new_car(position_a)
	var car_b := _new_car(position_b)
	tree.root.add_child(controller)
	tree.root.add_child(car_a)
	tree.root.add_child(car_b)
	controller.set_physics_process(false)
	car_a.set_physics_process(false)
	car_b.set_physics_process(false)
	car_a.position = position_a
	car_b.position = position_b
	car_a.velocity = Vector3.ZERO
	car_b.velocity = Vector3.ZERO
	car_a.external_velocity = Vector3.ZERO
	car_b.external_velocity = Vector3.ZERO
	await tree.process_frame
	controller.register_car(car_a, 1, true)
	controller.register_car(car_b, 2, false)
	return [controller, car_a, car_b]

func _new_car(position: Vector3) -> BumperCar:
	var car := CAR_SCENE.instantiate() as BumperCar
	car.position = position
	car.set_physics_process(false)
	return car

func _free_nodes(tree: SceneTree, nodes: Array) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	await tree.process_frame

func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
