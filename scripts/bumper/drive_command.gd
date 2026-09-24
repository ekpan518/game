class_name DriveCommand
extends RefCounted

var throttle: float
var steering: float

static func create(raw_throttle: float, raw_steering: float) -> DriveCommand:
	var command := DriveCommand.new()
	command.throttle = clampf(raw_throttle, -1.0, 1.0)
	command.steering = clampf(raw_steering, -1.0, 1.0)
	return command
