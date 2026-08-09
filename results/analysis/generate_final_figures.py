"""Generate the paper's validated final DCTA figures.

The condition plots use only fully paired trials: all six algorithms must have
an eligible, finite observation for the same scenario, communication model,
degradation level, and trial ID.  Percentage deviations are calculated within
each paired trial before they are averaged.  Formal significance cells are
read from the validated MATLAB analysis output, which applies paired Wilcoxon
tests and Holm adjustment within each six-algorithm family.
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib import colors as mpl_colors
from matplotlib.lines import Line2D
from matplotlib.patches import Patch, Rectangle


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
TABLE_DIR = SCRIPT_DIR / "tables"
FIGURE_DIR = SCRIPT_DIR / "figures"

ALGORITHMS = ["CBAA", "ACBBA", "PI", "HIPC", "DMCHBA", "DGA"]
ALGORITHM_COLORS = {
    algorithm: plt.get_cmap("tab10")(index)
    for index, algorithm in enumerate(ALGORITHMS)
}
MODELS = ["bernoulli", "gilbert_elliott", "rayleigh_style"]
MODEL_LABELS = {
    "bernoulli": "Bernoulli",
    "gilbert_elliott": "Gilbert-Elliott",
    "rayleigh_style": "Rayleigh-style",
}
MODEL_MARKERS = {"bernoulli": "o", "gilbert_elliott": "s", "rayleigh_style": "^"}
LEVELS = [5, 10, 20, 30, 40, 50, 60, 70]


@dataclass(frozen=True)
class ScenarioSpec:
    key: str
    title: str
    short_title: str
    folder: Path
    max_steps_column: str
    kind: str


SCENARIOS = [
    ScenarioSpec(
        "Bayesian clue-informed search",
        "Bayesian Search",
        "Bayes.",
        REPO_ROOT / "results" / "clue_search_core_500" / "combined",
        "max_steps_any_robot",
        "bayesian",
    ),
    ScenarioSpec(
        "Coverage area search",
        "Coverage",
        "Cover.",
        REPO_ROOT / "results" / "coverage_core_100" / "combined",
        "max_steps_any_robot",
        "coverage",
    ),
    ScenarioSpec(
        "Collaborative known-target visit",
        "Collaborative Visit",
        "Visit",
        REPO_ROOT / "results" / "known_target_visit_core_500" / "combined",
        "max_robot_steps",
        "visit",
    ),
]


def _canonical_level(value: object, model: str) -> str:
    if model == "ideal" or pd.isna(value) or not str(value).strip():
        return "ideal"
    text = str(value).strip().lower()
    try:
        return f"{float(text):.10g}"
    except ValueError:
        return text


def _nominal_degradation(model: str, raw: str, label: str) -> float:
    if model == "ideal":
        return 0.0
    if model == "bernoulli":
        return float(round(100 * float(raw)))
    if model == "gilbert_elliott":
        try:
            return float(round(100 * (1 - float(raw))))
        except ValueError:
            match = re.search(r"drop_0_(\d+)", label.lower())
            if not match:
                raise ValueError(f"Cannot parse Gilbert-Elliott degradation from {label!r}")
            return float(match.group(1))
    if model == "rayleigh_style":
        raw_to_pct = {
            -59.40: 5,
            -56.04: 10,
            -52.15: 20,
            -49.17: 30,
            -46.04: 40,
            -42.16: 50,
            -37.79: 60,
            -32.58: 70,
        }
        numeric = float(raw)
        nearest = min(raw_to_pct, key=lambda candidate: abs(candidate - numeric))
        if abs(nearest - numeric) >= 0.02:
            raise ValueError(f"Unrecognized Rayleigh level: {raw!r}")
        return float(raw_to_pct[nearest])
    raise ValueError(f"Unrecognized communication model: {model!r}")


def normalize_conditions(frame: pd.DataFrame) -> pd.DataFrame:
    frame = frame.copy()
    frame["trial_id"] = frame["trial_id"].astype("string")
    frame["algorithm"] = (
        frame["algorithm"]
        .astype("string")
        .str.strip()
        .str.upper()
        .replace({"A-CBBA": "ACBBA", "D-MCHBA": "DMCHBA"})
    )
    frame["comm_model"] = frame["comm_model"].astype("string").str.strip().str.lower()
    labels = (
        frame["comm_label"].astype("string").fillna("")
        if "comm_label" in frame.columns
        else pd.Series("", index=frame.index, dtype="string")
    )
    frame["comm_level_raw"] = [
        _canonical_level(value, model)
        for value, model in zip(frame["comm_level"], frame["comm_model"], strict=True)
    ]
    frame["comm_level_pct"] = [
        _nominal_degradation(model, raw, str(label))
        for model, raw, label in zip(
            frame["comm_model"], frame["comm_level_raw"], labels, strict=True
        )
    ]
    return frame


def load_scenario(spec: ScenarioSpec) -> pd.DataFrame:
    dtype = {"trial_id": "string", "comm_level": "string"}
    system = normalize_conditions(
        pd.read_csv(spec.folder / "system_performance.csv", dtype=dtype, low_memory=False)
    )
    trial = normalize_conditions(
        pd.read_csv(spec.folder / "trial_summary.csv", dtype=dtype, low_memory=False)
    )
    keys = ["trial_id", "algorithm", "comm_model", "comm_level_raw"]
    if system.duplicated(keys).any():
        raise ValueError(f"{spec.title}: duplicate normalized system keys")
    if trial.duplicated(keys).any():
        raise ValueError(f"{spec.title}: duplicate normalized trial keys")

    trial_columns = keys + ["trial_status"]
    if spec.kind == "bayesian":
        trial_columns.append("first_clue_robot")
    trial_keep = trial[trial_columns].rename(columns={"trial_status": "trial_trial_status"})
    data = system.merge(trial_keep, on=keys, how="left", validate="one_to_one")

    eligible = (
        data["trial_status"].astype("string").str.lower().eq("completed")
        & data["trial_trial_status"].astype("string").str.lower().eq("completed")
    )
    if spec.kind == "bayesian":
        eligible &= data["first_clue_robot"].astype("string").fillna("").str.strip().ne("")
    elif spec.kind == "visit":
        eligible &= (
            data["all_targets_visited"].astype("string").str.lower().eq("true")
            & pd.to_numeric(data["completed_target_count"], errors="coerce").eq(
                pd.to_numeric(data["target_count"], errors="coerce")
            )
        )
    data["base_eligible"] = eligible
    data["max_agent_steps"] = pd.to_numeric(data[spec.max_steps_column], errors="coerce")
    data["total_team_steps_metric"] = pd.to_numeric(data["total_team_steps"], errors="coerce")
    messages = pd.to_numeric(data["messages_sent_total"], errors="coerce")
    data["team_messages_per_step"] = messages / data["total_team_steps_metric"]
    return data


def paired_matrix(data: pd.DataFrame, model: str, level: int, metric_column: str) -> pd.DataFrame:
    subset = data[
        data["base_eligible"]
        & data["comm_model"].eq(model)
        & data["comm_level_pct"].eq(float(level))
    ][["trial_id", "algorithm", metric_column]].copy()
    subset[metric_column] = pd.to_numeric(subset[metric_column], errors="coerce")
    if subset.duplicated(["trial_id", "algorithm"]).any():
        raise ValueError(f"Duplicate paired rows for {model} {level} {metric_column}")
    matrix = subset.pivot(index="trial_id", columns="algorithm", values=metric_column)
    matrix = matrix.reindex(columns=ALGORITHMS).replace([np.inf, -np.inf], np.nan).dropna()
    return matrix.astype(float)


def paired_deviation(matrix: pd.DataFrame) -> pd.DataFrame:
    field = matrix.mean(axis=1)
    if (field == 0).any():
        raise ValueError("Zero six-algorithm field mean encountered")
    return matrix.div(field, axis=0).sub(1).mul(100)


def normal_mean_ci(values: pd.Series) -> tuple[float, float, float]:
    clean = values.dropna().to_numpy(dtype=float)
    mean = float(np.mean(clean))
    if clean.size <= 1:
        return mean, mean, mean
    half_width = 1.959963984540054 * float(np.std(clean, ddof=1)) / math.sqrt(clean.size)
    return mean, mean - half_width, mean + half_width


def build_condition_summary(
    scenario_data: dict[str, pd.DataFrame], metric_results: pd.DataFrame
) -> pd.DataFrame:
    metric_columns = {
        "max_agent_steps": "max_agent_steps",
        "total_team_steps": "total_team_steps_metric",
        "team_messages_per_step": "team_messages_per_step",
    }
    rows: list[dict[str, object]] = []
    for spec in SCENARIOS:
        data = scenario_data[spec.key]
        for metric_name, metric_column in metric_columns.items():
            for model in MODELS:
                for level in LEVELS:
                    matrix = paired_matrix(data, model, level, metric_column)
                    expected_rows = metric_results[
                        metric_results["scenario"].eq(spec.key)
                        & metric_results["metric"].eq(metric_name)
                        & metric_results["result_type"].eq("condition_metric")
                        & metric_results["comm_model"].eq(model)
                        & metric_results["comm_level_pct"].eq(level)
                    ]
                    expected_counts = expected_rows["eligible_paired_trials"].dropna().unique()
                    if len(expected_counts) != 1 or int(expected_counts[0]) != len(matrix):
                        raise ValueError(
                            f"Paired-count mismatch for {spec.title}, {metric_name}, "
                            f"{model}, {level}: raw={len(matrix)}, table={expected_counts}"
                        )
                    deviations = paired_deviation(matrix)
                    for algorithm in ALGORITHMS:
                        mean_dev, ci_low, ci_high = normal_mean_ci(deviations[algorithm])
                        rows.append(
                            {
                                "scenario": spec.key,
                                "metric": metric_name,
                                "comm_model": model,
                                "comm_level_pct": level,
                                "algorithm": algorithm,
                                "eligible_paired_trials": len(matrix),
                                "raw_mean": float(matrix[algorithm].mean()),
                                "mean_paired_deviation_pct": mean_dev,
                                "ci95_low": ci_low,
                                "ci95_high": ci_high,
                                "ci_method": "normal_approximation_on_paired_trial_deviations",
                            }
                        )
    return pd.DataFrame(rows)


def _is_true(value: object) -> bool:
    if isinstance(value, (bool, np.bool_)):
        return bool(value)
    return str(value).strip().lower() in {"true", "1"}


def pair_outcome(
    stats: pd.DataFrame,
    scenario: str,
    metric: str,
    model: str,
    level: int,
    first: str,
    second: str,
) -> str:
    rows = stats[
        stats["scenario"].eq(scenario)
        & stats["metric"].eq(metric)
        & stats["result_type"].eq("condition_metric")
        & stats["comm_model"].eq(model)
        & stats["comm_level_pct"].eq(level)
        & stats["test_type"].eq("wilcoxon_pairwise")
        & (
            (stats["algorithm_a"].eq(first) & stats["algorithm_b"].eq(second))
            | (stats["algorithm_a"].eq(second) & stats["algorithm_b"].eq(first))
        )
    ]
    if len(rows) != 1:
        raise ValueError(
            f"Expected one statistical row for {scenario}, {metric}, {model}, "
            f"{level}, {first}-{second}; found {len(rows)}"
        )
    row = rows.iloc[0]
    if not _is_true(row["reject_holm_0_05"]):
        return "NS"
    return str(row["algorithm_a"] if row["algorithm_a_mean"] < row["algorithm_b_mean"] else row["algorithm_b"])


def draw_outcome_strip(
    axis: plt.Axes,
    stats: pd.DataFrame,
    scenario: str,
    metric: str,
    model: str,
    pairs: list[tuple[str, str]],
    show_x_labels: bool,
) -> None:
    for row_index, (first, second) in enumerate(pairs):
        for column_index, level in enumerate(LEVELS):
            outcome = pair_outcome(stats, scenario, metric, model, level, first, second)
            color = "#d0d0d0" if outcome == "NS" else ALGORITHM_COLORS[outcome]
            axis.add_patch(
                Rectangle(
                    (column_index - 0.5, row_index - 0.5),
                    1,
                    1,
                    facecolor=color,
                    edgecolor="white",
                    linewidth=0.8,
                )
            )
    axis.set_xlim(-0.5, len(LEVELS) - 0.5)
    axis.set_ylim(len(pairs) - 0.5, -0.5)
    axis.set_yticks(range(len(pairs)), [f"{a}–{b}" for a, b in pairs], fontsize=7)
    axis.set_xticks(range(len(LEVELS)), LEVELS if show_x_labels else [""] * len(LEVELS))
    axis.tick_params(axis="x", length=0, labelsize=7)
    axis.tick_params(axis="y", length=0)
    for spine in axis.spines.values():
        spine.set_visible(False)


MAX_STEP_PAIRS = {
    "Bayesian clue-informed search": [("ACBBA", "DMCHBA")],
    "Coverage area search": [
        ("ACBBA", "PI"),
        ("ACBBA", "HIPC"),
        ("ACBBA", "DMCHBA"),
        ("PI", "HIPC"),
        ("PI", "DMCHBA"),
        ("HIPC", "DMCHBA"),
    ],
    "Collaborative known-target visit": [("DMCHBA", "DGA")],
}


def plot_max_steps(
    spec: ScenarioSpec, summary: pd.DataFrame, stats: pd.DataFrame, output_path: Path
) -> None:
    pairs = MAX_STEP_PAIRS[spec.key]
    strip_ratio = max(0.6, 0.30 * len(pairs))
    figure = plt.figure(figsize=(7.1, 9.1 + 0.35 * max(0, len(pairs) - 1)))
    grid = figure.add_gridspec(
        6,
        1,
        height_ratios=[4.0, strip_ratio, 4.0, strip_ratio, 4.0, strip_ratio],
        hspace=0.08,
    )
    plot_axes: list[plt.Axes] = []
    for model_index, model in enumerate(MODELS):
        axis = figure.add_subplot(grid[2 * model_index, 0], sharex=plot_axes[0] if plot_axes else None)
        plot_axes.append(axis)
        model_rows = summary[
            summary["scenario"].eq(spec.key)
            & summary["metric"].eq("max_agent_steps")
            & summary["comm_model"].eq(model)
        ]
        for algorithm in ALGORITHMS:
            rows = model_rows[model_rows["algorithm"].eq(algorithm)].set_index("comm_level_pct").loc[LEVELS]
            y = rows["mean_paired_deviation_pct"].to_numpy(float)
            low = rows["ci95_low"].to_numpy(float)
            high = rows["ci95_high"].to_numpy(float)
            axis.plot(
                range(len(LEVELS)),
                y,
                marker="o",
                linewidth=1.5 if algorithm not in {"DMCHBA", "DGA"} else 2.3,
                markersize=4.5,
                color=ALGORITHM_COLORS[algorithm],
                label=algorithm,
            )
            axis.fill_between(range(len(LEVELS)), low, high, color=ALGORITHM_COLORS[algorithm], alpha=0.08)
        axis.axhline(0, color="black", linestyle="--", linewidth=1)
        axis.text(0.01, 0.92, MODEL_LABELS[model], transform=axis.transAxes, fontsize=12, weight="bold", va="top")
        axis.grid(alpha=0.18)
        axis.tick_params(axis="x", labelbottom=False)
        strip_axis = figure.add_subplot(grid[2 * model_index + 1, 0])
        draw_outcome_strip(
            strip_axis,
            stats,
            spec.key,
            "max_agent_steps",
            model,
            pairs,
            show_x_labels=model_index == len(MODELS) - 1,
        )
    handles = [Line2D([0], [0], color=ALGORITHM_COLORS[a], marker="o", label=a) for a in ALGORITHMS]
    figure.subplots_adjust(left=0.25, right=0.98, top=0.88, bottom=0.07)
    figure.legend(handles=handles, loc="upper center", ncol=3, frameon=False, bbox_to_anchor=(0.56, 0.995))
    figure.supylabel("Mean paired max-step deviation (%)", x=0.025, fontsize=11)
    figure.supxlabel("Communication degradation level (%)", y=0.005, fontsize=11)
    figure.suptitle(f"{spec.title}: maximum steps by any robot", y=0.925, fontsize=13, weight="bold")
    figure.savefig(output_path, dpi=350, bbox_inches="tight", facecolor="white")
    plt.close(figure)


def plot_total_steps_summary(summary: pd.DataFrame, output_path: Path) -> None:
    figure, axes = plt.subplots(3, 1, figsize=(7.0, 10.2), sharex=True)
    offsets = [-0.20, 0.0, 0.20]
    for axis, spec in zip(axes, SCENARIOS, strict=True):
        y_positions = np.arange(len(ALGORITHMS))
        for offset, model in zip(offsets, MODELS, strict=True):
            means, lows, highs = [], [], []
            for algorithm in ALGORITHMS:
                rows = summary[
                    summary["scenario"].eq(spec.key)
                    & summary["metric"].eq("total_team_steps")
                    & summary["comm_model"].eq(model)
                    & summary["algorithm"].eq(algorithm)
                ].set_index("comm_level_pct").loc[LEVELS]
                values = rows["mean_paired_deviation_pct"].to_numpy(float)
                means.append(float(values.mean()))
                lows.append(float(values.min()))
                highs.append(float(values.max()))
            means_array = np.asarray(means)
            xerr = np.vstack([means_array - np.asarray(lows), np.asarray(highs) - means_array])
            axis.errorbar(
                means_array,
                y_positions + offset,
                xerr=xerr,
                fmt=MODEL_MARKERS[model],
                markersize=7,
                capsize=3,
                linewidth=1.4,
                color=plt.get_cmap("tab10")(MODELS.index(model)),
                label=MODEL_LABELS[model],
            )
        axis.axvline(0, color="black", linestyle="--", linewidth=1)
        axis.set_yticks(y_positions, ALGORITHMS)
        axis.invert_yaxis()
        axis.set_title(spec.title, fontsize=12, weight="bold")
        axis.grid(axis="x", alpha=0.18)
    axes[0].legend(loc="lower center", bbox_to_anchor=(0.5, 1.16), ncol=3, frameon=False)
    figure.supxlabel("Mean total-step deviation from paired trial field (%)", y=0.015, fontsize=11)
    figure.savefig(output_path, dpi=350, bbox_inches="tight", facecolor="white")
    plt.close(figure)


TOTAL_STEP_PAIRS = {
    "Bayesian clue-informed search": [("ACBBA", "DMCHBA")],
    "Coverage area search": [
        ("CBAA", "PI"),
        ("CBAA", "HIPC"),
        ("CBAA", "DMCHBA"),
        ("PI", "HIPC"),
        ("PI", "DMCHBA"),
        ("HIPC", "DMCHBA"),
    ],
    "Collaborative known-target visit": [("HIPC", "DGA")],
}


def plot_total_steps_wilcoxon(stats: pd.DataFrame, output_path: Path) -> None:
    row_specs: list[tuple[ScenarioSpec, tuple[str, str]]] = []
    for spec in SCENARIOS:
        row_specs.extend((spec, pair) for pair in TOTAL_STEP_PAIRS[spec.key])
    figure, axis = plt.subplots(figsize=(9.0, 6.6))
    for row_index, (spec, (first, second)) in enumerate(row_specs):
        for model_index, model in enumerate(MODELS):
            for level_index, level in enumerate(LEVELS):
                column = model_index * len(LEVELS) + level_index
                outcome = pair_outcome(
                    stats, spec.key, "total_team_steps", model, level, first, second
                )
                color = "#d0d0d0" if outcome == "NS" else ALGORITHM_COLORS[outcome]
                axis.add_patch(
                    Rectangle(
                        (column - 0.48, row_index - 0.38),
                        0.94,
                        0.76,
                        facecolor=color,
                        edgecolor="white",
                        linewidth=0.6,
                    )
                )
    axis.set_xlim(-0.5, len(MODELS) * len(LEVELS) - 0.5)
    axis.set_ylim(len(row_specs) - 0.5, -1.25)
    axis.set_yticks(
        range(len(row_specs)),
        [f"{spec.short_title} {a}–{b}" for spec, (a, b) in row_specs],
        fontsize=8,
    )
    axis.set_xticks([])
    axis.tick_params(axis="y", length=0)
    for boundary in [len(LEVELS) - 0.5, 2 * len(LEVELS) - 0.5]:
        axis.axvline(boundary, color="black", linewidth=1)
    for model_index, model in enumerate(MODELS):
        center = model_index * len(LEVELS) + (len(LEVELS) - 1) / 2
        axis.text(center, -0.95, MODEL_LABELS[model], ha="center", va="center", weight="bold")
    bayes_end = len(TOTAL_STEP_PAIRS[SCENARIOS[0].key]) - 0.5
    coverage_end = bayes_end + len(TOTAL_STEP_PAIRS[SCENARIOS[1].key])
    axis.axhline(bayes_end, color="black", linewidth=0.8)
    axis.axhline(coverage_end, color="black", linewidth=0.8)
    for spine in axis.spines.values():
        spine.set_visible(False)
    legend_handles = [Patch(facecolor=ALGORITHM_COLORS[a], label=a) for a in ALGORITHMS]
    legend_handles.append(Patch(facecolor="#d0d0d0", label="NS"))
    axis.legend(handles=legend_handles, loc="lower center", bbox_to_anchor=(0.5, 1.02), ncol=4, frameon=False)
    figure.text(
        0.5,
        0.015,
        "Within each model, cells progress from 5% to 70% degradation.",
        ha="center",
        fontsize=9,
    )
    figure.savefig(output_path, dpi=350, bbox_inches="tight", facecolor="white")
    plt.close(figure)


def plot_communication_tradeoff(summary: pd.DataFrame, output_path: Path) -> None:
    figure, axes = plt.subplots(1, 3, figsize=(10.0, 3.7), sharey=True)
    for axis, spec in zip(axes, SCENARIOS, strict=True):
        for algorithm in ALGORITHMS:
            for model in MODELS:
                max_rows = summary[
                    summary["scenario"].eq(spec.key)
                    & summary["metric"].eq("max_agent_steps")
                    & summary["comm_model"].eq(model)
                    & summary["algorithm"].eq(algorithm)
                ].set_index("comm_level_pct").loc[LEVELS]
                message_rows = summary[
                    summary["scenario"].eq(spec.key)
                    & summary["metric"].eq("team_messages_per_step")
                    & summary["comm_model"].eq(model)
                    & summary["algorithm"].eq(algorithm)
                ].set_index("comm_level_pct").loc[LEVELS]
                axis.scatter(
                    message_rows["raw_mean"].mean(),
                    max_rows["mean_paired_deviation_pct"].mean(),
                    s=58,
                    marker=MODEL_MARKERS[model],
                    color=ALGORITHM_COLORS[algorithm],
                    edgecolor="none",
                )
        axis.axhline(0, color="black", linestyle="--", linewidth=1)
        axis.set_title(spec.short_title.replace(".", ""), fontsize=12, weight="bold")
        axis.set_xlabel("Messages per team step")
        axis.grid(alpha=0.16)
    axes[0].set_ylabel("Mean paired max-step deviation (%)")
    algorithm_handles = [
        Line2D([0], [0], marker="o", linestyle="none", color=ALGORITHM_COLORS[a], label=a, markersize=7)
        for a in ALGORITHMS
    ]
    model_handles = [
        Line2D([0], [0], marker=MODEL_MARKERS[m], linestyle="none", color="black", label=MODEL_LABELS[m], markersize=7)
        for m in MODELS
    ]
    figure.legend(
        handles=algorithm_handles + model_handles,
        loc="upper center",
        ncol=5,
        frameon=False,
        bbox_to_anchor=(0.5, 1.10),
    )
    figure.savefig(output_path, dpi=350, bbox_inches="tight", facecolor="white")
    plt.close(figure)


def plot_prds_heatmap(metric_results: pd.DataFrame, output_path: Path) -> None:
    metric_groups = [
        ("Max steps", "max_agent_steps"),
        ("Total steps", "total_team_steps"),
        ("Messages/team step", "team_messages_per_step"),
        ("Redundant effort", "scenario_specific_redundancy"),
    ]
    values = np.full((len(ALGORITHMS), len(metric_groups) * len(SCENARIOS)), np.nan)
    column_labels: list[str] = []
    for group_index, (_, metric_name) in enumerate(metric_groups):
        for scenario_index, spec in enumerate(SCENARIOS):
            column = group_index * len(SCENARIOS) + scenario_index
            actual_metric = metric_name
            if metric_name == "scenario_specific_redundancy":
                actual_metric = "duplicate_target_visits" if spec.kind == "visit" else "system_cell_revisits"
            subset = metric_results[
                metric_results["scenario"].eq(spec.key)
                & metric_results["metric"].eq(actual_metric)
                & metric_results["result_type"].eq("prds")
                & metric_results["comm_model"].isin(MODELS)
            ]
            for algorithm_index, algorithm in enumerate(ALGORITHMS):
                rows = subset[subset["algorithm"].eq(algorithm)]
                if len(rows) != len(MODELS):
                    raise ValueError(
                        f"Expected three PRDS rows for {spec.title}, {actual_metric}, {algorithm}; "
                        f"found {len(rows)}"
                    )
                values[algorithm_index, column] = rows["mean_value"].mean()
            column_labels.append(spec.short_title)

    # Lower PRDS is preferable, so use a semantically ordered palette:
    # green = lower/better, red = higher/worse. Extra intermediate stops and
    # padded per-column limits keep the transitions gradual and avoid forcing
    # every column's extrema to the most saturated endpoint colors.
    cmap = mpl_colors.LinearSegmentedColormap.from_list(
        "green_good_red_bad",
        ["#2f7d32", "#78bd78", "#fff3b0", "#ef9a6b", "#b23a3a"],
        N=256,
    )
    rgba = np.zeros((values.shape[0], values.shape[1], 4), dtype=float)
    for column in range(values.shape[1]):
        col_values = values[:, column]
        col_min = float(np.min(col_values))
        col_max = float(np.max(col_values))
        padding = max(0.05 * (col_max - col_min), 1e-9)
        normalizer = mpl_colors.Normalize(vmin=col_min - padding, vmax=col_max + padding)
        rgba[:, column, :] = cmap(normalizer(col_values))

    figure, axis = plt.subplots(figsize=(12.2, 4.0))
    axis.imshow(rgba, aspect="auto")
    axis.set_yticks(range(len(ALGORITHMS)), ALGORITHMS)
    axis.set_xticks(range(len(column_labels)), column_labels, fontsize=8)
    axis.tick_params(length=0)
    for row in range(values.shape[0]):
        for column in range(values.shape[1]):
            axis.text(column, row, f"{values[row, column]:.2f}", ha="center", va="center", fontsize=8, color="black")
    for boundary in [2.5, 5.5, 8.5]:
        axis.axvline(boundary, color="black", linewidth=1.2)
    for group_index, (title, _) in enumerate(metric_groups):
        center = group_index * len(SCENARIOS) + 1
        axis.text(center, -1.02, title, ha="center", va="bottom", fontsize=11, weight="bold", clip_on=False)
    scalar = plt.cm.ScalarMappable(norm=mpl_colors.Normalize(0, 1), cmap=cmap)
    colorbar = figure.colorbar(scalar, ax=axis, fraction=0.025, pad=0.02)
    colorbar.set_ticks([0, 0.5, 1])
    colorbar.set_ticklabels(["Good", "Middle", "Bad"])
    colorbar.set_label("Within-column PRDS (lower is better)")
    axis.set_title("PRDS: mean percent metric change per +1% communication degradation", pad=38, fontsize=12)
    figure.savefig(output_path, dpi=350, bbox_inches="tight", facecolor="white")
    plt.close(figure)


def main() -> None:
    FIGURE_DIR.mkdir(parents=True, exist_ok=True)
    metric_results = pd.read_csv(TABLE_DIR / "dcta_metric_results.csv", low_memory=False)
    stats = pd.read_csv(TABLE_DIR / "dcta_statistical_tests.csv", low_memory=False)
    scenario_data = {spec.key: load_scenario(spec) for spec in SCENARIOS}
    summary = build_condition_summary(scenario_data, metric_results)
    summary.to_csv(TABLE_DIR / "final_figure_condition_summary.csv", index=False)
    (
        summary[
            [
                "scenario",
                "metric",
                "comm_model",
                "comm_level_pct",
                "eligible_paired_trials",
            ]
        ]
        .drop_duplicates()
        .to_csv(TABLE_DIR / "final_figure_paired_count_audit.csv", index=False)
    )

    output_names = {
        "Bayesian clue-informed search": "max_steps_bayesian_final.png",
        "Coverage area search": "max_steps_coverage_final.png",
        "Collaborative known-target visit": "max_steps_collaborative_visit_final.png",
    }
    for spec in SCENARIOS:
        plot_max_steps(spec, summary, stats, FIGURE_DIR / output_names[spec.key])
    plot_total_steps_summary(summary, FIGURE_DIR / "total_steps_summary_final.png")
    plot_total_steps_wilcoxon(stats, FIGURE_DIR / "total_steps_wilcoxon_final.png")
    plot_communication_tradeoff(summary, FIGURE_DIR / "communication_tradeoff_final.png")
    plot_prds_heatmap(metric_results, FIGURE_DIR / "prds_robustness_heatmap_final.png")

    print(f"Validated paired condition rows: {len(summary):,}")
    for path in sorted(FIGURE_DIR.glob("*_final.png")):
        print(path)


if __name__ == "__main__":
    main()
