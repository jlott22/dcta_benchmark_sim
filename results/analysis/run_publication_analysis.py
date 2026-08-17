"""Publication analysis for the DCTA benchmark paper update.

This script is intentionally read-only with respect to simulation results.  It
reads the current, scenario-prefixed combined CSVs and writes derived analysis
tables under ``results/analysis/tables``.

Methods implemented here:

* FGS binary completion: Cochran's Q, exact paired McNemar tests, and Holm
  correction within each significant communication condition.
* PRDS and PRDA: common-six complete ideal-plus-eight-level trajectories.
  A trial is retained for a mission, metric, and communication model only when
  all six algorithms have eligible finite outcomes at all nine nominal levels.
  PRDS uses log-linear slopes; PRDA integrates relative log trajectories by the
  trapezoidal rule, with Wilcoxon signed-rank tests and 15-test Holm families.

No failed trial is assigned a continuous-metric penalty.  Efficiency analyses
are conditional on recorded mission completion and metric eligibility.
"""

from __future__ import annotations

import hashlib
import itertools
import math
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from statistics import NormalDist

import numpy as np
import pandas as pd


ANALYSIS_DIR = Path(__file__).resolve().parent
REPO_ROOT = ANALYSIS_DIR.parents[1]
RESULTS_ROOT = REPO_ROOT / "results"
TABLE_DIR = ANALYSIS_DIR / "tables"
TABLE_DIR.mkdir(parents=True, exist_ok=True)

ALGORITHMS = ["CBAA", "ACBBA", "PI", "HIPC", "DMCHBA", "DGA"]
LEVELS = np.asarray([0, 5, 10, 20, 30, 40, 50, 60, 70], dtype=float)
DEGRADED_LEVELS = LEVELS[1:]
MODELS = ["bernoulli", "gilbert_elliott", "rayleigh_style"]
Z_975 = NormalDist().inv_cdf(0.975)

RAYLEIGH_TO_DEGRADATION = {
    -59.40: 5,
    -56.04: 10,
    -52.15: 20,
    -49.17: 30,
    -46.04: 40,
    -42.16: 50,
    -37.79: 60,
    -32.58: 70,
}


@dataclass(frozen=True)
class ScenarioSpec:
    mission: str
    short_name: str
    result_set: str
    system_name: str
    trial_name: str
    robot_name: str

    @property
    def folder(self) -> Path:
        return RESULTS_ROOT / self.result_set / "combined"

    @property
    def system_path(self) -> Path:
        return self.folder / self.system_name

    @property
    def trial_path(self) -> Path:
        return self.folder / self.trial_name

    @property
    def robot_path(self) -> Path:
        return self.folder / self.robot_name

    @property
    def manifest_path(self) -> Path:
        return self.folder / f"{self.result_set}_combined_condition_manifest.csv"


SCENARIOS = [
    ScenarioSpec(
        "Clue-Informed Probabilistic Search (CLIPS)",
        "CLIPS",
        "clue_search_core_500",
        "clue_search_core_500_combined_system_performance.csv",
        "clue_search_core_500_combined_trial_summary.csv",
        "clue_search_core_500_combined_robot_performance.csv",
    ),
    ScenarioSpec(
        "Collaborative Visit (CV)",
        "CV",
        "known_target_visit_core_500",
        "known_target_visit_core_500_combined_system_performance.csv",
        "known_target_visit_core_500_combined_trial_summary.csv",
        "known_target_visit_core_500_combined_robot_performance.csv",
    ),
    ScenarioSpec(
        "Full Grid Search (FGS)",
        "FGS",
        "coverage_core_100",
        "coverage_core_100_combined_system_performance.csv",
        "coverage_core_100_combined_trial_summary.csv",
        "coverage_core_100_combined_robot_performance.csv",
    ),
]

SHARED_METRICS = [
    "max_agent_steps",
    "total_team_steps",
    "team_messages_per_step",
    "max_agent_messages",
    "messages_per_unique_cell",
    "unique_cell_contribution_gini",
    "team_task_replans",
    "team_path_replans",
]

METRIC_OFFSETS = {
    "max_agent_steps": 0.0,
    "total_team_steps": 0.0,
    "post_clue_steps_to_find": 1.0,
    "team_messages_per_step": 0.0,
    "max_agent_messages": 0.0,
    "messages_per_unique_cell": 0.0,
    "unique_cell_contribution_gini": 1.0,
    "team_task_replans": 1.0,
    "team_path_replans": 1.0,
    "system_cell_revisits": 1.0,
    "duplicate_target_visits": 1.0,
    "target_completion_gini": 1.0,
    "messages_per_target": 0.0,
    "allocation_publications_per_mission": 0.0,
}

METRIC_SOURCES = {
    "max_agent_steps": "max_steps_any_robot (CLIPS/FGS) or max_robot_steps (CV)",
    "total_team_steps": "total_team_steps",
    "post_clue_steps_to_find": "post_clue_steps_to_find",
    "team_messages_per_step": "messages_sent_total / total_team_steps (publications per team step)",
    "max_agent_messages": "max_messages_any_robot or max(robot_performance.messages_sent)",
    "messages_per_unique_cell": "messages_per_unique_cell or messages_sent_total / unique_cells_visited",
    "unique_cell_contribution_gini": "workload_gini_unique_cells_contributed",
    "team_task_replans": "task_cell_replans_total",
    "team_path_replans": "path_replans_total",
    "system_cell_revisits": "system_revisits",
    "duplicate_target_visits": "duplicate_target_visits",
    "target_completion_gini": "workload_gini_targets_found",
    "messages_per_target": "messages_sent_total / completed_target_count",
    "allocation_publications_per_mission": "allocation_messages_sent_total",
}


def scenario_metrics(short_name: str) -> list[str]:
    if short_name == "CLIPS":
        return SHARED_METRICS + ["system_cell_revisits", "post_clue_steps_to_find"]
    if short_name == "FGS":
        return SHARED_METRICS + ["system_cell_revisits"]
    return SHARED_METRICS + [
        "duplicate_target_visits",
        "target_completion_gini",
        "messages_per_target",
    ]


def safe_divide(numerator: pd.Series, denominator: pd.Series) -> pd.Series:
    num = pd.to_numeric(numerator, errors="coerce")
    den = pd.to_numeric(denominator, errors="coerce")
    out = num / den
    return out.where(np.isfinite(out))


def degradation_level(frame: pd.DataFrame, short_name: str) -> pd.Series:
    result = pd.Series(np.nan, index=frame.index, dtype=float)
    model = frame["comm_model"].astype("string").str.lower()
    raw = frame["comm_level"].astype("string")
    label = frame["comm_label"].astype("string")
    result.loc[model.eq("ideal")] = 0.0

    bern = model.eq("bernoulli")
    result.loc[bern] = 100.0 * pd.to_numeric(raw.loc[bern], errors="coerce")

    ge = model.eq("gilbert_elliott")
    parsed = label.loc[ge].str.extract(r"drop_0_(\d+)_rho", expand=False)
    parsed_levels = pd.to_numeric(parsed, errors="coerce")
    fallback_levels = 100.0 * (1.0 - pd.to_numeric(raw.loc[ge], errors="coerce"))
    result.loc[ge] = parsed_levels.fillna(fallback_levels)

    rayleigh = model.eq("rayleigh_style")
    rayleigh_values = pd.to_numeric(raw.loc[rayleigh], errors="coerce")
    for threshold, pct in RAYLEIGH_TO_DEGRADATION.items():
        matches = rayleigh_values.sub(threshold).abs().lt(0.011)
        result.loc[rayleigh_values.index[matches]] = float(pct)

    return result.round(8)


