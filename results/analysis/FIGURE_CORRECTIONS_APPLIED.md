# `dcta_figure_corrections` implementation record

Source specification: `C:\Users\lottj\Downloads\dcta_figure_corrections.tex`  
Applied: 2026-08-09

| Figure | Requested correction | Implementation |
|---|---|---|
| `fgs_completion_rates_final` | Put the six-way-paired sample under every loss level | Added a second tick-label row: 100, 100, 94, 85, 77, 41, 24, 17 |
| `clips_post_clue_steps_final` | Correct the middle communication-family label | Retained Gilbert--Elliott because the active CLIPS bundle is the restored fixed-rho=0.8 rerun |
| `max_agent_steps_all_missions_final` | Accurate model labels and panel n | Retained Gilbert--Elliott for all missions and retained analytic n annotations |
| `total_team_steps` | Replace obsolete combined placeholder | Regenerated as the separate three-mission uncertainty figure |
| `cv_workload_tradeoff` | Separate workload question | Regenerated as the CV travel/Gini tradeoff |
| `communication_performance_tradeoff_revised` | Make degradation direction unambiguous | Restricted trajectories to 5--70%; open circles mark 5% and arrowheads mark 70% |
| `prda_pairwise_complete_final` | Encode Holm significance and retain n | Filled markers denote Holm-adjusted p<0.05; open markers denote nonsignificance; exact p and n are in `figure_pairwise_prda_source.csv` |
| `prds_supplement` | Accurate mission-specific state-model labels | Retained Gilbert--Elliott because all three active campaigns use the corrected fixed-rho process |
| `horizon_tuning` | Mark selected horizons | Stars mark the mission/algorithm horizons in the manuscript tuning table; the source CSV now records `selected_for_main_benchmark` |
| `DGA_iteration` | Mark k=25 and verify scope | Stars mark k=25. The available sensitivity bundle is CV-only, so captions no longer claim a CLIPS curve |

The specification's warning that only FGS uses fixed-rho Gilbert--Elliott was
written against the displaced pre-correction CLIPS/CV files. The corrected
reruns restored from revision `f898015` make the shared Gilbert--Elliott label
accurate for the current active data.

The current repository does not contain the three optional horizon robust-score
decision CSVs referenced by the MATLAB generator. Selected horizon markers are
therefore sourced from the current manuscript's `Selected planning horizons by
mission` table, not reconstructed robust-score heatmaps.

The prior active figures are archived in
`results/analysis/figures/archive/pre_dcta_figure_corrections_20260809/`.
