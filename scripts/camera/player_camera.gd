extends Node3D

const MOUSE_SENSITIVITY := 0.0025
const MIN_PITCH := deg_to_rad(-60.0)
const MAX_PITCH := deg_to_rad(45.0)

@onready var camera_pitch: Node3D = $CameraPitch
@onready var spring_arm: SpringArm3D = $CameraPitch/SpringArm3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var car := get_parent() as CollisionObject3D
	if car != null:
		spring_arm.add_excluded_object(car.get_rid())

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
		apply_captured_mouse_motion(event.relative)

func apply_captured_mouse_motion(relative: Vector2) -> void:
	rotate_y(-relative.x * MOUSE_SENSITIVITY)
	camera_pitch.rotation.x = clamp_pitch_radians(camera_pitch.rotation.x - relative.y * MOUSE_SENSITIVITY)

func clamp_pitch_radians(angle: float) -> float:
	return clampf(angle, MIN_PITCH, MAX_PITCH)
