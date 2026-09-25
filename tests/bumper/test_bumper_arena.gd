extends SceneTree

const RULES_SUITE = preload("res://tests/bumper/suites/test_bumper_rules.gd")
const VEHICLE_SUITE = preload("res://tests/bumper/suites/test_bumper_car.gd")
const MATCH_SUITE = preload("res://tests/bumper/suites/test_match_controller.gd")
const AI_SUITE = preload("res://tests/bumper/suites/test_ai_driver.gd")
var scope := "all"

func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scope="):
			scope = argument.trim_prefix("--scope=")
	call_deferred("_run")

func _run() -> void:
	if scope not in ["rules", "vehicle", "match", "ai", "all"]:
		push_error("[FAIL] Unsupported Bumper Arena test scope: %s." % scope)
		quit(1)
		return
	var suite_scripts: Array[Script] = []
	if scope in ["rules", "all"]:
		suite_scripts.append(RULES_SUITE)
	if scope in ["vehicle", "all"]:
		suite_scripts.append(VEHICLE_SUITE)
	if scope in ["match", "all"]:
		suite_scripts.append(MATCH_SUITE)
	if scope in ["ai", "all"]:
		suite_scripts.append(AI_SUITE)
	var failures: Array[String] = []
	for suite_script in suite_scripts:
		if not suite_script.can_instantiate():
			failures.append("Suite script failed to compile: %s" % suite_script.resource_path)
			continue
		var suite_failures: Array[String] = await suite_script.new().run(self)
		failures.append_array(suite_failures)
	if failures.is_empty():
		print("[PASS] Godot Bumper Arena %s checks passed." % scope)
		quit(0)
		return
	for failure in failures:
		push_error("[FAIL] %s" % failure)
	quit(1)
