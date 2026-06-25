from __future__ import annotations

import argparse
from pathlib import Path

from benchmark_sim.algorithms.registry import load_allocator_class
from benchmark_sim.comms.models import make_comm_model
from benchmark_sim.config import SimConfig
from benchmark_sim.core.scenario_loader import load_scenarios
from benchmark_sim.core.scheduler import AsyncTrialRunner
from benchmark_sim.core.types import TrialScenario
from benchmark_sim.metrics.export import write_outputs
from benchmark_sim.metrics.summary import build_rows


def parse_positive_int(value: str) -> int:
    try:
        parsed = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("must be a positive integer") from exc
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return parsed


def parse_max_candidate_cells(value: str) -> int | None:
    if str(value).lower() == "all":
        return None
    return parse_positive_int(value)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Run DCTA benchmark trials.")
    p.add_argument("--scenario-file", default=None, help="CSV/JSON scenario file from clue-object generator.")
    p.add_argument("--trial-mode", default="clue_search", choices=["clue_search", "coverage"])
    p.add_argument("--num-trials", type=int, default=1, help="Number of generated trials for coverage mode.")
    p.add_argument("--algorithm", required=True, help="Allocator class as module.path:ClassName.")
    p.add_argument("--algorithm-name", default=None, help="Optional display name for outputs.")
    p.add_argument("--comm-model", default="ideal", choices=["ideal", "bernoulli", "gilbert_elliot", "rayleigh_style"])
    p.add_argument("--comm-level", type=float, default=None,
                   help="Model-specific level: Bernoulli drop probability, GE bad-state success, or Rayleigh sensitivity dBm.")
    p.add_argument("--max-trials", type=int, default=None)
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--out-dir", default="runs/default")
    p.add_argument("--grid-size", type=int, default=19)
    p.add_argument("--target-decay-exp", type=float, default=1.0)
    p.add_argument(
        "--commitment-horizon",
        type=parse_positive_int,
        default=None,
        help="Override bundle/commitment horizon for ACBBA, PI, HIPC, DMCHBA, and DGA. CBAA ignores this.",
    )
    p.add_argument(
        "--max-candidate-cells",
        type=parse_max_candidate_cells,
        default=None,
        help="Top-K candidate prefilter for CBAA, ACBBA, PI, HIPC, DMCHBA, and DGA; use 'all' or omit for full candidates.",
    )
    p.add_argument("--no-parquet", action="store_true", help="Deprecated; metric outputs are always CSV-only.")
    return p.parse_args()


def scenarios_for_args(args: argparse.Namespace) -> list[TrialScenario]:
    if args.trial_mode == "coverage":
        if args.num_trials < 1:
            raise ValueError("--num-trials must be at least 1 for coverage mode")
        return [
            TrialScenario(trial_id=i, target=None, clues=[], metadata={"generated": "coverage"})
            for i in range(args.num_trials)
        ]
    if not args.scenario_file:
        raise ValueError("--scenario-file is required for clue_search mode")
    return load_scenarios(args.scenario_file, max_trials=args.max_trials)


def main() -> None:
    args = parse_args()
    cfg = SimConfig(
        trial_mode=args.trial_mode,
        grid_size=args.grid_size,
        target_decay_exp=args.target_decay_exp,
        write_parquet=False,
        commitment_horizon=args.commitment_horizon,
        max_candidate_cells=args.max_candidate_cells,
    )
    allocator_cls = load_allocator_class(args.algorithm)
    algorithm_name = args.algorithm_name or getattr(allocator_cls, "name", allocator_cls.__name__)
    comm_model = make_comm_model(args.comm_model, args.comm_level)
    comm_level = comm_model.level_label()
    scenarios = scenarios_for_args(args)

    trial_summary_rows = []
    system_performance_rows = []
    robot_performance_rows = []

    for i, scenario in enumerate(scenarios):
        runner = AsyncTrialRunner(cfg=cfg, allocator_cls=allocator_cls, comm_model=comm_model, seed=args.seed + scenario.trial_id * 1009)
        state = runner.run_trial(scenario)
        trial_row, system_row, robot_rows = build_rows(
            state=state,
            algorithm_name=algorithm_name,
            comm_model=args.comm_model,
            comm_level=comm_level,
            scenario_file=str(Path(args.scenario_file)) if args.scenario_file else "",
        )
        trial_summary_rows.append(trial_row)
        system_performance_rows.append(system_row)
        robot_performance_rows.extend(robot_rows)
        if args.trial_mode == "coverage":
            print(
                f"completed trial {scenario.trial_id}: "
                f"steps={system_row['total_team_steps']} unique={system_row['unique_cells_searched']}"
            )
        else:
            print(f"completed trial {scenario.trial_id}: steps={system_row['total_team_steps']} post_clue={system_row['post_clue_steps_to_find']}")

    write_outputs(
        out_dir=args.out_dir,
        trial_summary_rows=trial_summary_rows,
        system_performance_rows=system_performance_rows,
        robot_performance_rows=robot_performance_rows,
        config={
            "sim_config": cfg.to_dict(),
            "algorithm": args.algorithm,
            "algorithm_name": algorithm_name,
            "comm_model": args.comm_model,
            "comm_level": comm_level,
            "scenario_file": str(Path(args.scenario_file)) if args.scenario_file else "",
            "trial_mode": args.trial_mode,
            "seed": args.seed,
        },
        write_parquet=False,
    )
    print(f"outputs written to {args.out_dir}")


if __name__ == "__main__":
    main()
