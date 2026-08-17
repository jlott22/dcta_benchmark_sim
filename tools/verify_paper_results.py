#!/usr/bin/env python3
"""Assert the release's paper-critical values and write a compact audit CSV."""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[1]
TABLES = REPO_ROOT / "results" / "analysis" / "tables"
FIGURES = REPO_ROOT / "results" / "analysis" / "figures"
OUTPUT = TABLES / "paper_results_verification.csv"

records: list[dict[str, object]] = []


def record(check_id: str, scope: str, metric: str, observed: float, expected: float,
           source: str, tolerance: float = 0.0) -> None:
    passed = bool(np.isclose(observed, expected, rtol=0.0, atol=tolerance))
    records.append(
        {
            "check_id": check_id,
            "scope": scope,
            "metric": metric,
            "expected": expected,
            "observed": observed,
            "absolute_tolerance": tolerance,
            "status": "PASS" if passed else "FAIL",
            "source": source,
        }
    )
    if not passed:
        raise AssertionError(f"{check_id}: expected {expected}, observed {observed}")


def scalar(frame: pd.DataFrame, column: str) -> float:
    if len(frame) != 1:
        raise AssertionError(f"Expected one row for {column}; found {len(frame)}")
    return float(frame.iloc[0][column])


def main() -> None:
    eligibility_name = "grid_density_complete_block_eligibility_counts.csv"
    algorithm_name = "grid_density_complete_block_algorithm_summary.csv"
    plot_name = "grid_density_complete_block_plot_source.csv"
    status_name = "grid_density_complete_block_trial_status_summary.csv"
    trajectory_name = "trajectory_common_six_eligibility_audit.csv"
    dga_name = "dga_iteration_selection.csv"

    eligibility = pd.read_csv(TABLES / eligibility_name)
    algorithms = pd.read_csv(TABLES / algorithm_name)
    plot = pd.read_csv(TABLES / plot_name)
    status = pd.read_csv(TABLES / status_name)
    trajectory = pd.read_csv(TABLES / trajectory_name)
    dga = pd.read_csv(TABLES / dga_name)

    for mission, expected in {"CLIPS": 1560, "CV": 1544}.items():
        observed = eligibility.loc[eligibility.scenario.eq(mission), "common_block_eligible_n"].sum()
        record(f"{mission.lower()}_grid_blocks", mission, "eligible condition-trial blocks",
               observed, expected, eligibility_name)

    algorithm_targets = [
        ("CLIPS", "DMCHBA", 11, 2.84375, 4.95660507443191),
        ("CLIPS", "ACBBA", 10, 2.34375, 6.04837493027049),
        ("CV", "DGA", 17, 1.6875, 1.18276857780872),
        ("CV", "DMCHBA", 14, 1.6875, 1.34014350516198),
        ("CV", "CBAA", 1, 2.8125, 4.38333233327565),
    ]
    for mission, algorithm, leaders, rank, gap in algorithm_targets:
        row = algorithms[algorithms.scenario.eq(mission) & algorithms.algorithm.eq(algorithm)]
        prefix = f"{mission.lower()}_{algorithm.lower()}"
        record(f"{prefix}_leaders", mission, f"{algorithm} first-place conditions",
               scalar(row, "first_place_condition_count"), leaders, algorithm_name)
        record(f"{prefix}_rank", mission, f"{algorithm} mean condition rank",
               scalar(row, "mean_condition_rank"), rank, algorithm_name, 1e-12)
        record(f"{prefix}_gap", mission, f"{algorithm} mean percent above condition best",
               scalar(row, "mean_percent_above_condition_best"), gap, algorithm_name, 1e-10)

    clips34_targets = {
        "CBAA": 55.9293478260870,
        "ACBBA": 53.8913043478261,
        "PI": 57.2119565217391,
        "HIPC": 55.8777173913044,
        "DMCHBA": 54.4076086956522,
        "DGA": 61.3260869565217,
    }
    for algorithm, expected in clips34_targets.items():
        row = plot[
            plot.scenario.eq("CLIPS")
            & plot.factor.eq("grid_size")
            & plot.factor_value.eq(34)
            & plot.algorithm.eq(algorithm)
        ]
        record(f"clips_34_{algorithm.lower()}", "CLIPS", f"34-by-34 {algorithm} plotted mean",
               scalar(row, "plotted_mean"), expected, plot_name, 1e-10)

    totals = status[status.grid_size.isna() & status.scenario.isin(["CLIPS", "CV"])]
    at34 = status[status.grid_size.eq(34) & status.scenario.isin(["CLIPS", "CV"])]
    record("grid_terminal_failures", "CLIPS+CV", "terminal failures",
           totals.raw_failed_rows.sum(), 164, status_name)
    record("grid_event_caps", "CLIPS+CV", "event-cap failures",
           totals.event_cap_failure_runs.sum(), 155, status_name)
    record("grid_stagnation", "CLIPS+CV", "stagnation failures",
           totals.stagnation_failure_runs.sum(), 9, status_name)
    record("grid_34_terminal_failures", "CLIPS+CV", "34-by-34 terminal failures",
           at34.raw_failed_rows.sum(), 152, status_name)

    prds = trajectory[trajectory.method.eq("PRDS")]
    for mission, expected in {"CLIPS": 383, "CV": 500}.items():
        values = prds.loc[prds.scenario.eq(mission), "common_six_eligible_n"]
        if values.empty or values.nunique() != 1:
            raise AssertionError(f"{mission} PRDS common-six sample sizes are not constant")
        record(f"{mission.lower()}_prds_n", mission, "common-six PRDS trajectories per model/algorithm",
               values.iloc[0], expected, trajectory_name)

    selected = dga[dga.selected_for_main_benchmark.astype(bool)]
    record("dga_selected_k", "CV", "selected DGA generations",
           scalar(selected, "dga_iterations"), 25, dga_name)
    record("dga_regret", "CV", "selected mean normalized regret percent",
           scalar(selected, "mean_normalized_regret_pct"), 0.554870530209622, dga_name, 1e-12)
    record("dga_ideal_mean", "CV", "selected ideal mean maximum-agent steps",
           scalar(selected, "ideal_mean_maximum_agent_steps"), 21.8666666666667, dga_name, 1e-12)
    record("dga_bernoulli_mean", "CV", "selected Bernoulli mean maximum-agent steps",
           scalar(selected, "bernoulli_025_mean_maximum_agent_steps"), 23.1833333333333, dga_name, 1e-12)

    active_png = list(FIGURES.glob("*.png"))
    inspection_png = list((FIGURES / "inspection").glob("*.png"))
    editable_fig = list((FIGURES / "inspection").glob("*.fig"))
    sources = list((TABLES / "final_figure_sources").glob("*.csv"))
    record("active_png_count", "figures", "active PNG files", len(active_png), 5, "results/analysis/figures")
    record("inspection_png_count", "figures", "inspection PNG files", len(inspection_png), 5, "results/analysis/figures/inspection")
    record("editable_fig_count", "figures", "editable MATLAB FIG files", len(editable_fig), 5, "results/analysis/figures/inspection")
    record("figure_source_count", "figures", "dedicated source CSV files", len(sources), 5, "results/analysis/tables/final_figure_sources")

    output = pd.DataFrame.from_records(records)
    output.to_csv(OUTPUT, index=False, float_format="%.15g")
    print(f"PASS: {len(output)} paper-result checks; wrote {OUTPUT.relative_to(REPO_ROOT).as_posix()}")


if __name__ == "__main__":
    main()
