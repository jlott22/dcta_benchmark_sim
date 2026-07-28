#!/usr/bin/env python3
"""Resume transferred coverage trials with a time-weighted 12-worker queue."""
from __future__ import annotations

import argparse
import csv
import json
import os
import platform
import subprocess
import sys
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
RUN_ROOT = REPO_ROOT / "runs" / "coverage_core_100_ge_bursty_rho08"
MANIFEST_PATH = RUN_ROOT / "TRANSFER_MANIFEST.json"
STATE_PATH = RUN_ROOT / "transferred_coverage_state.json"
WORK_ROOT = RUN_ROOT / "_transferred_shards"
WORKER_SCRIPT = REPO_ROOT / "analysis" / "run_snapshot_coverage_trial.py"
EXPECTED_TRIALS = 100


@dataclass(frozen=True)
class Task:
    condition: dict
    trial_id: int
    estimated_seconds: float

    @property
    def condition_dir(self) -> Path:
        return REPO_ROOT / self.condition["condition_relative"]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workers", type=int, default=12)
    parser.add_argument("--initial-cap", type=int, default=20_000)
    parser.add_argument("--retry-cap", type=int, default=50_000)
    parser.add_argument(
        "--retry-only",
        action="store_true",
        help="Skip missing trials and run only failed canonical trial IDs.",
    )
    parser.add_argument(
        "--missing-only",
        action="store_true",
        help="Run and merge missing IDs, then stop before all failed-row retries.",
    )
    parser.add_argument(
        "--handoff-failures-only",
        action="store_true",
        help="Restrict retries to failed IDs recorded at the original handoff.",
    )
    parser.add_argument(
        "--retry-stage",
        default="retry",
        help="Shard-stage directory for retries (default: retry).",
    )
    parser.add_argument(
        "--algorithms",
        nargs="+",
        help="Restrict execution to these algorithm names (for example ACBBA CBAA HIPC PI).",
    )
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Execute missing trials. Without this flag the command is audit-only.",
    )
    parser.add_argument(
        "--allow-source-machine",
        action="store_true",
        help="Override the guard that prevents coverage execution on the source computer.",
    )
    return parser.parse_args()


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def trial_id(row: dict[str, str]) -> int:
    return int(row["trial_id"])


def atomic_json(path: Path, payload: dict) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, indent=2, default=str) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def write_state(stage: str, status: str, **extra: object) -> None:
    atomic_json(
        STATE_PATH,
        {"updated_at_unix": time.time(), "stage": stage, "status": status, **extra},
    )


def flag_value(command: list[str], flag: str, default: str | None = None) -> str | None:
    if flag not in command:
        return default
    index = command.index(flag)
    if index + 1 >= len(command):
        raise RuntimeError(f"missing value after {flag}")
    return command[index + 1]


def canonical_status(condition: dict) -> dict:
    condition_dir = REPO_ROOT / condition["condition_relative"]
    trial_rows = read_csv(condition_dir / "trial_summary.csv")
    system_rows = read_csv(condition_dir / "system_performance.csv")
    robot_rows = read_csv(condition_dir / "robot_performance.csv")
    trial_ids = [trial_id(row) for row in trial_rows]
    system_ids = [trial_id(row) for row in system_rows]
    robot_counts = Counter(trial_id(row) for row in robot_rows)
    if len(trial_ids) != len(set(trial_ids)) or len(system_ids) != len(set(system_ids)):
        raise RuntimeError(f"duplicate IDs in {condition_dir}")
    if set(trial_ids) != set(system_ids) or set(robot_counts) != set(trial_ids):
        raise RuntimeError(f"CSV ID mismatch in {condition_dir}")
    if any(value != 4 for value in robot_counts.values()):
        raise RuntimeError(f"expected four robot rows per trial in {condition_dir}")
    failed = sorted(
        trial_id(row)
        for row in trial_rows
        if row.get("trial_status", "").strip().lower() == "failed"
    )
    return {
        "ids": set(trial_ids),
        "failed": failed,
        "missing": sorted(set(range(EXPECTED_TRIALS)) - set(trial_ids)),
    }


