% Paper figure generation: horizon tuning trends for Collaborative Visit (CV),
% Clue-Informed Probabilistic Search (CLIPS), and Full Grid Search (FGS).
%
% The figure is designed as a compact vertical, single-column IEEE-style
% figure. Each panel is one scenario. Algorithm is encoded by color; ideal
% communication uses a solid line and Bernoulli p=0.25 uses a dotted line.
%
% Baseline: within each scenario, algorithm, and trial_id, average the metric
% across every tested horizon and both communication settings. The plotted
% value is the mean over trial_id of (metric - paired_trial_baseline).

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

horizons = [1, 2, 3, 5, 8, 12];
commLabels = ["ideal", "bernoulli_025"];
algorithms = ["acbba", "dga", "dmchba", "hipc", "pi"];
algorithmLabels = ["ACBBA", "DGA", "DMCHBA", "HIPC", "PI"];
% Rows: CV, CLIPS, FGS. Columns follow algorithms above. These are the
% selected main-benchmark horizons documented in Table default_horizons of
% the current manuscript.
selectedHorizons = [3, 3, 3, 8, 5; 8, 3, 5, 5, 3; 3, 5, 8, 3, 3];
if any(~ismember(selectedHorizons, horizons), 'all')
    error('At least one selected horizon is absent from the tested sweep.');
end

scenarioSpecs = struct( ...
    'name', {'Collaborative Visit (CV)', 'Clue-Informed Probabilistic Search (CLIPS)', 'Full Grid Search (FGS)'}, ...
    'inputFile', { ...
        fullfile(repoRoot, 'results', 'sensitivity_known_target_visit_horizon_300', 'combined', 'sensitivity_known_target_visit_horizon_300_combined_system_performance.csv'), ...
        fullfile(repoRoot, 'results', 'sensitivity_clue_search_horizon_300', 'combined', 'sensitivity_clue_search_horizon_300_combined_system_performance.csv'), ...
        fullfile(repoRoot, 'results', 'sensitivity_coverage_horizon_50', 'combined', 'sensitivity_coverage_horizon_50_combined_system_performance.csv') ...
    }, ...
    'metric', {'total_team_steps', 'post_clue_steps_to_find', 'total_team_steps'});

results = struct('name', {}, 'metric', {}, 'meanDelta', {}, 'usedTrials', {}, 'droppedTrials', {});
summaryRows = table();

for si = 1:numel(scenarioSpecs)
    result = analyzeScenario( ...
        scenarioSpecs(si), ...
        horizons, ...
        commLabels, ...
        algorithms);
    results(end + 1) = result; %#ok<SAGROW>
    summaryRows = [summaryRows; makeSummaryRows( ...
        result, horizons, commLabels, algorithms, selectedHorizons(si, :))]; %#ok<AGROW>

    fprintf('%s\n', result.name);
    fprintf('  Metric: %s\n', result.metric);
    fprintf('  Input: %s\n', scenarioSpecs(si).inputFile);
    fprintf('  Used fully paired algorithm-trials: %d\n', result.usedTrials);
    fprintf('  Dropped incomplete algorithm-trials: %d\n\n', result.droppedTrials);
end

summaryFile = fullfile(tableDir, 'horizon_tuning_paired_trial_delta_summary.csv');
writetable(summaryRows, summaryFile);
fprintf('Summary written to: %s\n', summaryFile);

% Historical exploratory layouts are retained below for provenance, but the
% release pipeline creates only the finalized Figure 5 through
% generate_final_paper_figures_CLIPS_CV.m.
generateHistoricalFigures = false;
if generateHistoricalFigures
figure('Name', 'Paper horizon tuning trends', 'Color', 'w', 'Units', 'inches', ...
    'Position', [1, 1, 3.5, 6.9]);
layout = tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
axesList = gobjects(1, numel(results));

colors = lines(numel(algorithms));
lineStyles = ["-", ":"];
lineWidth = 1.15;

