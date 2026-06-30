#!/usr/bin/env python3
from __future__ import annotations

import csv
import shlex
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
PYTHON_BIN = "${PYTHON_BIN:-python3}"
RUNNER_REL = Path("known_visit_sim/tests/known_visit_horizon/run_known_visit_horizon_trial.py")
SCENARIO_FILE = Path("known_visit_10target_300.csv")
ROOT = Path("runs/sensitivity_known_visit_horizon_300")
GRID_SIZE = 19
NUM_ROBOTS = 4
NUM_TARGETS = 10
NUM_TRIALS = 300
MAX_TRIALS = 300
SEED = 0
N_PARTS = 12

HORIZONS = [1, 2, 3, 5, 8, 12]
ALGORITHMS = ["ACBBA", "PI", "HIPC", "DMCHBA", "DGA"]
CONDITIONS = [
    ("ideal", "ideal", ""),
    ("bernoulli_025", "bernoulli", "0.25"),
    ("ge_075", "gilbert_elliot", "0.75"),
    ("rayleigh_m50_66", "rayleigh_style", "-50.66"),
]
WEIGHTS = {"DGA": 4, "DMCHBA": 4, "HIPC": 2, "PI": 2, "ACBBA": 2}


def q(x) -> str:
    return shlex.quote(str(x))


def build_jobs():
    jobs = []
    for horizon in HORIZONS:
        setting = f"h{horizon}"
        for alg in ALGORITHMS:
            for comm_label, model, level in CONDITIONS:
                run_id = f"{alg.lower()}_{setting}_{comm_label}"
                out_dir = ROOT / "raw" / setting / model / run_id
                args = [
                    PYTHON_BIN,
                    str(RUNNER_REL),
                    "--scenario-file", str(SCENARIO_FILE),
                    "--generate-scenarios-if-missing",
                    "--num-trials", str(NUM_TRIALS),
                    "--max-trials", str(MAX_TRIALS),
                    "--num-targets", str(NUM_TARGETS),
                    "--grid-size", str(GRID_SIZE),
                    "--num-robots", str(NUM_ROBOTS),
                    "--algorithm", alg,
                    "--comm-model", model,
                    "--commitment-horizon", str(horizon),
                    "--seed", str(SEED),
                    "--out-dir", str(out_dir),
                    "--condition-id", run_id,
                ]
                if level:
                    args += ["--comm-level", level]
                jobs.append({
                    "setting": setting,
                    "run_id": run_id,
                    "algorithm": alg,
                    "comm_label": comm_label,
                    "comm_model": model,
                    "comm_level": level,
                    "horizon": horizon,
                    "scenario_file": str(SCENARIO_FILE),
                    "grid_size": GRID_SIZE,
                    "num_robots": NUM_ROBOTS,
                    "num_targets": NUM_TARGETS,
                    "max_trials": MAX_TRIALS,
                    "out_dir": str(out_dir),
                    "args": args,
                    "weight": WEIGHTS.get(alg, 1),
                })
    return jobs


def assign_jobs(jobs):
    parts = [[] for _ in range(N_PARTS)]
    loads = [0 for _ in range(N_PARTS)]
    for job in sorted(jobs, key=lambda j: (-j["weight"], j["algorithm"], j["setting"], j["comm_label"])):
        idx = min(range(N_PARTS), key=lambda i: loads[i])
        parts[idx].append(job)
        loads[idx] += job["weight"]
    return parts, loads


def write_manifest(jobs):
    combined = REPO_ROOT / ROOT / "combined"
    combined.mkdir(parents=True, exist_ok=True)
    fields = ["setting", "run_id", "algorithm", "comm_label", "comm_model", "comm_level", "horizon", "scenario_file", "grid_size", "num_robots", "num_targets", "max_trials", "out_dir"]
    with (combined / "manifest.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for job in jobs:
            writer.writerow({k: job[k] for k in fields})


def write_part_scripts(parts):
    parts_dir = REPO_ROOT / ROOT / "parts"
    parts_dir.mkdir(parents=True, exist_ok=True)
    for idx, part_jobs in enumerate(parts):
        script_path = parts_dir / f"known_visit_horizon_core_{idx}.sh"
        lines = [
            "#!/usr/bin/env bash",
            "set -u",
            "set -o pipefail",
            f'REPO_ROOT="{REPO_ROOT}"',
            'cd "$REPO_ROOT" || exit 1',
            f'echo "Starting known-visit horizon core {idx} at $(date -Is)"',
            "",
        ]
        for job in part_jobs:
            cmd = " ".join(q(a) if not str(a).startswith("${PYTHON_BIN") else str(a) for a in job["args"])
            done_file = f'{job["out_dir"]}/_COMPLETE.txt'
            log_file = f'{job["out_dir"]}/run.log'
            lines += [
                "",
                'echo "============================================================"',
                f'echo "RUN {job["run_id"]}"',
                'echo "============================================================"',
                f'mkdir -p {q(job["out_dir"])}',
                f'if [[ -f {q(done_file)} ]]; then',
                f'  echo "Skipping completed: {job["run_id"]}"',
                "else",
                f'  echo "Command: {cmd}"',
                f'  {cmd} 2>&1 | tee {q(log_file)}',
                '  STATUS=${PIPESTATUS[0]}',
                '  if [[ "$STATUS" -ne 0 ]]; then',
                f'    echo "ERROR: failed {job["run_id"]} with status $STATUS"',
                '    exit "$STATUS"',
                "  fi",
                "fi",
            ]
        lines.append(f'echo "Finished known-visit horizon core {idx} at $(date -Is)"')
        script_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        script_path.chmod(0o755)
        print(f"Wrote {script_path} ({len(part_jobs)} jobs)")


def write_start_script():
    script_path = REPO_ROOT / ROOT / "start_all_known_visit_horizon_parts.sh"
    lines = [
        "#!/usr/bin/env bash",
        "set -u",
        "set -o pipefail",
        f'cd "{REPO_ROOT}" || exit 1',
        f'mkdir -p {ROOT}/logs',
        'echo "Starting all known-visit horizon parts at $(date -Is)"',
    ]
    for i in range(N_PARTS):
        lines.append(f'./{ROOT}/parts/known_visit_horizon_core_{i}.sh > {ROOT}/logs/core_{i}.master.log 2>&1 &')
    lines += ["wait", 'echo "All known-visit horizon parts finished at $(date -Is)"']
    script_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    script_path.chmod(0o755)
    print(f"Wrote {script_path}")


def main():
    jobs = build_jobs()
    parts, loads = assign_jobs(jobs)
    write_manifest(jobs)
    write_part_scripts(parts)
    write_start_script()
    print("loads:", loads)
    print("\nNext commands:")
    print(f"  python3 {REPO_ROOT / 'known_visit_sim/tests/known_visit_horizon/make_known_visit_horizon_sensitivity.py'}")
    print(f"  ./{ROOT}/start_all_known_visit_horizon_parts.sh")
    print(f"  bash known_visit_sim/tests/known_visit_horizon/combine_known_visit_horizon_sensitivity_300.sh")


if __name__ == "__main__":
    main()
