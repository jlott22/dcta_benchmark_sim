# Analysis and Paper Update Report

Generated: 2026-08-09  
Repository: `dcta_benchmark_sim`  
Analysis scope: current combined results; corrected CLIPS/CV GE reruns restored from Git revision `f898015`; displaced legacy files archived; no benchmark simulations newly executed.

## 1. Executive summary

The analysis and figure update is complete and reproducible from the current scenario-prefixed combined CSVs.

- Full Grid Search (FGS) has 424 recorded failures among 4,800 corrected Gilbert–Elliott (GE) algorithm runs (8.83%). All are `RuntimeError` scheduler-event safety-cap terminations. FGS Ideal, Bernoulli, and Rayleigh-style conditions have no failures.
- Clue-Informed Probabilistic Search (CLIPS) and Collaborative Visit (CV) each have 0 failures among 24,000 GE runs.
- FGS GE failures increase sharply after 40% nominal loss: 0, 0, 6, 16, 27, 74, 133, and 168 failures among 600 algorithm runs at 5–70% loss. The corresponding six-algorithm complete paired trial counts are 100, 100, 94, 85, 77, 41, 24, and 17.
- The revised degradation analysis no longer requires all six algorithms for every trajectory. For FGS GE maximum-agent steps, the legacy six-way rule retained only 3 trials. Revised PRDS retains 20–90 trials per algorithm, and revised PRDA retains 7–57 trials per algorithm pair.
- The main robustness figure now presents pairwise-complete PRDA by mission and communication model. PRDS remains a model-separated supplementary figure.
- The active GE campaigns for CLIPS, CV, and FGS all use the corrected fixed-correlation process with lag-one state correlation 0.8. Corrected CLIPS/CV reruns were recovered from revision `f898015`; the repository relayout had displaced them with the pre-correction files.
- The uploaded revised MATLAB horizon generator was promoted to the canonical filename, its current input paths were repaired, and the superseded generator was archived. The baseline calculation was not changed.

The primary paper interpretation should be two-part: mission-completion probability first, followed by efficiency conditional on successful completion. No failed trial was assigned a large step penalty.

## 2. Files/data sources used

The authoritative data-source inventory, row counts, timestamps, sizes, and SHA-256 hashes are in:

- `results/analysis/tables/publication_analysis_source_manifest.csv`

Primary current result sets:

| Mission | Current result folder | Primary tables |
|---|---|---|
| Clue-Informed Probabilistic Search (CLIPS) | `results/clue_search_core_500/combined` | scenario-prefixed system performance, trial summary, and condition manifest |
| Collaborative Visit (CV) | `results/known_target_visit_core_500/combined` | scenario-prefixed system performance, trial summary, robot performance, and condition manifest |
| Full Grid Search (FGS) | `results/coverage_core_100/combined` | scenario-prefixed system performance, trial summary, and condition manifest |

The CV robot table was loaded to derive maximum-agent publications because the CV system table does not contain that maximum. The CLIPS and FGS robot tables were hashed and documented but were not needed because their system tables already contain the required maximum-agent fields.

Horizon figure sources:

- `results/sensitivity_known_target_visit_horizon_300/combined/sensitivity_known_target_visit_horizon_300_combined_system_performance.csv`
- `results/sensitivity_clue_search_horizon_300/combined/sensitivity_clue_search_horizon_300_combined_system_performance.csv`
- `results/sensitivity_coverage_horizon_50/combined/sensitivity_coverage_horizon_50_combined_system_performance.csv`

Source-code audit evidence:

- Current corrected process: `benchmark_sim/comms/models.py`, `known_visit_sim/comms/models.py`
- Delivery/bypass behavior: `benchmark_sim/comms/bus.py`, `benchmark_sim/comms/message.py`, `known_visit_sim/comms/bus.py`, `known_visit_sim/comms/message.py`
- FGS completion and safety-cap order: `benchmark_sim/core/scheduler.py`
- Corrected CLIPS/CV reruns and their explicit `state_correlation=0.8`, `p_gg`, and `p_bb` manifests: Git revision `f898015`
- Restoration provenance: `results/clue_search_core_500/combined/CORRECTED_GE_RESTORE_MANIFEST.json` and `results/known_target_visit_core_500/combined/CORRECTED_GE_RESTORE_MANIFEST.json`
- Archived displaced legacy bundles: each scenario's `combined/archive/pre_corrected_active_20260809` directory
- FGS corrected replacement: condition-manifest fields `target_drop_fraction`, `comm_level_stationary_delivery`, `state_correlation`, `p_gg`, and `p_bb`, plus commits `f898015` and `cc38827`

