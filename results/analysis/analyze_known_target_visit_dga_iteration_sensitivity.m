% Analyze known-target DGA iteration tuning relative to per-trial average.
%
% Metric: total_team_steps
% Baseline: for each message condition x trial_id, average the metric across
% all available DGA iteration values.
% Plotted value: mean percent difference from that per-trial baseline.
%
% Trials are excluded within each message condition if any iteration value for
% that trial has total_team_steps == 0.

clear; clc;

scriptDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(fileparts(scriptDir));
outDir = fullfile(scriptDir, 'figures');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end
tableDir = fullfile(scriptDir, 'tables');
if ~exist(tableDir, 'dir')
    mkdir(tableDir);
end
inputFile = fullfile(repoRoot, 'results', 'sensitivity_known_target_visit_dga_iteration_300', 'combined', ...
    'sensitivity_known_target_visit_dga_iteration_300_combined_system_performance.csv');
metricName = 'total_team_steps';
selectedIterations = 25;

T = readtable(inputFile, 'TextType', 'string');
if ~ismember(metricName, T.Properties.VariableNames)
    error('Metric column not found: %s', metricName);
end

if ismember('trial_status', T.Properties.VariableNames)
    T = T(T.trial_status ~= "failed", :);
end

T.metric_value = double(T.(metricName));
T.iter_value = extractIteration(T);
T.comm_plot = extractComm(T);

valid = ~isnan(T.metric_value) & ~isnan(T.iter_value) & ~isnan(double(T.trial_id));
T = T(valid, :);

comms = unique(T.comm_plot, 'stable');
overlayData = struct( ...
    'comm', {}, ...
    'iterations', {}, ...
    'avgPctDiff', {}, ...
    'usedTrials', {}, ...
    'droppedTrials', {});
summaryRows = table(strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), false(0, 1), ...
    'VariableNames', {'scenario', 'comm_label', 'dga_iterations', ...
    'mean_percent_difference_from_trial_iteration_mean', ...
    'fully_paired_trials', 'dropped_incomplete_trials', ...
    'selected_for_main_benchmark'});
fprintf('Input: %s\n', inputFile);
fprintf('Metric: %s\n\n', metricName);

for ci = 1:numel(comms)
    comm = comms(ci);
    G = T(T.comm_plot == comm, :);
    iterations = sort(unique(G.iter_value))';
    trialIds = unique(G.trial_id)';

    y = nan(size(iterations));
    usedTrials = 0;
    droppedTrials = 0;
    pctByIter = cell(size(iterations));
    for ii = 1:numel(iterations)
        pctByIter{ii} = [];
    end

    for ti = 1:numel(trialIds)
        tid = trialIds(ti);
        values = nan(size(iterations));
        complete = true;
        for ii = 1:numel(iterations)
            rows = G(G.trial_id == tid & G.iter_value == iterations(ii), :);
            if height(rows) ~= 1
                complete = false;
                break;
            end
            values(ii) = rows.metric_value(1);
        end

        if ~complete || any(isnan(values)) || any(values == 0)
            droppedTrials = droppedTrials + 1;
            continue;
        end

        baseline = mean(values);
        if baseline == 0
            droppedTrials = droppedTrials + 1;
            continue;
        end

        usedTrials = usedTrials + 1;
        pctDiff = 100 .* (values - baseline) ./ baseline;
        for ii = 1:numel(iterations)
            pctByIter{ii}(end + 1) = pctDiff(ii); %#ok<SAGROW>
        end
    end

    for ii = 1:numel(iterations)
        y(ii) = mean(pctByIter{ii}, 'omitnan');
    end

    if usedTrials == 0
        fprintf('Skipping %s: no paired nonzero trials\n', comm);
        continue;
    end

    figure('Name', sprintf('DGA iteration / %s', comm));
    plot(iterations, y, '-o', 'LineWidth', 1.5);
    yline(0, '-', 'Color', [0.6 0.6 0.6]);
    grid on;
    xlabel('DGA iterations per trigger');
    ylabel(sprintf('Average %% difference from per-trial mean %s', metricName), 'Interpreter', 'none');
    title(sprintf('DGA iteration / %s', comm), 'Interpreter', 'none');
    xticks(iterations);

    fprintf('%s: used_trials=%d dropped_trials=%d\n', comm, usedTrials, droppedTrials);
    disp(table(iterations(:), y(:), 'VariableNames', {'iteration', 'avg_pct_diff'}));

    overlayData(end + 1).comm = comm; %#ok<SAGROW>
    overlayData(end).iterations = iterations;
    overlayData(end).avgPctDiff = y;
    overlayData(end).usedTrials = usedTrials;
    overlayData(end).droppedTrials = droppedTrials;

    summaryRows = [summaryRows; table( ... %#ok<AGROW>
        repmat("Collaborative Visit (CV)", numel(iterations), 1), ...
        repmat(comm, numel(iterations), 1), iterations(:), y(:), ...
        repmat(usedTrials, numel(iterations), 1), ...
        repmat(droppedTrials, numel(iterations), 1), ...
        iterations(:) == selectedIterations, ...
        'VariableNames', summaryRows.Properties.VariableNames)];
