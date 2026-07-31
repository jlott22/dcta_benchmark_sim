# GE Coverage 10k Distributed Worker

Use this branch on each Windows computer. Each computer runs one worker bundle
on 10 cores and writes all outputs under one directory:

`temp\ge_coverage_10k_distribution\results\worker_XX`

Use worker IDs `01` through `15`. Give each physical computer a different ID.

## Run A Worker

Open PowerShell:

```powershell
cd C:\Users\elec
git clone https://github.com/jlott22/dcta_benchmark_sim.git dcta_ge_worker_01
cd dcta_ge_worker_01
git checkout temp/ge-coverage-10k-distributed
python temp\ge_coverage_10k_distribution\run_worker.py --worker 01 --workers 10
```

If `python` is not found, use `py -3`:

```powershell
py -3 temp\ge_coverage_10k_distribution\run_worker.py --worker 01 --workers 10
```

## Pause Safely

Press:

```text
Ctrl+C
```

The runner stops active trials and keeps completed outputs. To resume, run the
same command again. Completed trial directories with valid `worker_result.json`
are skipped.

## Upload Results To GitHub

Run this after the worker finishes or after you pause it:

```powershell
python temp\ge_coverage_10k_distribution\pack_results.py --worker 01
git checkout -b temp/ge-coverage-10k-results-worker-01
git add temp/ge_coverage_10k_distribution/results/worker_01
git commit -m "Add GE 10k worker 01 results"
git push -u origin temp/ge-coverage-10k-results-worker-01
```

If `python` is not found, use `py -3` for the `pack_results.py` command.

## Copy-Paste Files

Exact commands for each worker are in:

`temp\ge_coverage_10k_distribution\commands\worker_XX_commands.txt`

Open the matching file for that computer and paste the commands into
PowerShell.
