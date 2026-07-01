from __future__ import annotations

from dataclasses import dataclass, field
from math import isfinite
from typing import Any, Dict, List, Optional, Protocol, Sequence, Set, Tuple

from known_visit_sim.core.types import AllocationDecision, Cell, Observation
from known_visit_sim.comms.message import Message


class RobotAPI(Protocol):
    rid: str
    pos: Cell
    heading: Tuple[int, int]
    grid_size: int

    @property
    def active_tasks(self) -> Set[Cell]: ...

    @property
    def searched(self) -> Set[Cell]: ...

    @property
    def target_p(self) -> Dict[Cell, float]: ...

    @property
    def peer_positions(self) -> Dict[str, Cell]: ...

    def publish_algorithm_message(self, category: str, payload: Dict[str, Any]) -> None: ...


class AllocatorBase:
    """Base class for task-allocation algorithms.

    The simulator does not implement CBAA, ACBBA, DMCHBA, HIPC, PI, or
    Silent Can-Win here. Add those algorithms by subclassing this class.

    Algorithms should make all task-allocation decisions in `choose_goal` and
    may publish allocation-specific messages with `robot.publish_algorithm_message`.
    """

    name: str = "base"

    def initialize(self, robot: RobotAPI) -> None:
        pass

    def handle_message(self, robot: RobotAPI, message: Message) -> None:
        """Receive droppable allocation-specific messages.

        Core state and collision-intent messages are handled by the simulator
        before this hook. Unknown categories are passed through here.
        """
        pass

    def on_observation(self, robot: RobotAPI, observation: Observation) -> None:
        """Called after the robot enters a cell and possibly visits a target."""
        pass

    def on_task_set_changed(self, robot: RobotAPI) -> bool:
        """Allow an allocator to reset cached paths after local task completion inference."""
        return True

    def recover_stalled_allocation(self, robot: RobotAPI) -> bool:
        """Clear local allocation consensus after a prolonged no-goal stall.

        This is deliberately local: it emits no recovery, release, refresh, or
        heartbeat message. The next normal allocation decision may emit the
        same claim message it would use during ordinary allocation.
        """
        reset = getattr(self, "_reset_cbaa_state", None)
        if not callable(reset):
            return False
        reset(robot)
        return True

    def choose_goal(self, robot: RobotAPI) -> AllocationDecision:
        """Return the next active target cell."""
        raise NotImplementedError

    def debug_state(self) -> Dict[str, Any]:
        return {}

    def _coverage_mode(self, robot: RobotAPI) -> bool:
        # Known-target visits always use route-distance allocation.
        return True

    def _is_active_task(self, robot: RobotAPI, cell: Cell) -> bool:
        return cell in (getattr(robot, "active_tasks", set()) or set())

    def _assigned_row_band(self, robot: RobotAPI) -> Tuple[int, int]:
        """Return this robot's deterministic, approximately even row partition."""
        grid_size = int(getattr(robot, "grid_size", 0))
        cfg = getattr(robot, "cfg", None)
        robot_ids = [str(rid) for rid in getattr(cfg, "robot_ids", [])]
        rid = str(robot.rid)
        if grid_size <= 0:
            raise ValueError("grid_size must be positive")
        if not robot_ids or rid not in robot_ids:
            return (0, grid_size - 1)

        robot_count = len(robot_ids)
        index = robot_ids.index(rid)
        rows_per_robot, extra_rows = divmod(grid_size, robot_count)
        start = index * rows_per_robot + min(index, extra_rows)
        height = rows_per_robot + (1 if index < extra_rows else 0)
        if height <= 0:
            raise ValueError("row-band assignment requires robot_count <= grid_size")
        return (start, start + height - 1)

    def _planning_horizon(self, robot: RobotAPI, default: int) -> int:
        cfg = getattr(robot, "cfg", None)
        override = getattr(cfg, "commitment_horizon", None)
        if override is None:
            return int(default)
        horizon = int(override)
        if horizon <= 0:
            raise ValueError("commitment_horizon must be positive")
        return horizon

    def _candidate_limit(self, robot: RobotAPI) -> Optional[int]:
        cfg = getattr(robot, "cfg", None)
        value = getattr(cfg, "max_candidate_cells", None)
        if value is None:
            value = getattr(self, "MAX_CANDIDATE_CELLS", None)
        if value is None:
            return None
        if isinstance(value, str) and value.lower() == "all":
            return None
        limit = int(value)
        if limit <= 0:
            raise ValueError("max_candidate_cells must be positive or 'all'")
        return limit

    def _filter_candidate_cells(self, robot: RobotAPI, candidates: Sequence[Cell]) -> List[Cell]:
        ordered = list(candidates)
        limit = self._candidate_limit(robot)
        setattr(robot, "candidate_count_before_filter", len(ordered))
        setattr(robot, "candidate_count_after_filter", len(ordered) if limit is None else min(len(ordered), limit))
        setattr(robot, "max_candidate_cells", limit)
        if limit is None or limit >= len(ordered):
            return ordered

        origin = self._normalize_filter_cell(getattr(robot, "pos", None)) or (0, 0)

        def ranking(cell: Cell) -> Tuple[float, int, Cell]:
            probability = self._filter_probability(robot, cell)
            distance = self._manhattan_distance(cell, origin)
            return (-probability, distance, cell)

        filtered = sorted(ordered, key=ranking)[:limit]
        setattr(robot, "candidate_count_after_filter", len(filtered))
        return filtered

    def _filter_probability(self, robot: RobotAPI, cell: Cell) -> float:
        target_p = getattr(robot, "target_p", {}) or {}
        try:
            value = target_p.get(cell, 0.0)
        except AttributeError:
            try:
                value = target_p[cell[1]][cell[0]]
            except Exception:
                value = 0.0
        try:
            probability = float(value)
        except Exception:
            return 0.0
        if not isfinite(probability):
            return 0.0
        return max(0.0, probability)

    def _normalize_filter_cell(self, cell: Any) -> Optional[Cell]:
        try:
            if cell is None or len(cell) != 2:
                return None
            return (int(cell[0]), int(cell[1]))
        except Exception:
            return None

    @staticmethod
    def _manhattan_distance(a: Cell, b: Cell) -> int:
        return abs(int(a[0]) - int(b[0])) + abs(int(a[1]) - int(b[1]))
