class_name AfterlightRules
extends RefCounted
## Pure port of afterlight-core/model.py. Sector indices remain 0..7.

static func action_mask(action: Dictionary) -> int:
	var mask: int = 0
	for i in range(int(action.width)):
		mask |= 1 << ((int(action.sector) + i) % 8)
	return mask

static func active(sc: Dictionary, positions: Array) -> int:
	var count: int = 0
	for i in range(sc.ships.size()):
		if int(positions[i]) >= 0 and int(positions[i]) < sc.ships[i].route.size():
			count += 1
	return count

static func spawn(sc: Dictionary, positions: Array, turn: int) -> Array:
	var spawned: Array = []
	var slots: int = int(sc.capacity) - active(sc, positions)
	var indices: Array = range(sc.ships.size())
	indices.sort_custom(func(a: int, b: int) -> bool:
		if int(sc.ships[a].release) == int(sc.ships[b].release):
			return a < b
		return int(sc.ships[a].release) < int(sc.ships[b].release))
	for i in indices:
		var ship: Dictionary = sc.ships[i]
		if slots > 0 and int(positions[i]) == -1 and int(ship.release) <= turn:
			positions[i] = 0
			spawned.append(ship.name)
			slots -= 1
	return spawned

static func initial(sc: Dictionary) -> Dictionary:
	var positions: Array = []
	positions.resize(sc.ships.size())
	positions.fill(-1)
	spawn(sc, positions, 0)
	return {"turn": 0, "positions": positions, "shadows": [0, 0]}

static func won(sc: Dictionary, state: Dictionary) -> bool:
	for i in range(sc.ships.size()):
		if int(state.positions[i]) != sc.ships[i].route.size():
			return false
	return true

static func terminal(sc: Dictionary, state: Dictionary) -> bool:
	return won(sc, state) or state.positions.has(-2) or int(state.turn) >= int(sc.limit)

static func tide_at(sc: Dictionary, turn: int) -> int:
	for tide in sc.get("tides", []):
		if int(tide[0]) == turn: return int(tide[1])
	return 0

static func advance(sc: Dictionary, state: Dictionary, action: Dictionary, shadows_enabled: bool = true) -> Dictionary:
	assert(not terminal(sc, state), "Cannot advance a terminal state")
	assert(int(action.width) in [0, 1, 2] and int(action.sector) >= 0 and int(action.sector) < 8)
	if terminal(sc, state):
		return {}
	var positions: Array = state.positions.duplicate()
	var moved: Array = []
	var saved: Array = []
	var lost: Array = []
	var landings: Array = []
	var mask: int = action_mask(action)
	var movement_mask: int = mask | tide_at(sc, int(state.turn) + 1)
	for i in range(sc.ships.size()):
		var ship: Dictionary = sc.ships[i]
		var p: int = int(state.positions[i])
		if p >= 0 and p < ship.route.size() and (movement_mask & (1 << int(ship.route[p]))) != 0:
			positions[i] = p + 1
			moved.append(ship.name)
			var destination: Variant = null
			if p + 1 < ship.route.size():
				destination = int(ship.route[p + 1])
			else:
				saved.append(ship.name)
			landings.append([ship.name, destination])
	var danger: int = int(state.shadows[0]) if shadows_enabled else 0
	for i in range(sc.ships.size()):
		var ship: Dictionary = sc.ships[i]
		var p: int = int(positions[i])
		if p >= 0 and p < ship.route.size() and (danger & (1 << int(ship.route[p]))) != 0:
			positions[i] = -2
			lost.append(ship.name)
	var turn: int = int(state.turn) + 1
	var spawned: Array = spawn(sc, positions, turn)
	var next_shadows: Array = [int(state.shadows[1]), mask] if shadows_enabled else [0, 0]
	return {"state": {"turn": turn, "positions": positions, "shadows": next_shadows},
		"moved": moved, "saved": saved, "lost": lost, "spawned": spawned,
		"landings": landings, "danger": danger}
