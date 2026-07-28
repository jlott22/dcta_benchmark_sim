#!/usr/bin/env python3
"""Combine and validate corrected-GE core rerun outputs without replacing old data."""
from __future__ import annotations

import argparse
import csv
import shutil
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SUITES = {
    "known": {
        "raw": REPO_ROOT / "runs" / "known_visit_core_500_ge_bursty_rho08" / "raw",
        "combined": REPO_ROOT / "known_visit_core_500_ge_bursty_rho08_combined",
        "trials": 500,
        "files": ("system_performance.csv", "trial_summary.csv", "robot_performance.csv", "target_performance.csv"),
        "multipliers": (1, 1, 4, 10),
        "manifest": REPO_ROOT / "runs" / "known_visit_core_500_ge_bursty_rho08" / "condition_manifest.csv",
    },
    "clue": {
        "raw": REPO_ROOT / "runs" / "clue_core_500_ge_bursty_rho08" / "raw",
        "combined": REPO_ROOT / "clue_500_ge_bursty_rho08_combined",
        "trials": 500,
        "files": ("system_performance.csv", "trial_summary.csv", "robot_performance.csv"),
        "multipliers": (1, 1, 4),
        "manifest": REPO_ROOT / "runs" / "clue_core_500_ge_bursty_rho08" / "condition_manifest.csv",
    },
    "coverage": {
        "raw": REPO_ROOT / "runs" / "coverage_core_100_ge_bursty_rho08" / "raw",
        "combined": REPO_ROOT / "coverage_100_ge_bursty_rho08_combined",
        "trials": 100,
        "files": ("system_performance.csv", "trial_summary.csv", "robot_performance.csv"),
        "multipliers": (1, 1, 4),
        "manifest": REPO_ROOT / "runs" / "coverage_core_100_ge_bursty_rho08" / "condition_manifest.csv",
    },
}
CONDITIONS = 48
META_FIELDS = ("communication_condition", "source_out_dir")


def source_files(raw: Path, filename: str) -> list[Path]:
    files = sorted(raw.glob(f"*/*/{filename}"))
    if len(files) != CONDITIONS:
        raise RuntimeError(f"{filename}: expected {CONDITIONS} source files, found {len(files)}")
    return files


def combine(raw: Path, combined: Path, filename: str, expected_rows: int) -> int:
    files = source_files(raw, filename)
    fieldnames: list[str] = []
    seen: set[str] = set()
    for path in files:
        with path.open(newline="", encoding="utf-8") as handle:
            names = csv.DictReader(handle).fieldnames or []
        for name in (*names, *META_FIELDS):
            if name not in seen:
                seen.add(name)
                fieldnames.append(name)

    combined.mkdir(parents=True, exist_ok=True)
    output = combined / filename
    rows_written = failed = 0
    with output.open("w", newline="", encoding="utf-8") as destination:
        writer = csv.DictWriter(destination, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        for path in files:
            relative = path.relative_to(raw)
            metadata = {
                "communication_condition": relative.parts[1],
                "source_out_dir": str(path.parent.relative_to(REPO_ROOT)),
            }
            with path.open(newline="", encoding="utf-8") as source:
                for row in csv.DictReader(source):
                    if str(row.get("trial_status", "")).lower() == "failed":
                        failed += 1
                    row.update(metadata)
                    writer.writerow(row)
                    rows_written += 1
    if rows_written != expected_rows:
        raise RuntimeError(f"{filename}: expected {expected_rows:,} rows, wrote {rows_written:,}")
    if failed:
        raise RuntimeError(f"{filename}: found {failed:,} failed rows")
    print(f"[OK] {output.relative_to(REPO_ROOT)}: {rows_written:,} rows")
    return rows_written


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", required=True, choices=sorted(SUITES))
    args = parser.parse_args()
    config = SUITES[args.suite]
    raw: Path = config["raw"]
    combined: Path = config["combined"]
    trials: int = config["trials"]
    for directory in raw.glob("*/*"):
        if directory.is_dir() and not (directory / "_COMPLETE.txt").exists():
            raise RuntimeError(f"Condition is not complete: {directory}")
    for filename, multiplier in zip(config["files"], config["multipliers"]):
        combine(raw, combined, filename, CONDITIONS * trials * multiplier)
    shutil.copy2(config["manifest"], combined / "condition_manifest.csv")
    print(f"[DONE] Combined and validated {args.suite} corrected-GE core outputs")


if __name__ == "__main__":
    main()