The restored CLIPS/CV active files are sourced directly from the corrected rerun bundle in `f898015`. Their supplemental corrected-condition manifests record stationary delivery, target loss, fixed state correlation 0.8, and the derived persistence probabilities. Restore manifests contain hashes for every archived and promoted file.

## 3. Task 1 — FGS completion analysis

### Verified counts

| GE nominal loss | Attempted algorithm runs | Completed | Failed | Failure rate | Six-way paired trial n |
|---:|---:|---:|---:|---:|---:|
| 5% | 600 | 600 | 0 | 0.00% | 100 |
| 10% | 600 | 600 | 0 | 0.00% | 100 |
| 20% | 600 | 594 | 6 | 1.00% | 94 |
| 30% | 600 | 584 | 16 | 2.67% | 85 |
| 40% | 600 | 573 | 27 | 4.50% | 77 |
| 50% | 600 | 526 | 74 | 12.33% | 41 |
| 60% | 600 | 467 | 133 | 22.17% | 24 |
| 70% | 600 | 432 | 168 | 28.00% | 17 |
| **Total** | **4,800** | **4,376** | **424** | **8.83%** | — |

Across GE levels, completion totals by algorithm were: CBAA 699/800 (87.38%), ACBBA 790/800 (98.75%), PI 665/800 (83.13%), HIPC 748/800 (93.50%), DMCHBA 755/800 (94.38%), and DGA 719/800 (89.88%).

All 424 failed rows have `failure_type=RuntimeError` and a `Debug safety cap reached` message. Failed rows intentionally contain blank continuous metrics. The scheduler checks whether all 361 cells are covered before it checks the event cap; therefore a cap exception can only be raised while coverage remains incomplete. I did not infer or fill an exact failed-run cell count.

The complete 150-row condition-by-algorithm table, including Ideal, Bernoulli, GE, and Rayleigh-style conditions, Wilson intervals, failure reasons, and six-way paired n, is `fgs_completion_failure_summary.csv`.

### Matched binary tests

Cochran’s Q used the 100 matched binary outcomes for all six algorithms in each FGS condition. Non-GE conditions and GE 5–10% have no outcome variation and therefore Q=0, p=1. GE 20% was not significant (Q=8.00, df=5, p=0.156). GE 30–70% was significant:

| GE loss | Cochran Q | df | p |
|---:|---:|---:|---:|
| 30% | 12.821 | 5 | 0.0251 |
| 40% | 29.173 | 5 | 2.14e-5 |
| 50% | 44.048 | 5 | 2.27e-8 |
| 60% | 82.194 | 5 | 2.91e-16 |
| 70% | 56.852 | 5 | 5.42e-11 |

Each significant condition received exactly 15 exact two-sided paired McNemar tests with Holm correction. No 30% pair survived Holm adjustment. Selected supported contrasts are:

- At 40% loss, ACBBA and DMCHBA each completed 100% versus DGA’s 88% (difference +12 percentage points; both Holm p=0.00732). Their matched odds ratios are undefined because the reverse discordant cell is zero and are deliberately left blank.
- At 50% loss, ACBBA completed 100% versus PI’s 76% (difference +24 points; Holm p=1.79e-6), and DMCHBA completed 96% versus DGA’s 79% (difference +17 points; Holm p=0.00537).
- At 60% loss, ACBBA completed 99% versus PI’s 53% (difference +46 points; Holm p=4.26e-13).
- At 70% loss, ACBBA completed 91% versus PI’s 45% (difference +46 points; Holm p=1.56e-10).

All 75 pairwise rows and their discordant cells are in `fgs_pairwise_mcnemar_holm_results.csv`.

## 4. Task 2 — revised PRDA/PRDS

### Eligibility and methods

