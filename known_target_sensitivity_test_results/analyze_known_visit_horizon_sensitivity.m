%% analyze_known_visit_horizon_sensitivity.m
% Robust horizon-sensitivity analysis for the known-target / known-visit DCTA test.
%
% Put this file in the same folder as system_performance.csv, OR leave it in
% benchmark_sim/tests and edit csvPath below. The script writes CSV summaries
% and MATLAB/PNG figures to <csv folder>/horizon_figs.
%
% Main interpretation:
%   - Mean steps/time: lower is better.
%   - Within-algorithm % better: positive means that horizon beat that
%     algorithm's own average horizon on the same paired trial/comm condition.
%   - Vs h3 delta: delta = h3_steps - hX_steps. Positive means hX used fewer
%     steps than h3 on paired trials.
%
% This version fixes common errors from the older script:
%   - Does not sort count tables by missing h_order.
%   - Finds system_performance.csv automatically in common locations.
%   - Does not require Statistics Toolbox for basic summaries.
%   - Handles ideal comm_level as 1.0 or blank.
%   - Handles known_visit_horizon or generic horizon sensitivity_suite labels.

clear; clc; close all;

%% ---------------- User settings ----------------
% Leave as "" to auto-detect, or set directly, e.g.
% csvPath = '/home/jlott/dcta_benchmark_sim/runs/sensitivity_known_visit_horizon_300/combined/system_performance.csv';
csvPath = "";

metricCol = 'total_team_steps';
timeMetricCol = 'final_target_completion_time_s';

% Expected left-to-right horizon order.
hOrderLabels  = {'h1', 'h2', 'h3', 'h5', 'h8', 'h12'};
hPrettyLabels = {'1',  '2',  '3',  '5',  '8',  '12'};
baselineSetting = 'h3';

% Usually false. If true, incomplete trials are removed from step/time analyses.
completedOnlyForPerformance = false;

% Usually false. Zero-step rows are not expected, but this keeps the option.
excludeZeroSteps = false;

%% ---------------- Locate CSV and output directory ----------------
scriptDir = fileparts(mfilename('fullpath'));
if strlength(csvPath) == 0
    candidates = {
        fullfile(scriptDir, 'system_performance.csv')
        fullfile(pwd, 'system_performance.csv')
        fullfile(pwd, 'runs', 'sensitivity_known_visit_horizon_300', 'combined', 'system_performance.csv')
        fullfile(pwd, 'horizon_results', 'combined', 'system_performance.csv')
        fullfile(scriptDir, 'horizon_results', 'combined', 'system_performance.csv')
        };

    csvPath = "";
    for i = 1:numel(candidates)
        if isfile(candidates{i})
            csvPath = string(candidates{i});
            break;
        end
    end
end

if strlength(csvPath) == 0 || ~isfile(csvPath)
    error('Could not find system_performance.csv. Set csvPath near the top of this script.');
end

csvPath = char(csvPath);
outDir = fullfile(fileparts(csvPath), 'horizon_figs');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

fprintf('Reading: %s\n', csvPath);
fprintf('Writing outputs to: %s\n', outDir);

%% ---------------- Load ----------------
opts = detectImportOptions(csvPath, 'NumHeaderLines', 0);
% Preserve text columns where possible.
textCols = intersect(opts.VariableNames, {'trial_mode','algorithm','comm_model','condition_id', ...
    'scenario_file','messages_sent_by_topic','sensitivity_suite','sensitivity_parameter', ...
    'sensitivity_label','source_comm_folder','source_condition_folder','source_out_dir'});
for i = 1:numel(textCols)
    try
        opts = setvartype(opts, textCols{i}, 'string');
    catch
        % Older MATLAB fallback: ignore, normalization below will convert.
    end
end
Traw = readtable(csvPath, opts);
Traw.Properties.VariableNames = matlab.lang.makeValidName(Traw.Properties.VariableNames);

requiredCols = {'trial_id', 'algorithm', 'comm_model', 'comm_level', ...
                'sensitivity_suite', 'sensitivity_label', metricCol};
