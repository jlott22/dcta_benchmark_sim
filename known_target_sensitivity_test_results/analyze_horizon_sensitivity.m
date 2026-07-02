%% analyze_horizon_sensitivity.m
% Horizon sensitivity analysis for the known-target DCTA benchmark.
%
% Input:
%   horizon_results/combined/system_performance.csv
%
% Required columns:
%   trial_id
%   algorithm
%   comm_model
%   comm_level
%   sensitivity_suite
%   sensitivity_label
%   total_team_steps
%
% Main outputs:
%   horizon_results/horizon_figs/horizon_summary_mean_steps.csv
%   horizon_results/horizon_figs/horizon_summary_within_algorithm.csv
%   horizon_results/horizon_figs/horizon_summary_change_from_h3.csv
%   horizon_results/horizon_figs/horizon_report_table.csv
%   horizon_results/horizon_figs/horizon_mean_steps_*.png/.fig
%   horizon_results/horizon_figs/horizon_within_algorithm_*.png/.fig
%   horizon_results/horizon_figs/horizon_change_vs_h3_*.png/.fig
%
% Notes:
%   - Cross-algorithm comparison has been removed.
%   - Within-algorithm graph uses each algorithm's own trial-level mean across
%     horizons as the baseline.
%   - Vs-h3 graph uses paired step difference relative to h3:
%         delta_steps = h3_steps - hX_steps
%     Positive means hX used fewer steps than h3.
%   - Paired t-tests are computed on delta_steps for each algorithm/comm/horizon.
%   - This script works for 50 trials or hundreds of trials as long as trial_id
%     is consistent across horizon settings.

clear; clc; close all;

%% ---------------- User settings ----------------
scriptDir = fileparts(mfilename('fullpath'));
csvPath = fullfile(scriptDir, 'horizon_results', 'combined', 'system_performance.csv');
outDir  = fullfile(scriptDir, 'horizon_results', 'horizon_figs');

metricCol = 'total_team_steps';

% Left to right: shortest to longest planning horizon.
hOrderLabels = {'h1', 'h2', 'h3', 'h5', 'h8', 'h12'};
hPrettyLabels = {'1', '2', '3', '5', '8', '12'};

% Baseline for paired comparison.
baselineSetting = 'h3';
baselinePretty = 'h3';

% Leave false unless zero-step trials should intentionally be removed.
excludeZeroSteps = false;

if ~exist(outDir, 'dir')
    mkdir(outDir);
end

%% ---------------- Load ----------------
T = readtable(csvPath);

requiredCols = {'trial_id', 'algorithm', 'comm_model', 'comm_level', ...
                'sensitivity_suite', 'sensitivity_label', metricCol};

for i = 1:numel(requiredCols)
    if ~ismember(requiredCols{i}, T.Properties.VariableNames)
        error('Missing required column: %s', requiredCols{i});
    end
end

%% ---------------- Normalize columns ----------------
T.trial_id_str = string(T.trial_id);
T.algorithm = string(T.algorithm);
T.comm_model = string(T.comm_model);
T.sensitivity_suite = string(T.sensitivity_suite);
T.sensitivity_label = string(T.sensitivity_label);

% Normalize comm_level. Ideal rows often have blank/NaN comm_level.
if isnumeric(T.comm_level)
    T.comm_level_str = string(T.comm_level);
else
    T.comm_level_str = string(T.comm_level);
end

missingLevel = ismissing(T.comm_level_str) | ...
               strlength(strtrim(T.comm_level_str)) == 0 | ...
               lower(strtrim(T.comm_level_str)) == "nan" | ...
               lower(strtrim(T.comm_level_str)) == "<missing>";

T.comm_level_str(missingLevel) = "ideal";

% Normalize setting into h1/h2/h3/h5/h8/h12.
% Handles "h12", "12", "horizon_12", etc.
rawSetting = lower(strtrim(T.sensitivity_label));
T.setting_norm = strings(height(T), 1);

for i = 1:height(T)
    s = rawSetting(i);
    tok = regexp(char(s), '\d+', 'match');
    if ~isempty(tok)
        T.setting_norm(i) = "h" + string(tok{1});
    else
        T.setting_norm(i) = s;
    end
end

% Keep only the known-target horizon study.
T = T(lower(strtrim(T.sensitivity_suite)) == "known_visit_horizon", :);

