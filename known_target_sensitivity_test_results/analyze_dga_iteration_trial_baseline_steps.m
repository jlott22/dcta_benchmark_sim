% Compare DGA iteration tuning for Collaborative Visit and Bayesian Search
% as step deltas from paired trial baselines.
%
% Metric: total_team_steps
% Baseline: within each scenario and trial_id, average total_team_steps across
% every tested DGA iteration value and both communication settings.
% Plotted value: for each scenario, iteration, and communication setting,
% mean over trial_id of (total_team_steps - paired_trial_baseline).
%
% Only fully paired trial IDs are used. A trial is included for a scenario
% only if it has exactly one valid row for every iteration x communication
% setting pair.

clear; clc;

scriptDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(scriptDir);
outDir = fullfile(scriptDir, 'dga_iteration', 'figs');
metricName = 'total_team_steps';
expectedIterations = [1, 2, 5, 10, 25, 50];
expectedComms = ["ideal", "bernoulli_025"];

scenarioSpecs = struct( ...
    'name', {'Collaborative Visit', 'Bayesian Search'}, ...
    'inputFile', { ...
        fullfile(scriptDir, 'dga_iteration', 'combined', 'system_performance.csv'), ...
        fullfile(repoRoot, 'clue_sensitivity_test_results', 'dga_iteration', 'system_performance.csv') ...
    });

if ~exist(outDir, 'dir')
    mkdir(outDir);
end

allSummary = table();
scenarioResults = struct( ...
    'name', {}, ...
    'meanDelta', {}, ...
    'meanSteps', {}, ...
    'semDelta', {}, ...
    'usedTrials', {}, ...
    'droppedTrials', {});

for si = 1:numel(scenarioSpecs)
    result = analyzeScenario( ...
        scenarioSpecs(si).name, ...
        scenarioSpecs(si).inputFile, ...
        metricName, ...
        expectedIterations, ...
        expectedComms);

    scenarioResults(end + 1) = result; %#ok<SAGROW>
    allSummary = [allSummary; makeSummaryRows(result, expectedIterations, expectedComms)]; %#ok<AGROW>

    fprintf('%s\n', result.name);
    fprintf('  Input: %s\n', scenarioSpecs(si).inputFile);
    fprintf('  Used fully paired trials: %d\n', result.usedTrials);
    fprintf('  Dropped incomplete trials: %d\n\n', result.droppedTrials);
end

summaryFile = fullfile(outDir, 'dga_iteration_scenario_trial_baseline_step_deltas.csv');
writetable(allSummary, summaryFile);
fprintf('Summary written to: %s\n\n', summaryFile);
disp(allSummary);

figure('Name', 'DGA iteration step delta comparison', 'Color', 'w');
hold on;
colors = lines(numel(scenarioResults));
markers = ["o", "s"];
lineStyles = ["-", ":"];
commLabels = ["Ideal", "Bernoulli p=0.25"];

for si = 1:numel(scenarioResults)
    for ci = 1:numel(expectedComms)
        displayName = sprintf('%s, %s', scenarioResults(si).name, char(commLabels(ci)));
        plot(expectedIterations, scenarioResults(si).meanDelta(ci, :), ...
            'LineStyle', char(lineStyles(ci)), ...
            'Marker', char(markers(ci)), ...
            'Color', colors(si, :), ...
            'LineWidth', 1.9, ...
            'MarkerSize', 7, ...
            'DisplayName', displayName);
    end
end

yline(0, '-', 'Color', [0.45 0.45 0.45], 'HandleVisibility', 'off');
hold off;

grid on;
xlabel('DGA iterations per trigger');
ylabel('Mean total-team-step difference from paired-trial baseline');
title('DGA iteration sensitivity by scenario');
xticks(expectedIterations);
legend('Location', 'best');

pngFile = fullfile(outDir, 'dga_iteration_scenario_trial_baseline_step_deltas.png');
figFile = fullfile(outDir, 'dga_iteration_scenario_trial_baseline_step_deltas.fig');
try
    exportgraphics(gcf, pngFile, 'Resolution', 300);
catch
    print(gcf, pngFile, '-dpng', '-r300');
end
savefig(gcf, figFile);
fprintf('Figure written to: %s\n', pngFile);
fprintf('MATLAB figure written to: %s\n', figFile);