for si = 1:numel(results)
    ax = nexttile(layout);
    axesList(si) = ax;
    hold(ax, 'on');
    for ai = 1:numel(algorithms)
        for ci = 1:numel(commLabels)
            plot(ax, horizons, squeeze(results(si).meanDelta(ai, ci, :)), ...
                'LineStyle', char(lineStyles(ci)), ...
                'Color', colors(ai, :), ...
                'LineWidth', lineWidth);
        end
        selectedH = selectedHorizons(si, ai);
        selectedIndex = find(horizons == selectedH, 1);
        for ci = 1:numel(commLabels)
            plot(ax, selectedH, results(si).meanDelta(ai, ci, selectedIndex), ...
                'LineStyle', 'none', ...
                'Marker', 'p', ...
                'MarkerSize', 4.8, ...
                'MarkerFaceColor', colors(ai, :), ...
                'MarkerEdgeColor', [0 0 0], ...
                'LineWidth', 0.65, ...
                'HandleVisibility', 'off');
        end
    end
    yline(ax, 0, '-', 'Color', [0.55 0.55 0.55], 'LineWidth', 0.7);
    hold(ax, 'off');

    grid(ax, 'on');
    box(ax, 'on');
    title(ax, results(si).name, 'FontWeight', 'normal');
    ylabel(ax, 'Steps vs. baseline');
    xticks(ax, horizons);
    xlim(ax, [min(horizons), max(horizons)]);
    set(ax, 'FontSize', 7, 'LineWidth', 0.7);

    if si < numel(results)
        ax.XTickLabel = [];
    else
        xlabel(ax, 'Commitment horizon');
    end
end

% Compact algorithm legend. Line style meaning is intentionally encoded in
% the subtitle to avoid a 10-entry legend in a single-column figure.
legendHandles = gobjects(1, numel(algorithms));
hold(axesList(1), 'on');
for ai = 1:numel(algorithms)
    legendHandles(ai) = plot(axesList(1), nan, nan, '-', ...
        'Color', colors(ai, :), ...
        'LineWidth', lineWidth, ...
        'DisplayName', char(algorithmLabels(ai)));
end
hold(axesList(1), 'off');

lgd = legend(legendHandles, cellstr(algorithmLabels), ...
    'Orientation', 'horizontal', ...
    'NumColumns', 3, ...
    'Location', 'southoutside', ...
    'Box', 'off', ...
    'FontSize', 6);
lgd.Layout.Tile = 'south';

title(layout, {'Horizon tuning trends', ...
    'solid=ideal; dotted=Bernoulli 0.25; star=selected'}, ...
    'FontWeight', 'normal', 'FontSize', 7.5);

pngFile = fullfile(outDir, 'horizon_tuning.png');
figFile = fullfile(outDir, 'horizon_tuning.fig');
try
    exportgraphics(gcf, pngFile, 'Resolution', 600);
catch
    print(gcf, pngFile, '-dpng', '-r600');
end
savefig(gcf, figFile);

fprintf('Figure written to: %s\n', pngFile);
fprintf('MATLAB figure written to: %s\n', figFile);

heatmapSpecs = struct( ...
    'name', {'Collaborative Visit (CV)', 'Clue-Informed Probabilistic Search (CLIPS)', 'Full Grid Search (FGS)'}, ...
    'decisionFile', { ...
        fullfile(repoRoot, 'results', 'analysis', 'tables', 'known_horizon_tuning_decision.csv'), ...
        fullfile(repoRoot, 'results', 'analysis', 'tables', 'clue_horizon_tuning_decision.csv'), ...
        fullfile(repoRoot, 'results', 'analysis', 'tables', 'coverage_horizon_tuning_decision.csv') ...
    });

decisionFilesPresent = all(arrayfun(@(spec) isfile(spec.decisionFile), heatmapSpecs));
if decisionFilesPresent
    heatmapResults = struct('name', {}, 'score', {}, 'chosen', {});
    for si = 1:numel(heatmapSpecs)
        heatmapResults(end + 1) = loadRobustScoreMatrix( ... %#ok<SAGROW>
            heatmapSpecs(si), ...
            algorithms, ...
            horizons);
    end

