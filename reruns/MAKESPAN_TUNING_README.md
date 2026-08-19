# Makespan-based horizon tuning

This package contains the frozen inputs, MATLAB analysis, generated decision
tables, verification checks, and figures for standalone horizon selection using
maximum-agent steps (makespan).

For each multi-task allocator, maximum-agent steps are averaged within each
matched trial across the ideal and 25% Bernoulli communication conditions. Only
trials containing every tested horizon in both conditions are retained. Among
eligible horizons `2, 3, 5, 8, 12`, the relative range is

`100 * (largest mean - smallest mean) / smallest mean`.

If the range is at most 1%, the curve is treated as practically
horizon-insensitive and the native default `h=3` is selected. Otherwise, the
horizon with the lowest mean makespan is selected. CBAA remains fixed at
`h=1`. The 1% threshold is a practical-sensitivity criterion, not a hypothesis
test.

Run the analysis from MATLAB with:

```matlab
run('reruns/generate_practical_sensitivity_horizon_tuning.m')
```

The active core-matrix reruns and start-overlap quarantine outputs are not part
of this published package.
