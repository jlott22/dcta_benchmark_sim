#!/usr/bin/env python3
"""Verify expected row counts and condition coverage for the grid-density sensitivity study."""
from __future__ import annotations

import argparse
import csv
from pathlib import Path
from collections import Counter

EXPECTED_CONDITIONS = 5 * 7 * 4 * 6
EXPECTED_SYSTEM_ROWS = EXPECTED_CONDITIONS * 50


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--run-root", default="/home/jlott/dcta_benchmark_sim/runs/sensitivity_grid_density_50")
    return p.parse_args()


def read_rows(path: Path):
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def main():
    args = parse_args()
    run_root = Path(args.run_root).resolve()
    manifest = read_rows(run_root / "condition_manifest.csv")
    print(f"[CHECK] condition_manifest rows: {len(manifest)} expected {EXPECTED_CONDITIONS}")

    sys_path = run_root / "combined" / "system_performance.csv"
    trial_path = run_root / "combined" / "trial_summary.csv"
    robot_path = run_root / "combined" / "robot_performance.csv"

    sys_rows = read_rows(sys_path) if sys_path.exists() else []
    trial_rows = read_rows(trial_path) if trial_path.exists() else []
    robot_rows = read_rows(robot_path) if robot_path.exists() else []

    print(f"[CHECK] system_performance rows: {len(sys_rows)} expected {EXPECTED_SYSTEM_ROWS}")
    print(f"[CHECK] trial_summary rows:      {len(trial_rows)} expected {EXPECTED_SYSTEM_ROWS}")

    expected_robot_rows = 0
    for row in manifest:
        expected_robot_rows += int(row["num_trials"]) * int(row["robot_count"])
    print(f"[CHECK] robot_performance rows: {len(robot_rows)} expected {expected_robot_rows}")

    # Verify each condition has exactly 50 system rows.
    counts = Counter(row.get("condition_id", "") for row in sys_rows)
    bad = [(cid, n) for cid, n in counts.items() if n != 50]
    missing = [row["condition_id"] for row in manifest if counts.get(row["condition_id"], 0) == 0]
    print(f"[CHECK] conditions with system rows: {len(counts)}")
    print(f"[CHECK] missing conditions: {len(missing)}")
    print(f"[CHECK] non-50-row conditions: {len(bad)}")
    if missing[:10]:
        print("[WARN] first missing:", missing[:10])
    if bad[:10]:
        print("[WARN] first bad counts:", bad[:10])

    required_cols = [
        "trial_id", "grid_size", "target_cells_per_robot", "robot_count",
        "actual_cells_per_robot", "comm_model", "comm_level", "condition_id",
    ]
    if sys_rows:
        cols = set(sys_rows[0].keys())
        missing_cols = [c for c in required_cols if c not in cols]
        print(f"[CHECK] missing required system columns: {missing_cols}")

    if len(manifest) == EXPECTED_CONDITIONS and len(sys_rows) == EXPECTED_SYSTEM_ROWS and len(trial_rows) == EXPECTED_SYSTEM_ROWS and len(robot_rows) == expected_robot_rows and not missing and not bad:
        print("[OK] verification passed")
    else:
        print("[WARN] verification found mismatches; inspect logs/source_manifest")


if __name__ == "__main__":
    main()
