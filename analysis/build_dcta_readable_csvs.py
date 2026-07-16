from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd


ANALYSIS_DIR = Path(r"C:\Users\lottj\Desktop\research\decentralized benchmark\dcta_benchmark_sim\analysis")
INPUT_CSV = ANALYSIS_DIR / "dcta_paired_metric_results.csv"
FINAL_CSV = ANALYSIS_DIR / "dcta_final_metric_results.csv"
PAIRWISE_CSV = ANALYSIS_DIR / "dcta_pairwise_results.csv"

ALGORITHMS = ["CBAA", "ACBBA", "PI", "HIPC", "DMCHBA", "DGA"]
ALG_RANK = {name: idx for idx, name in enumerate(ALGORITHMS)}
REQUESTED_METRICS = {
    "max_agent_steps",
    "total_team_steps",
    "team_messages_per_step",
    "max_agent_messages",
    "messages_per_unique_cell",
    "unique_cell_contribution_gini",
    "team_task_replans",
    "team_path_replans",
    "system_cell_revisits",
    "duplicate_target_visits",
    "target_completion_gini",
    "messages_per_target",
}
RAYLEIGH_EXPECTED = {
    "-59.4": 5.0,
    "-56.04": 10.0,
    "-52.15": 20.0,
    "-49.17": 30.0,
    "-46.04": 40.0,
    "-42.16": 50.0,
    "-37.79": 60.0,
    "-32.58": 70.0,
}


