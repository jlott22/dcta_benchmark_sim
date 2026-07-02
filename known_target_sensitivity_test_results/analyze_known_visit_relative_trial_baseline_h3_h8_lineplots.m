%% analyze_known_visit_relative_trial_baseline_h3_h8_lineplots.m
% Fixed-horizon known-target drop-performance comparison.
%
% This is NOT a horizon sensitivity plot.
%
% For each horizon (h=3 and h=8), each trial, and each metric:
%   baseline(trial,h,metric) = mean metric across ALL algorithms under
%                              ideal and Bernoulli 0.25 for that same trial.
%
% Then each algorithm/condition row is scored as:
%   percent_better = 100 * (baseline - algorithm_value) / baseline
%
% Therefore, for these lower-is-better metrics:
%   positive = better than same-trial all-algorithm baseline
%   zero     = equal to same-trial all-algorithm baseline
%   negative = worse than same-trial all-algorithm baseline
%
% Outputs:
%   relative_trial_baseline_h3_h8_per_trial.csv
%   relative_trial_baseline_h3_h8_summary.csv
%   line plots in relative_trial_baseline_figs/

clear; clc; close all;

%% ---------------- User settings ----------------
csvPath = "C:\Users\lottj\Desktop\research\decentralized benchmark\dcta_benchmark_sim\known_target_sensitivity_test_results\horizon_results\combined\system_performance.csv";
outDir = 'relative_trial_baseline_figs';

horizonsToUse = [3 8];
bernoulliLevel = 0.25;

metricCols = { ...
    'total_team_steps', ...
    'messages_sent_total', ...
    'path_replans_total', ...
    'final_target_completion_time_s' ...
};

metricLabels = { ...
    'Total team steps', ...
    'Messages sent', ...
    'Path replans', ...
    'Final target completion time' ...
};

metricFileNames = { ...
    'total_team_steps', ...
    'messages_sent_total', ...
    'path_replans_total', ...
    'final_target_completion_time_s' ...
};

if ~isfile(csvPath)
    error('Could not find input CSV: %s. Put this script in the same folder as system_performance.csv or edit csvPath.', csvPath);
end
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

%% ---------------- Load and normalize ----------------
T = readtable(csvPath, 'VariableNamingRule', 'preserve');

requiredCols = [{'trial_id','algorithm','comm_model','comm_level','sensitivity_value'}, metricCols];
for i = 1:numel(requiredCols)
    if ~ismember(requiredCols{i}, T.Properties.VariableNames)
        error('Missing required column: %s', requiredCols{i});
    end
end

alg = string(T.algorithm);
commModel = lower(strtrim(string(T.comm_model)));
commLevel = double(T.comm_level);
trialId = double(T.trial_id);
horizon = local_numeric_vector(T.sensitivity_value);

isIdeal = commModel == "ideal";
isBernoulli = commModel == "bernoulli" & abs(commLevel - bernoulliLevel) < 1e-9;
isWantedComm = isIdeal | isBernoulli;
isWantedH = ismember(horizon, horizonsToUse);

T = T(isWantedComm & isWantedH, :);
alg = alg(isWantedComm & isWantedH);
commModel = commModel(isWantedComm & isWantedH);
commLevel = commLevel(isWantedComm & isWantedH);
trialId = trialId(isWantedComm & isWantedH);
horizon = horizon(isWantedComm & isWantedH);

commCondition = strings(height(T),1);
commCondition(commModel == "ideal") = "Ideal";
commCondition(commModel == "bernoulli") = "Bernoulli 0.25";

algorithms = unique(alg, 'stable');
% Keep a stable preferred order if present.
preferredOrder = ["ACBBA","PI","HIPC","DMCHBA","DGA","CBAA","AuctionGreedy"];
orderedAlgorithms = strings(0,1);
for i = 1:numel(preferredOrder)
    if any(algorithms == preferredOrder(i))
        orderedAlgorithms(end+1,1) = preferredOrder(i); %#ok<SAGROW>
    end
end
for i = 1:numel(algorithms)
    if ~any(orderedAlgorithms == algorithms(i))
        orderedAlgorithms(end+1,1) = algorithms(i); %#ok<SAGROW>
    end
end
algorithms = orderedAlgorithms;

%% ---------------- Compute per-trial baseline-relative percentages ----------------
outHorizon = [];
outTrial = [];
outMetric = strings(0,1);
outAlgorithm = strings(0,1);
outComm = strings(0,1);
outBaseline = [];
outValue = [];
outPctBetter = [];

