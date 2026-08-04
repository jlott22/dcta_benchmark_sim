from __future__ import annotations

import unittest

from benchmark_sim.config import (
    SimConfig,
    adaptive_debug_max_events as benchmark_cap,
    generate_robot_ids,
)
from known_visit_sim.config import (
    SimConfig as KnownSimConfig,
    adaptive_debug_max_events as known_cap,
    generate_robot_ids as generate_known_robot_ids,
)


class AdaptiveDebugCapTests(unittest.TestCase):
    def test_reference_condition_uses_ten_thousand_events(self) -> None:
        self.assertEqual(benchmark_cap(19, 4), 10_000)
        self.assertEqual(known_cap(19, 4), 10_000)

    def test_small_conditions_retain_five_thousand_event_floor(self) -> None:
        self.assertEqual(benchmark_cap(14, 1), 5_000)
        self.assertEqual(known_cap(14, 1), 5_000)

    def test_large_conditions_scale_with_cells_and_robots(self) -> None:
        expected = (10_000 * 34 * 34 * 24 + (19 * 19 * 4) - 1) // (19 * 19 * 4)
        self.assertEqual(benchmark_cap(34, 24), expected)
        self.assertEqual(known_cap(34, 24), expected)

    def test_config_uses_adaptive_default(self) -> None:
        cfg = SimConfig(grid_size=19, robot_ids=generate_robot_ids(4))
        known_cfg = KnownSimConfig(grid_size=19, robot_ids=generate_known_robot_ids(4))
        self.assertEqual(cfg.debug_max_events, 10_000)
        self.assertEqual(known_cfg.debug_max_events, 10_000)

    def test_explicit_cap_overrides_adaptive_default(self) -> None:
        cfg = SimConfig(grid_size=34, robot_ids=generate_robot_ids(24), debug_max_events=12_345)
        known_cfg = KnownSimConfig(
            grid_size=34,
            robot_ids=generate_known_robot_ids(24),
            debug_max_events=12_345,
        )
        self.assertEqual(cfg.debug_max_events, 12_345)
        self.assertEqual(known_cfg.debug_max_events, 12_345)


if __name__ == "__main__":
    unittest.main()
