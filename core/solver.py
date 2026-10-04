"""Breadth-first solver; optional capped frontier for larger proof scenarios."""
from model import ACTIONS, initial, step, won


def remaining(sc, state):
    return sum(len(s.route) - max(p, 0) for s, p in zip(sc.ships, state.positions))


def solve(sc, *, shadows=True, wide=True, beam=None, start=None):
    root = start or initial(sc)
    frontier = {root: ()}
    expanded = 0
    truncated = False
    for _ in range(root.turn, sc.limit):
        following = {}
        for state, path in frontier.items():
            if won(sc, state):
                return path, {"expanded": expanded, "exhaustive": not truncated}
            expanded += 1
            for action in ACTIONS:
                if not wide and action.width == 2:
                    continue
                out = step(sc, state, action, shadows=shadows)
                # A nonmoving pulse is dominated by wait: it only adds danger.
                if out.lost or (action.width and not out.moved):
                    continue
                child = out.state
                child_path = path + (action,)
                if won(sc, child):
                    return child_path, {"expanded": expanded, "exhaustive": not truncated}
                if child.turn >= sc.limit:
                    continue
                if remaining(sc, child) > (sc.limit - child.turn) * sc.capacity:
                    continue
                following.setdefault(child, child_path)
        if beam and len(following) > beam:
            truncated = True
            ordered = sorted(following, key=lambda st: (remaining(sc, st),
                sum(m.bit_count() for m in st.shadows), st.positions, st.shadows))
            following = {st: following[st] for st in ordered[:beam]}
        frontier = following
        if not frontier:
            break
    return None, {"expanded": expanded, "exhaustive": not truncated}


def replay(sc, path, *, shadows=True, start=None):
    state = start or initial(sc)
    rows = []
    for action in path:
        out = step(sc, state, action, shadows=shadows)
        rows.append({"turn": out.state.turn, "action": str(action),
            "positions": out.state.positions, "danger": out.danger,
            "saved": out.saved, "lost": out.lost, "spawned": out.spawned})
        state = out.state
    return state, rows
