# Corrected-GE Coverage Failure Interpretation

Date recorded: 2026-07-27

## Summary

The corrected Gilbert–Elliott (GE) coverage trials that remain incomplete at
75,000 and 100,000 scheduler events should be recorded as coordination
failures, not treated as unusually slow successful trials.

The defensible interpretation is an **absorbing communication–allocation
deadlock under the combination of burst-correlated GE loss and the allocation
protocols' change-only messaging**. It should not be described as a failure
caused by the communication model alone.

## Evidence observed

At the initial inspection of the 100,000-event retry outputs:

- Every processed failure occurred in the GE drop-0.70, rho-0.8 condition.
- The failed workers exited normally and recorded `RuntimeError` with:
  `Debug safety cap reached ... allocator is stuck or returning no reachable goals.`
- There were no worker crashes, corrupt CSVs, or unrelated algorithm exceptions.
- The same deterministic trial IDs had already failed at 75,000 events.
- Matching Bernoulli drop-0.70 trials completed, generally in approximately
  927–1,132 team steps for the inspected ACBBA and HIPC trial IDs.
- All 600 rows in the existing Bernoulli drop-0.70 combined results were
  recorded as completed.

The 75,000-event quick-algorithm retry pass processed 619 earlier failures:

| Algorithm | Retried | Recovered at 75k | Still failed |
|---|---:|---:|---:|
| ACBBA | 36 | 26 | 10 |
| CBAA | 227 | 126 | 101 |
| HIPC | 134 | 82 | 52 |
| PI | 222 | 87 | 135 |
| **Total** | **619** | **321** | **298** |

The remaining 298 trials were scheduled for one final retry at 100,000 events.
Any trial that still fails at that cap remains logged as failed.

## Successful-run baseline and safety caps

After the 75,000-event retry results were merged, the four quick algorithms
(ACBBA, CBAA, HIPC, and PI) had 2,902 successful corrected-GE coverage trials.
Their observed movement-step totals were:

| Successful-trial set | N | Mean team steps | Median | Maximum |
|---|---:|---:|---:|---:|
| All corrected-GE drop levels | 2,902 | 606.2 | 581 | 1,174 |
| Corrected GE drop 0.70 | 277 | 708.4 | 682 | 1,167 |

The first retry pass used a cap of **75,000 scheduler events**. Trials still
failed after that pass were retried once at a final cap of **100,000 scheduler
events**. Thus, the final cap is far beyond the observed successful-trial
movement scale: successful drop-0.70 trials required at most 1,167 team
movement steps and averaged 708.4.

Team movement steps and scheduler events must not be described as identical
units. A scheduler event may be a move, turn, intent synchronization, path
failure, idle event, or no-goal event. The current successful-trial CSV schema
exports `total_team_steps` but does not export `events_processed`; failed
workers export the scheduler-event cap. Therefore, the table above is the
available empirical completion baseline, not an estimate mislabeled as an
average event count.

For an exact successful-run event-count comparison, representative diagnostic
replays should export `TrialState.events_processed`. Until that diagnostic
field is collected, the defensible statement is:

> Successful corrected-GE drop-0.70 trials averaged 708.4 team movement steps
> and required at most 1,167 team movement steps, whereas terminal trials
> remained incomplete through 75,000 and then 100,000 scheduler events.

## Mechanism

For stationary delivery probability 0.30 (drop probability 0.70) and state
correlation 0.8, the corrected GE parameters are:

- `pGG = 0.86`
- `pBB = 0.94`

Once a directed link enters the bad state, its expected bad-state run is about
16.7 attempted messages. By comparison, an independent Bernoulli process with
70% loss has an average loss run of about 3.3 messages.

The probability of ten consecutive losses illustrates the difference:

- Bernoulli drop 0.70: approximately 2.8%
- GE after entering the bad state: approximately 57%

These GE bursts can remove an entire sequence of task claims, releases, bundle
snapshots, or robot-state updates. The relevant allocator implementations do
not use claim leases, claim expiration, or periodic full-table refreshes.
Allocation messages are generally sent only after a bundle or table change,
and robot state messages are sent only after movement.