% Keep expected horizon values only.
keepH = false(height(T), 1);
for i = 1:numel(hOrderLabels)
    keepH = keepH | T.setting_norm == string(hOrderLabels{i});
end
T = T(keepH, :);

% Add metric.
T.metric = T.(metricCol);
T = T(~isnan(T.metric) & isfinite(T.metric), :);

if excludeZeroSteps
    T = T(T.metric > 0, :);
end

% Add numeric horizon order.
T.h_order = nan(height(T), 1);
for i = 1:numel(hOrderLabels)
    T.h_order(T.setting_norm == string(hOrderLabels{i})) = i;
end
T = T(~isnan(T.h_order), :);

% Remove rows with missing grouping keys.
badKey = ismissing(T.trial_id_str) | ismissing(T.algorithm) | ...
         ismissing(T.comm_model) | ismissing(T.comm_level_str) | ...
         ismissing(T.setting_norm);

T = T(~badKey, :);

fprintf('Loaded %d valid horizon rows before duplicate collapse.\n', height(T));

%% ---------------- Collapse duplicate rows if present ----------------
% One row per trial_id × algorithm × comm condition × horizon is expected.
% If duplicates exist, average them so paired comparisons are well-defined.

collapseVars = {'trial_id_str', 'algorithm', 'comm_model', ...
                'comm_level_str', 'setting_norm', 'h_order'};

[Gdup, Kdup] = findgroups(T(:, collapseVars));
metricMean = splitapply(@mean_omitnan, T.metric, Gdup);

Tclean = Kdup;
Tclean.metric = metricMean;
T = Tclean;

fprintf('Using %d unique trial/algorithm/comm/horizon rows after duplicate collapse.\n', height(T));

%% ---------------- Count check ----------------
countVars = {'algorithm', 'comm_model', 'comm_level_str', 'setting_norm'};
[Gc, countKey] = findgroups(T(:, countVars));
countKey.n_rows = splitapply(@numel, T.metric, Gc);
countKey = sortrows(countKey, {'comm_model', 'comm_level_str', 'algorithm', 'h_order'});
disp(countKey);

%% ================================================================
% Output 1: Mean steps by algorithm/horizon/comm
%
% Interpretation:
%   Lower mean_steps is better.
%% ================================================================

summaryMean = make_summary(T, ...
    {'algorithm', 'comm_model', 'comm_level_str', 'setting_norm', 'h_order'}, ...
    'metric');

summaryMean.Properties.VariableNames(end-5:end) = ...
    {'mean_steps', 'median_steps', 'std_steps', 'sem_steps', 'ci95_halfwidth_steps', 'n'};

summaryMean = sortrows(summaryMean, ...
    {'comm_model', 'comm_level_str', 'algorithm', 'h_order'});

writetable(summaryMean, fullfile(outDir, 'horizon_summary_mean_steps.csv'));

%% ================================================================
% Output 2: Within-algorithm horizon sensitivity
%
% Baseline:
%   mean total team steps within:
%   trial_id × algorithm × comm_model × comm_level
%   across all available horizon settings.
%
% Formula for each trial/horizon:
%   pct_better_than_trial_horizon_mean =
%       100 * (trial_horizon_mean - horizon_steps) / trial_horizon_mean
%
% Interpretation:
%   Positive = this horizon was better than that algorithm's own average
%   horizon on the same trial and communication condition.
%% ================================================================

baselineVars2 = {'trial_id_str', 'algorithm', 'comm_model', 'comm_level_str'};
T.within_alg_baseline_mean = grouped_mean_for_each_row(T, baselineVars2, 'metric');

T.within_alg_pct_better = 100 * ...
    (T.within_alg_baseline_mean - T.metric) ./ T.within_alg_baseline_mean;

T.within_alg_pct_better(~isfinite(T.within_alg_pct_better)) = NaN;

summaryWithin = make_summary(T, ...
    {'algorithm', 'comm_model', 'comm_level_str', 'setting_norm', 'h_order'}, ...
    'within_alg_pct_better');

summaryWithin.Properties.VariableNames(end-5:end) = ...
    {'mean_pct_better_than_trial_horizon_mean', ...
     'median_pct_better_than_trial_horizon_mean', ...
     'std_pct_better_than_trial_horizon_mean', ...
     'sem_pct_better_than_trial_horizon_mean', ...
     'ci95_halfwidth_pct_better_than_trial_horizon_mean', ...
     'n'};

