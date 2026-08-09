#!/usr/bin/env python3
"""Long-sequence verification of the GE factories used by all three missions."""

from __future__ import annotations

import random
import sys
from pathlib import Path

import numpy as np
import pandas as pd

ANALYSIS_DIR = Path(__file__).resolve().parent
REPO_ROOT = ANALYSIS_DIR.parents[1]
sys.path.insert(0, str(REPO_ROOT))

from benchmark_sim.comms.message import Message as BenchmarkMessage
from benchmark_sim.comms.models import make_comm_model as make_benchmark_model
from known_visit_sim.comms.message import Message as KnownVisitMessage
from known_visit_sim.comms.models import make_comm_model as make_known_visit_model


TABLE_DIR = ANALYSIS_DIR / "tables"
TABLE_DIR.mkdir(parents=True, exist_ok=True)
ATTEMPTS = 500_000
LEVELS = [0.95, 0.90, 0.80, 0.70, 0.60, 0.50, 0.40, 0.30]
IMPLEMENTATIONS = {
    "CLIPS_benchmark_sim": (make_benchmark_model, BenchmarkMessage),
    "CV_known_visit_sim": (make_known_visit_model, KnownVisitMessage),
    "FGS_benchmark_sim": (make_benchmark_model, BenchmarkMessage),
}


def run_lengths(binary_good: np.ndarray) -> tuple[float, float, int, int]:
    changes = np.flatnonzero(binary_good[1:] != binary_good[:-1]) + 1
    starts = np.r_[0, changes]
    ends = np.r_[changes, len(binary_good)]
    lengths = ends - starts
    states = binary_good[starts]
    good_lengths = lengths[states]
    bad_lengths = lengths[~states]
    return float(good_lengths.mean()), float(bad_lengths.mean()), len(good_lengths), len(bad_lengths)


def simulate(implementation: str, q: float, seed: int) -> dict:
    factory, message_type = IMPLEMENTATIONS[implementation]
    model = factory("gilbert_elliott", q)
    rng = random.Random(seed)
    message = message_type(sender="00", topic="state", payload={}, created_at_s=0.0)
    delivered = np.fromiter(
        (
            model.should_deliver(message, (0, 0), (1, 0), rng, ("00", "01"))
            for _ in range(ATTEMPTS)
        ),
        dtype=bool,
        count=ATTEMPTS,
    )
    drop = (~delivered).astype(float)
    lag_corr = float(np.corrcoef(drop[:-1], drop[1:])[0, 1])
    mean_good, mean_bad, good_runs, bad_runs = run_lengths(delivered)
    p_gg = float(model.p_good_to_good)
    p_bb = float(model.p_bad_to_bad)
    expected_rho = p_gg + p_bb - 1.0
    return {
        "implementation": implementation,
        "nominal_drop_pct": 100.0 * (1.0 - q),
        "stationary_delivery_q": q,
        "attempts": ATTEMPTS,
        "seed": seed,
        "p_gg": p_gg,
        "p_bb": p_bb,
        "initial_good_probability": float(model.initial_good_prob),
        "theoretical_drop_fraction": 1.0 - q,
        "estimated_drop_fraction": float(drop.mean()),
        "drop_fraction_error": float(drop.mean() - (1.0 - q)),
        "theoretical_lag1_state_drop_correlation": expected_rho,
        "estimated_lag1_drop_correlation": lag_corr,
        "lag1_correlation_error": lag_corr - expected_rho,
        "theoretical_mean_good_run": 1.0 / (1.0 - p_gg),
        "estimated_mean_good_run": mean_good,
        "good_run_count": good_runs,
        "theoretical_mean_bad_run": 1.0 / (1.0 - p_bb),
        "estimated_mean_bad_run": mean_bad,
        "bad_run_count": bad_runs,
        "delivery_evaluated_before_transition": True,
        "link_state_scope": "directed sender-receiver link",
    }


def main() -> None:
    rows = []
    for implementation in IMPLEMENTATIONS:
        for level_index, q in enumerate(LEVELS):
            # A common seed makes the cross-module check exact: the benchmark
            # and known-visit factories should generate identical sequences.
            rows.append(simulate(implementation, q, 20260809 + level_index))
    result = pd.DataFrame(rows)
    output = TABLE_DIR / "gilbert_elliott_sequence_verification.csv"
    result.to_csv(output, index=False, float_format="%.15g")

    max_drop_error = float(result["drop_fraction_error"].abs().max())
    max_corr_error = float(result["lag1_correlation_error"].abs().max())
    # With rho=0.8, 500,000 state draws have roughly one ninth the IID
    # effective sample size.  A one-percentage-point bound is conservative
    # across the eight stationary loss levels.
    if max_drop_error > 0.01:
        raise AssertionError(f"Drop calibration error too large: {max_drop_error}")
    if max_corr_error > 0.01:
        raise AssertionError(f"Fixed-rho estimate error too large: {max_corr_error}")
    grouped = result.groupby("implementation")["lag1_correlation_error"].apply(lambda s: float(s.abs().max()))
    print(f"Wrote {output}")
    print(f"Maximum absolute drop-fraction error: {max_drop_error:.6f}")
    for implementation, error in grouped.items():
        print(f"Maximum absolute rho error ({implementation}): {error:.6f}")


if __name__ == "__main__":
    main()