figure('Name', 'Paper horizon robust-score heatmap', 'Color', 'w', 'Units', 'inches', ...
    'Position', [1, 1, 3.5, 6.5]);
heatLayout = tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

allScores = [];
for si = 1:numel(heatmapResults)
    allScores = [allScores; heatmapResults(si).score(:)]; %#ok<AGROW>
end
scoreLimit = max(abs(allScores(~isnan(allScores))));
if isempty(scoreLimit) || scoreLimit == 0
    scoreLimit = 1;
end

for si = 1:numel(heatmapResults)
    ax = nexttile(heatLayout);
    imagesc(ax, heatmapResults(si).score);
    colormap(ax, redBlueMap(256));
    caxis(ax, [-scoreLimit, scoreLimit]);
    axis(ax, 'tight');
    box(ax, 'on');
    set(ax, ...
        'XTick', 1:numel(horizons), ...
        'XTickLabel', string(horizons), ...
        'YTick', 1:numel(algorithms), ...
        'YTickLabel', algorithmLabels, ...
        'FontSize', 7, ...
        'LineWidth', 0.7);
    title(ax, heatmapResults(si).name, 'FontWeight', 'normal');
    if si < numel(heatmapResults)
        ax.XTickLabel = [];
    else
        xlabel(ax, 'Commitment horizon');
    end
    ylabel(ax, 'Algorithm');

    hold(ax, 'on');
    [chosenAlg, chosenH] = find(heatmapResults(si).chosen);
    for jj = 1:numel(chosenAlg)
        rectangle(ax, ...
            'Position', [chosenH(jj) - 0.5, chosenAlg(jj) - 0.5, 1, 1], ...
            'EdgeColor', 'k', ...
            'LineWidth', 1.2);
    end
    hold(ax, 'off');
end

cb = colorbar;
cb.Layout.Tile = 'east';
cb.Label.String = 'Robust score';
cb.FontSize = 7;
title(heatLayout, {'Horizon robust-score heatmap', 'outlined cells = selected horizon'}, ...
    'FontWeight', 'normal', 'FontSize', 8);

heatPngFile = fullfile(outDir, 'horizon_tuning_robust_score_heatmap.png');
heatFigFile = fullfile(outDir, 'horizon_tuning_robust_score_heatmap.fig');
try
    exportgraphics(gcf, heatPngFile, 'Resolution', 600);
catch
    print(gcf, heatPngFile, '-dpng', '-r600');
end
savefig(gcf, heatFigFile);

    fprintf('Heatmap written to: %s\n', heatPngFile);
    fprintf('MATLAB heatmap figure written to: %s\n', heatFigFile);
else
    fprintf('Skipping optional robust-score heatmap: decision CSVs are not present.\n');
end
end

