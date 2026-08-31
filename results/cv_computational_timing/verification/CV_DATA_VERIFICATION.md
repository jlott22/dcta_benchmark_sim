# CV Data Verification

## Result

The active CV core and grid/robot-density datasets are internally consistent with their newer integration manifests. No canonical CSV, scenario, raw output, analysis table, or manuscript file was modified during this verification.

This is a verification of the current working-copy data, not a clean historical release: the worktree was already dirty before work began. `HEAD` and `origin/main` are both `d27fb17a7832374ec791a8efabda303fbdfcb4de`; local `main` remains at the older `749533fee9124942d064656a233b3befb4624467`. The exact file inventory and SHA-256 values are in `CV_AUTHORITATIVE_MANIFEST.json`.

## Authority and corrections

The active sources are determined by content, integration manifests, and replacement provenance—not timestamps.

- Core CV: `results/known_target_visit_core_500/combined/`, governed by `results/CORE_RERUN_INTEGRATION_MANIFEST.json`.
- CV grid/robot-density: `results/sensitivity_known_target_visit_grid_density_50/combined/`, governed by `results/GRID_DENSITY_RERUN_INTEGRATION_MANIFEST.json`.
- Older core material is quarantined under `results/archive/pre_core_rerun_integration_20260820/`; rerun/archive material under `reruns/archive/` is not mixed into active tables.

The active-file hashes match both integration manifests. `results/RELEASE_MANIFEST.csv` predates these local integrations and does not match the nine checked active CV core/grid files; it is therefore stale for current-worktree integrity claims.

The core integration replaces the full CV matrices for PI, ACBBA, and HIPC at the selected bundle setting of two, using `reruns/pi_core_matrix/` and the changed-horizon quarantine reruns. Grid/density integration accounts for later scale reruns and retains terminal failures. The DGA generation-selection source is `results/analysis/tables/dga_iteration_selection.csv`, selecting 25 iterations.

## Core checks

- 75,000 system rows and 75,000 trial rows: 6 algorithms × 25 communication conditions × 500 paired trials.
- 300,000 robot rows and 750,000 target rows stored in six canonical target shards.
- All 75,000 core trials have `trial_status=completed`.
- Every communication condition has exactly the same 500 trial IDs across CBAA, ACBBA, PI, HIPC, DMCHBA, and DGA.
- Active metadata records CBAA=1, ACBBA=2, PI=2, HIPC=2, DMCHBA=3, DGA=3 in the historical `commitment_horizon` column; DGA records 25 iterations.

## Grid/robot-density checks

- 9,600 system rows and 9,600 trial rows; 66,000 robot rows; 96,000 target rows; and 192 algorithm-condition manifest rows.
- The matrix contains grids 14, 19, 25, and 34; nominal cells per robot 50, 85, 140, and 220; ideal and Bernoulli-0.25 communication; six algorithms; and 50 paired trials per algorithm-condition.
- Pairing is exact across all six algorithms within every one of the 32 grid/density/communication blocks.
- 9,591 rows completed and 9 failed. Retained failures are ACBBA=1, DGA_iter_25=1, DMCHBA=2, and HIPC=5, all recorded as stagnation-cap `RuntimeError`s; none was silently replaced.

## Parameter-provenance finding

The active dataset and production source still encode `commitment_horizon=3` for DMCHBA and DGA. This conflicts with the settled timing-study requirement that those algorithms have no study-level bundle-length or commitment-horizon treatment. That conflict is a provenance/architecture discrepancy, not a reason to alter historical data. The new isolated timing study leaves the generic setting unset for those unchanged production allocators and does not overwrite or relabel the canonical outputs.

## Analysis regeneration boundary

The MATLAB/Python publication scripts write existing `results/analysis/` tables, figures, and logs, so they were not run in this dirty checkout. Their active outputs were instead read and compared against the integrated authoritative files. A full literal manuscript comparison is blocked because no manuscript PDF/DOCX/TEX was supplied; the provisional discrepancy audit uses `results/analysis/PAPER_VALUE_REPLACEMENTS_AFTER_GRID_INTEGRATION.md` and the cited active table sources. See `CV_MANUSCRIPT_DISCREPANCIES.md`.
