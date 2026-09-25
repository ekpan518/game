extends RefCounted

const AI_DRIVER_SCRIPT_PATH := "res://scripts/drivers/ai_driver.gd"
const BASE_CAR_SCENE_PATH := "res://scenes/vehicles/bumper_car.tscn"
const PLAYER_CAR_SCENE_PATH := "res://scenes/vehicles/player_car.tscn"
const AI_CAR_SCENE_PATH := "res://scenes/vehicles/ai_car.tscn"

class StubMatchController:
	extends MatchController

	var opponents: Array[BumperCar] = []

	func get_live_opponents_for(_requester: BumperCar) -> Array[BumperCar]:
		return opponents

func run(tree: SceneTree) -> Array[String]:
	await tree.process_frame
	var failures: Array[String] = []
	var ai_script := _load_script(AI_DRIVER_SCRIPT_PATH)
	var base_scene := _load_scene(BASE_CAR_SCENE_PATH)
	var player_scene := _load_scene(PLAYER_CAR_SCENE_PATH)
	var ai_scene := _load_scene(AI_CAR_SCENE_PATH)
	_expect(ai_script != null, "AIDriver script must load", failures)
	_expect(base_scene != null and player_scene != null, "Existing bumper car scenes must load for AI tests", failures)
	_expect(ai_scene != null, "Inherited AI car scene must load", failures)
	if ai_script == null or base_scene == null:
		return failures
	_test_typed_contract(ai_script, failures)
	await _test_nearest_and_stable_tie(tree, ai_script, base_scene, failures)
	await _test_no_target_is_neutral_and_resets(tree, ai_script, base_scene, failures)
	await _test_eliminated_and_freed_reselection(tree, ai_script, base_scene, failures)
	await _test_target_lead_uses_combat_velocity(tree, ai_script, base_scene, failures)
	await _test_safe_edge_recovery(tree, ai_script, base_scene, failures)
	await _test_emergency_edge_recovery(tree, ai_script, base_scene, failures)
	await _test_center_command_is_finite(tree, ai_script, base_scene, failures)
	await _test_behind_target_keeps_positive_throttle(tree, ai_script, base_scene, failures)
	await _test_stuck_recovery_timing_and_reset(tree, ai_script, base_scene, failures)
	await _test_edge_recovery_overrides_stuck(tree, ai_script, base_scene, failures)
	if ai_scene != null and player_scene != null:
		await _test_ai_scene(tree, ai_script, ai_scene, player_scene, failures)
	return failures

func _test_typed_contract(ai_script: Script, failures: Array[String]) -> void:
	_expect(_has_typed_argument(ai_script, "bind_match", 0, "MatchController"), "AIDriver.bind_match must require MatchController", failures)
	_expect(_has_typed_return(ai_script, "get_command", "DriveCommand"), "AIDriver.get_command must declare DriveCommand return", failures)

func _test_nearest_and_stable_tie(tree: SceneTree, ai_script: Script, car_scene: PackedScene, failures: Array[String]) -> void:
	var setup := await _make_case(tree, ai_script, car_scene, Vector3.ZERO, 1)
	var controller: StubMatchController = setup[0]
	var driver = setup[1]
	var car: BumperCar = setup[2]
	var low_id := await _add_car(tree, car_scene, Vector3(4.0, 0.0, -4.0), 2)
	var high_id := await _add_car(tree, car_scene, Vector3(-1.0, 0.0, -2.0), 3)
	controller.opponents.assign([low_id, high_id])
	var nearest_command = driver.get_command(car, 0.1)
	_expect(nearest_command.steering < -0.1, "AI must pursue the nearest live opponent on every command", failures)
	low_id.global_position = Vector3(2.0, 0.0, -2.0)
	high_id.global_position = Vector3(-2.0, 0.0, -2.0)
	controller.opponents.assign([high_id, low_id])
	var tied_command = driver.get_command(car, 0.1)
	_expect(tied_command.steering > 0.1, "Equal-distance targets must choose the lower stable ID independent of query order", failures)
	await _free_nodes(tree, [controller, driver, car, low_id, high_id])

