class_name DriverController
extends Node

func get_command(_car: BumperCar, _delta: float) -> DriveCommand:
	return DriveCommand.create(0.0, 0.0)
