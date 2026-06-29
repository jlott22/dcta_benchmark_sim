%% analyze_iteration_sensitivity.m
% DGA iteration-count sensitivity analysis for DCTA benchmark.
%
% Input:
%   iteration_results/system_performance.csv
%   OR system_performance.csv in the current working directory.
%
% Required columns:
%   trial_id
%   algorithm                e.g., DGA_iter_1, DGA_iter_2, DGA_iter_5, ...
%   comm_model
%   comm_level
%   post_clue_steps_to_find
%
% Main outputs:
%   iteration_results/iteration_figs/iteration_summary_mean_steps.csv
%   iteration_results/iteration_figs/iteration_summary_within_algorithm.csv
%   iteration_results/iteration_figs/iteration_summary_change_from_iter5.csv
%   iteration_results/iteration_figs/iteration_report_table.csv
%   iteration_results/iteration_figs/iteration_mean_steps_*.png/.fig
%   iteration_results/iteration_figs/iteration_within_algorithm_*.png/.fig
%   iteration_results/iteration_figs/iteration_change_vs_iter5_*.png/.fig
%
% Notes:
%   - Cross-algorithm comparison is not produced.
%   - The script parses the iteration count from algorithm names like DGA_iter_10.
%   - Within-algorithm graph uses each base algorithm's own trial-level mean
%     across iteration settings as the baseline.
%   - Vs-iter5 graph uses paired step difference relative to iter5:
%         delta_steps = iter5_steps - iterX_steps
%     Positive means iterX used fewer steps than iter5.
%   - Paired t-tests are computed on delta_steps for each comm condition and
%     iteration setting.
%   - This script works for 50 trials or hundreds of trials as long as trial_id
%     is consistent across iteration settings.

clear; clc; close all;

%% ---------------- User settings ----------------
outRoot = 'dga_iteration';
csvPath = fullfile(outRoot, 'system_performance.csv');

if ~isfile(csvPath)
    error('Could not find input CSV: %s', csvPath);
end

outDir = fullfile(outRoot, 'iteration_figs');
metricCol = 'post_clue_steps_to_find';

% Baseline for paired comparison. Change this only if you want a different
% reference iteration count.
baselineIter = 5;

% Leave false unless you intentionally want to remove cases where target was
% found before or at clue discovery.
excludeZeroPostClue = false;

if ~exist(outDir, 'dir')
    mkdir(outDir);
end

%% ---------------- Load ----------------
T = readtable(csvPath);

requiredCols = {'trial_id', 'algorithm', 'comm_model', 'comm_level', metricCol};
for i = 1:numel(requiredCols)
    if ~ismember(requiredCols{i}, T.Properties.VariableNames)
        error('Missing required column: %s', requiredCols{i});
    end
end

%% ---------------- Normalize columns ----------------
T.trial_id_str = string(T.trial_id);
T.algorithm_raw = string(T.algorithm);
T.comm_model = string(T.comm_model);

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

% Parse iteration count from algorithm strings, e.g. DGA_iter_10.
T.iter_value = nan(height(T), 1);
T.base_algorithm = strings(height(T), 1);
T.setting_norm = strings(height(T), 1);

for i = 1:height(T)
    alg = char(T.algorithm_raw(i));
    tok = regexp(alg, '^(.*)_iter_?(\d+)$', 'tokens', 'once');

    if isempty(tok)
        % More permissive fallback: any algorithm name containing iter + number.
        tok2 = regexp(alg, 'iter_?(\d+)', 'tokens', 'once');
        if isempty(tok2)
            warning('Could not parse iteration count from algorithm name: %s. Row will be dropped.', alg);
            continue;
        end
        T.iter_value(i) = str2double(tok2{1});
        T.base_algorithm(i) = regexprep(string(alg), '_?iter_?\d+', '');
    else
        T.base_algorithm(i) = string(tok{1});
        T.iter_value(i) = str2double(tok{2});
    end

    T.setting_norm(i) = "iter" + string(T.iter_value(i));
end

T.metric = T.(metricCol);
T = T(~isnan(T.metric) & isfinite(T.metric), :);
T = T(~isnan(T.iter_value) & isfinite(T.iter_value), :);

if excludeZeroPostClue
    T = T(T.metric > 0, :);
end