def task_output(stage: str, task: Task) -> Path:
    relative = Path(task.condition["condition_relative"]).relative_to(
        Path("runs") / "coverage_core_100_ge_bursty_rho08" / "raw"
    )
    return WORK_ROOT / stage / relative / f"trial_{task.trial_id:04d}"


def validate_shard(path: Path, selected: int) -> dict:
    trials = read_csv(path / "trial_summary.csv")
    systems = read_csv(path / "system_performance.csv")
    robots = read_csv(path / "robot_performance.csv")
    if len(trials) != 1 or len(systems) != 1 or len(robots) != 4:
        raise RuntimeError(f"invalid shard row counts in {path}")
    if {trial_id(row) for row in trials + systems + robots} != {selected}:
        raise RuntimeError(f"wrong trial ID in {path}")
    return json.loads((path / "worker_result.json").read_text(encoding="utf-8"))


def run_task(task: Task, stage: str, cap: int, runtime_root: Path) -> dict:
    out_dir = task_output(stage, task)
    if (out_dir / "worker_result.json").exists():
        return validate_shard(out_dir, task.trial_id)
    out_dir.mkdir(parents=True, exist_ok=True)
    source_command = task.condition["source_command"]
    algorithm_class = flag_value(source_command, "--algorithm")
    commitment = flag_value(source_command, "--commitment-horizon")
    command = [
        sys.executable,
        str(WORKER_SCRIPT),
        "--runtime-root",
        str(runtime_root),
        "--trial-id",
        str(task.trial_id),
        "--out-dir",
        str(out_dir),
        "--algorithm",
        str(algorithm_class),
        "--algorithm-name",
        task.condition["algorithm"],
        "--condition-id",
        task.condition["condition_id"],
        "--comm-model",
        "gilbert_elliot",
        "--comm-level",
        task.condition["comm_level_stationary_delivery"],
        "--debug-max-events",
        str(cap),
        "--seed",
        "0",
    ]
    if commitment is not None:
        command.extend(["--commitment-horizon", commitment])
    with (out_dir / "run.log").open("a", encoding="utf-8") as log:
        completed = subprocess.run(
            command,
            cwd=REPO_ROOT,
            stdout=log,
            stderr=subprocess.STDOUT,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            check=False,
        )
    if completed.returncode:
        raise RuntimeError(
            f"coverage worker failed: {task.condition['condition_id']} trial {task.trial_id}"
        )
    return validate_shard(out_dir, task.trial_id)


def run_tasks(
    tasks: list[Task],
    stage: str,
    cap: int,
    workers: int,
    runtime_root: Path,
) -> None:
    tasks = sorted(tasks, key=lambda task: task.estimated_seconds, reverse=True)
    if not tasks:
        return
    predicted = sum(task.estimated_seconds for task in tasks)
    write_state(
        stage,
        "running",
        tasks=len(tasks),
        workers=workers,
        predicted_core_hours=predicted / 3600.0,
        debug_max_events=cap,
    )
    finished = 0
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {
            pool.submit(run_task, task, stage, cap, runtime_root): task
            for task in tasks
        }
        for future in as_completed(futures):
            task = futures[future]
            result = future.result()
            finished += 1
            write_state(
                stage,
                "running",
                tasks=len(tasks),
                finished=finished,
                workers=workers,
                predicted_core_hours=predicted / 3600.0,
                debug_max_events=cap,
                latest={
                    "condition": task.condition["condition_id"],
                    "trial_id": task.trial_id,
                    "result": result,
                },
            )
            print(
                f"{stage}: {finished}/{len(tasks)} "
                f"{task.condition['condition_id']} trial={task.trial_id} "
                f"status={result['status']}",
                flush=True,
            )


def write_csv_atomic(path: Path, rows: list[dict[str, str]]) -> None:
    fields: list[str] = []
    seen: set[str] = set()
    for row in rows:
        for name in row:
            if name not in seen:
                seen.add(name)
                fields.append(name)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    os.replace(temporary, path)


