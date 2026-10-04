extends SceneTree
## Future smoke test of actual game controller, without desktop automation.
## Run with --qa to disable persistent settings and generated audio.
const Rules = preload("res://scripts/rules.gd")
var failures: Array = []
var game: Variant = null

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)

func run_checks() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.qa_mode = true
	root.add_child(game)
	await process_frame
	game.load_level(0)
	game.commit_turn()
	check(game.state.turn == 0, "Tutorial rejects an incorrect initial pulse")
	game.load_level(3)
	var snapshot: String = JSON.stringify(game.state)
	game.toggle_width()
	game.selected = 3
	game.refresh()
	check(JSON.stringify(game.state) == snapshot, "Aim and width are free")
	game.selected = 0
	game.beam_width = 1
	game.refresh()
	var predicted: String = JSON.stringify(game.preview.state)
	game.commit_button.emit_signal("pressed")
	check(JSON.stringify(game.state) == predicted, "Confirm button commits exact preview")
	check(game.history.size() == 2, "Commit stores full history")
	game.undo_button.emit_signal("pressed")
	check(JSON.stringify(game.state) == snapshot, "Undo restores initial state and shadows")
	game.choose_wait()
	check(game.state.turn == 0, "Selecting wait does not advance time")
	game.commit_turn()
	check(game.state.turn == 1 and game.state.shadows == [0, 0], "Wait advances exactly once without new shadow")
	game.restart()
	game.show_modal("pause")
	game.commit_turn()
	check(game.state.turn == 0, "Pause blocks the turn")
	game.close_modal()
	game.capture_set(3, ["N0", "N4", "N1", "W2", "W2", "N4"])
	check(Rules.won(game.scenario, game.state), "Native controller reaches verified victory")
	game.show_result()
	check(game.modal_kind == "win", "Victory opens result UI")
	game.undo()
	check(game.state.turn == 5 and game.modal_kind.is_empty(), "Undo leaves victory and restores turn five")
	game.capture_set(3, ["N0", "N1", "N2", "W3"])
	game.selected = 3
	game.beam_width = 2
	game.refresh()
	check(game.preview.lost == ["C"], "Preview marks the exact losing ship")
	game.capture_set(3, ["N0", "N1", "N2", "W3", "W3"])
	game.show_result()
	check(game.modal_kind == "loss", "Loss opens result UI")
	game.undo()
	check(game.state.turn == 4 and not game.state.positions.has(-2), "Undo restores a lost ship")
	print(JSON.stringify({"session_failures": failures, "checks": 14}))
	quit(0 if failures.is_empty() else 1)
