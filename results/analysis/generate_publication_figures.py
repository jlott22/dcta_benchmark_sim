"""Generate revised publication figures from the audited analysis tables.

PNG files are exported at 600 dpi and vector PDFs are exported alongside them.
Every figure has a machine-readable source CSV in ``results/analysis/tables``.
"""

from __future__ import annotations

from pathlib import Path

import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


ANALYSIS_DIR = Path(__file__).resolve().parent
TABLE_DIR = ANALYSIS_DIR / "tables"
FIGURE_DIR = ANALYSIS_DIR / "figures"
FIGURE_DIR.mkdir(parents=True, exist_ok=True)

ALGORITHMS = ["CBAA", "ACBBA", "PI", "HIPC", "DMCHBA", "DGA"]
MODELS = ["bernoulli", "gilbert_elliott", "rayleigh_style"]
MODEL_LABELS = {
    "bernoulli": "Bernoulli",
    "gilbert_elliott": "Gilbert–Elliott",
    "rayleigh_style": "Rayleigh-style",
}
SCENARIOS = ["CLIPS", "CV", "FGS"]
MISSION_LABELS = {
    "CLIPS": "Clue-Informed Probabilistic Search (CLIPS)",
    "CV": "Collaborative Visit (CV)",
    "FGS": "Full Grid Search (FGS)",
}
COLORS = dict(zip(ALGORITHMS, mpl.colormaps["tab10"].colors[: len(ALGORITHMS)], strict=True))
MARKERS = dict(zip(ALGORITHMS, ["o", "s", "^", "D", "v", "P"], strict=True))

mpl.rcParams.update(
    {
        "font.family": "DejaVu Sans",
        "font.size": 7.5,
        "axes.titlesize": 8.5,
        "axes.labelsize": 8,
        "legend.fontsize": 7,
        "xtick.labelsize": 7,
        "ytick.labelsize": 7,
        "axes.linewidth": 0.7,
        "lines.linewidth": 1.1,
        "savefig.bbox": "tight",
        "pdf.fonttype": 42,
        "ps.fonttype": 42,
    }
)


def save_figure(fig: plt.Figure, stem: str) -> None:
    fig.savefig(FIGURE_DIR / f"{stem}.png", dpi=600, facecolor="white")
    fig.savefig(FIGURE_DIR / f"{stem}.pdf", facecolor="white")
    plt.close(fig)


def write_source(frame: pd.DataFrame, filename: str) -> None:
    frame.to_csv(TABLE_DIR / filename, index=False, float_format="%.15g")


def panel_curve_source(summary: pd.DataFrame, scenario: str, metric: str) -> pd.DataFrame:
    selected = summary.loc[summary["scenario"].eq(scenario) & summary["metric"].eq(metric)].copy()
    frames = []
    ideal = selected.loc[selected["comm_model"].eq("ideal")]
    for model in MODELS:
        model_frame = selected.loc[selected["comm_model"].eq(model)]
        panel = pd.concat([ideal, model_frame], ignore_index=True)
        panel["panel_model"] = model
        frames.append(panel)
    return pd.concat(frames, ignore_index=True)


def annotate_n(ax: plt.Axes, panel: pd.DataFrame) -> None:
    n_by_level = panel.groupby("degradation_pct")["six_way_paired_n"].first().sort_index()
    values = n_by_level.astype(int).tolist()
    if len(set(values)) == 1:
        label = f"six-way paired n={values[0]} throughout"
    elif max(values) - min(values) <= 5:
        label = f"six-way paired n={min(values)}–{max(values)}"
    else:
        label = "six-way paired n (0→70%): " + ", ".join(map(str, values))
    ax.text(
        0.015,
        0.985,
        label,
        transform=ax.transAxes,
        ha="left",
        va="top",
        fontsize=5.2,
        color="0.25",
        bbox={"facecolor": "white", "edgecolor": "none", "alpha": 0.7, "pad": 0.5},
    )