% Remove rows with missing grouping keys.
badKey = ismissing(T.trial_id_str) | ismissing(T.base_algorithm) | ...
         ismissing(T.comm_model) | ismissing(T.comm_level_str) | ...
         ismissing(T.setting_norm);
T = T(~badKey, :);

% Sort/display order is numeric iteration count.
T.iter_order = T.iter_value;
iterValues = unique(T.iter_value);
iterValues = sort(iterValues(:))';
iterOrderLabels = "iter" + string(iterValues);
iterPrettyLabels = string(iterValues);

fprintf('Loaded %d valid iteration-sensitivity rows before duplicate collapse.\n', height(T));
fprintf('Detected iteration settings: %s\n', strjoin(iterOrderLabels, ', '));

%% ---------------- Collapse duplicate rows if present ----------------
% One row per trial_id x base_algorithm x comm condition x iteration setting is expected.
% If duplicates exist, average them so paired comparisons are well-defined.

collapseVars = {'trial_id_str', 'base_algorithm', 'comm_model', ...
                'comm_level_str', 'setting_norm', 'iter_value', 'iter_order'};

[Gdup, Kdup] = findgroups(T(:, collapseVars));
metricMean = splitapply(@mean_omitnan, T.metric, Gdup);

Tclean = Kdup;
Tclean.metric = metricMean;
T = Tclean;

fprintf('Using %d unique trial/base-algorithm/comm/iteration rows after duplicate collapse.\n', height(T));

%% ---------------- Count check ----------------
countVars = {'base_algorithm', 'comm_model', 'comm_level_str', 'setting_norm', 'iter_value', 'iter_order'};
[Gc, countKey] = findgroups(T(:, countVars));
countKey.n_rows = splitapply(@numel, T.metric, Gc);
countKey = sortrows(countKey, {'comm_model', 'comm_level_str', 'base_algorithm', 'iter_order'});
disp(countKey);

%% ================================================================
% Output 1: Mean steps by base algorithm / iteration / comm
%
% Interpretation:
%   Lower mean_steps is better.
%% ================================================================

summaryMean = make_summary(T, ...
    {'base_algorithm', 'comm_model', 'comm_level_str', 'setting_norm', 'iter_value', 'iter_order'}, ...
    'metric');

summaryMean.Properties.VariableNames(end-5:end) = ...
    {'mean_steps', 'median_steps', 'std_steps', 'sem_steps', 'ci95_halfwidth_steps', 'n'};

summaryMean = sortrows(summaryMean, ...
    {'comm_model', 'comm_level_str', 'base_algorithm', 'iter_order'});

writetable(summaryMean, fullfile(outDir, 'iteration_summary_mean_steps.csv'));

%% ================================================================
% Output 2: Within-algorithm iteration sensitivity
%
% Baseline:
%   mean post-clue steps within:
%   trial_id x base_algorithm x comm_model x comm_level
%   across all available iteration settings.
%
% Formula for each trial/iteration setting:
%   pct_better_than_trial_iteration_mean =
%       100 * (trial_iteration_mean - iter_steps) / trial_iteration_mean
%
% Interpretation:
%   Positive = this iteration count was better than that base algorithm's own
%   average iteration setting on the same trial and communication condition.
%% ================================================================

baselineVars2 = {'trial_id_str', 'base_algorithm', 'comm_model', 'comm_level_str'};
T.within_alg_baseline_mean = grouped_mean_for_each_row(T, baselineVars2, 'metric');

T.within_alg_pct_better = 100 * ...
    (T.within_alg_baseline_mean - T.metric) ./ T.within_alg_baseline_mean;
T.within_alg_pct_better(~isfinite(T.within_alg_pct_better)) = NaN;

summaryWithin = make_summary(T, ...
    {'base_algorithm', 'comm_model', 'comm_level_str', 'setting_norm', 'iter_value', 'iter_order'}, ...
    'within_alg_pct_better');

summaryWithin.Properties.VariableNames(end-5:end) = ...
    {'mean_pct_better_than_trial_iteration_mean', ...
     'median_pct_better_than_trial_iteration_mean', ...
     'std_pct_better_than_trial_iteration_mean', ...
     'sem_pct_better_than_trial_iteration_mean', ...
     'ci95_halfwidth_pct_better_than_trial_iteration_mean', ...
     'n'};

