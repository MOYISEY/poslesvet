extends Node2D
const Rules = preload("res://scripts/rules.gd")
const World = preload("res://scripts/world.gd")
const Sound = preload("res://scripts/sound.gd")
const InputHarness = preload("res://tests/input_harness.gd")
const Progress = preload("res://scripts/progress.gd")
const MOVE_DURATION: float = 0.62
const SIZE: Vector2 = Vector2(1366, 768)
const AMBER: Color = Color("f3c278")
const PALE: Color = Color("e5eadf")
const MUTED: Color = Color("8eaab9")

var scenario: Dictionary = {}
var state: Dictionary = {}
var preview: Dictionary = {}
var scenarios: Array = []
var history: Array = []
var previous_positions: Array = []
var last_outcome: Dictionary = {}
var selected: int = 0
var beam_width: int = 1
var wait_mode: bool = false
var stage: int = 0
var clock: float = 0.0
var animation: float = 0.0
var modal_kind: String = ""
var capture_dir: String = ""
var qa_mode: bool = false
var input_test: bool = false
var world: World
var sound: Sound
var ui: Control
var modal: Control
var modal_card: PanelContainer
var modal_content: VBoxContainer
var heading: Label
var counter: Label
var instruction: Label
var forecast: Label
var status: Label
var shadow_labels: Array = []
var commit_button: Button
var width_button: Button
var wait_button: Button
var undo_button: Button
var volume: float = 0.45
var settings: ConfigFile = ConfigFile.new()
var completed: Array = []
var action_history: Array = []
var progress_path: String = "user://progress-v1.json"
var suspend_save: bool = true
var progress_notice: String = "Ход и пройденные вахты сохраняются автоматически."
var effect: float = 0.0
var tide_label: Label
var browser_probe: bool = false
var persist_qa: bool = false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="): progress_path = arg.trim_prefix("--profile=")
		if arg.begins_with("--capture-dir="):
			capture_dir = arg.trim_prefix("--capture-dir=")
		if arg == "--qa":
			qa_mode = true
		if arg == "--input-test":
			input_test = true
			qa_mode = true
	qa_mode = qa_mode or not capture_dir.is_empty()
	if OS.has_feature("web"):
		browser_probe = bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('qa')"))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_min_size(Vector2i(960, 540))
	scenarios = JSON.parse_string(FileAccess.get_file_as_string("res://tests/scenarios.json"))
	if scenarios.size() < 4:
		push_error("Scenario data missing")
		get_tree().quit(2)
		return
	world = World.new()
	world.game = self
	add_child(world)
	build_ui()
	if not qa_mode:
		settings.load("user://settings.cfg")
		volume = float(settings.get_value("audio", "volume", 0.45))
		set_volume(volume, false)
		if not OS.has_feature("web"):
			set_fullscreen(bool(settings.get_value("window", "fullscreen", false)), false)
		sound = Sound.new()
		add_child(sound)
	load_level(0)
	if not qa_mode:
		var stored: Dictionary = Progress.read_save(progress_path, scenarios)
		if not stored.is_empty():
			restore_progress(stored)
			if stored.recovered: progress_notice = "Сохранение восстановлено из резервной копии."
		elif FileAccess.file_exists(progress_path):
			progress_notice = "Сохранение не удалось прочитать. Можно начать новую вахту."
		show_modal("welcome")
	suspend_save = false
	if input_test:
		call_deferred("run_input_tests")
	elif not capture_dir.is_empty():
		call_deferred("capture_suite")

func run_input_tests() -> void:
	var harness: RefCounted = InputHarness.new()
	await harness.run(self)

func _process(delta: float) -> void:
	if modal_kind not in ["pause", "help", "welcome", "levels"]:
		if not qa_mode:
			clock += delta
		if animation > 0.0:
			animation = maxf(0.0, animation - delta)
			if animation == 0.0:
				refresh()
				if Rules.terminal(scenario, state):
					show_result()
		effect = maxf(0.0, effect - delta)
	world.queue_redraw()
	if browser_probe: update_browser_probe()

