#!/usr/bin/env python3
"""Restore the corrected fixed-rho GE CLIPS/CV bundles from commit f898015.

The active result files displaced by the repository relayout are moved into
scenario-local archives.  Corrected Git blobs are staged and validated before
any active file is moved.  The script never modifies FGS results.
"""

from __future__ import annotations

import csv
import hashlib
import json
import shutil
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
REVISION = "f898015"
ARCHIVE_NAME = "pre_corrected_active_20260809"


@dataclass(frozen=True)
class RestoreItem:
    destination_name: str
    sources: tuple[str, ...]
    expected_rows: int | None = None


@dataclass(frozen=True)
class Bundle:
    name: str
    active_dir: Path
    items: tuple[RestoreItem, ...]


CLIPS_DIR = REPO_ROOT / "results" / "clue_search_core_500" / "combined"
CV_DIR = REPO_ROOT / "results" / "known_target_visit_core_500" / "combined"

BUNDLES = (
    Bundle(
        "CLIPS",
        CLIPS_DIR,
        (
            RestoreItem(
                "clue_search_core_500_combined_condition_manifest.csv",
                ("clue_500_combined/condition_manifest.csv",),
                150,
            ),
            RestoreItem(
                "clue_search_core_500_combined_system_performance.csv",
                ("clue_500_combined/system_performance_bay.csv",),
                75_000,
            ),
            RestoreItem(
                "clue_search_core_500_combined_trial_summary.csv",
                ("clue_500_combined/trial_summary.csv",),
                75_000,
            ),
            RestoreItem(
                "clue_search_core_500_combined_robot_performance.csv",
                (
                    "clue_500_combined/robot_performance_part_001.csv",
                    "clue_500_combined/robot_performance_part_002.csv",
                ),
                300_000,
            ),
            RestoreItem(
                "clue_search_core_500_corrected_ge_condition_manifest.csv",
                ("clue_500_combined/corrected_ge_condition_manifest.csv",),
                48,
            ),
        ),
    ),
    Bundle(
        "CV",
        CV_DIR,
        (
            RestoreItem(
                "known_target_visit_core_500_combined_condition_manifest.csv",
                ("known_visit_core_500_combined/condition_manifest.csv",),
                150,
            ),
            RestoreItem(
                "known_target_visit_core_500_combined_system_performance.csv",
                ("known_visit_core_500_combined/system_performance_known.csv",),
                75_000,
            ),
            RestoreItem(
                "known_target_visit_core_500_combined_trial_summary.csv",
                ("known_visit_core_500_combined/trial_summary.csv",),
                75_000,
            ),
            RestoreItem(
                "known_target_visit_core_500_combined_robot_performance.csv",
                ("known_visit_core_500_combined/robot_performance.csv",),
                300_000,
            ),
            *(
                RestoreItem(
                    f"target_performance_part_{part:03d}.csv",
                    (f"known_visit_core_500_combined/target_performance_part_{part:03d}.csv",),
                    expected_rows,
                )
                for part, expected_rows in enumerate(
                    (140_000, 140_000, 140_000, 140_000, 140_000, 50_000),
                    start=1,
                )
            ),
            RestoreItem(
                "target_performance_parts_manifest.csv",
                ("known_visit_core_500_combined/target_performance_parts_manifest.csv",),
                6,
            ),
            RestoreItem(
                "known_target_visit_core_500_corrected_ge_condition_manifest.csv",
                ("known_visit_core_500_combined/corrected_ge_condition_manifest.csv",),
                48,
            ),
        ),
    ),
)


