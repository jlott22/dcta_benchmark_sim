# Decentralized Task-Cell Allocation (DCTA) Benchmark Simulator

Asynchronous grid simulators for benchmarking decentralized task-cell allocation
algorithms under degraded communication. The repository contains the main
clue-informed search/coverage simulator and an isolated static known-target
visit simulator.

The simulator provides:

- world and scenario loading
- robot motion, sensing, and A* planning
- local per-robot belief maps using `target_p`
- protected collision-intent safety
- degraded communication models
- algorithm message routing
- batch CSV metrics
- pygame live visualization
- a static 10-target collaborative-visit benchmark

## Current Benchmark Assumptions

- Default grid is `19 x 19`.
- Four robots are used by default. The `edge_even` layout distributes them over
  the full left edge:
  - `00` starts at `(0, 0)`
  - `01` starts at `(0, 6)`
  - `02` starts at `(0, 12)`
  - `03` starts at `(0, 18)`
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
  CHANGE_LOG.md
  run_trials.py
  run_viewer.py
  config.py
  clue_object_generator_manhat.py
  algorithms/
    ACBBA.py
    Auction_greedy.py
    CBAA.py
    DMCHBA.py
    DGA.py
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
  tests/
    test_*.py
    run_*.sh
    combine_*.sh
known_visit_sim/
  run_trials.py
  generate_scenarios.py
  algorithms/
  comms/
  core/
  metrics/
  tests/
final_trial_500.csv
known_visit_g19_t10_n500.csv
README.md
```

`known_visit_sim/` is an isolated fork and does not import `benchmark_sim` at
runtime. This keeps the secondary known-target evaluation from changing the
main clue-informed benchmark.

Generated result directories at the repository root (`clue_500_combined/`,
`coverage_100_combined/`, and `sensitivity_test_results/`) contain study data,
not simulator source.

## Requirements and Setup

- Python 3.10 or newer (the current repository is exercised with Python 3.13).
- No third-party package is required for headless batch runs or unit tests.
- `pygame` is optional and only required for the live viewer.
- Bash is required for the study-driver scripts in `benchmark_sim/tests/`.

Run module commands from the repository root, the directory containing this
README and the `benchmark_sim/` package:

```powershell
python -m benchmark_sim.run_trials --help
python -m unittest discover -s benchmark_sim/tests -v
python -m unittest discover -s known_visit_sim/tests -v
```

## Implemented Algorithms

Built-in allocator modules currently include:

- `benchmark_sim.algorithms.ACBBA:ACBBAAllocator`
- `benchmark_sim.algorithms.CBAA:CBAAAllocator`
- `benchmark_sim.algorithms.DMCHBA:DMCHBAAllocator`
- `benchmark_sim.algorithms.DGA:DGAAllocator`
- `benchmark_sim.algorithms.PI:PIAllocator`
- `benchmark_sim.algorithms.HIPC:HIPCAllocator`
- `benchmark_sim.algorithms.Auction_greedy:AuctionGreedyAllocator`

The CLI accepts allocator classes in `module.path:ClassName` format. Algorithm display names can be overridden with `--algorithm-name`.

## Communication Models

`--comm-model` supports:

- `ideal` - all non-protected messages are delivered.
- `bernoulli` - independent receiver-side drops. `--comm-level` is drop probability.
- `gilbert_elliot` - all-or-nothing two-state burst-loss model. `--comm-level`
  sets GOOD-state persistence (`pGG`); BAD-state persistence is `1 - pGG`.
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

The repository root includes `final_trial_500.csv` (500 trials).

`benchmark_sim/clue_object_generator_manhat.py` can generate a fixed object
list or regenerate clue sets around that list. Its current controls
(`COMMAND`, grid size, trial count, clue count, seed, and output path) are
constants at the top of the file; it does not currently expose a CLI.

## Running Batch Trials

Example ACBBA run (PowerShell):

```powershell
python -m benchmark_sim.run_trials `
  --scenario-file final_trial_500.csv `
  --algorithm benchmark_sim.algorithms.ACBBA:ACBBAAllocator `
  --comm-model bernoulli `
  --comm-level 0.10 `
  --max-trials 10 `
  --out-dir runs/acbba_bernoulli_010
```

Example DGA run:

```powershell
python -m benchmark_sim.run_trials `
  --scenario-file final_trial_500.csv `
  --algorithm benchmark_sim.algorithms.DGA:DGAAllocator `
  --comm-model ideal `
  --max-trials 10 `
  --out-dir runs/dga_ideal
```

Coverage mode does not require a scenario file:

```powershell
python -m benchmark_sim.run_trials `
  --trial-mode coverage `
  --num-trials 5 `
  --algorithm benchmark_sim.algorithms.Auction_greedy:AuctionGreedyAllocator `
  --comm-model ideal `
  --out-dir runs/ag_coverage
