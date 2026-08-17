# Publication analysis

This directory contains the retained scripts that reproduce the paper's numerical tables and five final figures. Run them in the order documented in the repository-level `REPRODUCIBILITY.md`.

## Canonical pipeline

| Script | Primary output |
| --- | --- |
| `build_dcta_paired_metric_results.m` | master mission metrics and paired statistical results |
| `run_publication_analysis.py` | publication summaries, common-six PRDS/PRDA, and tests |
| `analyze_grid_density_sensitivity.m` | broad grid/density audit table used by downstream summaries |
| `recompute_grid_density_complete_blocks.m` | corrected common-six grid/density summaries and comparisons |
| `analyze_event_caps.m` | event-cap and terminal-failure audit |
| `analyze_horizon_sensitivity_paper_figures.m` | paired horizon source table using the paper's fixed selections |
| `analyze_known_target_visit_dga_iteration_sensitivity.m` | CV DGA-generation selection using maximum-agent steps |
| `export_clips_revisit_rate_tables.m` | per-trial and condition CLIPS revisit rates |
| `analyze_results_section_aux.m` | reconciled descriptive results used by the results text |
| `generate_final_paper_figures_CLIPS_CV.m` | all five final PNG and editable MATLAB figures |

Styling shared by all figures is defined in `final_figure_style.m` and `apply_publication_figure_typography.m`. Small `regenerate_*.m` helpers rebuild individual finalized figures when only one asset needs to change.

## Outputs

- `tables/` contains final derived CSVs, source manifests, and validation logs.
- `tables/final_figure_sources/` contains exactly one plotted-data CSV per active figure.
- `figures/` contains exactly the five final 600-dpi PNGs.
- `figures/inspection/` contains matching PNGs and editable MATLAB `.fig` files.

Superseded scripts, alternate plots, partial builds, and pre-correction results are preserved locally in the ignored root-level `archive_private/` directory. They are not part of the public analysis pipeline.