summaryWithin = sortrows(summaryWithin, ...
    {'comm_model', 'comm_level_str', 'base_algorithm', 'iter_order'});

writetable(summaryWithin, fullfile(outDir, 'iteration_summary_within_algorithm.csv'));

%% ================================================================
% Output 3: Paired comparison relative to iter5
%
% Baseline:
%   iter5 result for the same:
%   trial_id x base_algorithm x comm_model x comm_level
%
% Formula:
%   delta_steps = iter5_steps - iterX_steps
%
% Interpretation:
%   Positive delta = iterX used fewer steps than iter5, so iterX was better.
%   Negative delta = iterX used more steps than iter5, so iterX was worse.
%
% Also reports:
%   percent_improvement_of_paired_means =
%       100 * (mean(iter5_steps) - mean(iterX_steps)) / mean(iter5_steps)
%
% Paired t-test:
%   tests whether mean(delta_steps) differs from 0.
%% ================================================================

summaryVsBaseline = paired_vs_baseline_summary(T, baselineSetting, iterOrderLabels, baselinePretty);

summaryVsBaseline = sortrows(summaryVsBaseline, ...
    {'comm_model', 'comm_level_str', 'base_algorithm', 'iter_order'});

changeCsvName = sprintf('iteration_summary_change_from_%s.csv', char(baselineSetting));
writetable(summaryVsBaseline, fullfile(outDir, changeCsvName));

%% ---------------- Convenience report table ----------------
% One table that is easy to read in Excel/MATLAB:
% mean steps + within normalized sensitivity + paired-vs-iter5 stats.

reportTable = outerjoin(summaryMean, summaryWithin, ...
    'Keys', {'base_algorithm', 'comm_model', 'comm_level_str', 'setting_norm', 'iter_value', 'iter_order'}, ...
    'MergeKeys', true);

reportTable = outerjoin(reportTable, summaryVsBaseline, ...
    'Keys', {'base_algorithm', 'comm_model', 'comm_level_str', 'setting_norm', 'iter_value', 'iter_order'}, ...
    'MergeKeys', true);

reportTable = sortrows(reportTable, ...
    {'comm_model', 'comm_level_str', 'base_algorithm', 'iter_order'});

writetable(reportTable, fullfile(outDir, 'iteration_report_table.csv'));

%% ---------------- Plots ----------------

plot_by_comm(summaryMean, ...
    'mean_steps', ...
    'Mean iteration-count performance', ...
    'Mean post-clue steps to find target (lower is better)', ...
    'iteration_mean_steps', ...
    outDir, iterValues, iterPrettyLabels, 'iter_order', false);

plot_by_comm(summaryWithin, ...
    'mean_pct_better_than_trial_iteration_mean', ...
    'Within-algorithm iteration sensitivity', ...
    'Mean % better than own trial-level iteration average', ...
    'iteration_within_algorithm', ...
    outDir, iterValues, iterPrettyLabels, 'iter_order', true);

plot_by_comm(summaryVsBaseline, ...
    sprintf('mean_delta_steps_vs_%s', char(baselineSetting)), ...
    sprintf('Paired iteration-count change relative to %s', baselinePretty), ...
    sprintf('Mean paired steps saved vs %s (positive = better)', baselinePretty), ...
    sprintf('iteration_change_vs_%s', char(baselineSetting)), ...
    outDir, iterValues, iterPrettyLabels, 'iter_order', true);

fprintf('\nDone. Figures and summary CSVs saved in:\n%s\n', outDir);
fprintf('\nRecommended reporting files:\n');
fprintf('  %s\n', fullfile(outDir, 'iteration_report_table.csv'));
fprintf('  %s\n', fullfile(outDir, 'iteration_summary_mean_steps.csv'));
fprintf('  %s\n', fullfile(outDir, changeCsvName));

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
    valid = ~isnan(G) & ~isnan(vals) & isfinite(vals);

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