func _test_no_target_is_neutral_and_resets(tree: SceneTree, ai_script: Script, car_scene: PackedScene, failures: Array[String]) -> void:
	var unbound_driver = ai_script.new()
	var unbound_car := await _add_car(tree, car_scene, Vector3.ZERO, 1)
	var unbound_command = unbound_driver.get_command(unbound_car, 1.0)
	_expect(unbound_command.throttle == 0.0 and unbound_command.steering == 0.0, "An unbound AI must return an exact neutral command", failures)
	unbound_driver.free()
	unbound_car.queue_free()
	await tree.process_frame

	var setup := await _make_case(tree, ai_script, car_scene, Vector3.ZERO, 2)
	var controller: StubMatchController = setup[0]
	var driver = setup[1]
	var car: BumperCar = setup[2]
	var target := await _add_car(tree, car_scene, Vector3(0.0, 0.0, -5.0), 3)
	controller.opponents.assign([target])
	car._combat_velocity = Vector3.ZERO
	driver.get_command(car, 1.0)
	controller.opponents.clear()
	var neutral_command = driver.get_command(car, 0.25)
	_expect(neutral_command.throttle == 0.0 and neutral_command.steering == 0.0, "No live target must return an exact neutral command", failures)
	controller.opponents.assign([target])
	var after_reset = driver.get_command(car, 0.25)
	_expect(after_reset.throttle > 0.5, "Losing all targets must reset accumulated stuck state", failures)
	await _free_nodes(tree, [controller, driver, car, target])

func _test_eliminated_and_freed_reselection(tree: SceneTree, ai_script: Script, car_scene: PackedScene, failures: Array[String]) -> void:
	var setup := await _make_case(tree, ai_script, car_scene, Vector3.ZERO, 1)
	var controller: StubMatchController = setup[0]
	var driver = setup[1]
	var car: BumperCar = setup[2]
	var stale_right := await _add_car(tree, car_scene, Vector3(1.0, 0.0, -2.0), 2)
	var live_left := await _add_car(tree, car_scene, Vector3(-4.0, 0.0, -4.0), 3)
	controller.opponents.assign([car, stale_right, live_left])
	_expect(driver.get_command(car, 0.1).steering > 0.1, "AI must ignore itself and initially choose the nearer opponent", failures)
	stale_right.eliminate()
	_expect(driver.get_command(car, 0.1).steering < -0.1, "An eliminated target must be filtered and replaced immediately", failures)

	var freed_right := await _add_car(tree, car_scene, Vector3(1.0, 0.0, -2.0), 4)
	controller.opponents.assign([freed_right, live_left])
	_expect(driver.get_command(car, 0.1).steering > 0.1, "A newly nearer live opponent must be selected without caching", failures)
	freed_right.queue_free()
	await tree.process_frame
	var after_free = driver.get_command(car, 0.1)
	_expect(after_free.steering < -0.1, "A freed target must never be dereferenced and must cause safe reselection", failures)
	await _free_nodes(tree, [controller, driver, car, stale_right, live_left])

func _test_target_lead_uses_combat_velocity(tree: SceneTree, ai_script: Script, car_scene: PackedScene, failures: Array[String]) -> void:
	var setup := await _make_case(tree, ai_script, car_scene, Vector3.ZERO, 1)
	var controller: StubMatchController = setup[0]
	var driver = setup[1]
	var car: BumperCar = setup[2]
	var target := await _add_car(tree, car_scene, Vector3(0.0, 0.0, -6.0), 2)
	controller.opponents.assign([target])
	target._combat_velocity = Vector3.ZERO
	var direct = driver.get_command(car, 0.1)
	target.velocity = Vector3(-8.0, 0.0, 0.0)
	target._combat_velocity = Vector3(6.0, 0.0, 0.0)
	var led = driver.get_command(car, 0.1)
	_expect(absf(direct.steering) < 0.001 and absf(led.steering - 0.21433385) < 0.0001, "Target lead must use post-slide combat velocity for the exact 0.35 second prediction", failures)
	await _free_nodes(tree, [controller, driver, car, target])

func _test_safe_edge_recovery(tree: SceneTree, ai_script: Script, car_scene: PackedScene, failures: Array[String]) -> void:
	var setup := await _make_case(tree, ai_script, car_scene, Vector3(9.36, 0.0, 0.0), 1)
	var controller: StubMatchController = setup[0]
	var driver = setup[1]
	var car: BumperCar = setup[2]
	var target := await _add_car(tree, car_scene, Vector3(11.0, 0.0, 0.0), 2)
	controller.opponents.assign([target])
	car.velocity = Vector3(-4.0, 0.0, 0.0)
	car._combat_velocity = Vector3(1.0, 0.0, 0.0)
	var command = driver.get_command(car, 0.1)
	_expect(command.steering < -0.9, "At the inclusive safe radius, non-inward combat velocity must steer toward center", failures)
	_expect(command.throttle > 0.0 and command.throttle <= 0.65, "Safe-edge recovery must cap forward throttle at 0.65", failures)
	car._combat_velocity = Vector3(-1.0, 0.0, 0.0)
	var inward_command = driver.get_command(car, 0.1)
	_expect(inward_command.steering > 0.9 and inward_command.throttle == 1.0, "Clearly inward combat velocity in the safe band must allow pursuit", failures)
	await _free_nodes(tree, [controller, driver, car, target])

