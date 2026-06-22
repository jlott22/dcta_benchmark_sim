# DCTA Benchmark Simulator

Asynchronous grid simulator for benchmarking decentralized task-cell allocation algorithms in clue-informed multi-robot search under degraded communication.

The simulator provides:

- world and scenario loading
- robot motion, sensing, and A* planning
- local per-robot belief maps using `target_p`
- protected collision-intent safety
- degraded communication models
- algorithm message routing
- batch CSV metrics
- pygame live visualization

## Current Benchmark Assumptions

- Default grid is `19 x 19`.
- Four robots are used by default:
  - `00` starts at `(0, 0)`
  - `01` starts at `(0, 5)`
  - `02` starts at `(0, 10)`
  - `03` starts at `(0, 15)`
- All robots start facing east.
- Movement is asynchronous with configurable timing jitter.
- Target and clue detection are perfect when a robot reaches the cell.
- Target-found messages are protected and are never dropped.
- Collision-intent messages are protected and are never dropped.
- State, clue, and allocation messages are subject to the selected communication model.
- Belief uses target probability only: `target_p`.
- Pre-clue coverage behavior is owned by each algorithm implementation.
- Metric outputs are CSV-only.

## Repository Layout

```text
benchmark_sim/
  run_trials.py
  run_viewer.py
  config.py
  clue_object_generator_manhat.py
  algorithms/
    ACBBA.py
    Auction_greedy.py
    CBAA.py
    DMCHBA.py
    HIPC.py
    PI.py
    base.py
    registry.py
  comms/
    bus.py
    message.py
    models.py
  core/
    belief.py
    planner.py
    robot.py
    scenario_loader.py
    scheduler.py
    types.py
    world.py
  metrics/
    counters.py
    export.py
    summary.py
  visualization/
    pygame_viewer.py
```

## Implemented Algorithms

Built-in allocator modules currently include:

- `benchmark_sim.algorithms.ACBBA:ACBBAAllocator`
- `benchmark_sim.algorithms.CBAA:CBAAAllocator`
- `benchmark_sim.algorithms.DMCHBA:DMCHBAAllocator`
- `benchmark_sim.algorithms.PI:PIAllocator`
- `benchmark_sim.algorithms.HIPC:HIPCAllocator`
- `benchmark_sim.algorithms.Auction_greedy:AuctionGreedyAllocator`

The CLI accepts allocator classes in `module.path:ClassName` format. Algorithm display names can be overridden with `--algorithm-name`.

## Communication Models

`--comm-model` supports:

- `ideal` - all non-protected messages are delivered.
- `bernoulli` - independent receiver-side drops. `--comm-level` is drop probability.
- `gilbert_elliot` - two-state burst-loss model. `--comm-level` sets good-state persistence.
- `rayleigh_style` - simplified distance/path-loss/fading model. `--comm-level` sets sensitivity in dBm.

Protected messages bypass degraded delivery:

- `target`
- `collision_intent`

Core message categories:

- `state`
- `clue`
- `target`
- `collision_intent`

All other algorithm-published messages are allocation messages.

## Scenario Files

Clue-search mode uses CSV or JSON scenario files.

The bundled generator-style CSV format is:

```text
# optional metadata comments
episode,object_x,object_y,clue1_x,clue1_y,clue2_x,clue2_y,...
0,3,6,17,4,10,5,11,13,11,18
```

In simulator terminology:

- `episode` becomes `trial_id`
- `object_x/object_y` is the target location
- `clueN_x/clueN_y` are clue locations

The repository root includes `final_trial_500.csv`.

## Running Batch Trials

Example ACBBA run:

```bash
python -m benchmark_sim.run_trials ^
  --scenario-file final_trial_500.csv ^
  --algorithm benchmark_sim.algorithms.ACBBA:ACBBAAllocator ^
  --algorithm-name ACBBA ^
  --comm-model bernoulli ^
  --comm-level 0.10 ^
  --max-trials 10 ^
  --out-dir runs/acbba_bernoulli_010
```

Example DMCHBA run:

```bash
python -m benchmark_sim.run_trials ^
  --scenario-file final_trial_500.csv ^
  --algorithm benchmark_sim.algorithms.DMCHBA:DMCHBAAllocator ^
  --algorithm-name DMCHBA ^
  --comm-model ideal ^
  --max-trials 10 ^
  --out-dir runs/dmchba_ideal
```

Coverage mode does not require a scenario file:

```bash
python -m benchmark_sim.run_trials ^
  --trial-mode coverage ^
  --num-trials 5 ^
  --algorithm benchmark_sim.algorithms.Auction_greedy:AuctionGreedyAllocator ^
  --algorithm-name AG ^
  --comm-model ideal ^
  --out-dir runs/ag_coverage
```

Useful options:

- `--trial-mode clue_search|coverage`
- `--scenario-file <path>`
- `--max-trials <n>`
- `--num-trials <n>` for coverage mode
- `--seed <int>`
- `--grid-size <n>`
- `--target-decay-exp <float>`
- `--out-dir <path>`

## Running The Live Viewer

