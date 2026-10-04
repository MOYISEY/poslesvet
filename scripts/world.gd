extends Node2D
## Original procedural vector scene; rendering only, never mutates game state.
const Rules = preload("res://scripts/rules.gd")
const CENTER: Vector2 = Vector2(610, 326)
const BAY_ASPECT: float = 1.42
const RADIUS: float = 238.0
const OFFSET: float = -3.0 * PI / 4.0
const AMBER: Color = Color("f5c779")
const COLORS: Array = [Color("7ed7ca"), Color("e7dca8"), Color("bbb0ef")]
var game: Variant = null
var font: Font = ThemeDB.fallback_font

func ink(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)

func angle_for(sector: int) -> float:
	return OFFSET + float(sector) * TAU / 8.0

func polar(radius: float, angle: float) -> Vector2:
	return CENTER + Vector2(cos(angle) * BAY_ASPECT, sin(angle)) * radius

func bay_arc(radius: float, start: float, end: float, color: Color, width: float = 1.0) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var steps: int = maxi(18, int(absf(end - start) * 30.0))
	for i in range(steps + 1):
		points.append(polar(radius, lerpf(start, end, float(i) / steps)))
	draw_polyline(points, color, width, true)

func port_point(index: int) -> Vector2:
	return CENTER + Vector2(57 + index * 11, 62 - index * 5)

func ship_point(index: int, node: int) -> Vector2:
	var route: Array = game.scenario.ships[index].route
	if node >= route.size(): return port_point(index)
	node = maxi(0, node)
	var fraction: float = float(node) / maxf(1.0, float(route.size() - 1))
	var lane: int = index % 3
	var radius: float = lerpf(224.0, 103.0, fraction) + float(lane - 1) * 11.0
	var offset: float = float(lane - 1) * 0.048
	return polar(radius, angle_for(int(route[node])) + offset)

func text(at: Vector2, value: String, size: int, color: Color) -> void:
	draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw() -> void:
	if game == null or game.state.is_empty(): return
	draw_water()
	draw_grid()
	for sector in range(8):
		if (int(game.state.shadows[1]) & (1 << sector)) != 0: draw_shadow(sector, 2)
		if (int(game.state.shadows[0]) & (1 << sector)) != 0: draw_shadow(sector, 1)
	if not game.wait_mode and not Rules.terminal(game.scenario, game.state):
		for offset in range(game.beam_width):
			draw_beam((game.selected + offset) % 8)
	draw_routes()
	draw_tide()
	draw_ship_states()
	draw_island()
	draw_predictions()
	draw_sector_labels()
	if game.effect > 0.0 and not game.last_outcome.is_empty():
		for i in range(game.scenario.ships.size()):
			if game.last_outcome.saved.has(game.scenario.ships[i].name):
				draw_arc(port_point(i), 12 + (1.25 - game.effect) * 24, 0, TAU, 32, ink(AMBER, game.effect * 0.42), 2, true)

func draw_tide() -> void:
	var mask: int = Rules.tide_at(game.scenario, int(game.state.turn) + 1)
	var active_wave: bool = game.animation > 0.0 and Rules.tide_at(game.scenario, int(game.state.turn)) != 0
	if active_wave: mask = Rules.tide_at(game.scenario, int(game.state.turn))
	if mask == 0: return
	for sector in range(8):
		if mask & (1 << sector) == 0: continue
		var left: float = angle_for(sector) - PI / 8.0
		var radius: float = lerpf(85, 248, game.animation / game.MOVE_DURATION) if active_wave else 244.0 + sin(game.clock * 2.1) * 3.0
		for trail in range(3):
			bay_arc(radius + trail * 6, left + 0.02, left + PI / 4.0 - 0.02, Color(0.48, 0.88, 0.85, 0.50 - trail * 0.13), 2.2 - trail * 0.4)
		if not active_wave:
			text(polar(216, angle_for(sector)) + Vector2(-7, 5), "≈", 25, Color("91ddd5"))

