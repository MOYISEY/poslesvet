from model import Ship, Scenario

SCENARIOS = (
    Scenario("01_parallel_lanes", (
        Ship("A", (0, 2, 4, 6)), Ship("B", (1, 3, 5, 7))), 4),
    Scenario("02_crossing", (
        Ship("A", (1, 0, 3)), Ship("B", (2, 3, 2))), 5),
    Scenario("03_echo_at_exit", (
        Ship("A", (0, 2, 4)), Ship("B", (1, 4, 0))), 5),
    Scenario("04_designer_crossing", (
        Ship("A", (2, 3, 4)), Ship("B", (0, 1, 2, 3)),
        Ship("C", (4, 3, 2))), 6),
    Scenario("05_six_ship_probe", (
        Ship("A", (0, 2, 4, 6)), Ship("B", (1, 3, 5, 7)),
        Ship("C", (3, 2, 6, 0)),
        Ship("D", (4, 1, 5, 2), 6), Ship("E", (5, 2, 6, 3), 6),
        Ship("F", (7, 6, 0, 4), 6)), 18),
    Scenario("06_tide_crossing", (
        Ship("A", (2, 3, 4)), Ship("B", (0, 1, 2, 3)),
        Ship("C", (4, 3, 2))), 5, 3, ((3, 12),)),
)
