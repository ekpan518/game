extends RefCounted

const BASE_CAR_SCENE_PATH := "res://scenes/vehicles/bumper_car.tscn"
const PLAYER_CAR_SCENE_PATH := "res://scenes/vehicles/player_car.tscn"
const BUMPER_CAR_SCRIPT_PATH := "res://scripts/vehicles/bumper_car.gd"
const DRIVER_CONTROLLER_SCRIPT_PATH := "res://scripts/drivers/driver_controller.gd"
const HUMAN_DRIVER_SCRIPT_PATH := "res://scripts/drivers/human_driver.gd"

var _contact_reports: Array[Array] = []

class FixedCommandDriver:
	extends DriverController

	var command := DriveCommand.create(0.0, 0.0)

	func set_command(throttle: float, steering: float) -> void:
		command = DriveCommand.create(throttle, steering)

	func get_command(_car: BumperCar, _delta: float) -> DriveCommand:
		return command

func run(tree: SceneTree) -> Array[String]:
	await tree.process_frame
	var failures: Array[String] = []
	var car_scene := _load_scene(BASE_CAR_SCENE_PATH)
	var player_scene := _load_scene(PLAYER_CAR_SCENE_PATH)
	_expect(car_scene != null and player_scene != null, "Both bumper car scenes must load", failures)
	var script = _load_script(BUMPER_CAR_SCRIPT_PATH)
	_expect(script != null, "BumperCar script must load", failures)
	if script != null:
		_test_speed_model(script, failures)
	_test_driver_contract(failures)
	if car_scene != null:
		await _test_driver_physics_path(tree, car_scene, failures)
		await _test_base_car(tree, car_scene, failures)
		await _test_zero_snapshot(tree, car_scene, failures)
		await _test_snapshots_and_contacts(tree, car_scene, failures)
	if player_scene != null:
		await _test_player_car(tree, player_scene, failures)
	return failures

func _test_speed_model(script: Script, failures: Array[String]) -> void:
	_expect(is_equal_approx(script.step_longitudinal_speed(0.0, 1.0, 0.25), 4.5), "Forward acceleration must be 18 m/s squared", failures)
	_expect(is_equal_approx(script.step_longitudinal_speed(4.0, -1.0, 0.25), 0.0), "S must brake before reversing", failures)
	_expect(is_equal_approx(script.step_longitudinal_speed(0.0, -1.0, 0.25), -4.5), "Reverse must accelerate from rest", failures)
	_expect(is_equal_approx(script.step_longitudinal_speed(4.0, 0.0, 0.25), 2.0), "Coasting drag must be 8 m/s squared", failures)
	_expect(is_equal_approx(script.step_longitudinal_speed(12.0, 1.0, 1.0), 12.0), "Forward speed must cap at 12 m/s", failures)
	_expect(is_equal_approx(script.step_longitudinal_speed(-5.0, -1.0, 1.0), -5.0), "Reverse speed must cap at 5 m/s", failures)
	_expect(is_equal_approx(script.steering_rate_for_speed(0.0), deg_to_rad(42.0)), "Low-speed steering must retain 35 percent", failures)
	_expect(is_equal_approx(script.steering_rate_for_speed(12.0), deg_to_rad(120.0)), "Full-speed steering must be 120 degrees per second", failures)

