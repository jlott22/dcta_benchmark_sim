#!/usr/bin/env python3
"""Run one temporary GE 10k worker bundle."""
from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
import sys
import time
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from pathlib import Path
from threading import Lock


REPO_ROOT = Path(__file__).resolve().parents[2]
DIST_ROOT = Path(__file__).resolve().parent
RUN_ROOT = REPO_ROOT / "runs" / "coverage_core_100_ge_bursty_rho08"
RUNTIME_ROOT = RUN_ROOT / "runtime" / "legacy_ge_20260723"
WORKER_SCRIPT = REPO_ROOT / "analysis" / "run_snapshot_coverage_trial.py"
QUEUE_MANIFEST = DIST_ROOT / "queue_manifest.json"
PROCESS_LOCK = Lock()
RUNNING_PROCESSES: set[subprocess.Popen] = set()


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def trial_id(row: dict[str, str]) -> int:
    return int(row["trial_id"])


def atomic_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, indent=2, default=str) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def validate_trial_output(out_dir: Path, selected: int) -> dict:
    required = [
        "trial_summary.csv",
        "system_performance.csv",
        "robot_performance.csv",
        "config_used.json",
        "worker_result.json",
    ]
    missing = [name for name in required if not (out_dir / name).exists()]
    if missing:
        raise RuntimeError(f"{out_dir}: missing {missing}")
    trials = read_csv(out_dir / "trial_summary.csv")
    systems = read_csv(out_dir / "system_performance.csv")
    robots = read_csv(out_dir / "robot_performance.csv")
    if len(trials) != 1 or len(systems) != 1 or len(robots) != 4:
        raise RuntimeError(
            f"{out_dir}: invalid row counts trial={len(trials)} system={len(systems)} robot={len(robots)}"
        )
    if {trial_id(row) for row in trials + systems + robots} != {selected}:
        raise RuntimeError(f"{out_dir}: wrong trial ID")
    result = json.loads((out_dir / "worker_result.json").read_text(encoding="utf-8"))
    if int(result["trial_id"]) != selected:
        raise RuntimeError(f"{out_dir}: worker_result trial mismatch")
    return result


def output_dir(results_root: Path, micro_shard: str, task: dict) -> Path:
    condition_path = Path(task["condition_relative"]).relative_to(
        Path("runs") / "coverage_core_100_ge_bursty_rho08" / "raw"
    )
    return results_root / "shards" / micro_shard / condition_path / f"trial_{int(task['trial_id']):04d}"


