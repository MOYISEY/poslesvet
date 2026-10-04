import unittest
from dataclasses import replace
from model import Action, initial, step, won
from scenarios import SCENARIOS
from solver import solve, replay


def actions(*labels):
    return tuple(Action() if label == "wait" else
                 Action(int(label[1:]), 1 if label[0] == "N" else 2) for label in labels)


class ScenarioTests(unittest.TestCase):
    def test_all_known_winning_paths_replay_without_loss(self):
        paths = (
            actions("W0", "W2", "W4", "W6"),
            actions("N1", "N0", "N2", "N3", "N2"),
            actions("N0", "wait", "W1", "N4", "N0"),
            actions("N0", "N4", "N1", "W2", "W2", "N4"),
            actions("N3", "W0", "W2", "W4", "N6", "W7", "W4", "N7",
                    "N2", "N6", "W0", "W4", "W2"),
        )
        for sc, path in zip(SCENARIOS, paths):
            with self.subTest(scenario=sc.name):
                end, rows = replay(sc, path)
                self.assertTrue(won(sc, end))
                self.assertFalse(any(row["lost"] for row in rows))

    def test_designer_claims_independently_exhaustive(self):
        sc = SCENARIOS[3]
        best, stats = solve(sc)
        self.assertTrue(stats["exhaustive"])
        self.assertEqual(len(best), 6)
        faster, stats = solve(replace(sc, limit=5))
        self.assertIsNone(faster)
        self.assertTrue(stats["exhaustive"])
        narrow, stats = solve(sc, wide=False)
        self.assertIsNone(narrow)
        self.assertTrue(stats["exhaustive"])

    def test_wider_light_can_destroy_all_six_turn_solutions(self):
        sc = SCENARIOS[3]
        state = step(sc, initial(sc), Action(0, 1)).state
        narrow = step(sc, state, Action(4, 1))
        wide = step(sc, state, Action(3, 2))
        self.assertEqual(narrow.state.positions, wide.state.positions)
        self.assertEqual(narrow.moved, ("C",))
        self.assertEqual(wide.moved, ("C",))
        safe, _ = solve(sc, start=narrow.state)
        unsafe, stats = solve(sc, start=wide.state)
        self.assertIsNotNone(safe)
        self.assertIsNone(unsafe)
        self.assertTrue(stats["exhaustive"])

    def test_shadow_changes_optimal_cost_in_two_crossings(self):
        for sc in SCENARIOS[1:3]:
            with self.subTest(scenario=sc.name):
                normal, a = solve(sc)
                absent, b = solve(sc, shadows=False)
                self.assertTrue(a["exhaustive"] and b["exhaustive"])
                self.assertEqual((len(normal), len(absent)), (5, 4))

    def test_fast_unshadowed_exit_plan_loses_ship_on_turn_three(self):
        sc = SCENARIOS[2]
        _, rows = replay(sc, actions("N0", "W1", "N4"))
        self.assertEqual(rows[-1]["lost"], ("B",))
        self.assertEqual(rows[-1]["saved"], ("A",))

    def test_teaching_wide_beam_is_required(self):
        sc = SCENARIOS[0]
        path, stats = solve(sc, wide=False)
        self.assertIsNone(path)
        self.assertTrue(stats["exhaustive"])


if __name__ == "__main__":
    unittest.main()