func _test_driver_contract(failures: Array[String]) -> void:
	var driver_script := _load_script(DRIVER_CONTROLLER_SCRIPT_PATH)
	var human_script := _load_script(HUMAN_DRIVER_SCRIPT_PATH)
	_expect(driver_script != null and human_script != null, "Both driver scripts must load", failures)
	if driver_script == null or human_script == null:
		return
	_expect(_has_typed_return(driver_script, "get_command", "DriveCommand"), "DriverController command must declare DriveCommand return", failures)
	_expect(_has_typed_return(human_script, "get_command", "DriveCommand"), "HumanDriver command must declare DriveCommand return", failures)
	var neutral_driver = driver_script.new()
	var neutral_command = neutral_driver.get_command(null, 0.25)
	_expect(neutral_command != null and is_equal_approx(neutral_command.throttle, 0.0) and is_equal_approx(neutral_command.steering, 0.0), "DriverController must return a neutral command", failures)
	var human_driver = human_script.new()
	Input.action_press("drive_forward")
	Input.action_press("drive_left")
	var human_command = human_driver.get_command(null, 0.25)
	Input.action_release("drive_forward")
	Input.action_release("drive_left")
	_expect(human_command != null and is_equal_approx(human_command.throttle, 1.0), "HumanDriver must read drive_forward", failures)
	_expect(human_command != null and is_equal_approx(human_command.steering, -1.0), "HumanDriver must read drive_left", failures)
	neutral_driver.free()
	human_driver.free()

func _test_driver_physics_path(tree: SceneTree, car_scene: PackedScene, failures: Array[String]) -> void:
	var car = car_scene.instantiate()
	var fixed_driver := FixedCommandDriver.new()
	car.add_child(fixed_driver)
	car.set_physics_process(false)
	tree.root.add_child(car)
	await tree.process_frame
	car.set_driver(fixed_driver)
	car.set_physics_process(false)

	_reset_motion_case(car)
	fixed_driver.set_command(1.0, 0.0)
	var forward_start: Vector3 = car.global_position
	car._physics_process(0.25)
	var forward_displacement: Vector3 = car.global_position - forward_start
	_expect(car.longitudinal_speed > 0.0 and forward_displacement.dot(Vector3.FORWARD) > 0.001, "Forward throttle must move a real car along its forward vector", failures)

	_reset_motion_case(car)
	fixed_driver.set_command(-1.0, 0.0)
	var reverse_start: Vector3 = car.global_position
	car._physics_process(0.25)
	var reverse_displacement: Vector3 = car.global_position - reverse_start
	_expect(car.longitudinal_speed < 0.0 and reverse_displacement.dot(Vector3.BACK) > 0.001, "Reverse throttle must move a real car opposite its forward vector", failures)

	_reset_motion_case(car)
	fixed_driver.set_command(0.0, -1.0)
	car._physics_process(0.25)
	_expect(car.rotation.y > 0.01, "Left steering must rotate a real car around positive Y", failures)

	_reset_motion_case(car)
	fixed_driver.set_command(0.0, 1.0)
	car._physics_process(0.25)
	_expect(car.rotation.y < -0.01, "Right steering must rotate a real car around negative Y", failures)

	_reset_motion_case(car)
	car.apply_knockback(Vector3(3.0, 0.0, 0.0))
	fixed_driver.set_command(1.0, 0.0)
	var combined_start: Vector3 = car.global_position
	car._physics_process(0.1)
	var combined_displacement: Vector3 = car.global_position - combined_start
	var combined_velocity: Vector3 = car.get_combat_velocity()
	_expect(absf(combined_velocity.x - 2.0) < 0.001 and absf(combined_velocity.z + 1.8) < 0.001, "Throttle velocity and decayed external knockback must be combined", failures)
	_expect(combined_displacement.x > 0.001 and combined_displacement.z < -0.001, "Combined throttle and knockback must both affect real horizontal movement", failures)

	car.queue_free()
	await tree.process_frame

func _reset_motion_case(car: BumperCar) -> void:
	car.global_position = Vector3(0.0, 20.0, 0.0)
	car.rotation = Vector3.ZERO
	car.longitudinal_speed = 0.0
	car.external_velocity = Vector3.ZERO
	car.velocity = Vector3.ZERO