for i = 1:numel(requiredCols)
    if ~ismember(requiredCols{i}, Traw.Properties.VariableNames)
        error('Missing required column: %s', requiredCols{i});
    end
end

%% ---------------- Normalize columns ----------------
T = Traw;
T.trial_id_str = string(T.trial_id);
T.algorithm = string(T.algorithm);
T.comm_model = string(T.comm_model);
T.sensitivity_suite = string(T.sensitivity_suite);
T.sensitivity_label = string(T.sensitivity_label);

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

% Make ideal display cleaner. In your current CSV ideal is comm_level = 1.
isIdeal = lower(strtrim(T.comm_model)) == "ideal";
T.comm_level_str(isIdeal) = "1";

% Normalize horizon label into h1/h2/h3/h5/h8/h12.
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

% Keep horizon rows. Prefer known_visit_horizon, but fall back to any horizon
% sensitivity suite if the label in a future combined file changes.
suiteLower = lower(strtrim(T.sensitivity_suite));
keepSuite = suiteLower == "known_visit_horizon";
if ~any(keepSuite)
    keepSuite = contains(suiteLower, "horizon");
end
T = T(keepSuite, :);

% Keep expected horizon values only and add numeric order.
T.h_order = nan(height(T), 1);
for i = 1:numel(hOrderLabels)
    idx = T.setting_norm == string(hOrderLabels{i});
    T.h_order(idx) = i;
end
T = T(~isnan(T.h_order), :);

if isempty(T)
    error('No valid horizon rows found after filtering. Check sensitivity_suite and sensitivity_label columns.');
end

% Add main metric.
T.metric = double(T.(metricCol));
T = T(~isnan(T.metric) & isfinite(T.metric), :);

if completedOnlyForPerformance && ismember('all_targets_visited', T.Properties.VariableNames)
    T = T(toLogical(T.all_targets_visited), :);
end
if excludeZeroSteps
    T = T(T.metric > 0, :);
end

% Optional time metric.
hasTimeMetric = ismember(timeMetricCol, T.Properties.VariableNames);
if hasTimeMetric
    T.time_metric = double(T.(timeMetricCol));
end

% Remove rows with missing grouping keys.
badKey = ismissing(T.trial_id_str) | ismissing(T.algorithm) | ...
         ismissing(T.comm_model) | ismissing(T.comm_level_str) | ...
         ismissing(T.setting_norm);
T = T(~badKey, :);

fprintf('Loaded %d valid horizon rows before duplicate collapse.\n', height(T));

%% ---------------- Collapse duplicate rows if present ----------------
collapseVars = {'trial_id_str', 'algorithm', 'comm_model', ...
                'comm_level_str', 'setting_norm', 'h_order'};

[Gdup, Kdup] = findgroups(T(:, collapseVars));
Tclean = Kdup;
Tclean.metric = splitapply(@mean_omitnan, T.metric, Gdup);

% Preserve useful optional columns by grouped mean/rate.
if hasTimeMetric
    Tclean.time_metric = splitapply(@mean_omitnan, T.time_metric, Gdup);
end

optionalNumeric = {'completed_target_count','target_count','duplicate_target_visits', ...
    'target_conflicts','task_cell_revisits_total','task_cell_replans_total', ...
    'path_replans_total','collision_prevention_events','stall_recoveries_total', ...
    'messages_sent_total','allocation_messages_sent_total','message_drop_fraction', ...
    'workload_gini_targets_found','workload_gini_unique_cells_contributed'};
for i = 1:numel(optionalNumeric)
    col = optionalNumeric{i};
    if ismember(col, T.Properties.VariableNames)
        Tclean.(col) = splitapply(@mean_omitnan, double(T.(col)), Gdup);
    end
end

if ismember('all_targets_visited', T.Properties.VariableNames)
    Tclean.all_targets_visited_rate = splitapply(@mean_omitnan, double(toLogical(T.all_targets_visited)), Gdup);