def load_scenario(spec: ScenarioSpec) -> pd.DataFrame:
    system = pd.read_csv(spec.system_path, dtype={"comm_level": "string"}, low_memory=False)
    system["trial_id"] = pd.to_numeric(system["trial_id"], errors="raise").astype(int)
    system["algorithm"] = system["algorithm"].astype("string").str.upper()
    system["comm_model"] = (
        system["comm_model"].astype("string").str.lower().replace({"gilbert_elliot": "gilbert_elliott"})
    )
    system["comm_label"] = system["comm_label"].astype("string")
    system["mission"] = spec.mission
    system["scenario"] = spec.short_name
    system["degradation_pct"] = degradation_level(system, spec.short_name)

    key = ["trial_id", "algorithm", "comm_model", "degradation_pct"]
    if system.duplicated(key).any():
        raise AssertionError(f"Duplicate system keys in {spec.system_path}")

    status = system["trial_status"].astype("string").str.lower().eq("completed")
    if spec.short_name == "CLIPS":
        trial = pd.read_csv(
            spec.trial_path,
            usecols=["trial_id", "algorithm", "comm_model", "comm_level", "comm_label", "trial_status", "first_clue_robot"],
            dtype={"comm_level": "string", "first_clue_robot": "string"},
            low_memory=False,
        )
        trial["trial_id"] = pd.to_numeric(trial["trial_id"], errors="raise").astype(int)
        trial["algorithm"] = trial["algorithm"].astype("string").str.upper()
        trial["comm_model"] = (
            trial["comm_model"].astype("string").str.lower().replace({"gilbert_elliot": "gilbert_elliott"})
        )
        trial["comm_label"] = trial["comm_label"].astype("string")
        trial["degradation_pct"] = degradation_level(trial, spec.short_name)
        trial["trial_summary_eligible"] = (
            trial["trial_status"].astype("string").str.lower().eq("completed")
            & trial["first_clue_robot"].notna()
            & trial["first_clue_robot"].str.strip().ne("")
        )
        system = system.merge(trial[key + ["trial_summary_eligible"]], on=key, how="left", validate="one_to_one")
        status &= system["trial_summary_eligible"].fillna(False)
    elif spec.short_name == "FGS":
        trial = pd.read_csv(
            spec.trial_path,
            usecols=["trial_id", "algorithm", "comm_model", "comm_level", "comm_label", "trial_status"],
            dtype={"comm_level": "string"},
            low_memory=False,
        )
        trial["trial_id"] = pd.to_numeric(trial["trial_id"], errors="raise").astype(int)
        trial["algorithm"] = trial["algorithm"].astype("string").str.upper()
        trial["comm_model"] = (
            trial["comm_model"].astype("string").str.lower().replace({"gilbert_elliot": "gilbert_elliott"})
        )
        trial["comm_label"] = trial["comm_label"].astype("string")
        trial["degradation_pct"] = degradation_level(trial, spec.short_name)
        trial["trial_summary_eligible"] = trial["trial_status"].astype("string").str.lower().eq("completed")
        system = system.merge(trial[key + ["trial_summary_eligible"]], on=key, how="left", validate="one_to_one")
        status &= system["trial_summary_eligible"].fillna(False)
    else:
        status &= (
            system["all_targets_visited"].astype("string").str.lower().eq("true")
            & pd.to_numeric(system["completed_target_count"], errors="coerce").eq(
                pd.to_numeric(system["target_count"], errors="coerce")
            )
        )
    system["base_eligible"] = status.astype(bool)

    if "max_steps_any_robot" in system:
        system["max_agent_steps"] = pd.to_numeric(system["max_steps_any_robot"], errors="coerce")
    else:
        system["max_agent_steps"] = pd.to_numeric(system["max_robot_steps"], errors="coerce")
    system["total_team_steps"] = pd.to_numeric(system["total_team_steps"], errors="coerce")
    system["team_messages_per_step"] = safe_divide(system["messages_sent_total"], system["total_team_steps"])

    if "max_messages_any_robot" in system:
        system["max_agent_messages"] = pd.to_numeric(system["max_messages_any_robot"], errors="coerce")
    else:
        robot = pd.read_csv(
            spec.robot_path,
            usecols=["trial_id", "algorithm", "comm_model", "comm_level", "comm_label", "messages_sent"],
            dtype={"comm_level": "string"},
            low_memory=False,
        )
        robot["trial_id"] = pd.to_numeric(robot["trial_id"], errors="raise").astype(int)
        robot["algorithm"] = robot["algorithm"].astype("string").str.upper()
        robot["comm_model"] = (
            robot["comm_model"].astype("string").str.lower().replace({"gilbert_elliot": "gilbert_elliott"})
        )
        robot["comm_label"] = robot["comm_label"].astype("string")
        robot["degradation_pct"] = degradation_level(robot, spec.short_name)
        robot["messages_sent"] = pd.to_numeric(robot["messages_sent"], errors="coerce")
        robot_max = robot.groupby(key, dropna=False, as_index=False)["messages_sent"].max()
        robot_max = robot_max.rename(columns={"messages_sent": "max_agent_messages_derived"})
        system = system.merge(robot_max, on=key, how="left", validate="one_to_one")
        system["max_agent_messages"] = system["max_agent_messages_derived"]

    if spec.short_name in {"CLIPS", "FGS"}:
        if "messages_per_unique_cell" in system:
            system["messages_per_unique_cell"] = pd.to_numeric(system["messages_per_unique_cell"], errors="coerce")
        else:
            system["messages_per_unique_cell"] = safe_divide(system["messages_sent_total"], system["unique_cells_searched"])
        system["system_cell_revisits"] = pd.to_numeric(system["system_revisits"], errors="coerce")
    else:
        system["messages_per_unique_cell"] = safe_divide(system["messages_sent_total"], system["unique_cells_visited"])
        system["duplicate_target_visits"] = pd.to_numeric(system["duplicate_target_visits"], errors="coerce")
        system["target_completion_gini"] = pd.to_numeric(system["workload_gini_targets_found"], errors="coerce")
        system["messages_per_target"] = safe_divide(system["messages_sent_total"], system["completed_target_count"])

    system["unique_cell_contribution_gini"] = pd.to_numeric(
        system["workload_gini_unique_cells_contributed"], errors="coerce"
    )
    system["team_task_replans"] = pd.to_numeric(system["task_cell_replans_total"], errors="coerce")
    system["team_path_replans"] = pd.to_numeric(system["path_replans_total"], errors="coerce")
    system["allocation_publications_per_mission"] = pd.to_numeric(
        system["allocation_messages_sent_total"], errors="coerce"
    )
    if "post_clue_steps_to_find" in system:
        system["post_clue_steps_to_find"] = pd.to_numeric(system["post_clue_steps_to_find"], errors="coerce")

    if set(system["algorithm"].dropna().unique()) != set(ALGORITHMS):
        raise AssertionError(f"Unexpected algorithm set in {spec.system_path}")
    expected_levels = set(LEVELS.tolist())
    for model_name in MODELS:
        actual = set(system.loc[system["comm_model"].eq(model_name), "degradation_pct"].dropna().unique())
        if actual != set(DEGRADED_LEVELS.tolist()):
            raise AssertionError(f"{spec.short_name} {model_name} levels {actual}, expected {expected_levels - {0.0}}")
    return system