func _test_base_car(tree: SceneTree, car_scene: PackedScene, failures: Array[String]) -> void:
	var car = car_scene.instantiate()
	var second_car = car_scene.instantiate()
	_expect(not car.has_snapshot_for_frame(-1), "A car with no captured frame must not report the snapshot sentinel as present", failures)
	car.body_color = Color(0.9, 0.1, 0.2, 1.0)
	second_car.body_color = Color(0.1, 0.2, 0.9, 1.0)
	tree.root.add_child(car)
	tree.root.add_child(second_car)
	await tree.process_frame
	_expect(car is CharacterBody3D, "Base car root must be CharacterBody3D", failures)
	_expect(car.is_in_group("bumper_cars"), "Base car must join bumper_cars", failures)
	_expect(car.collision_layer == 2, "Base car collision layer must be 2", failures)
	_expect(car.collision_mask == 3, "Base car collision mask must be 3", failures)
	var collision_shape := car.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var box_shape: BoxShape3D = null
	if collision_shape != null:
		box_shape = collision_shape.shape as BoxShape3D
	_expect(box_shape != null and box_shape.size.is_equal_approx(Vector3(1.4, 0.8, 2.2)), "Car collision must be a 1.4 x 0.8 x 2.2 box", failures)
	_expect(car.get_node_or_null("Visuals") is Node3D, "Base car must contain Visuals", failures)
	_expect(_has_mesh_type(car, "Visuals/Body", "BoxMesh"), "Body must use BoxMesh", failures)
	_expect(_has_mesh_type(car, "Visuals/FrontBumper", "BoxMesh"), "FrontBumper must use BoxMesh", failures)
	_expect(_has_mesh_type(car, "Visuals/RearBumper", "BoxMesh"), "RearBumper must use BoxMesh", failures)
	var front_bumper := car.get_node_or_null("Visuals/FrontBumper") as MeshInstance3D
	var rear_bumper := car.get_node_or_null("Visuals/RearBumper") as MeshInstance3D
	var front_bumper_mesh := front_bumper.mesh as BoxMesh if front_bumper != null else null
	var rear_bumper_mesh := rear_bumper.mesh as BoxMesh if rear_bumper != null else null
	_expect(front_bumper_mesh != null and rear_bumper_mesh != null and front_bumper_mesh.size.z > rear_bumper_mesh.size.z and -front_bumper.position.z > rear_bumper.position.z, "Front silhouette must extend farther than the rear silhouette", failures)
	var hood := car.get_node_or_null("Visuals/Hood") as MeshInstance3D
	var cabin := car.get_node_or_null("Visuals/Cabin") as MeshInstance3D
	var hood_mesh := hood.mesh as BoxMesh if hood != null else null
	var cabin_mesh := cabin.mesh as BoxMesh if cabin != null else null
	var hood_top := hood.position.y + hood_mesh.size.y * 0.5 if hood != null and hood_mesh != null else INF
	var cabin_top := cabin.position.y + cabin_mesh.size.y * 0.5 if cabin != null and cabin_mesh != null else -INF
	_expect(hood_mesh != null and cabin_mesh != null and hood.position.z < 0.0 and cabin.position.z > 0.0 and hood_top < cabin_top, "A low front hood and taller rear-biased cabin must make the driving direction readable", failures)
	var headlight_left := car.get_node_or_null("Visuals/HeadlightL") as MeshInstance3D
	var headlight_right := car.get_node_or_null("Visuals/HeadlightR") as MeshInstance3D
	var tail_light_left := car.get_node_or_null("Visuals/TailLightL") as MeshInstance3D
	var tail_light_right := car.get_node_or_null("Visuals/TailLightR") as MeshInstance3D
	var headlight_left_material := headlight_left.material_override as StandardMaterial3D if headlight_left != null else null
	var headlight_right_material := headlight_right.material_override as StandardMaterial3D if headlight_right != null else null
	var tail_light_left_material := tail_light_left.material_override as StandardMaterial3D if tail_light_left != null else null
	var tail_light_right_material := tail_light_right.material_override as StandardMaterial3D if tail_light_right != null else null
	_expect(headlight_left != null and headlight_right != null and tail_light_left != null and tail_light_right != null and headlight_left.position.z < 0.0 and headlight_right.position.z < 0.0 and tail_light_left.position.z > 0.0 and tail_light_right.position.z > 0.0, "Cars must place a pair of headlights at the front and a pair of tail lights at the rear", failures)
	_expect(_is_warm_white_light(headlight_left_material) and _is_warm_white_light(headlight_right_material), "Both headlights must emit a bright warm-white cue", failures)
	_expect(_is_red_light(tail_light_left_material) and _is_red_light(tail_light_right_material), "Both tail lights must emit a distinct red cue", failures)
	for wheel_name in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		_expect(_has_mesh_type(car, "Visuals/%s" % wheel_name, "CylinderMesh"), "%s must use CylinderMesh" % wheel_name, failures)
	var label := car.get_node_or_null("Visuals/PowerLabel") as Label3D
	_expect(label != null, "Base car must contain PowerLabel", failures)
	var body := car.get_node_or_null("Visuals/Body") as MeshInstance3D
	var second_body := second_car.get_node_or_null("Visuals/Body") as MeshInstance3D
	var body_material: StandardMaterial3D = null
	var second_material: StandardMaterial3D = null
	var base_emission_energy := 0.0
	var second_albedo_before := Color()
	var second_emission_before := Color()
	var second_emission_energy_before := 0.0
	var second_emission_enabled_before := false
	_expect(body != null and second_body != null and body.material_override != second_body.material_override, "Each car must duplicate its body material", failures)
	if body != null and second_body != null:
		body_material = body.material_override as StandardMaterial3D
		second_material = second_body.material_override as StandardMaterial3D
		_expect(body_material != null and body_material.albedo_color.is_equal_approx(car.body_color), "Body material must use the instance color", failures)
		_expect(second_material != null and second_material.albedo_color.is_equal_approx(second_car.body_color), "Each duplicated material must keep its own color", failures)
		if body_material != null:
			base_emission_energy = body_material.emission_energy_multiplier
		if second_material != null:
			second_albedo_before = second_material.albedo_color
			second_emission_before = second_material.emission
			second_emission_energy_before = second_material.emission_energy_multiplier
			second_emission_enabled_before = second_material.emission_enabled
	car.apply_knockback(Vector3(100.0, 25.0, 0.0))
	_expect(is_equal_approx(car.external_velocity.length(), 18.0), "Knockback must cap at 18 m/s", failures)
	_expect(is_zero_approx(car.external_velocity.y), "Knockback must remain horizontal", failures)
	car.set_power_stacks(9)
	_expect(car.power_stacks == 3, "Power stacks must clamp to three", failures)
	_expect(label != null and label.text == "3", "PowerLabel must show the clamped stack count", failures)
	_expect(body_material != null and body_material.emission_enabled, "Powered cars must enable body emission", failures)
	_expect(body_material != null and body_material.emission.is_equal_approx(car.body_color), "Powered emission must use the car's own color", failures)
	_expect(body_material != null and body_material.emission_energy_multiplier > base_emission_energy, "Power stacks must increase body emission energy", failures)
	_expect(second_material != null and second_material.emission_enabled == second_emission_enabled_before and second_material.albedo_color.is_equal_approx(second_albedo_before) and second_material.emission.is_equal_approx(second_emission_before) and is_equal_approx(second_material.emission_energy_multiplier, second_emission_energy_before), "Powering one car must not modify another car's material", failures)
	car.set_power_stacks(-2)
	_expect(car.power_stacks == 0 and label != null and label.text == "0", "Power stacks and label must clamp to zero", failures)
	_expect(body_material != null and not body_material.emission_enabled, "Returning to zero stacks must disable body emission", failures)
	_expect(second_material != null and second_material.emission_enabled == second_emission_enabled_before and second_material.albedo_color.is_equal_approx(second_albedo_before) and second_material.emission.is_equal_approx(second_emission_before) and is_equal_approx(second_material.emission_energy_multiplier, second_emission_energy_before), "Resetting one car must leave another car's material unchanged", failures)
	_expect(car.eliminate(), "The first eliminate call must succeed", failures)
	_expect(not car.eliminate(), "The second eliminate call must be idempotent", failures)
	_expect(not car.alive, "Elimination must mark the car dead", failures)
	_expect(car.collision_layer == 0 and car.collision_mask == 0, "Elimination must disable car collision", failures)
	_expect(not car.visible and not car.is_physics_processing(), "Elimination must hide and stop the car", failures)
	second_car.freeze_for_result()
	_expect(second_car.alive, "Result freeze must not eliminate a survivor", failures)
	_expect(not second_car.is_physics_processing(), "Result freeze must stop vehicle physics", failures)
	_expect(second_car.velocity.is_zero_approx() and second_car.external_velocity.is_zero_approx(), "Result freeze must stop all motion", failures)
	car.queue_free()
	second_car.queue_free()
	await tree.process_frame

