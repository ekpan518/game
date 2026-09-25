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

func run(tree: SceneTree) -> Array[String]:
	await tree.process_frame
	var failures: Array[String] = []
	_test_match_state_boundaries(failures)
	_test_match_state_batch_rules(failures)
	_test_match_state_results_and_ties(failures)
	await _test_controller_registration_and_queries(tree, failures)
	await _test_controller_contact_deduplication(tree, failures)
	await _test_controller_contact_edge_cases(tree, failures)
	await _test_controller_contact_before_death(tree, failures)
	await _test_controller_fall_fallback_and_restart(tree, failures)
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
	high_ai.queue_free()
	await tree.process_frame
	_expect(controller.get_live_opponents_for(player).is_empty(), "Freed cars must be filtered from live opponents", failures)
	_expect(controller.queue_elimination(player), "A live player must still be queueable", failures)
	await tree.process_frame
	_expect(controller.get_live_opponents_for(player).is_empty(), "A dead requester must receive no opponents", failures)
	await _free_nodes(tree, [controller, player, low_ai, unknown])

func _test_controller_contact_deduplication(tree: SceneTree, failures: Array[String]) -> void:
	var setup := await _make_two_car_match(tree, Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	var controller = setup[0]
	var car_a: BumperCar = setup[1]
	var car_b: BumperCar = setup[2]
	car_a._capture_snapshot(100, Vector3(8.0, 0.0, 0.0))
	car_b._capture_snapshot(100, Vector3.ZERO)
	controller.report_contact(car_a, car_b, Vector3.LEFT, Vector3(-100.0, 0.0, 0.0), 100)
	controller.report_contact(car_b, car_a, Vector3.LEFT, Vector3(100.0, 0.0, 0.0), 100)
	await tree.process_frame
	_expect(car_a.external_velocity.is_zero_approx(), "A stationary defender must not knock back the attacker", failures)
	_expect(car_b.external_velocity.is_equal_approx(Vector3(7.2, 0.0, 0.0)), "Reversed reports in one frame must apply one canonical knockback", failures)
	car_a._capture_snapshot(101, Vector3(8.0, 0.0, 0.0))
	car_b._capture_snapshot(101, Vector3.ZERO)
	controller.report_contact(car_b, car_a, Vector3.LEFT, Vector3.ZERO, 101)
	await tree.process_frame
	_expect(car_b.external_velocity.is_equal_approx(Vector3(14.4, 0.0, 0.0)), "The same pair must be eligible again on the next physics frame", failures)
	await _free_nodes(tree, setup)

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
	bilateral_a._capture_snapshot(220, Vector3(8.0, 0.0, 0.0))
	bilateral_b._capture_snapshot(220, Vector3(-8.0, 0.0, 0.0))
	bilateral_controller.report_contact(bilateral_a, bilateral_b, Vector3.RIGHT, Vector3.ZERO, 220)
	await tree.process_frame
	_expect(bilateral_a.external_velocity.x < -13.9 and bilateral_b.external_velocity.x > 13.9, "Both directional attacks must be calculated and applied for a head-on collision", failures)
	await _free_nodes(tree, bilateral)

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
	var result_events := SignalRecorder.new()
	controller.match_ended.connect(result_events.record_one)
	var physics_frame := Engine.get_physics_frames()
	player._capture_snapshot(physics_frame, Vector3(8.0, 0.0, 0.0))
	victim._capture_snapshot(physics_frame, Vector3.ZERO)
	controller.report_contact(player, victim, Vector3.RIGHT, Vector3(8.0, 0.0, 0.0), physics_frame)
	_expect(controller.queue_elimination(victim), "A same-frame contacted victim must enter the death batch", failures)
	await tree.process_frame
	_expect(not victim.alive and player.power_stacks == 1, "Deferred drain must resolve same-frame contacts before deaths", failures)
	_expect(result_events.values == [&"victory"], "Eliminating the final opponent must emit victory once", failures)
	_expect(not player.is_physics_processing(), "A final result must freeze surviving cars", failures)
	await _free_nodes(tree, setup)

func _test_controller_fall_fallback_and_restart(tree: SceneTree, failures: Array[String]) -> void:
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
	var restart_probe := RestartProbe.new()
	restart_probe.target = controller
	controller.restart_accepted.connect(restart_probe.on_restart)
	_expect(controller.request_restart(), "The controller must accept its first restart request", failures)
	_expect(restart_probe.calls == 1 and restart_probe.reentrant_results == [false], "Controller restart latch must be set before emitting", failures)
	_expect(not controller.request_restart() and restart_probe.calls == 1, "Controller restart acceptance must be idempotent", failures)
	await _free_nodes(tree, setup)

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
	var result_label := hud.find_child("ResultLabel", true, false) as Label
	var restart_button := hud.find_child("RestartButton", true, false) as Button
	_expect(alive_label != null and alive_label.text == "剩余车辆：4/4", "HUD must start with the four-car alive copy", failures)
	_expect(power_label != null and power_label.text == "强化：0/3", "HUD must start with zero power copy", failures)
	_expect(result_panel != null and not result_panel.visible, "HUD result panel must start hidden", failures)
	hud.set_alive_count(2, 4)
	hud.set_power_stacks(2)
	_expect(alive_label != null and alive_label.text == "剩余车辆：2/4", "HUD must render alive updates", failures)
	_expect(power_label != null and power_label.text == "强化：2/3", "HUD must render power updates", failures)
	hud.show_result(&"victory")
	_expect(result_panel != null and result_panel.visible and result_label != null and result_label.text == "胜利！", "HUD must show Chinese victory copy", failures)
	hud.show_result(&"defeat")
	_expect(result_label != null and result_label.text == "失败", "HUD must show Chinese defeat copy", failures)
	var restart_probe := RestartProbe.new()
	restart_probe.target = hud
	hud.restart_requested.connect(restart_probe.on_restart)
	_expect(hud.request_restart(), "HUD must accept its first restart request", failures)
	_expect(restart_probe.calls == 1 and restart_probe.reentrant_results == [false], "HUD restart latch must be set before emitting", failures)
	_expect(not hud.request_restart() and restart_probe.calls == 1, "Two immediate HUD restart requests must emit only once", failures)
	hud.queue_free()
	await tree.process_frame

	var input_hud = HUD_SCENE.instantiate()
	tree.root.add_child(input_hud)
	await tree.process_frame
	var input_events := SignalRecorder.new()
	input_hud.restart_requested.connect(input_events.record)
	var input_button := input_hud.find_child("RestartButton", true, false) as Button
	input_button.pressed.emit()
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	enter.echo = false
	input_hud._unhandled_input(enter)
	_expect(input_events.values.size() == 1, "Restart button and Enter must share one latch", failures)
	input_hud.queue_free()
	await tree.process_frame

	var enter_hud = HUD_SCENE.instantiate()
	tree.root.add_child(enter_hud)
	await tree.process_frame
	var enter_events := SignalRecorder.new()
	enter_hud.restart_requested.connect(enter_events.record)
	enter_hud._unhandled_input(enter)
	_expect(enter_events.values.size() == 1, "Enter alone must request restart", failures)
	enter_hud.queue_free()
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
