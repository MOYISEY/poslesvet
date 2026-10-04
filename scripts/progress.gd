extends RefCounted
## Versioned local save. Replay commands, never trust serialized game state.
const Rules = preload("res://scripts/rules.gd")

static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high

static func decode(text: String, scenarios: Array) -> Dictionary:
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK: return {}
	var data: Variant = parser.data
	if not data is Dictionary or data.get("version") != 1: return {}
	if not data.get("completed") is Array or not data.get("run") is Dictionary: return {}
	var completed: Array = []
	for index in data.completed:
		if not integer(index, 0, scenarios.size() - 1): return {}
		if not completed.has(int(index)): completed.append(int(index))
	var run: Dictionary = data.run
	if not integer(run.get("stage"), 0, scenarios.size() - 1) or not run.get("actions") is Array: return {}
	var stage: int = int(run.stage)
	var sc: Dictionary = scenarios[stage]
	if run.actions.size() > int(sc.limit): return {}
	var state: Dictionary = Rules.initial(sc)
	var history: Array = [state.duplicate(true)]
	var actions: Array = []
	for item in run.actions:
		if not item is Dictionary or Rules.terminal(sc, state): return {}
		if not integer(item.get("sector"), 0, 7) or not integer(item.get("width"), 0, 2): return {}
		var action: Dictionary = {"sector": int(item.sector), "width": int(item.width)}
		if stage == 0 and (action.width != 2 or action.sector != int(state.turn) * 2): return {}
		state = Rules.advance(sc, state, action).state
		history.append(state.duplicate(true))
		actions.append(action)
	return {"version": 1, "completed": completed, "run": {"stage": stage, "actions": actions}, "history": history}

static func read_save(path: String, scenarios: Array) -> Dictionary:
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate): continue
		var data: Dictionary = decode(FileAccess.get_file_as_string(candidate), scenarios)
		if not data.is_empty():
			data["recovered"] = candidate != path
			return data
	return {}

static func write_save(path: String, completed: Array, stage: int, actions: Array) -> Error:
	var data: Dictionary = {"version": 1, "completed": completed, "run": {"stage": stage, "actions": actions}}
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK: return error
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			error = DirAccess.remove_absolute(path + ".bak")
			if error != OK: return error
		error = DirAccess.rename_absolute(path, path + ".bak")
		if error != OK: return error
	return DirAccess.rename_absolute(path + ".tmp", path)
