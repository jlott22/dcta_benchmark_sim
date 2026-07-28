# Clue-Search Combined Results

The canonical combined CSVs in this directory contain the original ideal, Bernoulli, and Rayleigh rows plus the corrected bursty Gilbert-Elliott (rho = 0.8) rows completed in July 2026.

The exact pre-replacement combined files are preserved under `archive/pre_corrected_ge_20260727/`. `GE_REPLACEMENT_REPORT.json` records row counts, hashes, and validation results. `corrected_ge_condition_manifest.csv` preserves the GE transition parameters and source commands.

`robot_performance.csv` is stored as two ordered
`robot_performance_part_*.csv` files so every Git blob remains below GitHub's
100 MiB limit. `robot_performance_parts_manifest.csv` records their row counts
and SHA-256 hashes. The analysis loader concatenates the parts in filename
order.

Coverage results were not read or changed by this replacement.