func draw_water() -> void:
	for band in range(32):
		var t: float = float(band) / 31.0
		var color: Color = Color("091725").lerp(Color("0b2c3b"), t)
		draw_rect(Rect2(0, band * 24, 1366, 25), color)
	# Broad, soft pools of shallow water; no texture or external asset.
	for layer in range(8, 0, -1):
		var pool: PackedVector2Array = PackedVector2Array()
		for i in range(65):
			var angle: float = TAU * float(i) / 64.0
			pool.append(CENTER + Vector2(cos(angle) * (210 + layer * 45), sin(angle) * (85 + layer * 25) + 45))
		draw_colored_polygon(pool, Color(0.08, 0.27, 0.31, 0.022))
	# A distant, low shore; the broad water surface remains unobstructed.
	draw_colored_polygon(PackedVector2Array([Vector2(0, 104), Vector2(108, 88), Vector2(192, 99),
		Vector2(269, 85), Vector2(353, 95), Vector2(412, 82), Vector2(459, 90),
		Vector2(566, 76), Vector2(730, 91), Vector2(809, 81), Vector2(917, 99),
		Vector2(1041, 89), Vector2(1148, 100), Vector2(1231, 77), Vector2(1366, 100),
		Vector2(1366, 0), Vector2(0, 0)]), Color("081420"))
	for i in range(36):
		var x: float = fmod(float(i * 137 + 113), 1320.0) + 20.0
		var y: float = fmod(float(i * 47 + 21), 76.0) + 12.0
		draw_circle(Vector2(x, y), 0.65, Color(0.75, 0.85, 0.85, 0.25 + 0.1 * sin(game.clock + i)))
	draw_circle(Vector2(974, 68), 15, Color("a2b4b8"))
	draw_circle(Vector2(980, 63), 14, Color("081420"))
	for i in range(23):
		var y: float = 116.0 + i * 15.0
		var offset: float = sin(game.clock * 0.21 + i * 2.4) * (9 + i * 0.9)
		var length: float = 6 + fmod(float(i * 17), 19.0)
		draw_line(Vector2(974 + offset - length, y), Vector2(974 + offset + length, y), Color(0.58, 0.76, 0.78, 0.09 - i * 0.002), 1.4, true)
	for row in range(21):
		var y: float = 119.0 + row * 23.0
		var points: PackedVector2Array = PackedVector2Array()
		for col in range(45):
			var x: float = col * 32.0
			points.append(Vector2(x, y + sin(x * 0.018 + row * 1.7 + game.clock * 0.24) * 2.2))
		draw_polyline(points, Color(0.33, 0.58, 0.65, 0.045), 1.0, true)
	for i in range(55):
		var x: float = fmod(float(i * 227), 1330.0) + 14.0
		var y: float = fmod(float(i * 91), 436.0) + 129.0
		var shift: float = sin(game.clock * 0.7 + i) * 6.0
		draw_line(Vector2(x + shift, y), Vector2(x + 10 + shift, y), Color(0.55, 0.75, 0.77, 0.10 + 0.045 * sin(game.clock * 1.2 + i)), 1.2, true)
	# Foreground rocks give the coast a tangible silhouette.
	draw_colored_polygon(PackedVector2Array([Vector2(0, 569), Vector2(53, 546), Vector2(76, 564),
		Vector2(126, 552), Vector2(154, 578), Vector2(203, 589), Vector2(212, 622),
		Vector2(0, 646)]), Color("10212c"))
	draw_polyline(PackedVector2Array([Vector2(0, 571), Vector2(53, 548), Vector2(76, 566),
		Vector2(126, 554), Vector2(154, 580), Vector2(203, 591)]), Color("26414b"), 2, true)
	# Quiet footer, not a floating dashboard card.
	draw_rect(Rect2(0, 589, 1366, 179), Color(0.025, 0.065, 0.10, 0.80))

func draw_grid() -> void:
	for radius in [103.0, 163.0, 224.0, RADIUS]:
		bay_arc(radius, 0, TAU, Color(0.33, 0.54, 0.61, 0.07), 1)
	for i in range(8):
		var angle: float = angle_for(i) - PI / 8.0
		draw_line(polar(54, angle), polar(RADIUS, angle), Color(0.41, 0.59, 0.63, 0.14), 1, true)

