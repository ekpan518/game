class_name HumanDriver
extends DriverController

func get_command(_car: BumperCar, _delta: float) -> DriveCommand:
	return DriveCommand.create(
		Input.get_axis("drive_back", "drive_forward"),
		Input.get_axis("drive_left", "drive_right")
	)