PRDS is algorithm-complete. A trial is included for an algorithm only when that algorithm has eligible finite values at ideal communication and all eight degradation levels. The fitted model is

`log(Y(q)+c) = alpha + beta*q`, with `PRDS = 100*(exp(beta)-1)`.

PRDA is pairwise-complete. A trial is included for a pair only when both named algorithms have eligible finite values at ideal communication and all eight model levels. For pair A,B,

`D_AB(q) = [log(Y_A(q)+c)-log(Y_B(q)+c)] - [log(Y_A(0)+c)-log(Y_B(0)+c)]`,

and `PRDA_AB = (100/70)*trapz(q,D_AB(q))`.

Offsets match the existing convention: c=0 for strictly positive metrics and c=1 for metrics that can be zero. Mean intervals are two-sided 95% Student-t intervals. Wilcoxon signed-rank tests use the existing normal approximation with continuity correction, exclude exact zero differences, and report rank-biserial effect size. PRDA p-values are Holm-adjusted over exactly 15 pairs within each mission × model × metric family. A six-algorithm Friedman test is not used for the revised primary PRDA analysis.

The analysis produced 540 PRDS summaries and 1,350 PRDA pair summaries across 90 PRDA Holm families. Every family contains exactly 15 pairs.

### Eligibility expansion

For FGS GE maximum-agent steps:

- Legacy six-way complete-trajectory n: 3.
- Revised PRDS n: CBAA 30, ACBBA 90, PI 20, HIPC 58, DMCHBA 65, DGA 43.
- Revised pairwise PRDA n: 7–57, depending on pair.

The complete algorithm/pair comparison with the legacy n is in `trajectory_eligibility_old_vs_new.csv`; exact eligible trial IDs are in `trajectory_sample_sizes.csv`.

### FGS GE maximum-agent-step robustness

Mean PRDS (% metric change per +1 percentage point degradation) was CBAA 1.790 (95% CI 1.730–1.850; n=30), ACBBA 1.393 (1.356–1.429; n=90), PI 1.706 (1.632–1.780; n=20), HIPC 1.595 (1.553–1.636; n=58), DMCHBA 1.338 (1.274–1.402; n=65), and DGA 1.227 (1.147–1.306; n=43). Every algorithm’s PRDS was positive in every eligible trajectory and differed from zero by signed-rank test.

Nine of the 15 FGS GE maximum-agent-step PRDA pairs survived Holm adjustment. Examples:

- CBAA vs ACBBA: mean PRDA +15.912 (95% CI 11.318–20.506; n=28; Holm p=0.000216), so CBAA became relatively worse.
- ACBBA vs PI: −9.377 (−14.511 to −4.243; n=19; Holm p=0.0413), so ACBBA became relatively better.
- CBAA vs DMCHBA: +23.664 (17.154–30.175; n=21; Holm p=0.000833), so CBAA became relatively worse.
- HIPC vs DMCHBA: +10.707 (6.828–14.586; n=39; Holm p=0.000319), so HIPC became relatively worse.
- DMCHBA vs DGA: +1.263 (−4.916 to 7.442; n=28; Holm p=0.608), providing no evidence that their relative separation changed.

Automated sign calculations and manually inspectable level-by-level D values for representative trajectories are in `prda_sign_sanity_checks.csv`. Those checks confirm the requested sign interpretation.

## 5. Task 3 — regenerated figures

All new Python-pipeline figures have 600-dpi PNG and vector PDF versions. Each has a dedicated source CSV. MATLAB `.fig` output is retained for the MATLAB horizon workflow.