summaryWithin = sortrows(summaryWithin, ...
    {'comm_model', 'comm_level_str', 'algorithm', 'h_order'});

writetable(summaryWithin, fullfile(outDir, 'horizon_summary_within_algorithm.csv'));

%% ================================================================
% Output 3: Paired comparison relative to h3
%
% Baseline:
%   h3 result for the same:
%   trial_id × algorithm × comm_model × comm_level
%
% Formula:
%   delta_steps = h3_steps - hX_steps
%
% Interpretation:
%   Positive delta = hX used fewer steps than h3, so hX was better.
%   Negative delta = hX used more steps than h3, so hX was worse.
%
% Also reports:
%   percent_improvement_of_paired_means =
%       100 * (mean(h3_steps) - mean(hX_steps)) / mean(h3_steps)
%
% Paired t-test:
%   tests whether mean(delta_steps) differs from 0.
%% ================================================================

summaryVsH3 = paired_vs_baseline_summary(T, baselineSetting, hOrderLabels);

summaryVsH3 = sortrows(summaryVsH3, ...
    {'comm_model', 'comm_level_str', 'algorithm', 'h_order'});

dropCsvName = sprintf('horizon_summary_change_from_%s.csv', baselineSetting);
writetable(summaryVsH3, fullfile(outDir, dropCsvName));

%% ---------------- Convenience report table ----------------
% One table that is easy to read in Excel/MATLAB:
% mean steps + within normalized sensitivity + paired-vs-h3 stats.

reportTable = outerjoin(summaryMean, summaryWithin, ...
    'Keys', {'algorithm', 'comm_model', 'comm_level_str', 'setting_norm', 'h_order'}, ...
    'MergeKeys', true);

reportTable = outerjoin(reportTable, summaryVsH3, ...
    'Keys', {'algorithm', 'comm_model', 'comm_level_str', 'setting_norm', 'h_order'}, ...
    'MergeKeys', true);

reportTable = sortrows(reportTable, ...
    {'comm_model', 'comm_level_str', 'algorithm', 'h_order'});

writetable(reportTable, fullfile(outDir, 'horizon_report_table.csv'));

%% ---------------- Plots ----------------

plot_by_comm(summaryMean, ...
    'mean_steps', ...
    'Mean horizon performance', ...
    'Mean total team steps (lower is better)', ...
    'horizon_mean_steps', ...
    outDir, hOrderLabels, hPrettyLabels, 'h_order', false);

plot_by_comm(summaryWithin, ...
    'mean_pct_better_than_trial_horizon_mean', ...
    'Within-algorithm horizon sensitivity', ...
    'Mean % better than own trial-level horizon average', ...
    'horizon_within_algorithm', ...
    outDir, hOrderLabels, hPrettyLabels, 'h_order', true);

plot_by_comm(summaryVsH3, ...
    'mean_delta_steps_vs_h3', ...
    sprintf('Paired horizon change relative to %s', baselinePretty), ...
    sprintf('Mean paired steps saved vs %s (positive = better)', baselinePretty), ...
    sprintf('horizon_change_vs_%s', baselineSetting), ...
    outDir, hOrderLabels, hPrettyLabels, 'h_order', true);

fprintf('\nDone. Figures and summary CSVs saved in:\n%s\n', outDir);
fprintf('\nRecommended reporting files:\n');
fprintf('  %s\n', fullfile(outDir, 'horizon_report_table.csv'));
fprintf('  %s\n', fullfile(outDir, 'horizon_summary_mean_steps.csv'));
fprintf('  %s\n', fullfile(outDir, dropCsvName));

%% ================================================================
% Local helper functions
%% ================================================================

function rowMeans = grouped_mean_for_each_row(T, groupVars, valueCol)
    [G, ~] = findgroups(T(:, groupVars));

    rowMeans = nan(height(T), 1);
    valid = ~isnan(G);

    if any(valid)
        groupMeans = splitapply(@mean_omitnan, T.(valueCol)(valid), G(valid));
        rowMeans(valid) = groupMeans(G(valid));
    end
end