else
    Tclean.all_targets_visited_rate = ones(height(Tclean), 1);
end

T = Tclean;
fprintf('Using %d unique trial/algorithm/comm/horizon rows after duplicate collapse.\n', height(T));

%% ---------------- Count check ----------------
countVars = {'algorithm', 'comm_model', 'comm_level_str', 'setting_norm', 'h_order'};
[Gc, countKey] = findgroups(T(:, countVars));
countKey.n_rows = splitapply(@numel, T.metric, Gc);
countKey = sortrows(countKey, {'comm_model', 'comm_level_str', 'algorithm', 'h_order'});
writetable(countKey, fullfile(outDir, 'horizon_row_counts.csv'));
disp(countKey);

%% ---------------- Summaries ----------------
summaryMean = make_summary(T, ...
    {'algorithm', 'comm_model', 'comm_level_str', 'setting_norm', 'h_order'}, ...
    'metric');
summaryMean.Properties.VariableNames(end-5:end) = ...
    {'mean_steps', 'median_steps', 'std_steps', 'sem_steps', 'ci95_halfwidth_steps', 'n'};
summaryMean = sortrows(summaryMean, {'comm_model', 'comm_level_str', 'algorithm', 'h_order'});
writetable(summaryMean, fullfile(outDir, 'horizon_summary_mean_steps.csv'));

if hasTimeMetric && ismember('time_metric', T.Properties.VariableNames)
    summaryTime = make_summary(T, ...
        {'algorithm', 'comm_model', 'comm_level_str', 'setting_norm', 'h_order'}, ...
        'time_metric');
    summaryTime.Properties.VariableNames(end-5:end) = ...
        {'mean_completion_time_s', 'median_completion_time_s', 'std_completion_time_s', ...
         'sem_completion_time_s', 'ci95_halfwidth_completion_time_s', 'n'};
    summaryTime = sortrows(summaryTime, {'comm_model', 'comm_level_str', 'algorithm', 'h_order'});
    writetable(summaryTime, fullfile(outDir, 'horizon_summary_completion_time.csv'));
end

summaryCompletion = make_summary(T, ...
    {'algorithm', 'comm_model', 'comm_level_str', 'setting_norm', 'h_order'}, ...
    'all_targets_visited_rate');
summaryCompletion.Properties.VariableNames(end-5:end) = ...
    {'mean_completion_rate', 'median_completion_rate', 'std_completion_rate', ...
     'sem_completion_rate', 'ci95_halfwidth_completion_rate', 'n'};
summaryCompletion = sortrows(summaryCompletion, {'comm_model', 'comm_level_str', 'algorithm', 'h_order'});
writetable(summaryCompletion, fullfile(outDir, 'horizon_summary_completion_rate.csv'));

% Additional available metric summaries.
extraSummaries = {'duplicate_target_visits','target_conflicts','task_cell_revisits_total', ...
    'task_cell_replans_total','path_replans_total','collision_prevention_events', ...
    'stall_recoveries_total','messages_sent_total','allocation_messages_sent_total', ...
    'message_drop_fraction','workload_gini_targets_found','workload_gini_unique_cells_contributed'};
for i = 1:numel(extraSummaries)
    col = extraSummaries{i};
    if ismember(col, T.Properties.VariableNames)
        Sx = make_summary(T, {'algorithm', 'comm_model', 'comm_level_str', 'setting_norm', 'h_order'}, col);
        Sx.Properties.VariableNames(end-5:end) = strcat({'mean_','median_','std_','sem_','ci95_halfwidth_','n_'}, col);
        Sx.Properties.VariableNames{end} = 'n';
        Sx = sortrows(Sx, {'comm_model', 'comm_level_str', 'algorithm', 'h_order'});
        writetable(Sx, fullfile(outDir, ['horizon_summary_' col '.csv']));
    end
end

