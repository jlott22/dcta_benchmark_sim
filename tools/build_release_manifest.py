#!/usr/bin/env python3
"""Create the portable SHA-256 inventory for the public repository tree."""
from __future__ import annotations

import csv
import hashlib
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
OUTPUT = REPO_ROOT / "results" / "RELEASE_MANIFEST.csv"
EXCLUDED_PARTS = {".git", "archive_private", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache"}
EXCLUDED_SUFFIXES = {".pyc", ".pyo", ".asv", ".tmp", ".temp"}


def include(path: Path) -> bool:
    relative = path.relative_to(REPO_ROOT)
    if relative.as_posix() == "archive_private/README.md":
        return path.is_file()
    return (
        path.is_file()
        and path != OUTPUT
        and not any(part in EXCLUDED_PARTS for part in relative.parts)
        and path.suffix.lower() not in EXCLUDED_SUFFIXES
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def csv_rows(path: Path) -> int | str:
    if path.suffix.lower() != ".csv":
        return ""
    with path.open("rb") as handle:
        return max(0, sum(chunk.count(b"\n") for chunk in iter(lambda: handle.read(1024 * 1024), b"")) - 1)


def category(relative: Path) -> str:
    parts = relative.parts
    if parts[0] == "scenarios":
        return "scenario"
    if parts[0] == "results" and len(parts) > 2 and parts[1] != "analysis" and parts[2] == "combined":
        return "canonical_result"
    if parts[:3] == ("results", "analysis", "tables"):
        return "derived_table"
    if parts[:3] == ("results", "analysis", "figures"):
        return "final_figure"
    if relative.suffix.lower() in {".py", ".m", ".sh"}:
        return "code"
    if relative.suffix.lower() in {".md", ".tex", ".cff"}:
        return "documentation"
    return "repository_support"


def main() -> None:
    rows = []
    for path in sorted((path for path in REPO_ROOT.rglob("*") if include(path)), key=lambda item: item.as_posix().lower()):
        relative = path.relative_to(REPO_ROOT)
        rows.append(
            {
                "category": category(relative),
                "repository_path": relative.as_posix(),
                "bytes": path.stat().st_size,
                "data_rows": csv_rows(path),
                "sha256": sha256(path),
            }
        )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["category", "repository_path", "bytes", "data_rows", "sha256"],
        )
        writer.writeheader()
        writer.writerows(rows)

    total_bytes = sum(row["bytes"] for row in rows)
    print(f"Wrote {OUTPUT.relative_to(REPO_ROOT).as_posix()}: {len(rows)} files, {total_bytes} bytes")


if __name__ == "__main__":
    main()