def git_blob_process(source: str) -> subprocess.Popen[bytes]:
    return subprocess.Popen(
        ["git", "show", f"{REVISION}:{source}"],
        cwd=REPO_ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def stream_item(item: RestoreItem, destination: Path) -> None:
    header: bytes | None = None
    with destination.open("wb") as output:
        for source_index, source in enumerate(item.sources):
            process = git_blob_process(source)
            assert process.stdout is not None
            source_header = process.stdout.readline()
            if not source_header:
                stderr = process.stderr.read().decode("utf-8", errors="replace") if process.stderr else ""
                raise RuntimeError(f"Empty or missing Git blob {source}: {stderr}")
            if header is None:
                header = source_header
                output.write(source_header)
            elif source_header.rstrip(b"\r\n") != header.rstrip(b"\r\n"):
                process.kill()
                raise RuntimeError(f"CSV header mismatch while joining {source}")
            shutil.copyfileobj(process.stdout, output, length=1024 * 1024)
            stderr = process.stderr.read().decode("utf-8", errors="replace") if process.stderr else ""
            return_code = process.wait()
            if return_code:
                raise RuntimeError(f"git show failed for {source}: {stderr}")
            if source_index and destination.stat().st_size == 0:
                raise RuntimeError(f"Failed to append {source}")


def csv_rows(path: Path) -> int:
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle)
        try:
            next(reader)
        except StopIteration as exc:
            raise RuntimeError(f"CSV is empty: {path}") from exc
        return sum(1 for _ in reader)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    subprocess.run(
        ["git", "cat-file", "-e", f"{REVISION}^{{commit}}"],
        cwd=REPO_ROOT,
        check=True,
    )

    staged: dict[str, list[dict[str, object]]] = {}
    for bundle in BUNDLES:
        archive_dir = bundle.active_dir / "archive" / ARCHIVE_NAME
        stage_dir = bundle.active_dir / f".restore_{REVISION}_staging"
        if archive_dir.exists():
            raise RuntimeError(f"Archive already exists; refusing to overwrite: {archive_dir}")
        if stage_dir.exists():
            # A prior validation failure can leave only disposable staged
            # blobs.  No active files have moved unless the archive exists.
            if archive_dir.exists():
                raise RuntimeError(
                    f"Both archive and staging exist; refusing ambiguous recovery: {stage_dir}"
                )
            shutil.rmtree(stage_dir)
        stage_dir.mkdir(parents=True)
        staged[bundle.name] = []
        for item in bundle.items:
            destination = stage_dir / item.destination_name
            print(f"Staging {bundle.name}: {item.destination_name}")
            stream_item(item, destination)
            row_count = csv_rows(destination)
            if item.expected_rows is not None and row_count != item.expected_rows:
                raise RuntimeError(
                    f"Unexpected rows for {destination}: {row_count} != {item.expected_rows}"
                )
            staged[bundle.name].append(
                {
                    "destination_name": item.destination_name,
                    "git_sources": list(item.sources),
                    "rows": row_count,
                    "bytes": destination.stat().st_size,
                    "sha256": sha256(destination),
                }
            )

    for bundle in BUNDLES:
        archive_dir = bundle.active_dir / "archive" / ARCHIVE_NAME
        stage_dir = bundle.active_dir / f".restore_{REVISION}_staging"
        archive_dir.mkdir(parents=True)
        archived_files: list[dict[str, object]] = []
        for active_file in sorted(bundle.active_dir.iterdir()):
            if not active_file.is_file():
                continue
            archived_files.append(
                {
                    "name": active_file.name,
                    "bytes": active_file.stat().st_size,
                    "sha256": sha256(active_file),
                }
            )
            shutil.move(str(active_file), archive_dir / active_file.name)

        for staged_file in sorted(stage_dir.iterdir()):
            shutil.move(str(staged_file), bundle.active_dir / staged_file.name)
        stage_dir.rmdir()

        manifest = {
            "restored_utc": datetime.now(timezone.utc).isoformat(),
            "source_revision": REVISION,
            "bundle": bundle.name,
            "active_directory": str(bundle.active_dir.relative_to(REPO_ROOT)).replace("\\", "/"),
            "archived_directory": str(archive_dir.relative_to(REPO_ROOT)).replace("\\", "/"),
            "archived_files": archived_files,
            "restored_files": staged[bundle.name],
        }
        (bundle.active_dir / "CORRECTED_GE_RESTORE_MANIFEST.json").write_text(
            json.dumps(manifest, indent=2) + "\n",
            encoding="utf-8",
        )

    print("Corrected fixed-rho GE bundles restored for CLIPS and CV.")
    print("FGS files were not modified.")


if __name__ == "__main__":
    main()