def valid_metric(frame: pd.DataFrame, metric: str) -> pd.Series:
    values = pd.to_numeric(frame[metric], errors="coerce")
    valid = np.isfinite(values)
    if METRIC_OFFSETS[metric] == 0:
        valid &= values.gt(0)
    return pd.Series(valid, index=frame.index)


def student_t_critical_975(df: int) -> float:
    """Accurate Cornish-Fisher expansion for the 0.975 Student-t quantile."""
    if df <= 0:
        return math.nan
    z = Z_975
    v = float(df)
    return (
        z
        + (z**3 + z) / (4 * v)
        + (5 * z**5 + 16 * z**3 + 3 * z) / (96 * v**2)
        + (3 * z**7 + 19 * z**5 + 17 * z**3 - 15 * z) / (384 * v**3)
        + (79 * z**9 + 776 * z**7 + 1482 * z**5 - 1920 * z**3 - 945 * z) / (92160 * v**4)
    )


def descriptive(values: np.ndarray) -> dict[str, float | int]:
    x = np.asarray(values, dtype=float)
    x = x[np.isfinite(x)]
    n = len(x)
    if n == 0:
        return {"eligible_n": 0, "mean": math.nan, "median": math.nan, "sd": math.nan, "ci95_low": math.nan, "ci95_high": math.nan}
    mean = float(np.mean(x))
    median = float(np.median(x))
    sd = float(np.std(x, ddof=1)) if n > 1 else math.nan
    if n > 1:
        half = student_t_critical_975(n - 1) * sd / math.sqrt(n)
        lo, hi = mean - half, mean + half
    else:
        lo = hi = math.nan
    return {"eligible_n": n, "mean": mean, "median": median, "sd": sd, "ci95_low": lo, "ci95_high": hi}


def average_ranks(values: np.ndarray) -> np.ndarray:
    return pd.Series(values).rank(method="average").to_numpy(dtype=float)


def wilcoxon_signed_rank(values: np.ndarray) -> dict[str, float | int | str]:
    x = np.asarray(values, dtype=float)
    x = x[np.isfinite(x)]
    x = x[x != 0]
    if len(x) == 0:
        return {
            "nonzero_n": 0,
            "w_positive": 0.0,
            "w_negative": 0.0,
            "p_raw": 1.0,
            "rank_biserial": math.nan,
            "test_method": "normal approximation with continuity correction; zeros excluded",
        }
    ranks = average_ranks(np.abs(x))
    w_pos = float(ranks[x > 0].sum())
    w_neg = float(ranks[x < 0].sum())
    denom = w_pos + w_neg
    rank_biserial = (w_pos - w_neg) / denom if denom else math.nan
    mean_w = denom / 2.0
    var_w = float(np.square(ranks).sum()) / 4.0
    if var_w <= 0:
        p_value = 1.0
    else:
        continuity = 0.5 * np.sign(w_pos - mean_w)
        z = (w_pos - mean_w - continuity) / math.sqrt(var_w)
        p_value = math.erfc(abs(z) / math.sqrt(2.0))
    return {
        "nonzero_n": len(x),
        "w_positive": w_pos,
        "w_negative": w_neg,
        "p_raw": min(max(float(p_value), 0.0), 1.0),
        "rank_biserial": float(rank_biserial),
        "test_method": "normal approximation with continuity correction; zeros excluded",
    }


def holm_adjust(p_values: list[float]) -> list[float]:
    p = np.asarray(p_values, dtype=float)
    order = np.argsort(p)
    adjusted_sorted = np.empty_like(p)
    running = 0.0
    m = len(p)
    for rank, idx in enumerate(order):
        running = max(running, (m - rank) * p[idx])
        adjusted_sorted[idx] = min(running, 1.0)
    return adjusted_sorted.tolist()


def regularized_gamma_q(a: float, x: float) -> float:
    """Regularized upper incomplete gamma Q(a,x), Numerical Recipes form."""
    if x < 0 or a <= 0:
        return math.nan
    if x == 0:
        return 1.0
    eps = 3e-14
    fpmin = 1e-300
    gln = math.lgamma(a)
    if x < a + 1.0:
        ap = a
        summation = 1.0 / a
        delta = summation
        for _ in range(10000):
            ap += 1.0
            delta *= x / ap
            summation += delta
            if abs(delta) < abs(summation) * eps:
                break
        p = summation * math.exp(-x + a * math.log(x) - gln)
        return min(max(1.0 - p, 0.0), 1.0)
    b = x + 1.0 - a
    c = 1.0 / fpmin
    d = 1.0 / b
    h = d
    for i in range(1, 10000):
        an = -i * (i - a)
        b += 2.0
        d = an * d + b
        if abs(d) < fpmin:
            d = fpmin
        c = b + an / c
        if abs(c) < fpmin:
            c = fpmin
        d = 1.0 / d
        delta = d * c
        h *= delta
        if abs(delta - 1.0) < eps:
            break
    return min(max(math.exp(-x + a * math.log(x) - gln) * h, 0.0), 1.0)


def cochran_q(matrix: np.ndarray) -> tuple[float, int, float]:
    x = np.asarray(matrix, dtype=float)
    n, k = x.shape
    columns = x.sum(axis=0)
    rows = x.sum(axis=1)
    total = columns.sum()
    denominator = k * total - np.square(rows).sum()
    if denominator == 0:
        return 0.0, k - 1, 1.0
    q = (k - 1) * (k * np.square(columns).sum() - total**2) / denominator
    q = max(float(q), 0.0)
    return q, k - 1, regularized_gamma_q((k - 1) / 2.0, q / 2.0)


def exact_mcnemar_p(n10: int, n01: int) -> float:
    discordant = n10 + n01
    if discordant == 0:
        return 1.0
    tail = sum(math.comb(discordant, k) for k in range(min(n10, n01) + 1)) / (2.0**discordant)
    return min(1.0, 2.0 * tail)


def wilson_interval(successes: int, attempts: int) -> tuple[float, float]:
    if attempts == 0:
        return math.nan, math.nan
    p = successes / attempts
    z2 = Z_975**2
    center = (p + z2 / (2 * attempts)) / (1 + z2 / attempts)
    half = Z_975 * math.sqrt(p * (1 - p) / attempts + z2 / (4 * attempts**2)) / (1 + z2 / attempts)
    return center - half, center + half