```

Useful options:

- `--trial-mode clue_search|coverage`
- `--scenario-file <path>`
- `--max-trials <n>`
- `--num-trials <n>` for coverage mode
- `--seed <int>`
- `--grid-size <n>`
- `--num-robots <n>` (must not exceed grid size for `edge_even`)
- `--robot-start-layout edge_even`
- `--condition-id <label>`
- `--target-cells-per-robot <float>` and `--actual-cells-per-robot <float>`
- `--target-decay-exp <float>`
- `--commitment-horizon <n>` overrides the default for ACBBA, PI, HIPC,
  DMCHBA, and DGA; CBAA ignores it
- `--max-candidate-cells <n|all>` controls the candidate prefilter for CBAA,
  ACBBA, PI, HIPC, DMCHBA, and DGA
- `--out-dir <path>`

Use `python -m benchmark_sim.run_trials --help` as the authoritative CLI
reference.

## Static Collaborative Known-Target Visit

`known_visit_sim` is the secondary pure task-allocation/routing benchmark. All
task locations are known to every robot at initialization, there are no clues
or hidden targets, and world truth ends a trial when every task cell has been
visited. The bundled `known_visit_g19_t10_n500.csv` contains 500 paired
scenarios with 10 unique task cells on a 19x19 grid, generated with seed
`20260630`; task cells do not overlap the default robot starts.

Generate another paired scenario file:

```powershell
python -m known_visit_sim.generate_scenarios `
  --grid-size 19 `
  --num-robots 4 `
  --num-targets 10 `
  --num-trials 500 `
  --robot-start-layout edge_even `
  --seed 20260630 `
  --output known_visit_g19_t10_n500.csv
```

Run one algorithm/communication condition:

```powershell
python -m known_visit_sim.run_trials `
  --scenario-file known_visit_g19_t10_n500.csv `
  --algorithm DGA `
  --comm-model ideal `
  --grid-size 19 `
  --num-robots 4 `
  --robot-start-layout edge_even `
  --condition-id known_visit_ideal `
  --out-dir runs/known_visit/dga_ideal
```

Unlike the main simulator, `--algorithm` accepts a built-in short name:
`CBAA`, `ACBBA`, `PI`, `HIPC`, `DMCHBA`, `DGA`, or `AuctionGreedy`. It supports
the same four communication-model names and also exposes
`--commitment-horizon` and `--max-candidate-cells`.

Known-visit communication deliberately has only droppable `state` messages
and protected `collision_intent` messages at the core level. A robot infers a
peer's task completion from a delivered peer location; there is no dedicated
task-complete message. World truth records completion independently, so trial
termination does not require local consensus.

Each known-visit run writes:

```text
trial_summary.csv
system_performance.csv
robot_performance.csv
target_performance.csv
config_used.json
```

Known-visit metrics include completed-target count, completion status and
simulation time, duplicate target visits/target conflicts, task-cell revisits,
total and maximum robot steps, unique cells visited, replans, communication
counts, messages per completed target, workload Gini values, and per-target
first-finder/completion records.

## Running The Live Viewer

The viewer requires pygame:

```powershell
pip install pygame
```

Run:

```powershell
python -m benchmark_sim.run_viewer `
  --scenario-file final_trial_500.csv `
  --algorithm benchmark_sim.algorithms.ACBBA:ACBBAAllocator `
  --comm-model bernoulli `
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
- `grid_size`
- `grid_cells`
- `robot_count`
- `target_cells_per_robot`
- `actual_cells_per_robot`
- `condition_id`
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

## Tests and Experiment Drivers

Run the complete unit/integration suite from the repository root:

```powershell
python -m unittest discover -s benchmark_sim/tests -v
python -m unittest discover -s known_visit_sim/tests -v
```

The `benchmark_sim/tests/` directory also contains Bash drivers for the current
experiments, including:

- `run_dga_final500_by_condition.sh`: DGA over the 500-trial scenario for the
  configured ideal, Bernoulli, Gilbert-Elliot, and Rayleigh-style conditions.
- `run_dga_iteration_sensitivity.sh` and
  `run_dga_iteration_ideal_missing_repair.sh`: DGA iteration studies and repair.
- `run_grid_density_sensitivity.sh`: grid-size/robot-density study with
  partitioned Python workers.
- `combine_*.sh` and `combine_grid_density_sensitivity.py`: validation and
  aggregation of raw study outputs.

Run these scripts from a Bash environment. Some older/final-run drivers contain
a machine-specific default repository path; set `DCTA_REPO_ROOT` where the
script supports it or inspect the header before launching a long run.

## Notes

- Metric exports are CSV-only; `--no-parquet` remains as a deprecated compatibility flag.
- `target_p` is the only belief/reward probability map.
- The simulator has no hardware clue-probability or clue-POD layer; clue and target detection are deterministic at the cell.
- Pre-clue search strategy is implemented inside each allocator so hardware and simulator behavior can stay aligned.