function S = make_summary(T, groupVars, valueCol)
    [G, S] = findgroups(T(:, groupVars));

    vals = T.(valueCol);
    valid = ~isnan(G) & ~isnan(vals);

    Gv = G(valid);
    valsv = vals(valid);

    if isempty(Gv)
        S = S([], :);
        S.mean_value = [];
        S.median_value = [];
        S.std_value = [];
        S.sem_value = [];
        S.ci95_halfwidth_value = [];
        S.n_value = [];
        return;
    end

    S = S(unique(Gv), :);

    S.mean_value   = splitapply(@mean_omitnan, valsv, Gv);
    S.median_value = splitapply(@median_omitnan, valsv, Gv);
    S.std_value    = splitapply(@std_omitnan, valsv, Gv);
    S.sem_value    = splitapply(@sem_omitnan, valsv, Gv);
    S.ci95_halfwidth_value = splitapply(@ci95_halfwidth_omitnan, valsv, Gv);
    S.n_value      = splitapply(@n_valid, valsv, Gv);
end

function S = paired_vs_baseline_summary(T, baselineSetting, hOrderLabels)

    keyTable = unique(T(:, {'algorithm', 'comm_model', 'comm_level_str'}), 'rows');

    outRows = table();

    for ki = 1:height(keyTable)
        alg = keyTable.algorithm(ki);
        cm = keyTable.comm_model(ki);
        cl = keyTable.comm_level_str(ki);

        K = T(T.algorithm == alg & T.comm_model == cm & T.comm_level_str == cl, :);
        B = K(K.setting_norm == string(baselineSetting), :);

        if isempty(B)
            warning('No baseline %s rows for %s / %s / %s. Skipping.', ...
                baselineSetting, alg, cm, cl);
            continue;
        end

        Btab = table(B.trial_id_str, B.metric, ...
            'VariableNames', {'trial_id_str', 'baseline_steps'});

        for hi = 1:numel(hOrderLabels)
            h = string(hOrderLabels{hi});
            D = K(K.setting_norm == h, :);

            if isempty(D)
                continue;
            end

            Dtab = table(D.trial_id_str, D.metric, ...
                'VariableNames', {'trial_id_str', 'setting_steps'});

            P = innerjoin(Dtab, Btab, 'Keys', 'trial_id_str');

            if isempty(P)
                continue;
            end

            delta = P.baseline_steps - P.setting_steps;
            delta = delta(~isnan(delta) & isfinite(delta));

            nPairs = numel(delta);

            meanSetting = mean_omitnan(P.setting_steps);
            meanBaseline = mean_omitnan(P.baseline_steps);
            meanDelta = mean_omitnan(delta);
            medianDelta = median_omitnan(delta);
            stdDelta = std_omitnan(delta);
            semDelta = sem_omitnan(delta);
            ciHalf = ci95_halfwidth_omitnan(delta);

            if isfinite(meanBaseline) && abs(meanBaseline) > eps
                pctOfMeans = 100 * (meanBaseline - meanSetting) / meanBaseline;
            else
                pctOfMeans = NaN;
            end

            % Paired t-test on delta. For h3 vs h3 all deltas are zero;
            % report p/t as NaN because it is the reference condition.
            pVal = NaN;
            tStat = NaN;
            df = NaN;
            ciLow = NaN;
            ciHigh = NaN;
            cohenDz = NaN;

            if nPairs >= 2 && stdDelta > 0
                try
                    [~, pVal, ci, stats] = ttest(delta, 0);
                    ciLow = ci(1);
                    ciHigh = ci(2);
                    tStat = stats.tstat;
                    df = stats.df;
                catch
                    warning('ttest failed or Statistics Toolbox unavailable for %s / %s / %s / %s.', ...
                        alg, cm, cl, h);
                end

                cohenDz = meanDelta / stdDelta;
            elseif nPairs >= 1 && all(abs(delta) < eps)
                ciLow = 0;
                ciHigh = 0;
            end

            row = table(alg, cm, cl, h, hi, ...
                nPairs, meanSetting, meanBaseline, meanDelta, medianDelta, ...
                stdDelta, semDelta, ciHalf, ciLow, ciHigh, ...
                pctOfMeans, pVal, tStat, df, cohenDz, ...
                'VariableNames', {'algorithm', 'comm_model', 'comm_level_str', ...
                                  'setting_norm', 'h_order', ...
                                  'n_pairs', 'mean_steps', 'mean_h3_steps_for_pairs', ...
                                  'mean_delta_steps_vs_h3', 'median_delta_steps_vs_h3', ...
                                  'std_delta_steps_vs_h3', 'sem_delta_steps_vs_h3', ...
                                  'ci95_halfwidth_delta_steps_vs_h3', ...
                                  'ci95_low_delta_steps_vs_h3', ...
                                  'ci95_high_delta_steps_vs_h3', ...
                                  'pct_improvement_of_paired_means_vs_h3', ...
                                  'paired_ttest_p_vs_h3', 'paired_ttest_tstat_vs_h3', ...
                                  'paired_ttest_df_vs_h3', 'cohen_dz_vs_h3'});

            outRows = [outRows; row]; %#ok<AGROW>
        end
    end

    S = outRows;
