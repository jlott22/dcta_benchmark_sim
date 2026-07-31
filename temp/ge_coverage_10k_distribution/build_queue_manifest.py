#!/usr/bin/env python3
"""Build the temporary 10k-cap GE coverage worker queue."""
from __future__ import annotations

import argparse
import csv
import json
import time
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
DIST_ROOT = Path(__file__).resolve().parent
RUN_ROOT = REPO_ROOT / "runs" / "coverage_core_100_ge_bursty_rho08"
TRANSFER_MANIFEST = RUN_ROOT / "TRANSFER_MANIFEST.json"
DEFAULT_OUTPUT = DIST_ROOT / "queue_manifest.json"
EXPECTED_TRIALS = 100


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def trial_ids(path: Path) -> set[int]:
    return {int(row["trial_id"]) for row in read_csv(path)}


def flag_value(command: list[str], flag: str) -> str | None:
    if flag not in command:
        return None
    index = command.index(flag)
    if index + 1 >= len(command):
        raise RuntimeError(f"missing value after {flag}")
    return command[index + 1]


def micro_shards_for_tasks(tasks: list[dict], target_seconds: float) -> list[dict]:
    shards: list[dict] = []
    current: list[dict] = []
    current_seconds = 0.0
    for task in sorted(tasks, key=lambda item: (-item["estimated_seconds"], item["condition_id"], item["trial_id"])):
        if current and current_seconds + task["estimated_seconds"] > target_seconds:
            shards.append(
                {
                    "micro_shard": f"m{len(shards) + 1:03d}",
                    "estimated_seconds": round(current_seconds, 3),
                    "tasks": current,
                }
            )
            current = []
            current_seconds = 0.0
        current.append(task)
        current_seconds += task["estimated_seconds"]
    if current:
        shards.append(
            {
                "micro_shard": f"m{len(shards) + 1:03d}",
                "estimated_seconds": round(current_seconds, 3),
                "tasks": current,
            }
        )
    return shards


def assign_workers(micro_shards: list[dict], worker_count: int) -> dict[str, dict]:
    workers = {
        f"{index:02d}": {
            "worker": f"{index:02d}",
            "estimated_seconds": 0.0,
            "task_count": 0,
            "micro_shards": [],
        }
        for index in range(1, worker_count + 1)
    }
    for shard in sorted(micro_shards, key=lambda item: -item["estimated_seconds"]):
        worker = min(workers.values(), key=lambda item: (item["estimated_seconds"], item["worker"]))
        worker["micro_shards"].append(shard)
        worker["estimated_seconds"] += shard["estimated_seconds"]
        worker["task_count"] += len(shard["tasks"])
    for worker in workers.values():
        worker["estimated_seconds"] = round(worker["estimated_seconds"], 3)
        worker["micro_shard_ids"] = [shard["micro_shard"] for shard in worker["micro_shards"]]
    return workers


def build_manifest(worker_count: int, cap: int, target_micro_shard_seconds: float) -> dict:
    transfer = json.loads(TRANSFER_MANIFEST.read_text(encoding="utf-8"))
    tasks: list[dict] = []
    for condition in transfer["conditions"]:
        algorithm = condition["algorithm"].upper()
        if algorithm not in {"DGA", "DMCHBA"}:
            continue
        condition_dir = REPO_ROOT / condition["condition_relative"]
        present = trial_ids(condition_dir / "trial_summary.csv")
        missing = sorted(set(range(int(condition.get("expected_trials", EXPECTED_TRIALS)))) - present)
        if not missing:
            continue
        source_command = condition["source_command"]
        algorithm_class = flag_value(source_command, "--algorithm")
        if algorithm_class is None:
            raise RuntimeError(f"missing --algorithm in source command for {condition['condition_id']}")
        commitment_horizon = flag_value(source_command, "--commitment-horizon")
        estimate = float(condition.get("estimated_seconds_per_trial") or 1.0)
        for trial_id in missing:
            tasks.append(
                {
                    "algorithm_name": condition["algorithm"],
                    "algorithm_class": algorithm_class,
                    "condition_id": condition["condition_id"],
                    "condition_relative": condition["condition_relative"],
                    "trial_id": trial_id,
                    "comm_model": "gilbert_elliot",
                    "comm_level": float(condition["comm_level_stationary_delivery"]),
                    "commitment_horizon": int(commitment_horizon) if commitment_horizon is not None else None,
                    "seed": 0,
                    "estimated_seconds": estimate,
                }
            )
    micro_shards = micro_shards_for_tasks(tasks, target_micro_shard_seconds)
    workers = assign_workers(micro_shards, worker_count)
    assigned = [
        (task["condition_id"], task["trial_id"])
        for worker in workers.values()
        for shard in worker["micro_shards"]
        for task in shard["tasks"]
    ]
    if len(assigned) != len(set(assigned)):
        raise RuntimeError("duplicate trial assignment detected")
    return {
        "format_version": 1,
        "generated_at_unix": time.time(),
        "source_manifest": str(TRANSFER_MANIFEST.relative_to(REPO_ROOT)),
        "policy": "run_missing_trials_only_no_retry_after_event_cap",
        "debug_max_events": cap,
        "worker_count": worker_count,
        "task_count": len(tasks),
        "micro_shard_count": len(micro_shards),
        "target_micro_shard_seconds": target_micro_shard_seconds,
        "total_estimated_seconds": round(sum(task["estimated_seconds"] for task in tasks), 3),
        "workers": workers,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workers", type=int, default=15)
    parser.add_argument("--cap", type=int, default=10_000)
    parser.add_argument("--target-micro-shard-seconds", type=float, default=18_000.0)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    manifest = build_manifest(args.workers, args.cap, args.target_micro_shard_seconds)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {args.output}")
    print(f"tasks={manifest['task_count']} micro_shards={manifest['micro_shard_count']} workers={manifest['worker_count']}")
    for worker_id, worker in manifest["workers"].items():
        hours = worker["estimated_seconds"] / 3600.0
        print(f"worker {worker_id}: tasks={worker['task_count']} estimate={hours:.2f}h")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
