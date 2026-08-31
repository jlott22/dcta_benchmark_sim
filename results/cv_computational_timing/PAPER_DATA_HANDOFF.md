# Paper Data Handoff

## Authoritative timing files

- `combined/timing_invocation_trial_level.csv`
- `combined/timing_invocation_robot_level.csv`
- `combined/timing_mission_trial_level.csv`
- `combined/timing_mission_robot_level.csv`
- `combined/timing_condition_summary.csv`
- `combined/timing_timeout_and_failure_log.csv`
- `analysis/timing_pairwise_tests.csv`
- `analysis/timing_timeout_summary.csv`
- `analysis/timing_figure_sources.csv`

## Abstract / Results values

Use the exact primary-condition statistics in `TIMING_FINDINGS.md`: first-invocation chi-square(5) = 470.183, p = 2.17e-99, W = 0.940; cumulative-team-time chi-square(5) = 457.377, p = 1.26e-96, W = 0.915. State that all 3,750 planned timing jobs completed, including 750/750 at 50 targets.

## Discussion support

Report per-invocation and cumulative-compute rankings separately. Explain that measurements are implementation-level Python wall-clock results on the tested laptop. State explicitly that the DGA/DMCHBA timing rerun uses the documented no-horizon study variants, while the historical core data record a fixed horizon of three.

## Figure sources

- `figures/timing_invocation_vs_target_count.png`
- `figures/timing_cumulative_vs_target_count.png`
- `figures/timing_call_count_vs_target_count.png`
- `figures/timing_per_invocation_vs_cumulative_10target.png`
- `analysis/timing_figure_sources.csv`

## Statements not to make

- Do not claim language-independent or intrinsic algorithm complexity from these Python wall-clock timings.
- Do not claim the no-horizon DGA/DMCHBA timing variants are identical to the historical h=3 core implementation.
- Do not treat individual allocator calls within a mission as independent replicates.
- Do not state that a timeout was observed or impute a 20-minute timeout value; none occurred.
