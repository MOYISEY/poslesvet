extends SceneTree
## Future invocation: Godot --headless --path . --script res://tests/verify_core.gd
const Rules = preload("res://scripts/rules.gd")
var failures: Array = []

func _initialize() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures.json"))
	if not data is Dictionary:
		printerr("Fixtures could not be read")
		quit(2)
		return
	for case in data.initials:
		check(Rules.initial(case.scenario), case.expected, "initial/" + str(case.scenario.name))
	for case in data.cases:
		var untouched: Dictionary = case.state.duplicate(true)
		var result: Dictionary = Rules.advance(case.scenario, case.state, case.action, case.shadows_enabled)
		check(result, case.expected, case.label)
		check(case.state, untouched, str(case.label) + "/pure")
		check(Rules.advance(case.scenario, case.state, case.action, case.shadows_enabled), result, str(case.label) + "/repeat")
	var report: Dictionary = {"transitions": data.cases.size(), "initial_states": data.initials.size(), "failures": failures}
	var output: String = "user://core-verification.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			output = arg.trim_prefix("--report=")
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write report: ", output)
		quit(2)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func check(actual: Variant, expected: Variant, label: String) -> void:
	if not equivalent(actual, expected):
		failures.append({"label": label, "actual": actual, "expected": expected})

func equivalent(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not equivalent(a[key], b[key]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not equivalent(a[i], b[i]):
				return false
		return true
	return a == b