def sort_frame(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df["_alg_rank"] = df["algorithm"].map(ALG_RANK)
    return df.sort_values(
        ["scenario", "metric_family", "metric", "result_type", "comm_model", "comm_level_pct", "_alg_rank"],
        na_position="last",
    ).drop(columns=["_alg_rank"])


def build_final_metric_results(detailed: pd.DataFrame) -> pd.DataFrame:
    summaries = detailed[
        (detailed["result_type"] == "condition_metric")
        & (detailed["comparison_type"] == "algorithm_summary")
    ].copy()
    field = detailed[
        (detailed["result_type"] == "condition_metric")
        & (detailed["comparison_type"] == "vs_field_mean")
    ].copy()

    key = ["scenario", "metric", "result_type", "comm_model", "comm_level_pct", "focal_algorithm"]
    condition = summaries.merge(
        field[
            key
            + [
                "comparison_mean",
                "mean_absolute_advantage",
                "percent_advantage",
            ]
        ],
        on=key,
        how="left",
        suffixes=("", "_field"),
        validate="one_to_one",
    )

    condition_out = pd.DataFrame(
        {
            "scenario": condition["scenario"],
            "metric": condition["metric"],
            "metric_family": condition["metric_family"],
            "result_type": "condition_metric",
            "comm_model": condition["comm_model"],
            "comm_level_pct": condition["comm_level_pct"],
            "algorithm": condition["focal_algorithm"],
            "eligible_paired_trials": condition["eligible_paired_trials"],
            "excluded_trials": condition["excluded_trials"],
            "mean_value": condition["focal_mean"],
            "median_value": condition["focal_median"],
            "ci95_low": condition["focal_ci95_low"],
            "ci95_high": condition["focal_ci95_high"],
            "field_mean": condition["comparison_mean_field"],
            "absolute_advantage_vs_field": condition["mean_absolute_advantage_field"],
            "percent_advantage_vs_field": condition["percent_advantage_field"],
            "prda": np.nan,
            "prda_ci95_low": np.nan,
            "prda_ci95_high": np.nan,
            "prds": np.nan,
            "prds_ci95_low": np.nan,
            "prds_ci95_high": np.nan,
            "units": condition["units"],
            "notes": condition["notes"],
        }
    )

    prda = detailed[
        (detailed["result_type"] == "prda")
        & (detailed["comparison_type"] == "algorithm_summary")
    ].copy()
    prds = detailed[
        (detailed["result_type"] == "prds")
        & (detailed["comparison_type"] == "algorithm_summary")
    ].copy()
    deg_key = ["scenario", "metric", "comm_model", "focal_algorithm"]
    degradation = prda.merge(
        prds[
            deg_key
            + [
                "focal_mean",
                "focal_ci95_low",
                "focal_ci95_high",
                "eligible_paired_trials",
                "excluded_trials",
                "notes",
            ]
        ],
        on=deg_key,
        how="inner",
        suffixes=("_prda", "_prds"),
        validate="one_to_one",
    )

    degradation_out = pd.DataFrame(
        {
            "scenario": degradation["scenario"],
            "metric": degradation["metric"],
            "metric_family": degradation["metric_family"],
            "result_type": "degradation_summary",
            "comm_model": degradation["comm_model"],
            "comm_level_pct": np.nan,
            "algorithm": degradation["focal_algorithm"],
            "eligible_paired_trials": degradation["eligible_paired_trials_prda"],
            "excluded_trials": degradation["excluded_trials_prda"],
            "mean_value": np.nan,
            "median_value": np.nan,
            "ci95_low": np.nan,
            "ci95_high": np.nan,
            "field_mean": np.nan,
            "absolute_advantage_vs_field": np.nan,
            "percent_advantage_vs_field": np.nan,
            "prda": degradation["focal_mean_prda"],
            "prda_ci95_low": degradation["focal_ci95_low_prda"],
            "prda_ci95_high": degradation["focal_ci95_high_prda"],
            "prds": degradation["focal_mean_prds"],
            "prds_ci95_low": degradation["focal_ci95_low_prds"],
            "prds_ci95_high": degradation["focal_ci95_high_prds"],
            "units": "prda_percentage_points; percent_metric_change_per_1pct_degradation",
            "notes": degradation["notes_prda"].astype(str) + " " + degradation["notes_prds"].astype(str),
        }
    )

    return sort_frame(pd.concat([condition_out, degradation_out], ignore_index=True))


def build_pairwise_results(detailed: pd.DataFrame) -> pd.DataFrame:
    pairs = detailed[detailed["comparison_type"] == "algorithm_pair"].copy()
    pairs = pairs[
        pairs["focal_algorithm"].map(ALG_RANK) < pairs["comparison_algorithm"].map(ALG_RANK)
    ].copy()

    out = pd.DataFrame(
        {
            "scenario": pairs["scenario"],
            "metric": pairs["metric"],
            "metric_family": pairs["metric_family"],
            "result_type": pairs["result_type"],
            "comm_model": pairs["comm_model"],
            "comm_level_pct": pairs["comm_level_pct"],
            "algorithm_a": pairs["focal_algorithm"],
            "algorithm_b": pairs["comparison_algorithm"],
            "eligible_paired_trials": pairs["eligible_paired_trials"],
            "algorithm_a_mean": pairs["focal_mean"],
            "algorithm_b_mean": pairs["comparison_mean"],
            "mean_difference": pairs["mean_absolute_advantage"],
            "median_difference": pairs["median_absolute_advantage"],
            "percent_advantage_algorithm_a": pairs["percent_advantage"],
            "ci95_low": pairs["ci95_low"],
            "ci95_high": pairs["ci95_high"],
            "percent_ci95_low": pairs["percent_ci95_low"],
            "percent_ci95_high": pairs["percent_ci95_high"],
            "units": pairs["units"],
            "notes": pairs["notes"],
        }
    )
    out["_alg_a"] = out["algorithm_a"].map(ALG_RANK)
    out["_alg_b"] = out["algorithm_b"].map(ALG_RANK)
    out = out.sort_values(
        [
            "scenario",
            "metric_family",
            "metric",
            "result_type",
            "comm_model",
            "comm_level_pct",
            "_alg_a",
            "_alg_b",
        ],
        na_position="last",
    )
    return out.drop(columns=["_alg_a", "_alg_b"])


def validate_outputs(detailed: pd.DataFrame, final_df: pd.DataFrame, pairwise_df: pd.DataFrame) -> list[str]:
    messages: list[str] = []

    reciprocal_key = pairwise_df.apply(
        lambda row: (
            row["scenario"],
            row["metric"],
            row["result_type"],
            row["comm_model"],
            row["comm_level_pct"],
            tuple(sorted([row["algorithm_a"], row["algorithm_b"]])),
        ),
        axis=1,
    )
    duplicate_pairs = int(reciprocal_key.duplicated().sum())
    if duplicate_pairs:
        raise AssertionError(f"Found {duplicate_pairs} reciprocal/duplicate unordered pair rows")
    messages.append("No reciprocal duplicate pairs in dcta_pairwise_results.csv")

    cond = final_df[final_df["result_type"] == "condition_metric"]
    cond_key = ["scenario", "metric", "comm_model", "comm_level_pct", "algorithm"]
    cond_dupes = int(cond.duplicated(cond_key).sum())
    expected_condition = detailed[
        (detailed["result_type"] == "condition_metric")
        & (detailed["comparison_type"] == "algorithm_summary")
    ][cond_key[:-1] + ["focal_algorithm"]].drop_duplicates().shape[0]
    if cond_dupes or len(cond) != expected_condition:
        raise AssertionError(
            f"Condition compact row validation failed: rows={len(cond)}, expected={expected_condition}, dupes={cond_dupes}"
        )
    messages.append("Exactly one condition row per scenario x metric x comm_model x comm_level_pct x algorithm")

    deg = final_df[final_df["result_type"] == "degradation_summary"]
    deg_key = ["scenario", "metric", "comm_model", "algorithm"]
    deg_dupes = int(deg.duplicated(deg_key).sum())
    expected_deg = detailed[
        (detailed["result_type"] == "prda")
        & (detailed["comparison_type"] == "algorithm_summary")
    ][["scenario", "metric", "comm_model", "focal_algorithm"]].drop_duplicates().shape[0]
    if deg_dupes or len(deg) != expected_deg:
        raise AssertionError(
            f"Degradation compact row validation failed: rows={len(deg)}, expected={expected_deg}, dupes={deg_dupes}"
        )
    messages.append("Exactly one degradation summary row per scenario x metric x comm_model x algorithm")

    metrics = set(final_df["metric"].unique()) | set(pairwise_df["metric"].unique())
    missing = sorted(REQUESTED_METRICS - metrics)
    if missing:
        raise AssertionError(f"Missing requested metrics: {missing}")
    messages.append("All requested metrics are present")

    if final_df["scenario"].str.contains("coverage", case=False, na=False).any() or pairwise_df["scenario"].str.contains("coverage", case=False, na=False).any():
        raise AssertionError("Coverage rows found")
    messages.append("No coverage rows present")

    if (final_df["metric"] == "team_path_churn").any() or (pairwise_df["metric"] == "team_path_churn").any():
        raise AssertionError("team_path_churn rows remain")
    messages.append("No team_path_churn rows remain")

    ray = detailed[
        (detailed["comm_model"] == "rayleigh_style")
        & (detailed["result_type"] == "condition_metric")
    ][["comm_level_raw", "comm_level_pct"]].drop_duplicates()
    for raw, expected in RAYLEIGH_EXPECTED.items():
        observed = ray.loc[ray["comm_level_raw"].astype(str) == raw, "comm_level_pct"].dropna().unique()
        if len(observed) != 1 or float(observed[0]) != expected:
            raise AssertionError(f"Rayleigh mapping mismatch for {raw}: observed={observed}, expected={expected}")
    messages.append("Rayleigh condition levels are correctly ordered from 5 to 70")

    bayes_deg = detailed[
        (detailed["scenario"] == "Bayesian clue-informed search")
        & (detailed["result_type"].isin(["prda", "prds"]))
    ]
    bad_total = int((bayes_deg["total_trial_count"] != 500).sum())
    bad_excluded = int((bayes_deg["excluded_trials"] != (500 - bayes_deg["eligible_paired_trials"])).sum())
    if bad_total or bad_excluded:
        raise AssertionError(f"Bayesian degradation metadata failed: bad_total={bad_total}, bad_excluded={bad_excluded}")
    messages.append("Bayesian degradation rows use total_trial_count=500 and excluded=500-eligible")

    return messages


def main() -> None:
    detailed = pd.read_csv(INPUT_CSV)
    detailed["metric"] = detailed["metric"].replace({"team_path_churn": "team_path_replans"})
    detailed.loc[
        detailed["metric"].isin(["team_task_replans", "team_path_replans"])
        & detailed["units"].eq("churn_events"),
        "units",
    ] = "replan_events"

    final_df = build_final_metric_results(detailed)
    pairwise_df = build_pairwise_results(detailed)

    final_df.to_csv(FINAL_CSV, index=False)
    pairwise_df.to_csv(PAIRWISE_CSV, index=False)

    messages = validate_outputs(detailed, final_df, pairwise_df)

    print("Created compact DCTA result CSVs")
    print(f"  {FINAL_CSV}")
    print(f"  {PAIRWISE_CSV}")
    print(f"dcta_final_metric_results.csv rows: {len(final_df)}")
    print(f"dcta_pairwise_results.csv rows: {len(pairwise_df)}")
    print("Metrics found:")
    print("  " + ", ".join(sorted(final_df["metric"].unique())))
    print("Scenarios found:")
    print("  " + ", ".join(sorted(final_df["scenario"].unique())))
    print("Communication models found:")
    print("  " + ", ".join(sorted(final_df["comm_model"].dropna().unique())))
    print("Validation:")
    for message in messages:
        print(f"  - {message}")

    print("\nExample final metric rows:")
    print(final_df.head(8).to_string(index=False))
    print("\nExample pairwise rows:")
    print(pairwise_df.head(8).to_string(index=False))


if __name__ == "__main__":
    main()