end

summaryFile = fullfile(tableDir, 'dga_iteration_percent_delta_summary.csv');
writetable(summaryRows, summaryFile);
fprintf('Summary written to: %s\n', summaryFile);

if ~isempty(overlayData)
    figure('Name', 'DGA iteration / all communication modes', 'Color', 'w', ...
        'Units', 'inches', 'Position', [1, 1, 3.5, 2.8]);
    hold on;
    allIterations = [];
    legendLabels = strings(1, numel(overlayData));
    colors = lines(numel(overlayData));
    lineHandles = gobjects(1, numel(overlayData));
    for i = 1:numel(overlayData)
        entry = overlayData(i);
        lineHandles(i) = plot(entry.iterations, entry.avgPctDiff, '-o', ...
            'Color', colors(i, :), 'LineWidth', 1.5);
        selectedIndex = find(entry.iterations == selectedIterations, 1);
        if isempty(selectedIndex)
            error('Selected DGA iteration count %d is absent from %s.', ...
                selectedIterations, entry.comm);
        end
        plot(selectedIterations, entry.avgPctDiff(selectedIndex), ...
            'LineStyle', 'none', ...
            'Marker', 'p', ...
            'MarkerSize', 8, ...
            'MarkerFaceColor', colors(i, :), ...
            'MarkerEdgeColor', [0 0 0], ...
            'LineWidth', 0.8, ...
            'HandleVisibility', 'off');
        allIterations = [allIterations, entry.iterations]; %#ok<AGROW>
        if entry.comm == "ideal"
            legendLabels(i) = "Ideal";
        elseif entry.comm == "bernoulli_025"
            legendLabels(i) = "Bernoulli p=0.25";
        else
            legendLabels(i) = entry.comm;
        end
    end
    yline(0, '-', 'Color', [0.6 0.6 0.6], 'HandleVisibility', 'off');
    selectedHandle = plot(nan, nan, 'kp', ...
        'MarkerFaceColor', [1 1 1], 'MarkerSize', 9, ...
        'LineStyle', 'none', 'DisplayName', sprintf('Selected k=%d', selectedIterations));
    hold off;
    grid on;
    xlabel('DGA iterations per trigger');
    ylabel('Mean total-step deviation (%)');
    title('CV DGA iteration sensitivity', 'FontWeight', 'normal', 'FontSize', 8);
    xticks(sort(unique(allIterations)));
    set(gca, 'FontSize', 7);
    legend([lineHandles, selectedHandle], ...
        [legendLabels, "Selected k=" + string(selectedIterations)], ...
        'Interpreter', 'none', 'Location', 'best', 'FontSize', 6.5);

    fprintf('DGA iteration / all communication modes: plotted_conditions=%d\n', numel(overlayData));

    pngFile = fullfile(outDir, 'DGA_iteration.png');
    figFile = fullfile(outDir, 'DGA_iteration.fig');
    try
        exportgraphics(gcf, pngFile, 'Resolution', 600);
    catch
        print(gcf, pngFile, '-dpng', '-r600');
    end
    savefig(gcf, figFile);
    fprintf('Figure written to: %s\n', pngFile);
    fprintf('MATLAB figure written to: %s\n', figFile);
end

function iter = extractIteration(T)
    iter = nan(height(T), 1);
    for i = 1:height(T)
        value = "";
        if ismember('value', T.Properties.VariableNames)
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
        if ismember('comm_label', T.Properties.VariableNames) && strlength(string(T.comm_label(i))) > 0
            comm(i) = string(T.comm_label(i));
        elseif ismember('comm_level', T.Properties.VariableNames) && strlength(string(T.comm_level(i))) > 0
            comm(i) = string(T.comm_model(i)) + "_" + string(T.comm_level(i));
        else
            comm(i) = string(T.comm_model(i));
        end
    end
end