%% ---------------- Within-algorithm paired horizon baseline ----------------
baselineVars2 = {'trial_id_str', 'algorithm', 'comm_model', 'comm_level_str'};
T.within_alg_baseline_mean = grouped_mean_for_each_row(T, baselineVars2, 'metric');
T.within_alg_pct_better = 100 * (T.within_alg_baseline_mean - T.metric) ./ T.within_alg_baseline_mean;
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
summaryWithin = sortrows(summaryWithin, {'comm_model', 'comm_level_str', 'algorithm', 'h_order'});
writetable(summaryWithin, fullfile(outDir, 'horizon_summary_within_algorithm.csv'));

%% ---------------- Paired h3 comparison ----------------
summaryVsH3 = paired_vs_baseline(T, hOrderLabels, baselineSetting);
summaryVsH3 = sortrows(summaryVsH3, {'comm_model', 'comm_level_str', 'algorithm', 'h_order'});
writetable(summaryVsH3, fullfile(outDir, 'horizon_summary_change_from_h3.csv'));

%% ---------------- Report table ----------------
reportTable = summaryMean(:, {'algorithm','comm_model','comm_level_str','setting_norm','h_order', ...
    'mean_steps','median_steps','ci95_halfwidth_steps','n'});
reportTable = outerjoin(reportTable, summaryCompletion(:, {'algorithm','comm_model','comm_level_str','setting_norm','h_order','mean_completion_rate'}), ...
    'Keys', {'algorithm','comm_model','comm_level_str','setting_norm','h_order'}, 'MergeKeys', true);
if exist('summaryTime', 'var')
    reportTable = outerjoin(reportTable, summaryTime(:, {'algorithm','comm_model','comm_level_str','setting_norm','h_order','mean_completion_time_s'}), ...
        'Keys', {'algorithm','comm_model','comm_level_str','setting_norm','h_order'}, 'MergeKeys', true);
end
if ismember('duplicate_target_visits', T.Properties.VariableNames)
    dupSummary = make_summary(T, {'algorithm','comm_model','comm_level_str','setting_norm','h_order'}, 'duplicate_target_visits');
    dupSummary.Properties.VariableNames(end-5:end) = {'mean_duplicate_target_visits','median_duplicate_target_visits','std_duplicate_target_visits','sem_duplicate_target_visits','ci95_duplicate_target_visits','n_dup'};
    reportTable = outerjoin(reportTable, dupSummary(:, {'algorithm','comm_model','comm_level_str','setting_norm','h_order','mean_duplicate_target_visits'}), ...
        'Keys', {'algorithm','comm_model','comm_level_str','setting_norm','h_order'}, 'MergeKeys', true);
end
reportTable = sortrows(reportTable, {'comm_model', 'comm_level_str', 'algorithm', 'h_order'});
writetable(reportTable, fullfile(outDir, 'horizon_report_table.csv'));

%% ---------------- Plots ----------------
plot_by_comm(summaryMean, 'mean_steps', ...
    'Known-target horizon sensitivity: mean total team steps', ...
    'Mean total team steps (lower is better)', ...
    'horizon_mean_steps', outDir, hOrderLabels, hPrettyLabels, 'h_order', false);

if exist('summaryTime', 'var')
    plot_by_comm(summaryTime, 'mean_completion_time_s', ...
        'Known-target horizon sensitivity: mean completion time', ...
        'Mean final target completion time, s (lower is better)', ...
        'horizon_completion_time', outDir, hOrderLabels, hPrettyLabels, 'h_order', false);
end

plot_by_comm(summaryWithin, 'mean_pct_better_than_trial_horizon_mean', ...
    'Within-algorithm paired horizon effect', ...
    '% better than own paired horizon mean (positive is better)', ...
    'horizon_within_algorithm', outDir, hOrderLabels, hPrettyLabels, 'h_order', true);

plot_by_comm(summaryVsH3, 'mean_delta_steps_vs_h3', ...
    'Paired change relative to h3', ...
    'h3 steps - hX steps (positive means hX better)', ...
    'horizon_change_vs_h3', outDir, hOrderLabels, hPrettyLabels, 'h_order', true);

