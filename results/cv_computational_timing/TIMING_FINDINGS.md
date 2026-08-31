# Timing Findings

## Dataset and integrity

The final timing dataset contains 3,750 measured scenario-trial jobs: 2,400 first-invocation jobs (Experiment 1) and 1,350 full-mission jobs (Experiment 2). All 3,750 jobs completed; there were no failures or 20-minute timeouts. The statistical replicate is the paired scenario/trial, never individual allocator calls.

The active DGA and DMCHBA records use the user-directed no-horizon timing-study variants documented in `USER_DIRECTED_DGA_DMCHBA_NO_HORIZON_RERUN.md`; their generic `SimConfig.commitment_horizon` is unset and DGA uses 25 iterations per trigger. The timing data are implementation-level Python wall-clock measurements on this laptop, not language-independent algorithm-complexity estimates.

## Primary 10-target condition

For maximum first-invocation time, the mean ranking was CBAA (0.396 ms), HIPC (0.542 ms), ACBBA (0.733 ms), PI (1.653 ms), DMCHBA (2.040 ms), DGA (243.338 ms). The paired Friedman test was chi-square(5) = 470.183, p = 2.17e-99, Kendall W = 0.940; 15 of 15 Wilcoxon comparisons survived within-metric Holm correction.

For cumulative team allocator time, the mean ranking was CBAA (13.595 ms), DMCHBA (25.154 ms), ACBBA (29.866 ms), HIPC (59.243 ms), PI (71.205 ms), DGA (9.60 s). The paired Friedman test was chi-square(5) = 457.377, p = 1.26e-96, Kendall W = 0.915; 15 of 15 Holm-corrected pairwise comparisons were significant.

Allocator-call frequency ranked DMCHBA (66.61 calls), CBAA (81.07 calls), DGA (91.76 calls), ACBBA (108.20 calls), HIPC (116.36 calls), PI (132.22 calls). The call-count omnibus result was chi-square(5) = 198.131, p = 7.13e-41, Kendall W = 0.396. Per-invocation and cumulative rankings therefore must be reported separately; the tables, rather than an inferred complexity claim, provide the supported comparison.

## Sensitivity and 50-target stress condition

The 5- and 25-target results use the same paired summaries and secondary Friedman/Wilcoxon-Holm tables in `timing_pairwise_tests.csv`. At 5 targets, first-invocation mean ranking was HIPC (0.580 ms), ACBBA (0.698 ms), CBAA (0.762 ms), DMCHBA (0.910 ms), PI (1.667 ms), DGA (130.024 ms); cumulative-team-time ranking was CBAA (15.466 ms), DMCHBA (27.000 ms), ACBBA (31.127 ms), HIPC (45.433 ms), PI (63.085 ms), DGA (9.81 s). At 25 targets, first-invocation mean ranking was CBAA (0.818 ms), HIPC (1.218 ms), ACBBA (1.769 ms), PI (4.172 ms), DMCHBA (16.879 ms), DGA (848.896 ms); cumulative-team-time ranking was CBAA (31.704 ms), ACBBA (97.227 ms), DMCHBA (104.582 ms), PI (149.910 ms), HIPC (278.302 ms), DGA (14.85 s).

The DGA mean first-invocation values across the tested loads were 5 targets: 130.024 ms, 10 targets: 243.338 ms, 25 targets: 848.896 ms, 50 targets: 2.79 s; its cumulative-team-time values were 5 targets: 9.81 s, 10 targets: 9.60 s, 25 targets: 14.85 s, 50 targets: 36.92 s. These scaling summaries are descriptive of the tested implementations and paired scenario layouts, not asymptotic complexity estimates.

At 50 targets, 750/750 jobs completed and 0 timed out. Because there was no censoring in this run, successful-trial timing distributions are descriptive summaries of all planned trials; no timeout value was imputed as a completed timing observation.

## Publication readiness

The data package is internally complete and publication-ready as a documented no-horizon timing study: every planned job is present, paired identities are complete, no duplicate or replacement record was detected, all validated timing fields are finite and nonnegative, and the source-data checksums match the locked canonical manifests. It is not valid to present these two no-horizon timing variants as an unchanged rerun of the historical fixed-horizon-three DGA/DMCHBA core benchmark; that architecture/configuration difference remains the sole material comparability caveat and must accompany any publication claim using these rows.

## Manuscript-ready sentences

- “At the primary 10-target CV condition, first-invocation allocator runtime differed across implementations (Friedman chi-square(5) = 470.183, p = 2.17e-99, Kendall W = 0.940); the mean ranking was CBAA (0.396 ms), HIPC (0.542 ms), ACBBA (0.733 ms), PI (1.653 ms), DMCHBA (2.040 ms), DGA (243.338 ms).”
- “Cumulative team allocator time at 10 targets also differed across implementations (Friedman chi-square(5) = 457.377, p = 1.26e-96, Kendall W = 0.915), with mean ranking CBAA (13.595 ms), DMCHBA (25.154 ms), ACBBA (29.866 ms), HIPC (59.243 ms), PI (71.205 ms), DGA (9.60 s).”
- “All 750 50-target timing jobs completed before the 20-minute wall-clock limit; these measurements characterize the tested Python implementations on the tested laptop.”

## Limitations

Do not describe these wall-clock values as intrinsic, language-independent algorithmic complexity. Do not claim that the no-horizon DGA/DMCHBA timing variants are identical to the historical core benchmark implementation that encoded a fixed horizon of three. The raw timing data, manifests, and paired statistical tables should be cited for numerical claims.
