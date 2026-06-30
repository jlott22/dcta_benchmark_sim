# Static Collaborative Known-Target Visit

This package is an isolated simulator fork. It does not import `benchmark_sim`
at runtime. All task cells are known at initialization, and world truth ends a
trial as soon as every task has been visited.

Generate paired scenarios:

```bash
python -m known_visit_sim.generate_scenarios \
  --grid-size 19 --num-robots 4 --num-targets 10 --num-trials 500 \
  --robot-start-layout edge_even --seed 20260630 \
  --output known_visit_g19_t10_n500.csv
```

Run one algorithm/communication condition:

```bash
python -m known_visit_sim.run_trials \
  --scenario-file known_visit_g19_t10_n500.csv \
  --algorithm DGA --comm-model ideal --grid-size 19 --num-robots 4 \
  --robot-start-layout edge_even --condition-id known_visit_ideal \
  --out-dir runs/known_visit/dga_ideal
```

Built-in algorithm names are `CBAA`, `ACBBA`, `PI`, `HIPC`, `DMCHBA`, `DGA`,
and `AuctionGreedy`. Communication models are `ideal`, `bernoulli`,
`gilbert_elliot`, and `rayleigh_style`.

Core communication consists only of droppable `state` and protected
`collision_intent` messages. Target completion is inferred from delivered peer
locations; no task-complete message exists. The output directory contains
trial, system, robot, and per-target CSV files.