plot_by_comm(summaryCompletion, 'mean_completion_rate', ...
    'Known-target horizon sensitivity: completion rate', ...
    'All-target completion rate', ...
    'horizon_completion_rate', outDir, hOrderLabels, hPrettyLabels, 'h_order', false);

fprintf('\nDone. Key outputs:\n');
fprintf('  %s\n', fullfile(outDir, 'horizon_summary_mean_steps.csv'));
fprintf('  %s\n', fullfile(outDir, 'horizon_summary_within_algorithm.csv'));
fprintf('  %s\n', fullfile(outDir, 'horizon_summary_change_from_h3.csv'));
fprintf('  %s\n', fullfile(outDir, 'horizon_report_table.csv'));

%% ========================================================================
% Local helper functions
%% ========================================================================

function S = make_summary(T, groupVars, valueCol)
    [G, K] = findgroups(T(:, groupVars));
    x = double(T.(valueCol));
    S = K;
    S.mean_value = splitapply(@mean_omitnan, x, G);
    S.median_value = splitapply(@median_omitnan, x, G);
    S.std_value = splitapply(@std_omitnan, x, G);
    S.sem_value = splitapply(@sem_omitnan, x, G);
    S.ci95_halfwidth_value = splitapply(@ci95_halfwidth_omitnan, x, G);
    S.n_value = splitapply(@n_valid, x, G);
end

function baseline = grouped_mean_for_each_row(T, groupVars, valueCol)
    [G, ~] = findgroups(T(:, groupVars));
    groupMean = splitapply(@mean_omitnan, double(T.(valueCol)), G);
    baseline = groupMean(G);
end

function S = paired_vs_baseline(T, hOrderLabels, baselineSetting)
    outRows = table();
    keyTable = unique(T(:, {'algorithm', 'comm_model', 'comm_level_str'}), 'rows');

    for ki = 1:height(keyTable)
        alg = keyTable.algorithm(ki);
        cm = keyTable.comm_model(ki);
        cl = keyTable.comm_level_str(ki);

        K = T(T.algorithm == alg & T.comm_model == cm & T.comm_level_str == cl, :);
        B = K(K.setting_norm == string(baselineSetting), :);
        if isempty(B)
            continue;
        end

        Btab = table(B.trial_id_str, B.metric, 'VariableNames', {'trial_id_str','baseline_steps'});

        for hi = 1:numel(hOrderLabels)
            h = string(hOrderLabels{hi});
            D = K(K.setting_norm == h, :);
            if isempty(D)
                continue;
            end
            Dtab = table(D.trial_id_str, D.metric, 'VariableNames', {'trial_id_str','setting_steps'});
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

            pVal = NaN; tStat = NaN; df = NaN; ciLow = NaN; ciHigh = NaN; cohenDz = NaN;
            if nPairs >= 2
                if stdDelta > 0
                    tStat = meanDelta / (stdDelta / sqrt(nPairs));
                    df = nPairs - 1;
                    cohenDz = meanDelta / stdDelta;
                    try
                        pVal = 2 * (1 - tcdf(abs(tStat), df));
                    catch
                        pVal = NaN;
                    end
                    try
                        tcrit = tinv(0.975, df);
                    catch
                        tcrit = 1.96;
                    end
                    ciLow = meanDelta - tcrit * stdDelta / sqrt(nPairs);
                    ciHigh = meanDelta + tcrit * stdDelta / sqrt(nPairs);
                else
                    % All paired deltas are identical.
                    if all(abs(delta) < eps)
                        tStat = 0; df = nPairs - 1; pVal = 1; ciLow = 0; ciHigh = 0; cohenDz = 0;
                    else
                        tStat = sign(meanDelta) * Inf; df = nPairs - 1; pVal = 0; ciLow = meanDelta; ciHigh = meanDelta;
                    end
                end
            elseif nPairs == 1
                ciLow = meanDelta; ciHigh = meanDelta;
            end

            row = table(alg, cm, cl, h, hi, nPairs, meanSetting, meanBaseline, ...
                meanDelta, medianDelta, stdDelta, semDelta, ciHalf, ciLow, ciHigh, ...
                pctOfMeans, pVal, tStat, df, cohenDz, ...
                'VariableNames', {'algorithm','comm_model','comm_level_str','setting_norm','h_order', ...
                'n_pairs','mean_steps','mean_h3_steps_for_pairs','mean_delta_steps_vs_h3', ...
                'median_delta_steps_vs_h3','std_delta_steps_vs_h3','sem_delta_steps_vs_h3', ...
                'ci95_halfwidth_delta_steps_vs_h3','ci95_low_delta_steps_vs_h3', ...
                'ci95_high_delta_steps_vs_h3','pct_improvement_of_paired_means_vs_h3', ...
                'paired_ttest_p_vs_h3','paired_ttest_tstat_vs_h3','paired_ttest_df_vs_h3','cohen_dz_vs_h3'});
            outRows = [outRows; row]; %#ok<AGROW>
        end
    end
    S = outRows;