def merge_tasks(tasks: list[Task], stage: str, replace: bool) -> None:
    grouped: dict[str, list[Task]] = {}
    for task in tasks:
        grouped.setdefault(task.condition["condition_id"], []).append(task)
    for condition_tasks in grouped.values():
        condition = condition_tasks[0].condition
        condition_dir = REPO_ROOT / condition["condition_relative"]
        trials = {trial_id(row): row for row in read_csv(condition_dir / "trial_summary.csv")}
        systems = {trial_id(row): row for row in read_csv(condition_dir / "system_performance.csv")}
        robots: dict[int, list[dict[str, str]]] = {}
        for row in read_csv(condition_dir / "robot_performance.csv"):
            robots.setdefault(trial_id(row), []).append(row)
        for task in condition_tasks:
            selected = task.trial_id
            if selected in trials and not replace:
                raise RuntimeError(f"refusing to overwrite coverage trial {selected}")
            out_dir = task_output(stage, task)
            trials[selected] = read_csv(out_dir / "trial_summary.csv")[0]
            systems[selected] = read_csv(out_dir / "system_performance.csv")[0]
            robots[selected] = read_csv(out_dir / "robot_performance.csv")
        ids = sorted(trials)
        write_csv_atomic(condition_dir / "trial_summary.csv", [trials[key] for key in ids])
        write_csv_atomic(condition_dir / "system_performance.csv", [systems[key] for key in ids])
        write_csv_atomic(
            condition_dir / "robot_performance.csv",
            [
                row
                for key in ids
                for row in sorted(robots[key], key=lambda item: item.get("robot_id", ""))
            ],
        )
        canonical_status(condition)


def tasks_from_manifest(
    manifest: dict,
    failed: bool,
    selected_algorithms: set[str] | None = None,
    handoff_failures_only: bool = False,
) -> list[Task]:
    tasks: list[Task] = []
    for condition in manifest["conditions"]:
        if (
            selected_algorithms is not None
            and condition["algorithm"].upper() not in selected_algorithms
        ):
            continue
        status = canonical_status(condition)
        ids = status["failed"] if failed else status["missing"]
        if failed and handoff_failures_only:
            handoff_ids = {
                int(trial_id)
                for trial_id in condition.get(
                    "handoff_failed_ids",
                    condition.get("failed_ids", []),
                )
            }
            ids = sorted(set(ids) & handoff_ids)
        estimate = float(condition.get("estimated_seconds_per_trial") or 1.0)
        if failed:
            estimate *= 2.5
        for selected in ids:
            tasks.append(Task(condition, selected, estimate))
    return tasks


def audit_summary(manifest: dict) -> dict:
    conditions = []
    for condition in manifest["conditions"]:
        status = canonical_status(condition)
        conditions.append(
            {
                "algorithm": condition["algorithm"],
                "condition_id": condition["condition_id"],
                "recorded": len(status["ids"]),
                "failed": len(status["failed"]),
                "missing": len(status["missing"]),
                "estimated_seconds_per_trial": condition.get("estimated_seconds_per_trial"),
            }
        )
    return {
        "conditions": len(conditions),
        "recorded": sum(item["recorded"] for item in conditions),
        "failed": sum(item["failed"] for item in conditions),
        "missing": sum(item["missing"] for item in conditions),
        "details": conditions,
    }


