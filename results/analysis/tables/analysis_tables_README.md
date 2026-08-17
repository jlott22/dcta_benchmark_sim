# Derived analysis tables

These files are generated from the canonical combined datasets. Raw inputs are never rewritten.

Key table groups:

- `dcta_metric_*`: master mission metrics, tests, log, and source manifest.
- `publication_*`, `revised_prds.csv`, `revised_prda*.csv`, and `trajectory_*`: publication analysis under the documented eligibility rules.
- `grid_density_complete_block_*`: eligibility counts, retained failures/statuses, condition summaries, algorithm summaries, plotted data, and continuous comparisons for Figure 4.
- `event_cap_*`: terminal-failure classification and cap recommendations.
- `*_horizon_tuning_decision.csv` and `horizon_tuning_paired_trial_delta_summary.csv`: horizon selection inputs and Figure 5 values.
- `dga_iteration_*`: corrected CV DGA-generation condition means, normalized regret, selection, provenance, and validation.
- `clips_system_cell_revisit_rate_*`: per-trial and condition-level CLIPS revisit rates.
- `results_section_aux/`: reconciled descriptive fields used in the results narrative.
- `final_figure_sources/`: exactly five CSVs, one per active paper figure.

Source manifests use repository-relative paths so the release is portable. Raw provenance fields may retain historical machine paths by design.
