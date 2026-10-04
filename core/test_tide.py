import unittest
from dataclasses import replace
from model import Action, Scenario, Ship, State, step, initial, Session
from scenarios import SCENARIOS
from solver import solve, replay


class TideTests(unittest.TestCase):
    def test_overlap_advances_once_and_wait_creates_no_shadow(self):
        sc = Scenario('overlap', (Ship('A', (2, 2, 2)),), 5, tides=((3, 4),))
        state = State(2, (0,))
        self.assertEqual(step(sc, state, Action(2, 2)).state.positions, (1,))
        out = step(sc, state, Action())
        self.assertEqual((out.state.positions, out.state.shadows), ((1,), (0, 0)))
        self.assertEqual(state.positions, (0,))

    def test_tide_damage_and_rescue_order(self):
        sc = Scenario('order', (Ship('A', (2,)), Ship('B', (2, 3))), 5, tides=((3, 4),))
        out = step(sc, State(2, (0, 0), (12, 0)), Action())
        self.assertEqual((out.saved, out.lost), (('A',), ('B',)))

    def test_new_arrivals_do_not_ride_previous_wave(self):
        sc = Scenario('spawn', (Ship('A', (2,)), Ship('B', (2, 3), 3)), 5, 1, ((3, 4),))
        out = step(sc, State(2, (0, -1)), Action())
        self.assertEqual(out.state.positions, (1, 0))

    def test_tide_is_necessary_for_bonus_five_turn_plan(self):
        sc = SCENARIOS[5]
        path, stats = solve(sc)
        self.assertTrue(stats['exhaustive'])
        self.assertEqual(len(path), 5)
        final, rows = replay(sc, path)
        self.assertEqual(final.positions, (3, 4, 3))
        self.assertFalse(any(row['lost'] for row in rows))
        impossible, stats = solve(replace(sc, tides=()))
        self.assertIsNone(impossible)
        self.assertTrue(stats['exhaustive'])

    def test_undo_across_tide_is_deterministic(self):
        sc = SCENARIOS[5]
        session = Session(sc)
        for action in (Action(4, 1), Action(0, 1)):
            session.commit(action)
        before = session.state
        first = session.commit(Action(1, 1))
        self.assertEqual(session.undo(), before)
        self.assertEqual(session.commit(Action(1, 1)), first)

    def test_bad_tide_schedule_is_rejected(self):
        for tides in (((0, 4),), ((3, 256),), ((3, 4), (3, 8))):
            with self.assertRaises(ValueError):
                Scenario('bad', (Ship('A', (0,)),), 5, tides=tides)


if __name__ == '__main__':
    unittest.main()
