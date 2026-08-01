# Corrected-GE Coverage Failure Interpretation

Date updated: 2026-08-01

## Summary

Corrected Gilbert-Elliott (GE) coverage trials that hit their scheduler-event
safety cap are recorded as terminal coordination failures. They should not be
treated as unusually slow successful trials or retried for this dataset.

The defensible interpretation is an absorbing communication-allocation
deadlock under the combination of burst-correlated GE loss and allocation
protocols that rely heavily on change-only messaging. It should not be
described as a failure caused by the communication model alone.

## Final Dataset Policy

The final dataset uses these cap policies:

- historical quick-algorithm cap-escalation failures remained failed after the
  prior 75,000/100,000-event workflow;
- the final distributed DGA/DMCHBA pass used a 10,000-event cap;
- all cap hits are final failed rows;
- no additional retry stage is part of the final dataset.

Final GE coverage totals:

| Status | Trials |
|---|---:|
| Completed | 4,376 |
| Failed | 424 |

The final distributed pass contributed 675 formerly missing DGA/DMCHBA trials:
616 completed and 59 failed at the 10,000-event cap.

## Mechanism

For stationary delivery probability 0.30 (drop probability 0.70) and state
correlation 0.8, the corrected GE parameters are:

- `pGG = 0.86`
- `pBB = 0.94`

Once a directed link enters the bad state, its expected bad-state run is about
16.7 attempted messages. By comparison, an independent Bernoulli process with
70% loss has an average loss run of about 3.3 messages.

These GE bursts can remove an entire sequence of task claims, releases, bundle
snapshots, or robot-state updates. The relevant allocator implementations do
not use claim leases, claim expiration, or periodic full-table refreshes.
Allocation messages are generally sent only after a bundle or table change,
and robot state messages are sent only after movement.

A lost release or snapshot can therefore leave robots with stale,
inconsistent ownership tables. Eventually the remaining globally unvisited
cells may appear owned or unavailable in every local table. The robots then
repeatedly return `no_goal` or `idle`.

The interaction is reinforced by two implementation details:

1. GE link state advances when a non-protected message is attempted, rather
   than continuously with simulated time.
2. Once robots stop moving and bundles stop changing, few or no
   allocation-relevant messages are attempted.

Consequently, the state may become self-preserving: coverage does not
increase, claims do not refresh, and communication does not generate a
recovery event.

## Reporting Guidance

Recommended manuscript language:

> A trial was classified as a terminal coordination failure if it remained
> incomplete at the configured scheduler-event safety cap. Diagnostic
> inspection identified absorbing no-goal behavior induced by the interaction
> of burst-correlated communication loss and non-expiring, change-only
> allocation messages. These trials were retained as failures rather than
> treated as unusually long completion times.

For the Bernoulli comparison:

> Bernoulli and Gilbert-Elliott conditions had comparable mean message-loss
> rates but different temporal structures. Independent Bernoulli losses
> permitted intermittent coordination recovery, whereas correlated GE bursts
> could remove complete claim/release sequences and expose the absence of
> claim expiration and periodic retransmission.

Avoid writing that GE loss alone mathematically guarantees infinite execution.
The observed behavior is an interaction among burst loss, allocator consensus
state, change-only retransmission, and the simulator's message-driven GE state
transition.

For algorithm ranking, use completion probability as the primary robustness
measure and completion steps as a secondary, conditional measure. Do not rank
algorithms solely by the mean steps of successful trials, because that omits
the hardest failed trials.

## Relevant Sources

- Final validation metadata:
  `runs/coverage_core_100_ge_bursty_rho08/combined/FINAL_DATASET_METADATA.json`
- Worker validation table:
  `runs/coverage_core_100_ge_bursty_rho08/combined/worker_result_validation.csv`
- Core GE model source:
  `benchmark_sim/comms/models.py`
- Core scheduler/event-cap source:
  `benchmark_sim/core/scheduler.py`
- Core robot no-goal behavior:
  `benchmark_sim/core/robot.py`
- Allocator implementations:
  `benchmark_sim/algorithms/`
- Archived historical/runtime/distributed-run provenance:
  `runs/coverage_core_100_ge_bursty_rho08/artifacts/ge_coverage_final_provenance_20260801.zip`