def plot_curves(
    ax: plt.Axes,
    panel: pd.DataFrame,
    ylabel: str | None = None,
    show_legend: bool = False,
    show_n: bool = True,
) -> None:
    for algorithm in ALGORITHMS:
        values = panel.loc[panel["algorithm"].eq(algorithm)].sort_values("degradation_pct")
        x = values["degradation_pct"].to_numpy(dtype=float)
        y = values["mean"].to_numpy(dtype=float)
        lo = values["ci95_low"].to_numpy(dtype=float)
        hi = values["ci95_high"].to_numpy(dtype=float)
        ax.plot(
            x,
            y,
            color=COLORS[algorithm],
            marker=MARKERS[algorithm],
            markersize=2.8,
            label=algorithm,
        )
        ax.vlines(x, lo, hi, color=COLORS[algorithm], linewidth=0.55, alpha=0.7)
    ax.axvline(0, color="0.8", linewidth=0.6)
    ax.grid(True, color="0.88", linewidth=0.5)
    ax.set_xlim(-2, 72)
    ax.set_xticks([0, 10, 20, 30, 40, 50, 60, 70])
    if ylabel:
        ax.set_ylabel(ylabel)
    if show_n:
        annotate_n(ax, panel)
    if show_legend:
        ax.legend(ncol=3, frameon=False, loc="upper center", bbox_to_anchor=(0.5, -0.21))


def clips_post_clue_figure(summary: pd.DataFrame) -> None:
    source = panel_curve_source(summary, "CLIPS", "post_clue_steps_to_find")
    write_source(source, "figure_clips_post_clue_source.csv")
    fig, axes = plt.subplots(3, 1, figsize=(3.5, 6.0), sharex=True, constrained_layout=True)
    for row, model in enumerate(MODELS):
        panel = source.loc[source["panel_model"].eq(model)]
        plot_curves(axes[row], panel, ylabel="Post-clue team steps", show_n=True)
        axes[row].set_title(MODEL_LABELS[model])
        if row == len(MODELS) - 1:
            axes[row].set_xlabel("Communication degradation (%)")
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, ncol=3, frameon=False, loc="outside lower center")
    fig.suptitle("CLIPS performance after first clue discovery", fontsize=9)
    save_figure(fig, "clips_post_clue_steps_final")


def multi_scenario_curve_figure(summary: pd.DataFrame, metric: str, ylabel: str, stem: str, title: str) -> None:
    sources = [panel_curve_source(summary, scenario, metric) for scenario in SCENARIOS]
    source = pd.concat(sources, ignore_index=True)
    source_filename = {
        "max_agent_steps": "figure_maximum_agent_steps_source.csv",
        "total_team_steps": "figure_total_team_steps_source.csv",
    }[metric]
    write_source(source, source_filename)
    fig, axes = plt.subplots(3, 3, figsize=(7.16, 6.25), constrained_layout=True)
    for row, scenario in enumerate(SCENARIOS):
        for column, model in enumerate(MODELS):
            panel = source.loc[source["scenario"].eq(scenario) & source["panel_model"].eq(model)]
            plot_curves(axes[row, column], panel, ylabel=None, show_n=True)
            if row == 0:
                axes[row, column].set_title(MODEL_LABELS[model])
            if column == 0:
                axes[row, column].set_ylabel(f"{scenario}\n{ylabel}")
            if row == 2:
                axes[row, column].set_xlabel("Communication degradation (%)")
    handles, labels = axes[0, 0].get_legend_handles_labels()
    fig.legend(handles, labels, ncol=6, frameon=False, loc="outside lower center")
    fig.suptitle(title, fontsize=9)
    save_figure(fig, stem)