func _test_emergency_edge_recovery(tree: SceneTree, ai_script: Script, car_scene: PackedScene, failures: Array[String]) -> void:
	var setup := await _make_case(tree, ai_script, car_scene, Vector3(10.8, 0.0, 0.0), 1)
	var controller: StubMatchController = setup[0]
	var driver = setup[1]
	var car: BumperCar = setup[2]
	var target := await _add_car(tree, car_scene, Vector3(14.0, 0.0, 0.0), 2)
	controller.opponents.assign([target])
	car._combat_velocity = Vector3(-5.0, 0.0, 0.0)
	var command = driver.get_command(car, 0.1)
	_expect(command.steering < -0.9, "At the inclusive emergency radius, recovery must steer toward center regardless of inward velocity", failures)
	_expect(command.throttle == 1.0, "Emergency recovery must use full forward throttle", failures)
	await _free_nodes(tree, [controller, driver, car, target])

func _test_center_command_is_finite(tree: SceneTree, ai_script: Script, car_scene: PackedScene, failures: Array[String]) -> void:
	var center := Vector3(4.0, 0.0, -3.0)
	var setup := await _make_case(tree, ai_script, car_scene, center, 1)
	var controller: StubMatchController = setup[0]
	var driver = setup[1]
	var car: BumperCar = setup[2]
	var target := await _add_car(tree, car_scene, center, 2)
	controller.opponents.assign([target])
	driver.set_arena_center(center)
	var command = driver.get_command(car, 0.1)
	_expect(not is_nan(command.steering) and not is_inf(command.steering), "A car at the exact arena center must produce finite steering", failures)
	_expect(command.steering == 0.0, "A zero desired direction at arena center must steer neutrally", failures)
	await _free_nodes(tree, [controller, driver, car, target])

func _test_behind_target_keeps_positive_throttle(tree: SceneTree, ai_script: Script, car_scene: PackedScene, failures: Array[String]) -> void:
	var setup := await _make_case(tree, ai_script, car_scene, Vector3.ZERO, 1)
	var controller: StubMatchController = setup[0]
	var driver = setup[1]
	var car: BumperCar = setup[2]
	var target := await _add_car(tree, car_scene, Vector3(0.0, 0.0, 5.0), 2)
	controller.opponents.assign([target])
	var command = driver.get_command(car, 0.1)
	_expect(command.throttle > 0.0 and command.throttle < 1.0, "A target behind must reduce throttle but never make normal pursuit reverse", failures)
	await _free_nodes(tree, [controller, driver, car, target])

func _test_stuck_recovery_timing_and_reset(tree: SceneTree, ai_script: Script, car_scene: PackedScene, failures: Array[String]) -> void:
	var setup := await _make_case(tree, ai_script, car_scene, Vector3.ZERO, 2)
	var controller: StubMatchController = setup[0]
	var driver = setup[1]
	var car: BumperCar = setup[2]
	var target := await _add_car(tree, car_scene, Vector3(0.0, 0.0, -5.0), 4)
	controller.opponents.assign([target])
	car.velocity = Vector3(8.0, 0.0, 0.0)
	car.longitudinal_speed = 8.0
	car._combat_velocity = Vector3.ZERO
	_expect(driver.get_command(car, 0.5).throttle > 0.5, "Stuck recovery must not begin before 1.25 seconds", failures)
	_expect(driver.get_command(car, 0.5).throttle > 0.5, "One second of low post-slide speed must remain normal pursuit", failures)
	var entry = driver.get_command(car, 0.25)
	_expect(entry.throttle == -1.0 and absf(entry.steering) == 1.0, "The call reaching 1.25 seconds must immediately enter reverse-and-turn recovery", failures)
	var recovery_turn: float = entry.steering
	var recovery_second = driver.get_command(car, 0.25)
	var recovery_third = driver.get_command(car, 0.25)
	_expect(recovery_second.throttle == -1.0 and recovery_third.throttle == -1.0, "Recovery must remain active for exactly 0.75 seconds", failures)
	_expect(recovery_second.steering == recovery_turn and recovery_third.steering == recovery_turn, "Recovery steering must remain deterministic for one stable ID", failures)
	var after_recovery = driver.get_command(car, 0.01)
	_expect(after_recovery.throttle > 0.5, "The call after 0.75 seconds of recovery must resume normal pursuit", failures)

	driver.get_command(car, 0.75)
	car._combat_velocity = Vector3(0.5, 0.0, 0.0)
	driver.get_command(car, 0.25)
	car._combat_velocity = Vector3.ZERO
	_expect(driver.get_command(car, 0.5).throttle > 0.5 and driver.get_command(car, 0.5).throttle > 0.5, "Speed at the 0.5 m/s boundary must reset the stuck timer", failures)

	var odd_setup := await _make_case(tree, ai_script, car_scene, Vector3(2.0, 0.0, 0.0), 3)
	var odd_match: StubMatchController = odd_setup[0]
	var odd_driver = odd_setup[1]
	var odd_car: BumperCar = odd_setup[2]
	var odd_target := await _add_car(tree, car_scene, Vector3(2.0, 0.0, -5.0), 5)
	odd_match.opponents.assign([odd_target])
	odd_car._combat_velocity = Vector3.ZERO
	var odd_recovery = odd_driver.get_command(odd_car, 1.25)
	_expect(odd_recovery.throttle == -1.0 and odd_recovery.steering == -recovery_turn, "Positive even and odd stable IDs must choose opposite deterministic recovery turns", failures)
	await _free_nodes(tree, [controller, driver, car, target, odd_match, odd_driver, odd_car, odd_target])

