# DCTA Benchmark Simulator

A lightweight asynchronous grid simulator for benchmarking decentralized task-allocation algorithms in clue-informed multi-robot search under degraded communication.

This package intentionally **does not implement the task-allocation algorithms**. It provides the trial runner, world model, belief map, communication models, metrics exports, and a live viewer. Add algorithm implementations by subclassing `benchmark_sim.algorithms.base.AllocatorBase`.

## Key design choices

- 19×19 grid by default.
- Four robots start on the west edge: `00=(0,0)`, `01=(0,5)`, `02=(0,10)`, `03=(0,15)`, all facing east.
- Asynchronous robot wake-ups with configurable jitter.
- Target and clue detection are perfect when the robot reaches the cell (`POD = 1`).
- Target-found messages are protected and are never dropped.
- Collision-intent messages are protected and are never dropped.
- All other messages are subject to the selected degraded communication model.
- No pre-clue serpentine sweep is built into the simulator. Pre-clue behavior belongs in each algorithm implementation.
- Belief map uses `target_p` only. 
- Scenario files are loaded from your generator CSV format or JSON.
- Performance outputs are written as CSV.

## Package layout

```text
benchmark_sim/
  config.py
  run_trials.py
  run_viewer.py
  core/
    belief.py
    planner.py
    robot.py
    scenario_loader.py
    scheduler.py
    types.py
    world.py
  comms/
    bus.py
    message.py
    models.py
  metrics/
    counters.py
    export.py
    summary.py
  algorithms/
    base.py
    registry.py
    template.py
  visualization/
    pygame_viewer.py
```

## Install optional dependencies

The simulator only needs the Python standard library for batch execution. The live viewer requires pygame.

```bash
pip install pygame
```

## Running batch trials

After you add an allocator class:

```bash
python -m benchmark_sim.run_trials \
  --scenario-file trials_d1_c4_g19.csv \
  --algorithm my_algorithms.silent_canwin:SilentCanWinAllocator \
  --comm-model bernoulli \
  --comm-level 0.25 \
  --out-dir runs/test_bernoulli_025
```

The algorithm argument uses `module.path:ClassName`.

## Running the live viewer

```bash
python -m benchmark_sim.run_viewer \
  --scenario-file trials_d1_c4_g19.csv \
  --algorithm my_algorithms.silent_canwin:SilentCanWinAllocator \
  --comm-model bernoulli \
  --comm-level 0.10
```

Viewer controls:

- `p`: pause/resume
- `.`: single-step while paused
- `t`: toggle true target/clue overlay
- `1`–`4`: show probability heatmap for a selected robot
- `n`: next trial after completion
- `q` or `Esc`: quit

## Output files

Batch mode writes:

```text
trial_summary.csv
system_performance.csv
robot_performance.csv
config_used.json
```

`trial_summary.csv` contains descriptors and verification fields. `system_performance` and `robot_performance` contain metrics intended for evaluation.

## Algorithm interface

See `benchmark_sim/algorithms/base.py` and `benchmark_sim/algorithms/template.py`.

Algorithms are responsible for selecting goals and publishing any allocation-specific messages. The simulator handles movement, detection, protected target termination, protected collision-intent safety, message loss, belief updates from detected/delivered clues, and metric collection.
