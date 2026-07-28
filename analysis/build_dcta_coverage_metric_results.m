% build_dcta_coverage_metric_results.m
% Refresh coverage-only DCTA metrics and statistical tests, preserving the
% existing clue and known-target rows already written in analysis outputs.

dctaAnalysisRunMode = "coverage_append_only";
run(fullfile(fileparts(mfilename("fullpath")), "build_dcta_paired_metric_results.m"));