def run_task(results_root: Path, micro_shard: str, task: dict, cap: int) -> dict:
    selected = int(task["trial_id"])
    out_dir = output_dir(results_root, micro_shard, task)
    if (out_dir / "worker_result.json").exists():
        result = validate_trial_output(out_dir, selected)
        return {"task": task, "micro_shard": micro_shard, "result": result, "skipped": True}
    out_dir.mkdir(parents=True, exist_ok=True)
    command = [
        sys.executable,
        str(WORKER_SCRIPT),
        "--runtime-root",
        str(RUNTIME_ROOT),
        "--trial-id",
        str(selected),
        "--out-dir",
        str(out_dir),
        "--algorithm",
        str(task["algorithm_class"]),
        "--algorithm-name",
        str(task["algorithm_name"]),
        "--condition-id",
        str(task["condition_id"]),
        "--comm-model",
        str(task.get("comm_model", "gilbert_elliot")),
        "--comm-level",
        str(task["comm_level"]),
        "--debug-max-events",
        str(cap),
        "--seed",
        str(task.get("seed", 0)),
    ]
    if task.get("commitment_horizon") is not None:
        command.extend(["--commitment-horizon", str(task["commitment_horizon"])])
    with (out_dir / "run.log").open("a", encoding="utf-8") as log:
        log.write(json.dumps({"started_at_unix": time.time(), "command": command}) + "\n")
        process = subprocess.Popen(
            command,
            cwd=REPO_ROOT,
            stdout=log,
            stderr=subprocess.STDOUT,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        with PROCESS_LOCK:
            RUNNING_PROCESSES.add(process)
        try:
            return_code = process.wait()
        finally:
            with PROCESS_LOCK:
                RUNNING_PROCESSES.discard(process)
        log.write(json.dumps({"finished_at_unix": time.time(), "return_code": return_code}) + "\n")
    if return_code != 0:
        raise RuntimeError(f"trial process exited {return_code}: {task['condition_id']} trial {selected}")
    result = validate_trial_output(out_dir, selected)
    return {"task": task, "micro_shard": micro_shard, "result": result, "skipped": False}


def terminate_children() -> None:
    with PROCESS_LOCK:
        processes = list(RUNNING_PROCESSES)
    for process in processes:
        if process.poll() is None:
            process.terminate()
    deadline = time.time() + 10
    for process in processes:
        while process.poll() is None and time.time() < deadline:
            time.sleep(0.2)
        if process.poll() is None:
            process.kill()


def flatten_tasks(worker: dict, only_micro_shard: str | None) -> list[tuple[str, dict]]:
    tasks: list[tuple[str, dict]] = []
    for shard in worker["micro_shards"]:
        micro_shard = shard["micro_shard"]
        if only_micro_shard and micro_shard != only_micro_shard:
            continue
        for task in shard["tasks"]:
            tasks.append((micro_shard, task))
    return tasks


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--worker", required=True, help="Worker ID, for example 01")
    parser.add_argument("--workers", type=int, default=10, help="Parallel trial processes")
    parser.add_argument("--cap", type=int, default=None, help="Override queue debug cap")
    parser.add_argument("--only-micro-shard", default=None)
    parser.add_argument("--limit-tasks", type=int, default=None, help="Run only the first N assigned tasks")
    parser.add_argument("--results-root", type=Path, default=None, help="Override output root for smoke tests")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    worker_id = f"{int(args.worker):02d}"
    if args.workers < 1:
        raise SystemExit("--workers must be positive")
    manifest = json.loads(QUEUE_MANIFEST.read_text(encoding="utf-8"))
    if worker_id not in manifest["workers"]:
        raise SystemExit(f"unknown worker {worker_id}; expected 01..{int(manifest['worker_count']):02d}")
    cap = int(args.cap if args.cap is not None else manifest["debug_max_events"])
    worker = manifest["workers"][worker_id]
    results_root = args.results_root or (DIST_ROOT / "results" / f"worker_{worker_id}")
    state_path = results_root / "worker_state.json"
    tasks = flatten_tasks(worker, args.only_micro_shard)
    if args.limit_tasks is not None:
        tasks = tasks[: args.limit_tasks]
    print(f"worker={worker_id} tasks={len(tasks)} cores={args.workers} cap={cap}")
    print(f"results={results_root}")
    if args.dry_run:
        for micro_shard, task in tasks:
            print(f"{micro_shard} {task['algorithm_name']} {task['condition_id']} trial={task['trial_id']}")
        return 0
    started = time.time()
    state = {
        "worker": worker_id,
        "status": "running",
        "started_at_unix": started,
        "updated_at_unix": started,
        "cap": cap,
        "parallel_workers": args.workers,
        "assigned_tasks": len(tasks),
        "completed": 0,
        "failed": 0,
        "skipped": 0,
        "errors": 0,
        "latest": None,
    }
    atomic_json(state_path, state)
    pending = []
    try:
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            future_to_task = {
                pool.submit(run_task, results_root, micro_shard, task, cap): (micro_shard, task)
                for micro_shard, task in tasks
            }
            pending = list(future_to_task)
            while pending:
                done, not_done = wait(pending, return_when=FIRST_COMPLETED)
                pending = list(not_done)
                for future in done:
                    micro_shard, task = future_to_task[future]
                    try:
                        payload = future.result()
                        result = payload["result"]
                        if payload["skipped"]:
                            state["skipped"] += 1
                        elif result.get("status") == "failed":
                            state["failed"] += 1
                        else:
                            state["completed"] += 1
                        state["latest"] = {
                            "micro_shard": micro_shard,
                            "condition_id": task["condition_id"],
                            "trial_id": task["trial_id"],
                            "status": result.get("status"),
                            "elapsed_seconds": result.get("elapsed_seconds"),
                        }
                    except Exception as exc:
                        state["errors"] += 1
                        state["latest"] = {
                            "micro_shard": micro_shard,
                            "condition_id": task["condition_id"],
                            "trial_id": task["trial_id"],
                            "error": str(exc),
                        }
                        print(f"[ERROR] {task['condition_id']} trial={task['trial_id']} {exc}", flush=True)
                    state["updated_at_unix"] = time.time()
                    elapsed_h = (state["updated_at_unix"] - started) / 3600.0
                    print(
                        f"[{worker_id}] done={state['completed']} failed={state['failed']} "
                        f"skipped={state['skipped']} errors={state['errors']} remaining={len(pending)} "
                        f"elapsed={elapsed_h:.2f}h latest={state['latest']}",
                        flush=True,
                    )
                    atomic_json(state_path, state)
    except KeyboardInterrupt:
        print("Ctrl+C received; terminating running trials and saving paused state.", flush=True)
        terminate_children()
        state["status"] = "paused"
        state["updated_at_unix"] = time.time()
        atomic_json(state_path, state)
        return 130
    state["status"] = "complete" if state["errors"] == 0 else "complete_with_errors"
    state["updated_at_unix"] = time.time()
    atomic_json(state_path, state)
    print(f"worker {worker_id} {state['status']}; run pack_results.py before pushing.")
    return 0 if state["errors"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
