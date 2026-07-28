# Current Simulation Transfer State

Updated: 2026-07-27

The corrected Gilbert–Elliott coverage campaign is stopped and prepared for a
computer transfer. No Python coordinator or coverage worker should be running
on the source computer.

## Authoritative checkpoint

- Campaign: `runs/coverage_core_100_ge_bursty_rho08`
- Conditions: 48
- Trial target: 100 per condition, 4,800 total
- Canonical recorded: 3,816
- Canonical completed: 3,508
- Canonical failed: 308
- Canonical missing: 984
- Reusable unmerged missing-stage shards: 69
- Actual trials still requiring computation: 915
- Next execution: missing DGA and DMCHBA trials only, at a 50,000-event cap
- Queued follow-up: retry the 10 DGA/DMCHBA failures present at handoff, at a
  50,000-event cap
- Quick-algorithm terminal failures: 298, finalized at 100,000 events

The missing-stage computation is 637 DGA trials and 278 DMCHBA trials after
accounting for reusable shard output. The canonical checkpoint also contains
10 earlier DGA/DMCHBA failed rows. They are preserved, excluded from the
missing-stage resume, and selected explicitly by the later `retry-long`
command.

## Transfer package

The campaign directory contains readable canonical CSVs, its own frozen
runtime, checksum manifests, documentation, and two compact archives:

- `artifacts/validated_shards.zip` preserves every accepted shard and all
  retry evidence.
- `artifacts/historical_logs.zip` preserves coordinator logs, PID records,
  monitor output, state snapshots, and retired launcher scripts.

The 12 paused partial DGA directories had no `worker_result.json` and were
intentionally discarded. No accepted result was removed.

See
[`runs/coverage_core_100_ge_bursty_rho08/README.md`](runs/coverage_core_100_ge_bursty_rho08/README.md)
for clone, verification, resume, interruption, and finalization instructions.

## Destination commands

```powershell
git clone https://github.com/jlott22/dcta_benchmark_sim.git
Set-Location dcta_benchmark_sim
python analysis/coverage_transfer.py verify
python analysis/coverage_transfer.py status
python analysis/coverage_transfer.py resume --workers 12
python analysis/coverage_transfer.py resume --workers 12 --execute
python analysis/coverage_transfer.py retry-long --workers 12
python analysis/coverage_transfer.py retry-long --workers 12 --execute
```

Replace 12 with three-quarters of the destination computer's physical cores.
The first resume command is a dry run. Do not execute if verification or the
audit fails.

The transfer has been prepared locally but is not considered available on the
destination until the relevant files are committed and pushed to GitHub.