end

function m = mean_omitnan(x)
    x = x(~isnan(x) & isfinite(x));
    if isempty(x), m = NaN; else, m = mean(x); end
end

function med = median_omitnan(x)
    x = x(~isnan(x) & isfinite(x));
    if isempty(x), med = NaN; else, med = median(x); end
end

function s = std_omitnan(x)
    x = x(~isnan(x) & isfinite(x));
    if numel(x) <= 1, s = NaN; else, s = std(x); end
end

function se = sem_omitnan(x)
    x = x(~isnan(x) & isfinite(x));
    n = numel(x);
    if n <= 1, se = NaN; else, se = std(x) / sqrt(n); end
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

function y = toLogical(x)
    if islogical(x)
        y = x;
    elseif isnumeric(x)
        y = x ~= 0;
    else
        xs = lower(strtrim(string(x)));
        y = xs == "true" | xs == "1" | xs == "yes";
    end
end

function plot_by_comm(S, yCol, plotTitleBase, yLabelText, filePrefix, outDir, orderLabels, prettyLabels, orderCol, showZeroLine)
    if isempty(S)
        warning('No rows to plot for %s.', filePrefix);
        return;
    end
    if ~ismember(yCol, S.Properties.VariableNames)
        warning('Column %s not found. Skipping plot %s.', yCol, filePrefix);
        return;
    end

    commKeys = unique(S(:, {'comm_model', 'comm_level_str'}), 'rows');
    for ci = 1:height(commKeys)
        cm = commKeys.comm_model(ci);
        cl = commKeys.comm_level_str(ci);
        D = S(S.comm_model == cm & S.comm_level_str == cl, :);
        algs = unique(D.algorithm, 'stable');

        f = figure('Color', 'w', 'Position', [100 100 1050 600], 'Visible', 'off');
        hold on; grid on; box on;

        for ai = 1:numel(algs)
            alg = algs(ai);
            A = D(D.algorithm == alg, :);
            A = sortrows(A, orderCol);
            x = A.(orderCol);
            y = A.(yCol);
            plot(x, y, '-o', 'LineWidth', 1.8, 'MarkerSize', 6, 'DisplayName', char(alg));
        end

        if showZeroLine
            try
                yline(0, '--', 'HandleVisibility', 'off');
            catch
                xl = [0.75, numel(orderLabels) + 0.25];
                line(xl, [0 0], 'LineStyle', '--', 'Color', [0 0 0], 'HandleVisibility', 'off');
            end
        end

        xlim([0.75, numel(orderLabels) + 0.25]);
        xticks(1:numel(orderLabels));
        xticklabels(prettyLabels);
        xlabel('Planning horizon');
        ylabel(yLabelText);
        title(sprintf('%s\n%s, level %s', plotTitleBase, cm, cl), 'Interpreter', 'none');
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
        try
            savefig(f, figPath);
        catch
            saveas(f, figPath);
        end
        close(f);
        fprintf('Saved %s\n', pngPath);
    end
end
