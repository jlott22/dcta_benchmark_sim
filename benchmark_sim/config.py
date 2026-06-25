from __future__ import annotations

from dataclasses import dataclass, field, asdict
from typing import Dict, List, Optional, Tuple

Cell = Tuple[int, int]
Heading = Tuple[int, int]

EAST: Heading = (1, 0)
NORTH: Heading = (0, 1)
SOUTH: Heading = (0, -1)
WEST: Heading = (-1, 0)


@dataclass
class SimConfig:
    trial_mode: str = "clue_search"
    grid_size: int = 19
    robot_ids: List[str] = field(default_factory=lambda: ["00", "01", "02", "03"])
    start_positions: Dict[str, Cell] = field(default_factory=lambda: {
        "00": (0, 0),
        "01": (0, 5),
        "02": (0, 10),
        "03": (0, 15),
    })
    start_headings: Dict[str, Heading] = field(default_factory=lambda: {
        "00": EAST,
        "01": EAST,
        "02": EAST,
        "03": EAST,
    })

    # Belief/reward parameters. Belief uses target_p only.
    target_decay_exp: float = 1.0
    reward_factor: float = 5.0

    # Planning costs.
    move_cost: float = 1.0
    turn_cost: float = 0.3
    visited_step_penalty: float = 4.0
    min_step_cost: float = 0.01

    # Asynchronous scheduler timing.
    async_step_mean_s: float = 1.60
    async_step_jitter_s: float = 0.10
    async_min_delay_s: float = 1.50
    async_max_delay_s: float = 1.70
    async_initial_spread_s: float = 0.10
    async_tick_span_s: float = 0.25
    turn_quarter_s: float = 0.30
    replan_delay_s: float = 0.30
    no_goal_delay_s: float = 0.50

    # Communication timing.
    comm_delay_s: float = 0.04
    comm_delay_jitter_s: float = 0.01
    collision_intent_settle_s: float = 0.10

    # Safety cap is for implementation bugs, not an experimental timeout.
    debug_max_events: int = 50_000

    # Output behavior. Metric exports are CSV-only.
    write_parquet: bool = False

    # Optional sensitivity-study controls. None preserves allocator defaults.
    commitment_horizon: Optional[int] = None
    max_candidate_cells: Optional[int] = None

    def to_dict(self):
        return asdict(self)
