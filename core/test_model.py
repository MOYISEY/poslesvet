import unittest
from model import Action, Ship, Scenario, State, Session, initial, step, won, terminal


class RulesTests(unittest.TestCase):
    def sc(self, *ships, limit=10, capacity=3):
        return Scenario("test", ships, limit, capacity)

    def test_shadow_from_turn_one_occurs_on_turn_three(self):
        sc = self.sc(Ship("A", (2, 2, 2, 2)))
        a = step(sc, initial(sc), Action(2, 1))
        b = step(sc, a.state, Action())
        c = step(sc, b.state, Action())
        self.assertEqual((a.lost, b.lost, c.lost), ((), (), ("A",)))
        self.assertEqual((a.danger, b.danger, c.danger), (0, 0, 4))

    def test_landing_in_due_shadow_kills(self):
        sc = self.sc(Ship("A", (1, 2, 4)))
        out = step(sc, State(2, (0,), (4, 0)), Action(1, 1))
        self.assertEqual(out.landings, (("A", 2),))
        self.assertEqual(out.lost, ("A",))

    def test_moving_out_of_shadow_is_safe(self):
        sc = self.sc(Ship("A", (2, 1, 4)))
        out = step(sc, State(2, (0,), (4, 0)), Action(2, 1))
        self.assertFalse(out.lost)
        self.assertEqual(out.state.positions, (1,))

    def test_port_removes_ship_before_danger(self):
        sc = self.sc(Ship("A", (2,)))
        out = step(sc, State(2, (0,), (4, 0)), Action(2, 1))
        self.assertEqual(out.saved, ("A",))
        self.assertFalse(out.lost)
        self.assertTrue(won(sc, out.state))

    def test_wide_moves_simultaneously_once_and_wraps(self):
        sc = self.sc(Ship("A", (7, 0, 2)), Ship("B", (0, 7, 3)))
        out = step(sc, initial(sc), Action(7, 2))
        self.assertEqual(out.state.positions, (1, 1))
        self.assertEqual(out.moved, ("A", "B"))
        self.assertEqual(out.state.shadows, (0, 129))

    def test_new_ship_spawns_after_danger_without_free_move(self):
        sc = self.sc(Ship("A", (6,)), Ship("B", (2, 3), 3))
        out = step(sc, State(2, (0, -1), (4, 0)), Action(2, 1))
        self.assertEqual(out.spawned, ("B",))
        self.assertEqual(out.state.positions, (0, 0))
        self.assertFalse(out.lost)

    def test_capacity_and_overdue_release_fifo(self):
        sc = self.sc(Ship("A", (0,)), Ship("B", (1,), 1),
                     Ship("C", (2,), 0), capacity=1)
        state = initial(sc)
        self.assertEqual(state.positions, (0, -1, -1))
        out = step(sc, state, Action(0, 1))
        self.assertEqual(out.spawned, ("C",))
        self.assertEqual(out.state.positions, (1, -1, 0))
        out = step(sc, out.state, Action(2, 1))
        self.assertEqual(out.spawned, ("B",))

    def test_shadow_sector_stays_exact_not_following_ship(self):
        sc = self.sc(Ship("A", (2, 4, 6, 0)))
        a = step(sc, initial(sc), Action(2, 1))
        b = step(sc, a.state, Action())
        c = step(sc, b.state, Action())
        self.assertEqual(c.danger, 4)
        self.assertFalse(c.lost)

    def test_preview_determinism_undo_restart_including_spawns(self):
        sc = self.sc(Ship("A", (0,)), Ship("B", (1, 2), 1))
        session = Session(sc)
        before = session.state
        preview = session.preview(Action(0, 1))
        self.assertEqual(session.state, before)
        self.assertEqual(session.commit(Action(0, 1)), preview)
        self.assertEqual(session.undo(), before)
        self.assertEqual(session.commit(Action(0, 1)), preview)
        self.assertEqual(session.restart(), before)

    def test_last_turn_win_and_storm_failure(self):
        sc = self.sc(Ship("A", (0,)), limit=1)
        win = step(sc, initial(sc), Action(0, 1)).state
        fail = step(sc, initial(sc), Action()).state
        self.assertTrue(won(sc, win))
        self.assertFalse(won(sc, fail))
        self.assertTrue(terminal(sc, fail))
        with self.assertRaises(ValueError):
            step(sc, fail, Action(0, 1))


if __name__ == "__main__":
    unittest.main()
