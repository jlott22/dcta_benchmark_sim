# CV Manuscript Discrepancies

## Scope limitation

No manuscript PDF, DOCX, or full TEX source was supplied or found in this repository. This report therefore compares the repository's recorded pre-/post-integration claim audit, `results/analysis/PAPER_VALUE_REPLACEMENTS_AFTER_GRID_INTEGRATION.md`, with active CV analysis tables. It is ready to be reconciled to manuscript page/table/figure identifiers once the manuscript is provided. The manuscript itself was not edited.

## Material replacements

| Affected location | Old value | Corrected value | Active source | Interpretation |
| --- | ---: | ---: | --- | --- |
| Section VI-C, common-six blocks | 1,544 / 1,600 | 1,592 / 1,600 | `grid_density_complete_block_eligibility_counts.csv` | More usable paired scale blocks; conclusion remains supported. |
| Section VI-C, CV noncompletions | 64 | 9 | `grid_density_complete_block_trial_status_summary.csv` | Material correction to reliability accounting. |
| Table IV, ACBBA/PI/HIPC setting | 3 / 5 / 8 | 2 / 2 / 2 | `reruns/analysis/final_tuning_values.csv` | Parameter table must be corrected; see no-horizon caveat below. |
| Section VII-A, ACBBA/HIPC/PI max steps | 29.11 / 32.30 / 34.86 | 26.91 / 25.12 / 29.05 | `results_section_aux/core_primary_max_steps_summary.csv` | HIPC improves materially. |
| Section VII-A, first-place counts DGA/DMCHBA/HIPC | 20 / 4 / 0 | 18 / 2 / 4 | `grid_density_complete_block_algorithm_summary.csv` | HIPC becomes competitive; DGA remains most consistent. |
| Section VII-A, top-two counts DGA/DMCHBA/HIPC | 24 / 24 / 0 | 21 / 19 / 8 | `grid_density_complete_block_algorithm_summary.csv` | Same qualitative change. |
| Section VII-A, DGA-vs-DMCHBA Holm split | 13 / 2 / 9 | 12 / 0 / 12 | `grid_density_complete_block_continuous_comparisons.csv` | Distinction is less favorable to a DGA-only claim. |
| Section VII-B, HIPC team steps | 68.94 | 79.48 | `secondary_metric_summary.csv` | Workload/efficiency statement must be revised. |
| Section VII-B, HIPC unique-cell / target-completion Gini | .348 / .438 | .134 / .267 | `secondary_metric_summary.csv` | Material distribution change. |
| Section VII-B, HIPC duplicate visits | 1.31 | 1.35 | `secondary_metric_summary.csv` | Minor numerical change. |
| Section VII-C, messages per completed target PI/HIPC/ACBBA | 2.88 / 2.93 / 4.28 | 2.48 / 2.61 / 3.71 | `secondary_metric_summary.csv` | Numerical update; relative communication discussion should be checked. |
| Section VII-D, HIPC PRDS | -.106 / -.027 / -.181 | .166 / .281 / .161 | `revised_prds.csv`, `figure_prds_supplement_source.csv` | Material: remove the claim that degradation improves HIPC; it now degrades positively, albeit comparatively mildly. |
| Section VII-D, CV Spearman values | .429 / .086 / .029 | .543 / .086 / -.086 | `revised_prds.csv` | Numerical and directionality correction. |
| Section VII-E, DGA rank/gap | 1.69 / 1.18% | 1.77 / 1.19% | `grid_density_complete_block_algorithm_summary.csv` | Small numerical change; DGA remains a leader. |
| Section VII-E, DMCHBA rank/gap | 1.69 / 1.34% | 1.72 / 1.34% | `grid_density_complete_block_algorithm_summary.csv` | Small numerical change; DMCHBA remains a leader. |
| Scale density omnibus support | 42 / 48 | 44 / 48 | `grid_density_complete_block_continuous_comparisons.csv` | Strengthens coverage, not headline order. |
| PI fewer-robot contrasts | 38 / 48 | 45 / 48 | `grid_density_complete_block_continuous_comparisons.csv` | Material direction/support update. |
| HIPC density direction | 0 fewer / 14 more | 11 fewer / 3 more | `scale_density_direction_summary.csv` | Material directional reversal. |
| ACBBA placement | fourth | fifth | `grid_density_complete_block_algorithm_summary.csv` | Ranking text must be updated. |

## Provenance and figure issues

- The historic `corrected_main_benchmark_horizons.csv` and older horizon figure script contain superseded settings and must not be used as the timing-study configuration source.
- `PAPER_FIGURE_VALIDATION.md` and `paper_figure_source_manifest.csv` predate the current grid integration. Their Figure 4 validation entries do not match the 2026-08-21 grid tables, even though the newer grid figure itself exists. Revalidate Figure 4 in an isolated copy before making an end-to-end figure-provenance claim.
- `REPRODUCIBILITY.md` still states 164 grid/density terminal failures, while the current active analysis identifies 87 total across missions (78 event-cap and 9 CV stagnation). It is stale until reconciled.

## No-horizon caveat

The active CV source and condition manifest label DMCHBA and DGA with historical horizon 3. The settled requirement for the timing study calls for no study-level treatment of that parameter. This report records the source fact as an architecture/data-provenance discrepancy; it does not retroactively change historical datasets or claim that their labels meet the settled timing configuration.

## Final timing-study update

The finished timing campaign adds new implementation-level runtime results; it does not change canonical CV performance values. All 3,750 planned timing jobs completed with zero failures and zero timeouts. At 10 targets, maximum first-invocation time had Friedman chi-square(5) = 470.183, p = 2.17e-99, W = 0.940; cumulative team allocator time had chi-square(5) = 457.377, p = 1.26e-96, W = 0.915. Use `TIMING_FINDINGS.md` and the timing CSV tables for manuscript values.

The DGA/DMCHBA timing records are a user-directed no-horizon rerun and therefore must not be described as identical to the historical active core configuration, which records horizon 3 for both algorithms. This is a disclosed timing-study architecture/configuration difference, not a correction to canonical benchmark outcome data.