def main() -> int:
    args = parse_args()
    if args.workers < 1:
        raise SystemExit("--workers must be positive")
    if args.retry_only and args.missing_only:
        raise SystemExit("--retry-only and --missing-only are mutually exclusive")
    if args.handoff_failures_only and not args.retry_only:
        raise SystemExit("--handoff-failures-only requires --retry-only")
    if (
        not args.retry_stage.startswith("retry")
        or not args.retry_stage.replace("_", "").replace("-", "").isalnum()
    ):
        raise SystemExit("--retry-stage must be a simple name beginning with 'retry'")
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    runtime_root = REPO_ROOT / manifest["runtime_relative"]
    available_algorithms = {
        condition["algorithm"].upper() for condition in manifest["conditions"]
    }
    selected_algorithms = (
        {algorithm.upper() for algorithm in args.algorithms}
        if args.algorithms
        else None
    )
    if selected_algorithms is not None:
        unknown = selected_algorithms - available_algorithms
        if unknown:
            raise SystemExit(f"unknown coverage algorithms: {sorted(unknown)}")
    summary = audit_summary(manifest)
    if not args.execute:
        if args.retry_only:
            selected_tasks = tasks_from_manifest(
                manifest,
                failed=True,
                selected_algorithms=selected_algorithms,
                handoff_failures_only=args.handoff_failures_only,
            )
            summary["selected_retry_tasks"] = len(selected_tasks)
        else:
            selected_tasks = tasks_from_manifest(
                manifest,
                failed=False,
                selected_algorithms=selected_algorithms,
            )
            summary["selected_missing_tasks"] = len(selected_tasks)
        print(json.dumps(summary, indent=2), flush=True)
        write_state("audit", "complete", summary=summary)
        return 0
    print(json.dumps(summary, indent=2), flush=True)
    if platform.node() == manifest["source_machine"] and not args.allow_source_machine:
        raise SystemExit(
            "refusing to execute coverage on the source machine; run this after "
            "transfer, or pass --allow-source-machine as an explicit override"
        )

    if args.retry_only:
        retries = tasks_from_manifest(
            manifest,
            failed=True,
            selected_algorithms=selected_algorithms,
            handoff_failures_only=args.handoff_failures_only,
        )
        run_tasks(
            retries,
            args.retry_stage,
            args.retry_cap,
            args.workers,
            runtime_root,
        )
        merge_tasks(retries, args.retry_stage, replace=True)
        remaining_failures = tasks_from_manifest(
            manifest,
            failed=True,
            selected_algorithms=selected_algorithms,
            handoff_failures_only=args.handoff_failures_only,
        )
        final_summary = audit_summary(manifest)
        if remaining_failures:
            write_state(
                "retry_selected",
                "failed",
                algorithms=sorted(selected_algorithms or available_algorithms),
                summary=final_summary,
            )
            raise SystemExit(
                f"{len(remaining_failures)} selected coverage retries still failed"
            )
        write_state(
            "retry_selected",
            "complete",
            algorithms=sorted(selected_algorithms or available_algorithms),
            summary=final_summary,
        )
        return 0

    missing = tasks_from_manifest(
        manifest,
        failed=False,
        selected_algorithms=selected_algorithms,
    )
    run_tasks(missing, "missing", args.initial_cap, args.workers, runtime_root)
    merge_tasks(missing, "missing", replace=False)
    still_missing = tasks_from_manifest(
        manifest,
        failed=False,
        selected_algorithms=selected_algorithms,
    )
    if still_missing:
        raise SystemExit(f"{len(still_missing)} coverage trials remain missing after merge")
    if args.missing_only:
        final_summary = audit_summary(manifest)
        write_state(
            "missing_selected",
            "complete",
            algorithms=sorted(selected_algorithms or available_algorithms),
            summary=final_summary,
        )
        return 0

    retries = tasks_from_manifest(
        manifest,
        failed=True,
        selected_algorithms=selected_algorithms,
    )
    run_tasks(
        retries,
        args.retry_stage,
        args.retry_cap,
        args.workers,
        runtime_root,
    )
    merge_tasks(retries, args.retry_stage, replace=True)
    remaining_failures = tasks_from_manifest(
        manifest,
        failed=True,
        selected_algorithms=selected_algorithms,
    )
    final_summary = audit_summary(manifest)
    if remaining_failures:
        write_state("retry", "failed", summary=final_summary)
        raise SystemExit(f"{len(remaining_failures)} coverage retries still failed")
    write_state("all_coverage", "complete", summary=final_summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