| Figure | Output stem | Source table | Decision/notes |
|---|---|---|---|
| CLIPS post-clue performance | `clips_post_clue_steps_final` | `figure_clips_post_clue_source.csv` | Matches the paper figure path; primary CLIPS metric is post-clue team steps, with analytic n and 95% CIs |
| Maximum-agent steps | `max_agent_steps_all_missions_final` | `figure_maximum_agent_steps_source.csv` | Matches the paper figure path; 3×3 mission/model layout with FGS GE declining n printed |
| FGS completion probability | `fgs_completion_rates_final` | `figure_fgs_completion_source.csv` | Matches the paper figure path; 95% Wilson intervals, severe-loss region, and six-way paired n beneath each loss tick |
| Total team steps | `total_team_steps` | `figure_total_team_steps_source.csv` | CIs represent trial uncertainty; FGS explicitly conditional on completion |
| CV workload tradeoff | `cv_workload_tradeoff` | `figure_cv_workload_tradeoff_source.csv` | Shows HIPC’s low team steps/high unique-cell contribution Gini |
| Communication tradeoff | `communication_performance_tradeoff_revised` | `figure_communication_tradeoff_source.csv` | Matches the paper figure path; impaired-condition trajectories use open 5% endpoints and 70% arrowheads |
| Main robustness | `prda_pairwise_complete_final` | `figure_pairwise_prda_source.csv` | Matches the paper figure path; filled/open markers encode Holm significance and pair-specific n ranges remain printed |
| PRDS supplement | `prds_supplement` | `figure_prds_supplement_source.csv` | No averaging across models; algorithm-specific n printed |
| Horizon tuning | `horizon_tuning.png/.fig` | `horizon_tuning_paired_trial_delta_summary.csv` | Existing baseline retained; stars mark the mission/algorithm horizons listed in the manuscript tuning table |
| DGA iteration tuning | `DGA_iteration.png/.fig` | `dga_iteration_percent_delta_summary.csv` | CV only; stars mark main-benchmark k=25; no CLIPS DGA-iteration campaign is present |

The horizon baseline is exactly what the MATLAB code says: within mission, algorithm, and trial, it averages the metric over every tested horizon and both communication settings, then plots the mean trial-level deviation from that paired baseline. The regenerated analysis used 1,500 fully paired algorithm-trials for CV, 1,232 for CLIPS, and 246 for FGS, dropping 0, 3, and 4 incomplete algorithm-trials, respectively. The method was checked, not silently changed.

The paper path `figures/total_steps_workload_tradeoff_final.png` has no one-to-one revised output. The updated analysis separates this content into `total_team_steps.png` (three-mission team-step uncertainty) and `cv_workload_tradeoff.png` (the CV HIPC workload-imbalance tradeoff). Combining them under the old caption would misdescribe both plots; the paper should use two figure environments or select one of the two scientific questions.

`FIGURE_CAPTIONS.tex` contains proposed LaTeX environments and captions. The old canonical MATLAB generator is archived at `results/analysis/archive/analyze_horizon_sensitivity_paper_figures_pre_revised_20260809.m`; the uploaded revision is now `results/analysis/analyze_horizon_sensitivity_paper_figures.m`.

The later correction specification `C:\Users\lottj\Downloads\dcta_figure_corrections.tex` was applied to the active figures. Its warning that only FGS uses fixed-rho Gilbert--Elliott is superseded by the restored corrected CLIPS/CV reruns, so the common Gilbert--Elliott column title remains accurate. The pre-correction active figure set is preserved in `results/analysis/figures/archive/pre_dcta_figure_corrections_20260809/`.

## 6. Task 4 — Gilbert–Elliott audit

| Mission | Parameter mapping actually used | Transition matrix (rows G/B, columns G/B) | Stationary loss | Lag-1 correlation | Paper fixed-rho=0.8 claim |
|---|---|---|---|---|---|
| CLIPS | q=stationary delivery; pGG=q+0.8(1−q); pBB=(1−q)+0.8q | `[[0.8+0.2q,0.2(1−q)],[0.2q,1−0.2q]]` | 1−q | 0.8 | Correct |
| CV | q=stationary delivery; pGG=q+0.8(1−q); pBB=(1−q)+0.8q | `[[0.8+0.2q,0.2(1−q)],[0.2q,1−0.2q]]` | 1−q | 0.8 | Correct |
| FGS | q=stationary delivery; pGG=q+0.8(1−q); pBB=(1−q)+0.8q | `[[0.8+0.2q,0.2(1−q)],[0.2q,1−0.2q]]` | 1−q | 0.8 | Correct |

For all three missions, state is maintained per directed sender–receiver link. Each link is initialized from its stationary distribution, with GOOD probability q. Delivery is evaluated from the current state before the link transitions. GOOD delivers with probability 1 and BAD with probability 0.