The viewer requires pygame:

```bash
pip install pygame
```

Run:

```bash
python -m benchmark_sim.run_viewer ^
  --scenario-file final_trial_500.csv ^
  --algorithm benchmark_sim.algorithms.ACBBA:ACBBAAllocator ^
  --algorithm-name ACBBA ^
  --comm-model bernoulli ^
  --comm-level 0.10
```

Viewer controls:

- `p`: pause/resume
- `.`: single-step while paused
- `t`: toggle true target/clue overlay
- `1`-`4`: show probability heatmap for a selected robot
- `n`: next trial after completion
- `q` or `Esc`: quit

## Output Files

Batch mode writes:

```text
trial_summary.csv
system_performance.csv
robot_performance.csv
config_used.json
```

### trial_summary.csv

Descriptor and verification fields:

- `trial_id`
- `trial_mode`
- `algorithm`
- `comm_model`
- `comm_level`
- `scenario_file`
- `target_x`
- `target_y`
- `clue_locations`
- `first_clue_robot`
- `first_clue_x`
- `first_clue_y`
- `robot_start_locations`
- `robot_end_locations`
- `clues_detected_by_robot`
- `target_found_by_robot`

### system_performance.csv

System-level metrics:

- `trial_id`
- `trial_mode`
- `algorithm`
- `comm_model`
- `comm_level`
- `total_team_steps`
- `steps_before_first_clue`
- `post_clue_steps_to_find`
- `unique_cells_searched`
- `system_revisits`
- `task_cell_replans_total`
- `path_replans_total`
- `collision_prevention_events`
- `messages_sent_total`
- `messages_delivered_total`
- `messages_dropped_total`
- `protected_messages_sent_total`
- `unprotected_messages_sent_total`
- `core_messages_sent_total`
- `allocation_messages_sent_total`
- `post_clue_messages_sent_total`
- `post_clue_allocation_messages_sent_total`
- `message_drop_fraction`
- `messages_per_unique_cell`
- `messages_per_post_clue_step`
- `allocation_messages_per_step`
- `allocation_messages_per_post_clue_step`
- `allocation_messages_per_unique_cell`
- `messages_sent_by_topic`
- `max_steps_any_robot`
- `max_messages_any_robot`
- `workload_gini_unique_cells_contributed`

`workload_gini_unique_cells_contributed` measures balance of useful unique search contribution across robots. Historical Gini fields in older outputs were step-based, not unique-cell based.

### robot_performance.csv

Robot-level metrics:

- `trial_id`
- `trial_mode`
- `algorithm`
- `comm_model`
- `comm_level`
- `robot_id`
- `steps_total`
- `steps_after_first_clue`
- `unique_cells_contributed`
- `system_revisits_by_robot`
- `task_cell_replans`
- `path_replans`
- `collision_prevention_events`
- `messages_sent`
- `protected_messages_sent`
- `unprotected_messages_sent`
- `core_messages_sent`
- `allocation_messages_sent`
- `post_clue_messages_sent`
- `messages_sent_by_topic`
- `messages_delivered_to_robot`
- `messages_dropped_to_robot`

## Metric Definitions

- `unique_cells_searched`: count of globally unique searched cells.
- `unique_cells_contributed`: per-robot count of cells that robot was first to contribute to team coverage.
- `system_revisits`: team-level repeat searches of already searched cells.
- `system_revisits_by_robot`: repeat searches attributed to a robot.
- `task_cell_replans`: post-clue replacement of an unsearched task cell.
- `path_replans`: post-clue path failures and collision replans.
- `collision_prevention_events`: post-clue collision-prevention event count; repeated blocks in the same episode are not double counted until movement resumes.
- `messages_sent_total`: all published simulator messages before drops.
- `messages_delivered_total`: delivered messages after communication model filtering.
- `messages_dropped_total`: dropped messages after communication model filtering.
- `protected_messages_sent_total`: target and collision-intent messages.
- `core_messages_sent_total`: state, clue, target, and collision-intent messages.
- `allocation_messages_sent_total`: algorithm-specific allocation messages.
- `post_clue_messages_sent_total`: messages sent after first clue discovery.
- `post_clue_allocation_messages_sent_total`: allocation messages sent after first clue discovery.

## Algorithm Interface

See `benchmark_sim/algorithms/base.py`.

Allocator implementations subclass `AllocatorBase` and provide:

- `initialize(robot)`
- `handle_message(robot, message)`
- `on_observation(robot, observation)`
- `choose_goal(robot)`

The simulator handles movement, sensing, protected target termination, protected collision-intent safety, message loss, belief updates, and metric collection. Algorithms select task cells and publish allocation-specific messages through `robot.publish_algorithm_message(...)`.

## Notes

- Metric exports are CSV-only; `--no-parquet` remains as a deprecated compatibility flag.
- `target_p` is the only belief/reward probability map.
- The simulator has no hardware clue-probability or clue-POD layer; clue and target detection are deterministic at the cell.
- Pre-clue search strategy is implemented inside each allocator so hardware and simulator behavior can stay aligned.
