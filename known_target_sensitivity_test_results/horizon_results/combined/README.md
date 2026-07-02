# Known-Visit Horizon Combined Results

This directory contains the combined outputs for all 120 conditions and
36,000 trials in the known-visit horizon sensitivity study.

`target_performance.csv` is split into three 120,000-row parts to keep every
repository object below GitHub's per-file size limit. Reconstruct it with:

```bash
awk 'FNR == 1 && NR != 1 { next } { print }' \
  target_performance_part1.csv \
  target_performance_part2.csv \
  target_performance_part3.csv \
  > target_performance.csv
```

The reconstructed file contains 360,000 data rows. All other combined CSVs
are stored as single files.
