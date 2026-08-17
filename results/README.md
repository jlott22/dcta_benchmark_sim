# Result datasets

Each study directory contains its canonical, evaluation-ready files in `combined/`. Raw CSV values are retained unchanged; analysis outputs live only in `analysis/`.

## Core experiments

| Directory | Mission | System rows |
| --- | --- | ---: |
| `clue_search_core_500` | CLIPS | 75,000 |
| `coverage_core_100` | FGS | 15,000 |
| `known_target_visit_core_500` | CV | 75,000 |

The CLIPS and CV core campaigns contain 500 trials per algorithm/communication condition. The FGS campaign contains 100. The corrected bursty Gilbert–Elliott FGS subset is part of the active combined data.

The CV core `target_performance_part_001.csv` through `target_performance_part_006.csv` files are the canonical shards of one large target-level table, not abandoned partial runs. Their active manifest is stored beside them.

## Sensitivity experiments

| Directory | Purpose | System rows |
| --- | --- | ---: |
| `sensitivity_clue_search_grid_density_50` | CLIPS grid and robot density | 9,600 |
| `sensitivity_known_target_visit_grid_density_50` | CV grid and robot density | 9,600 |
| `sensitivity_coverage_grid_density_50` | FGS grid and robot density | 9,600 |
| `sensitivity_clue_search_horizon_300` | CLIPS commitment horizon | 18,000 |
| `sensitivity_known_target_visit_horizon_300` | CV commitment horizon | 18,000 |
| `sensitivity_coverage_horizon_50` | FGS commitment horizon | 3,000 |
| `sensitivity_clue_search_topk_300` | CLIPS candidate-set size | 21,600 |
| `sensitivity_known_target_visit_topk_300` | CV candidate-set size | 21,600 |
| `sensitivity_known_target_visit_dga_iteration_300` | CV DGA generation count | 3,600 |

The paper's grid/density analysis uses the raw CLIPS and CV `system_performance.csv` files in their respective `combined/` directories and applies common-six block eligibility in the analysis layer. Failures remain in the raw and derived status/failure summaries.

## Provenance

`RELEASE_MANIFEST.csv` records repository-relative paths, sizes, row counts, and SHA-256 hashes for released result and figure artifacts. Historical absolute paths inside raw provenance columns document the original execution environment and do not need to exist on a reader's machine.

See `analysis/README.md` for the retained calculation pipeline.
