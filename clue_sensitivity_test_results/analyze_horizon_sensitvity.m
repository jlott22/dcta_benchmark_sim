% Analyze clue-informed horizon tuning relative to per-trial average.
%
% Metric: post_clue_steps_to_find
% Baseline: for each algorithm x message condition x trial_id, average the
% metric across all available horizon values.
% Plotted value: mean percent difference from that per-trial baseline.
%
% Trials are excluded within each algorithm x message condition if any horizon
% value for that trial has post_clue_steps_to_find == 0.

clear; clc;

scriptDir = fileparts(mfilename('fullpath'));
inputFile = fullfile(scriptDir, 'horizon_results', 'combined', 'system_performance.csv');
metricName = 'post_clue_steps_to_find';

T = readtable(inputFile, 'TextType', 'string');
if ~ismember(metricName, T.Properties.VariableNames)
    error('Metric column not found: %s', metricName);
end

if ismember('trial_status', T.Properties.VariableNames)
    T = T(T.trial_status ~= "failed", :);
end

T.metric_value = double(T.(metricName));
T.h_value = extractHorizon(T);
T.algorithm_plot = upper(string(T.algorithm));
if ismember('algorithm_key', T.Properties.VariableNames)
    hasKey = strlength(string(T.algorithm_key)) > 0;
    T.algorithm_plot(hasKey) = upper(string(T.algorithm_key(hasKey)));
end
T.comm_plot = extractComm(T);

valid = ~isnan(T.metric_value) & ~isnan(T.h_value) & ~isnan(double(T.trial_id));
T = T(valid, :);

algorithms = unique(T.algorithm_plot, 'stable');
overlayData = struct( ...
    'comm', {}, ...
    'algorithm', {}, ...
    'horizons', {}, ...
    'avgPctDiff', {}, ...
    'usedTrials', {}, ...
    'droppedTrials', {});
fprintf('Input: %s\n', inputFile);
fprintf('Metric: %s\n\n', metricName);

for ai = 1:numel(algorithms)
    alg = algorithms(ai);
    Ta = T(T.algorithm_plot == alg, :);
    comms = unique(Ta.comm_plot, 'stable');
    for ci = 1:numel(comms)
        comm = comms(ci);
        G = Ta(Ta.comm_plot == comm, :);
        horizons = sort(unique(G.h_value))';
        trialIds = unique(G.trial_id)';

        y = nan(size(horizons));
        usedTrials = 0;
        droppedTrials = 0;
        pctByH = cell(size(horizons));
        for hi = 1:numel(horizons)
            pctByH{hi} = [];
        end

        for ti = 1:numel(trialIds)
            tid = trialIds(ti);
            values = nan(size(horizons));
            complete = true;
            for hi = 1:numel(horizons)
                rows = G(G.trial_id == tid & G.h_value == horizons(hi), :);
                if height(rows) ~= 1
                    complete = false;
                    break;
                end
                values(hi) = rows.metric_value(1);
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
            for hi = 1:numel(horizons)
                pctByH{hi}(end + 1) = pctDiff(hi); %#ok<SAGROW>
            end
        end

        for hi = 1:numel(horizons)
            y(hi) = mean(pctByH{hi}, 'omitnan');
        end

        if usedTrials == 0
            fprintf('Skipping %s / %s: no paired nonzero trials\n', alg, comm);
            continue;
        end

        figure('Name', sprintf('%s / %s', alg, comm));
        plot(horizons, y, '-o', 'LineWidth', 1.5);
        yline(0, '-', 'Color', [0.6 0.6 0.6]);
        grid on;
        xlabel('Commitment horizon h');
        ylabel(sprintf('Average %% difference from per-trial mean %s', metricName), 'Interpreter', 'none');
        title(sprintf('%s / %s', alg, comm), 'Interpreter', 'none');
        xticks(horizons);

        fprintf('%s / %s: used_trials=%d dropped_trials=%d\n', alg, comm, usedTrials, droppedTrials);
        disp(table(horizons(:), y(:), 'VariableNames', {'h', 'avg_pct_diff'}));

        overlayData(end + 1).comm = comm; %#ok<SAGROW>
        overlayData(end).algorithm = alg;
        overlayData(end).horizons = horizons;
        overlayData(end).avgPctDiff = y;
        overlayData(end).usedTrials = usedTrials;
        overlayData(end).droppedTrials = droppedTrials;
    end
end

if ~isempty(overlayData)
    overlayComms = strings(1, numel(overlayData));
    for i = 1:numel(overlayData)
        overlayComms(i) = overlayData(i).comm;
    end
    comms = unique(overlayComms, 'stable');

    for ci = 1:numel(comms)
        comm = comms(ci);
        idx = find(overlayComms == comm);

        figure('Name', sprintf('All algorithms / %s', comm));
        hold on;
        allHorizons = [];
        legendLabels = strings(1, numel(idx));
        for ii = 1:numel(idx)
            entry = overlayData(idx(ii));
            plot(entry.horizons, entry.avgPctDiff, '-o', 'LineWidth', 1.5);
            allHorizons = [allHorizons, entry.horizons]; %#ok<AGROW>
            legendLabels(ii) = entry.algorithm;
        end
        yline(0, '-', 'Color', [0.6 0.6 0.6], 'HandleVisibility', 'off');
        hold off;
        grid on;
        xlabel('Commitment horizon h');
        ylabel(sprintf('Average %% difference from per-trial mean %s', metricName), 'Interpreter', 'none');
        title(sprintf('All algorithms / %s', comm), 'Interpreter', 'none');
        xticks(sort(unique(allHorizons)));
        legend(legendLabels, 'Interpreter', 'none', 'Location', 'best');

        fprintf('All algorithms / %s: plotted_algorithms=%d\n', comm, numel(idx));
    end
end

function h = extractHorizon(T)
    h = nan(height(T), 1);
    for i = 1:height(T)
        value = "";
        if ismember('value', T.Properties.VariableNames)
            value = string(T.value(i));
        end
        if strlength(value) == 0 && ismember('setting', T.Properties.VariableNames)
            value = string(T.setting(i));
        end
        value = erase(value, "h");
        parsed = str2double(value);
        if ~isnan(parsed)
            h(i) = parsed;
            continue;
        end

        condition = "";
        if ismember('condition_id', T.Properties.VariableNames)
            condition = string(T.condition_id(i));
        elseif ismember('run_id', T.Properties.VariableNames)
            condition = string(T.run_id(i));
        end
        token = regexp(condition, '(^|_)h(\d+)(_|$)', 'tokens', 'once');
        if ~isempty(token)
            h(i) = str2double(token{2});
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