A lost release or snapshot can therefore leave robots with stale, inconsistent
ownership tables. Eventually the remaining globally unvisited cells may appear
owned or unavailable in every local table. The robots then repeatedly return
`no_goal` or `idle`.

The interaction is reinforced by two implementation details:

1. GE link state advances when a non-protected message is attempted, rather
   than continuously with simulated time.
2. Once robots stop moving and bundles stop changing, few or no allocation-
   relevant messages are attempted.

Consequently, the state may become self-preserving: coverage does not increase,
claims do not refresh, and communication does not generate a recovery event.

## What “indefinite” means

Reaching the 100,000-event cap alone proves non-termination only through that
threshold. A stronger claim of indefinite continuation should be supported by
a diagnostic replay showing that:

- coverage plateaus below 361 cells;
- no new cell is visited during a long final window;
- all robots repeatedly produce `no_goal` or `idle`;
- no bundle-changing or allocation-changing message is produced;
- the remaining cells are excluded by stale ownership claims; and
- the allocation-relevant state is unchanged from one event to the next,
  apart from the scheduler clock and event counter.

If those properties hold, the state is absorbing under the implemented
transition rules: another scheduler event cannot increase coverage or repair
the allocation state without an external perturbation.

## Recommended manuscript language

> A trial was classified as a terminal coordination failure if it remained
> incomplete at 100,000 scheduler events after also failing at 75,000 events.
> Diagnostic inspection identified an absorbing no-goal state induced by the
> interaction of burst-correlated communication loss and non-expiring,
> change-only allocation messages. These trials were retained as failures
> rather than treated as unusually long completion times.

For the Bernoulli comparison:

> Bernoulli and Gilbert–Elliott conditions had comparable mean message-loss
> rates but different temporal structures. Independent Bernoulli losses
> permitted intermittent coordination recovery, whereas correlated GE bursts
> could remove complete claim/release sequences and expose the absence of
> claim expiration and periodic retransmission.

Avoid writing that GE loss alone mathematically guarantees infinite execution.
The observed behavior is an interaction among burst loss, allocator consensus
state, change-only retransmission, and the simulator's message-driven GE state
transition.

## Recommended presentation

Report:

1. Completion rate by algorithm and GE drop level.
2. Completion steps conditional on successful completion.
3. A coverage-versus-events trace for representative successful and failed
   trials.
4. The last-progress event, remaining unvisited cells, tail `no_goal` fraction,
   and tail allocation-message count for diagnostic failures.
5. A survival curve for events to full coverage, with unfinished trials
   censored at 100,000 events.

For algorithm ranking, use completion probability as the primary robustness
measure and completion steps as a secondary, conditional measure. Do not rank
algorithms solely by the mean steps of successful trials, because that omits
the hardest failed trials.

## Relevant implementation locations

- Frozen GE model:
  `runs/coverage_core_100_ge_bursty_rho08/runtime/legacy_ge_20260723/benchmark_sim/comms/models.py`
- Frozen scheduler and event cap:
  `runs/coverage_core_100_ge_bursty_rho08/runtime/legacy_ge_20260723/benchmark_sim/core/scheduler.py`
- Robot state publication and no-goal behavior:
  `runs/coverage_core_100_ge_bursty_rho08/runtime/legacy_ge_20260723/benchmark_sim/core/robot.py`
- ACBBA change-only table messages:
  `runs/coverage_core_100_ge_bursty_rho08/runtime/legacy_ge_20260723/benchmark_sim/algorithms/ACBBA.py`
- HIPC change-only bundle messages:
  `runs/coverage_core_100_ge_bursty_rho08/runtime/legacy_ge_20260723/benchmark_sim/algorithms/HIPC.py`
- Historical cap-escalation shard archive:
  `runs/coverage_core_100_ge_bursty_rho08/artifacts/validated_shards.zip`
