#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import inspect
import json
import os
import sys
from pathlib import Path
from typing import Any, Iterable, List, Tuple

REPO_ROOT = Path(os.environ.get("DCTA_REPO_ROOT", "/home/dcta_benchmark_sim")).expanduser().resolve()
if not (REPO_ROOT / "known_visit_sim").is_dir():
    raise RuntimeError(
        f"known_visit_sim package not found under {REPO_ROOT}; "
        "clone the repository to /home/dcta_benchmark_sim or set DCTA_REPO_ROOT"
    )
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from known_visit_sim.algorithms.registry import load_allocator_class
from known_visit_sim.config import SimConfig, edge_even_start_positions, generate_robot_ids
from known_visit_sim.core.scenario_loader import load_scenarios
from known_visit_sim.core.scheduler import AsyncTrialRunner
from known_visit_sim.generate_scenarios import generate
from known_visit_sim.metrics.export import write_outputs
from known_visit_sim.metrics.summary import build_rows
from known_visit_sim.comms import models as comm_models

Cell = Tuple[int, int]


def generate_scenario_file(path: Path, grid_size: int, num_trials: int, num_targets: int, num_robots: int, seed: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    targets_by_trial = generate(grid_size, num_trials, num_targets, num_robots, seed)
    max_targets = max((len(t) for t in targets_by_trial), default=num_targets)
    fields = ["trial_id"]
    for i in range(1, max_targets + 1):
        fields += [f"target{i}_x", f"target{i}_y"]
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for trial_id, targets in enumerate(targets_by_trial):
            row: dict[str, Any] = {"trial_id": trial_id}
            for i, (x, y) in enumerate(targets, start=1):
                row[f"target{i}_x"] = x
                row[f"target{i}_y"] = y
            writer.writerow(row)


def _construct(cls: type, *candidates: tuple[tuple[Any, ...], dict[str, Any]]) -> Any:
    errors: list[str] = []
    for args, kwargs in candidates:
        try:
            return cls(*args, **kwargs)
        except TypeError as exc:
            errors.append(str(exc))
    raise TypeError(f"Could not construct {cls.__name__}; tried {len(candidates)} signatures: {errors}")


def make_comm_model(name: str, level: str | None) -> Any:
    name = name.lower()
    if name == "ideal":
        return comm_models.IdealModel()
    if name == "bernoulli":
        drop = float(level if level not in (None, "") else 0.0)
        return comm_models.BernoulliModel(drop)
    if name in {"gilbert_elliot", "ge", "gilbert-elliot"}:
        cls = getattr(comm_models, "GilbertElliotModel", None) or getattr(comm_models, "GilbertElliot", None)
        if cls is None:
            raise RuntimeError("known_visit_sim.comms.models has no GilbertElliotModel/GilbertElliot class")
        p_bad_success = float(level if level not in (None, "") else 0.75)
        return _construct(
            cls,
            ((p_bad_success,), {}),
            ((), {"p_bad_success": p_bad_success}),
            ((), {"comm_level": p_bad_success}),
            ((), {}),
        )
    if name in {"rayleigh_style", "rayleigh"}:
        cls = getattr(comm_models, "RayleighStyleModel", None) or getattr(comm_models, "RayleighModel", None)
        if cls is None:
            raise RuntimeError("known_visit_sim.comms.models has no RayleighStyleModel/RayleighModel class")
        sensitivity = float(level if level not in (None, "") else -50.66)
        return _construct(
            cls,
            ((sensitivity,), {}),
            ((), {"sensitivity_dbm": sensitivity}),
            ((), {"comm_level": sensitivity}),
            ((), {}),
        )
    raise ValueError(f"Unknown comm model: {name}")


def apply_horizon(allocator_cls: type, horizon: int) -> list[str]:
    changed: list[str] = []
    for attr in ("BUNDLE_SIZE", "COMMITMENT_HORIZON"):
        if hasattr(allocator_cls, attr):
            setattr(allocator_cls, attr, int(horizon))
            changed.append(attr)
    return changed


def make_config(args: argparse.Namespace) -> SimConfig:
    ids = generate_robot_ids(args.num_robots)
    values = dict(
        grid_size=args.grid_size,
        robot_ids=ids,
        start_positions=edge_even_start_positions(args.grid_size, ids),
        comm_delay_s=args.comm_delay_s,
        comm_delay_jitter_s=args.comm_delay_jitter_s,
        collision_intent_settle_s=args.collision_intent_settle_s,
        debug_max_events=args.debug_max_events,
        condition_id=args.condition_id,
    )
    return SimConfig(**values)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run one known-visit planning-horizon sensitivity condition.")
    parser.add_argument("--scenario-file", required=True)
    parser.add_argument("--generate-scenarios-if-missing", action="store_true")
    parser.add_argument("--num-trials", type=int, default=300)
    parser.add_argument("--max-trials", type=int, default=None)
    parser.add_argument("--num-targets", type=int, default=10)
    parser.add_argument("--grid-size", type=int, default=19)
    parser.add_argument("--num-robots", type=int, default=4)
    parser.add_argument("--algorithm", required=True, help="Known-visit algorithm name, e.g. ACBBA, PI, HIPC, DMCHBA, DGA")
    parser.add_argument("--comm-model", required=True, choices=["ideal", "bernoulli", "gilbert_elliot", "rayleigh_style"])
    parser.add_argument("--comm-level", default="")
    parser.add_argument("--commitment-horizon", type=int, required=True)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--condition-id", default="")
    parser.add_argument("--comm-delay-s", type=float, default=0.04)
    parser.add_argument("--comm-delay-jitter-s", type=float, default=0.01)
    parser.add_argument("--collision-intent-settle-s", type=float, default=0.10)
    parser.add_argument("--debug-max-events", type=int, default=800000)
    args = parser.parse_args()

    scenario_path = Path(args.scenario_file)
    if args.generate_scenarios_if_missing and not scenario_path.exists():
        generate_scenario_file(scenario_path, args.grid_size, args.num_trials, args.num_targets, args.num_robots, args.seed)

    ids = generate_robot_ids(args.num_robots)
    starts = set(edge_even_start_positions(args.grid_size, ids).values())
    scenarios = load_scenarios(scenario_path, args.grid_size, starts)
    if args.max_trials is not None:
        scenarios = scenarios[: args.max_trials]

    allocator_cls = load_allocator_class(args.algorithm)
    changed = apply_horizon(allocator_cls, args.commitment_horizon)
    if not changed:
        print(f"[WARN] {args.algorithm} has no BUNDLE_SIZE or COMMITMENT_HORIZON; horizon is metadata only.")

    cfg = make_config(args)
    comm_level_label = args.comm_level if args.comm_level != "" else "1.0"

    trial_rows: list[dict[str, Any]] = []
    system_rows: list[dict[str, Any]] = []
    robot_rows: list[dict[str, Any]] = []
    target_rows: list[dict[str, Any]] = []

    for idx, scenario in enumerate(scenarios):
        model = make_comm_model(args.comm_model, args.comm_level)
        trial_seed = int(args.seed) + int(getattr(scenario, "trial_id", idx))
        state = AsyncTrialRunner(cfg, allocator_cls, model, trial_seed).run_trial(scenario)
        trial, system, robots, targets = build_rows(
            state,
            args.algorithm,
            args.comm_model,
            comm_level_label,
            str(scenario_path),
        )
        meta = {
            "trial_mode": "known_visit",
            "sensitivity_suite": "known_visit_horizon",
            "sensitivity_parameter": "commitment_horizon",
            "sensitivity_value": args.commitment_horizon,
            "sensitivity_label": f"h{args.commitment_horizon}",
            "condition_id": args.condition_id,
            "num_targets": args.num_targets,
            "num_robots": args.num_robots,
        }
        for row in [trial, system, *robots, *targets]:
            row.update(meta)
        trial_rows.append(trial)
        system_rows.append(system)
        robot_rows.extend(robots)
        target_rows.extend(targets)

        if (idx + 1) % 25 == 0 or (idx + 1) == len(scenarios):
            print(f"completed {idx + 1}/{len(scenarios)} trials for {args.algorithm} h{args.commitment_horizon} {args.comm_model} {comm_level_label}", flush=True)

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    extra_config = {
        "trial_mode": "known_visit",
        "algorithm": args.algorithm,
        "comm_model": args.comm_model,
        "comm_level": comm_level_label,
        "commitment_horizon": args.commitment_horizon,
        "horizon_fields_changed": changed,
        "scenario_file": str(scenario_path),
        "num_trials_requested": args.num_trials,
        "max_trials": args.max_trials,
        "grid_size": args.grid_size,
        "num_robots": args.num_robots,
        "num_targets": args.num_targets,
        "seed": args.seed,
        "condition_id": args.condition_id,
    }
    write_outputs(out_dir, trial_rows, system_rows, robot_rows, target_rows, extra_config)
    (out_dir / "_COMPLETE.txt").write_text("complete\n", encoding="utf-8")


if __name__ == "__main__":
    main()
