# Validated publication figures

This is the authoritative output directory for the revised paper figures.
`generate_publication_figures.py` writes both 600-dpi PNG and vector PDF files;
the MATLAB sensitivity workflows additionally retain editable FIG files.

## Paper-aligned figure inventory

- `fgs_completion_rates_final`: FGS completion probability with 95% Wilson
  intervals under corrected Gilbert--Elliott communication; the second x-axis
  label row gives six-way-paired conditional-efficiency sample sizes.
- `clips_post_clue_steps_final`: CLIPS post-clue team steps with trial-level
  uncertainty and analytic sample sizes.
- `max_agent_steps_all_missions_final`: maximum-agent steps for CLIPS, CV, and
  FGS, separated by communication model.
- `communication_performance_tradeoff_revised`: publication rate versus
  maximum-agent steps using absolute axes; open circles and arrowheads mark
  the 5% and 70% endpoints.
- `prda_pairwise_complete_final`: pairwise-complete PRDA with communication
  models separated; filled/open markers encode Holm significance.
- `horizon_tuning.png/.fig`: commitment-horizon sensitivity for CV, CLIPS,
  and FGS, with the manuscript-selected mission/algorithm horizons starred.
- `DGA_iteration.png/.fig`: DGA generation-count sensitivity for CV. The
  available sensitivity campaign contains no corresponding CLIPS result, so
  the attached paper caption must not claim both missions. The main-benchmark
  value `k=25` is starred explicitly.

## Revised figures requiring a paper-path change

- `total_team_steps`: three-mission total-team-step curves with 95% confidence
  intervals; FGS values are conditional on completion.
- `cv_workload_tradeoff`: the CV HIPC resource-use/workload-imbalance tradeoff.
- `prds_supplement`: algorithm-complete PRDS for supplementary use.

The paper's single `total_steps_workload_tradeoff_final` placeholder does not
match the revised outputs: total-step uncertainty and the CV workload tradeoff
are now separate figures.

## Reproduction and audit

- `../run_publication_analysis.py` rebuilds the revised statistical tables.
- `../generate_publication_figures.py` regenerates the publication PNG/PDF
  figures and `../FIGURE_CAPTIONS.tex`.
- `../analyze_horizon_sensitivity_paper_figures.m` regenerates
  `horizon_tuning.png/.fig`.
- `../analyze_known_target_visit_dga_iteration_sensitivity.m` regenerates
  `DGA_iteration.png/.fig` and its percentage-delta source table.
- `../verify_gilbert_elliott.py` independently validates the stored
  communication-process interpretations.