func _test_zero_snapshot(tree: SceneTree, car_scene: PackedScene, failures: Array[String]) -> void:
	var stationary_car = car_scene.instantiate()
	stationary_car.position = Vector3(40.0, 20.0, 0.0)
	tree.root.add_child(stationary_car)
	await tree.physics_frame
	await tree.process_frame
	var captured_frame := _find_retained_snapshot_frame(stationary_car, Engine.get_physics_frames())
	_expect(captured_frame >= 0, "A stationary car must retain the physics frame it captured", failures)
	if captured_frame >= 0:
		_expect(stationary_car.has_snapshot_for_frame(captured_frame), "A stationary frame with zero velocity must be present", failures)
		_expect(stationary_car.get_snapshot_for_frame(captured_frame).is_zero_approx(), "A stationary frame must retain Vector3.ZERO as valid snapshot data", failures)
		_expect(not stationary_car.has_snapshot_for_frame(captured_frame + 1000), "An unknown frame must remain absent beside a valid zero snapshot", failures)
	stationary_car.queue_free()
	await tree.process_frame

func _test_snapshots_and_contacts(tree: SceneTree, car_scene: PackedScene, failures: Array[String]) -> void:
	_contact_reports.clear()
	var left_car = car_scene.instantiate()
	var right_car = car_scene.instantiate()
	left_car.position = Vector3(-0.6, 0.0, 0.0)
	right_car.position = Vector3(0.6, 0.0, 0.0)
	tree.root.add_child(left_car)
	tree.root.add_child(right_car)
	left_car.contact_reported.connect(_on_contact_reported)
	right_car.contact_reported.connect(_on_contact_reported)
	if not left_car.has_method("has_snapshot_for_frame"):
		_expect(false, "BumperCar must expose snapshot presence separately from a zero velocity", failures)
		left_car.queue_free()
		right_car.queue_free()
		await tree.process_frame
		return
	left_car.apply_knockback(Vector3(4.0, 0.0, 0.0))
	right_car.apply_knockback(Vector3(-4.0, 0.0, 0.0))
	await tree.physics_frame
	await tree.process_frame
	var captured_frame := _find_retained_snapshot_frame(left_car, Engine.get_physics_frames())
	_expect(captured_frame >= 0, "Car must report which exact physics frame it captured", failures)
	var captured_velocity: Vector3 = left_car.get_snapshot_for_frame(captured_frame)
	_expect(not captured_velocity.is_zero_approx(), "Car must capture combat velocity before movement", failures)
	await tree.physics_frame
	await tree.process_frame
	_expect(left_car.has_snapshot_for_frame(captured_frame), "Car must retain the previous physics-frame snapshot", failures)
	_expect(left_car.get_snapshot_for_frame(captured_frame).is_equal_approx(captured_velocity), "Car must retain the previous physics-frame snapshot exactly", failures)
	_expect(not left_car.has_snapshot_for_frame(-999), "Unknown physics frames must be reported as missing", failures)
	_expect(not _contact_reports.is_empty(), "Live car slide collisions must emit contact reports", failures)
	if not _contact_reports.is_empty():
		var report := _contact_reports[0]
		_expect(report[0] != null and report[1] != null and report[0] != report[1], "Contact report must identify reporter and other car", failures)
		_expect(report[2] is Vector3 and not (report[2] as Vector3).is_zero_approx(), "Contact report must include a contact normal", failures)
		var reporter_to_other: Vector3 = report[1].global_position - report[0].global_position
		_expect(reporter_to_other.dot(report[2]) > 0.0, "Contact normal must point from reporter toward the other car", failures)
		_expect(report[3] is Vector3 and report[4] is int, "Contact report must include velocity and physics frame", failures)
		_expect(report[0].get_snapshot_for_frame(report[4]).is_equal_approx(report[3]), "Reported velocity must match the exact frame snapshot", failures)
		var combat_velocity := report[5] as Vector3
		var post_slide_velocity := report[6] as Vector3
		var post_slide_horizontal := Vector3(post_slide_velocity.x, 0.0, post_slide_velocity.z)
		_expect(is_zero_approx(combat_velocity.y), "Combat velocity must stay horizontal", failures)
		_expect(combat_velocity.is_equal_approx(post_slide_horizontal), "Combat velocity must reflect the post-slide horizontal velocity", failures)
	left_car.queue_free()
	right_car.queue_free()
	await tree.process_frame

