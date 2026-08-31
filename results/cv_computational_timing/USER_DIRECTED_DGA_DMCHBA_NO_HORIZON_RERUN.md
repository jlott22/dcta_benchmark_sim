# User-directed DGA/DMCHBA no-horizon rerun

## Authority and scope

On 2026-08-31, the user explicitly directed that the isolated timing-study DGA and DMCHBA data be removed and rerun without a commitment horizon. This applies only to `results/cv_computational_timing/`; canonical CV core, grid/density, scenario, and source data are not changed.

## Change

`tools/cv_computational_timing.py` now uses two study-local wrappers:

- `NoHorizonDMCHBAAllocator`
- `NoHorizonDGAAllocator`

Both replace the production fixed cap with the number of currently active tasks, so no fixed commitment horizon truncates the allocation path. DGA retains its production 25 iterations per trigger. The generic `SimConfig.commitment_horizon` remains unset for both algorithms.

## Data handling and execution order

The completed CBAA, ACBBA, PI, and HIPC timing records remain active. All prior DGA/DMCHBA timing raw files, warmups, logs, combined tables, and derived analysis files were quarantined from the active study tree at `quarantine_native_horizon_dga_dmchba_20260831T213002Z/` before replacement runs began. They are retained solely for auditability and are not combined with no-horizon results.

The replacement DGA/DMCHBA campaign reuses the immutable paired scenario and job manifests. It reruns every DGA/DMCHBA measured job: 800 first-invocation jobs and 450 full-mission jobs, 1,250 total. Lower-load jobs run before any 50-target job, and each 50-target child retains the 20-minute timeout rule.
