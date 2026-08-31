# Pre-launch configuration correction

Before the campaign launch, two measured diagnostic records and the initial excluded warmups were produced with draft study-local allocator subclasses. Those subclasses changed DGA/DMCHBA planning behavior and therefore were not an acceptable timing-study configuration.

The draft artifacts are retained unchanged under `superseded_prelaunch_adapter_diagnostics_20260831/`; they are not part of the active raw-result tree, combined files, progress count, or analysis. No canonical CV data was changed or moved.

The active runner now reuses every production allocator class unchanged. It supplies `SimConfig.commitment_horizon=2` only to ACBBA, PI, and HIPC to reproduce their selected bundle setting. It supplies no study-level generic horizon to CBAA, DMCHBA, or DGA. DGA retains its production 25-iteration setting. This preserves the settled study convention without rewriting the native DGA/DMCHBA implementation, whose historical internal default of three remains documented as a source-provenance discrepancy.

This pre-launch decision was superseded by the user's later explicit instruction to rerun DGA and DMCHBA without a commitment horizon. That separate, user-directed architecture change is recorded in `ARCHITECTURE_CHANGES.md` and `USER_DIRECTED_DGA_DMCHBA_NO_HORIZON_RERUN.md`.
