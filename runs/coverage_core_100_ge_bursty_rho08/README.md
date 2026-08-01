# Final Corrected-GE Coverage Dataset

This directory is the final evaluation-ready dataset for the corrected
Gilbert-Elliott coverage campaign with 100 trials per condition.

The campaign is complete as of 2026-08-01. All 48 algorithm/communication
conditions contain trial IDs 0-99 exactly once.

## Contents

- `raw/`: canonical per-condition CSV results.
- `combined/`: evaluation-ready combined CSVs and final validation metadata.
- `condition_manifest.csv`: condition definitions with repo-relative output
  paths.
- `artifacts/ge_coverage_final_provenance_20260801.zip`: compact provenance
  archive for the temporary distributed run and historical handoff material.
- `docs/GE_FAILURE_INTERPRETATION.md`: interpretation notes for terminal
  cap failures.

Temporary runner scripts, live worker folders, runtime snapshots, transfer
state, PID files, logs, and raw backup folders were removed from the live repo
tree after provenance was archived.

## Final Counts

| Dataset | Rows |
|---|---:|
| `combined/trial_summary.csv` | 4,800 |
| `combined/system_performance.csv` | 4,800 |
| `combined/robot_performance.csv` | 19,200 |
| Conditions | 48 |
| Trials per condition | 100 |

Final trial status counts:

| Status | Trials |
|---|---:|
| Completed | 4,376 |
| Failed | 424 |

The final distributed pass added 675 previously missing DGA/DMCHBA trials:
616 completed and 59 failed at the 10,000-event safety cap. A cap hit is a
final failed trial, not a retry candidate.

## Validation

The final validation report is stored at
`combined/FINAL_VALIDATION_REPORT.json`. The merge verified:

- all 675 expected thumb-drive worker results were present and valid;
- no duplicate or unexpected worker trial keys existed;
- every final condition has exactly 100 trial rows;
- every final trial has one system row and four robot rows;
- no final trial IDs are missing.

The final metadata file is `combined/FINAL_DATASET_METADATA.json`.

## Provenance

The provenance archive contains:

- the temporary 15-worker queue manifest and runner scripts;
- worker result manifests, worker states, and per-trial `worker_result.json`
  files from the thumb drive;
- the final validation report;
- the previous transfer manifests/checksums;
- historical shard and log archives from the handoff workflow.

The final live tree intentionally keeps only canonical results, concise
metadata, docs, and that single archive.
