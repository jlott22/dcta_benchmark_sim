#!/usr/bin/env python3
"""Run one coverage trial against an explicit frozen source snapshot."""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--trial-id", type=int, required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--algorithm", required=True)
    parser.add_argument("--algorithm-name", required=True)
    parser.add_argument("--condition-id", required=True)
    parser.add_argument("--comm-model", default="gilbert_elliot")
    parser.add_argument("--comm-level", type=float, required=True)
    parser.add_argument("--commitment-horizon", type=int, default=None)
    parser.add_argument("--debug-max-events", type=int, required=True)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--grid-size", type=int, default=19)
    parser.add_argument("--num-robots", type=int, default=4)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    runtime_root = Path(args.runtime_root).resolve()
    out_dir = Path(args.out_dir).resolve()
    sys.path.insert(0, str(runtime_root))

    from benchmark_sim.algorithms.registry import load_allocator_class
    from benchmark_sim.comms.models import make_comm_model
    from benchmark_sim.config import (
        EAST,
        SimConfig,
        edge_even_start_positions,
        generate_robot_ids,
    )
    from benchmark_sim.core.scheduler import AsyncTrialRunner
    from benchmark_sim.core.types import TrialScenario
    from benchmark_sim.metrics.export import write_outputs
    from benchmark_sim.metrics.summary import build_rows
    from benchmark_sim.run_trials import failure_rows

    scenario = TrialScenario(
        trial_id=args.trial_id,
        target=None,
        clues=[],
        metadata={"generated": "coverage"},
    )
    robot_ids = generate_robot_ids(args.num_robots)
    start_positions = edge_even_start_positions(args.grid_size, robot_ids)
    cfg = SimConfig(
        trial_mode="coverage",
        grid_size=args.grid_size,
        robot_ids=robot_ids,
        start_positions=start_positions,
        start_headings={rid: EAST for rid in robot_ids},
        robot_start_layout="edge_even",
        condition_id=args.condition_id,
        target_cells_per_robot=None,
        actual_cells_per_robot=None,
        target_decay_exp=1.0,
        write_parquet=False,
        commitment_horizon=args.commitment_horizon,
        max_candidate_cells=None,
        debug_max_events=args.debug_max_events,
    )
    allocator_cls = load_allocator_class(args.algorithm)
    comm_model = make_comm_model(args.comm_model, args.comm_level)
    comm_level_label = comm_model.level_label()
    started = time.time()

    try:
        runner = AsyncTrialRunner(
            cfg=cfg,
            allocator_cls=allocator_cls,
            comm_model=comm_model,
            seed=args.seed + scenario.trial_id * 1009,
        )
        state = runner.run_trial(scenario)
        trial_row, system_row, robot_rows = build_rows(
            state=state,
            algorithm_name=args.algorithm_name,
            comm_model=args.comm_model,
            comm_level=comm_level_label,
            scenario_file="",
        )
        trial_row["trial_status"] = "completed"
        system_row["trial_status"] = "completed"
        for row in robot_rows:
            row["trial_status"] = "completed"
    except Exception as exc:
        trial_row, system_row, robot_rows = failure_rows(
            scenario=scenario,
            args=args,
            cfg=cfg,
            algorithm_name=args.algorithm_name,
            comm_level=comm_level_label,
            scenario_file="",
            exc=exc,
        )

    config = {
        "sim_config": cfg.to_dict(),
        "algorithm": args.algorithm,
        "algorithm_name": args.algorithm_name,
        "comm_model": args.comm_model,
        "comm_level": comm_level_label,
        "scenario_file": "",
        "trial_mode": "coverage",
        "seed": args.seed,
        "snapshot_runtime": str(runtime_root),
        "single_trial_id": args.trial_id,
    }
    write_outputs(
        out_dir=out_dir,
        trial_summary_rows=[trial_row],
        system_performance_rows=[system_row],
        robot_performance_rows=robot_rows,
        config=config,
        write_parquet=False,
    )
    result = {
        "trial_id": args.trial_id,
        "status": trial_row.get("trial_status", ""),
        "failure_type": trial_row.get("failure_type", ""),
        "failure_message": trial_row.get("failure_message", ""),
        "debug_max_events": args.debug_max_events,
        "elapsed_seconds": time.time() - started,
    }
    (out_dir / "worker_result.json").write_text(
        json.dumps(result, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(result), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
