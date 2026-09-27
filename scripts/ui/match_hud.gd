class_name MatchHUD
extends CanvasLayer

signal restart_requested

var _restart_latched := false
var _cue_priority := -1
var _cue_queue: Array[Dictionary] = []
var _cue_tween: Tween

@onready var _alive_label: Label = $AliveLabel
@onready var _power_label: Label = $PowerLabel
@onready var _result_panel: Control = $ResultPanel
@onready var _result_label: Label = $ResultPanel/VBoxContainer/ResultLabel
@onready var _restart_button: Button = $ResultPanel/VBoxContainer/RestartButton
@onready var _gameplay_cue: Label = $GameplayCue

func _ready() -> void:
	if not _restart_button.pressed.is_connected(request_restart):
		_restart_button.pressed.connect(request_restart)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER:
		var viewport := get_viewport()
		if request_restart():
			if is_instance_valid(viewport):
				viewport.set_input_as_handled()

func set_alive_count(alive: int, total: int) -> void:
	_alive_label.text = "剩余车辆：%d/%d" % [alive, total]

func set_power_stacks(stacks: int) -> void:
	_power_label.text = "强化：%d/3" % BumperRules.clamp_stacks(stacks)

func show_result(result: StringName) -> void:
	clear_gameplay_cues()
	_result_label.text = "胜利！" if result == &"victory" else "失败"
	_result_panel.show()

func show_gameplay_cue(text: String, priority: int) -> void:
	if _result_panel.visible or text.is_empty():
		return
	if _gameplay_cue.visible:
		if _gameplay_cue.text == text:
			return
		if priority <= _cue_priority:
			_queue_gameplay_cue(text, priority)
			return
		_queue_gameplay_cue(_gameplay_cue.text, _cue_priority)
	if _cue_tween != null:
		_cue_tween.kill()
	_cue_priority = priority
	_gameplay_cue.text = text
	_gameplay_cue.show()
	_cue_tween = create_tween().set_ignore_time_scale(true)
	_cue_tween.tween_interval(0.85)
	_cue_tween.tween_callback(_advance_gameplay_cue)

func _queue_gameplay_cue(text: String, priority: int) -> void:
	for queued in _cue_queue:
		if queued.text == text:
			return
	_cue_queue.append({"text": text, "priority": priority})
	_cue_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.priority > b.priority)
	if _cue_queue.size() > 3:
		_cue_queue.resize(3)

func clear_gameplay_cues() -> void:
	if _cue_tween != null:
		_cue_tween.kill()
		_cue_tween = null
	_cue_queue.clear()
	_cue_priority = -1
	_gameplay_cue.hide()

func _advance_gameplay_cue() -> void:
	_cue_tween = null
	_gameplay_cue.hide()
	_cue_priority = -1
	if not _cue_queue.is_empty():
		var next_cue: Dictionary = _cue_queue.pop_front()
		show_gameplay_cue(next_cue.text, next_cue.priority)

func request_restart() -> bool:
	if _result_panel == null or not _result_panel.visible or _restart_latched:
		return false
	_restart_latched = true
	restart_requested.emit()
	return true