func wedge(sector: int, inner: float = 51.0, outer: float = RADIUS) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var left: float = angle_for(sector) - PI / 8.0
	for i in range(25):
		points.append(polar(outer, left + PI / 4.0 * float(i) / 24.0))
	for i in range(24, -1, -1):
		points.append(polar(inner, left + PI / 4.0 * float(i) / 24.0))
	return points

func draw_beam(sector: int) -> void:
	var left: float = angle_for(sector) - PI / 8.0
	var strength: float = 0.075 + game.animation * 0.15
	draw_colored_polygon(wedge(sector, 18), ink(AMBER, strength))
	for band in range(9):
		var near_radius: float = 18.0 + band * 24.0
		draw_colored_polygon(wedge(sector, near_radius, minf(RADIUS, near_radius + 24.0)), ink(AMBER, 0.065 * pow(1.0 - band / 9.0, 2.0)))
	bay_arc(RADIUS, left, left + PI / 4.0, ink(AMBER, 0.65), 1.7)
	draw_line(polar(20, left), polar(RADIUS, left), ink(AMBER, 0.22), 1.0, true)
	draw_line(polar(20, left + PI / 4.0), polar(RADIUS, left + PI / 4.0), ink(AMBER, 0.22), 1.0, true)
	for glint in range(10):
		var angle: float = left + 0.08 + fmod(glint * 0.237, 0.62)
		var at: Vector2 = polar(70.0 + glint * 15, angle)
		var length: float = 3.0 + sin(game.clock * 0.5 + glint) * 2.0
		draw_line(at - Vector2(length, 0), at + Vector2(length, 0), ink(AMBER, 0.15), 1.4, true)
	if game.animation > 0.0:
		var pulse_radius: float = lerpf(RADIUS, 28.0, game.animation / game.MOVE_DURATION)
		bay_arc(pulse_radius, left, left + PI / 4.0, ink(AMBER, 0.7), 2.5)
		bay_arc(maxf(20, pulse_radius - 12), left, left + PI / 4.0, ink(AMBER, 0.25), 4)

func draw_shadow(sector: int, delay: int) -> void:
	var color: Color = Color("df8296") if delay == 1 else Color("9286c8")
	var left: float = angle_for(sector) - PI / 8.0
	draw_colored_polygon(wedge(sector), ink(color, 0.105 if delay == 1 else 0.065))
	if delay == 1:
		for radius in range(66, 234, 17):
			var points: PackedVector2Array = PackedVector2Array()
			for j in range(18):
				points.append(polar(radius + j * 0.35, left + 0.025 + (PI / 4.0 - 0.05) * j / 17.0))
			draw_polyline(points, ink(color, 0.38), 1.5, true)
	else:
		for radius in range(77, 236, 27):
			for j in range(7):
				draw_circle(polar(radius, left + 0.07 + j * 0.105), 1.35, ink(color, 0.65))
	var tag: Vector2 = polar(192.0 if delay == 1 else 165.0, left + 0.11)
	draw_circle(tag, 11, ink(Color("0b1e2c"), 0.85))
	text(tag + Vector2(-4, 5), str(delay), 14, color)