func panel_style(color: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

func label_at(text: String, at: Vector2, bounds: Vector2, size: int = 18, color: Color = PALE) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.position = at
	label.size = bounds
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(label)
	return label

func button(text: String, callback: Callable, primary: bool = false) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(130, 48)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", Color("102534") if primary else PALE)
	b.add_theme_color_override("font_hover_color", Color("102534") if primary else Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color("102534") if primary else Color.WHITE)
	b.add_theme_stylebox_override("normal", panel_style(AMBER if primary else Color("102c40"), Color("395367")))
	b.add_theme_stylebox_override("hover", panel_style(Color("ffdda2") if primary else Color("204359"), AMBER))
	b.add_theme_stylebox_override("pressed", panel_style(Color("d6a45b") if primary else Color("0a1d2e"), AMBER))
	b.add_theme_stylebox_override("disabled", panel_style(Color("152a38"), Color("263b48")))
	b.add_theme_stylebox_override("focus", panel_style(Color(0, 0, 0, 0), AMBER))
	b.pressed.connect(callback)
	return b

func place_button(text: String, at: Vector2, bounds: Vector2, callback: Callable, primary: bool = false) -> Button:
	var b: Button = button(text, callback, primary)
	b.position = at
	b.size = bounds
	ui.add_child(b)
	return b

func build_ui() -> void:
	ui = Control.new()
	ui.size = SIZE
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	label_at("ПОСЛЕСВЕТ", Vector2(40, 27), Vector2(440, 48), 32, AMBER)
	heading = label_at("", Vector2(42, 73), Vector2(630, 34), 17, MUTED)
	counter = label_at("", Vector2(1080, 31), Vector2(244, 40), 23)
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	instruction = label_at("", Vector2(42, 130), Vector2(282, 82), 17, MUTED)
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction.add_theme_constant_override("line_spacing", 3)
	var details: LinkButton = LinkButton.new()
	details.text = "Правила · H  ›"
	details.position = Vector2(42, 221)
	details.add_theme_font_size_override("font_size", 16)
	details.add_theme_color_override("font_color", AMBER)
	details.focus_mode = Control.FOCUS_NONE
	details.pressed.connect(func(): show_modal("help"))
	ui.add_child(details)
	tide_label = label_at("", Vector2(42, 271), Vector2(264, 175), 17, Color("91ddd5"))
	tide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shadow_labels.append(label_at("", Vector2(1050, 176), Vector2(275, 90), 17, Color("f2a4a8")))
	shadow_labels.append(label_at("", Vector2(1050, 285), Vector2(275, 90), 17, Color("b7a1df")))
	for label in shadow_labels:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status = label_at("", Vector2(1050, 390), Vector2(270, 186), 17, MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	forecast = label_at("", Vector2(42, 603), Vector2(1280, 64), 18)
	forecast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label_at("Наведите курсор на сектор · 1–8 или стрелки тоже меняют прицел · Пробел — импульс", Vector2(42, 654), Vector2(1250, 22), 14, MUTED)
	width_button = place_button("", Vector2(42, 687), Vector2(210, 48), toggle_width)
	wait_button = place_button("Ждать · W", Vector2(264, 687), Vector2(150, 48), choose_wait)
	commit_button = place_button("Импульс · Пробел", Vector2(430, 681), Vector2(260, 58), commit_turn, true)
	undo_button = place_button("Отмена · Z", Vector2(716, 687), Vector2(156, 48), undo)
	place_button("Заново · R", Vector2(884, 687), Vector2(151, 48), restart)
	place_button("? · H", Vector2(1047, 687), Vector2(130, 48), func(): show_modal("help"))
	place_button("Пауза · Esc", Vector2(1189, 687), Vector2(136, 48), func(): show_modal("pause"))
	modal = Control.new()
	modal.size = SIZE
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.hide()
	ui.add_child(modal)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.015, 0.035, 0.06, 0.82)
	dim.size = SIZE
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(dim)
	modal_card = PanelContainer.new()
	modal_card.position = Vector2(373, 138)
	modal_card.size = Vector2(620, 480)
	modal_card.add_theme_stylebox_override("panel", panel_style(Color("102635"), Color("486171")))
	modal.add_child(modal_card)
	modal_content = VBoxContainer.new()
	modal_content.add_theme_constant_override("separation", 15)
	modal_card.add_child(modal_content)

func load_level(index: int) -> void:
	stage = index
	scenario = scenarios[index].duplicate(true)
	state = Rules.initial(scenario)
	history = [state.duplicate(true)]
	previous_positions = state.positions.duplicate()
	last_outcome = {}
	action_history = []
	selected = 0
	beam_width = 1
	wait_mode = false
	animation = 0.0
	effect = 0.0
	close_modal()
	refresh()
	persist_progress()

func restore_progress(data: Dictionary) -> void:
	var previous_suspension: bool = suspend_save
	suspend_save = true
	completed = data.completed.duplicate()
	load_level(int(data.run.stage))
	action_history = data.run.actions.duplicate(true)
	history = data.history.duplicate(true)
	state = history.back().duplicate(true)
	previous_positions = state.positions.duplicate()
	refresh()
	suspend_save = previous_suspension

func persist_progress() -> void:
	if Rules.won(scenario, state) and not completed.has(stage): completed.append(stage)
	if (qa_mode and not persist_qa) or suspend_save: return
	var error: Error = Progress.write_save(progress_path, completed, stage, action_history)
	if error != OK: progress_notice = "Не удалось сохранить ход. Игра продолжится без сохранения."

func continue_game() -> void:
	close_modal()
	persist_progress()
	if Rules.terminal(scenario, state): show_result()

func unlocked(index: int) -> bool:
	return index == 0 or completed.has(0 if index == 5 else index - 1) or completed.has(index)

func current_action() -> Dictionary:
	return {"sector": selected, "width": 0 if wait_mode else beam_width}

func tutorial_hint() -> String:
	match int(state.turn):
		0: return "Широкий луч: 0 + 1.\nTab меняет ширину.\nПробел — импульс."
		1: return "Теперь широкий луч: 2 + 3.\nОдин импульс — один узел.\nПервая тень уже в пути."
		2: return "Теперь широкий луч: 4 + 5.\nЗатем ударит тень 1.\nКорабли уже вне её секторов."
		_: return "Луч 6 + 7 ведёт в порт.\nКольца — будущие места.\nСпасение раньше тени."

func sector_list(mask: int) -> String:
	var names: PackedStringArray = PackedStringArray()
	for sector in range(8):
		if (mask & (1 << sector)) != 0:
			names.append(str(sector))
	return ", ".join(names) if not names.is_empty() else "нет"

func ship_names(names: Array) -> String:
	var values: PackedStringArray = PackedStringArray()
	for name in names:
		values.append(str(name))
	return ", ".join(values)

func refresh() -> void:
	if state.is_empty(): return
	var ended: bool = Rules.terminal(scenario, state)
	preview = {} if ended else Rules.advance(scenario, state, current_action())
	var titles: Array = ["Первая вахта · обучение", "Ночь 1 / 4 · чужой след", "Ночь 2 / 4 · порог гавани", "Ночь 3 / 4 · встречные огни", "Ночь 4 / 4 · перед штормом", "Прилив · дополнительная вахта"]
	heading.text = titles[stage]
	counter.text = "Ход %d / %d" % [mini(int(state.turn) + 1, int(scenario.limit)), int(scenario.limit)]
	if ended: counter.text = "Завершено · %d ходов" % int(state.turn)
	var briefs: Array = [tutorial_hint(),
		"Два корабля · 5 ходов.\nПути сходятся в секторе 3.\nБерегите идущего следом.",
		"Два корабля · 5 ходов.\nМожно подождать — или\nпровести суда по очереди.",
		"Три корабля · 6 ходов.\nШире луч — шире тень.\nВыберите сторону луча.",
		"Шесть кораблей · 18 ходов.\nD, E, F — после хода 6.\nВ бухте — до трёх судов.",
		"Три корабля · 5 ходов.\nПусть волна поможет лучу.\nСпасите всех до шторма."]
	instruction.text = briefs[stage]
	tide_label.text = ""
	for tide in scenario.get("tides", []):
		if int(tide[0]) > int(state.turn):
			tide_label.text = "≈  ПРИЛИВ · ХОД %d\nСектора: %s\n\nВолна: один узел вперёд.\nТень создаёт только луч.\nЛуч + волна: один шаг." % [int(tide[0]), sector_list(int(tide[1]))]
			break
	if stage == 5 and tide_label.text.is_empty(): tide_label.text = "≈  Прилив прошёл.\nНовых волн не будет."
	shadow_labels[0].text = "1. Ближайшая тень\nПосле движения на ходу %d\nСектора: %s" % [int(state.turn) + 1, sector_list(int(state.shadows[0]))]
	shadow_labels[1].text = "2. Следующая тень\nПосле движения на ходу %d\nСектора: %s" % [int(state.turn) + 2, sector_list(int(state.shadows[1]))]
	var saved_count: int = 0
	var pending: PackedStringArray = PackedStringArray()
	for i in range(scenario.ships.size()):
		if int(state.positions[i]) == scenario.ships[i].route.size(): saved_count += 1
		if int(state.positions[i]) == -1:
			pending.append("%s · после хода %d" % [scenario.ships[i].name, scenario.ships[i].release])
	status.text = "В порту: %d / %d\nДо шторма: %d ходов\n\n" % [saved_count, scenario.ships.size(), maxi(0, int(scenario.limit) - int(state.turn))]
	status.text += "Все суда уже появились.\nНовых судов не будет." if pending.is_empty() else "Ожидаются:\n" + "\n".join(pending)
	width_button.text = ("Узкий · Tab" if beam_width == 1 else "Широкий · Tab") + ("  *" if not wait_mode else "")
	wait_button.text = "Ждать · W" + ("  *" if wait_mode else "")
	commit_button.text = "Пропустить · Пробел" if wait_mode else "Импульс · Пробел"
	if ended: commit_button.text = "Итоги вахты · Enter"
	commit_button.disabled = animation > 0.0
	undo_button.disabled = history.size() <= 1
	if ended:
		forecast.text = "Все огни вернулись домой." if Rules.won(scenario, state) else "Можно отменить ход и попробовать другой путь."
		forecast.modulate = PALE
	else:
		var description: String = "ОЖИДАНИЕ" if wait_mode else "ЛУЧ: " + sector_list(Rules.action_mask(current_action()))
		var tide: int = Rules.tide_at(scenario, int(state.turn) + 1)
		if tide != 0: description += "  +  ПРИЛИВ: " + sector_list(tide)
		description += "    >    "
		description += "Никто не сдвинется" if preview.moved.is_empty() else "Продвинутся: " + ship_names(preview.moved)
		if not preview.saved.is_empty(): description += "  ·  В порт: " + ship_names(preview.saved)
		if not preview.lost.is_empty():
			description += "\nПОТЕРЯ ПОСЛЕ ДВИЖЕНИЯ: " + ship_names(preview.lost) + ". Измените прицел."
			forecast.modulate = Color("ffb1a5")
		else:
			description += "\nПотерь на этом ходу нет."
			forecast.modulate = PALE
		description += "  Новая тень: после движения на ходу %d." % (int(state.turn) + 3) if not wait_mode else "  Ожидание не создаёт новую тень."
		forecast.text = description
	world.queue_redraw()
	update_browser_probe.call_deferred()

func update_browser_probe() -> void:
	if not browser_probe: return
	var buttons: Array = []
	for child in modal_content.get_children():
		if child is Button:
			var rect: Rect2 = child.get_global_rect()
			buttons.append({"text": child.text, "disabled": child.disabled, "x": rect.get_center().x, "y": rect.get_center().y})
	var data: Dictionary = {"stage": stage, "state": state, "modal": modal_kind, "completed": completed, "actions": action_history, "buttons": buttons, "notice": progress_notice}
	JavaScriptBridge.eval("window.__afterlight = " + JSON.stringify(data))

func toggle_width() -> void:
	if not modal_kind.is_empty(): return
	beam_width = 2 if beam_width == 1 else 1
	wait_mode = false
	refresh()

func choose_wait() -> void:
	if not modal_kind.is_empty(): return
	wait_mode = not wait_mode
	refresh()

func commit_turn() -> void:
	if not modal_kind.is_empty() or animation > 0.0: return
	if Rules.terminal(scenario, state):
		show_result()
		return
	if stage == 0 and (wait_mode or beam_width != 2 or selected != int(state.turn) * 2):
		forecast.text = "Обучение: выберите широкий луч %d + %d и подтвердите импульс." % [int(state.turn) * 2, int(state.turn) * 2 + 1]
		forecast.modulate = AMBER
		return
	previous_positions = state.positions.duplicate()
	last_outcome = Rules.advance(scenario, state, current_action())
	action_history.append(current_action().duplicate())
	state = last_outcome.state
	history.append(state.duplicate(true))
	animation = MOVE_DURATION
	effect = 1.25
	if sound != null:
		sound.play_cue("loss" if not last_outcome.lost.is_empty() else ("tide" if Rules.tide_at(scenario, int(state.turn)) != 0 else ("wait" if wait_mode else "pulse")))
	refresh()
	persist_progress()

func undo() -> void:
	if history.size() <= 1: return
	history.pop_back()
	if not action_history.is_empty(): action_history.pop_back()
	state = history.back().duplicate(true)
	previous_positions = state.positions.duplicate()
	last_outcome = {}
	animation = 0.0
	close_modal()
	if sound != null: sound.play_cue("undo")
	refresh()
	effect = 0.0
	persist_progress()

func restart() -> void:
	load_level(stage)

func close_modal() -> void:
	modal_kind = ""
	modal.hide()
	update_browser_probe.call_deferred()

func modal_text(text: String, size: int = 19, color: Color = PALE) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", 5)
	modal_content.add_child(label)
	return label

func show_modal(kind: String) -> void:
	modal_kind = kind
	for child in modal_content.get_children():
		modal_content.remove_child(child)
		child.queue_free()
	modal_card.position = Vector2(373, 102 if kind == "help" else 138)
	modal_card.size = Vector2(620, 0)
	modal.show()
	update_browser_probe.call_deferred()
	match kind:
		"welcome":
			modal_text("Послесвет", 32, AMBER)
			modal_text("Свет ведёт корабли домой. Его тень возвращается через два хода.", 22)
			modal_text(progress_notice, 17, MUTED)
			modal_text("Пройдено вахт: %d / 6" % completed.size(), 17, MUTED)
			modal_content.add_child(button("Начать вахту · Enter" if action_history.is_empty() and completed.is_empty() else "Продолжить · Enter", continue_game, true))
			modal_content.add_child(button("Выбор вахты", func(): show_modal("levels")))
		"levels":
			modal_text("Выбор вахты", 29, AMBER)
			var names: Array = ["Первая вахта · обучение", "Ночь 1 · чужой след", "Ночь 2 · порог гавани", "Ночь 3 · встречные огни", "Ночь 4 · перед штормом", "Прилив · новая вахта"]
			for index in range(names.size()):
				var choice: Button = button(names[index] + (" · пройдено" if completed.has(index) else ""), func(): load_level(index))
				choice.disabled = not unlocked(index)
				modal_content.add_child(choice)
			modal_content.add_child(button("Вернуться · Esc", close_modal))
		"help":
			modal_text("Как читать бухту", 30, AMBER)
			modal_text("Импульс продвигает корабли в луче на один узел. Ромб — ближайший узел маршрута. Пунктирное кольцо — место после выбранного движения.", 19)
			modal_text("1. Штрихи и 2. Точки — две приближающиеся тени. Точные ходы их удара указаны справа.\nИмпульс на ходу 1 создаёт тень на ходу 3. Спасение в порту происходит раньше удара тени.", 19)
			modal_text("Мышь / стрелки — прицел. Клавиши 1–8 — секторы 0–7.\nTab — ширина. W — выбрать ожидание.\nПробел / Enter — подтвердить. Z — отменить.\nR — заново. Esc — пауза. F11 — полный экран.", 18, MUTED)
			modal_text("Нужно спасти всех до шторма. Предпросмотр показывает потери текущего хода; две будущие тени планируете вы.", 18)
			modal_content.add_child(button("Понятно · Esc", close_modal, true))
		"pause":
			modal_text("Тихая вахта", 30, AMBER)
			modal_text("Пауза. Бухта подождёт.", 19)
			modal_text("Громкость", 18, MUTED)
			var slider: HSlider = HSlider.new()
			slider.min_value = 0.0
			slider.max_value = 1.0
			slider.step = 0.01
			slider.value = volume
			slider.custom_minimum_size = Vector2(0, 32)
			slider.value_changed.connect(func(value: float): set_volume(value))
			modal_content.add_child(slider)
			var fullscreen: CheckButton = CheckButton.new()
			fullscreen.text = "Полный экран · F11"
			fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			fullscreen.toggled.connect(func(enabled: bool): set_fullscreen(enabled))
			modal_content.add_child(fullscreen)
			modal_content.add_child(button("Продолжить · Esc", close_modal, true))
			modal_content.add_child(button("Начать эту вахту заново", restart))
			modal_content.add_child(button("Выбор вахты", func(): show_modal("levels")))
			if not OS.has_feature("web"):
				modal_content.add_child(button("Выйти из игры", func(): get_tree().quit()))
		"win":
			modal_text("Все огни дома", 32, AMBER)
			var message: String = "Обучение завершено. Впереди четыре короткие ночи с пересекающимися маршрутами."
			if stage > 0: message = "Все корабли в порту. Вы провели их сквозь тени собственного света."
			if stage == 4: message = "Четыре ночи позади. Последний корабль вошёл в порт до шторма. Спасибо за эту вахту."
			if stage == 5: message = "Волна и свет сработали вместе. Все три корабля успели в порт за пять ходов."
			modal_text(message, 22)
			modal_text("Спасено: %d / %d   ·   Ходов: %d" % [scenario.ships.size(), scenario.ships.size(), state.turn], 19, MUTED)
			if stage < 4:
				modal_content.add_child(button("Начать первую ночь" if stage == 0 else "Следующая ночь", func(): load_level(stage + 1), true))
			else:
				modal_content.add_child(button("Пройти ночь ещё раз", restart, true))
			modal_content.add_child(button("Отменить последний ход", undo))
			modal_content.add_child(button("Посмотреть бухту", close_modal))
			modal_content.add_child(button("Выбор вахты", func(): show_modal("levels")))
		"loss":
			modal_text("Один свет погас" if state.positions.has(-2) else "Пришёл шторм", 30, Color("f2a4a8"))
			modal_text("Корабль оказался в тени после движения. Отмените ход: все позиции и будущие тени восстановятся." if state.positions.has(-2) else "Ходы закончились. Не все корабли успели в порт. Попробуйте объединить их продвижения широким лучом.", 21)
			modal_content.add_child(button("Отменить ход · Z", undo, true))
			modal_content.add_child(button("Начать заново · R", restart))
			modal_content.add_child(button("Посмотреть бухту", close_modal))

func show_result() -> void:
	var victory: bool = Rules.won(scenario, state)
	show_modal("win" if victory else "loss")
	if sound != null: sound.play_cue("win" if victory else "loss")

func set_volume(value: float, save: bool = true) -> void:
	volume = clampf(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume == 0.0)
	if save and not qa_mode:
		settings.set_value("audio", "volume", volume)
		settings.save("user://settings.cfg")

func set_fullscreen(enabled: bool, save: bool = true) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
	if save and not qa_mode:
		settings.set_value("window", "fullscreen", enabled)
		settings.save("user://settings.cfg")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if code == KEY_F11:
			set_fullscreen(DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN)
			return
		if code == KEY_ESCAPE:
			if modal_kind.is_empty(): show_modal("pause")
			else: close_modal()
			return
		if code == KEY_Z:
			undo()
			return
		if code == KEY_R:
			restart()
			return
		if modal_kind == "welcome" and code in [KEY_ENTER, KEY_SPACE]:
			continue_game()
			return
		if not modal_kind.is_empty(): return
		match code:
			KEY_LEFT, KEY_A: selected = (selected + 7) % 8; wait_mode = false
			KEY_RIGHT, KEY_D: selected = (selected + 1) % 8; wait_mode = false
			KEY_TAB: toggle_width()
			KEY_W: choose_wait()
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER: commit_turn()
			KEY_H: show_modal("help")
			_:
				if code >= KEY_1 and code <= KEY_8:
					selected = code - KEY_1
					wait_mode = false
		refresh()
	if not modal_kind.is_empty(): return
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		var pointer: Vector2 = event.position
		var relative: Vector2 = pointer - world.CENTER
		relative.x /= world.BAY_ASPECT
		if relative.length() > 62.0 and relative.length() < 297.0 and pointer.y < 599.0:
			selected = posmod(int(floor((relative.angle() - world.OFFSET + PI / 8.0) / (TAU / 8.0))), 8)
			wait_mode = false
			refresh()

func capture_set(index: int, labels: Array) -> void:
	load_level(index)
	for label in labels:
		var action: Dictionary = {"sector": int(str(label).substr(1)), "width": 1 if str(label).begins_with("N") else 2}
		previous_positions = state.positions.duplicate()
		last_outcome = Rules.advance(scenario, state, action)
		action_history.append(action.duplicate())
		state = last_outcome.state
		history.append(state.duplicate(true))
	animation = 0.0
	clock = 0.75
	refresh()

func capture_frame(filename: String) -> bool:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Viewport image unavailable: " + filename)
		return false
	var result: Error = image.save_png(capture_dir.path_join(filename + ".png"))
	return result == OK

func capture_suite() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Viewport capture needs a rendered session; omit --headless")
		get_tree().quit(2)
		return
	var error: Error = DirAccess.make_dir_recursive_absolute(capture_dir)
	if error != OK:
		push_error("Capture directory error: " + str(error))
		get_tree().quit(2)
		return
	var results: Dictionary = {}
	capture_set(0, [])
	results.tutorial = await capture_frame("01_tutorial")
	capture_set(0, ["W0", "W2"])
	selected = 4; beam_width = 2; refresh()
	results.timing = await capture_frame("02_shadow_timing")
	capture_set(3, [])
	results.challenge = await capture_frame("03_challenge")
	capture_set(3, ["N0"])
	selected = 4; beam_width = 1; refresh()
	results.narrow = await capture_frame("04_narrow_choice")
	selected = 3; beam_width = 2; refresh()
	results.wide = await capture_frame("05_wider_shadow")
	capture_set(3, ["N0", "N1", "N2", "W3"])
	selected = 3; beam_width = 2; refresh()
	results.danger = await capture_frame("06_exact_loss_preview")
	capture_set(3, ["N0", "N1", "N2", "W3", "W3"])
	show_result()
	results.loss = await capture_frame("07_defeat")
	capture_set(3, ["N0", "N4", "N1", "W2", "W2", "N4"])
	show_result()
	results.win = await capture_frame("08_victory")
	capture_set(3, [])
	show_modal("pause")
	results.pause = await capture_frame("09_pause")
	show_modal("help")
	results.help = await capture_frame("10_help")
	capture_set(4, [])
	results.final_night = await capture_frame("11_final_night")
	capture_set(5, ["N4", "N0"])
	selected = 1; beam_width = 1; refresh()
	results.tide_plan = await capture_frame("12_tide_plan")
	commit_turn()
	animation = MOVE_DURATION * 0.62
	clock = 1.6
	results.tide_wave = await capture_frame("13_tide_wave")
	animation = 0.0
	completed = [0, 1, 2, 3, 4, 5]
	show_modal("levels")
	results.levels = await capture_frame("14_levels")
	show_modal("welcome")
	results.continue_game = await capture_frame("15_continue")
	var file: FileAccess = FileAccess.open(capture_dir.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(results, "  "))
	file.close()
	get_tree().quit(1 if results.values().has(false) else 0)