def fgs_completion_figure(completion: pd.DataFrame) -> None:
    source = completion.loc[completion["comm_model"].eq("gilbert_elliott")].copy()
    write_source(source, "figure_fgs_completion_source.csv")
    fig, ax = plt.subplots(figsize=(3.5, 3.0), constrained_layout=True)
    ax.axvspan(45, 72, color="0.95", zorder=0)
    ax.axvline(50, color="0.65", linestyle="--", linewidth=0.7, zorder=1)
    for algorithm in ALGORITHMS:
        values = source.loc[source["algorithm"].eq(algorithm)].sort_values("degradation_pct")
        x = values["degradation_pct"].to_numpy(dtype=float)
        y = values["completion_rate"].to_numpy(dtype=float)
        yerr = np.vstack(
            [
                y - values["completion_ci95_wilson_low"].to_numpy(dtype=float),
                values["completion_ci95_wilson_high"].to_numpy(dtype=float) - y,
            ]
        )
        ax.errorbar(
            x,
            y,
            yerr=yerr,
            color=COLORS[algorithm],
            marker=MARKERS[algorithm],
            markersize=4,
            capsize=2,
            label=algorithm,
        )
    ax.set_xlim(3, 72)
    ax.set_ylim(0.3, 1.025)
    levels = [5, 10, 20, 30, 40, 50, 60, 70]
    paired_n = (
        source.groupby("degradation_pct")["six_way_paired_n_continuous_metrics"]
        .first()
        .reindex(levels)
        .astype(int)
    )
    ax.set_xticks(levels, [f"{level}\n{paired_n.loc[level]}" for level in levels])
    ax.set_xlabel("Gilbert–Elliott nominal loss (%)\nSix-way paired n")
    ax.set_ylabel("Mission completion probability")
    ax.set_title("FGS completion reliability\n100 matched trials per algorithm and level")
    ax.grid(True, color="0.88", linewidth=0.5)
    ax.legend(ncol=2, frameon=False, loc="lower left")
    ax.text(58.5, 0.47, "severe-loss region", ha="center", va="bottom", fontsize=6.5, color="0.35")
    save_figure(fig, "fgs_completion_rates_final")


def cv_workload_tradeoff(summary: pd.DataFrame) -> None:
    total = summary.loc[
        summary["scenario"].eq("CV")
        & summary["metric"].eq("total_team_steps")
        & summary["comm_model"].ne("ideal")
    ]
    gini = summary.loc[
        summary["scenario"].eq("CV")
        & summary["metric"].eq("unique_cell_contribution_gini")
        & summary["comm_model"].ne("ideal")
    ]
    keys = ["mission", "scenario", "comm_model", "comm_label", "degradation_pct", "algorithm"]
    condition_source = total.merge(gini, on=keys, suffixes=("_steps", "_gini"), validate="one_to_one")
    source = (
        condition_source.groupby("algorithm", as_index=False)
        .agg(
            mean_total_team_steps=("mean_steps", "mean"),
            mean_unique_cell_contribution_gini=("mean_gini", "mean"),
            impaired_condition_count=("comm_label", "nunique"),
        )
        .set_index("algorithm")
        .reindex(ALGORITHMS)
        .reset_index()
    )
    if not source["impaired_condition_count"].eq(24).all():
        raise ValueError("CV workload aggregate does not contain 24 impaired conditions per algorithm")
    write_source(source, "figure_cv_workload_tradeoff_source.csv")

    fig, ax = plt.subplots(figsize=(3.5, 3.0), constrained_layout=True)
    for row in source.itertuples(index=False):
        ax.scatter(
            row.mean_total_team_steps,
            row.mean_unique_cell_contribution_gini,
            color=COLORS[row.algorithm],
            marker=MARKERS[row.algorithm],
            s=28,
            label=row.algorithm,
        )
        if row.algorithm == "HIPC":
            ax.annotate(
                "HIPC",
                (row.mean_total_team_steps, row.mean_unique_cell_contribution_gini),
                xytext=(4, -1),
                textcoords="offset points",
                fontsize=6.5,
            )
    ax.set_xlabel("Mean total team steps")
    ax.set_ylabel("Mean unique-cell contribution Gini")
    ax.grid(True, color="0.9", linewidth=0.5)
    legend_handles = [
        mpl.lines.Line2D([], [], color=COLORS[algorithm], marker=MARKERS[algorithm], linestyle="none", label=algorithm)
        for algorithm in ALGORITHMS
    ]
    ax.legend(handles=legend_handles, ncol=2, frameon=False, loc="best")
    ax.set_title("CV travel–workload tradeoff\n24 impaired conditions", fontsize=8.5)
    save_figure(fig, "cv_workload_tradeoff")