func draw_routes() -> void:
	for i in range(game.scenario.ships.size()):
		var ship: Dictionary = game.scenario.ships[i]
		var color: Color = COLORS[i % COLORS.size()]
		var queued: bool = int(game.state.positions[i]) == -1
		var current: int = int(game.state.positions[i])
		var route: PackedVector2Array = PackedVector2Array()
		for node in range(ship.route.size() + 1):
			route.append(ship_point(i, node))
		draw_polyline(route, ink(color, 0.08 if queued else 0.18), 1.1, true)
		if queued:
			var entry: Vector2 = ship_point(i, 0)
			draw_arc(entry, 10, 0, TAU, 24, ink(color, 0.5), 1, true)
			text(entry + Vector2(-7, -16), "%s · %d" % [ship.name, ship.release], 14, ink(color, 0.65))
		for node in range(ship.route.size()):
			var point: Vector2 = ship_point(i, node)
			draw_circle(point, 2.4, ink(color, 0.24 if queued else 0.40))
			if node < ship.route.size() - 1:
				var next: Vector2 = ship_point(i, node + 1)
				var mid: Vector2 = point.lerp(next, 0.52)
				var direction: Vector2 = (next - point).normalized()
				var perp: Vector2 = direction.orthogonal()
				draw_polyline(PackedVector2Array([mid - direction * 4 + perp * 3, mid,
					mid - direction * 4 - perp * 3]), ink(color, 0.16 if queued else 0.27), 1, true)
		if current >= 0 and current < ship.route.size():
			var start: Vector2 = ship_point(i, current)
			var next: Vector2 = ship_point(i, current + 1)
			var direction: Vector2 = (next - start).normalized()
			var distance: float = start.distance_to(next)
			for dash in range(28, int(distance) - 12, 13):
				draw_line(start + direction * dash, start + direction * minf(dash + 5.0, distance - 12), ink(color, 0.57), 1.6, true)
			if current + 1 < ship.route.size():
				draw_circle(next, 10, ink(color, 0.07))
				draw_colored_polygon(PackedVector2Array([next + Vector2(0, -5), next + Vector2(5, 0), next + Vector2(0, 5), next + Vector2(-5, 0)]), ink(color, 0.92))

func draw_ship_states() -> void:
	for i in range(game.scenario.ships.size()):
		var ship: Dictionary = game.scenario.ships[i]
		var node: int = int(game.state.positions[i])
		if node == -1: continue
		var color: Color = COLORS[i % COLORS.size()]
		if node == ship.route.size() and (game.animation <= 0 or int(game.previous_positions[i]) == node):
			draw_circle(port_point(i), 3.0, ink(color, 0.8))
			continue
		var lost: bool = node == -2
		if lost:
			node = int(game.previous_positions[i])
			if not game.last_outcome.is_empty() and game.last_outcome.moved.has(ship.name): node += 1
		var point: Vector2 = ship_point(i, node)
		if game.animation > 0 and not game.previous_positions.is_empty():
			var from: Vector2 = ship_point(i, int(game.previous_positions[i]))
			var t: float = 1.0 - game.animation / game.MOVE_DURATION
			point = from.lerp(point, t * t * (3.0 - 2.0 * t))
		var heading: float = (ship_point(i, node + 1) - point).angle()
		if game.animation > 0.0 and not game.previous_positions.is_empty():
			var from: Vector2 = ship_point(i, int(game.previous_positions[i]))
			if from.distance_to(ship_point(i, node)) > 1.0:
				heading = lerp_angle((ship_point(i, node) - from).angle(), heading, 1.0 - game.animation / game.MOVE_DURATION)
		point.y += sin(game.clock * 2.3 + i * 1.7) * 1.3
		heading += sin(game.clock * 1.8 + i) * 0.028
		var backward: Vector2 = -Vector2.from_angle(heading)
		for wake in range(3):
			var behind: Vector2 = point + backward * (25 + wake * 9)
			draw_arc(behind, 6 + wake * 3 + sin(game.clock * 2.8 - wake) * 1.5, heading + PI * 0.68, heading + PI * 1.32, 12,
				ink(color, (0.37 if game.animation > 0 else 0.24) - wake * 0.055), 1.4, true)
		if lost:
			cross(point, Color("f8a59f"), 10)
			text(point + Vector2(14, -9), ship.name, 17, Color("f8a59f"))
		else:
			boat(point, heading, color)
			var name_offset: Vector2 = Vector2(26, 5) if point.y < CENTER.y - 175.0 else Vector2(-6, -26)
			text(point + name_offset, ship.name, 19, color.lightened(0.15))