function S = paired_vs_baseline_summary(T, baselineSetting, settingOrderLabels, baselinePretty)

    keyTable = unique(T(:, {'base_algorithm', 'comm_model', 'comm_level_str'}), 'rows');
    outRows = table();

    for ki = 1:height(keyTable)
        alg = keyTable.base_algorithm(ki);
        cm = keyTable.comm_model(ki);
        cl = keyTable.comm_level_str(ki);

        K = T(T.base_algorithm == alg & T.comm_model == cm & T.comm_level_str == cl, :);
        B = K(K.setting_norm == string(baselineSetting), :);

        if isempty(B)
            warning('No baseline %s rows for %s / %s / %s. Skipping.', ...
                baselinePretty, alg, cm, cl);
            continue;
        end

        Btab = table(B.trial_id_str, B.metric, ...
            'VariableNames', {'trial_id_str', 'baseline_steps'});

        for hi = 1:numel(settingOrderLabels)
            setting = string(settingOrderLabels(hi));
            D = K(K.setting_norm == setting, :);

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
                        alg, cm, cl, setting);
                end
                cohenDz = meanDelta / stdDelta;
            elseif nPairs >= 1 && all(abs(delta) < eps)
                ciLow = 0;
                ciHigh = 0;
            end

            iterNum = str2double(regexprep(char(setting), '[^0-9]', ''));
            if isnan(iterNum)
                iterNum = hi;
            end

            meanDeltaName = sprintf('mean_delta_steps_vs_%s', char(baselineSetting));
            medianDeltaName = sprintf('median_delta_steps_vs_%s', char(baselineSetting));
            stdDeltaName = sprintf('std_delta_steps_vs_%s', char(baselineSetting));
            semDeltaName = sprintf('sem_delta_steps_vs_%s', char(baselineSetting));
            ciHalfName = sprintf('ci95_halfwidth_delta_steps_vs_%s', char(baselineSetting));
            ciLowName = sprintf('ci95_low_delta_steps_vs_%s', char(baselineSetting));
            ciHighName = sprintf('ci95_high_delta_steps_vs_%s', char(baselineSetting));
            pctName = sprintf('pct_improvement_of_paired_means_vs_%s', char(baselineSetting));
            pName = sprintf('paired_ttest_p_vs_%s', char(baselineSetting));
            tName = sprintf('paired_ttest_tstat_vs_%s', char(baselineSetting));
            dfName = sprintf('paired_ttest_df_vs_%s', char(baselineSetting));
            dzName = sprintf('cohen_dz_vs_%s', char(baselineSetting));
            baseMeanName = sprintf('mean_%s_steps_for_pairs', char(baselineSetting));

            row = table(alg, cm, cl, setting, iterNum, iterNum, ...
                nPairs, meanSetting, meanBaseline, meanDelta, medianDelta, ...
                stdDelta, semDelta, ciHalf, ciLow, ciHigh, ...
                pctOfMeans, pVal, tStat, df, cohenDz, ...
                'VariableNames', {'base_algorithm', 'comm_model', 'comm_level_str', ...
                                  'setting_norm', 'iter_value', 'iter_order', ...
                                  'n_pairs', 'mean_steps', baseMeanName, ...
                                  meanDeltaName, medianDeltaName, ...
                                  stdDeltaName, semDeltaName, ciHalfName, ...
                                  ciLowName, ciHighName, pctName, ...
                                  pName, tName, dfName, dzName});

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

function plot_by_comm(S, yCol, plotTitleBase, yLabelText, filePrefix, outDir, xValues, prettyLabels, orderCol, showZeroLine)

    if isempty(S)
        warning('No rows to plot for %s.', filePrefix);
        return;
    end

    commKeys = unique(S(:, {'comm_model', 'comm_level_str'}), 'rows');

    for ci = 1:height(commKeys)
        cm = commKeys.comm_model(ci);
        cl = commKeys.comm_level_str(ci);

        D = S(S.comm_model == cm & S.comm_level_str == cl, :);
        algs = unique(D.base_algorithm, 'stable');

        f = figure('Color', 'w', 'Position', [100 100 1000 575]);
        hold on; grid on; box on;

        for ai = 1:numel(algs)
            alg = algs(ai);
            A = D(D.base_algorithm == alg, :);
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

        xlim([min(xValues) - 0.05 * range_or_one(xValues), max(xValues) + 0.05 * range_or_one(xValues)]);
        xticks(xValues);
        xticklabels(prettyLabels);

        xlabel('DGA iterations per trigger');
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

function r = range_or_one(x)
    r = max(x) - min(x);
    if ~isfinite(r) || r <= 0
        r = 1;
    end
end
