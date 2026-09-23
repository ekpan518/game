extends SceneTree

var failures: Array[String] = []
var scope := "all"

func _init() -> void:
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--scope="):
            scope = argument.trim_prefix("--scope=")
    call_deferred("_run")

func _run() -> void:
    if scope in ["player", "world", "all"]:
        await _test_player_contract()
    if scope in ["world", "all"]:
        await _test_main_scene_contract()
    if failures.is_empty():
        print("[PASS] Godot Stage 0 %s checks passed." % scope)
        quit(0)
        return
    for failure in failures:
        push_error("[FAIL] %s" % failure)
    quit(1)

func _expect(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)

func _test_player_contract() -> void:
    var packed_player := load("res://scenes/player/player.tscn") as PackedScene
    _expect(packed_player != null, "player.tscn must load as a PackedScene")
    if packed_player == null:
        return
    var player = packed_player.instantiate()
    root.add_child(player)
    await process_frame
    _expect(player is CharacterBody3D, "Player root must be CharacterBody3D")
    var forward: Vector3 = player.call("calculate_move_direction", Vector2(0.0, -1.0))
    _expect(forward.is_equal_approx(Vector3.FORWARD), "Forward input must follow camera forward at zero yaw")
    var yaw_for_direction := player.get_node("CameraYaw") as Node3D
    yaw_for_direction.rotation.y = PI / 2.0
    var turned_forward: Vector3 = player.call("calculate_move_direction", Vector2(0.0, -1.0))
    _expect(turned_forward.is_equal_approx(Vector3.LEFT), "Forward input must rotate with camera yaw")
    yaw_for_direction.rotation.y = 0.0
    var diagonal: Vector3 = player.call("calculate_move_direction", Vector2(1.0, -1.0))
    _expect(is_equal_approx(diagonal.length(), 1.0), "Diagonal movement direction must be normalized")
    var min_pitch: float = player.call("clamp_pitch_radians", -PI)
    var max_pitch: float = player.call("clamp_pitch_radians", PI)
    _expect(is_equal_approx(min_pitch, deg_to_rad(-60.0)), "Pitch must clamp to -60 degrees")
    _expect(is_equal_approx(max_pitch, deg_to_rad(45.0)), "Pitch must clamp to 45 degrees")
    var spring_arm := player.get_node("CameraYaw/CameraPitch/SpringArm3D") as SpringArm3D
    _expect(is_equal_approx(spring_arm.spring_length, 4.5), "Spring arm length must be 4.5")
    _expect(spring_arm.collision_mask == 1, "Spring arm must collide with physics layer 1")
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    var yaw := player.get_node("CameraYaw") as Node3D
    var pitch := player.get_node("CameraYaw/CameraPitch") as Node3D
    var yaw_before := yaw.rotation.y
    var pitch_before := pitch.rotation.x
    var motion := InputEventMouseMotion.new()
    motion.relative = Vector2(100.0, 50.0)
    player.call("_unhandled_input", motion)
    _expect(is_equal_approx(yaw.rotation.y, yaw_before), "Released mouse motion must not change yaw")
    _expect(is_equal_approx(pitch.rotation.x, pitch_before), "Released mouse motion must not change pitch")
    if DisplayServer.get_name() != "headless":
        var click := InputEventMouseButton.new()
        click.button_index = MOUSE_BUTTON_LEFT
        click.pressed = true
        player.call("_unhandled_input", click)
        _expect(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Left click must recapture the mouse")
        var escape := InputEventKey.new()
        escape.keycode = KEY_ESCAPE
        escape.pressed = true
        player.call("_unhandled_input", escape)
        _expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Escape must release the mouse")
    player.queue_free()
    await process_frame

func _test_main_scene_contract() -> void:
    _expect(
        ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main/main.tscn",
        "project.godot must point to the Stage 0 main scene"
    )
    var packed_main := load("res://scenes/main/main.tscn") as PackedScene
    _expect(packed_main != null, "main.tscn must load as a PackedScene")
    if packed_main == null:
        return
    var main = packed_main.instantiate()
    root.add_child(main)
    await process_frame
    var environment := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
    var light := main.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
    var ground := main.get_node_or_null("Ground") as StaticBody3D
    var ground_mesh_node := main.get_node_or_null("Ground/MeshInstance3D") as MeshInstance3D
    var ground_shape_node := main.get_node_or_null("Ground/CollisionShape3D") as CollisionShape3D
    var player := main.get_node_or_null("Player") as CharacterBody3D
    _expect(environment != null and environment.environment != null, "WorldEnvironment must have an Environment")
    _expect(light != null and light.shadow_enabled, "DirectionalLight3D must cast shadows")
    _expect(ground != null and is_equal_approx(ground.position.y, -0.25), "Ground body must put its top at y = 0")
    _expect(player != null and is_equal_approx(player.position.y, 0.9), "Player capsule must start on the ground")
    var ground_mesh: BoxMesh = null
    var ground_shape: BoxShape3D = null
    if ground_mesh_node != null:
        ground_mesh = ground_mesh_node.mesh as BoxMesh
    if ground_shape_node != null:
        ground_shape = ground_shape_node.shape as BoxShape3D
    _expect(ground_mesh != null and ground_mesh.size.is_equal_approx(Vector3(24.0, 0.5, 24.0)), "Ground mesh must be 24 x 0.5 x 24")
    _expect(ground_shape != null and ground_shape.size.is_equal_approx(Vector3(24.0, 0.5, 24.0)), "Ground collision must match the mesh")
    main.queue_free()
    await process_frame