function result = analyzeScenario(scenarioName, inputFile, metricName, expectedIterations, expectedComms)
    T = readtable(inputFile, 'TextType', 'string');
    if ~ismember(metricName, T.Properties.VariableNames)
        error('Metric column not found in %s: %s', inputFile, metricName);
    end

    if ismember('trial_status', T.Properties.VariableNames)
        T = T(T.trial_status ~= "failed", :);
    end

    T.metric_value = double(T.(metricName));
    T.iter_value = extractIteration(T);
    T.comm_plot = extractComm(T);
    T.trial_numeric = double(T.trial_id);

    valid = ...
        ~isnan(T.metric_value) & ...
        T.metric_value > 0 & ...
        ~isnan(T.iter_value) & ...
        ~isnan(T.trial_numeric) & ...
        ismember(T.iter_value, expectedIterations) & ...
        ismember(T.comm_plot, expectedComms);
    T = T(valid, :);

    trialIds = unique(T.trial_numeric)';
    nIterations = numel(expectedIterations);
    nComms = numel(expectedComms);
    deltaByCommIter = cell(nComms, nIterations);
    rawByCommIter = cell(nComms, nIterations);
    usedTrials = 0;
    droppedTrials = 0;

    for ti = 1:numel(trialIds)
        tid = trialIds(ti);
        values = nan(nComms, nIterations);
        complete = true;

        for ci = 1:nComms
            for ii = 1:nIterations
                rows = T( ...
                    T.trial_numeric == tid & ...
                    T.comm_plot == expectedComms(ci) & ...
                    T.iter_value == expectedIterations(ii), :);
                if height(rows) ~= 1
                    complete = false;
                    break;
                end
                values(ci, ii) = rows.metric_value(1);
            end
            if ~complete
                break;
            end
        end

        if ~complete || any(isnan(values(:)))
            droppedTrials = droppedTrials + 1;
            continue;
        end

        trialBaseline = mean(values(:));
        usedTrials = usedTrials + 1;

        for ci = 1:nComms
            for ii = 1:nIterations
                rawByCommIter{ci, ii}(end + 1) = values(ci, ii); %#ok<SAGROW>
                deltaByCommIter{ci, ii}(end + 1) = values(ci, ii) - trialBaseline; %#ok<SAGROW>
            end
        end
    end

    meanDelta = nan(nComms, nIterations);
    meanSteps = nan(nComms, nIterations);
    semDelta = nan(nComms, nIterations);
    for ci = 1:nComms
        for ii = 1:nIterations
            deltas = deltaByCommIter{ci, ii};
            rawSteps = rawByCommIter{ci, ii};
            meanDelta(ci, ii) = mean(deltas, 'omitnan');
            meanSteps(ci, ii) = mean(rawSteps, 'omitnan');
            semDelta(ci, ii) = std(deltas, 'omitnan') ./ sqrt(numel(deltas));
        end
    end

    result.name = scenarioName;
    result.meanDelta = meanDelta;
    result.meanSteps = meanSteps;
    result.semDelta = semDelta;
    result.usedTrials = usedTrials;
    result.droppedTrials = droppedTrials;
end

function summaryRows = makeSummaryRows(result, expectedIterations, expectedComms)
    summaryRows = table();
    for ci = 1:numel(expectedComms)
        for ii = 1:numel(expectedIterations)
            summaryRows = [summaryRows; table( ... %#ok<AGROW>
                string(result.name), ...
                expectedComms(ci), ...
                expectedIterations(ii), ...
                result.meanSteps(ci, ii), ...
                result.meanDelta(ci, ii), ...
                result.semDelta(ci, ii), ...
                result.usedTrials, ...
                result.droppedTrials, ...
                'VariableNames', {'scenario', 'comm_label', 'dga_iterations', ...
                'mean_total_team_steps', 'mean_delta_from_trial_baseline', ...
                'sem_delta_from_trial_baseline', 'n_fully_paired_trials', ...
                'dropped_incomplete_trials'})];
        end
    end
end

function iter = extractIteration(T)
    iter = nan(height(T), 1);
    for i = 1:height(T)
        value = "";
        if ismember('source_iter', T.Properties.VariableNames)
            value = string(T.source_iter(i));
        end
        if strlength(value) == 0 && ismember('value', T.Properties.VariableNames)
            value = string(T.value(i));
        end
        if strlength(value) == 0 && ismember('setting', T.Properties.VariableNames)
            value = string(T.setting(i));
        end
        value = erase(value, "iter_");
        value = erase(value, "iter");
        parsed = str2double(value);
        if ~isnan(parsed)
            iter(i) = parsed;
            continue;
        end

        condition = "";
        if ismember('condition_id', T.Properties.VariableNames)
            condition = string(T.condition_id(i));
        elseif ismember('run_id', T.Properties.VariableNames)
            condition = string(T.run_id(i));
        end
        token = regexp(condition, '(^|_)iter_(\d+)(_|$)', 'tokens', 'once');
        if isempty(token)
            token = regexp(condition, '(^|_)iter(\d+)(_|$)', 'tokens', 'once');
        end
        if ~isempty(token)
            iter(i) = str2double(token{2});
        end
    end
end

function comm = extractComm(T)
    comm = strings(height(T), 1);
    for i = 1:height(T)
        if ismember('source_comm_label', T.Properties.VariableNames) && strlength(string(T.source_comm_label(i))) > 0
            comm(i) = string(T.source_comm_label(i));
        elseif ismember('comm_label', T.Properties.VariableNames) && strlength(string(T.comm_label(i))) > 0
            comm(i) = string(T.comm_label(i));
        elseif ismember('comm_level', T.Properties.VariableNames) && strlength(string(T.comm_level(i))) > 0
            comm(i) = string(T.comm_model(i)) + "_" + string(T.comm_level(i));
        else
            comm(i) = string(T.comm_model(i));
        end
    end
end