func _test_player_car(tree: SceneTree, player_scene: PackedScene, failures: Array[String]) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var mouse_capture_supported := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player = player_scene.instantiate()
	tree.root.add_child(player)
	await tree.process_frame
	var human_driver := player.get_node_or_null("HumanDriver")
	_expect(human_driver != null and human_driver.get_script() == _load_script(HUMAN_DRIVER_SCRIPT_PATH), "Player car must contain HumanDriver", failures)
	_expect(player.driver == human_driver, "Player car must use its HumanDriver", failures)
	var yaw := player.get_node_or_null("CameraYaw") as Node3D
	var pitch := player.get_node_or_null("CameraYaw/CameraPitch") as Node3D
	var spring_arm := player.get_node_or_null("CameraYaw/CameraPitch/SpringArm3D") as SpringArm3D
	var camera := player.get_node_or_null("CameraYaw/CameraPitch/SpringArm3D/Camera3D") as Camera3D
	_expect(yaw != null and pitch != null and spring_arm != null and camera != null, "Player camera must use the direct yaw, pitch, spring-arm, camera chain", failures)
	_expect(camera != null and camera.current, "Player camera must be current", failures)
	_expect(spring_arm != null and is_equal_approx(spring_arm.spring_length, 4.5), "Player spring arm must be 4.5 m", failures)
	_expect(spring_arm != null and spring_arm.collision_mask == 1, "Player spring arm collision mask must be 1", failures)
	_expect(spring_arm != null and is_equal_approx(spring_arm.margin, 0.05), "Player spring arm margin must be 0.05 m", failures)
	if spring_arm != null:
		var owner_was_excluded := spring_arm.remove_excluded_object(player.get_rid())
		_expect(owner_was_excluded, "Player spring arm must exclude its owning car RID", failures)
		if owner_was_excluded:
			spring_arm.add_excluded_object(player.get_rid())
	if yaw != null and pitch != null:
		_expect(is_equal_approx(yaw.clamp_pitch_radians(-PI), deg_to_rad(-60.0)), "Camera pitch must clamp to -60 degrees", failures)
		_expect(is_equal_approx(yaw.clamp_pitch_radians(PI), deg_to_rad(45.0)), "Camera pitch must clamp to 45 degrees", failures)
		if yaw.has_method("apply_captured_mouse_motion"):
			var direct_yaw_before := yaw.rotation.y
			var direct_pitch_before := pitch.rotation.x
			yaw.apply_captured_mouse_motion(Vector2(100.0, 50.0))
			_expect(yaw.rotation.y < direct_yaw_before - 0.01, "Captured mouse motion logic must rotate camera yaw", failures)
			_expect(pitch.rotation.x < direct_pitch_before - 0.01, "Captured mouse motion logic must rotate camera pitch", failures)
		else:
			_expect(false, "Player camera must expose deterministic captured-motion behavior", failures)
		if mouse_capture_supported:
			_expect(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Player camera must capture the mouse on ready", failures)
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			var captured_yaw_before := yaw.rotation.y
			var captured_pitch_before := pitch.rotation.x
			var captured_motion := InputEventMouseMotion.new()
			captured_motion.relative = Vector2(100.0, 50.0)
			yaw._unhandled_input(captured_motion)
			_expect(yaw.rotation.y < captured_yaw_before - 0.01, "Captured mouse motion must rotate camera yaw", failures)
			_expect(pitch.rotation.x < captured_pitch_before - 0.01, "Captured mouse motion must rotate camera pitch", failures)
			var echoed_escape := InputEventKey.new()
			echoed_escape.keycode = KEY_ESCAPE
			echoed_escape.pressed = true
			echoed_escape.echo = true
			yaw._unhandled_input(echoed_escape)
			_expect(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Echoed Escape must not release the mouse", failures)
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		escape.echo = false
		yaw._unhandled_input(escape)
		if mouse_capture_supported:
			_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Non-echo Escape must release the mouse", failures)
		else:
			_expect(DisplayServer.get_name() == "headless", "Mouse capture may be unavailable only on a headless display server", failures)
		var yaw_before := yaw.rotation.y
		var pitch_before := pitch.rotation.x
		var released_motion := InputEventMouseMotion.new()
		released_motion.relative = Vector2(100.0, 50.0)
		yaw._unhandled_input(released_motion)
		_expect(is_equal_approx(yaw.rotation.y, yaw_before), "Released mouse motion must not change camera yaw", failures)
		_expect(is_equal_approx(pitch.rotation.x, pitch_before), "Released mouse motion must not change camera pitch", failures)
		var left_click := InputEventMouseButton.new()
		left_click.button_index = MOUSE_BUTTON_LEFT
		left_click.pressed = true
		yaw._unhandled_input(left_click)
		if mouse_capture_supported:
			_expect(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Left click must recapture the mouse", failures)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.queue_free()
	await tree.process_frame

func _on_contact_reported(reporter, other, contact_normal: Vector3, reporter_velocity: Vector3, physics_frame: int) -> void:
	_contact_reports.append([reporter, other, contact_normal, reporter_velocity, physics_frame, reporter.get_combat_velocity(), reporter.velocity])

func _load_scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene

func _load_script(path: String) -> Script:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Script

func _has_mesh_type(root: Node, path: String, expected_class: String) -> bool:
	var mesh_instance := root.get_node_or_null(path) as MeshInstance3D
	return mesh_instance != null and mesh_instance.mesh != null and mesh_instance.mesh.get_class() == expected_class

func _is_warm_white_light(material: StandardMaterial3D) -> bool:
	return material != null and material.emission_enabled and material.emission.r > 0.8 and material.emission.g > 0.7

func _is_red_light(material: StandardMaterial3D) -> bool:
	return material != null and material.emission_enabled and material.emission.r > 0.7 and material.emission.g < 0.2

func _has_typed_return(script: Script, method_name: String, type_name: String) -> bool:
	for method in script.get_script_method_list():
		if method.name == method_name:
			return method.return.type == TYPE_OBJECT and method.return.class_name == type_name
	return false

func _find_retained_snapshot_frame(car, latest_engine_frame: int) -> int:
	for offset in range(3):
		var candidate := latest_engine_frame - offset
		if car.has_snapshot_for_frame(candidate):
			return candidate
	return -1

func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
