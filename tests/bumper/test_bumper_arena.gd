extends SceneTree

const RULES_SUITE = preload("res://tests/bumper/suites/test_bumper_rules.gd")
var scope := "all"

func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scope="):
			scope = argument.trim_prefix("--scope=")
	call_deferred("_run")

func _run() -> void:
	if scope not in ["rules", "all"]:
		push_error("[FAIL] Unsupported Bumper Arena test scope: %s." % scope)
		quit(1)
		return
	var suite_scripts: Array[Script] = [RULES_SUITE]
	var failures: Array[String] = []
	for suite_script in suite_scripts:
		var suite_failures: Array[String] = await suite_script.new().run(self)
		failures.append_array(suite_failures)
	if failures.is_empty():
		print("[PASS] Godot Bumper Arena %s checks passed." % scope)
		quit(0)
		return
	for failure in failures:
		push_error("[FAIL] %s" % failure)
	quit(1)
