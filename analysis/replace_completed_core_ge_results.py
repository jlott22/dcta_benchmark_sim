#!/usr/bin/env python3
"""Archive legacy combined results and replace only completed-suite GE rows.

This utility intentionally supports the completed clue-search and known-target
suites only. Coverage is out of scope and is never read or written.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Iterator


REPO_ROOT = Path(__file__).resolve().parents[1]
GE_MODEL = "gilbert_elliot"
EXPECTED_CONDITIONS = 48
EXPECTED_TRIALS_PER_CONDITION = 500


@dataclass(frozen=True)
class DataFile:
    main_name: str
    corrected_name: str
    multiplier: int


@dataclass(frozen=True)
class Suite:
    key: str
    label: str
    main_dir: Path
    corrected_dir: Path
    stage: str
    environment: str
    data_files: tuple[DataFile, ...]
    target_parts: bool = False


SUITES = (
    Suite(
        key="clue",
        label="clue-search",
        main_dir=REPO_ROOT / "clue_500_combined",
        corrected_dir=REPO_ROOT / "clue_500_ge_bursty_rho08_combined",
        stage="clue_core",
        environment="clue",
        data_files=(
            DataFile("trial_summary.csv", "trial_summary.csv", 1),
            DataFile("system_performance_bay.csv", "system_performance.csv", 1),
            DataFile("robot_performance.csv", "robot_performance.csv", 4),
        ),
    ),
    Suite(
        key="known",
        label="known-target",
        main_dir=REPO_ROOT / "known_visit_core_500_combined",
        corrected_dir=REPO_ROOT / "known_visit_core_500_ge_bursty_rho08_combined",
        stage="known_core",
        environment="known",
        data_files=(
            DataFile("trial_summary.csv", "trial_summary.csv", 1),
            DataFile("system_performance_known.csv", "system_performance.csv", 1),
            DataFile("robot_performance.csv", "robot_performance.csv", 4),
        ),
        target_parts=True,
    ),
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def csv_data_rows(path: Path) -> int:
    return sum(1 for _ in rows_from(path))


def read_header(path: Path) -> list[str]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle).fieldnames or [])


def rows_from(path: Path) -> Iterator[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        yield from csv.DictReader(handle)


def compact_float(value: str) -> str:
    number = float(value)
    return f"{number:.12g}"


def relative_run_path(value: str) -> str:
    normalized = value.replace("\\", "/")
    marker = "/runs/"
    if marker in normalized.lower():
        index = normalized.lower().index(marker)
        return normalized[index + 1 :]
    if normalized.lower().startswith("runs/"):
        return normalized
    raise RuntimeError(f"Corrected output path is not under runs/: {value}")


def communication_label(manifest_row: dict[str, str]) -> str:
    prefix = manifest_row["algorithm"].lower() + "_"
    condition_id = manifest_row["condition_id"]
    if not condition_id.lower().startswith(prefix):
        raise RuntimeError(f"Unexpected corrected condition ID: {condition_id}")
    return condition_id[len(prefix) :]


def load_corrected_manifest(suite: Suite) -> tuple[list[dict[str, str]], dict[str, dict[str, str]]]:
    path = suite.corrected_dir / "condition_manifest.csv"
    rows = list(rows_from(path))
    if len(rows) != EXPECTED_CONDITIONS:
        raise RuntimeError(
            f"{suite.key}: expected {EXPECTED_CONDITIONS} corrected manifest rows, found {len(rows)}"
        )
    by_condition: dict[str, dict[str, str]] = {}
    pairs: set[tuple[str, str]] = set()
    for row in rows:
        condition_id = row["condition_id"]
        if condition_id in by_condition:
            raise RuntimeError(f"{suite.key}: duplicate corrected manifest condition {condition_id}")
        if row.get("comm_model", "").lower() != GE_MODEL:
            raise RuntimeError(f"{suite.key}: non-GE corrected manifest row {condition_id}")
        if int(row["expected_trials"]) != EXPECTED_TRIALS_PER_CONDITION:
            raise RuntimeError(f"{suite.key}: unexpected trial count in {condition_id}")
        pairs.add((row["algorithm"].upper(), compact_float(row["target_drop_fraction"])))
        by_condition[condition_id] = row
    if len(pairs) != EXPECTED_CONDITIONS:
        raise RuntimeError(f"{suite.key}: corrected manifest does not contain 6 x 8 conditions")
    return rows, by_condition


def transformed_corrected_row(
    row: dict[str, str],
    output_fields: list[str],
    suite: Suite,
    manifest_by_condition: dict[str, dict[str, str]],
) -> dict[str, str]:
    condition_id = row.get("condition_id", "")
    try:
        manifest = manifest_by_condition[condition_id]
    except KeyError as error:
        raise RuntimeError(f"{suite.key}: row has unknown corrected condition {condition_id}") from error

    output = {field: row.get(field, "") for field in output_fields}
    metadata = {
        "stage": suite.stage,
        "environment": suite.environment,
        "algorithm_key": manifest["algorithm"].lower(),
        "commitment_horizon": manifest.get("commitment_horizon", ""),
        "dga_iterations": manifest.get("dga_iterations", ""),
        "comm_label": communication_label(manifest),
        "comm_model": GE_MODEL,
        "comm_level": compact_float(manifest["comm_level_stationary_delivery"]),
        "condition_id": condition_id,
        "scenario_file": manifest["scenario_file"].replace("\\", "/"),
        "out_dir": relative_run_path(manifest["out_dir"]),
        "run_id": condition_id,
    }
    for field, value in metadata.items():
        if field in output:
            output[field] = value
    return output


def transformed_manifest_row(
    row: dict[str, str], output_fields: list[str], suite: Suite
) -> dict[str, str]:
    condition_id = row["condition_id"]
    values = {
        "stage": suite.stage,
        "environment": suite.environment,
        "algorithm_key": row["algorithm"].lower(),
        "algorithm": row["algorithm"],
        "commitment_horizon": row.get("commitment_horizon", ""),
        "dga_iterations": row.get("dga_iterations", ""),
        "comm_label": communication_label(row),
        "comm_model": GE_MODEL,
        "comm_level": compact_float(row["comm_level_stationary_delivery"]),
        "scenario_file": row["scenario_file"].replace("\\", "/"),
        "out_dir": relative_run_path(row["out_dir"]),
        "run_id": condition_id,
        "expected_trials": row["expected_trials"],
        "command": row.get("command", ""),
    }
    return {field: values.get(field, "") for field in output_fields}


def canonical_non_ge_digest(paths: Iterable[Path], fields: list[str]) -> tuple[str, int]:
    digest = hashlib.sha256()
    count = 0
    for path in paths:
        for row in rows_from(path):
            if row.get("comm_model", "").lower() == GE_MODEL:
                continue
            payload = json.dumps(
                [row.get(field, "") for field in fields],
                ensure_ascii=False,
                separators=(",", ":"),
            )
            digest.update(payload.encode("utf-8"))
            digest.update(b"\n")
            count += 1
    return digest.hexdigest(), count


def write_replaced_csv(
    old_path: Path,
    corrected_path: Path,
    output_path: Path,
    suite: Suite,
    manifest_by_condition: dict[str, dict[str, str]],
) -> dict[str, int]:
    fields = read_header(old_path)
    corrected_fields = set(read_header(corrected_path))
    required = {"trial_id", "algorithm", "comm_model", "condition_id"}
    if not required.issubset(corrected_fields):
        raise RuntimeError(f"{corrected_path}: missing required corrected fields")

    counts = Counter()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="", encoding="utf-8") as destination:
        writer = csv.DictWriter(destination, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for row in rows_from(old_path):
            if row.get("comm_model", "").lower() == GE_MODEL:
                counts["old_ge_removed"] += 1
                continue
            writer.writerow({field: row.get(field, "") for field in fields})
            counts["non_ge_preserved"] += 1
        for row in rows_from(corrected_path):
            writer.writerow(
                transformed_corrected_row(row, fields, suite, manifest_by_condition)
            )
            counts["corrected_ge_added"] += 1
    counts["total"] = counts["non_ge_preserved"] + counts["corrected_ge_added"]
    return dict(counts)


def write_replaced_manifest(
    old_path: Path,
    corrected_rows: list[dict[str, str]],
    output_path: Path,
    suite: Suite,
) -> dict[str, int]:
    fields = read_header(old_path)
    counts = Counter()
    with output_path.open("w", newline="", encoding="utf-8") as destination:
        writer = csv.DictWriter(destination, fieldnames=fields)
        writer.writeheader()
        for row in rows_from(old_path):
            if row.get("comm_model", "").lower() == GE_MODEL:
                counts["old_ge_removed"] += 1
                continue
            writer.writerow({field: row.get(field, "") for field in fields})
            counts["non_ge_preserved"] += 1
        for row in corrected_rows:
            writer.writerow(transformed_manifest_row(row, fields, suite))
            counts["corrected_ge_added"] += 1
    counts["total"] = counts["non_ge_preserved"] + counts["corrected_ge_added"]
    return dict(counts)


def target_part_paths(directory: Path) -> list[Path]:
    return sorted(directory.glob("target_performance_part_[0-9][0-9][0-9].csv"))


def write_replaced_target_parts(
    suite: Suite,
    output_dir: Path,
    manifest_by_condition: dict[str, dict[str, str]],
) -> dict[str, int]:
    old_parts = target_part_paths(suite.main_dir)
    if len(old_parts) != 6:
        raise RuntimeError(f"{suite.key}: expected 6 old target parts, found {len(old_parts)}")
    part_manifest = suite.main_dir / "target_performance_parts_manifest.csv"
    capacities = [
        int(row["data_rows"])
        for row in rows_from(part_manifest)
    ]
    if len(capacities) != len(old_parts):
        raise RuntimeError(f"{suite.key}: target part manifest/part count mismatch")
    corrected_path = suite.corrected_dir / "target_performance.csv"
    fields = read_header(old_parts[0])
    counts = Counter()

    def output_rows() -> Iterator[dict[str, str]]:
        for path in old_parts:
            if read_header(path) != fields:
                raise RuntimeError(f"{suite.key}: target part header mismatch in {path.name}")
            for row in rows_from(path):
                if row.get("comm_model", "").lower() == GE_MODEL:
                    counts["old_ge_removed"] += 1
                    continue
                counts["non_ge_preserved"] += 1
                yield {field: row.get(field, "") for field in fields}
        for row in rows_from(corrected_path):
            counts["corrected_ge_added"] += 1
            yield transformed_corrected_row(row, fields, suite, manifest_by_condition)

    iterator = output_rows()
    part_rows: list[tuple[str, int]] = []
    for index, capacity in enumerate(capacities, start=1):
        name = f"target_performance_part_{index:03d}.csv"
        path = output_dir / name
        written = 0
        with path.open("w", newline="", encoding="utf-8") as destination:
            writer = csv.DictWriter(destination, fieldnames=fields)
            writer.writeheader()
            while written < capacity:
                try:
                    writer.writerow(next(iterator))
                except StopIteration as error:
                    raise RuntimeError(
                        f"{suite.key}: target rows ended in {name} at {written:,}/{capacity:,}"
                    ) from error
                written += 1
        part_rows.append((name, written))
    try:
        next(iterator)
    except StopIteration:
        pass
    else:
        raise RuntimeError(f"{suite.key}: target rows exceed original part capacities")

    with (output_dir / "target_performance_parts_manifest.csv").open(
        "w", newline="", encoding="utf-8"
    ) as destination:
        writer = csv.writer(destination)
        writer.writerow(("part_file", "data_rows"))
        writer.writerows(part_rows)
    counts["total"] = sum(count for _, count in part_rows)
    return dict(counts)


def validate_corrected_rows(
    paths: list[Path],
    suite: Suite,
    manifest_by_condition: dict[str, dict[str, str]],
    multiplier: int,
) -> dict[str, int]:
    trial_counts: dict[str, Counter[int]] = defaultdict(Counter)
    corrected_rows = failed_rows = 0
    for path in paths:
        for row in rows_from(path):
            if row.get("comm_model", "").lower() != GE_MODEL:
                continue
            corrected_rows += 1
            condition_id = row.get("condition_id", "")
            if condition_id not in manifest_by_condition:
                raise RuntimeError(f"{suite.key}: output contains old/unknown GE condition {condition_id}")
            status = row.get("trial_status", "").lower()
            if status and status != "completed":
                failed_rows += 1
            trial_counts[condition_id][int(row["trial_id"])] += 1
    expected_rows = EXPECTED_CONDITIONS * EXPECTED_TRIALS_PER_CONDITION * multiplier
    if corrected_rows != expected_rows:
        raise RuntimeError(
            f"{suite.key}: expected {expected_rows:,} corrected GE rows, found {corrected_rows:,}"
        )
    if failed_rows:
        raise RuntimeError(f"{suite.key}: found {failed_rows:,} non-completed corrected GE rows")
    expected_ids = set(range(EXPECTED_TRIALS_PER_CONDITION))
    for condition_id in manifest_by_condition:
        counts = trial_counts.get(condition_id, Counter())
        if set(counts) != expected_ids:
            raise RuntimeError(f"{suite.key}: incorrect trial IDs in {condition_id}")
        if set(counts.values()) != {multiplier}:
            raise RuntimeError(
                f"{suite.key}: incorrect per-trial row multiplier in {condition_id}"
            )
    return {"corrected_ge_rows": corrected_rows, "failed_ge_rows": failed_rows}


def archive_file_metadata(path: Path, suite: Suite, archive_dir: Path) -> dict[str, object]:
    return {
        "suite": suite.key,
        "original_path": str(path.relative_to(REPO_ROOT)).replace("\\", "/"),
        "archived_path": str((archive_dir / path.name).relative_to(REPO_ROOT)).replace("\\", "/"),
        "bytes": path.stat().st_size,
        "data_rows": csv_data_rows(path),
        "sha256": sha256_file(path),
    }


def output_file_metadata(path: Path, canonical_path: Path) -> dict[str, object]:
    return {
        "path": str(canonical_path.relative_to(REPO_ROOT)).replace("\\", "/"),
        "bytes": path.stat().st_size,
        "data_rows": csv_data_rows(path),
        "sha256": sha256_file(path),
    }


def write_corrected_condition_details(
    path: Path, corrected_rows: list[dict[str, str]], suite: Suite
) -> None:
    source_fields = list(corrected_rows[0])
    fields = ["suite", "canonical_stage", "canonical_environment", "canonical_comm_label",
              "canonical_comm_level", "canonical_out_dir", *source_fields]
    with path.open("w", newline="", encoding="utf-8") as destination:
        writer = csv.DictWriter(destination, fieldnames=fields)
        writer.writeheader()
        for row in corrected_rows:
            writer.writerow(
                {
                    "suite": suite.key,
                    "canonical_stage": suite.stage,
                    "canonical_environment": suite.environment,
                    "canonical_comm_label": communication_label(row),
                    "canonical_comm_level": compact_float(
                        row["comm_level_stationary_delivery"]
                    ),
                    "canonical_out_dir": relative_run_path(row["out_dir"]),
                    **row,
                }
            )


def archive_candidates(suite: Suite) -> list[Path]:
    names = {"condition_manifest.csv"}
    names.update(data.main_name for data in suite.data_files)
    if suite.target_parts:
        names.add("target_performance_parts_manifest.csv")
        names.update(path.name for path in target_part_paths(suite.main_dir))
    paths = [suite.main_dir / name for name in sorted(names)]
    missing = [path for path in paths if not path.is_file()]
    if missing:
        raise RuntimeError(f"{suite.key}: missing canonical files: {missing}")
    return paths


def stage_suite(
    suite: Suite, staging_dir: Path, archive_tag: str
) -> tuple[dict[str, object], list[Path]]:
    corrected_rows, manifest_by_condition = load_corrected_manifest(suite)
    suite_stage = staging_dir / suite.main_dir.name
    suite_stage.mkdir(parents=True)
    old_paths = archive_candidates(suite)
    archive_dir = suite.main_dir / "archive" / archive_tag
    if archive_dir.exists():
        raise RuntimeError(f"Archive already exists: {archive_dir}")

    manifest_counts = write_replaced_manifest(
        suite.main_dir / "condition_manifest.csv",
        corrected_rows,
        suite_stage / "condition_manifest.csv",
        suite,
    )
    file_counts: dict[str, dict[str, int]] = {"condition_manifest.csv": manifest_counts}

    for data_file in suite.data_files:
        old_path = suite.main_dir / data_file.main_name
        corrected_path = suite.corrected_dir / data_file.corrected_name
        output_path = suite_stage / data_file.main_name
        file_counts[data_file.main_name] = write_replaced_csv(
            old_path, corrected_path, output_path, suite, manifest_by_condition
        )

    if suite.target_parts:
        file_counts["target_performance_parts"] = write_replaced_target_parts(
            suite, suite_stage, manifest_by_condition
        )

    validation: dict[str, dict[str, int]] = {}
    for data_file in suite.data_files:
        path = suite_stage / data_file.main_name
        validation[data_file.main_name] = validate_corrected_rows(
            [path], suite, manifest_by_condition, data_file.multiplier
        )
        old_digest, old_count = canonical_non_ge_digest(
            [suite.main_dir / data_file.main_name], read_header(suite.main_dir / data_file.main_name)
        )
        new_digest, new_count = canonical_non_ge_digest([path], read_header(path))
        if (old_digest, old_count) != (new_digest, new_count):
            raise RuntimeError(f"{suite.key}: non-GE preservation failed for {data_file.main_name}")
        validation[data_file.main_name].update(
            {
                "non_ge_rows": old_count,
                "non_ge_sha256": old_digest,
            }
        )

    if suite.target_parts:
        old_target_parts = target_part_paths(suite.main_dir)
        new_target_parts = target_part_paths(suite_stage)
        validation["target_performance_parts"] = validate_corrected_rows(
            new_target_parts, suite, manifest_by_condition, 10
        )
        fields = read_header(old_target_parts[0])
        old_digest, old_count = canonical_non_ge_digest(old_target_parts, fields)
        new_digest, new_count = canonical_non_ge_digest(new_target_parts, fields)
        if (old_digest, old_count) != (new_digest, new_count):
            raise RuntimeError(f"{suite.key}: non-GE preservation failed for target parts")
        validation["target_performance_parts"].update(
            {"non_ge_rows": old_count, "non_ge_sha256": old_digest}
        )

    manifest_fields = read_header(suite.main_dir / "condition_manifest.csv")
    old_manifest_digest, old_manifest_count = canonical_non_ge_digest(
        [suite.main_dir / "condition_manifest.csv"], manifest_fields
    )
    new_manifest_digest, new_manifest_count = canonical_non_ge_digest(
        [suite_stage / "condition_manifest.csv"], manifest_fields
    )
    if (old_manifest_digest, old_manifest_count) != (
        new_manifest_digest,
        new_manifest_count,
    ):
        raise RuntimeError(f"{suite.key}: non-GE manifest preservation failed")
    validation["condition_manifest.csv"] = {
        "non_ge_rows": old_manifest_count,
        "non_ge_sha256": old_manifest_digest,
        "corrected_ge_rows": EXPECTED_CONDITIONS,
    }

    details_path = suite_stage / "corrected_ge_condition_manifest.csv"
    write_corrected_condition_details(details_path, corrected_rows, suite)

    archive_metadata = [
        archive_file_metadata(path, suite, archive_dir) for path in old_paths
    ]
    staged_csvs = sorted(suite_stage.glob("*.csv"))
    output_metadata = [
        output_file_metadata(path, suite.main_dir / path.name) for path in staged_csvs
    ]
    report: dict[str, object] = {
        "schema_version": 1,
        "suite": suite.key,
        "suite_label": suite.label,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "operation": "Archived the prior combined files and replaced only gilbert_elliot rows.",
        "archive_tag": archive_tag,
        "corrected_source": str(suite.corrected_dir.relative_to(REPO_ROOT)).replace("\\", "/"),
        "coverage_touched": False,
        "file_counts": file_counts,
        "validation": validation,
        "archived_files": archive_metadata,
        "new_csv_files": output_metadata,
    }
    report_path = suite_stage / "GE_REPLACEMENT_REPORT.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    readme = (
        f"# {suite.label.title()} Combined Results\n\n"
        f"The canonical combined CSVs in this directory contain the original ideal, "
        f"Bernoulli, and Rayleigh rows plus the corrected bursty Gilbert-Elliott "
        f"(rho = 0.8) rows completed in July 2026.\n\n"
        f"The exact pre-replacement combined files are preserved under "
        f"`archive/{archive_tag}/`. `GE_REPLACEMENT_REPORT.json` records row counts, "
        f"hashes, and validation results. `corrected_ge_condition_manifest.csv` "
        f"preserves the GE transition parameters and source commands.\n\n"
        f"Coverage results were not read or changed by this replacement.\n"
    )
    (suite_stage / "README.md").write_text(readme, encoding="utf-8")
    return report, old_paths


def commit_suite(
    suite: Suite,
    staging_dir: Path,
    archive_tag: str,
    report: dict[str, object],
    old_paths: list[Path],
) -> None:
    archive_dir = suite.main_dir / "archive" / archive_tag
    archive_dir.mkdir(parents=True)
    archive_manifest = {
        "schema_version": 1,
        "suite": suite.key,
        "archive_tag": archive_tag,
        "created_utc": report["created_utc"],
        "reason": "Pre-corrected-GE snapshot; files are preserved byte-for-byte.",
        "files": report["archived_files"],
    }
    (archive_dir / "ARCHIVE_MANIFEST.json").write_text(
        json.dumps(archive_manifest, indent=2) + "\n", encoding="utf-8"
    )
    (archive_dir / "README.md").write_text(
        f"# Pre-corrected-GE archive\n\n"
        f"These are the exact combined {suite.label} files that were current before "
        f"the corrected bursty Gilbert-Elliott rows were installed. Do not edit "
        f"these archived CSVs. Verify them with `ARCHIVE_MANIFEST.json`.\n",
        encoding="utf-8",
    )
    for source in old_paths:
        source.replace(archive_dir / source.name)

    suite_stage = staging_dir / suite.main_dir.name
    for source in sorted(suite_stage.iterdir()):
        source.replace(suite.main_dir / source.name)
    suite_stage.rmdir()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--archive-tag",
        default="pre_corrected_ge_20260727",
        help="Name of the archive subdirectory created under each combined suite.",
    )
    args = parser.parse_args()
    if "/" in args.archive_tag or "\\" in args.archive_tag:
        raise RuntimeError("Archive tag must be a single directory name")

    staging_dir = REPO_ROOT / f".ge_replacement_staging_{args.archive_tag}"
    if staging_dir.exists():
        raise RuntimeError(f"Staging directory already exists: {staging_dir}")
    staging_dir.mkdir()

    staged: list[tuple[Suite, dict[str, object], list[Path]]] = []
    try:
        for suite in SUITES:
            report, old_paths = stage_suite(suite, staging_dir, args.archive_tag)
            staged.append((suite, report, old_paths))
            print(f"[VALIDATED] {suite.key}: staged replacement is complete")
        for suite, report, old_paths in staged:
            commit_suite(suite, staging_dir, args.archive_tag, report, old_paths)
            print(f"[INSTALLED] {suite.key}: archived originals and installed corrected GE")
        staging_dir.rmdir()
    except Exception:
        print(f"[PRESERVED] Staging data remains at {staging_dir}")
        raise

    print("[DONE] Clue and known-target GE rows replaced; coverage was not touched")


if __name__ == "__main__":
    main()
