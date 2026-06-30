from __future__ import annotations

import argparse
from pathlib import Path

from known_visit_sim.algorithms.registry import load_allocator_class
from known_visit_sim.comms.models import make_comm_model
from known_visit_sim.config import EAST, SimConfig, edge_even_start_positions, generate_robot_ids
from known_visit_sim.core.scenario_loader import load_scenarios
from known_visit_sim.core.scheduler import AsyncTrialRunner
from known_visit_sim.metrics.export import write_outputs
from known_visit_sim.metrics.summary import build_rows


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return parsed


def candidate_limit(value: str) -> int | None:
    return None if value.lower() == "all" else positive_int(value)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run static collaborative known-target visits.")
    parser.add_argument("--scenario-file", required=True)
    parser.add_argument("--algorithm", required=True)
    parser.add_argument("--algorithm-name", default=None)
    parser.add_argument("--comm-model", default="ideal",
                        choices=["ideal", "bernoulli", "gilbert_elliot", "rayleigh_style"])
    parser.add_argument("--comm-level", type=float, default=None)
    parser.add_argument("--max-trials", type=int, default=None)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--out-dir", default="runs/known_visit/default")
    parser.add_argument("--grid-size", type=positive_int, default=19)
    parser.add_argument("--num-robots", type=positive_int, default=4)
    parser.add_argument("--robot-start-layout", choices=["edge_even"], default="edge_even")
    parser.add_argument("--condition-id", default="")
    parser.add_argument("--commitment-horizon", type=positive_int, default=None)
    parser.add_argument("--max-candidate-cells", type=candidate_limit, default=None)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    robot_ids = generate_robot_ids(args.num_robots)
    starts = edge_even_start_positions(args.grid_size, robot_ids)
    cfg = SimConfig(
        grid_size=args.grid_size,
        robot_ids=robot_ids,
        start_positions=starts,
        start_headings={rid: EAST for rid in robot_ids},
        robot_start_layout=args.robot_start_layout,
        condition_id=args.condition_id,
        commitment_horizon=args.commitment_horizon,
        max_candidate_cells=args.max_candidate_cells,
    )
    scenarios = load_scenarios(
        args.scenario_file, args.grid_size, set(starts.values()), args.max_trials
    )
    allocator_cls = load_allocator_class(args.algorithm)
    algorithm = args.algorithm_name or getattr(allocator_cls, "name", allocator_cls.__name__)
    comm = make_comm_model(args.comm_model, args.comm_level)
    comm_level = comm.level_label()
    trial_rows, system_rows, robot_rows, target_rows = [], [], [], []
    for scenario in scenarios:
        state = AsyncTrialRunner(
            cfg, allocator_cls, make_comm_model(args.comm_model, args.comm_level),
            args.seed + scenario.trial_id * 1009,
        ).run_trial(scenario)
        trial, system, robots, targets = build_rows(
            state, algorithm, args.comm_model, comm_level, str(Path(args.scenario_file))
        )
        trial_rows.append(trial)
        system_rows.append(system)
        robot_rows.extend(robots)
        target_rows.extend(targets)
        print(f"completed trial {scenario.trial_id}: targets={system['completed_target_count']}/{system['target_count']} steps={system['total_team_steps']}")
    write_outputs(
        args.out_dir, trial_rows, system_rows, robot_rows, target_rows,
        {"sim_config": cfg.to_dict(), "algorithm": args.algorithm,
         "algorithm_name": algorithm, "comm_model": args.comm_model,
         "comm_level": comm_level, "scenario_file": args.scenario_file, "seed": args.seed},
    )
    print(f"outputs written to {args.out_dir}")


if __name__ == "__main__":
    main()