func boat(at: Vector2, heading: float, color: Color) -> void:
	var hull: PackedVector2Array = PackedVector2Array()
	for point in [Vector2(23, 0), Vector2(7, -8), Vector2(-15, -7), Vector2(-19, 0), Vector2(-15, 7), Vector2(7, 8)]:
		hull.append(at + point.rotated(heading))
	var shadow: PackedVector2Array = PackedVector2Array()
	for i in range(33):
		var angle: float = TAU * i / 32.0
		shadow.append(at + Vector2(3, 5) + Vector2(cos(angle) * 25, sin(angle) * 11).rotated(heading))
	draw_colored_polygon(shadow, Color(0.01, 0.045, 0.065, 0.7))
	draw_colored_polygon(hull, color.darkened(0.05))
	var rim: PackedVector2Array = hull.duplicate()
	rim.append(hull[0])
	draw_polyline(rim, ink(color.lightened(0.3), 0.85), 1.3, true)
	var deck: PackedVector2Array = PackedVector2Array()
	for point in [Vector2(6, -4), Vector2(-9, -4), Vector2(-9, 4), Vector2(6, 4)]:
		deck.append(at + point.rotated(heading))
	draw_colored_polygon(deck, Color("1a3542"))
	draw_line(at + Vector2(-12, 0).rotated(heading), at + Vector2(12, 0).rotated(heading), ink(Color.WHITE, 0.35), 1.0, true)
	draw_circle(at + Vector2(8, 0).rotated(heading), 3.1, Color("fff0bc"))
	draw_circle(at + Vector2(8, 0).rotated(heading), 7, Color(1.0, 0.8, 0.46, 0.06))

func cross(at: Vector2, color: Color, radius: float) -> void:
	draw_line(at + Vector2(-radius, -radius), at + Vector2(radius, radius), color, 2.5, true)
	draw_line(at + Vector2(radius, -radius), at + Vector2(-radius, radius), color, 2.5, true)

func draw_predictions() -> void:
	if game.preview.is_empty() or game.animation > 0.0: return
	for landing in game.preview.landings:
		var index: int = -1
		for i in range(game.scenario.ships.size()):
			if game.scenario.ships[i].name == landing[0]: index = i
		if index < 0: continue
		var point: Vector2 = ship_point(index, int(game.state.positions[index]) + 1)
		var color: Color = Color("ffaaa0") if game.preview.lost.has(landing[0]) else COLORS[index % 3]
		for segment in range(8):
			draw_arc(point, 17, segment * PI / 4.0, segment * PI / 4.0 + 0.43, 6, ink(color, 0.92), 1.8, true)
		if landing[1] == null:
			var label_at: Vector2 = CENTER + Vector2(118, 48 + 18 * (index % 3))
			draw_line(point + Vector2(14, 0), label_at + Vector2(-4, -5), ink(color, 0.5), 1, true)
			text(label_at, str(landing[0]) + " > порт", 14, color)
		else:
			text(point + Vector2(20, 6), str(landing[0]) + " >", 15, color)
	for name in game.preview.lost:
		for i in range(game.scenario.ships.size()):
			if game.scenario.ships[i].name != name: continue
			var node: int = int(game.state.positions[i]) + (1 if game.preview.moved.has(name) else 0)
			cross(ship_point(i, node), Color("ffaaa0"), 9)