func _test_edge_recovery_overrides_stuck(tree: SceneTree, ai_script: Script, car_scene: PackedScene, failures: Array[String]) -> void:
	var setup := await _make_case(tree, ai_script, car_scene, Vector3.ZERO, 2)
	var controller: StubMatchController = setup[0]
	var driver = setup[1]
	var car: BumperCar = setup[2]
	var target := await _add_car(tree, car_scene, Vector3(14.0, 0.0, 0.0), 3)
	controller.opponents.assign([target])
	car._combat_velocity = Vector3.ZERO
	_expect(driver.get_command(car, 1.25).throttle == -1.0, "Precondition: the car must enter stuck recovery", failures)
	car.global_position = Vector3(10.8, 0.0, 0.0)
	var edge_command = driver.get_command(car, 0.25)
	_expect(edge_command.throttle == 1.0 and edge_command.steering < -0.9, "Emergency edge recovery must override an active stuck reverse", failures)
	await _free_nodes(tree, [controller, driver, car, target])

func _test_ai_scene(tree: SceneTree, ai_script: Script, ai_scene: PackedScene, player_scene: PackedScene, failures: Array[String]) -> void:
	var ai = ai_scene.instantiate()
	var player = player_scene.instantiate()
	ai.set_physics_process(false)
	player.set_physics_process(false)
	tree.root.add_child(ai)
	tree.root.add_child(player)
	await tree.process_frame
	var ai_driver := ai.get_node_or_null("AIDriver")
	var ai_driver_count := 0
	for child in ai.get_children():
		if child.get_script() == ai_script:
			ai_driver_count += 1
	_expect(ai is BumperCar and ai.get_script() == player.get_script(), "AI scene must inherit the same BumperCar implementation as the player", failures)
	_expect(ai_driver_count == 1 and ai_driver != null and ai_driver.get_script() == ai_script and ai.driver == ai_driver, "AI scene must contain and bind exactly one AIDriver", failures)
	_expect(ai.find_children("*", "Camera3D", true, false).is_empty(), "AI scene must not contain a Camera3D", failures)
	_expect(ai.MAX_FORWARD_SPEED == player.MAX_FORWARD_SPEED and ai.DRIVE_ACCELERATION == player.DRIVE_ACCELERATION and ai.MAX_STEERING_RATE == player.MAX_STEERING_RATE, "AI and player scenes must use identical BumperCar motion constants", failures)
	await _free_nodes(tree, [ai, player])

func _make_case(tree: SceneTree, ai_script: Script, car_scene: PackedScene, position: Vector3, stable_id: int) -> Array:
	var controller := StubMatchController.new()
	controller.set_physics_process(false)
	var driver = ai_script.new()
	var car := car_scene.instantiate() as BumperCar
	car.set_physics_process(false)
	car.position = position
	car.stable_id = stable_id
	tree.root.add_child(controller)
	tree.root.add_child(driver)
	tree.root.add_child(car)
	await tree.process_frame
	driver.bind_match(controller)
	driver.set_arena_center(Vector3.ZERO)
	return [controller, driver, car]

func _add_car(tree: SceneTree, car_scene: PackedScene, position: Vector3, stable_id: int) -> BumperCar:
	var car := car_scene.instantiate() as BumperCar
	car.set_physics_process(false)
	car.position = position
	car.stable_id = stable_id
	tree.root.add_child(car)
	await tree.process_frame
	return car

func _free_nodes(tree: SceneTree, nodes: Array) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	await tree.process_frame

func _load_scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene

func _load_script(path: String) -> Script:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Script

func _has_typed_argument(script: Script, method_name: String, argument_index: int, type_name: String) -> bool:
	for method in script.get_script_method_list():
		if method.name != method_name or method.args.size() <= argument_index:
			continue
		var argument: Dictionary = method.args[argument_index]
		return argument.type == TYPE_OBJECT and argument.class_name == type_name
	return false

func _has_typed_return(script: Script, method_name: String, type_name: String) -> bool:
	for method in script.get_script_method_list():
		if method.name == method_name:
			return method.return.type == TYPE_OBJECT and method.return.class_name == type_name
	return false

func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
