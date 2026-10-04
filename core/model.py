"""Afterlight: deterministic, dependency-free tactical core (no engine/UI)."""
from dataclasses import dataclass

SECTORS = 8


@dataclass(frozen=True)
class Action:
    sector: int = 0
    width: int = 0  # 0 = wait, 1 = narrow, 2 = clockwise adjacent pair

    def __post_init__(self):
        if self.width not in (0, 1, 2) or not 0 <= self.sector < SECTORS:
            raise ValueError("invalid action")

    @property
    def mask(self):
        return sum(1 << ((self.sector + i) % SECTORS) for i in range(self.width))

    def __str__(self):
        return "wait" if not self.width else f"{'N' if self.width == 1 else 'W'}{self.sector}"


ACTIONS = (Action(),) + tuple(Action(s, w) for w in (1, 2) for s in range(8))


@dataclass(frozen=True)
class Ship:
    name: str
    route: tuple[int, ...]  # occupied sector at each non-port node
    release: int = 0  # 0 initially; otherwise enters AFTER this turn's danger


@dataclass(frozen=True)
class Scenario:
    name: str
    ships: tuple[Ship, ...]
    limit: int
    capacity: int = 3
    tides: tuple[tuple[int, int], ...] = ()  # (turn, sector mask), movement before shadow

    def __post_init__(self):
        if self.limit < 1 or self.capacity < 1 or not self.ships:
            raise ValueError("invalid scenario")
        if len({s.name for s in self.ships}) != len(self.ships):
            raise ValueError("duplicate ship name")
        for s in self.ships:
            if not s.route or s.release < 0 or any(not 0 <= x < 8 for x in s.route):
                raise ValueError("invalid route/release")
        if len({turn for turn, mask in self.tides}) != len(self.tides) or any(
            not 1 <= turn <= self.limit or not 1 <= mask <= 255 for turn, mask in self.tides
        ):
            raise ValueError("invalid tide schedule")


@dataclass(frozen=True)
class State:
    turn: int
    positions: tuple[int, ...]  # -1 queued, -2 lost, len(route) rescued
    shadows: tuple[int, int] = (0, 0)  # due after next move, due one move later


@dataclass(frozen=True)
class Outcome:
    state: State
    moved: tuple[str, ...]
    saved: tuple[str, ...]
    lost: tuple[str, ...]
    spawned: tuple[str, ...]
    landings: tuple[tuple[str, int | None], ...]
    danger: int


def active(sc, positions):
    return sum(0 <= p < len(s.route) for s, p in zip(sc.ships, positions))


def _spawn(sc, positions, turn):
    spawned = []
    slots = sc.capacity - active(sc, positions)
    for i, s in sorted(enumerate(sc.ships), key=lambda pair: (pair[1].release, pair[0])):
        if slots and positions[i] == -1 and s.release <= turn:
            positions[i] = 0
            spawned.append(s.name)
            slots -= 1
    return tuple(spawned)


def initial(sc):
    positions = [-1] * len(sc.ships)
    _spawn(sc, positions, 0)
    return State(0, tuple(positions))


def won(sc, state):
    return all(p == len(s.route) for s, p in zip(sc.ships, state.positions))


def terminal(sc, state):
    return won(sc, state) or -2 in state.positions or state.turn >= sc.limit


def step(sc, state, action, *, shadows=True):
    """Also the preview function: pure; caller commits only on confirmation."""
    if terminal(sc, state):
        raise ValueError("cannot advance terminal state")
    positions = list(state.positions)
    moved, saved, lost, landings = [], [], [], []
    mask = action.mask
    movement_mask = mask | dict(sc.tides).get(state.turn + 1, 0)
    # Select from ORIGINAL positions: never cascade through multiple route nodes.
    for i, (ship, p) in enumerate(zip(sc.ships, state.positions)):
        if 0 <= p < len(ship.route) and movement_mask & (1 << ship.route[p]):
            positions[i] += 1
            moved.append(ship.name)
            destination = None if positions[i] == len(ship.route) else ship.route[positions[i]]
            landings.append((ship.name, destination))
            if destination is None:
                saved.append(ship.name)
    danger = state.shadows[0] if shadows else 0
    for i, (ship, p) in enumerate(zip(sc.ships, positions)):
        if 0 <= p < len(ship.route) and danger & (1 << ship.route[p]):
            positions[i] = -2
            lost.append(ship.name)
    turn = state.turn + 1
    spawned = _spawn(sc, positions, turn)
    next_shadows = (state.shadows[1], mask) if shadows else (0, 0)
    return Outcome(State(turn, tuple(positions), next_shadows), tuple(moved),
                   tuple(saved), tuple(lost), spawned, tuple(landings), danger)


class Session:
    def __init__(self, scenario):
        self.scenario = scenario
        self.history = [initial(scenario)]

    @property
    def state(self):
        return self.history[-1]

    def preview(self, action):
        return step(self.scenario, self.state, action)

    def commit(self, action):
        result = self.preview(action)
        self.history.append(result.state)
        return result

    def undo(self):
        if len(self.history) > 1:
            self.history.pop()
        return self.state

    def restart(self):
        self.history = [initial(self.scenario)]
        return self.state
