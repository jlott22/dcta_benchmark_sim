#!/usr/bin/env python3
"""Validate and summarize one temporary GE 10k worker result directory."""
from __future__ import annotations

import argparse
import csv
import json
import os
import time
from collections import Counter
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
DIST_ROOT = Path(__file__).resolve().parent
QUEUE_MANIFEST = DIST_ROOT / "queue_manifest.json"


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def trial_id(row: dict[str, str]) -> int:
    return int(row["trial_id"])


def write_csv(path: Path, rows: list[dict]) -> None:
    fields: list[str] = []
    seen: set[str] = set()
    for row in rows:
        for field in row:
            if field not in seen:
                seen.add(field)
                fields.append(field)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    os.replace(temporary, path)


def display_path(path: Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def assigned_tasks(manifest: dict, worker_id: str) -> list[tuple[str, dict]]:
    tasks: list[tuple[str, dict]] = []
    worker = manifest["workers"][worker_id]
    for shard in worker["micro_shards"]:
        for task in shard["tasks"]:
            tasks.append((shard["micro_shard"], task))
    return tasks


def validate_trial(out_dir: Path, selected: int) -> dict:
    required = [
        "trial_summary.csv",
        "system_performance.csv",
        "robot_performance.csv",
        "config_used.json",
        "worker_result.json",
    ]
    missing = [name for name in required if not (out_dir / name).exists()]
    if missing:
        return {"valid": False, "reason": f"missing {missing}"}
    trials = read_csv(out_dir / "trial_summary.csv")
    systems = read_csv(out_dir / "system_performance.csv")
    robots = read_csv(out_dir / "robot_performance.csv")
    if len(trials) != 1 or len(systems) != 1 or len(robots) != 4:
        return {
            "valid": False,
            "reason": f"bad row counts trial={len(trials)} system={len(systems)} robot={len(robots)}",
        }
    if {trial_id(row) for row in trials + systems + robots} != {selected}:
        return {"valid": False, "reason": "wrong trial IDs"}
    result = json.loads((out_dir / "worker_result.json").read_text(encoding="utf-8"))
    if int(result["trial_id"]) != selected:
        return {"valid": False, "reason": "worker_result trial mismatch"}
    return {"valid": True, "result": result}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--worker", required=True, help="Worker ID, for example 01")
    parser.add_argument("--results-root", type=Path, default=None, help="Override output root for smoke tests")
    args = parser.parse_args()
    worker_id = f"{int(args.worker):02d}"
    manifest = json.loads(QUEUE_MANIFEST.read_text(encoding="utf-8"))
    if worker_id not in manifest["workers"]:
        raise SystemExit(f"unknown worker {worker_id}")
    results_root = args.results_root or (DIST_ROOT / "results" / f"worker_{worker_id}")
    results_root.mkdir(parents=True, exist_ok=True)
    rows = []
    valid = invalid = missing = completed = failed = 0
    status_counts: Counter[str] = Counter()
    for micro_shard, task in assigned_tasks(manifest, worker_id):
        condition_path = Path(task["condition_relative"]).relative_to(
            Path("runs") / "coverage_core_100_ge_bursty_rho08" / "raw"
        )
        out_dir = results_root / "shards" / micro_shard / condition_path / f"trial_{int(task['trial_id']):04d}"
        check = validate_trial(out_dir, int(task["trial_id"]))
        row = {
            "worker": worker_id,
            "micro_shard": micro_shard,
            "algorithm_name": task["algorithm_name"],
            "condition_id": task["condition_id"],
            "trial_id": task["trial_id"],
            "out_dir": display_path(out_dir),
            "valid": str(check["valid"]).lower(),
        }
        if check["valid"]:
            valid += 1
            result = check["result"]
            row.update(
                {
                    "status": result.get("status", ""),
                    "debug_max_events": result.get("debug_max_events", ""),
                    "elapsed_seconds": result.get("elapsed_seconds", ""),
                    "failure_type": result.get("failure_type", ""),
                    "failure_message": result.get("failure_message", ""),
                }
            )
            status_counts[str(result.get("status", ""))] += 1
            if result.get("status") == "failed":
                failed += 1
            else:
                completed += 1
        else:
            if out_dir.exists():
                invalid += 1
            else:
                missing += 1
            row["reason"] = check["reason"]
        rows.append(row)
    write_csv(results_root / "RESULT_MANIFEST.csv", rows)
    payload = {
        "worker": worker_id,
        "created_at_unix": time.time(),
        "result_root": display_path(results_root),
        "assigned_tasks": len(rows),
        "valid_results": valid,
        "completed_results": completed,
        "failed_results": failed,
        "missing_results": missing,
        "invalid_results": invalid,
        "status_counts": dict(status_counts),
        "complete": valid == len(rows),
        "policy": manifest["policy"],
        "debug_max_events": manifest["debug_max_events"],
    }
    (results_root / "RESULT_MANIFEST.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2))
    if invalid:
        raise SystemExit(1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
