class_name DriveCommand
extends RefCounted

const DRIVE_COMMAND_SCRIPT = preload("res://scripts/bumper/drive_command.gd")

var throttle: float
var steering: float

static func create(raw_throttle: float, raw_steering: float) -> RefCounted:
	var command = DRIVE_COMMAND_SCRIPT.new()
	command.throttle = clampf(raw_throttle, -1.0, 1.0)
	command.steering = clampf(raw_steering, -1.0, 1.0)
	return command
