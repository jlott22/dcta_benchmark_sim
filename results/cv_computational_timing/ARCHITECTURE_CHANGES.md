# Simulation-Architecture Change Record

## Status

No existing `known_visit_sim`, `benchmark_sim`, scenario, canonical result, or analysis file was changed for this timing study.

The new study is an isolated orchestration layer under `results/cv_computational_timing/` and `tools/cv_computational_timing.py`. It reuses the production CV simulator's existing allocator timer (`RobotShell._choose_goal_with_metrics`) and asynchronous runner (`AsyncTrialRunner`) without inserting measured wall-clock duration into simulated time or event ordering.

## Study-local configuration boundary

The initial timing run used the production implementations and recorded the following source/data discrepancy:

- CBAA remains single-task.
- ACBBA, PI, and HIPC receive the selected bundle setting of two through their own `SimConfig` instances.
- DGA retained its production implementation and its selected 25 iterations; the study passed no generic horizon override to it.
- DMCHBA retained its production implementation; the study passed no generic horizon override to it.

The production DGA and DMCHBA classes internally expose a default value of three, while the historical core commands also supplied a generic value of three. That source/data fact conflicts with the settled timing-study convention that they have no *study-level* bundle-length or commitment-horizon treatment.

## User-directed DGA/DMCHBA no-horizon rerun

On 2026-08-31, the user explicitly instructed that all active timing-study DGA/DMCHBA records be removed from the active study and rerun with no commitment horizon. The isolated runner now uses `NoHorizonDMCHBAAllocator` and `NoHorizonDGAAllocator`, each of which replaces the fixed cap with the current number of active tasks. This is intentionally a timing-study algorithm variant, not a change to `known_visit_sim` or any canonical benchmark dataset. DGA retains `DGA_ITERATIONS_PER_TRIGGER=25`.

All pre-rerun DGA/DMCHBA timing raw files, logs, combined tables, and analysis products are quarantined outside the active raw tree before the rerun. The replacement records include the allocator implementation and planning-horizon policy. This user-directed change supersedes the prior no-override configuration note for these two algorithms only.

## Timing boundary

Experiment 1 invokes each robot once from a fresh, valid initial CV state through `RobotShell.step(0.0, planner)`. The standard intent-settle action ensures the timer records the real allocator call before a move is committed.

Experiment 2 uses normal `AsyncTrialRunner.run_trial` execution. The wall-clock samples remain observational: `perf_counter_ns` affects neither `TrialState.clock_s` nor the event queue. Results report allocator invocation time only, excluding process launch, scenario parsing, setup, file I/O, and movement/path execution.

## Windows worker-launch correction

The isolated runner now starts the background parent without a visible console and configures Windows `multiprocessing` workers to use the installed `pythonw.exe`. This is an orchestration-only presentation change: it does not alter simulator architecture, allocator behavior, timing scope, job manifests, or any canonical data. Each raw job record records the worker launch mode for auditability.