for hIdx = 1:numel(horizonsToUse)
    h = horizonsToUse(hIdx);
    trials = unique(trialId(horizon == h));

    for mIdx = 1:numel(metricCols)
        metricName = metricCols{mIdx};
        valuesAll = double(T.(metricName));

        for tIdx = 1:numel(trials)
            tr = trials(tIdx);
            baselineMask = horizon == h & trialId == tr;
            baseline = mean(valuesAll(baselineMask), 'omitnan');

            if ~isfinite(baseline) || abs(baseline) < eps
                continue;
            end

            rowMask = baselineMask;
            rowIdx = find(rowMask);
            for r = rowIdx(:)'
                value = valuesAll(r);
                if ~isfinite(value)
                    continue;
                end
                pctBetter = 100.0 * (baseline - value) / baseline;

                outHorizon(end+1,1) = h; %#ok<SAGROW>
                outTrial(end+1,1) = tr; %#ok<SAGROW>
                outMetric(end+1,1) = string(metricName); %#ok<SAGROW>
                outAlgorithm(end+1,1) = alg(r); %#ok<SAGROW>
                outComm(end+1,1) = commCondition(r); %#ok<SAGROW>
                outBaseline(end+1,1) = baseline; %#ok<SAGROW>
                outValue(end+1,1) = value; %#ok<SAGROW>
                outPctBetter(end+1,1) = pctBetter; %#ok<SAGROW>
            end
        end
    end
end

perTrial = table(outHorizon, outTrial, outMetric, outAlgorithm, outComm, outBaseline, outValue, outPctBetter, ...
    'VariableNames', {'horizon','trial_id','metric','algorithm','comm_condition','trial_baseline','value','percent_better_than_trial_baseline'});

writetable(perTrial, fullfile(outDir, 'relative_trial_baseline_h3_h8_per_trial.csv'));

%% ---------------- Summarize ----------------
sumHorizon = [];
sumMetric = strings(0,1);
sumMetricLabel = strings(0,1);
sumAlgorithm = strings(0,1);
sumComm = strings(0,1);
sumMean = [];
sumMedian = [];
sumStd = [];
sumSEM = [];
sumN = [];

for hIdx = 1:numel(horizonsToUse)
    h = horizonsToUse(hIdx);
    for mIdx = 1:numel(metricCols)
        metricName = string(metricCols{mIdx});
        metricLabel = string(metricLabels{mIdx});
        for aIdx = 1:numel(algorithms)
            a = algorithms(aIdx);
            for cIdx = 1:2
                if cIdx == 1
                    c = "Ideal";
                else
                    c = "Bernoulli 0.25";
                end

                mask = perTrial.horizon == h & perTrial.metric == metricName & ...
                       perTrial.algorithm == a & perTrial.comm_condition == c;
                y = perTrial.percent_better_than_trial_baseline(mask);
                y = y(isfinite(y));
                if isempty(y)
                    continue;
                end

                sumHorizon(end+1,1) = h; %#ok<SAGROW>
                sumMetric(end+1,1) = metricName; %#ok<SAGROW>
                sumMetricLabel(end+1,1) = metricLabel; %#ok<SAGROW>
                sumAlgorithm(end+1,1) = a; %#ok<SAGROW>
                sumComm(end+1,1) = c; %#ok<SAGROW>
                sumMean(end+1,1) = mean(y, 'omitnan'); %#ok<SAGROW>
                sumMedian(end+1,1) = median(y, 'omitnan'); %#ok<SAGROW>
                sumStd(end+1,1) = std(y, 'omitnan'); %#ok<SAGROW>
                sumSEM(end+1,1) = std(y, 'omitnan') / sqrt(numel(y)); %#ok<SAGROW>
                sumN(end+1,1) = numel(y); %#ok<SAGROW>
            end
        end
    end
end

summary = table(sumHorizon, sumMetric, sumMetricLabel, sumAlgorithm, sumComm, sumMean, sumMedian, sumStd, sumSEM, sumN, ...
    'VariableNames', {'horizon','metric','metric_label','algorithm','comm_condition','mean_percent_better','median_percent_better','std_percent_better','sem_percent_better','n'});

writetable(summary, fullfile(outDir, 'relative_trial_baseline_h3_h8_summary.csv'));

%% ---------------- Line plots ----------------
% x-axis has two points: Ideal and Bernoulli 0.25.
% Each algorithm is one line. Separate figure for each metric and horizon.

