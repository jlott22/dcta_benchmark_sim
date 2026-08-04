from __future__ import annotations

from dataclasses import dataclass, field, asdict
from typing import Dict, List, Optional, Tuple

Cell = Tuple[int, int]
Heading = Tuple[int, int]

EAST: Heading = (1, 0)
NORTH: Heading = (0, 1)
SOUTH: Heading = (0, -1)
WEST: Heading = (-1, 0)
LOGIC_REVISION = "dcta_parity_v1"
DEBUG_CAP_REFERENCE_EVENTS = 10_000
DEBUG_CAP_REFERENCE_GRID_SIZE = 19
DEBUG_CAP_REFERENCE_ROBOTS = 4
DEBUG_CAP_MIN_EVENTS = 5_000


def adaptive_debug_max_events(grid_size: int, num_robots: int) -> int:
    """Scale the event cap with grid cells and robot count."""
    if grid_size <= 0:
        raise ValueError("grid_size must be positive")
    if num_robots <= 0:
        raise ValueError("num_robots must be positive")
    numerator = DEBUG_CAP_REFERENCE_EVENTS * grid_size * grid_size * num_robots
    denominator = DEBUG_CAP_REFERENCE_GRID_SIZE**2 * DEBUG_CAP_REFERENCE_ROBOTS
    scaled = (numerator + denominator - 1) // denominator
    return max(DEBUG_CAP_MIN_EVENTS, scaled)


def generate_robot_ids(num_robots: int) -> List[str]:
    """Return deterministic robot IDs, zero-padded through at least 99."""
    if num_robots <= 0:
        raise ValueError("num_robots must be positive")
    return [f"{index:02d}" for index in range(num_robots)]


def edge_even_start_positions(grid_size: int, robot_ids: List[str]) -> Dict[str, Cell]:
    """Place robots evenly along the left edge of a square grid."""
    if grid_size <= 0:
        raise ValueError("grid_size must be positive")
    if not robot_ids:
        raise ValueError("at least one robot is required")
    if len(robot_ids) > grid_size:
        raise ValueError("edge_even requires num_robots <= grid_size")

    if len(robot_ids) == 1:
        return {robot_ids[0]: (0, (grid_size - 1) // 2)}

    denominator = len(robot_ids) - 1
    return {
        rid: (0, round(index * (grid_size - 1) / denominator))
        for index, rid in enumerate(robot_ids)
    }


@dataclass
class SimConfig:
    trial_mode: str = "clue_search"
    grid_size: int = 19
    robot_ids: List[str] = field(default_factory=lambda: generate_robot_ids(4))
    start_positions: Dict[str, Cell] = field(default_factory=dict)
    start_headings: Dict[str, Heading] = field(default_factory=dict)
    robot_start_layout: str = "edge_even"
    condition_id: str = ""
    target_cells_per_robot: Optional[float] = None
    actual_cells_per_robot: Optional[float] = None

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
    collision_goal_backoff_max_s: float = 5.0

    # None selects the grid/robot-scaled safety cap; an integer is an explicit override.
    debug_max_events: Optional[int] = None

    # Output behavior. Metric exports are CSV-only.
    write_parquet: bool = False

    # Optional sensitivity-study controls. None preserves allocator defaults.
    commitment_horizon: Optional[int] = None
    max_candidate_cells: Optional[int] = None

    # Additive run-provenance fields.
    logic_revision: str = LOGIC_REVISION
    study_profile: str = "custom"
    scenario_file_sha256: str = ""
    scenario_selection_sha256: str = ""

    def __post_init__(self) -> None:
        if not self.robot_ids:
            raise ValueError("at least one robot is required")
        if self.debug_max_events is None:
            self.debug_max_events = adaptive_debug_max_events(self.grid_size, len(self.robot_ids))
        elif self.debug_max_events <= 0:
            raise ValueError("debug_max_events must be positive")
        if not self.start_positions:
            if self.robot_start_layout != "edge_even":
                raise ValueError(f"unsupported robot start layout: {self.robot_start_layout}")
            self.start_positions = edge_even_start_positions(self.grid_size, self.robot_ids)
        if not self.start_headings:
            self.start_headings = {rid: EAST for rid in self.robot_ids}

        missing_positions = set(self.robot_ids).difference(self.start_positions)
        missing_headings = set(self.robot_ids).difference(self.start_headings)
        if missing_positions:
            raise ValueError(f"missing start positions for robots: {sorted(missing_positions)}")
        if missing_headings:
            raise ValueError(f"missing start headings for robots: {sorted(missing_headings)}")
        if self.collision_goal_backoff_max_s <= 0:
            raise ValueError("collision_goal_backoff_max_s must be positive")

    def to_dict(self):
        return asdict(self)