def communication_tradeoff(summary: pd.DataFrame) -> None:
    max_steps = summary.loc[summary["metric"].eq("max_agent_steps")]
    message_rate = summary.loc[summary["metric"].eq("team_messages_per_step")]
    keys = ["mission", "scenario", "comm_model", "comm_label", "degradation_pct", "algorithm"]
    merged = max_steps.merge(message_rate, on=keys, suffixes=("_max_steps", "_message_rate"), validate="one_to_one")
    frames = []
    for scenario in SCENARIOS:
        scenario_rows = merged.loc[merged["scenario"].eq(scenario)]
        for model in MODELS:
            panel = scenario_rows.loc[scenario_rows["comm_model"].eq(model)].copy()
            panel["panel_model"] = model
            frames.append(panel)
    source = pd.concat(frames, ignore_index=True)
    write_source(source, "figure_communication_tradeoff_source.csv")

    fig, axes = plt.subplots(3, 3, figsize=(7.16, 6.25), constrained_layout=True)
    for row_idx, scenario in enumerate(SCENARIOS):
        for col_idx, model in enumerate(MODELS):
            ax = axes[row_idx, col_idx]
            panel = source.loc[source["scenario"].eq(scenario) & source["panel_model"].eq(model)]
            for algorithm in ALGORITHMS:
                values = panel.loc[panel["algorithm"].eq(algorithm)].sort_values("degradation_pct")
                x = values["mean_message_rate"].to_numpy(dtype=float)
                y = values["mean_max_steps"].to_numpy(dtype=float)
                ax.plot(
                    x,
                    y,
                    color=COLORS[algorithm],
                    label=algorithm,
                )
                ax.scatter(
                    x[0],
                    y[0],
                    s=17,
                    marker="o",
                    facecolors="white",
                    edgecolors=COLORS[algorithm],
                    linewidths=0.9,
                    zorder=3,
                )
                ax.scatter(
                    x[-1],
                    y[-1],
                    s=24,
                    marker=">",
                    facecolors=COLORS[algorithm],
                    edgecolors="white",
                    linewidths=0.35,
                    zorder=4,
                )
            ax.grid(True, color="0.9", linewidth=0.5)
            if row_idx == 0:
                ax.set_title(MODEL_LABELS[model])
            if col_idx == 0:
                ax.set_ylabel(f"{scenario}\nMaximum-agent steps")
            if row_idx == 2:
                ax.set_xlabel("Message publications / team step")
    handles, labels = axes[0, 0].get_legend_handles_labels()
    fig.legend(handles, labels, ncol=6, frameon=False, loc="outside lower center")
    fig.suptitle(
        "Communication publication rate versus mission timeliness\n"
        "open circle = 5%; arrowhead = 70% degradation",
        fontsize=9,
    )
    save_figure(fig, "communication_performance_tradeoff_revised")