function result = analyzeScenario(spec, horizons, commLabels, algorithms)
    T = readtable(spec.inputFile, 'TextType', 'string');
    if ~ismember(spec.metric, T.Properties.VariableNames)
        error('Metric column not found in %s: %s', spec.inputFile, spec.metric);
    end

    if ismember('trial_status', T.Properties.VariableNames)
        T = T(T.trial_status ~= "failed", :);
    end

    T.metric_value = double(T.(spec.metric));
    T.h_value = extractHorizon(T);
    T.algorithm_plot = extractAlgorithm(T);
    T.comm_plot = extractComm(T);
    T.trial_numeric = double(T.trial_id);

    valid = ...
        ~isnan(T.metric_value) & ...
        T.metric_value > 0 & ...
        ~isnan(T.h_value) & ...
        ~isnan(T.trial_numeric) & ...
        ismember(T.h_value, horizons) & ...
        ismember(T.algorithm_plot, algorithms) & ...
        ismember(T.comm_plot, commLabels);
    T = T(valid, :);

    nAlgorithms = numel(algorithms);
    nComms = numel(commLabels);
    nHorizons = numel(horizons);
    deltaByAlgCommH = cell(nAlgorithms, nComms, nHorizons);
    usedTrials = 0;
    droppedTrials = 0;

    for ai = 1:nAlgorithms
        alg = algorithms(ai);
        Ta = T(T.algorithm_plot == alg, :);
        trialIds = unique(Ta.trial_numeric)';

        for ti = 1:numel(trialIds)
            tid = trialIds(ti);
            values = nan(nComms, nHorizons);
            complete = true;

            for ci = 1:nComms
                for hi = 1:nHorizons
                    rows = Ta( ...
                        Ta.trial_numeric == tid & ...
                        Ta.comm_plot == commLabels(ci) & ...
                        Ta.h_value == horizons(hi), :);
                    if height(rows) ~= 1
                        complete = false;
                        break;
                    end
                    values(ci, hi) = rows.metric_value(1);
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
                for hi = 1:nHorizons
                    deltaByAlgCommH{ai, ci, hi}(end + 1) = values(ci, hi) - trialBaseline; %#ok<SAGROW>
                end
            end
        end
    end

    meanDelta = nan(nAlgorithms, nComms, nHorizons);
    for ai = 1:nAlgorithms
        for ci = 1:nComms
            for hi = 1:nHorizons
                meanDelta(ai, ci, hi) = mean(deltaByAlgCommH{ai, ci, hi}, 'omitnan');
            end
        end
    end

    result.name = spec.name;
    result.metric = spec.metric;
    result.meanDelta = meanDelta;
    result.usedTrials = usedTrials;
    result.droppedTrials = droppedTrials;
end

function summaryRows = makeSummaryRows(result, horizons, commLabels, algorithms, selectedHorizons)
    summaryRows = table();
    for ai = 1:numel(algorithms)
        for ci = 1:numel(commLabels)
            for hi = 1:numel(horizons)
                summaryRows = [summaryRows; table( ... %#ok<AGROW>
                    string(result.name), ...
                    string(result.metric), ...
                    algorithms(ai), ...
                    commLabels(ci), ...
                    horizons(hi), ...
                    result.meanDelta(ai, ci, hi), ...
                    horizons(hi) == selectedHorizons(ai), ...
                    'VariableNames', {'scenario', 'metric', 'algorithm_key', ...
                    'comm_label', 'horizon', 'mean_delta_from_trial_baseline', ...
                    'selected_for_main_benchmark'})];
            end
        end
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

function alg = extractAlgorithm(T)
    alg = lower(string(T.algorithm));
    if ismember('algorithm_key', T.Properties.VariableNames)
        hasKey = strlength(string(T.algorithm_key)) > 0;
        alg(hasKey) = lower(string(T.algorithm_key(hasKey)));
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

function result = loadRobustScoreMatrix(spec, algorithms, horizons)
    T = readtable(spec.decisionFile, 'TextType', 'string');
    score = nan(numel(algorithms), numel(horizons));
    chosen = false(numel(algorithms), numel(horizons));

    for ai = 1:numel(algorithms)
        for hi = 1:numel(horizons)
            rows = T( ...
                lower(string(T.algorithm_key)) == algorithms(ai) & ...
                str2double(string(T.candidate)) == horizons(hi), :);
            if height(rows) ~= 1
                continue;
            end
            score(ai, hi) = str2double(string(rows.robust_score(1)));
            chosen(ai, hi) = strcmpi(string(rows.chosen(1)), "true");
        end
    end

    result.name = spec.name;
    result.score = score;
    result.chosen = chosen;
end

function cmap = redBlueMap(n)
    if nargin < 1
        n = 256;
    end
    low = [0.20, 0.35, 0.85];
    mid = [1.00, 1.00, 1.00];
    high = [0.85, 0.20, 0.20];
    half = floor(n / 2);
    lower = [linspace(low(1), mid(1), half)', ...
        linspace(low(2), mid(2), half)', ...
        linspace(low(3), mid(3), half)'];
    upper = [linspace(mid(1), high(1), n - half)', ...
        linspace(mid(2), high(2), n - half)', ...
        linspace(mid(3), high(3), n - half)'];
    cmap = [lower; upper];
end
