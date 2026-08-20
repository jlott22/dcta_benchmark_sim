"""Run the quarantined, published grid-density subset at revised horizons.

This campaign deliberately does not write to ``results/``.  One subprocess owns
one condition directory and executes its 50 scenario trials sequentially; the
scheduler keeps no more than 12 simulation subprocesses active.
"""
from __future__ import annotations

import csv
import hashlib
import json
import os
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
RUN_ROOT = ROOT / "reruns" / "grid_density"
SCENARIO_ROOT = RUN_ROOT / "scenarios"
LOG_ROOT = RUN_ROOT / "logs"
MANIFEST_ROOT = RUN_ROOT / "manifests"
MAX_SIMULATIONS = 12
CORE_RETRY_PID = 13176
GRIDS = (14, 19, 25, 34)
DENSITIES = (220, 140, 85, 50)
ROBOT_COUNTS = {
    14: {220: 1, 140: 2, 85: 3, 50: 4},
    19: {220: 2, 140: 3, 85: 5, 50: 8},
    25: {220: 3, 140: 5, 85: 8, 50: 13},
    34: {220: 6, 140: 9, 85: 14, 50: 24},
}
COMMUNICATION = (("ideal", "ideal", None), ("bernoulli_drop_0_25", "bernoulli", 0.25))
CLIPS_ALGORITHMS = {"PI": "benchmark_sim.algorithms.PI:PIAllocator"}
CV_ALGORITHMS = {
    "ACBBA": "known_visit_sim.algorithms.ACBBA:ACBBAAllocator",
    "HIPC": "known_visit_sim.algorithms.HIPC:HIPCAllocator",
    "PI": "known_visit_sim.algorithms.PI:PIAllocator",
}


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True), encoding="utf-8")
    temporary.replace(path)


def process_exists(pid: int) -> bool:
    result = subprocess.run(
        ["powershell.exe", "-NoProfile", "-Command", f"Get-Process -Id {pid} -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id"],
        capture_output=True, text=True, check=False,
    )
    return str(pid) in result.stdout.split()