def pairwise_prda_figure(prda: pd.DataFrame, prda_tests: pd.DataFrame) -> None:
    keys = ["scenario", "comm_model", "metric", "algorithm_a", "algorithm_b", "pair"]
    tests = prda_tests.loc[
        prda_tests["metric"].eq("max_agent_steps"),
        keys + ["p_holm", "reject_holm_0_05"],
    ].copy()
    source = prda.loc[prda["metric"].eq("max_agent_steps")].merge(
        tests,
        on=keys,
        how="left",
        validate="one_to_one",
    )
    if source[["p_holm", "reject_holm_0_05"]].isna().any().any():
        raise ValueError("Missing Holm-test result for at least one maximum-agent PRDA pair")
    write_source(source, "figure_pairwise_prda_source.csv")
    pair_order = [f"{a} vs {b}" for a_index, a in enumerate(ALGORITHMS) for b in ALGORITHMS[a_index + 1 :]]
    y_positions = np.arange(len(pair_order))
    fig, axes = plt.subplots(3, 3, figsize=(7.16, 7.3), constrained_layout=True)
    for row_idx, scenario in enumerate(SCENARIOS):
        scenario_source = source.loc[source["scenario"].eq(scenario)]
        row_limit = float(
            np.nanmax(
                np.abs(
                    scenario_source[["ci95_low", "ci95_high"]].to_numpy(dtype=float)
                )
            )
        )
        row_limit = max(row_limit * 1.08, 1.0)
        for col_idx, model in enumerate(MODELS):
            ax = axes[row_idx, col_idx]
            panel = scenario_source.loc[scenario_source["comm_model"].eq(model)].set_index("pair").reindex(pair_order)
            means = panel["mean"].to_numpy(dtype=float)
            lo = panel["ci95_low"].to_numpy(dtype=float)
            hi = panel["ci95_high"].to_numpy(dtype=float)
            ax.hlines(y_positions, lo, hi, color="0.25", linewidth=0.8)
            significant = panel["reject_holm_0_05"].astype(bool).to_numpy()
            ax.scatter(
                means[significant],
                y_positions[significant],
                s=13,
                facecolors="#2166ac",
                edgecolors="#2166ac",
                linewidths=0.7,
                zorder=3,
            )
            ax.scatter(
                means[~significant],
                y_positions[~significant],
                s=13,
                facecolors="white",
                edgecolors="#2166ac",
                linewidths=0.8,
                zorder=3,
            )
            ax.axvline(0, color="0.55", linewidth=0.7)
            ax.set_xlim(-row_limit, row_limit)
            ax.set_ylim(len(pair_order) - 0.4, -0.6)
            ax.grid(True, axis="x", color="0.9", linewidth=0.5)
            if col_idx == 0:
                ax.set_yticks(y_positions, pair_order, fontsize=5.6)
                ax.set_ylabel(scenario)
            else:
                ax.set_yticks(y_positions, [])
            if row_idx == 0:
                ax.set_title(MODEL_LABELS[model])
            if row_idx == 2:
                ax.set_xlabel("Pairwise PRDA (A vs B)")
            n_min = int(panel["eligible_n"].min())
            n_max = int(panel["eligible_n"].max())
            ax.text(0.98, 0.02, f"pairwise n={n_min}–{n_max}", transform=ax.transAxes, ha="right", va="bottom", fontsize=5.5)
    significance_handles = [
        mpl.lines.Line2D([], [], marker="o", linestyle="none", markerfacecolor="#2166ac", markeredgecolor="#2166ac", label="Holm p<0.05"),
        mpl.lines.Line2D([], [], marker="o", linestyle="none", markerfacecolor="white", markeredgecolor="#2166ac", label="Not significant"),
    ]
    fig.legend(handles=significance_handles, ncol=2, frameon=False, loc="outside lower center")
    fig.suptitle("Pairwise-complete robustness of maximum-agent steps\nnegative: first algorithm became relatively better", fontsize=9)
    save_figure(fig, "prda_pairwise_complete_final")


def prds_supplement_figure(prds: pd.DataFrame) -> None:
    source = prds.loc[prds["metric"].eq("max_agent_steps")].copy()
    write_source(source, "figure_prds_supplement_source.csv")
    values = source["mean"].to_numpy(dtype=float)
    limit = float(np.nanmax(np.abs(values)))
    fig, axes = plt.subplots(3, 3, figsize=(7.16, 5.2), constrained_layout=True)
    image = None
    for row_idx, scenario in enumerate(SCENARIOS):
        for col_idx, model in enumerate(MODELS):
            ax = axes[row_idx, col_idx]
            panel = source.loc[source["scenario"].eq(scenario) & source["comm_model"].eq(model)].set_index("algorithm").reindex(ALGORITHMS)
            matrix = panel["mean"].to_numpy(dtype=float).reshape(-1, 1)
            image = ax.imshow(matrix, cmap="coolwarm", vmin=-limit, vmax=limit, aspect="auto")
            for y, value in enumerate(matrix[:, 0]):
                ax.text(0, y, f"{value:.2f}\nn={int(panel.iloc[y]['eligible_n'])}", ha="center", va="center", fontsize=5.8)
            ax.set_xticks([])
            ax.set_yticks(np.arange(len(ALGORITHMS)), ALGORITHMS if col_idx == 0 else [])
            if row_idx == 0:
                ax.set_title(MODEL_LABELS[model])
            if col_idx == 0:
                ax.set_ylabel(scenario)
    assert image is not None
    fig.colorbar(image, ax=axes, shrink=0.78, label="Mean PRDS (% metric change / +1% degradation)")
    fig.suptitle("Supplementary algorithm-complete PRDS: maximum-agent steps", fontsize=9)
    save_figure(fig, "prds_supplement")


