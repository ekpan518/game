class_name MatchHUD
extends CanvasLayer

signal restart_requested

var _restart_latched := false

@onready var _alive_label: Label = $AliveLabel
@onready var _power_label: Label = $PowerLabel
@onready var _result_panel: Control = $ResultPanel
@onready var _result_label: Label = $ResultPanel/VBoxContainer/ResultLabel
@onready var _restart_button: Button = $ResultPanel/VBoxContainer/RestartButton

func _ready() -> void:
	if not _restart_button.pressed.is_connected(request_restart):
		_restart_button.pressed.connect(request_restart)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER:
		if request_restart():
			get_viewport().set_input_as_handled()

func set_alive_count(alive: int, total: int) -> void:
	_alive_label.text = "剩余车辆：%d/%d" % [alive, total]

func set_power_stacks(stacks: int) -> void:
	_power_label.text = "强化：%d/3" % BumperRules.clamp_stacks(stacks)

func show_result(result: StringName) -> void:
	_result_label.text = "胜利！" if result == &"victory" else "失败"
	_result_panel.show()

func request_restart() -> bool:
	if _restart_latched:
		return false
	_restart_latched = true
	restart_requested.emit()
	return true
