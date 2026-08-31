# CV Computational Timing Study

This is an isolated, resumable timing study. It does not write into the canonical CV core or grid/density result trees.

Run all commands from the repository root:

```powershell
python tools/cv_computational_timing.py prepare
python tools/cv_computational_timing.py smoke-test
python tools/cv_computational_timing.py run --background
python tools/cv_computational_timing.py status
python tools/cv_computational_timing.py resume --background
python tools/cv_computational_timing.py stop
python tools/cv_computational_timing.py combine
python tools/cv_computational_timing.py verify
python tools/cv_computational_timing.py analyze
```

`stop` is safe: it writes a stop marker, lets active dedicated job processes finish and write terminal records, and prevents any new job from starting. `resume` clears that marker and runs only missing jobs; completed, failed, and timed-out raw records are retained.

## Design

- Experiment 1: 100 paired layouts × 4 loads × 6 algorithms = 2,400 measured first-invocation jobs.
- Experiment 2: (50 + 100 + 50 + 25) paired missions × 6 algorithms = 1,350 measured full-mission jobs.
- Total: 3,750 measured jobs, excluding warmups.
- Loads are 5, 10, 25, and 50 targets on the 19×19, four-robot, edge-even-start CV architecture under ideal communication.
- All non-50-target jobs are attempted before any 50-target warmup or measured job begins. Every 50-target child process has a 20-minute wall-clock timeout; its terminal timeout record remains in `raw/`.
- The runner uses `floor(0.75 × physical CPU cores)` by default, forces numerical-library threads to one, and attempts a distinct CPU affinity per active child job where the OS permits it.
- On Windows, the background parent is launched hidden and each short-lived timing worker uses `pythonw.exe`; this prevents a terminal window per job.
- ACBBA, PI, and HIPC use B=2 through their own configuration. Following a documented user-directed rerun, DGA and DMCHBA use isolated no-horizon timing-study adapters; CBAA remains production single-task.

## Layout

- `manifests/`: immutable scenario, job, parameter, and configuration manifests.
- `raw/`: one atomic JSON record per terminal job; warmups are separately retained and excluded from analysis.
- `logs/`: one log per job plus the background campaign log.
- `state/progress.json`: machine-readable campaign state.
- `combined/`: regenerated flat CSV views of terminal raw records.
- `analysis/`: smoke, integrity, and condition-summary outputs.
- `verification/`: the read-only CV source audit and discrepancy report.

See `ARCHITECTURE_CHANGES.md` for the simulation-boundary and configuration record.