x = [1 2];
xLabels = {'Ideal','Bernoulli 0.25'};

for hIdx = 1:numel(horizonsToUse)
    h = horizonsToUse(hIdx);
    for mIdx = 1:numel(metricCols)
        metricName = string(metricCols{mIdx});
        metricLabel = metricLabels{mIdx};
        metricFile = metricFileNames{mIdx};

        fig = figure('Color','w','Position',[100 100 950 580]);
        hold on; grid on; box on;

        for aIdx = 1:numel(algorithms)
            a = algorithms(aIdx);
            y = nan(1,2);
            for cIdx = 1:2
                if cIdx == 1
                    c = "Ideal";
                else
                    c = "Bernoulli 0.25";
                end
                mask = summary.horizon == h & summary.metric == metricName & ...
                       summary.algorithm == a & summary.comm_condition == c;
                if any(mask)
                    y(cIdx) = summary.mean_percent_better(find(mask,1,'first'));
                end
            end
            plot(x, y, '-o', 'LineWidth', 1.8, 'MarkerSize', 7, 'DisplayName', char(a));
        end

        yline(0, '--', 'Baseline', 'HandleVisibility','off');
        xlim([0.85 2.15]);
        xticks(x);
        xticklabels(xLabels);
        ylabel('% better than same-trial all-algorithm baseline');
        xlabel('Communication condition');
        title(sprintf('%s: relative performance at h=%d', metricLabel, h), 'Interpreter','none');
        subtitle('Positive means lower/better than the trial baseline');
        legend('Location','bestoutside');

        outBase = fullfile(outDir, sprintf('line_h%d_%s_relative_trial_baseline', h, metricFile));
        savefig(fig, [outBase '.fig']);
        exportgraphics(fig, [outBase '.png'], 'Resolution', 300);
        close(fig);
    end
end

%% ---------------- Optional compact all-metric plots per horizon ----------------
% These are also line graphs, but the x-axis is metric. Ideal and Bernoulli are
% plotted separately for each algorithm to make quick scanning easier.

for hIdx = 1:numel(horizonsToUse)
    h = horizonsToUse(hIdx);
    fig = figure('Color','w','Position',[100 100 1100 650]);
    hold on; grid on; box on;
    metricX = 1:numel(metricCols);

    for aIdx = 1:numel(algorithms)
        a = algorithms(aIdx);
        for cIdx = 1:2
            if cIdx == 1
                c = "Ideal";
                lineStyle = '-o';
            else
                c = "Bernoulli 0.25";
                lineStyle = '--s';
            end
            y = nan(1,numel(metricCols));
            for mIdx = 1:numel(metricCols)
                metricName = string(metricCols{mIdx});
                mask = summary.horizon == h & summary.metric == metricName & ...
                       summary.algorithm == a & summary.comm_condition == c;
                if any(mask)
                    y(mIdx) = summary.mean_percent_better(find(mask,1,'first'));
                end
            end
            plot(metricX, y, lineStyle, 'LineWidth', 1.5, 'MarkerSize', 6, ...
                'DisplayName', sprintf('%s - %s', char(a), char(c)));
        end
    end

    yline(0, '--', 'Baseline', 'HandleVisibility','off');
    xlim([0.8 numel(metricCols)+0.2]);
    xticks(metricX);
    xticklabels(metricLabels);
    xtickangle(20);
    ylabel('% better than same-trial all-algorithm baseline');
    xlabel('Metric');
    title(sprintf('Relative drop-performance summary at h=%d', h), 'Interpreter','none');
    subtitle('Positive means lower/better than same-trial baseline');
    legend('Location','bestoutside');

    outBase = fullfile(outDir, sprintf('line_h%d_all_metrics_relative_trial_baseline', h));
    savefig(fig, [outBase '.fig']);
    exportgraphics(fig, [outBase '.png'], 'Resolution', 300);
    close(fig);
end

fprintf('\n[DONE] Wrote outputs to: %s\n', outDir);
fprintf('  - relative_trial_baseline_h3_h8_per_trial.csv\n');
fprintf('  - relative_trial_baseline_h3_h8_summary.csv\n');
fprintf('  - line_h*_*.png/.fig\n\n');

%% ---------------- Local helper ----------------
function x = local_numeric_vector(v)
    if isnumeric(v)
        x = double(v);
        return;
    end
    s = string(v);
    x = nan(numel(s),1);
    for ii = 1:numel(s)
        token = erase(lower(strtrim(s(ii))), "h");
        x(ii) = str2double(token);
    end
end
