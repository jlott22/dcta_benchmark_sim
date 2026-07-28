#!/usr/bin/env python3
"""Split one oversized CSV into validated, GitHub-safe row parts."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def logical_digest(path: Path) -> tuple[str, int, list[str]]:
    digest = hashlib.sha256()
    count = 0
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        fields = list(reader.fieldnames or [])
        for row in reader:
            payload = json.dumps(
                [row.get(field, "") for field in fields],
                ensure_ascii=False,
                separators=(",", ":"),
            )
            digest.update(payload.encode("utf-8"))
            digest.update(b"\n")
            count += 1
    return digest.hexdigest(), count, fields


def relative(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT)).replace("\\", "/")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("--rows-per-part", type=int, default=150_000)
    parser.add_argument("--remove-source", action="store_true")
    parser.add_argument("--report-json", type=Path)
    args = parser.parse_args()

    source = args.input.resolve()
    if not source.is_relative_to(REPO_ROOT):
        raise RuntimeError("Input must be inside the repository")
    if not source.is_file() or source.suffix.lower() != ".csv":
        raise RuntimeError(f"Input CSV does not exist: {source}")
    if args.rows_per_part <= 0:
        raise RuntimeError("--rows-per-part must be positive")

    staging = source.parent / f".split_{source.stem}"
    if staging.exists():
        raise RuntimeError(f"Staging path already exists: {staging}")
    if list(source.parent.glob(f"{source.stem}_part_[0-9][0-9][0-9].csv")):
        raise RuntimeError(f"Part files already exist for {source.name}")
    manifest_path = source.parent / f"{source.stem}_parts_manifest.csv"
    if manifest_path.exists():
        raise RuntimeError(f"Part manifest already exists: {manifest_path}")

    original_digest, original_rows, fields = logical_digest(source)
    if not fields:
        raise RuntimeError("Input CSV has no header")
    staging.mkdir()
    part_metadata: list[dict[str, object]] = []
    try:
        with source.open(newline="", encoding="utf-8-sig") as handle:
            reader = csv.DictReader(handle)
            writer = None
            destination = None
            part_path = None
            part_rows = 0
            total_rows = 0
            part_number = 0
            for row in reader:
                if writer is None or part_rows == args.rows_per_part:
                    if destination is not None:
                        destination.close()
                        part_metadata.append(
                            {
                                "part_file": part_path.name,
                                "data_rows": part_rows,
                                "bytes": part_path.stat().st_size,
                                "sha256": sha256_file(part_path),
                            }
                        )
                    part_number += 1
                    part_path = staging / f"{source.stem}_part_{part_number:03d}.csv"
                    destination = part_path.open("w", newline="", encoding="utf-8")
                    writer = csv.DictWriter(destination, fieldnames=fields)
                    writer.writeheader()
                    part_rows = 0
                writer.writerow({field: row.get(field, "") for field in fields})
                part_rows += 1
                total_rows += 1
            if destination is not None:
                destination.close()
                part_metadata.append(
                    {
                        "part_file": part_path.name,
                        "data_rows": part_rows,
                        "bytes": part_path.stat().st_size,
                        "sha256": sha256_file(part_path),
                    }
                )
        if total_rows != original_rows:
            raise RuntimeError(f"Split row mismatch: {total_rows:,} != {original_rows:,}")

        split_digest = hashlib.sha256()
        split_rows = 0
        for metadata in part_metadata:
            digest, count, part_fields = logical_digest(staging / str(metadata["part_file"]))
            if part_fields != fields:
                raise RuntimeError(f"Part header mismatch: {metadata['part_file']}")
            # Re-read to preserve a single digest across the ordered sequence.
            with (staging / str(metadata["part_file"])).open(
                newline="", encoding="utf-8-sig"
            ) as handle:
                for row in csv.DictReader(handle):
                    payload = json.dumps(
                        [row.get(field, "") for field in fields],
                        ensure_ascii=False,
                        separators=(",", ":"),
                    )
                    split_digest.update(payload.encode("utf-8"))
                    split_digest.update(b"\n")
            split_rows += count
        if split_rows != original_rows or split_digest.hexdigest() != original_digest:
            raise RuntimeError("Ordered split content does not match the source CSV")

        staged_manifest = staging / manifest_path.name
        with staged_manifest.open("w", newline="", encoding="utf-8") as destination:
            writer = csv.DictWriter(
                destination,
                fieldnames=("part_file", "data_rows", "bytes", "sha256"),
            )
            writer.writeheader()
            writer.writerows(part_metadata)

        for metadata in part_metadata:
            part = staging / str(metadata["part_file"])
            part.replace(source.parent / part.name)
        staged_manifest.replace(manifest_path)
        staging.rmdir()

        if args.remove_source:
            source.unlink()

        if args.report_json:
            report_path = args.report_json.resolve()
            report = json.loads(report_path.read_text(encoding="utf-8"))
            source_relative = relative(source)
            report["new_csv_files"] = [
                item
                for item in report.get("new_csv_files", [])
                if item.get("path") != source_relative
            ]
            installed_parts = []
            for metadata in part_metadata:
                installed_path = source.parent / str(metadata["part_file"])
                installed_parts.append(
                    {
                        "path": relative(installed_path),
                        "bytes": installed_path.stat().st_size,
                        "data_rows": metadata["data_rows"],
                        "sha256": sha256_file(installed_path),
                    }
                )
            installed_parts.append(
                {
                    "path": relative(manifest_path),
                    "bytes": manifest_path.stat().st_size,
                    "data_rows": len(part_metadata),
                    "sha256": sha256_file(manifest_path),
                }
            )
            report["new_csv_files"].extend(installed_parts)
            report["post_install_partition"] = {
                "created_utc": datetime.now(timezone.utc).isoformat(),
                "source_path": source_relative,
                "source_removed": args.remove_source,
                "source_data_rows": original_rows,
                "source_logical_sha256": original_digest,
                "rows_per_part": args.rows_per_part,
                "parts": installed_parts[:-1],
                "parts_manifest": relative(manifest_path),
                "ordered_parts_logical_sha256": split_digest.hexdigest(),
            }
            report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

        largest = max(int(item["bytes"]) for item in part_metadata)
        print(
            f"[DONE] {source.name}: {original_rows:,} rows -> "
            f"{len(part_metadata)} parts; largest {largest / (1024 * 1024):.2f} MiB"
        )
    except Exception:
        print(f"[PRESERVED] Split staging remains at {staging}")
        raise


if __name__ == "__main__":
    main()
