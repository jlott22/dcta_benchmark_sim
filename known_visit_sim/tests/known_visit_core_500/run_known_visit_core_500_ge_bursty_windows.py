#!/usr/bin/env python3
"""Run the corrected bursty-GE known-target core study on Windows.

The job definitions reproduce the authoritative original combined manifest,
changing only the GE implementation/labels and output root. Conditions are
safe to resume because ``known_visit_sim.run_trials`` checkpoints CSV output
after every trial.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
SCENARIO = REPO_ROOT / "scenarios" / "known_visit_g19_t10_n500.csv"
SCENARIO_SHA256 = "064c7d15a551e1299c4630fa8d9ca178265bb33c0bc13a3dc1061d44411039c1"
DEFAULT_RUN_ROOT = REPO_ROOT / "runs" / "known_visit_core_500_ge_bursty_rho08"
ALGORITHMS = {
    "CBAA": "known_visit_sim.algorithms.CBAA:CBAAAllocator",
    "ACBBA": "known_visit_sim.algorithms.ACBBA:ACBBAAllocator",
    "PI": "known_visit_sim.algorithms.PI:PIAllocator",
    "HIPC": "known_visit_sim.algorithms.HIPC:HIPCAllocator",
    "DMCHBA": "known_visit_sim.algorithms.DMCHBA:DMCHBAAllocator",
    "DGA": "known_visit_sim.algorithms.DGA:DGAAllocator",
}
HORIZON_ALGORITHMS = {"ACBBA", "PI", "HIPC", "DMCHBA", "DGA"}
TARGET_DROPS = (0.05, 0.10, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70)
STATE_CORRELATION = 0.8


@dataclass(frozen=True)
class Job:
    algorithm: str
    drop: float
    delivery: float
    p_gg: float
    p_bb: float
    condition_id: str
    out_dir: Path
    command: tuple[str, ...]


def decimal_label(value: float) -> str:
    return f"{value:.2f}".replace(".", "_")


def scenario_hash() -> str:
    digest = hashlib.sha256()
    with SCENARIO.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def count_rows(path: Path) -> tuple[int, int]:
    if not path.exists() or path.stat().st_size == 0:
        return 0, 0
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    failed = sum(str(row.get("trial_status", "")).lower() == "failed" for row in rows)
    return len(rows), failed


def build_jobs(run_root: Path, trials: int) -> list[Job]:
    jobs: list[Job] = []
    for algorithm, algorithm_path in ALGORITHMS.items():
        for drop in TARGET_DROPS:
            delivery = 1.0 - drop
            p_gg = delivery + STATE_CORRELATION * (1.0 - delivery)
            p_bb = (1.0 - delivery) + STATE_CORRELATION * delivery
            condition = f"{algorithm.lower()}_gilbert_elliott_drop_{decimal_label(drop)}_rho_0_8"
            out_dir = run_root / "raw" / algorithm.lower() / condition.removeprefix(f"{algorithm.lower()}_")
            command = [
                sys.executable,
                "-m",
                "known_visit_sim.run_trials",
                "--scenario-file",
                str(SCENARIO.relative_to(REPO_ROOT)),
                "--algorithm",
                algorithm_path,
                "--algorithm-name",
                algorithm,
                "--grid-size",
                "19",
                "--num-robots",
                "4",
                "--robot-start-layout",
                "edge_even",
                "--condition-id",
                condition,
                "--seed",
                "0",
                "--out-dir",
                str(out_dir),
                "--max-trials",
                str(trials),
                "--comm-model",
                "gilbert_elliot",
                "--comm-level",
                f"{delivery:g}",
            ]
            if algorithm in HORIZON_ALGORITHMS:
                command.extend(["--commitment-horizon", "3"])
            jobs.append(
                Job(
                    algorithm=algorithm,
                    drop=drop,
                    delivery=delivery,
                    p_gg=p_gg,
                    p_bb=p_bb,
                    condition_id=condition,
                    out_dir=out_dir,
                    command=tuple(command),
                )
            )
    return jobs


def write_manifest(run_root: Path, jobs: list[Job], trials: int, workers: int) -> None:
    run_root.mkdir(parents=True, exist_ok=True)
    path = run_root / "condition_manifest.csv"
    fields = [
        "stage", "environment", "algorithm", "comm_model", "target_drop_fraction",
        "comm_level_stationary_delivery", "state_correlation", "p_gg", "p_bb",
        "scenario_file", "scenario_sha256", "seed", "commitment_horizon",
        "dga_iterations", "expected_trials", "condition_id", "out_dir", "command",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for job in jobs:
            writer.writerow({
                "stage": "known_core_ge_bursty",
                "environment": "known_target",
                "algorithm": job.algorithm,
                "comm_model": "gilbert_elliot",
                "target_drop_fraction": f"{job.drop:g}",
                "comm_level_stationary_delivery": f"{job.delivery:g}",
                "state_correlation": STATE_CORRELATION,
                "p_gg": f"{job.p_gg:g}",
                "p_bb": f"{job.p_bb:g}",
                "scenario_file": str(SCENARIO.relative_to(REPO_ROOT)),
                "scenario_sha256": SCENARIO_SHA256,
                "seed": 0,
                "commitment_horizon": 3 if job.algorithm in HORIZON_ALGORITHMS else "",
                "dga_iterations": 25 if job.algorithm == "DGA" else "",
                "expected_trials": trials,
                "condition_id": job.condition_id,
                "out_dir": str(job.out_dir),
                "command": json.dumps(job.command),
            })
    metadata = {
        "created_at_unix": time.time(),
        "logical_processors": os.cpu_count(),
        "workers": workers,
        "worker_fraction": workers / (os.cpu_count() or workers),
        "conditions": len(jobs),
        "expected_trials": len(jobs) * trials,
        "trials_per_condition": trials,
        "scenario_sha256": SCENARIO_SHA256,
        "state_correlation": STATE_CORRELATION,
    }
    (run_root / "run_metadata.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")


def update_progress(run_root: Path, jobs: list[Job], trials: int) -> None:
    conditions_complete = conditions_failed = completed_trials = failed_trials = 0
    for job in jobs:
        rows, failed = count_rows(job.out_dir / "system_performance.csv")
        completed_trials += rows
        failed_trials += failed
        if rows == trials and failed == 0:
            conditions_complete += 1
        if (job.out_dir / "_FAILED.txt").exists() or failed:
            conditions_failed += 1
    progress = {
        "updated_at_unix": time.time(),
        "completed_trials": completed_trials,
        "expected_trials": len(jobs) * trials,
        "conditions_complete": conditions_complete,
        "conditions_total": len(jobs),
        "conditions_with_failures": conditions_failed,
        "failed_trial_rows": failed_trials,
    }
    temp = run_root / "progress.json.tmp"
    temp.write_text(json.dumps(progress, indent=2) + "\n", encoding="utf-8")
    temp.replace(run_root / "progress.json")


def run_job(job: Job, trials: int) -> dict[str, object]:
    job.out_dir.mkdir(parents=True, exist_ok=True)
    rows, failed = count_rows(job.out_dir / "system_performance.csv")
    if rows == trials and failed == 0:
        (job.out_dir / "_COMPLETE.txt").write_text("complete\n", encoding="utf-8")
        return {"condition": job.condition_id, "status": "already_complete", "rows": rows, "failed": failed}

    log_path = job.out_dir / "run.log"
    creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    with log_path.open("a", encoding="utf-8") as log:
        log.write(f"\nSTART {time.strftime('%Y-%m-%dT%H:%M:%S')}\n")
        log.write(json.dumps(job.command) + "\n")
        log.flush()
        completed = subprocess.run(
            job.command,
            cwd=REPO_ROOT,
            stdout=log,
            stderr=subprocess.STDOUT,
            creationflags=creationflags,
            check=False,
        )
        log.write(f"END status={completed.returncode} {time.strftime('%Y-%m-%dT%H:%M:%S')}\n")

    rows, failed = count_rows(job.out_dir / "system_performance.csv")
    status = "complete" if completed.returncode == 0 and rows == trials and failed == 0 else "failed"
    marker = job.out_dir / ("_COMPLETE.txt" if status == "complete" else "_FAILED.txt")
    marker.write_text(
        f"status={completed.returncode}\nrows={rows}\nfailed_trial_rows={failed}\n",
        encoding="utf-8",
    )
    return {"condition": job.condition_id, "status": status, "rows": rows, "failed": failed}


def set_windows_sleep_inhibition(enable: bool) -> None:
    if os.name != "nt":
        return
    import ctypes

    es_continuous = 0x80000000
    es_system_required = 0x00000001
    es_awaymode_required = 0x00000040
    flags = es_continuous | es_system_required | es_awaymode_required if enable else es_continuous
    ctypes.windll.kernel32.SetThreadExecutionState(flags)


def main() -> None:
    logical = os.cpu_count() or 1
    parser = argparse.ArgumentParser()
    parser.add_argument("--workers", type=int, default=max(1, int(logical * 0.75)))
    parser.add_argument("--trials", type=int, default=500)
    parser.add_argument("--run-root", type=Path, default=DEFAULT_RUN_ROOT)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if args.workers < 1 or args.workers > logical:
        parser.error(f"--workers must be in [1, {logical}]")
    if args.trials < 1 or args.trials > 500:
        parser.error("--trials must be in [1, 500]")
    if not SCENARIO.exists():
        raise SystemExit(f"Original scenario file is missing: {SCENARIO}")
    observed_hash = scenario_hash()
    if observed_hash != SCENARIO_SHA256:
        raise SystemExit(f"Scenario hash mismatch: expected {SCENARIO_SHA256}, observed {observed_hash}")

    run_root = args.run_root.expanduser().resolve()
    jobs = build_jobs(run_root, args.trials)
    write_manifest(run_root, jobs, args.trials, args.workers)
    update_progress(run_root, jobs, args.trials)
    print(
        f"Prepared {len(jobs)} corrected-GE conditions, {len(jobs) * args.trials:,} trials, "
        f"workers={args.workers}/{logical}, root={run_root}",
        flush=True,
    )
    if args.dry_run:
        return

    lock = threading.Lock()
    set_windows_sleep_inhibition(True)
    try:
        with ThreadPoolExecutor(max_workers=args.workers) as executor:
            futures = {executor.submit(run_job, job, args.trials): job for job in jobs}
            for future in as_completed(futures):
                job = futures[future]
                try:
                    result = future.result()
                except Exception as exc:  # keep other conditions running
                    result = {"condition": job.condition_id, "status": "launcher_error", "error": repr(exc)}
                with lock:
                    with (run_root / "launcher.log").open("a", encoding="utf-8") as handle:
                        handle.write(json.dumps(result) + "\n")
                    update_progress(run_root, jobs, args.trials)
                    print(json.dumps(result), flush=True)
    finally:
        set_windows_sleep_inhibition(False)
        update_progress(run_root, jobs, args.trials)


if __name__ == "__main__":
    main()