def fgs_completion_analysis(fgs: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    rows: list[dict] = []
    q_rows: list[dict] = []
    pair_rows: list[dict] = []

    condition_keys = (
        fgs[["comm_model", "degradation_pct", "comm_label"]]
        .drop_duplicates()
        .sort_values(["comm_model", "degradation_pct"], na_position="first")
    )
    for condition in condition_keys.itertuples(index=False):
        mask = fgs["comm_model"].eq(condition.comm_model) & fgs["degradation_pct"].eq(condition.degradation_pct)
        condition_frame = fgs.loc[mask].copy()
        completion = (
            condition_frame.pivot(index="trial_id", columns="algorithm", values="trial_status")
            .reindex(columns=ALGORITHMS)
            .apply(lambda col: col.astype("string").str.lower().eq("completed"))
        )
        if completion.isna().any().any() or len(completion) != 100:
            raise AssertionError(f"Incomplete FGS attempt matrix for {condition.comm_label}")
        six_way_n = int(completion.all(axis=1).sum())
        q_stat, q_df, q_p = cochran_q(completion.to_numpy(dtype=int))
        q_rows.append(
            {
                "mission": "Full Grid Search (FGS)",
                "comm_model": condition.comm_model,
                "comm_label": condition.comm_label,
                "degradation_pct": condition.degradation_pct,
                "matched_trial_n": len(completion),
                "algorithm_count": len(ALGORITHMS),
                "cochran_q": q_stat,
                "df": q_df,
                "p_value": q_p,
                "significant_0_05": q_p < 0.05,
                "test_method": "Cochran's Q; chi-square reference distribution",
            }
        )

        for algorithm in ALGORITHMS:
            alg_frame = condition_frame.loc[condition_frame["algorithm"].eq(algorithm)]
            attempted = len(alg_frame)
            completed = int(alg_frame["trial_status"].astype("string").str.lower().eq("completed").sum())
            failed = attempted - completed
            lo, hi = wilson_interval(completed, attempted)
            failed_rows = alg_frame.loc[alg_frame["trial_status"].astype("string").str.lower().ne("completed")]
            reasons = "none"
            if failed:
                reason_counts = failed_rows["failure_type"].fillna("unspecified").astype(str).value_counts()
                reasons = "; ".join(f"{name}: scheduler-event safety cap before 361-cell coverage (n={count})" for name, count in reason_counts.items())
            rows.append(
                {
                    "mission": "Full Grid Search (FGS)",
                    "comm_model": condition.comm_model,
                    "comm_label": condition.comm_label,
                    "degradation_pct": condition.degradation_pct,
                    "algorithm": algorithm,
                    "attempted_trials": attempted,
                    "completed_trials": completed,
                    "failed_trials": failed,
                    "completion_rate": completed / attempted,
                    "failure_rate": failed / attempted,
                    "completion_ci95_wilson_low": lo,
                    "completion_ci95_wilson_high": hi,
                    "failure_reasons": reasons,
                    "six_way_paired_n_continuous_metrics": six_way_n,
                    "continuous_metric_scope": "conditional on completion and six-way paired eligibility",
                }
            )

        if q_p < 0.05:
            family: list[dict] = []
            for algorithm_a, algorithm_b in itertools.combinations(ALGORITHMS, 2):
                a = completion[algorithm_a].to_numpy(dtype=bool)
                b = completion[algorithm_b].to_numpy(dtype=bool)
                n10 = int(np.sum(a & ~b))
                n01 = int(np.sum(~a & b))
                raw_p = exact_mcnemar_p(n10, n01)
                family.append(
                    {
                        "mission": "Full Grid Search (FGS)",
                        "comm_model": condition.comm_model,
                        "comm_label": condition.comm_label,
                        "degradation_pct": condition.degradation_pct,
                        "matched_trial_n": len(completion),
                        "algorithm_a": algorithm_a,
                        "algorithm_b": algorithm_b,
                        "completion_rate_a": float(a.mean()),
                        "completion_rate_b": float(b.mean()),
                        "completion_rate_difference_a_minus_b": float(a.mean() - b.mean()),
                        "completion_rate_difference_percentage_points": 100.0 * float(a.mean() - b.mean()),
                        "a_completed_b_failed": n10,
                        "a_failed_b_completed": n01,
                        "discordant_pairs": n10 + n01,
                        "matched_odds_ratio_a_vs_b": n10 / n01 if n10 > 0 and n01 > 0 else math.nan,
                        "mcnemar_p_raw": raw_p,
                        "test_method": "exact two-sided McNemar binomial test",
                    }
                )
            adjusted = holm_adjust([row["mcnemar_p_raw"] for row in family])
            for row, p_holm in zip(family, adjusted, strict=True):
                row["mcnemar_p_holm"] = p_holm
                row["reject_holm_0_05"] = p_holm < 0.05
                pair_rows.append(row)

    summary = pd.DataFrame(rows)
    omnibus = pd.DataFrame(q_rows)
    pairwise = pd.DataFrame(pair_rows)
    if len(pairwise) and not (pairwise.groupby(["comm_model", "comm_label"]).size() == 15).all():
        raise AssertionError("Each significant FGS McNemar family must contain exactly 15 comparisons")
    return summary, omnibus, pairwise


def curve_table(data: pd.DataFrame, metric: str, model: str, algorithm: str) -> pd.DataFrame:
    subset = data.loc[
        data["algorithm"].eq(algorithm)
        & data["base_eligible"]
        & (
            (data["comm_model"].eq("ideal") & data["degradation_pct"].eq(0))
            | (data["comm_model"].eq(model) & data["degradation_pct"].isin(DEGRADED_LEVELS))
        )
        & valid_metric(data, metric),
        ["trial_id", "degradation_pct", metric],
    ].copy()
    if subset.duplicated(["trial_id", "degradation_pct"]).any():
        raise AssertionError(f"Duplicate curve point for {data['scenario'].iat[0]} {metric} {model} {algorithm}")
    curves = subset.pivot(index="trial_id", columns="degradation_pct", values=metric).reindex(columns=LEVELS)
    curves = curves.dropna(axis=0, how="any")
    values = curves.to_numpy(dtype=float)
    if METRIC_OFFSETS[metric] == 0:
        curves = curves.loc[(values > 0).all(axis=1)]
    return curves


def compute_degradation_analysis(all_data: dict[str, pd.DataFrame]) -> tuple[pd.DataFrame, ...]:
    prds_rows: list[dict] = []
    prda_rows: list[dict] = []
    prda_test_rows: list[dict] = []
    sample_rows: list[dict] = []
    comparison_rows: list[dict] = []
    sanity_candidates: list[dict] = []

    for spec in SCENARIOS:
        data = all_data[spec.short_name]
        total_trials = int(data["trial_id"].nunique())
        for model in MODELS:
            for metric in scenario_metrics(spec.short_name):
                curves_by_algorithm = {
                    algorithm: curve_table(data, metric, model, algorithm) for algorithm in ALGORITHMS
                }
                common_ids = pd.Index(
                    sorted(
                        set.intersection(
                            *(set(curves.index.tolist()) for curves in curves_by_algorithm.values())
                        )
                    ),
                    name="trial_id",
                )
                common_n = len(common_ids)
                offset = METRIC_OFFSETS[metric]

                for algorithm, curves in curves_by_algorithm.items():
                    algorithm_complete_n = len(curves)
                    curves = curves.loc[common_ids]
                    z = np.log(curves.to_numpy(dtype=float) + offset)
                    centered_levels = LEVELS - LEVELS.mean()
                    beta = ((z - z.mean(axis=1, keepdims=True)) * centered_levels).sum(axis=1) / np.square(centered_levels).sum()
                    values = 100.0 * (np.exp(beta) - 1.0)
                    stats = descriptive(values)
                    test = wilcoxon_signed_rank(values)
                    prds_rows.append(
                        {
                            "mission": spec.mission,
                            "scenario": spec.short_name,
                            "comm_model": model,
                            "metric": metric,
                            "algorithm": algorithm,
                            "total_trial_count": total_trials,
                            **stats,
                            "wilcoxon_nonzero_n": test["nonzero_n"],
                            "wilcoxon_w_positive": test["w_positive"],
                            "wilcoxon_w_negative": test["w_negative"],
                            "wilcoxon_p_two_sided": test["p_raw"],
                            "rank_biserial": test["rank_biserial"],
                            "log_offset_c": offset,
                            "units": "percent metric change per +1 percentage point degradation",
                            "source_column": METRIC_SOURCES[metric],
                            "eligibility_rule": "common-six complete: all six algorithms have completed/eligible finite metric values at ideal and all eight model levels for the same trial IDs",
                            "ci_method": "two-sided 95% Student-t interval for the mean",
                            "wilcoxon_method": test["test_method"],
                        }
                    )
                    ids = sorted(int(x) for x in curves.index)
                    sample_rows.append(
                        {
                            "mission": spec.mission,
                            "scenario": spec.short_name,
                            "comm_model": model,
                            "metric": metric,
                            "method": "PRDS common-six complete",
                            "algorithm_a": algorithm,
                            "algorithm_b": "",
                            "eligible_n": len(ids),
                            "eligible_trial_ids": ";".join(map(str, ids)),
                        }
                    )
                    comparison_rows.append(
                        {
                            "mission": spec.mission,
                            "scenario": spec.short_name,
                            "comm_model": model,
                            "metric": metric,
                            "method": "PRDS",
                            "algorithm_a": algorithm,
                            "algorithm_b": "",
                            "previous_eligibility_n": algorithm_complete_n,
                            "common_six_eligible_n": common_n,
                            "trajectories_excluded_by_common_six": algorithm_complete_n - common_n,
                        }
                    )

                family_tests: list[dict] = []
                for algorithm_a, algorithm_b in itertools.combinations(ALGORITHMS, 2):
                    curves_a_all = curves_by_algorithm[algorithm_a]
                    curves_b_all = curves_by_algorithm[algorithm_b]
                    pairwise_ids = curves_a_all.index.intersection(curves_b_all.index).sort_values()
                    curves_a = curves_a_all.loc[common_ids]
                    curves_b = curves_b_all.loc[common_ids]
                    ids = common_ids
                    a = curves_a.loc[ids].to_numpy(dtype=float)
                    b = curves_b.loc[ids].to_numpy(dtype=float)
                    relative = np.log(a + offset) - np.log(b + offset)
                    degradation = relative - relative[:, [0]]
                    values = (100.0 / 70.0) * np.trapezoid(degradation, LEVELS, axis=1)
                    stats = descriptive(values)
                    test = wilcoxon_signed_rank(values)
                    base = {
                        "mission": spec.mission,
                        "scenario": spec.short_name,
                        "comm_model": model,
                        "metric": metric,
                        "algorithm_a": algorithm_a,
                        "algorithm_b": algorithm_b,
                        "pair": f"{algorithm_a} vs {algorithm_b}",
                        "total_trial_count": total_trials,
                    }
                    prda_rows.append(
                        {
                            **base,
                            **stats,
                            "log_offset_c": offset,
                            "units": "mean log-relative-degradation x 100",
                            "source_column": METRIC_SOURCES[metric],
                            "eligibility_rule": "common-six complete: all six algorithms have completed/eligible finite metric values at ideal and all eight model levels for the same trial IDs",
                            "interpretation": "negative: algorithm_a became relatively better; positive: algorithm_a became relatively worse",
                            "ci_method": "two-sided 95% Student-t interval for the mean",
                        }
                    )
                    family_tests.append(
                        {
                            **base,
                            "eligible_n": len(values),
                            "nonzero_n": test["nonzero_n"],
                            "w_positive": test["w_positive"],
                            "w_negative": test["w_negative"],
                            "p_raw": test["p_raw"],
                            "rank_biserial": test["rank_biserial"],
                            "test_method": test["test_method"],
                        }
                    )
                    int_ids = sorted(int(x) for x in ids)
                    sample_rows.append(
                        {
                            "mission": spec.mission,
                            "scenario": spec.short_name,
                            "comm_model": model,
                            "metric": metric,
                            "method": "PRDA common-six complete",
                            "algorithm_a": algorithm_a,
                            "algorithm_b": algorithm_b,
                            "eligible_n": len(int_ids),
                            "eligible_trial_ids": ";".join(map(str, int_ids)),
                        }
                    )
                    comparison_rows.append(
                        {
                            "mission": spec.mission,
                            "scenario": spec.short_name,
                            "comm_model": model,
                            "metric": metric,
                            "method": "PRDA",
                            "algorithm_a": algorithm_a,
                            "algorithm_b": algorithm_b,
                            "previous_eligibility_n": len(pairwise_ids),
                            "common_six_eligible_n": common_n,
                            "trajectories_excluded_by_common_six": len(pairwise_ids) - common_n,
                        }
                    )
                    if metric == "max_agent_steps" and len(ids):
                        chosen = int(np.argmax(np.abs(values)))
                        sanity_candidates.append(
                            {
                                **base,
                                "trial_id": int(ids[chosen]),
                                "prda": float(values[chosen]),
                                **{f"D_at_{int(q)}pct": float(degradation[chosen, idx]) for idx, q in enumerate(LEVELS)},
                                "manual_sign_check": "negative means A improved relative to B; positive means A worsened relative to B",
                            }
                        )

                adjusted = holm_adjust([row["p_raw"] for row in family_tests])
                if len(adjusted) != 15:
                    raise AssertionError("PRDA Holm family does not contain 15 algorithm pairs")
                for row, p_holm in zip(family_tests, adjusted, strict=True):
                    row["p_holm"] = p_holm
                    row["reject_raw_0_05"] = row["p_raw"] < 0.05
                    row["reject_holm_0_05"] = p_holm < 0.05
                    row["holm_family"] = f"{spec.short_name}|{model}|{metric}|15 pairs"
                    prda_test_rows.append(row)

    sanity = pd.DataFrame(sanity_candidates)
    if len(sanity):
        sanity = (
            sanity.assign(sign=lambda x: np.sign(x["prda"]))
            .sort_values(["scenario", "comm_model", "sign", "prda"])
            .groupby(["scenario", "comm_model"], as_index=False, group_keys=False)
            .head(2)
            .drop(columns="sign")
        )
    return (
        pd.DataFrame(prds_rows),
        pd.DataFrame(prda_rows),
        pd.DataFrame(prda_test_rows),
        pd.DataFrame(sample_rows),
        pd.DataFrame(comparison_rows),
        sanity,
    )


def condition_metric_summary(all_data: dict[str, pd.DataFrame]) -> pd.DataFrame:
    rows: list[dict] = []
    plotted_metrics = [
        "post_clue_steps_to_find",
        "max_agent_steps",
        "total_team_steps",
        "team_messages_per_step",
        "allocation_publications_per_mission",
        "unique_cell_contribution_gini",
        "target_completion_gini",
    ]
    for spec in SCENARIOS:
        data = all_data[spec.short_name]
        for metric in plotted_metrics:
            if metric not in data.columns:
                continue
            conditions = data[["comm_model", "degradation_pct", "comm_label"]].drop_duplicates()
            for condition in conditions.itertuples(index=False):
                subset = data.loc[
                    data["comm_model"].eq(condition.comm_model)
                    & data["degradation_pct"].eq(condition.degradation_pct)
                    & data["base_eligible"]
                    & valid_metric(data, metric),
                    ["trial_id", "algorithm", metric],
                ]
                matrix = subset.pivot(index="trial_id", columns="algorithm", values=metric).reindex(columns=ALGORITHMS)
                matrix = matrix.dropna(axis=0, how="any")
                if matrix.empty:
                    continue
                for algorithm in ALGORITHMS:
                    stats = descriptive(matrix[algorithm].to_numpy(dtype=float))
                    rows.append(
                        {
                            "mission": spec.mission,
                            "scenario": spec.short_name,
                            "comm_model": condition.comm_model,
                            "comm_label": condition.comm_label,
                            "degradation_pct": condition.degradation_pct,
                            "metric": metric,
                            "algorithm": algorithm,
                            "attempted_trial_n": int(data.loc[
                                data["comm_model"].eq(condition.comm_model)
                                & data["degradation_pct"].eq(condition.degradation_pct), "trial_id"
                            ].nunique()),
                            "six_way_paired_n": len(matrix),
                            **stats,
                            "source_column": METRIC_SOURCES[metric],
                            "scope": "six-way paired and conditional on mission completion",
                            "ci_method": "two-sided 95% Student-t interval for the mean",
                        }
                    )
    return pd.DataFrame(rows)


def condition_pairwise_tests(all_data: dict[str, pd.DataFrame]) -> pd.DataFrame:
    """Paired condition-level tests for every metric used in a main figure.

    This deliberately uses the same six-algorithm-complete matrix as
    ``condition_metric_summary`` so that the inferential statements and plotted
    means have identical trial support.  Holm correction is applied over the
    15 algorithm pairs within each mission/model/level/metric family.
    """
    rows: list[dict] = []
    plotted_metrics = [
        "post_clue_steps_to_find",
        "max_agent_steps",
        "total_team_steps",
        "team_messages_per_step",
        "allocation_publications_per_mission",
        "unique_cell_contribution_gini",
        "target_completion_gini",
    ]
    for spec in SCENARIOS:
        data = all_data[spec.short_name]
        for metric in plotted_metrics:
            if metric not in data.columns:
                continue
            conditions = data[["comm_model", "degradation_pct", "comm_label"]].drop_duplicates()
            for condition in conditions.itertuples(index=False):
                subset = data.loc[
                    data["comm_model"].eq(condition.comm_model)
                    & data["degradation_pct"].eq(condition.degradation_pct)
                    & data["base_eligible"]
                    & valid_metric(data, metric),
                    ["trial_id", "algorithm", metric],
                ]
                matrix = subset.pivot(index="trial_id", columns="algorithm", values=metric).reindex(columns=ALGORITHMS)
                matrix = matrix.dropna(axis=0, how="any")
                if matrix.empty:
                    continue
                family: list[dict] = []
                for algorithm_a, algorithm_b in itertools.combinations(ALGORITHMS, 2):
                    values_a = matrix[algorithm_a].to_numpy(dtype=float)
                    values_b = matrix[algorithm_b].to_numpy(dtype=float)
                    differences = values_b - values_a
                    test = wilcoxon_signed_rank(differences)
                    diff_stats = descriptive(differences)
                    family.append(
                        {
                            "family_id": (
                                f"{spec.short_name}|{metric}|{condition.comm_model}|"
                                f"{condition.degradation_pct:g}"
                            ),
                            "mission": spec.mission,
                            "scenario": spec.short_name,
                            "metric": metric,
                            "comm_model": condition.comm_model,
                            "comm_label": condition.comm_label,
                            "degradation_pct": condition.degradation_pct,
                            "paired_n": len(matrix),
                            "algorithm_a": algorithm_a,
                            "algorithm_b": algorithm_b,
                            "algorithm_a_mean": float(np.mean(values_a)),
                            "algorithm_b_mean": float(np.mean(values_b)),
                            "mean_difference_b_minus_a": diff_stats["mean"],
                            "median_difference_b_minus_a": diff_stats["median"],
                            "difference_ci95_low": diff_stats["ci95_low"],
                            "difference_ci95_high": diff_stats["ci95_high"],
                            "wilcoxon_nonzero_n": test["nonzero_n"],
                            "wilcoxon_w_positive": test["w_positive"],
                            "wilcoxon_w_negative": test["w_negative"],
                            "wilcoxon_p_raw": test["p_raw"],
                            "rank_biserial": test["rank_biserial"],
                            "wilcoxon_method": test["test_method"],
                            "scope": "six-way paired and conditional on mission completion",
                        }
                    )
                adjusted = holm_adjust([row["wilcoxon_p_raw"] for row in family])
                for row, p_holm in zip(family, adjusted, strict=True):
                    row["wilcoxon_p_holm"] = p_holm
                    row["reject_holm_0_05"] = p_holm < 0.05
                rows.extend(family)
    return pd.DataFrame(rows)


def realized_ge_drop_fractions(all_data: dict[str, pd.DataFrame]) -> pd.DataFrame:
    rows: list[dict] = []
    for spec in SCENARIOS:
        data = all_data[spec.short_name]
        ge = data.loc[data["comm_model"].eq("gilbert_elliott")].copy()
        for (level, algorithm), group in ge.groupby(["degradation_pct", "algorithm"], sort=True):
            recorded = pd.to_numeric(group["message_drop_fraction"], errors="coerce").to_numpy(dtype=float)
            recorded = recorded[np.isfinite(recorded)]
            drop_stats = descriptive(recorded)
            dropped = int(pd.to_numeric(group["messages_dropped_total"], errors="raise").sum())
            rows.append(
                {
                    "mission": spec.mission,
                    "scenario": spec.short_name,
                    "nominal_drop_pct": level,
                    "algorithm": algorithm,
                    "attempted_runs": len(group),
                    "completed_runs": int(group["trial_status"].astype("string").str.lower().eq("completed").sum()),
                    "failed_runs": int(group["trial_status"].astype("string").str.lower().ne("completed").sum()),
                    "recorded_fraction_n": drop_stats["eligible_n"],
                    "mean_trial_drop_fraction": drop_stats["mean"],
                    "median_trial_drop_fraction": drop_stats["median"],
                    "sd_trial_drop_fraction": drop_stats["sd"],
                    "mean_ci95_low": drop_stats["ci95_low"],
                    "mean_ci95_high": drop_stats["ci95_high"],
                    "total_recorded_dropped_receiver_deliveries": dropped,
                    "total_recorded_delivered_receiver_deliveries_all_topics": int(
                        pd.to_numeric(group["messages_delivered_total"], errors="raise").sum()
                    ),
                    "aggregation": "unweighted mean of stored per-trial message_drop_fraction; that simulator field excludes protected deliveries",
                    "scope": "all recorded runs, including partial event histories from failed FGS runs",
                    "pooled_fraction_note": "not computed: historical logs do not expose unprotected_delivered_total and can end with successful deliveries queued",
                }
            )
    return pd.DataFrame(rows)


def ge_audit_table() -> pd.DataFrame:
    corrected_matrix = "[[0.8+0.2q, 0.2(1-q)], [0.2q, 1-0.2q]] (rows GOOD/BAD; columns GOOD/BAD)"
    return pd.DataFrame(
        [
            {
                "mission": "Clue-Informed Probabilistic Search (CLIPS)",
                "source_file": "benchmark_sim/comms/models.py at f898015; corrected GE rerun restored from clue_500_combined",
                "parameter_mapping": "q=stationary delivery=1-nominal loss; pGG=q+0.8(1-q); pBB=(1-q)+0.8q",
                "good_delivery_rule": "probability 1",
                "bad_delivery_rule": "probability 0",
                "transition_matrix": corrected_matrix,
                "stationary_good": "q",
                "stationary_loss": "1-q",
                "lag1_state_correlation": "pGG+pBB-1=0.8",
                "initialization": "per directed link, GOOD with probability q (stationary initialization)",
                "transition_timing": "delivery evaluated from current state, then state transitions",
                "protected_bypass": "collision_intent and target publications bypass loss and do not advance link state",
                "matches_paper_fixed_rho_0_8": True,
                "classification": "A: corrected fixed-rho=0.8 GE rerun",
            },
            {
                "mission": "Collaborative Visit (CV)",
                "source_file": "known_visit_sim/comms/models.py at f898015; corrected GE rerun restored from known_visit_core_500_combined",
                "parameter_mapping": "q=stationary delivery=1-nominal loss; pGG=q+0.8(1-q); pBB=(1-q)+0.8q",
                "good_delivery_rule": "probability 1",
                "bad_delivery_rule": "probability 0",
                "transition_matrix": corrected_matrix,
                "stationary_good": "q",
                "stationary_loss": "1-q",
                "lag1_state_correlation": "pGG+pBB-1=0.8",
                "initialization": "per directed link, GOOD with probability q (stationary initialization)",
                "transition_timing": "delivery evaluated from current state, then state transitions",
                "protected_bypass": "collision_intent publications bypass loss and do not advance link state",
                "matches_paper_fixed_rho_0_8": True,
                "classification": "A: corrected fixed-rho=0.8 GE rerun",
            },
            {
                "mission": "Full Grid Search (FGS)",
                "source_file": "benchmark_sim/comms/models.py at f898015 and current HEAD; corrected GE rerun retained in active FGS bundle",
                "parameter_mapping": "q=stationary delivery=1-nominal loss; pGG=q+0.8(1-q); pBB=(1-q)+0.8q",
                "good_delivery_rule": "probability 1",
                "bad_delivery_rule": "probability 0",
                "transition_matrix": corrected_matrix,
                "stationary_good": "q",
                "stationary_loss": "1-q",
                "lag1_state_correlation": "pGG+pBB-1=0.8",
                "initialization": "per directed link, GOOD with probability q (stationary initialization)",
                "transition_timing": "delivery evaluated from current state, then state transitions",
                "protected_bypass": "collision_intent and target publications bypass loss and do not advance link state",
                "matches_paper_fixed_rho_0_8": True,
                "classification": "A: corrected fixed-rho=0.8 GE rerun",
            },
        ]
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_manifest() -> pd.DataFrame:
    rows: list[dict] = []
    for spec in SCENARIOS:
        for role, path in [
            ("system_performance", spec.system_path),
            ("trial_summary", spec.trial_path),
            ("robot_performance", spec.robot_path),
            ("condition_manifest", spec.manifest_path),
        ]:
            selected = not (role == "robot_performance" and spec.short_name in {"CLIPS", "FGS"})
            if selected:
                reason = "current scenario-prefixed combined result file used in analysis"
            else:
                reason = "documented and hashed but not loaded; current system table already contains the required maximum-agent fields"
            with path.open("rb") as handle:
                row_count = sum(1 for _ in handle) - 1
            rows.append(
                {
                    "mission": spec.mission,
                    "role": role,
                    "relative_path": path.relative_to(REPO_ROOT).as_posix(),
                    "size_bytes": path.stat().st_size,
                    "modified_local": datetime.fromtimestamp(path.stat().st_mtime).astimezone().isoformat(),
                    "sha256": sha256_file(path),
                    "data_rows": row_count,
                    "selected": selected,
                    "reason": reason,
                }
            )
        if spec.short_name in {"CLIPS", "CV"}:
            prefix = spec.result_set
            for role, path in [
                (
                    "corrected_ge_condition_manifest",
                    spec.folder / f"{prefix}_corrected_ge_condition_manifest.csv",
                ),
                ("corrected_ge_restore_manifest", spec.folder / "CORRECTED_GE_RESTORE_MANIFEST.json"),
            ]:
                with path.open("rb") as handle:
                    row_count = sum(1 for _ in handle) - (1 if path.suffix == ".csv" else 0)
                rows.append(
                    {
                        "mission": spec.mission,
                        "role": role,
                        "relative_path": path.relative_to(REPO_ROOT).as_posix(),
                        "size_bytes": path.stat().st_size,
                        "modified_local": datetime.fromtimestamp(path.stat().st_mtime).astimezone().isoformat(),
                        "sha256": sha256_file(path),
                        "data_rows": row_count,
                        "selected": False,
                        "reason": "provenance record for corrected fixed-rho=0.8 GE restoration from f898015",
                    }
                )
    return pd.DataFrame(rows)


def write_csv(frame: pd.DataFrame, filename: str) -> None:
    frame.to_csv(TABLE_DIR / filename, index=False, float_format="%.15g")


def validate_outputs(
    all_data: dict[str, pd.DataFrame],
    fgs_summary: pd.DataFrame,
    fgs_q: pd.DataFrame,
    fgs_pairs: pd.DataFrame,
    prds: pd.DataFrame,
    prda: pd.DataFrame,
    prda_tests: pd.DataFrame,
    condition_tests: pd.DataFrame,
) -> list[str]:
    checks: list[str] = []
    fgs = all_data["FGS"]
    ge = fgs.loc[fgs["comm_model"].eq("gilbert_elliott")]
    failed = ge["trial_status"].astype("string").str.lower().ne("completed")
    assert len(ge) == 4800 and int(failed.sum()) == 424
    assert ge.loc[failed, "failure_type"].astype("string").eq("RuntimeError").all()
    assert ge.loc[failed, "failure_message"].astype("string").str.contains("Debug safety cap reached", regex=False).all()
    # Failed combined rows deliberately carry no continuous metrics.  The
    # scheduler raises this exception inside the still-running coverage loop,
    # before a completed result row can be built; do not impute a cell count.
    assert pd.to_numeric(ge.loc[failed, "unique_cells_searched"], errors="coerce").isna().all()
    checks.append("FGS GE failures: 424/4,800; every failed row is a RuntimeError safety-cap termination and carries no imputed continuous metrics")

    expected_failures = {5: 0, 10: 0, 20: 6, 30: 16, 40: 27, 50: 74, 60: 133, 70: 168}
    actual_failures = ge.groupby("degradation_pct")["trial_status"].apply(lambda s: int(s.astype("string").str.lower().ne("completed").sum())).to_dict()
    assert actual_failures == expected_failures
    checks.append("FGS GE aggregate failures by level match 0,0,6,16,27,74,133,168")

    non_ge = fgs.loc[~fgs["comm_model"].eq("gilbert_elliott")]
    assert non_ge["trial_status"].astype("string").str.lower().eq("completed").all()
    checks.append("Every FGS run under Ideal, Bernoulli, and Rayleigh-style communication completed")

    expected_paired = {5: 100, 10: 100, 20: 94, 30: 85, 40: 77, 50: 41, 60: 24, 70: 17}
    actual_paired = (
        fgs_summary.loc[fgs_summary["comm_model"].eq("gilbert_elliott")]
        .groupby("degradation_pct")["six_way_paired_n_continuous_metrics"]
        .first()
        .astype(int)
        .to_dict()
    )
    assert actual_paired == expected_paired
    checks.append("FGS GE six-way paired counts match 100,100,94,85,77,41,24,17")

    for scenario in ["CLIPS", "CV"]:
        data = all_data[scenario]
        ge_data = data.loc[data["comm_model"].eq("gilbert_elliott")]
        assert len(ge_data) == 24000
        assert ge_data["trial_status"].astype("string").str.lower().eq("completed").all()
        assert ge_data["comm_label"].astype("string").str.contains("_rho_0_8", regex=False).all()
    checks.append("CLIPS and CV each contain 24,000 corrected fixed-rho=0.8 GE runs and zero recorded failures")

    assert (fgs_summary["attempted_trials"] == fgs_summary["completed_trials"] + fgs_summary["failed_trials"]).all()
    assert np.allclose(fgs_summary["completion_rate"] + fgs_summary["failure_rate"], 1.0)
    checks.append("Completion counts and rates add exactly")

    significant_conditions = int(fgs_q["significant_0_05"].sum())
    assert len(fgs_pairs) == 15 * significant_conditions
    checks.append(f"FGS Holm families: {significant_conditions} significant conditions x 15 comparisons")

    assert (prds["eligible_n"] > 0).all() and (prda["eligible_n"] > 0).all()
    family_sizes = prda_tests.groupby(["scenario", "comm_model", "metric"]).size()
    assert (family_sizes == 15).all()
    checks.append(f"PRDA Holm families: {len(family_sizes)} families, all exactly 15 comparisons")
    checks.append("All PRDS and PRDA summaries have positive eligible trajectory n")

    condition_family_sizes = condition_tests.groupby("family_id").size()
    assert (condition_family_sizes == 15).all()
    assert np.all(condition_tests["wilcoxon_p_holm"] + 1e-12 >= condition_tests["wilcoxon_p_raw"])
    assert (
        condition_tests.loc[
            condition_tests["scenario"].eq("CLIPS")
            & condition_tests["metric"].eq("post_clue_steps_to_find")
        ].shape[0]
        == 25 * 15
    )
    checks.append(
        f"Figure-metric condition tests: {len(condition_family_sizes)} Holm families, all exactly 15 comparisons; CLIPS post-clue tests cover 25 conditions"
    )
    return checks


def main() -> None:
    print("Reading current combined result files...")
    all_data = {spec.short_name: load_scenario(spec) for spec in SCENARIOS}

    print("Computing FGS completion/failure statistics...")
    fgs_summary, fgs_q, fgs_pairs = fgs_completion_analysis(all_data["FGS"])

    print("Computing common-six complete PRDS and PRDA...")
    prds, prda, prda_tests, sample_sizes, old_vs_new, sanity = compute_degradation_analysis(all_data)

    print("Computing plotting summaries and GE realized drop fractions...")
    condition_summary = condition_metric_summary(all_data)
    condition_tests = condition_pairwise_tests(all_data)
    ge_drops = realized_ge_drop_fractions(all_data)
    ge_audit = ge_audit_table()
    manifest = source_manifest()

    checks = validate_outputs(all_data, fgs_summary, fgs_q, fgs_pairs, prds, prda, prda_tests, condition_tests)

    write_csv(fgs_summary, "fgs_completion_failure_summary.csv")
    write_csv(fgs_q, "fgs_cochran_q_results.csv")
    write_csv(fgs_pairs, "fgs_pairwise_mcnemar_holm_results.csv")
    write_csv(prds, "revised_prds.csv")
    write_csv(prda, "revised_prda.csv")
    write_csv(prda_tests, "revised_prda_statistical_tests.csv")
    write_csv(sample_sizes, "trajectory_sample_sizes.csv")
    write_csv(old_vs_new, "trajectory_common_six_eligibility_audit.csv")
    write_csv(sanity, "prda_sign_sanity_checks.csv")
    write_csv(condition_summary, "publication_figure_condition_summary.csv")
    write_csv(condition_tests, "publication_condition_pairwise_tests.csv")
    write_csv(ge_drops, "gilbert_elliott_realized_drop_fractions.csv")
    write_csv(ge_audit, "gilbert_elliott_audit.csv")
    write_csv(manifest, "publication_analysis_source_manifest.csv")

    log_lines = [
        "DCTA publication analysis validation log",
        f"Generated UTC: {datetime.now(timezone.utc).isoformat()}",
        f"Script: {Path(__file__).relative_to(REPO_ROOT).as_posix()}",
        "Mean CI: two-sided 95% Student-t interval.",
        "Wilcoxon: normal approximation with continuity correction; zero differences excluded.",
        "McNemar: exact two-sided binomial test; Holm adjusted over 15 pairs per significant condition.",
        "Continuous FGS metrics: conditional on successful completion; no cap penalty assigned.",
        "",
        "VALIDATION CHECKS",
        *[f"PASS: {check}" for check in checks],
    ]
    (TABLE_DIR / "publication_analysis_validation_log.txt").write_text("\n".join(log_lines) + "\n", encoding="utf-8")

    print("Analysis completed. Validation checks:")
    for check in checks:
        print(f"  PASS: {check}")


if __name__ == "__main__":
    main()
