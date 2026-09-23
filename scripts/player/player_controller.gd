extends CharacterBody3D

const MOVE_SPEED := 5.0
const ACCELERATION := 20.0
const DECELERATION := 24.0
const MOUSE_SENSITIVITY := 0.0025
const MIN_PITCH := deg_to_rad(-60.0)
const MAX_PITCH := deg_to_rad(45.0)

@onready var camera_yaw: Node3D = $CameraYaw
@onready var camera_pitch: Node3D = $CameraYaw/CameraPitch
@onready var spring_arm: SpringArm3D = $CameraYaw/CameraPitch/SpringArm3D
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    spring_arm.add_excluded_object(get_rid())

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        get_viewport().set_input_as_handled()
        return
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        get_viewport().set_input_as_handled()
        return
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        camera_yaw.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
        camera_pitch.rotation.x = clamp_pitch_radians(camera_pitch.rotation.x - event.relative.y * MOUSE_SENSITIVITY)

func _physics_process(delta: float) -> void:
    if is_on_floor():
        velocity.y = 0.0
    else:
        velocity.y -= gravity * delta
    var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    var direction := calculate_move_direction(input_vector)
    var target_velocity := direction * MOVE_SPEED
    var change_rate := ACCELERATION if not direction.is_zero_approx() else DECELERATION
    velocity.x = move_toward(velocity.x, target_velocity.x, change_rate * delta)
    velocity.z = move_toward(velocity.z, target_velocity.z, change_rate * delta)
    move_and_slide()

func calculate_move_direction(input_vector: Vector2) -> Vector3:
    var forward := -camera_yaw.global_transform.basis.z
    var right := camera_yaw.global_transform.basis.x
    forward.y = 0.0
    right.y = 0.0
    forward = forward.normalized()
    right = right.normalized()
    var direction := right * input_vector.x + forward * -input_vector.y
    if direction.length_squared() > 1.0:
        direction = direction.normalized()
    return direction

func clamp_pitch_radians(angle: float) -> float:
    return clampf(angle, MIN_PITCH, MAX_PITCH)