def write_captions() -> None:
    captions = r"""% Auto-generated publication figure environments (paths are repository-relative).
\begin{figure}[t]
  \centering
  \includegraphics[width=\columnwidth]{results/analysis/figures/clips_post_clue_steps_final.pdf}
  \caption{Clue-Informed Probabilistic Search (CLIPS) performance after first clue discovery. Points are six-algorithm-paired means of \texttt{post\_clue\_steps\_to\_find}; vertical intervals are 95\% Student-$t$ confidence intervals. Each panel reports the paired sample-size range, and the ideal point is repeated at 0\% only as a common baseline. Source: \texttt{figure\_clips\_post\_clue\_source.csv}.}
  \label{fig:clips-post-clue}
\end{figure}

\begin{figure*}[t]
  \centering
  \includegraphics[width=\textwidth]{results/analysis/figures/max_agent_steps_all_missions_final.pdf}
  \caption{Maximum-agent steps for CLIPS, Collaborative Visit (CV), and Full Grid Search (FGS), separated by communication model. Points are six-algorithm-paired means with 95\% Student-$t$ confidence intervals. Printed $n$ values expose the declining conditional-on-completion support for FGS under severe Gilbert--Elliott loss. Source: \texttt{figure\_maximum\_agent\_steps\_source.csv}.}
  \label{fig:maximum-agent-steps}
\end{figure*}

\begin{figure}[t]
  \centering
  \includegraphics[width=\columnwidth]{results/analysis/figures/fgs_completion_rates_final.pdf}
  \caption{FGS mission-completion probability under the corrected Gilbert--Elliott process. Points show completion proportions over 100 matched trials per algorithm at each nominal loss level, and error bars are 95\% Wilson intervals. The second row of horizontal-axis labels reports the number of trial IDs completed by all six algorithms and therefore available for conditional continuous-metric comparison. Source: \texttt{figure\_fgs\_completion\_source.csv}.}
  \label{fig:fgs-completion}
\end{figure}

\begin{figure*}[t]
  \centering
  \includegraphics[width=\textwidth]{results/analysis/figures/total_team_steps.pdf}
  \caption{Total team steps by mission and communication model. Intervals represent trial uncertainty (95\% Student-$t$ confidence intervals), not ranges across degradation levels. FGS values are explicitly conditional on successful completion and use the printed six-way-paired $n$. Source: \texttt{figure\_total\_team\_steps\_source.csv}.}
  \label{fig:total-team-steps}
\end{figure*}

\begin{figure}[t]
  \centering
  \includegraphics[width=\columnwidth]{results/analysis/figures/cv_workload_tradeoff.pdf}
  \caption{CV aggregate-travel--workload tradeoff across the 24 impaired conditions. Points show each algorithm's unweighted mean total team steps and mean unique-cell contribution Gini; the lower-left region is preferred when both total motion and workload balance matter. HIPC minimizes aggregate travel but concentrates substantially more work on a subset of robots. Source: \texttt{figure\_cv\_workload\_tradeoff\_source.csv}.}
  \label{fig:cv-workload-tradeoff}
\end{figure}

\begin{figure*}[t]
  \centering
  \includegraphics[width=\textwidth]{results/analysis/figures/communication_performance_tradeoff_revised.pdf}
  \caption{Communication--mission tradeoff across CLIPS, CV, and FGS. Each algorithm trajectory relates message publications per team step to absolute maximum-agent steps as nominal degradation increases from 5\% to 70\%. The lower-left region is preferred. Open circles identify 5\% and arrowheads identify 70\%; FGS points are conditional on successful completion. Source: \texttt{figure\_communication\_tradeoff\_source.csv}.}
  \label{fig:communication-tradeoff}
\end{figure*}

\begin{figure*}[t]
  \centering
  \includegraphics[width=\textwidth]{results/analysis/figures/prda_pairwise_complete_final.pdf}
  \caption{Pairwise-complete relative degradation area (PRDA) for maximum-agent steps, with communication models kept separate. Points show means with 95\% Student-$t$ confidence intervals. Negative values mean the first named algorithm became relatively better as degradation increased. Filled markers denote Holm-adjusted $p<0.05$, open markers denote nonsignificant comparisons, and panel annotations give pairwise-complete $n$ ranges. Source: \texttt{figure\_pairwise\_prda\_source.csv}.}
  \label{fig:pairwise-prda}
\end{figure*}

\begin{figure*}[t]
  \centering
  \includegraphics[width=\textwidth]{results/analysis/figures/prds_supplement.pdf}
  \caption{Supplementary algorithm-complete proportional robustness degradation slope (PRDS) for maximum-agent steps. Communication models are not averaged; each cell reports the mean PRDS and eligible algorithm-specific trajectory $n$. Source: \texttt{figure\_prds\_supplement\_source.csv}.}
  \label{fig:prds-supplement}
\end{figure*}

\begin{figure}[t]
  \centering
  \includegraphics[width=\columnwidth]{results/analysis/figures/horizon_tuning.png}
  \caption{Commitment-horizon sensitivity for CV, CLIPS, and FGS. Within each scenario, algorithm, and trial, the paired baseline is the mean metric over all tested horizons and both communication settings; plotted values are metric-minus-baseline means. Solid lines denote ideal communication, dotted lines Bernoulli loss probability 0.25, and stars mark the selected main-benchmark horizon for each algorithm and mission. Source: \texttt{horizon\_tuning\_paired\_trial\_delta\_summary.csv}.}
  \label{fig:horizon-tuning}
\end{figure}

\begin{figure}[t]
  \centering
  \includegraphics[width=\columnwidth]{results/analysis/figures/DGA_iteration.png}
  \caption{DGA generation-count sensitivity in CV under ideal and Bernoulli $p_d=0.25$ communication. Values are mean percent differences from the per-trial average over all tested DGA iteration counts. Stars mark the main-benchmark value $k=25$. The available sensitivity bundle contains no corresponding CLIPS sweep. Source: \texttt{dga\_iteration\_percent\_delta\_summary.csv}.}
  \label{fig:dga-iteration}
\end{figure}
"""
    (ANALYSIS_DIR / "FIGURE_CAPTIONS.tex").write_text(captions, encoding="utf-8")


