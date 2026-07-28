# Corrected-GE Coverage Campaign Handoff

This directory is the authoritative checkpoint for the 100-trial-per-condition
corrected Gilbert–Elliott coverage campaign. It is self-contained and intended
to be cloned from GitHub onto the destination computer.

## Transfer checkpoint

Packed on 2026-07-27 after the source computer shut down unexpectedly. No
validated trial data was lost.

| Algorithm | Recorded | Completed | Failed | Missing |
|---|---:|---:|---:|---:|
| ACBBA | 800 | 790 | 10 | 0 |
| CBAA | 800 | 699 | 101 | 0 |
| HIPC | 800 | 748 | 52 | 0 |
| PI | 800 | 665 | 135 | 0 |
| DMCHBA | 522 | 515 | 7 | 278 |
| DGA | 94 | 91 | 3 | 706 |
| **Total** | **3,816** | **3,508** | **308** | **984** |

The shard archive contains 986 validated trial outputs. Of those, 69 are
unmerged DGA missing-stage results: 63 completed and 6 failed. They reduce the
actual remaining computation from 984 to **915 trials** (637 DGA and 278
DMCHBA) in the missing stage. Ten older DGA/DMCHBA failures are queued for a
separate 50,000-event retry afterward. The other shard outputs preserve the
full retry history.

The 298 ACBBA/CBAA/HIPC/PI failures are final outcomes after remaining
incomplete through both 75,000 and 100,000 scheduler events. Do not retry or
replace them. See
[`docs/GE_FAILURE_INTERPRETATION.md`](docs/GE_FAILURE_INTERPRETATION.md) for
the evidence and recommended reporting language.

## Directory layout

```text
coverage_core_100_ge_bursty_rho08/
  README.md
  condition_manifest.csv
  TRANSFER_MANIFEST.json
  TRANSFER_STATUS.json
  TRANSFER_CHECKSUMS.sha256
  raw/                         canonical per-condition CSV checkpoints
  runtime/legacy_ge_20260723/ frozen simulator used by every resumed trial
  artifacts/
    ARTIFACT_MANIFEST.json
    validated_shards.zip       all 986 validated shard outputs
    historical_logs.zip        launch, retry, monitor, and state history
  docs/
    GE_FAILURE_INTERPRETATION.md
```

There are deliberately no extracted shard directories in the Git checkout.
The transfer utility restores them only when a resume is requested. The
working shard directory is ignored by Git and is recoverable from
`validated_shards.zip`.

Only the 12 paused, incomplete DGA worker directories were discarded. They
lacked `worker_result.json` and therefore contained no accepted trial output.
All canonical rows and every shard with validated output were preserved.

## Clone and verify on the destination computer

Use Python 3.10 or newer. Headless trials require no third-party Python
packages.

```powershell
git clone https://github.com/jlott22/dcta_benchmark_sim.git
Set-Location dcta_benchmark_sim
python analysis/coverage_transfer.py verify
python analysis/coverage_transfer.py status
```

Verification must report:

- 3,816 canonical recorded trials;
- 3,508 completed and 308 failed canonical rows;
- 984 canonical missing IDs;
- 915 effective missing trials after the 69 reusable shards;
- valid checksums for the canonical CSVs, archives, frozen runtime, manifests,
  and campaign documentation.

Do not run if verification fails.

## Resume safely

Choose a worker count equal to three-quarters of the destination computer's
**physical** cores. For example, use 12 workers on a 16-physical-core system.
First run the command without `--execute`; it verifies and restores the shard
archive and prints the coordinator audit without starting trials:

```powershell
python analysis/coverage_transfer.py resume --workers 12
```

If the audit is correct, start the missing DGA and DMCHBA trials:

```powershell
python analysis/coverage_transfer.py resume --workers 12 --execute
```

The default missing-trial cap is 50,000 scheduler events. The wrapper restricts
the coordinator to DGA and DMCHBA and stops after the missing stage, so the 298
final quick-algorithm failures cannot be retried accidentally. On the original
source computer only, execution also requires the explicit
`--allow-source-machine` override.

The coordinator:

- reuses each validated shard;
- creates isolated output for each remaining ID;
- refuses to overwrite canonical IDs;
- accepts only one trial row, one system row, and four robot rows for an ID;
- merges atomically only after the missing stage finishes.

After the missing stage is merged, dry-run and then execute the follow-up for
the 10 DGA/DMCHBA IDs that were already failed at handoff:

```powershell
python analysis/coverage_transfer.py retry-long --workers 12
python analysis/coverage_transfer.py retry-long --workers 12 --execute
```

This command is restricted to the handoff failure-ID lists and a 50,000-event
cap. It cannot select the 298 finalized quick-algorithm failures, and it does
not select new missing-stage trials that already reached the 50,000-event cap.
If any of the 10 still fail, their validated failed rows remain the final
record.

After a completed run, preserve all new shards and run the packing command
again before another transfer:

```powershell
python analysis/coverage_transfer.py pack
```

## Status, monitoring, and interruption

```powershell
python analysis/coverage_transfer.py status
Get-Process python -ErrorAction SilentlyContinue
Get-Content runs/coverage_core_100_ge_bursty_rho08/transferred_coverage_state.json
```

The state JSON is created during execution and is intentionally treated as
historical/transient state when the checkpoint is repacked.

To pause, stop new scheduling first and allow active child trials to finish.
Before resuming, confirm no worker process remains. A directory without
`worker_result.json` is incomplete and must not be merged; it may be discarded
when deliberately abandoning paused partial work. Rerunning the resume command
reuses all validated outputs.

The transfer checksums describe the packed checkpoint and will naturally stop
matching once new canonical results are merged. Repack after new work to
create a new verified checkpoint.

## Final acceptance

When the campaign is finished, every one of the 48 conditions must contain
trial IDs 0–99 exactly once in both trial and system data, with four robot rows
per ID. Then run:

```powershell
python analysis/combine_core_ge_bursty.py --suite coverage
```

The final combined outputs must contain 4,800 trial rows, 4,800 system rows,
and 19,200 robot rows. Terminal 100,000-event failures remain failed rows; they
are not missing trials.

## GitHub publication scope

The worktree may contain unrelated research changes. Commit this handoff with
an explicit path list instead of staging the entire repository:

```powershell
git add -- `
  .gitattributes `
  .gitignore `
  CURRENT_STATE.md `
  README.md `
  analysis/coverage_transfer.py `
  analysis/prepare_coverage_transfer.py `
  analysis/resume_coverage_sharded.py `
  analysis/run_snapshot_coverage_trial.py `
  analysis/combine_core_ge_bursty.py `
  runs/coverage_core_100_ge_bursty_rho08
git diff --cached --stat
```

Review the staged diff, then commit and push through the normal project
workflow. Do not use `git add .` in a dirty research worktree.
