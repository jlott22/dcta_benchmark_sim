# Private pre-release archive

This directory holds superseded builds, pre-correction datasets, execution
logs, temporary paper inspections, and other material preserved during the
2026-08-16 public-release cleanup.

Everything below this README is intentionally excluded from Git. The public
repository does not depend on archived files. Canonical data remain under
`results/*/combined/`, final analysis outputs under `results/analysis/tables/`,
and the paper figures under `results/analysis/figures/`.

The cleanup archive contains an `archive_manifest.csv` recording every moved
file's original path, archived path, byte size, SHA-256 digest, and whether the
file was tracked before cleanup.