Protected publications bypass the model and do not advance link state. CLIPS/FGS protect collision-intent and target publications; CV protects collision-intent publications.

Mean stored trial-level unprotected drop fractions independently track nominal loss:

| Nominal loss | CLIPS | CV | FGS |
|---:|---:|---:|---:|
| 5% | 5.054% | 5.090% | 4.960% |
| 10% | 10.202% | 9.963% | 9.855% |
| 20% | 20.156% | 19.920% | 19.811% |
| 30% | 30.193% | 30.294% | 29.967% |
| 40% | 40.284% | 40.164% | 39.822% |
| 50% | 50.689% | 50.153% | 50.132% |
| 60% | 60.613% | 60.066% | 60.108% |
| 70% | 70.454% | 69.929% | 69.993% |

These are unweighted means of the exact stored per-trial `message_drop_fraction`, which excludes protected deliveries. An attempt-weighted pooled fraction is not invented because the result rows do not expose `unprotected_delivered_total` and failed FGS runs can terminate with successful deliveries still queued.

The standalone audit simulated 500,000 attempts per level through each mission's actual factory. Maximum absolute nominal-drop error was 0.006774 and maximum absolute lag-one-correlation error was 0.002905 for each factory. The common-seed sequences were identical, confirming fixed rho≈0.8 in CLIPS, CV, and FGS.

Overall classification: **A**. The active results for all three missions match the paper's fixed-rho=0.8 description. The pre-correction CLIPS/CV files are archived and excluded from the analysis.

## 7. Exact statistics that should be inserted into the paper

Condition-level continuous-metric comparisons below use the same six-way-paired completed trials as the plotted means. Wilcoxon signed-rank p-values are Holm-adjusted over the 15 algorithm pairs within each mission, communication model, degradation level, and metric. The averages are unweighted means of the 24 impaired-condition means.

### Corrected CLIPS results

- Maximum-agent steps: DMCHBA 56.72, ACBBA 60.58, HIPC 63.16, PI 63.34, CBAA 63.83, and DGA 64.10. The corresponding counts of Holm-supported wins were 71, 31, 4, 7, 5, and 1. DMCHBA versus ACBBA favored DMCHBA in 8 conditions and neither algorithm in 16.
- Post-clue team steps: DMCHBA 158.46, ACBBA 172.96, CBAA 180.62, HIPC 182.09, PI 183.26, and DGA 186.84. Paired support was 384--386 trials per impaired condition. Supported-win totals were DMCHBA 70, ACBBA 28, CBAA 5, HIPC 6, PI 8, and DGA 0; DMCHBA versus ACBBA again split 8/0/16.
- Total team steps: DMCHBA 221.64, ACBBA 236.15, CBAA 243.81, HIPC 245.27, PI 246.45, and DGA 250.03.
- The restored CLIPS bundle still contains the previously documented single DMCHBA safety-cap failure in the Ideal condition. It contains zero failures in the 24,000 corrected GE runs.

### Corrected CV results

- Maximum-agent steps: DGA 24.49, DMCHBA 24.78, CBAA 26.02, ACBBA 29.11, HIPC 32.30, and PI 34.86. Supported-win totals were 105, 93, 68, 39, 22, and 5, respectively. DGA versus DMCHBA favored DGA in 13 conditions, DMCHBA in 2, and neither in 9.
- Total team steps: HIPC 68.94, DGA 85.18, DMCHBA 89.99, CBAA 96.42, ACBBA 99.92, and PI 105.44. HIPC won all 120 Holm-supported pairwise opportunities.
- HIPC's low total travel remains a workload-concentration tradeoff: its mean unique-cell contribution Gini was 0.348 and target-completion Gini was 0.438, versus 0.075 and 0.238 for DMCHBA and 0.099 and 0.246 for DGA.

### Cross-mission statements

Use these statements, also supplied in `PAPER_INSERTIONS.tex`:

1. FGS GE reliability: 424/4,800 failures (8.83%), with failure rates 0.00%, 0.00%, 1.00%, 2.67%, 4.50%, 12.33%, 22.17%, and 28.00% at 5–70% nominal loss.
2. FGS conditional-efficiency n at those levels: 100, 100, 94, 85, 77, 41, 24, and 17 complete six-way paired trials.
3. Cochran Q first reaches significance at 30% (Q=12.821, df=5, p=0.0251), but no 30% McNemar pair survives Holm. Strong pairwise completion differences appear from 40% onward.
4. Revised FGS GE maximum-agent-step trajectory support expands from legacy n=3 to PRDS n=20–90 and PRDA n=7–57.
5. The corrected CLIPS, CV, and FGS GE campaigns all have stationary loss 1−q and lag-one state correlation 0.8.
6. Mean publications per team step across impaired conditions were 2.063 for CLIPS DMCHBA, 2.083 for CV DMCHBA, and 2.012 for FGS DMCHBA; DMCHBA had 120/120 Holm-supported communication wins in every mission.

## 8. Exact text/claims that should NOT be made anymore

- Do not infer GE transition probabilities from the displaced legacy-style condition labels; use the corrected `drop_*_rho_0_8` manifests and active restored files.
- Do not mix the archived pre-correction CLIPS/CV files into current tables or figures.
- Do not treat missing FGS efficiency metrics as ordinary missing observations or replace them with a giant step penalty in the primary analysis.
- Do not describe severe-loss FGS efficiency curves as if every point has n=100.
- Do not use the old six-algorithm full-curve intersection as the primary PRDS or PRDA eligibility rule.
- Do not average FGS GE PRDS/PRDA with other communication models as if their eligible n were comparable.
- Do not label publication-rate metrics as messages per cell.
- Do not use the retired mission labels Bayesian Search or Coverage as names for CLIPS or FGS.
- Do not describe the horizon baseline as ideal-only or single-setting; it averages all horizons and both tested communication settings within algorithm/trial.

## 9. Decisions requiring my review

Implementation choices were made conservatively and are documented. The remaining scientific/manuscript decisions are collected in the final section, **CRITICAL DECISIONS FOR JAMES**.

## 10. List of generated files with paths

### Reproducible scripts

- `results/analysis/run_publication_analysis.py`
- `results/analysis/restore_corrected_ge_results.py`
- `results/analysis/verify_gilbert_elliott.py`
- `results/analysis/generate_publication_figures.py`
- `results/analysis/analyze_horizon_sensitivity_paper_figures.m`
- `results/analysis/analyze_known_target_visit_dga_iteration_sensitivity.m`
- `results/analysis/build_dcta_paired_metric_results.m`
- `results/analysis/archive/analyze_horizon_sensitivity_paper_figures_pre_revised_20260809.m`

### Corrected-result restoration records

- `results/clue_search_core_500/combined/CORRECTED_GE_RESTORE_MANIFEST.json`
- `results/clue_search_core_500/combined/clue_search_core_500_corrected_ge_condition_manifest.csv`
- `results/clue_search_core_500/combined/archive/pre_corrected_active_20260809/`
- `results/known_target_visit_core_500/combined/CORRECTED_GE_RESTORE_MANIFEST.json`
- `results/known_target_visit_core_500/combined/known_target_visit_core_500_corrected_ge_condition_manifest.csv`
- `results/known_target_visit_core_500/combined/archive/pre_corrected_active_20260809/`
- `results/analysis/figures/archive/pre_corrected_clips_cv_analysis_20260809/`
- `results/analysis/figures/archive/pre_dcta_figure_corrections_20260809/`

### Requested statistical tables and audit outputs

