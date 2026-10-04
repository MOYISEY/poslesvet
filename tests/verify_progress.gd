extends SceneTree
const Progress = preload("res://scripts/progress.gd")
const Rules = preload("res://scripts/rules.gd")
var checks: int = 0
var failures: Array = []
var path: String = "user://qa-progress-only.json"

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func write_text(target: String, value: String) -> void:
	var f: FileAccess = FileAccess.open(target, FileAccess.WRITE)
	f.store_string(value)
	f.close()

func run_checks() -> void:
	var scenarios: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/scenarios.json"))
	var actions: Array = [{"sector": 4, "width": 1}, {"sector": 0, "width": 1}, {"sector": 1, "width": 1}]
	var payload: Dictionary = {"version": 1, "completed": [0, 1], "run": {"stage": 5, "actions": actions}}
	var valid: String = JSON.stringify(payload)
	var data: Dictionary = Progress.decode(valid, scenarios)
	check(not data.is_empty() and data.history.size() == 4, "Save replays all history across tide")
	check(data.history.back().positions == [1, 2, 2], "Replay reconstructs exact tide positions")
	check(data.history.back().shadows == [1, 2], "Replay reconstructs exact shadows")
	for broken in ["", "{", "null", "[]", "true", "{}", '{"version":9}', '{"version":1,"completed":[],"run":null}']:
		check(Progress.decode(broken, scenarios).is_empty(), "Reject malformed root: " + broken)
	for change in [{"stage": -1}, {"stage": 6}, {"stage": 0.5}, {"stage": "5"}, {"actions": [null]}, {"actions": [{"width": 3, "sector": 0}]}, {"actions": [{"width": 1, "sector": 8}]}, {"actions": [{"width": 0.5, "sector": 0}]}]:
		var bad: Dictionary = payload.duplicate(true)
		bad.run.merge(change, true)
		check(Progress.decode(JSON.stringify(bad), scenarios).is_empty(), "Reject invalid command or stage " + str(change))
	var bad_completed: Dictionary = payload.duplicate(true)
	bad_completed.completed = [0, 99]
	check(Progress.decode(JSON.stringify(bad_completed), scenarios).is_empty(), "Reject out-of-range completed night")
	var bad_tutorial: Dictionary = payload.duplicate(true)
	bad_tutorial.run = {"stage": 0, "actions": [{"sector": 0, "width": 0}]}
	check(Progress.decode(JSON.stringify(bad_tutorial), scenarios).is_empty(), "Reject impossible tutorial history")
	var after_end: Dictionary = payload.duplicate(true)
	after_end.run = {"stage": 0, "actions": [{"sector": 0,"width": 2}, {"sector": 2,"width": 2}, {"sector": 4,"width": 2}, {"sector": 6,"width": 2}, {"sector": 0,"width": 0}]}
	check(Progress.decode(JSON.stringify(after_end), scenarios).is_empty(), "Reject commands after victory")
	check(Progress.write_save(path, [0, 1], 5, actions) == OK, "Write local save")
	check(Progress.read_save(path, scenarios).run.actions == actions, "Read saved commands")
	check(Progress.write_save(path, [0, 1], 5, actions.slice(0, 2)) == OK, "Atomic replacement retains backup")
	write_text(path, "{truncated")
	var recovered: Dictionary = Progress.read_save(path, scenarios)
	check(recovered.recovered and recovered.run.actions == actions, "Recover damaged primary from valid backup")
	write_text(path + ".bak", "damaged too")
	check(Progress.read_save(path, scenarios).is_empty(), "Corrupt primary and backup produce safe new game")
	var game: Variant = load("res://scenes/main.tscn").instantiate()
	game.qa_mode = true
	root.add_child(game)
	await process_frame
	game.restore_progress(data)
	check(game.stage == 5 and game.state == data.history.back(), "Controller restores saved night and exact state")
	check(game.completed == [0, 1] and game.unlocked(5) and not game.unlocked(4), "Completion unlocks bonus while preserving campaign gates")
	game.undo()
	check(game.state == data.history[2] and game.action_history.size() == 2, "Undo after load restores pre-tide state")
	game.selected = 1
	game.beam_width = 1
	game.commit_turn()
	check(game.state == data.history.back(), "Replaying after undo matches saved tide")
	game.queue_free()
	for target in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(target): DirAccess.remove_absolute(target)
	var report: Dictionary = {"checks": checks, "failures": failures}
	write_text("res://tests/progress-report.json", JSON.stringify(report, "  "))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
