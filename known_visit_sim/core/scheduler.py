from __future__ import annotations

import heapq
import random
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional, Type

from known_visit_sim.algorithms.base import AllocatorBase
from known_visit_sim.comms.bus import MessageBus
from known_visit_sim.comms.models import CommunicationModel
from known_visit_sim.config import SimConfig
from .planner import AStarPlanner
from .robot import RobotShell, StepResult
from .types import TrialScenario
from .world import World


@dataclass(order=True)
class WakeEvent:
    time_s: float
    order: int
    rid: str = field(compare=False)


@dataclass
class TrialState:
    cfg: SimConfig
    scenario: TrialScenario
    world: World
    robots: Dict[str, RobotShell]
    bus: MessageBus
    planner: AStarPlanner
    clock_s: float = 0.0
    events_processed: int = 0
    done: bool = False


class AsyncTrialRunner:
    def __init__(self, cfg: SimConfig, allocator_cls: Type[AllocatorBase],
                 comm_model: CommunicationModel, seed: int = 0) -> None:
        self.cfg = cfg
        self.allocator_cls = allocator_cls
        self.comm_model = comm_model
        self.rng = random.Random(seed)

    def new_trial(self, scenario: TrialScenario) -> TrialState:
        bus = MessageBus(self.comm_model, self.cfg.comm_delay_s, self.cfg.comm_delay_jitter_s, self.rng)
        world = World(self.cfg.grid_size, scenario)
        planner = AStarPlanner(
            self.cfg.grid_size, self.cfg.move_cost, self.cfg.turn_cost,
            self.cfg.visited_step_penalty, self.cfg.reward_factor, self.cfg.min_step_cost,
        )
        robots = {
            rid: RobotShell(
                rid, self.cfg.start_positions[rid], self.cfg.start_headings[rid],
                self.cfg, world, bus, self.allocator_cls(),
            )
            for rid in self.cfg.robot_ids
        }
        # Registration must finish before initial state is broadcast so every
        # peer has the same opportunity (subject to the communication model)
        # to learn each starting location.
        for robot in robots.values():
            robot.publish_state()
        return TrialState(self.cfg, scenario, world, robots, bus, planner)

    def initial_queue(self, state: TrialState) -> List[WakeEvent]:
        queue: List[WakeEvent] = []
        span = self.cfg.async_step_mean_s * max(0.0, self.cfg.async_initial_spread_s)
        for index, rid in enumerate(state.robots):
            heapq.heappush(queue, WakeEvent(self.rng.uniform(0.0, span) if span else 0.0, index, rid))
        return queue

    def run_trial(self, scenario: TrialScenario,
                  on_step: Optional[Callable[[TrialState, RobotShell, StepResult], None]] = None) -> TrialState:
        state = self.new_trial(scenario)
        queue = self.initial_queue(state)
        order = len(queue)
        while queue and not state.done:
            event = heapq.heappop(queue)
            state.clock_s = event.time_s
            state.bus.pump(state.clock_s)
            robot = state.robots[event.rid]
            result = robot.step(state.clock_s, state.planner)
            state.events_processed += 1
            if on_step:
                on_step(state, robot, result)
            if state.world.all_targets_completed():
                state.done = True
                break
            if state.events_processed >= self.cfg.debug_max_events:
                raise RuntimeError(f"Debug safety cap reached in trial {scenario.trial_id}")
            order += 1
            heapq.heappush(queue, WakeEvent(state.clock_s + self._interval_for(result), order, event.rid))
        return state

    def _interval_for(self, result: StepResult) -> float:
        if result.reason == "turn":
            return max(self.cfg.turn_quarter_s, 1e-3)
        if result.reason == "intent_sync":
            return max(self.cfg.collision_intent_settle_s, 1e-3)
        if result.reason == "path_failed":
            return max(self.cfg.replan_delay_s, 1e-3)
        if result.reason in {"no_goal", "idle"}:
            return max(self.cfg.no_goal_delay_s, 1e-3)
        if result.moved:
            jitter = self.rng.uniform(-self.cfg.async_step_jitter_s, self.cfg.async_step_jitter_s)
            return max(1e-3, min(self.cfg.async_max_delay_s, max(self.cfg.async_min_delay_s,
                                                                  self.cfg.async_step_mean_s + jitter)))
        return max(result.time_cost_s, 1e-3)
