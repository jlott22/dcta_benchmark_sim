# Decentralized Task-Cell Allocation Benchmark

This repository contains the simulators, scenarios, raw combined results, analysis code, and finalized figures for *Benchmarking Decentralized Multi-Robot Task Allocation in Search Missions Under Degraded Communication*.

The benchmark evaluates six decentralized task-allocation algorithms—CBAA, ACBBA, PI, HIPC, DMCHBA, and DGA—in three grid missions:

- Clue-Informed Probabilistic Search (CLIPS)
- Full Grid Search (FGS)
- Collaborative Visit (CV)

The release preserves the recorded raw CSV values. Generated tables and paper figures can be rebuilt from those files without modifying them.

## Clone and set up

Two canonical robot-performance CSVs are stored with Git LFS. Install Git LFS before cloning or run `git lfs pull` after cloning.

```bash
git lfs install
git clone <repository-url>
cd dcta_benchmark_sim
python -m venv .venv
# Linux/macOS: source .venv/bin/activate
# Windows PowerShell: .venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

Python 3.10 or newer is supported. The simulators themselves use the standard library; NumPy and pandas are required by the publication analysis. Install `pygame` separately only for the optional live viewer.

MATLAB R2025b with Statistics and Machine Learning Toolbox is recommended for exact figure and statistical-table regeneration. The scripts use functions including `tiedrank`, `tinv`, `signrank`, `ranksum`, and `chi2cdf`.

## Repository layout

```text
benchmark_sim/       CLIPS and FGS simulator, algorithms, and tests
known_visit_sim/     CV simulator, algorithms, and tests
scenarios/           deterministic paper scenarios
results/             canonical raw/combined datasets
  analysis/          retained analysis and figure-generation code
    tables/          derived numerical results and provenance
    figures/         the five finalized paper figures
archive_private/     ignored local preservation area for superseded artifacts
```

See [results/README.md](results/README.md) for the data inventory and [REPRODUCIBILITY.md](REPRODUCIBILITY.md) for the exact analysis order, eligibility rules, and verification targets. A SHA-256 inventory of the release data is written to `results/RELEASE_MANIFEST.csv`.

## Run a trial

Run commands from the repository root. For a CLIPS trial:

```bash
python -m benchmark_sim.run_trials \
  --trial-mode clue_search \
  --algorithm benchmark_sim.algorithms.DGA:DGAAllocator \
  --algorithm-name DGA \
  --scenario-file scenarios/final_trial_500.csv \
  --max-trials 1 \
  --comm-model gilbert_elliott \
  --comm-level 0.75 \
  --out-dir results/example_clue_trial
```

For a CV trial:

```bash
python -m known_visit_sim.run_trials \
  --scenario-file scenarios/known_visit_g19_t10_n500.csv \
  --algorithm known_visit_sim.algorithms.DGA:DGAAllocator \
  --algorithm-name DGA \
  --comm-model ideal \
  --out-dir results/example_known_target_trial
```

Historical `out_dir`, `source_out_dir`, and `source_command` fields in raw CSVs are provenance strings from the machines that ran the experiments; they are not live paths required by this checkout.

## Verify the simulators

```bash
python -m unittest discover -s benchmark_sim/tests -v
python -m unittest discover -s known_visit_sim/tests -v
```

## Final paper artifacts

The five authoritative 600-dpi PNGs are in `results/analysis/figures/`. Matching editable MATLAB `.fig` files and visual-inspection copies are in `results/analysis/figures/inspection/`. Every plotted value has a dedicated CSV in `results/analysis/tables/final_figure_sources/`.

Superseded files are not part of the public release tree. During local cleanup they are preserved under `archive_private/`, which is intentionally ignored by Git except for its explanatory README.
