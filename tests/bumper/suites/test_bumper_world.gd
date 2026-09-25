extends RefCounted

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const SPAWN_NAMES := [&"SpawnPlayer", &"SpawnAI1", &"SpawnAI2", &"SpawnAI3"]

class SignalRecorder:
	extends RefCounted

	var values: Array = []

	func record() -> void:
		values.append(true)

	func record_one(value: Variant) -> void:
		values.append(value)

func run(tree: SceneTree) -> Array[String]:
	await tree.process_frame
	var failures: Array[String] = []
	_test_project_settings(failures)
	var packed_main := _load_scene(MAIN_SCENE_PATH)
	_expect(packed_main != null, "Main scene must load", failures)
	if packed_main == null:
		return failures
	await _test_world_structure(tree, packed_main, failures)
	await _test_simultaneous_player_and_last_ai_defeat(tree, packed_main, failures)
	await _test_separate_ai_eliminations_win(tree, packed_main, failures)
	await _test_restart_route_and_fresh_instance(tree, packed_main, failures)
	return failures

func _test_project_settings(failures: Array[String]) -> void:
	_expect(ProjectSettings.get_setting("application/config/name") == "Bumper Arena", "Project name must be Bumper Arena", failures)
	_expect(ProjectSettings.get_setting("application/run/main_scene") == MAIN_SCENE_PATH, "Main scene path must remain stable", failures)
	_expect(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility", "Desktop renderer must remain GL Compatibility", failures)
	_expect(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile") == "gl_compatibility", "Mobile renderer must remain GL Compatibility", failures)
	_expect(ProjectSettings.get_setting("rendering/rendering_device/driver.windows") == "d3d12", "Windows rendering driver must remain d3d12", failures)
	_expect(ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics", "3D physics engine must remain Jolt Physics", failures)
	for action in [&"drive_forward", &"drive_back", &"drive_left", &"drive_right"]:
		_expect(InputMap.has_action(action), "Drive action %s must exist" % action, failures)
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right"]:
		_expect(not InputMap.has_action(action), "Legacy action %s must be removed" % action, failures)

func _test_world_structure(tree: SceneTree, packed_main: PackedScene, failures: Array[String]) -> void:
	var main := packed_main.instantiate()
	_disable_vehicle_physics(main)
	tree.root.add_child(main)
	_disable_vehicle_physics(main)
	await tree.process_frame
	_expect(main.name == &"BumperArena", "Main root must be named BumperArena", failures)
	_expect(main.has_method("_reload_current_scene"), "BumperArena root must own the reload handler", failures)

	var controller := main.get_node_or_null("MatchController") as MatchController
	var arena := main.get_node_or_null("Arena") as Node3D
	var death_zone := main.get_node_or_null("Arena/DeathZone") as Area3D
	var hud := main.get_node_or_null("HUD") as MatchHUD
	_expect(controller != null, "World must contain MatchController", failures)
	_expect(arena != null, "World must contain Arena", failures)
	_expect(death_zone != null, "World must contain a death zone", failures)
	_expect(hud != null, "World must contain HUD", failures)
	_test_environment(main, failures)
	if arena != null:
		_test_arena_geometry(arena, failures)

	var cars := _cars_under(main)
	_expect(cars.size() == 4, "World must contain four bumper cars", failures)
	if cars.size() == 4:
		_test_cars_and_spawns(main, arena, cars, failures)
	var human_drivers := _nodes_of_type(main, HumanDriver)
	var ai_drivers := _nodes_of_type(main, AIDriver)
	var cameras := main.find_children("*", "Camera3D", true, false)
	var current_cameras := 0
	for camera_value in cameras:
		var camera := camera_value as Camera3D
		if camera != null and camera.current:
			current_cameras += 1
	_expect(human_drivers.size() == 1, "World must contain exactly one human driver", failures)
	_expect(ai_drivers.size() == 3, "World must contain exactly three AI drivers", failures)
	_expect(cameras.size() == 1 and current_cameras == 1, "World must contain exactly one current camera", failures)
	if controller != null:
		for driver_value in ai_drivers:
			var ai_driver := driver_value as AIDriver
			_expect(ai_driver._match_controller == controller, "Every AI driver must bind to the world MatchController", failures)
			if arena != null:
				_expect(ai_driver._arena_center.is_equal_approx(arena.global_position), "Every AI driver must bind the arena center", failures)
		for car in cars:
			_expect(car.contact_reported.is_connected(controller.report_contact), "Car contacts must connect through MatchController.register_car", failures)
			_expect(car.contact_reported.get_connections().size() == 1, "Each car contact signal must have exactly one connection", failures)
	if hud != null:
		_test_initial_hud(hud, failures)
	if controller != null and hud != null:
		_expect(controller.alive_count_changed.is_connected(hud.set_alive_count), "Controller alive updates must connect to HUD", failures)
		_expect(controller.player_power_changed.is_connected(hud.set_power_stacks), "Controller power updates must connect to HUD", failures)
		_expect(controller.match_ended.is_connected(hud.show_result), "Controller result updates must connect to HUD", failures)
		_expect(hud.restart_requested.is_connected(controller.request_restart), "HUD restart requests must connect to MatchController", failures)
	if controller != null and death_zone != null:
		_expect(death_zone.car_entered_death_zone.is_connected(controller.queue_elimination), "Death zone must connect to MatchController queueing", failures)
	main.queue_free()
	await tree.process_frame

func _test_environment(main: Node, failures: Array[String]) -> void:
	var world_environment := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var environment: Environment = null
	var sky: Sky = null
	if world_environment != null:
		environment = world_environment.environment
	if environment != null:
		sky = environment.sky
	_expect(world_environment != null and environment != null, "World must have a non-null environment", failures)
	_expect(sky != null and sky.sky_material is ProceduralSkyMaterial, "World environment must use a procedural sky", failures)
	var lights := main.find_children("*", "DirectionalLight3D", true, false)
	_expect(lights.size() == 1, "World must contain exactly one directional light", failures)
	if lights.size() == 1:
		_expect((lights[0] as DirectionalLight3D).shadow_enabled, "World directional light must cast shadows", failures)

func _test_arena_geometry(arena: Node3D, failures: Array[String]) -> void:
	var platform := arena.get_node_or_null("Platform") as StaticBody3D
	_expect(platform != null, "Arena must contain one static Platform", failures)
	_expect(arena.find_children("*", "StaticBody3D", true, false).size() == 1, "Arena must not contain rails or extra static barriers", failures)
	if platform != null:
		_expect(platform.collision_layer == 1 and platform.collision_mask == 2, "Platform must use layer 1 and mask 2", failures)
		var mesh_instance := platform.get_node_or_null("MeshInstance3D") as MeshInstance3D
		var cylinder_mesh: CylinderMesh = null
		if mesh_instance != null:
			cylinder_mesh = mesh_instance.mesh as CylinderMesh
		_expect(cylinder_mesh != null, "Platform visual must use CylinderMesh", failures)
		if cylinder_mesh != null:
			_expect(is_equal_approx(cylinder_mesh.top_radius, 12.0) and is_equal_approx(cylinder_mesh.bottom_radius, 12.0) and is_equal_approx(cylinder_mesh.height, 0.6), "Platform mesh must be radius 12 and height 0.6", failures)
		var collision := platform.get_node_or_null("CollisionShape3D") as CollisionShape3D
		var cylinder_shape: CylinderShape3D = null
		if collision != null:
			cylinder_shape = collision.shape as CylinderShape3D
		_expect(cylinder_shape != null, "Platform collision must use CylinderShape3D", failures)
		if cylinder_shape != null:
			_expect(is_equal_approx(cylinder_shape.radius, 12.0) and is_equal_approx(cylinder_shape.height, 0.6), "Platform collision must match radius 12 and height 0.6", failures)
	var death_zone := arena.get_node_or_null("DeathZone") as Area3D
	if death_zone != null:
		_expect(is_equal_approx(death_zone.position.y, -5.0), "DeathZone must be centered at y = -5", failures)
		_expect(death_zone.collision_layer == 0 and death_zone.collision_mask == 2, "DeathZone must use layer 0 and mask 2", failures)
		var death_collision := death_zone.get_node_or_null("CollisionShape3D") as CollisionShape3D
		var death_shape: BoxShape3D = null
		if death_collision != null:
			death_shape = death_collision.shape as BoxShape3D
		_expect(death_shape != null and death_shape.size.is_equal_approx(Vector3(32.0, 2.0, 32.0)), "DeathZone must use a 32 x 2 x 32 box", failures)
	for spawn_name in SPAWN_NAMES:
		var marker := arena.get_node_or_null(NodePath(spawn_name)) as Marker3D
		_expect(marker != null, "Arena must contain %s" % spawn_name, failures)
		if marker == null:
			continue
		var xz_radius := Vector2(marker.position.x, marker.position.z).length()
		_expect(is_equal_approx(xz_radius, 6.0) and is_equal_approx(marker.position.y, 0.7), "%s must spawn at XZ radius 6 and y 0.7" % spawn_name, failures)
		_expect(_faces_center(marker.global_transform), "%s must face the arena center" % spawn_name, failures)

func _test_cars_and_spawns(main: Node, arena: Node3D, cars: Array[BumperCar], failures: Array[String]) -> void:
	var ids: Array[int] = []
	var colors: Dictionary[String, bool] = {}
	var cars_by_id: Dictionary[int, BumperCar] = {}
	for car in cars:
		ids.append(car.stable_id)
		cars_by_id[car.stable_id] = car
		colors[car.body_color.to_html()] = true
		_expect(car.collision_layer == 2 and car.collision_mask == 3, "Every live car must use layer 2 and mask 3", failures)
		var body := car.get_node_or_null("Visuals/Body") as MeshInstance3D
		var body_material := body.material_override as StandardMaterial3D if body != null else null
		_expect(body_material != null and body_material.albedo_color.is_equal_approx(car.body_color), "Every car must render its assigned body color", failures)
	ids.sort()
	_expect(ids == [1, 2, 3, 4], "Cars must use unique stable IDs 1 through 4", failures)
	_expect(colors.size() == 4, "The four cars must use four distinct high-contrast colors", failures)
	for car in cars:
		var channel_range := maxf(car.body_color.r, maxf(car.body_color.g, car.body_color.b)) - minf(car.body_color.r, minf(car.body_color.g, car.body_color.b))
		_expect(channel_range >= 0.5, "Every car color must have high channel contrast", failures)
	if arena == null:
		return
	for index in range(SPAWN_NAMES.size()):
		var car := cars_by_id.get(index + 1) as BumperCar
		var marker := arena.get_node_or_null(NodePath(SPAWN_NAMES[index])) as Marker3D
		if car == null or marker == null:
			continue
		_expect(car.global_position.is_equal_approx(marker.global_position), "Car %d must start on %s (actual %s, expected %s)" % [index + 1, SPAWN_NAMES[index], car.global_position, marker.global_position], failures)
		_expect(_faces_center(car.global_transform), "Car %d must face the arena center" % (index + 1), failures)
	var human_car_count := 0
	for car in cars:
		if car.get_node_or_null("HumanDriver") is HumanDriver:
			human_car_count += 1
			_expect(car.stable_id == 1, "Stable ID 1 must be the human car", failures)
	_expect(human_car_count == 1, "Exactly one car must be human-controlled", failures)

func _test_initial_hud(hud: MatchHUD, failures: Array[String]) -> void:
	var alive_label := hud.get_node_or_null("AliveLabel") as Label
	var power_label := hud.get_node_or_null("PowerLabel") as Label
	var result_panel := hud.get_node_or_null("ResultPanel") as Control
	_expect(alive_label != null and alive_label.text == "剩余车辆：4/4", "HUD must start at four alive", failures)
	_expect(power_label != null and power_label.text == "强化：0/3", "HUD must start at zero power", failures)
	_expect(result_panel != null and not result_panel.visible, "HUD result must start hidden", failures)

func _test_simultaneous_player_and_last_ai_defeat(tree: SceneTree, packed_main: PackedScene, failures: Array[String]) -> void:
	var main := await _instantiate_world(tree, packed_main)
	var controller := main.get_node_or_null("MatchController") as MatchController
	var hud := main.get_node_or_null("HUD") as MatchHUD
	var cars := _cars_under(main)
	if controller == null or hud == null or cars.size() != 4:
		_expect(false, "Defeat integration requires controller, HUD, and four cars", failures)
		await _free_world(tree, main)
		return
	var cars_by_id := _cars_by_id(cars)
	_expect(controller.queue_elimination(cars_by_id[2]), "First AI elimination must queue through the public controller API", failures)
	await tree.process_frame
	_expect(controller.queue_elimination(cars_by_id[3]), "Second AI elimination must queue through the public controller API", failures)
	await tree.process_frame
	var result_events := SignalRecorder.new()
	controller.match_ended.connect(result_events.record_one)
	_expect(controller.queue_elimination(cars_by_id[4]), "Last AI must queue before simultaneous resolution", failures)
	_expect(controller.queue_elimination(cars_by_id[1]), "Player must queue in the same elimination batch", failures)
	await tree.process_frame
	var result_label := hud.get_node_or_null("ResultPanel/VBoxContainer/ResultLabel") as Label
	_expect(result_events.values == [&"defeat"], "Simultaneous player and last-AI deaths must emit defeat", failures)
	_expect(result_label != null and result_label.text == "失败", "Simultaneous final defeat must reach the HUD", failures)
	await _free_world(tree, main)

func _test_separate_ai_eliminations_win(tree: SceneTree, packed_main: PackedScene, failures: Array[String]) -> void:
	var main := await _instantiate_world(tree, packed_main)
	var controller := main.get_node_or_null("MatchController") as MatchController
	var hud := main.get_node_or_null("HUD") as MatchHUD
	var cars := _cars_under(main)
	if controller == null or hud == null or cars.size() != 4:
		_expect(false, "Victory integration requires controller, HUD, and four cars", failures)
		await _free_world(tree, main)
		return
	var cars_by_id := _cars_by_id(cars)
	var result_events := SignalRecorder.new()
	controller.match_ended.connect(result_events.record_one)
	for stable_id in [2, 3, 4]:
		_expect(controller.queue_elimination(cars_by_id[stable_id]), "AI %d elimination must queue through the public controller API" % stable_id, failures)
		await tree.process_frame
	var result_label := hud.get_node_or_null("ResultPanel/VBoxContainer/ResultLabel") as Label
	_expect(result_events.values == [&"victory"], "Three separate AI eliminations must emit victory", failures)
	_expect(result_label != null and result_label.text == "胜利！", "Victory must reach the HUD", failures)
	await _free_world(tree, main)

func _test_restart_route_and_fresh_instance(tree: SceneTree, packed_main: PackedScene, failures: Array[String]) -> void:
	var dirty_main := await _instantiate_world(tree, packed_main)
	var dirty_controller := dirty_main.get_node_or_null("MatchController") as MatchController
	var dirty_hud := dirty_main.get_node_or_null("HUD") as MatchHUD
	var dirty_cars := _cars_under(dirty_main)
	if dirty_controller == null or dirty_hud == null or dirty_cars.size() != 4:
		_expect(false, "Restart integration requires controller, HUD, and four cars", failures)
		await _free_world(tree, dirty_main)
		return
	var reload_callable := Callable(dirty_main, "_reload_current_scene")
	_expect(dirty_controller.restart_accepted.is_connected(reload_callable), "Controller restart acceptance must connect to the root reload handler", failures)
	if dirty_controller.restart_accepted.is_connected(reload_callable):
		dirty_controller.restart_accepted.disconnect(reload_callable)
	var restart_events := SignalRecorder.new()
	dirty_controller.restart_accepted.connect(restart_events.record)
	_expect(dirty_hud.request_restart(), "Instantiated HUD must accept its first restart request", failures)
	_expect(not dirty_hud.request_restart(), "Instantiated HUD must reject its second restart request", failures)
	_expect(restart_events.values.size() == 1, "HUD to controller wiring must accept restart exactly once", failures)

	var dirty_by_id := _cars_by_id(dirty_cars)
	dirty_by_id[1].set_power_stacks(3)
	dirty_hud.set_power_stacks(3)
	dirty_hud.show_result(&"defeat")
	_expect(dirty_controller.queue_elimination(dirty_by_id[2]), "Dirty scene must accept a mutation before re-instantiation", failures)
	await tree.process_frame
	await _free_world(tree, dirty_main)

	var fresh_main := await _instantiate_world(tree, packed_main)
	var fresh_cars := _cars_under(fresh_main)
	var fresh_hud := fresh_main.get_node_or_null("HUD") as MatchHUD
	_expect(fresh_cars.size() == 4 and _alive_count(fresh_cars) == 4, "A fresh scene instance must restore four live cars", failures)
	var all_zero := fresh_cars.size() == 4
	for car in fresh_cars:
		all_zero = all_zero and car.power_stacks == 0
	_expect(all_zero, "A fresh scene instance must restore zero power stacks", failures)
	if fresh_hud != null:
		_test_initial_hud(fresh_hud, failures)
	else:
		_expect(false, "A fresh scene instance must restore HUD", failures)
	await _free_world(tree, fresh_main)

func _instantiate_world(tree: SceneTree, packed_main: PackedScene) -> Node:
	var main := packed_main.instantiate()
	_disable_vehicle_physics(main)
	tree.root.add_child(main)
	_disable_vehicle_physics(main)
	await tree.process_frame
	var controller := main.get_node_or_null("MatchController") as MatchController
	if controller != null:
		controller.set_physics_process(false)
	return main

func _free_world(tree: SceneTree, main: Node) -> void:
	if is_instance_valid(main):
		main.queue_free()
	await tree.process_frame

func _disable_vehicle_physics(node: Node) -> void:
	if node is BumperCar:
		(node as BumperCar).set_physics_process(false)
	for child in node.get_children():
		_disable_vehicle_physics(child)

func _cars_under(main: Node) -> Array[BumperCar]:
	var cars: Array[BumperCar] = []
	if main.get_tree() == null:
		return cars
	for node in main.get_tree().get_nodes_in_group("bumper_cars"):
		if node is BumperCar and main.is_ancestor_of(node):
			cars.append(node)
	return cars

func _cars_by_id(cars: Array[BumperCar]) -> Dictionary[int, BumperCar]:
	var lookup: Dictionary[int, BumperCar] = {}
	for car in cars:
		lookup[car.stable_id] = car
	return lookup

func _alive_count(cars: Array[BumperCar]) -> int:
	var count := 0
	for car in cars:
		if car.alive:
			count += 1
	return count

func _nodes_of_type(root: Node, type_script: Script) -> Array[Node]:
	var matches: Array[Node] = []
	_collect_nodes_of_type(root, type_script, matches)
	return matches

func _collect_nodes_of_type(node: Node, type_script: Script, matches: Array[Node]) -> void:
	if node.get_script() == type_script:
		matches.append(node)
	for child in node.get_children():
		_collect_nodes_of_type(child, type_script, matches)

func _faces_center(transform: Transform3D) -> bool:
	var forward := -transform.basis.z
	forward.y = 0.0
	var toward_center := -transform.origin
	toward_center.y = 0.0
	return not forward.is_zero_approx() and not toward_center.is_zero_approx() and forward.normalized().dot(toward_center.normalized()) > 0.999

func _load_scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene

func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
