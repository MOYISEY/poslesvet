extends RefCounted
## Engine-supported input injection. This is NOT a human or physical-mouse test.
const Rules = preload("res://scripts/rules.gd")
const Sound = preload("res://scripts/sound.gd")
var game: Variant
var failures: Array = []
var checks: int = 0
var windows: Array = []

func check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("INPUT CHECK FAILED: ", label)
	return condition

func key(code: int, logical_override: int = 0) -> void:
	var down: InputEventKey = InputEventKey.new()
	down.keycode = logical_override if logical_override != 0 else code
	down.physical_keycode = code if logical_override != 0 else 0
	down.pressed = true
	Input.parse_input_event(down)
	await game.get_tree().process_frame
	var up: InputEventKey = InputEventKey.new()
	up.keycode = logical_override if logical_override != 0 else code
	up.physical_keycode = code if logical_override != 0 else 0
	Input.parse_input_event(up)
	await game.get_tree().process_frame

func mouse_click(at: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	game.get_viewport().push_input(motion, true)
	await game.get_tree().process_frame
	for pressed in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		game.get_viewport().push_input(event, true)
		await game.get_tree().process_frame

func settle() -> void:
	await game.get_tree().create_timer(0.72).timeout
	await game.get_tree().process_frame

func select_action(label: String) -> void:
	if label == "wait":
		if not game.wait_mode: await key(KEY_W)
		return
	if game.wait_mode: await key(KEY_W)
	var width: int = 1 if label.begins_with("N") else 2
	if game.beam_width != width: await key(KEY_TAB)
	await key(KEY_1 + int(label.substr(1)))

func play_path(path: Array) -> bool:
	for label in path:
		await select_action(label)
		var before: int = int(game.state.turn)
		await key(KEY_SPACE)
		if not check(int(game.state.turn) == before + 1, "One input advances one turn: " + label):
			return false
		await settle()
	return true

func modal_button(starts_with: String) -> Button:
	for node in game.modal_content.get_children():
		if node is Button and node.text.begins_with(starts_with): return node
	return null

func capture(name: String) -> void:
	check(await game.capture_frame(name), "Viewport saved: " + name)

func run(instance: Node) -> void:
	game = instance
	if game.capture_dir.is_empty():
		game.capture_dir = ProjectSettings.globalize_path("user://input-test")
	DirAccess.make_dir_recursive_absolute(game.capture_dir)
	await game.get_tree().process_frame
	var initial_text: String = JSON.stringify(game.state)
	await key(KEY_TAB)
	check(game.beam_width == 2 and JSON.stringify(game.state) == initial_text, "Tab changes width without spending a turn")
	await key(KEY_1)
	await key(KEY_SPACE)
	await key(KEY_SPACE)
	check(game.state.turn == 1, "Repeated Space is blocked during movement")
	await settle()
	if not await play_path(["W2", "W4", "W6"]): finish(); return
	if not check(game.modal_kind == "win", "Interactive tutorial reaches victory"): finish(); return
	await key(KEY_ESCAPE)
	await key(KEY_ENTER)
	check(game.modal_kind == "win", "Result screen reopens after viewing the bay")
	var next: Button = modal_button("Начать первую")
	if not check(next != null, "Tutorial provides a working next-night button"): finish(); return
	await mouse_click(next.get_global_rect().get_center())
	if not check(game.stage == 1 and game.state.turn == 0, "GUI click enters first night"): finish(); return
	await key(KEY_ESCAPE)
	await key(KEY_SPACE)
	check(game.modal_kind == "pause" and game.state.turn == 0, "Pause blocks keyboard confirmation")
	var slider: HSlider
	for child in game.modal_content.get_children():
		if child is HSlider: slider = child
	if check(slider != null, "Volume slider exists"):
		await mouse_click(slider.get_global_rect().position + Vector2(slider.size.x * 0.25, slider.size.y * 0.5))
		check(game.volume > 0.1 and game.volume < 0.4, "Volume changes through GUI mouse event")
		await key(KEY_HOME)
		check(game.volume == 0.0 and AudioServer.is_bus_mute(0), "Slider Home mutes audio")
	await key(KEY_ESCAPE)
	await key(KEY_W)
	check(game.state.turn == 0 and game.wait_mode, "W selects wait without confirming")
	await key(KEY_SPACE)
	await settle()
	check(game.state.turn == 1 and game.state.shadows == [0, 0], "Wait creates no shadow")
	await key(KEY_Z, 0x042F)
	check(game.state.turn == 0, "Physical Z restores state with Cyrillic keyboard layout")
	await key(KEY_H)
	check(game.modal_kind == "help", "Help keyboard shortcut")
	await capture("qa_help")
	await key(KEY_ESCAPE)
	var paths: Array = [[], ["N1", "N0", "N2", "N3", "N2"],
		["N0", "wait", "W1", "N4", "N0"],
		["N0", "N4", "N1", "W2", "W2", "N4"],
		["N3", "W0", "W2", "W4", "N6", "W7", "W4", "N7", "N2", "N6", "W0", "W4", "W2"]]
	for night in range(1, 5):
		check(game.stage == night, "Campaign order " + str(night))
		if not await play_path(paths[night]): finish(); return
		if not check(game.modal_kind == "win" and Rules.won(game.scenario, game.state), "Night won via input " + str(night)): finish(); return
		await capture("qa_night_%d_victory" % night)
		if night < 4:
			next = modal_button("Следующая")
			if not check(next != null, "Next night button " + str(night)): finish(); return
			await mouse_click(next.get_global_rect().get_center())
	# Exercise defeat/undo/restart and actual GUI confirmation in the diagnostic night.
	game.show_modal("levels")
	await game.get_tree().process_frame
	var bonus: Button = modal_button("Прилив")
	if check(bonus != null and not bonus.disabled, "Bonus tide is unlocked after tutorial"):
		await mouse_click(bonus.get_global_rect().get_center())
		check(game.stage == 5, "Level selection enters tide bonus")
	game.progress_path = game.capture_dir.path_join("qa-save.json")
	game.persist_qa = true
	if not await play_path(["N4", "N0", "N1"]): finish(); return
	var stored: Dictionary = game.Progress.read_save(game.progress_path, game.scenarios)
	check(not stored.is_empty() and stored.history.back() == game.state, "Exported controller saves complete tide state")
	game.load_level(0)
	game.restore_progress(stored)
	check(game.state.turn == 3 and game.stage == 5, "Exported controller continues saved bonus")
	await key(KEY_Z)
	check(game.state.turn == 2 and game.state.positions == [0, 1, 1], "Loaded game can undo tide")
	if not await play_path(["N1", "W2", "W3"]): finish(); return
	check(game.modal_kind == "win" and game.completed.has(5), "Tide night completes and records progress")
	game.persist_qa = false
	await capture("qa_tide_victory")
	game.load_level(3)
	var details: LinkButton
	for child in game.ui.get_children():
		if child is LinkButton: details = child
	if check(details != null, "Compact briefing provides expandable rules link"):
		await mouse_click(details.get_global_rect().get_center())
		check(game.modal_kind == "help", "Rules link opens help through GUI click")
		await key(KEY_ESCAPE)
	for sector in range(8):
		await mouse_click(game.world.polar(263.0, game.world.angle_for(sector)))
		check(game.selected == sector and game.state.turn == 0, "Perspective bay mouse aim without spending turn: " + str(sector))
	await mouse_click(game.world.polar(263.0, game.world.angle_for(0)))
	await mouse_click(game.commit_button.get_global_rect().get_center())
	await mouse_click(game.commit_button.get_global_rect().get_center())
	check(game.state.turn == 1, "Repeated GUI confirmation is blocked during movement")
	await key(KEY_ESCAPE)
	var paused_animation: float = game.animation
	await game.get_tree().create_timer(0.2).timeout
	check(is_equal_approx(game.animation, paused_animation), "Pause freezes movement animation")
	await key(KEY_ESCAPE)
	await settle()
	if not await play_path(["N1", "N2", "W3"]): finish(); return
	await select_action("W3")
	check(game.preview.lost == ["C"], "Preview identifies future loss before confirmation")
	await capture("qa_loss_preview")
	await key(KEY_SPACE)
	await settle()
	check(game.modal_kind == "loss", "Loss screen reached via input")
	await key(KEY_Z)
	check(game.modal_kind.is_empty() and game.state.turn == 4 and not game.state.positions.has(-2), "Undo revives lost ship through input")
	await key(KEY_R)
	check(game.state.turn == 0 and game.history.size() == 1, "Restart clears history and shadows")
	for size in [Vector2i(960, 540), Vector2i(1111, 625), Vector2i(1537, 865), Vector2i(1366, 768)]:
		game.get_window().size = size
		await game.get_tree().create_timer(0.2).timeout
		var actual: Vector2i = game.get_window().size
		windows.append({"requested": [size.x, size.y], "actual": [actual.x, actual.y], "scale_x": float(actual.x) / 1366.0})
		await capture("qa_window_%dx%d" % [actual.x, actual.y])
		await mouse_click(game.width_button.get_global_rect().get_center())
		check(game.beam_width == 2, "GUI width button at size " + str(actual))
		await mouse_click(game.width_button.get_global_rect().get_center())
		check(game.beam_width == 1, "GUI width toggles back at size " + str(actual))
	await key(KEY_F11)
	await game.get_tree().create_timer(0.2).timeout
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "F11 enters fullscreen")
	await key(KEY_F11)
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "F11 returns to windowed")
	var audio: Node = Sound.new()
	game.add_child(audio)
	check(audio.sea.playing and audio.sea.stream.data.size() == 176400, "Synthesized ambience stream plays")
	audio.play_cue("win")
	check(audio.voice.playing and audio.voice.stream.data.size() > 0, "Synthesized cue stream plays")
	audio.sea.stop()
	audio.voice.stop()
	audio.queue_free()
	await game.get_tree().process_frame
	finish()

func finish() -> void:
	var report: Dictionary = {"checks": checks, "failures": failures, "window_tests": windows,
		"screen_dpi_reported": DisplayServer.screen_get_dpi(),
		"input_method": "Input.parse_input_event for keys; Viewport.push_input for GUI mouse events; no physical interaction",
		"editor_binary": OS.has_feature("editor"), "engine": Engine.get_version_info(),
		"human_playtest": false, "system_dpi_changed": false}
	var file: FileAccess = FileAccess.open(game.capture_dir.path_join("input-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print(JSON.stringify(report))
	game.get_tree().quit(0 if failures.is_empty() else 1)