def adaptive_cap(grid: int, robots: int) -> int:
    # Current runner policy: 10k events at the 19x19, four-robot reference.
    return max(5_000, -(-10_000 * grid * grid * robots // (19 * 19 * 4)))


@dataclass(frozen=True)
class Job:
    mission: str
    algorithm: str
    grid: int
    density: int
    robots: int
    comm_label: str
    comm_model: str
    comm_level: float | None
    seed: int
    scenario_file: str
    horizon: int
    cap: int
    attempt: int = 1
    trial_ids: tuple[int, ...] = tuple(range(50))

    @property
    def label(self) -> str:
        return f"g{self.grid}_d{self.density}_{self.comm_label}"

    @property
    def output_dir(self) -> Path:
        return RUN_ROOT / "raw" / self.mission / self.algorithm.lower() / "h2" / self.label / f"attempt{self.attempt}"


def generate_scenarios() -> dict[str, dict[int, Path]]:
    """Regenerate the published 50-trial inputs using their recorded seeds."""
    from benchmark_sim.tests.grid_density.prepare_grid_density_sensitivity import generate_scenarios_for_grid
    from known_visit_sim.tests.grid_density.prepare_known_grid_density_sensitivity import generate_known_target_scenarios_for_grid

    clips, cv = {}, {}
    for grid in GRIDS:
        clips_path = SCENARIO_ROOT / "clips" / f"scaling_grid{grid}_trials50.csv"
        cv_path = SCENARIO_ROOT / "cv" / f"known_visit_grid{grid}_targets10_trials50.csv"
        generate_scenarios_for_grid(grid, 50, 4, 20260630, clips_path, 1.0)
        generate_known_target_scenarios_for_grid(grid, 50, 10, 20260701, cv_path)
        clips[grid], cv[grid] = clips_path, cv_path
    return {"clips": clips, "cv": cv}


def make_jobs(scenarios: dict[str, dict[int, Path]]) -> list[Job]:
    jobs: list[Job] = []
    for mission, algorithms, seed_base in (("clips", CLIPS_ALGORITHMS, 700000), ("cv", CV_ALGORITHMS, 810000)):
        for grid_index, grid in enumerate(GRIDS):
            for density_index, density in enumerate(DENSITIES):
                robots = ROBOT_COUNTS[grid][density]
                for comm_index, (label, model, level) in enumerate(COMMUNICATION):
                    seed = seed_base + grid_index * 10000 + density_index * 1000 + comm_index * 100
                    for algorithm in algorithms:
                        jobs.append(Job(mission, algorithm, grid, density, robots, label, model, level, seed,
                                        str(scenarios[mission][grid].relative_to(ROOT)), 2, adaptive_cap(grid, robots)))
    return jobs


def command(job: Job, scenario_file: str | None = None) -> list[str]:
    scenario = scenario_file or job.scenario_file
    import_path = (CLIPS_ALGORITHMS if job.mission == "clips" else CV_ALGORITHMS)[job.algorithm]
    if job.mission == "clips":
        args = [sys.executable, "-m", "benchmark_sim.run_trials", "--trial-mode", "clue_search", "--scenario-file", scenario,
                "--algorithm", import_path, "--algorithm-name", job.algorithm, "--grid-size", str(job.grid),
                "--num-robots", str(job.robots), "--robot-start-layout", "edge_even", "--condition-id", f"{job.algorithm.lower()}_{job.label}",
                "--seed", str(job.seed), "--out-dir", str(job.output_dir), "--max-trials", str(len(job.trial_ids)),
                "--commitment-horizon", "2", "--comm-model", job.comm_model, "--debug-max-events", str(job.cap),
                "--target-cells-per-robot", str(job.density), "--actual-cells-per-robot", f"{job.grid * job.grid / job.robots:.6f}",
                "--target-decay-exp", "1.0", "--no-parquet"]
    else:
        args = [sys.executable, "-m", "known_visit_sim.run_trials", "--scenario-file", scenario,
                "--algorithm", import_path, "--algorithm-name", job.algorithm, "--grid-size", str(job.grid),
                "--num-robots", str(job.robots), "--robot-start-layout", "edge_even", "--condition-id", f"{job.algorithm.lower()}_{job.label}",
                "--seed", str(job.seed), "--out-dir", str(job.output_dir), "--max-trials", str(len(job.trial_ids)),
                "--commitment-horizon", "2", "--comm-model", job.comm_model, "--debug-max-events", str(job.cap),
                "--max-candidate-cells", "all"]
    if job.comm_level is not None:
        args.extend(["--comm-level", str(job.comm_level)])
    return args


def failed_trials(output: Path) -> list[int]:
    source = output / "system_performance.csv"
    if not source.exists():
        return []
    with source.open(newline="", encoding="utf-8-sig") as handle:
        return [int(row["trial_id"]) for row in csv.DictReader(handle) if row.get("trial_status", "").lower() == "failed"]


def scenario_subset(job: Job, ids: list[int]) -> Path:
    source = ROOT / job.scenario_file
    destination = RUN_ROOT / "retry_inputs" / job.mission / job.algorithm.lower() / f"{job.label}_attempt2.csv"
    destination.parent.mkdir(parents=True, exist_ok=True)
    with source.open(newline="", encoding="utf-8-sig") as handle:
        comments = [line for line in handle if line.lstrip().startswith("#")]
    with source.open(newline="", encoding="utf-8-sig") as handle:
        rows = [line for line in handle if line.strip() and not line.lstrip().startswith("#")]
    reader = csv.DictReader(rows)
    selected = [row for row in reader if int(row["trial_id"] if "trial_id" in row else row["episode"]) in ids]
    with destination.open("w", newline="", encoding="utf-8") as handle:
        handle.writelines(comments)
        writer = csv.DictWriter(handle, fieldnames=reader.fieldnames)
        writer.writeheader(); writer.writerows(selected)
    return destination


active_lock = threading.Lock()
active_jobs = 0


def wait_for_slot() -> None:
    global active_jobs
    while True:
        external = 1 if process_exists(CORE_RETRY_PID) else 0
        with active_lock:
            if active_jobs < MAX_SIMULATIONS - external:
                active_jobs += 1
                return
        time.sleep(5)


def release_slot() -> None:
    global active_jobs
    with active_lock:
        active_jobs -= 1


def execute(job: Job) -> dict:
    wait_for_slot()
    try:
        output = job.output_dir
        output.mkdir(parents=True, exist_ok=True)
        log = LOG_ROOT / job.mission / job.algorithm.lower() / f"{job.label}_attempt{job.attempt}.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        env = os.environ.copy()
        for key in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
            env[key] = "1"
        started = now()
        args = command(job)
        with log.open("a", encoding="utf-8", buffering=1) as handle:
            handle.write(f"[{started}] START {' '.join(args)}\n")
            result = subprocess.run(args, cwd=ROOT, env=env, stdout=handle, stderr=subprocess.STDOUT, text=True)
            handle.write(f"[{now()}] EXIT {result.returncode}\n")
        if result.returncode:
            raise RuntimeError(f"exit {result.returncode}; see {log}")
        failures = failed_trials(output)
        record = {"job": asdict(job), "started_utc": started, "completed_utc": now(), "output": str(output.relative_to(ROOT)),
                  "failed_trial_ids": failures, "retry_scheduled": bool(failures and job.cap < 50_000)}
        if failures and job.cap < 50_000:
            retry = Job(**{**asdict(job), "cap": 50_000, "attempt": 2, "trial_ids": tuple(failures)})
            record["retry"] = execute_retry(retry, scenario_subset(job, failures))
        return record
    finally:
        release_slot()


def execute_retry(job: Job, retry_scenario: Path) -> dict:
    output = job.output_dir
    output.mkdir(parents=True, exist_ok=True)
    log = LOG_ROOT / job.mission / job.algorithm.lower() / f"{job.label}_attempt2.log"
    env = os.environ.copy()
    for key in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
        env[key] = "1"
    args = command(job, str(retry_scenario.relative_to(ROOT)))
    started = now()
    with log.open("a", encoding="utf-8", buffering=1) as handle:
        handle.write(f"[{started}] RETRY {' '.join(args)}\n")
        result = subprocess.run(args, cwd=ROOT, env=env, stdout=handle, stderr=subprocess.STDOUT, text=True)
        handle.write(f"[{now()}] EXIT {result.returncode}\n")
    if result.returncode:
        raise RuntimeError(f"retry exit {result.returncode}; see {log}")
    return {"cap": 50_000, "scenario": str(retry_scenario.relative_to(ROOT)), "failed_trial_ids": failed_trials(output), "completed_utc": now()}


def main() -> int:
    scenarios = generate_scenarios()
    jobs = make_jobs(scenarios)
    write_json(MANIFEST_ROOT / "campaign_manifest.json", {
        "started_utc": now(), "integration_authorized": False, "worker_limit": MAX_SIMULATIONS,
        "core_retry_pid_reserved": CORE_RETRY_PID, "jobs": [asdict(job) for job in jobs],
        "scenario_sha256": {mission: {str(g): sha256(path) for g, path in paths.items()} for mission, paths in scenarios.items()},
        "policy": "adaptive cap; retry failed initial trials once at 50000 if initial cap is below 50000; retain second-attempt failures",
    })
    write_json(RUN_ROOT / "STATUS.json", {"status": "running", "started_utc": now(), "jobs": len(jobs), "trials": 6400, "integration_authorized": False})
    results, errors = [], []
    with ThreadPoolExecutor(max_workers=MAX_SIMULATIONS) as pool:
        futures = {pool.submit(execute, job): job for job in jobs}
        for future in as_completed(futures):
            job = futures[future]
            try:
                record = future.result(); results.append(record)
                print(f"COMPLETE {job.mission}/{job.algorithm}/{job.label} failed={record['failed_trial_ids']}", flush=True)
            except Exception as exc:
                errors.append({"job": asdict(job), "error": repr(exc)})
                print(f"ERROR {job.mission}/{job.algorithm}/{job.label}: {exc}", flush=True)
    write_json(MANIFEST_ROOT / "completion_manifest.json", {"completed_utc": now(), "results": results, "errors": errors, "integration_authorized": False})
    write_json(RUN_ROOT / "STATUS.json", {"status": "complete" if not errors else "complete_with_errors", "completed_utc": now(), "completed_jobs": len(results), "errors": errors, "integration_authorized": False})
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