- `results/analysis/tables/fgs_completion_failure_summary.csv`
- `results/analysis/tables/fgs_cochran_q_results.csv`
- `results/analysis/tables/fgs_pairwise_mcnemar_holm_results.csv`
- `results/analysis/tables/revised_prds.csv`
- `results/analysis/tables/revised_prda.csv`
- `results/analysis/tables/revised_prda_statistical_tests.csv`
- `results/analysis/tables/trajectory_sample_sizes.csv`
- `results/analysis/tables/trajectory_eligibility_old_vs_new.csv`
- `results/analysis/tables/prda_sign_sanity_checks.csv`
- `results/analysis/tables/gilbert_elliott_audit.csv`
- `results/analysis/tables/gilbert_elliott_realized_drop_fractions.csv`
- `results/analysis/tables/gilbert_elliott_sequence_verification.csv`
- `results/analysis/tables/publication_analysis_source_manifest.csv`
- `results/analysis/tables/publication_analysis_validation_log.txt`
- `results/analysis/tables/publication_figure_condition_summary.csv`
- `results/analysis/tables/publication_condition_pairwise_tests.csv`
- `results/analysis/tables/dcta_metric_results.csv`
- `results/analysis/tables/dcta_statistical_tests.csv`
- `results/analysis/tables/dcta_metric_source_manifest.csv`
- `results/analysis/tables/dcta_metric_analysis_log.txt`
- `results/analysis/tables/horizon_tuning_paired_trial_delta_summary.csv`
- `results/analysis/tables/dga_iteration_percent_delta_summary.csv`

### Figure source tables

- `results/analysis/tables/figure_clips_post_clue_source.csv`
- `results/analysis/tables/figure_maximum_agent_steps_source.csv`
- `results/analysis/tables/figure_fgs_completion_source.csv`
- `results/analysis/tables/figure_total_team_steps_source.csv`
- `results/analysis/tables/figure_cv_workload_tradeoff_source.csv`
- `results/analysis/tables/figure_communication_tradeoff_source.csv`
- `results/analysis/tables/figure_pairwise_prda_source.csv`
- `results/analysis/tables/figure_prds_supplement_source.csv`

### Figures

Each stem below has `.png` and `.pdf` versions in `results/analysis/figures`:

- `clips_post_clue_steps_final`
- `max_agent_steps_all_missions_final`
- `fgs_completion_rates_final`
- `total_team_steps`
- `cv_workload_tradeoff`
- `communication_performance_tradeoff_revised`
- `prda_pairwise_complete_final`
- `prds_supplement`

MATLAB horizon outputs:

- `results/analysis/figures/horizon_tuning.png`
- `results/analysis/figures/horizon_tuning.fig`
- `results/analysis/figures/DGA_iteration.png`
- `results/analysis/figures/DGA_iteration.fig`

### Paper-ready text

- `PAPER_INSERTIONS.tex`
- `results/analysis/FIGURE_CAPTIONS.tex`
- `ANALYSIS_AND_PAPER_UPDATE_REPORT.md`

## Internal consistency audit

- Counts and percentages reproduce exactly from raw attempted/completed/failed rows.
- FGS GE paired n reproduces the supplied 100, 100, 94, 85, 77, 41, 24, 17 sequence.
- Every significant FGS completion family has exactly 15 McNemar comparisons.
- Every PRDA family has exactly 15 Wilcoxon comparisons before Holm adjustment.
- Every figure-metric condition family has exactly 15 paired Wilcoxon comparisons before Holm adjustment; the CLIPS post-clue primary metric covers all 25 communication conditions.
- The refreshed MATLAB paired-metric outputs contain 5,394 metric rows and 14,384 statistical rows, comprising 899 Friedman omnibus families and 13,485 pairwise Wilcoxon rows.
- All plot points reproduce their dedicated source CSVs; regenerated PNG/PDF timestamps postdate the source tables.
- New mission labels consistently use Clue-Informed Probabilistic Search (CLIPS), Collaborative Visit (CV), and Full Grid Search (FGS).
- FGS efficiency is explicitly conditional on completion and separated from completion probability.
- No simulation was newly executed. Displaced legacy CLIPS/CV files were moved intact to scenario-local archives, and corrected rerun blobs from `f898015` were restored with hashes and row counts recorded.

## CRITICAL DECISIONS FOR JAMES

1. **Main robustness emphasis:** approve maximum-agent-step pairwise PRDA as the main robustness figure and model-separated PRDS as supplementary, or name a different primary metric. All metrics remain available in the CSVs.
2. **Communication tradeoff:** approve message publications per team step as the consistent x-axis. Allocator-specific publications per mission cannot be compared cleanly without first standardizing topic classification across algorithms.
3. **Primary FGS estimand:** confirm the two-part presentation—completion probability plus efficiency conditional on completion—and keep cap-penalty analysis out of the primary results.