end

function m = mean_omitnan(x)
    x = x(~isnan(x) & isfinite(x));
    if isempty(x)
        m = NaN;
    else
        m = mean(x);
    end
end

function med = median_omitnan(x)
    x = x(~isnan(x) & isfinite(x));
    if isempty(x)
        med = NaN;
    else
        med = median(x);
    end
end

function s = std_omitnan(x)
    x = x(~isnan(x) & isfinite(x));
    if numel(x) <= 1
        s = NaN;
    else
        s = std(x);
    end
end

function se = sem_omitnan(x)
    x = x(~isnan(x) & isfinite(x));
    n = numel(x);
    if n <= 1
        se = NaN;
    else
        se = std(x) / sqrt(n);
    end
end

function hw = ci95_halfwidth_omitnan(x)
    x = x(~isnan(x) & isfinite(x));
    n = numel(x);
    if n <= 1
        hw = NaN;
        return;
    end

    se = std(x) / sqrt(n);

    % Use tinv if available. Otherwise use 1.96 as a large-sample fallback.
    try
        tcrit = tinv(0.975, n - 1);
    catch
        tcrit = 1.96;
    end

    hw = tcrit * se;
end

function n = n_valid(x)
    n = sum(~isnan(x) & isfinite(x));
end

function plot_by_comm(S, yCol, plotTitleBase, yLabelText, filePrefix, outDir, orderLabels, prettyLabels, orderCol, showZeroLine)

    if isempty(S)
        warning('No rows to plot for %s.', filePrefix);
        return;
    end

    commKeys = unique(S(:, {'comm_model', 'comm_level_str'}), 'rows');

    for ci = 1:height(commKeys)
        cm = commKeys.comm_model(ci);
        cl = commKeys.comm_level_str(ci);

        D = S(S.comm_model == cm & S.comm_level_str == cl, :);
        algs = unique(D.algorithm, 'stable');

        f = figure('Color', 'w', 'Position', [100 100 1000 575]);
        hold on; grid on; box on;

        for ai = 1:numel(algs)
            alg = algs(ai);
            A = D(D.algorithm == alg, :);
            A = sortrows(A, orderCol);

            x = A.(orderCol);
            y = A.(yCol);

            plot(x, y, '-o', ...
                'LineWidth', 1.8, ...
                'MarkerSize', 6, ...
                'DisplayName', char(alg));
        end

        if showZeroLine
            yline(0, '--', 'HandleVisibility', 'off');
        end

        xlim([0.75, numel(orderLabels) + 0.25]);
        xticks(1:numel(orderLabels));
        xticklabels(prettyLabels);

        xlabel('Planning horizon setting');
        ylabel(yLabelText);

        title(sprintf('%s\n%s, level %s', plotTitleBase, cm, cl), ...
            'Interpreter', 'none');

        legend('Location', 'bestoutside', 'Interpreter', 'none');
        set(gca, 'FontSize', 12);

        safeCm = regexprep(char(cm), '[^\w\-]', '_');
        safeCl = regexprep(char(cl), '[^\w\-]', '_');

        pngPath = fullfile(outDir, sprintf('%s_%s_%s.png', filePrefix, safeCm, safeCl));
        figPath = fullfile(outDir, sprintf('%s_%s_%s.fig', filePrefix, safeCm, safeCl));

        try
            exportgraphics(f, pngPath, 'Resolution', 300);
        catch
            saveas(f, pngPath);
        end

        savefig(f, figPath);

        fprintf('Saved %s\n', pngPath);
    end
end
