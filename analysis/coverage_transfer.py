#!/usr/bin/env python3
"""Pack, verify, restore, and resume the corrected-GE coverage checkpoint."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import time
import zipfile
from collections import Counter
from pathlib import Path, PurePosixPath


REPO_ROOT = Path(__file__).resolve().parents[1]
RUN_ROOT = REPO_ROOT / "runs" / "coverage_core_100_ge_bursty_rho08"
RAW_ROOT = RUN_ROOT / "raw"
SHARD_ROOT = RUN_ROOT / "_transferred_shards"
ARTIFACT_ROOT = RUN_ROOT / "artifacts"
DOC_ROOT = RUN_ROOT / "docs"
RUNTIME_ROOT = RUN_ROOT / "runtime" / "legacy_ge_20260723"
LEGACY_RUNTIME_ROOT = (
    REPO_ROOT
    / "runs"
    / "clue_core_500_ge_bursty_rho08"
    / "_transfer_runtime"
    / "legacy_ge_20260723"
)
SHARD_ARCHIVE = ARTIFACT_ROOT / "validated_shards.zip"
HISTORY_ARCHIVE = ARTIFACT_ROOT / "historical_logs.zip"
ARTIFACT_MANIFEST = ARTIFACT_ROOT / "ARTIFACT_MANIFEST.json"
TRANSFER_MANIFEST = RUN_ROOT / "TRANSFER_MANIFEST.json"
TRANSFER_STATUS = RUN_ROOT / "TRANSFER_STATUS.json"
CHECKSUM_PATH = RUN_ROOT / "TRANSFER_CHECKSUMS.sha256"
CONDITION_MANIFEST = RUN_ROOT / "condition_manifest.csv"
EXPECTED_CONDITIONS = 48
EXPECTED_TRIALS = 100
QUICK_ALGORITHMS = {"ACBBA", "CBAA", "HIPC", "PI"}
LONG_ALGORITHMS = {"DGA", "DMCHBA"}
CANONICAL_NAMES = {
    "trial_summary.csv",
    "system_performance.csv",
    "robot_performance.csv",
    "config_used.json",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("pack", help="Build the compact GitHub handoff.")
    subparsers.add_parser("verify", help="Verify checksums and checkpoint structure.")
    subparsers.add_parser("restore", help="Restore validated shards from the archive.")
    subparsers.add_parser("status", help="Print canonical and shard status.")
    resume = subparsers.add_parser(
        "resume",
        help="Verify, restore, and resume only missing DGA/DMCHBA trials.",
    )
    resume.add_argument("--workers", type=int, required=True)
    resume.add_argument("--initial-cap", type=int, default=50_000)
    resume.add_argument(
        "--execute",
        action="store_true",
        help="Actually start workers. Without this flag, perform a dry-run audit.",
    )
    resume.add_argument(
        "--allow-source-machine",
        action="store_true",
        help="Explicitly override the source-machine execution guard.",
    )
    retry = subparsers.add_parser(
        "retry-long",
        help="Retry only the 10 DGA/DMCHBA failures present at handoff.",
    )
    retry.add_argument("--workers", type=int, required=True)
    retry.add_argument("--retry-cap", type=int, default=50_000)
    retry.add_argument(
        "--execute",
        action="store_true",
        help="Actually start workers. Without this flag, perform a dry-run audit.",
    )
    retry.add_argument(
        "--allow-source-machine",
        action="store_true",
        help="Explicitly override the source-machine execution guard.",
    )
    return parser.parse_args()


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def atomic_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, path)


def condition_rows() -> list[dict[str, str]]:
    rows = read_csv(CONDITION_MANIFEST)
    if len(rows) != EXPECTED_CONDITIONS:
        raise RuntimeError(
            f"expected {EXPECTED_CONDITIONS} conditions, found {len(rows)}"
        )
    return rows


def condition_dir(row: dict[str, str]) -> Path:
    algorithm = row["algorithm"].strip()
    condition_id = row["condition_id"].strip()
    suffix = condition_id.removeprefix(f"{algorithm.lower()}_")
    return RAW_ROOT / algorithm.lower() / suffix


def audit_condition(row: dict[str, str]) -> dict:
    directory = condition_dir(row)
    trials = read_csv(directory / "trial_summary.csv")
    systems = read_csv(directory / "system_performance.csv")
    robots = read_csv(directory / "robot_performance.csv")
    trial_ids = [int(item["trial_id"]) for item in trials]
    system_ids = [int(item["trial_id"]) for item in systems]
    robot_counts = Counter(int(item["trial_id"]) for item in robots)
    if len(trial_ids) != len(set(trial_ids)):
        raise RuntimeError(f"duplicate trial IDs in {directory}")
    if len(system_ids) != len(set(system_ids)):
        raise RuntimeError(f"duplicate system IDs in {directory}")
    if set(trial_ids) != set(system_ids):
        raise RuntimeError(f"trial/system ID mismatch in {directory}")
    if set(robot_counts) != set(trial_ids):
        raise RuntimeError(f"trial/robot ID mismatch in {directory}")
    if any(count != 4 for count in robot_counts.values()):
        raise RuntimeError(f"expected four robot rows per ID in {directory}")
    failed = sorted(
        int(item["trial_id"])
        for item in trials
        if item.get("trial_status", "").strip().lower() == "failed"
    )
    recorded = sorted(set(trial_ids))
    missing = sorted(set(range(EXPECTED_TRIALS)) - set(recorded))
    return {
        "algorithm": row["algorithm"].strip(),
        "condition_id": row["condition_id"].strip(),
        "condition_relative": directory.relative_to(REPO_ROOT).as_posix(),
        "recorded_ids": recorded,
        "completed_ids": sorted(set(recorded) - set(failed)),
        "failed_ids": failed,
        "missing_ids": missing,
    }


def audit_canonical() -> dict:
    conditions = [audit_condition(row) for row in condition_rows()]
    totals = {
        "expected": EXPECTED_CONDITIONS * EXPECTED_TRIALS,
        "recorded": sum(len(item["recorded_ids"]) for item in conditions),
        "completed": sum(len(item["completed_ids"]) for item in conditions),
        "failed": sum(len(item["failed_ids"]) for item in conditions),
        "missing": sum(len(item["missing_ids"]) for item in conditions),
    }
    return {"totals": totals, "conditions": conditions}


def validate_shard(directory: Path) -> dict:
    result_path = directory / "worker_result.json"
    if not result_path.exists():
        raise RuntimeError(f"incomplete shard lacks worker_result.json: {directory}")
    selected = int(directory.name.split("_")[-1])
    trials = read_csv(directory / "trial_summary.csv")
    systems = read_csv(directory / "system_performance.csv")
    robots = read_csv(directory / "robot_performance.csv")
    if len(trials) != 1 or len(systems) != 1 or len(robots) != 4:
        raise RuntimeError(f"invalid shard row counts: {directory}")
    if {int(row["trial_id"]) for row in trials + systems + robots} != {selected}:
        raise RuntimeError(f"wrong trial ID in shard: {directory}")
    return json.loads(result_path.read_text(encoding="utf-8"))


def audit_extracted_shards() -> dict:
    stages: dict[str, dict] = {}
    if not SHARD_ROOT.exists():
        return {"present": False, "stages": {}, "validated": 0}
    total = 0
    for stage_dir in sorted(path for path in SHARD_ROOT.iterdir() if path.is_dir()):
        shard_dirs = sorted(
            path
            for path in stage_dir.rglob("trial_*")
            if path.is_dir() and path.name.startswith("trial_")
        )
        statuses: Counter[str] = Counter()
        caps: Counter[str] = Counter()
        for directory in shard_dirs:
            result = validate_shard(directory)
            statuses[str(result.get("status", ""))] += 1
            caps[str(result.get("debug_max_events", ""))] += 1
        stages[stage_dir.name] = {
            "validated": len(shard_dirs),
            "statuses": dict(sorted(statuses.items())),
            "caps": dict(sorted(caps.items())),
        }
        total += len(shard_dirs)
    return {"present": True, "stages": stages, "validated": total}


def safe_zip_members(archive: zipfile.ZipFile) -> list[zipfile.ZipInfo]:
    members = archive.infolist()
    for member in members:
        path = PurePosixPath(member.filename)
        if path.is_absolute() or ".." in path.parts:
            raise RuntimeError(f"unsafe archive member: {member.filename}")
    return members


def archive_paths(
    destination: Path,
    paths: list[Path],
    prefix: str = "",
) -> dict:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".tmp")
    if temporary.exists():
        temporary.unlink()
    file_count = 0
    with zipfile.ZipFile(
        temporary,
        "w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
    ) as archive:
        for source in sorted(paths):
            if source.is_dir():
                files = sorted(path for path in source.rglob("*") if path.is_file())
            elif source.is_file():
                files = [source]
            else:
                continue
            for path in files:
                relative = path.relative_to(RUN_ROOT).as_posix()
                arcname = f"{prefix.rstrip('/')}/{relative}" if prefix else relative
                archive.write(path, arcname)
                file_count += 1
    with zipfile.ZipFile(temporary) as archive:
        if archive.testzip() is not None:
            raise RuntimeError(f"archive verification failed: {destination}")
        if len(safe_zip_members(archive)) != file_count:
            raise RuntimeError(f"archive member count mismatch: {destination}")
    os.replace(temporary, destination)
    return {
        "path": destination.relative_to(REPO_ROOT).as_posix(),
        "bytes": destination.stat().st_size,
        "sha256": sha256(destination),
        "files": file_count,
    }


def copy_frozen_runtime() -> dict:
    source_manifest = LEGACY_RUNTIME_ROOT / "SNAPSHOT_MANIFEST.json"
    source_root = LEGACY_RUNTIME_ROOT
    if not source_manifest.exists() and (RUNTIME_ROOT / "SNAPSHOT_MANIFEST.json").exists():
        source_manifest = RUNTIME_ROOT / "SNAPSHOT_MANIFEST.json"
        source_root = RUNTIME_ROOT
    manifest = json.loads(source_manifest.read_text(encoding="utf-8"))
    RUNTIME_ROOT.mkdir(parents=True, exist_ok=True)
    for relative, expected in manifest["files"].items():
        source = source_root / relative
        destination = RUNTIME_ROOT / relative
        if not source.exists():
            raise RuntimeError(f"frozen-runtime file missing: {source}")
        if sha256(source) != expected:
            raise RuntimeError(f"frozen-runtime source checksum changed: {source}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        if not destination.exists() or sha256(destination) != expected:
            shutil.copy2(source, destination)
    destination_manifest = RUNTIME_ROOT / "SNAPSHOT_MANIFEST.json"
    if source_manifest.resolve() != destination_manifest.resolve():
        shutil.copy2(source_manifest, destination_manifest)
    verify_frozen_runtime()
    return {
        "path": RUNTIME_ROOT.relative_to(REPO_ROOT).as_posix(),
        "manifest_sha256": sha256(destination_manifest),
        "files": len(manifest["files"]),
    }


def verify_frozen_runtime() -> None:
    manifest_path = RUNTIME_ROOT / "SNAPSHOT_MANIFEST.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for relative, expected in manifest["files"].items():
        path = RUNTIME_ROOT / relative
        if not path.exists() or sha256(path) != expected:
            raise RuntimeError(f"frozen-runtime verification failed: {path}")


def historical_files() -> list[Path]:
    files: list[Path] = []
    for path in RUN_ROOT.iterdir():
        if not path.is_file():
            continue
        if path.name in {
            "README.md",
            "condition_manifest.csv",
            "TRANSFER_MANIFEST.json",
            "TRANSFER_STATUS.json",
            "TRANSFER_CHECKSUMS.sha256",
        }:
            continue
        files.append(path)
    for path in RAW_ROOT.rglob("*"):
        if path.is_file() and path.name not in CANONICAL_NAMES:
            files.append(path)
    return sorted(set(files))


def archived_item(path: Path) -> dict:
    if not path.exists():
        raise RuntimeError(f"expected existing archive: {path}")
    with zipfile.ZipFile(path) as archive:
        members = safe_zip_members(archive)
        if archive.testzip() is not None:
            raise RuntimeError(f"archive verification failed: {path}")
    return {
        "path": path.relative_to(REPO_ROOT).as_posix(),
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
        "files": len(members),
    }


def archive_history(paths: list[Path]) -> dict:
    """Add new history files without dropping earlier archived evidence."""
    if not paths:
        return archived_item(HISTORY_ARCHIVE)
    HISTORY_ARCHIVE.parent.mkdir(parents=True, exist_ok=True)
    temporary = HISTORY_ARCHIVE.with_suffix(HISTORY_ARCHIVE.suffix + ".tmp")
    if temporary.exists():
        temporary.unlink()
    new_members = {
        f"history/{path.relative_to(RUN_ROOT).as_posix()}": path
        for path in paths
    }
    with zipfile.ZipFile(
        temporary,
        "w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
    ) as destination:
        if HISTORY_ARCHIVE.exists():
            with zipfile.ZipFile(HISTORY_ARCHIVE) as source:
                for member in safe_zip_members(source):
                    if member.is_dir() or member.filename in new_members:
                        continue
                    with source.open(member) as source_handle:
                        with destination.open(member, "w", force_zip64=True) as output:
                            shutil.copyfileobj(source_handle, output)
        for member, path in sorted(new_members.items()):
            destination.write(path, member)
    with zipfile.ZipFile(temporary) as archive:
        if archive.testzip() is not None:
            raise RuntimeError(f"archive verification failed: {HISTORY_ARCHIVE}")
        members = safe_zip_members(archive)
    os.replace(temporary, HISTORY_ARCHIVE)
    return {
        "path": HISTORY_ARCHIVE.relative_to(REPO_ROOT).as_posix(),
        "bytes": HISTORY_ARCHIVE.stat().st_size,
        "sha256": sha256(HISTORY_ARCHIVE),
        "files": len(members),
    }


def write_transfer_documents(
    canonical: dict,
    shard_audit: dict,
    runtime_info: dict,
    artifact_info: dict,
) -> None:
    old_manifest = {}
    if TRANSFER_MANIFEST.exists():
        old_manifest = json.loads(TRANSFER_MANIFEST.read_text(encoding="utf-8"))
    old_conditions = {
        item["condition_id"]: item for item in old_manifest.get("conditions", [])
    }
    manifest_rows = {row["condition_id"]: row for row in condition_rows()}
    conditions = []
    for item in canonical["conditions"]:
        previous = old_conditions.get(item["condition_id"], {})
        manifest_row = manifest_rows[item["condition_id"]]
        directory = REPO_ROOT / item["condition_relative"]
        files = {
            path.name: {"bytes": path.stat().st_size, "sha256": sha256(path)}
            for path in sorted(directory.iterdir())
            if path.is_file() and path.name in CANONICAL_NAMES
        } if directory.exists() else {}
        enriched = dict(item)
        enriched.update(
            {
                "expected_trials": EXPECTED_TRIALS,
                "target_drop_fraction": manifest_row["target_drop_fraction"],
                "comm_level_stationary_delivery": manifest_row[
                    "comm_level_stationary_delivery"
                ],
                "source_command": json.loads(manifest_row["source_command"]),
                "estimated_seconds_per_trial": previous.get(
                    "estimated_seconds_per_trial"
                ),
                "estimate_basis": previous.get("estimate_basis"),
                "handoff_failed_ids": previous.get(
                    "handoff_failed_ids",
                    previous.get("failed_ids", item["failed_ids"]),
                ),
                "files": files,
            }
        )
        conditions.append(enriched)
    missing_validated = shard_audit["stages"].get("missing", {}).get("validated", 0)
    effective_remaining = canonical["totals"]["missing"] - missing_validated
    transfer_manifest = {
        "format_version": 2,
        "generated_at_unix": time.time(),
        "generated_at_local": time.strftime("%Y-%m-%d %H:%M:%S %Z"),
        "git_head_at_pack": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=REPO_ROOT, text=True
        ).strip(),
        "source_machine": platform.node(),
        "coverage_root": RUN_ROOT.relative_to(REPO_ROOT).as_posix(),
        "runtime_relative": runtime_info["path"],
        "runtime_manifest_sha256": runtime_info["manifest_sha256"],
        "totals": canonical["totals"],
        "validated_shards": shard_audit,
        "effective_missing_trials_to_compute": effective_remaining,
        "resume_algorithms": sorted(LONG_ALGORITHMS),
        "finalized_failure_algorithms": sorted(QUICK_ALGORITHMS),
        "artifacts": artifact_info,
        "conditions": conditions,
        "notes": [
            "The 298 ACBBA/CBAA/HIPC/PI failures are final after 100000 events.",
            "Only missing DGA/DMCHBA IDs should resume on the destination computer.",
            "After the missing stage, retry only the 10 long-algorithm handoff failures at 50000 events.",
            "Restore validated_shards.zip before execution to reuse 69 missing-stage shards.",
            "Paused partial shard directories were intentionally discarded during packing.",
        ],
    }
    status = {
        "campaign": "corrected_ge_coverage_100",
        "packed_at_local": transfer_manifest["generated_at_local"],
        "canonical": canonical["totals"],
        "validated_shards": shard_audit["stages"],
        "effective_missing_trials_to_compute": effective_remaining,
        "next_stage": "missing DGA/DMCHBA, then 10 handoff failure retries",
        "workers_used_before_transfer": 12,
        "initial_cap": 50_000,
        "quick_algorithm_terminal_failure_cap": 100_000,
        "quick_algorithm_terminal_failures": 298,
        "running_processes_expected": 0,
    }
    atomic_text(TRANSFER_MANIFEST, json.dumps(transfer_manifest, indent=2) + "\n")
    atomic_text(TRANSFER_STATUS, json.dumps(status, indent=2) + "\n")


def transfer_files_for_checksums() -> list[Path]:
    paths = [
        RUN_ROOT / "README.md",
        CONDITION_MANIFEST,
        TRANSFER_MANIFEST,
        TRANSFER_STATUS,
        ARTIFACT_MANIFEST,
        SHARD_ARCHIVE,
        HISTORY_ARCHIVE,
    ]
    paths.extend(path for path in RAW_ROOT.rglob("*") if path.is_file())
    paths.extend(path for path in RUNTIME_ROOT.rglob("*") if path.is_file())
    paths.extend(path for path in DOC_ROOT.rglob("*") if path.is_file())
    return sorted(set(path for path in paths if path.exists()))


def write_checksums() -> None:
    lines = [
        f"{sha256(path)}  {path.relative_to(REPO_ROOT).as_posix()}"
        for path in transfer_files_for_checksums()
    ]
    atomic_text(CHECKSUM_PATH, "\n".join(lines) + "\n")


def verify_checksums() -> dict:
    if not CHECKSUM_PATH.exists():
        raise RuntimeError(f"missing checksum file: {CHECKSUM_PATH}")
    checked = 0
    for line in CHECKSUM_PATH.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        expected, relative = line.split("  ", 1)
        path = REPO_ROOT / relative
        if not path.exists():
            raise RuntimeError(f"transfer file missing: {relative}")
        actual = sha256(path)
        if actual != expected:
            raise RuntimeError(f"transfer checksum mismatch: {relative}")
        checked += 1
    return {"checked_files": checked}


def remove_empty_parents(start: Path, stop: Path) -> None:
    current = start
    while current != stop and current.exists():
        try:
            current.rmdir()
        except OSError:
            break
        current = current.parent


def pack() -> dict:
    canonical = audit_canonical()
    runtime_info = copy_frozen_runtime()
    shard_audit = audit_extracted_shards()
    if not shard_audit["present"] or shard_audit["validated"] == 0:
        if not SHARD_ARCHIVE.exists() or not ARTIFACT_MANIFEST.exists():
            raise RuntimeError("no extracted shards or existing shard archive to pack")
        artifact_info = json.loads(ARTIFACT_MANIFEST.read_text(encoding="utf-8"))
    else:
        shard_archive_info = archive_paths(SHARD_ARCHIVE, [SHARD_ROOT])
        history = historical_files()
        history_archive_info = (
            archive_history(history)
            if history
            else archived_item(HISTORY_ARCHIVE)
        )
        artifact_info = {
            "created_at_local": time.strftime("%Y-%m-%d %H:%M:%S %Z"),
            "validated_shards": shard_archive_info,
            "historical_logs": history_archive_info,
            "shard_audit": shard_audit,
        }
        atomic_text(ARTIFACT_MANIFEST, json.dumps(artifact_info, indent=2) + "\n")
        with zipfile.ZipFile(SHARD_ARCHIVE) as archive:
            if archive.testzip() is not None:
                raise RuntimeError("validated shard archive failed final verification")
        shutil.rmtree(SHARD_ROOT)
        for path in history:
            if path.exists():
                path.unlink()
        quarantine = RUN_ROOT / "_paused_quarantine"
        if quarantine.exists():
            shutil.rmtree(quarantine)
        for directory in sorted(
            (path for path in RAW_ROOT.rglob("*") if path.is_dir()),
            reverse=True,
        ):
            remove_empty_parents(directory, RAW_ROOT)
    write_transfer_documents(
        canonical=canonical,
        shard_audit=artifact_info["shard_audit"],
        runtime_info=runtime_info,
        artifact_info={
            "validated_shards": artifact_info["validated_shards"],
            "historical_logs": artifact_info["historical_logs"],
        },
    )
    write_checksums()
    verification = verify()
    return {"packed": True, **verification}


def verify() -> dict:
    checksum = verify_checksums()
    canonical = audit_canonical()
    verify_frozen_runtime()
    artifact = json.loads(ARTIFACT_MANIFEST.read_text(encoding="utf-8"))
    for key in ("validated_shards", "historical_logs"):
        item = artifact[key]
        path = REPO_ROOT / item["path"]
        if path.stat().st_size != item["bytes"] or sha256(path) != item["sha256"]:
            raise RuntimeError(f"artifact verification failed: {path}")
        with zipfile.ZipFile(path) as archive:
            if archive.testzip() is not None:
                raise RuntimeError(f"corrupt artifact archive: {path}")
            safe_zip_members(archive)
    return {
        "verified": True,
        "checksums": checksum,
        "canonical": canonical["totals"],
        "effective_missing_trials_to_compute": json.loads(
            TRANSFER_STATUS.read_text(encoding="utf-8")
        )["effective_missing_trials_to_compute"],
        "shards_extracted": SHARD_ROOT.exists(),
    }


def restore() -> dict:
    verification = verify()
    if SHARD_ROOT.exists():
        audit = audit_extracted_shards()
        return {"restored": False, "reason": "already extracted", "audit": audit}
    with zipfile.ZipFile(SHARD_ARCHIVE) as archive:
        members = safe_zip_members(archive)
        for member in members:
            target = (RUN_ROOT / member.filename).resolve()
            if RUN_ROOT.resolve() not in target.parents and target != RUN_ROOT.resolve():
                raise RuntimeError(f"archive extraction escaped run root: {member.filename}")
        archive.extractall(RUN_ROOT)
    audit = audit_extracted_shards()
    expected = json.loads(ARTIFACT_MANIFEST.read_text(encoding="utf-8"))[
        "shard_audit"
    ]["validated"]
    if audit["validated"] != expected:
        raise RuntimeError(
            f"restored {audit['validated']} shards, expected {expected}"
        )
    return {"restored": True, "verification": verification, "audit": audit}


def status() -> dict:
    canonical = audit_canonical()
    artifact = (
        json.loads(ARTIFACT_MANIFEST.read_text(encoding="utf-8"))
        if ARTIFACT_MANIFEST.exists()
        else {}
    )
    extracted = audit_extracted_shards()
    archived_shards = artifact.get("shard_audit", {})
    missing_validated = (
        extracted.get("stages", {}).get("missing", {}).get("validated", 0)
        if extracted["present"]
        else archived_shards.get("stages", {}).get("missing", {}).get(
            "validated", 0
        )
    )
    return {
        "canonical": canonical["totals"],
        "validated_missing_shards": missing_validated,
        "effective_missing_trials_to_compute": (
            canonical["totals"]["missing"] - missing_validated
        ),
        "shards_extracted": extracted["present"],
        "handoff_long_algorithm_failures_to_retry": 10,
        "next_stage": "missing DGA/DMCHBA, then 10 handoff failure retries",
    }


def resume(args: argparse.Namespace) -> int:
    if args.workers < 1:
        raise SystemExit("--workers must be positive")
    restore_result = restore()
    command = [
        sys.executable,
        str(REPO_ROOT / "analysis" / "resume_coverage_sharded.py"),
        "--workers",
        str(args.workers),
        "--initial-cap",
        str(args.initial_cap),
        "--algorithms",
        "DGA",
        "DMCHBA",
        "--missing-only",
    ]
    if args.execute:
        command.append("--execute")
    if args.allow_source_machine:
        command.append("--allow-source-machine")
    print(
        json.dumps(
            {
                "restore": restore_result,
                "command": command,
                "execute": args.execute,
            },
            indent=2,
        ),
        flush=True,
    )
    return subprocess.call(command, cwd=REPO_ROOT)


def retry_long(args: argparse.Namespace) -> int:
    if args.workers < 1:
        raise SystemExit("--workers must be positive")
    restore_result = restore()
    command = [
        sys.executable,
        str(REPO_ROOT / "analysis" / "resume_coverage_sharded.py"),
        "--workers",
        str(args.workers),
        "--retry-cap",
        str(args.retry_cap),
        "--retry-only",
        "--handoff-failures-only",
        "--retry-stage",
        f"retry_long_{args.retry_cap}",
        "--algorithms",
        "DGA",
        "DMCHBA",
    ]
    if args.execute:
        command.append("--execute")
    if args.allow_source_machine:
        command.append("--allow-source-machine")
    print(
        json.dumps(
            {
                "restore": restore_result,
                "command": command,
                "execute": args.execute,
            },
            indent=2,
        ),
        flush=True,
    )
    return subprocess.call(command, cwd=REPO_ROOT)


def main() -> int:
    args = parse_args()
    if args.command == "pack":
        result = pack()
    elif args.command == "verify":
        result = verify()
    elif args.command == "restore":
        result = restore()
    elif args.command == "status":
        result = status()
    elif args.command == "resume":
        return resume(args)
    elif args.command == "retry-long":
        return retry_long(args)
    else:
        raise AssertionError(args.command)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
