from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, Protocol, Set, Tuple

from benchmark_sim.core.types import AllocationDecision, Cell, Observation
from benchmark_sim.comms.message import Message


class RobotAPI(Protocol):
    rid: str
    pos: Cell
    heading: Tuple[int, int]
    grid_size: int

    @property
    def known_clues(self) -> list[Cell]: ...

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

        Core simulator messages such as state, clue, target, and collision_intent
        are handled by the simulator before this hook. Unknown categories are
        passed through here.
        """
        pass

    def on_observation(self, robot: RobotAPI, observation: Observation) -> None:
        """Called after the robot searches a cell and detects clue/target if present."""
        pass

    def choose_goal(self, robot: RobotAPI) -> AllocationDecision:
        """Return the next task/search cell.

        Pre-clue sweeping behavior belongs in the algorithm implementation, not
        in the simulator.
        """
        raise NotImplementedError

    def debug_state(self) -> Dict[str, Any]:
        return {}
