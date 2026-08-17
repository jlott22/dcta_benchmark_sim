# Reproducing the paper analysis

Run all commands from the repository root. The pipeline treats files under each study's `combined/` directory as read-only inputs and writes derived outputs only under `results/analysis/`.

## Software

- Python 3.10 or newer with the packages in `requirements.txt`
- MATLAB R2025b (recommended)
- MATLAB Statistics and Machine Learning Toolbox
- Git LFS for the two large canonical robot-performance CSVs

## Analysis order

```bash
matlab -batch "addpath('results/analysis'); build_dcta_paired_metric_results"
python results/analysis/run_publication_analysis.py
matlab -batch "addpath('results/analysis'); analyze_grid_density_sensitivity; recompute_grid_density_complete_blocks; analyze_event_caps; analyze_horizon_sensitivity_paper_figures; analyze_known_target_visit_dga_iteration_sensitivity; export_clips_revisit_rate_tables; analyze_results_section_aux; generate_final_paper_figures_CLIPS_CV"
```

The last MATLAB command produces exactly five active PNG figures, five editable `.fig` files, five inspection PNGs, and one dedicated source CSV per figure.

## Continuous-outcome eligibility

Core CLIPS and CV analyses retain completed missions with finite positive maximum-agent steps and their mission-specific completion requirements. Communication-trajectory PRDS and PRDA calculations use a common-six trajectory: a trial/model trajectory is eligible only if all six algorithms are valid at all nine communication levels.

Grid/density continuous outcomes use a common six-algorithm trial block. Within every mission, grid, nominal cells-per-robot level, communication setting, and trial ID, all six algorithms must have completed and have finite maximum-agent steps. If one algorithm is invalid, the entire block is excluded from every algorithm's continuous summaries and comparisons. Failed rows remain in the trial-status and failure summaries.

CLIPS revisit rate is calculated per trial as total team cell revisits divided by total team steps. Trial-level and condition-level results are written to:

- `results/analysis/tables/clips_system_cell_revisit_rate_trial_values.csv`
- `results/analysis/tables/clips_system_cell_revisit_rate_condition_summary.csv`

## Recorded validation checks

The generated tables must reproduce these checks:

| Check | Expected value |
| --- | --- |
| CLIPS grid/density common-six blocks | 1,560 of 1,600 |
| CV grid/density common-six blocks | 1,544 of 1,600 |
| CLIPS leaders across 32 conditions | DMCHBA 11; ACBBA 10 |
| CLIPS mean rank / mean gap | DMCHBA 2.84 / 4.96%; ACBBA 2.34 / 6.05% |
| CV leaders across 32 conditions | DGA 17; DMCHBA 14; CBAA 1 |
| CV mean rank / mean gap | DGA 1.69 / 1.18%; DMCHBA 1.69 / 1.34% |
| CLIPS 34-by-34 means | CBAA 55.93; ACBBA 53.89; PI 57.21; HIPC 55.88; DMCHBA 54.41; DGA 61.33 |
| Grid/density terminal failures | 164 total: 155 event-cap and 9 CV stagnation; 152 total at 34-by-34 |
| Common-six PRDS trajectories | CLIPS 383 per model/algorithm; CV 500 per model/algorithm |
| CV DGA generation selection | k=25; mean normalized regret 0.554871% |
| CV DGA selected means | 21.8667 ideal; 23.1833 under Bernoulli loss p_d=0.25 |

Machine-readable copies of these checks are in `results/analysis/tables/paper_results_verification.csv`; pipeline-specific validation logs provide row counts and additional assertions.

## Final figure map

| Paper figure | File |
| --- | --- |
| Figure 1 | `primary_mission_performance_curves.png` |
| Figure 2 | `communication_performance_tradeoff.png` |
| Figure 3 | `prds_supplement.png` |
| Figure 4 | `grid_density_maximum_agent_steps_summary.png` |
| Figure 5 | `horizon_tuning.png` |

The PNGs are in `results/analysis/figures/`; editable versions are in its `inspection/` subdirectory. Do not use material in `archive_private/` as an analysis input.
