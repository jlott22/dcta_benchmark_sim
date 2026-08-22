# Target-load commitment-horizon pilot (25 paired trials)

This self-contained pilot asks whether the effect of tuning the common
multi-task commitment horizon in the known-target Collaborative Visit mission
changes with target load.  It contrasts new 5- and 20-target conditions with
the first 25 paired trials of the repository's existing 10-target,
300-trial horizon campaign.

The pilot is exploratory: the same 25 scenario realizations define the
response surfaces, choose candidate horizons, and evaluate transfer between
effort- and makespan-based tuning.  Its inferential outputs must therefore be
described as pilot/exploratory rather than held-out confirmatory results.

## Design

| Fixed item | Value |
| --- | --- |
| Mission | Known-target Collaborative Visit |
| Grid / robots / starts | 19 x 19 / 4 / deterministic `edge_even` |
| Algorithms | ACBBA, DGA, DMCHBA, HIPC, PI |
| Horizons | 1, 2, 3, 5, 8, 12 |
| Communication | ideal; Bernoulli independent message loss, `p_drop=0.25` |
| New target loads | 5 and 20 |
| Paired trials per target load | 25 (`trial_id` 0--24) |

There are `2 x 5 x 6 x 2 = 120` conditions and `120 x 25 = 3,000`
algorithm runs.  The 10-target condition is deliberately **not rerun**.
For a self-contained analysis bundle, a read-only duplicate of the exact
10-target reference inputs is stored at:

```text
horizon tuning conference/reference_core_benchmark_pilot/combined/
  sensitivity_known_target_visit_horizon_300_combined_system_performance.csv
  sensitivity_known_target_visit_horizon_300_combined_robot_performance.csv
  sensitivity_known_target_visit_horizon_300_combined_target_performance.csv
```

It retains IDs 0--24 after checking that the duplicated 10-target data are
complete and paired. The canonical source files remain unchanged at
`results/sensitivity_known_target_visit_horizon_300/combined/`.

## Reproducibility and pairing

Exactly one generated scenario file is reused across all 60 conditions at a
given target load:

| Target count | Scenario file | Scenario seed |
| --- | --- | --- |
| 5 | `scenarios/known_visit_g19_t5_n25.csv` | `2026082105` |
| 20 | `scenarios/known_visit_g19_t20_n25.csv` | `2026082120` |

Both seeds are distinct from each other and from the existing 10-target
campaign's seed `0`.  The simulator base seed remains `0`, matching that
campaign, and the existing runner deterministically uses
`0 + trial_id * 1009` for every algorithm/horizon/communication cell.

The wrapper calls the existing `known_visit_sim.run_trials` module directly.
For DGA it uses the recorded `DGAIter25Allocator` wrapper, retaining
population 30, 25 iterations per trigger, mutation 0.3, crossover 0.7,
elite count 2, and unlimited candidates.  It also explicitly passes
`--debug-max-events 5000`: the historic 10-target campaign used the
pre-adaptive 19 x 19 / 4-robot default of 5,000, whereas current HEAD's
automatic default is 10,000.  This deliberate compatibility choice is
recorded in every campaign manifest.

## Run and monitor

Run all commands from the `dcta_benchmark_sim` repository root.  The default
is 12 workers, matching the repository's established safe policy of one
sequential condition runner on three quarters of 16 physical cores.  The
host exposes 22 logical processors, but numerical-library threads are capped
at one in each worker to avoid oversubscription.

Start the actual campaign:

```powershell
python "horizon tuning conference/scripts/run_target_load_horizon_pilot.py" --workers 12
```

Resume after an interruption (the normal start command is already resumable):

```powershell
python "horizon tuning conference/scripts/run_target_load_horizon_pilot.py" --resume --workers 12
```

Check status without starting any process:

```powershell
python "horizon tuning conference/scripts/run_target_load_horizon_pilot.py" --status
```

Rebuild combined files and validation only:

```powershell
python "horizon tuning conference/scripts/run_target_load_horizon_pilot.py" --combine-only
```

The campaign lock prevents a second active launch.  Each condition writes only
inside its own raw output directory.  The underlying simulator records both
completed and failed trial IDs; failed records are retained and skipped on
resume, so no failure is silently replaced with a different seed.  The wrapper
stops only for systemic integrity evidence (for example, malformed output,
wrong load/horizon/communication labels, duplicate IDs, or repeated identical
exceptions), while allowing isolated recorded trial failures to remain visible.

## Folder layout

```text
horizon tuning conference/
  scenarios/                  paired 5- and 20-target inputs
  scripts/                    campaign, combination, and validation runner
  manifests/                  campaign, condition, scenario, and validation records
  logs/                       campaign lock and per-condition logs
  results/raw/targets_5/      one output directory per condition
  results/raw/targets_20/     one output directory per condition
  results/combined/           canonical combined CSV files
  reference_core_benchmark_pilot/
                              duplicated 10-target scenario and combined inputs
  analysis/                   MATLAB pilot analysis
```

At full successful completion, the combined files contain 3,000 trial-summary
rows, 3,000 system-performance rows, 12,000 robot-performance rows, 7,500
five-target rows plus 30,000 twenty-target rows in target performance, and
120 condition-manifest rows.  `manifests/validation_results.csv` and
`manifests/validation_report.txt` record the row, pairing, metadata,
completion, finite-metric, and pre-existing-results integrity checks.

## MATLAB analysis (after campaign completion)

Do not run MATLAB while the simulation is active.  Once the pilot is complete,
run:

```matlab
run(fullfile(pwd, 'horizon tuning conference', 'analysis', ...
    'analyze_target_load_horizon_pilot.m'))
```

The script resolves its own location, so it can also be invoked from another
working directory with its absolute path.  It writes all tables, PNGs, and
editable `.fig` figures below this experiment folder only.