func draw_island() -> void:
	var c: Vector2 = CENTER
	for ripple in range(3):
		var surf: PackedVector2Array = PackedVector2Array()
		for step in range(33):
			var angle: float = TAU * step / 32.0
			surf.append(c + Vector2(0, 63) + Vector2(cos(angle) * (63 + ripple * 9), sin(angle) * (42 + ripple * 5)))
		draw_polyline(surf, Color(0.37, 0.63, 0.65, 0.13 - ripple * 0.03), 1.4, true)
	draw_circle(c + Vector2(2, 58), 55, Color(0.08, 0.21, 0.25, 0.7))
	draw_colored_polygon(PackedVector2Array([c + Vector2(-51, 56), c + Vector2(-35, 24),
		c + Vector2(4, 28), c + Vector2(31, 45), c + Vector2(48, 82),
		c + Vector2(20, 104), c + Vector2(-28, 95)]), Color("293b42"))
	draw_colored_polygon(PackedVector2Array([c + Vector2(-35, 42), c + Vector2(-2, 28),
		c + Vector2(27, 50), c + Vector2(19, 87), c + Vector2(-30, 78)]), Color("3d4d4d"))
	draw_colored_polygon(PackedVector2Array([c + Vector2(-51, 56), c + Vector2(-30, 78), c + Vector2(-28, 95), c + Vector2(-44, 80)]), Color("1d3038"))
	draw_colored_polygon(PackedVector2Array([c + Vector2(27, 50), c + Vector2(48, 82), c + Vector2(20, 104), c + Vector2(19, 87)]), Color("23353a"))
	draw_line(c + Vector2(-33, 43), c + Vector2(-47, 58), Color("60706a"), 1.6, true)
	draw_line(c + Vector2(-28, 95), c + Vector2(18, 102), Color(0.48, 0.67, 0.66, 0.38), 1.2, true)
	draw_colored_polygon(PackedVector2Array([c + Vector2(4, 65), c + Vector2(26, 72), c + Vector2(45, 91), c + Vector2(22, 94)]), Color(0.04, 0.11, 0.14, 0.5))
	draw_line(c + Vector2(21, 67), c + Vector2(91, 51), Color("5f6962"), 12, true)
	for i in range(8):
		var at: Vector2 = c + Vector2(25 + i * 9, 66 - i * 2)
		draw_line(at + Vector2(-2, -5), at + Vector2(1, 6), Color("283f46"), 2, true)
	text(c + Vector2(56, 91), "ПОРТ", 12, Color("a4baba"))
	# Tower body, shaded flank, balcony, lantern and copper roof.
	draw_colored_polygon(PackedVector2Array([c + Vector2(-17, 4), c + Vector2(16, 4),
		c + Vector2(25, 77), c + Vector2(-25, 77)]), Color("c9cbb8"))
	draw_colored_polygon(PackedVector2Array([c + Vector2(5, 4), c + Vector2(16, 4),
		c + Vector2(25, 77), c + Vector2(8, 77)]), Color("789199"))
	for row in range(5):
		var y: float = 17 + row * 12
		var edge: float = 17 + (y - 4) * 8 / 73
		draw_line(c + Vector2(-edge, y), c + Vector2(7, y), Color(0.26, 0.36, 0.38, 0.18), 1, true)
		draw_line(c + Vector2(-10 if row % 2 == 0 else 1, y), c + Vector2(-10 if row % 2 == 0 else 1, y + 9), Color(0.26, 0.36, 0.38, 0.13), 1, true)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-20, 32), c + Vector2(19, 32),
		c + Vector2(21, 46), c + Vector2(-22, 46)]), Color("526c78"))
	draw_rect(Rect2(c + Vector2(-5, 60), Vector2(10, 17)), Color("193444"))
	draw_rect(Rect2(c + Vector2(-4, 14), Vector2(7, 10)), Color("234655"))
	for ring in range(5, 0, -1):
		draw_circle(c + Vector2(0, -4), 12 + ring * 7, ink(AMBER, 0.023))
	draw_rect(Rect2(c + Vector2(-15, -13), Vector2(30, 21)), Color("735839"))
	draw_rect(Rect2(c + Vector2(-11, -10), Vector2(22, 15)), AMBER)
	draw_line(c + Vector2(0, -12), c + Vector2(0, 7), Color("675a41"), 2, true)
	draw_line(c + Vector2(-24, 10), c + Vector2(24, 10), Color("203947"), 5, true)
	draw_line(c + Vector2(-22, 4), c + Vector2(22, 4), Color("819394"), 1.4, true)
	for x in [-21, -11, 11, 21]:
		draw_line(c + Vector2(x, 4), c + Vector2(x, 11), Color("829697"), 1.4, true)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-21, -14), c + Vector2(0, -29),
		c + Vector2(21, -14)]), Color("ac8057"))
	draw_line(c + Vector2(0, -29), c + Vector2(0, -37), Color("a2a797"), 2, true)

func draw_sector_labels() -> void:
	for sector in range(8):
		var point: Vector2 = polar(263, angle_for(sector))
		var selected_mask: int = 0 if game.wait_mode else Rules.action_mask(game.current_action())
		var chosen: bool = (selected_mask & (1 << sector)) != 0
		draw_circle(point, 16, Color("3e3b2e") if chosen else Color("102938"))
		draw_arc(point, 16, 0, TAU, 32, ink(AMBER if chosen else Color("6b8996"), 0.65), 1, true)
		text(point + Vector2(-5, 6), str(sector), 17, AMBER if chosen else Color("a0bac6"))