def main() -> None:
    summary = pd.read_csv(TABLE_DIR / "publication_figure_condition_summary.csv")
    completion = pd.read_csv(TABLE_DIR / "fgs_completion_failure_summary.csv")
    prda = pd.read_csv(TABLE_DIR / "revised_prda.csv")
    prda_tests = pd.read_csv(TABLE_DIR / "revised_prda_statistical_tests.csv")
    prds = pd.read_csv(TABLE_DIR / "revised_prds.csv")

    clips_post_clue_figure(summary)
    multi_scenario_curve_figure(
        summary,
        "max_agent_steps",
        "Maximum-agent steps",
        "max_agent_steps_all_missions_final",
        "Maximum-agent mission effort",
    )
    fgs_completion_figure(completion)
    multi_scenario_curve_figure(
        summary,
        "total_team_steps",
        "Total team steps",
        "total_team_steps",
        "Total team effort (FGS conditional on completion)",
    )
    cv_workload_tradeoff(summary)
    communication_tradeoff(summary)
    pairwise_prda_figure(prda, prda_tests)
    prds_supplement_figure(prds)
    write_captions()
    print(f"Wrote revised figures to {FIGURE_DIR}")
    print(f"Wrote source tables to {TABLE_DIR}")


if __name__ == "__main__":
    main()
