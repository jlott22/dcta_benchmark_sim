function recompute_grid_density_complete_blocks
%RECOMPUTE_GRID_DENSITY_COMPLETE_BLOCKS Correct CLIPS/CV scale summaries.
%
% Continuous maximum-agent-step results are retained only for a trial block
% when CBAA, ACBBA, PI, HIPC, DMCHBA, and DGA all completed and all six
% maximum-agent-step values are finite.  The raw system, trial-status, and
% failure-summary CSVs are read only and are never filtered or overwritten.
%
% This focused entry point intentionally regenerates only the corrected
% scale-study derivatives and Figure 4's four-panel maximum-step figure.  It
% does not rerun simulations and does not read or change the message-volume
% or PRDS analyses.

clear; clc; close all;

scriptDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(fileparts(scriptDir));
tableDir = fullfile(scriptDir, 'tables');
figureDir = fullfile(scriptDir, 'figures');
inspectionDir = fullfile(figureDir, 'inspection');
ensureDir(tableDir);
ensureDir(figureDir);
ensureDir(inspectionDir);

algorithmOrder = ["cbaa", "acbba", "pi", "hipc", "dmchba", "dga"];
algorithmLabels = upper(algorithmOrder);
grids = [14, 19, 25, 34];
densities = [50, 85, 140, 220];
comms = ["ideal", "bernoulli_025"];

specs = struct( ...
    'mission', {"CLIPS", "CV"}, ...
    'inputFile', { ...
        fullfile(repoRoot, 'results', 'sensitivity_clue_search_grid_density_50', ...
            'combined', 'sensitivity_clue_search_grid_density_50_combined_system_performance.csv'), ...
        fullfile(repoRoot, 'results', 'sensitivity_known_target_visit_grid_density_50', ...
            'combined', 'system_performance.csv')}, ...
    'maxColumn', {"max_steps_any_robot", "max_robot_steps"});

conditionParts = cell(numel(specs), 1);
eligibilityParts = cell(numel(specs), 1);
algorithmParts = cell(numel(specs), 1);
comparisonParts = cell(numel(specs), 1);
plotParts = cell(numel(specs), 1);
statusParts = cell(numel(specs), 1);

for si = 1:numel(specs)
    spec = specs(si);
    T = loadMission(spec, algorithmOrder);
    [T, conditionTable, eligibilityTable, comparisonTable] = ...
        applyCompleteBlockEligibility(T, spec.mission, grids, densities, comms, algorithmOrder);
    conditionTable = addConditionRanks(conditionTable);
    algorithmTable = summarizeAlgorithms(conditionTable, spec.mission, algorithmOrder);
    plotTable = makePlotSource(T, spec.mission, grids, densities, comms, algorithmOrder);
    statusTable = summarizeTrialStatus(T, spec.mission, grids);

    validateMission(spec.mission, T, conditionTable, eligibilityTable, algorithmTable, plotTable);
    conditionParts{si} = conditionTable;
    eligibilityParts{si} = eligibilityTable;
    algorithmParts{si} = algorithmTable;
    comparisonParts{si} = comparisonTable;
    plotParts{si} = plotTable;
    statusParts{si} = statusTable;
end

conditionSummary = vertcat(conditionParts{:});
eligibilityCounts = vertcat(eligibilityParts{:});
algorithmSummary = vertcat(algorithmParts{:});
continuousComparisons = vertcat(comparisonParts{:});
plotSource = vertcat(plotParts{:});
trialStatusSummary = vertcat(statusParts{:});

conditionPath = fullfile(tableDir, 'grid_density_complete_block_condition_summary.csv');
eligibilityPath = fullfile(tableDir, 'grid_density_complete_block_eligibility_counts.csv');
algorithmPath = fullfile(tableDir, 'grid_density_complete_block_algorithm_summary.csv');
comparisonPath = fullfile(tableDir, 'grid_density_complete_block_continuous_comparisons.csv');
statusPath = fullfile(tableDir, 'grid_density_complete_block_trial_status_summary.csv');
plotPath = fullfile(tableDir, 'grid_density_complete_block_plot_source.csv');

writetable(conditionSummary, conditionPath);
writetable(eligibilityCounts, eligibilityPath);
writetable(algorithmSummary, algorithmPath);
writetable(continuousComparisons, comparisonPath);
writetable(trialStatusSummary, statusPath);
writetable(plotSource, plotPath);

% Keep the Results-section descriptive derivatives synchronized with the
% complete-block source.  These are derived outputs, not source data.
writeResultsSectionDerivatives(conditionSummary, algorithmSummary, tableDir);

% This is the dedicated source consumed by the final figure generator.
finalSourceDir = fullfile(tableDir, 'final_figure_sources');
ensureDir(finalSourceDir);
finalSourcePath = fullfile(finalSourceDir, ...
    'source_grid_density_maximum_agent_steps_summary.csv');
writetable(plotSource, finalSourcePath);

style = final_figure_style();
fig = plotMaximumAgentSteps(plotSource, style, algorithmOrder, algorithmLabels);
pngPath = fullfile(figureDir, 'grid_density_maximum_agent_steps_summary.png');
inspectionPngPath = fullfile(inspectionDir, 'grid_density_maximum_agent_steps_summary.png');
figPath = fullfile(inspectionDir, 'grid_density_maximum_agent_steps_summary.fig');
set(fig, 'Units', 'inches', 'Position', [1 1 3.49 4.30], ...
    'PaperUnits', 'inches', 'PaperPosition', [0 0 3.49 4.30], ...
    'PaperSize', [3.49 4.30], 'Color', 'w');
apply_publication_figure_typography(fig, style);
drawnow;
print(fig, pngPath, '-dpng', sprintf('-r%d', style.exportDpi));
[copied, message] = copyfile(pngPath, inspectionPngPath, 'f');
if ~copied
    error('Could not copy inspection PNG: %s', message);
end
savefig(fig, figPath);
close(fig);

assert(isfile(pngPath) && isfile(figPath), 'Figure 4 output is absent.');
pngInfo = imfinfo(pngPath);
assert(abs(pngInfo.Width - 3.49 * style.exportDpi) <= 2 && ...
    abs(pngInfo.Height - 4.30 * style.exportDpi) <= 2, ...
    'Figure 4 PNG dimensions do not match the existing canvas.');

fprintf('PASS: complete-block scale analysis regenerated.\n');
fprintf('Condition summaries: %s\n', conditionPath);
fprintf('Eligibility counts: %s\n', eligibilityPath);
fprintf('Figure 4 PNG: %s\n', pngPath);
fprintf('Figure 4 editable FIG: %s\n', figPath);
printVerification(conditionSummary, eligibilityCounts, algorithmSummary, trialStatusSummary);
end

function T = loadMission(spec, algorithmOrder)
if ~isfile(spec.inputFile)
    error('Required raw system-performance CSV is absent: %s', spec.inputFile);
end
opts = detectImportOptions(spec.inputFile, 'Delimiter', ',', 'TextType', 'string', ...
    'VariableNamingRule', 'preserve');
opts.DataLines = [2 Inf];
T = readtable(spec.inputFile, opts);
required = ["trial_id", "grid_size", "grid_cells", "robot_count", ...
    "target_cells_per_robot", "comm_label", "algorithm_key", "trial_status", ...
    spec.maxColumn, "debug_max_events", "failure_message"];
missing = setdiff(required, string(T.Properties.VariableNames));
if ~isempty(missing)
    error('%s system-performance CSV lacks: %s', spec.mission, strjoin(cellstr(missing), ', '));
end
T.trial_id = asDouble(T.trial_id);
T.grid_size = asDouble(T.grid_size);
T.grid_cells = asDouble(T.grid_cells);
T.robot_count = asDouble(T.robot_count);
T.target_cells_per_robot = asDouble(T.target_cells_per_robot);
T.comm_label = lower(string(T.comm_label));
T.algorithm = lower(string(T.algorithm_key));
T.trial_status = lower(string(T.trial_status));
T.max_agent_steps = asDouble(T.(spec.maxColumn));
T.completed = T.trial_status == "completed";
T.finite_max_agent_steps = isfinite(T.max_agent_steps);
T.failure_message = lower(string(T.failure_message));
T.scheduler_cap = ~T.completed & contains(T.failure_message, "debug safety cap");
T.stagnation_failure = ~T.completed & contains(T.failure_message, "stagnation detected");
T.other_failure = ~T.completed & ~T.scheduler_cap & ~T.stagnation_failure;
T = T(ismember(T.algorithm, algorithmOrder), :);
T.row_id = (1:height(T))';

if height(T) ~= 9600 || any(T.grid_cells ~= T.grid_size .^ 2)
    error('%s raw design does not match the expected 9,600-row 4x4x2x6 study.', spec.mission);
end
end

function [T, conditionTable, eligibilityTable, comparisonTable] = ...
        applyCompleteBlockEligibility(T, mission, grids, densities, comms, algorithmOrder)
T.common_block_eligible = false(height(T), 1);
conditionRows = {};
eligibilityRows = {};
comparisonRows = {};
ri = 0;
ei = 0;
ci = 0;

for gi = 1:numel(grids)
    for di = 1:numel(densities)
        for mi = 1:numel(comms)
            conditionMask = T.grid_size == grids(gi) & ...
                T.target_cells_per_robot == densities(di) & ...
                T.comm_label == comms(mi);
            C = T(conditionMask, :);
            trialIds = sort(unique(C.trial_id))';
            if height(C) ~= 300 || numel(trialIds) ~= 50
                error('%s g=%g d=%g %s has an incomplete raw condition block.', ...
                    mission, grids(gi), densities(di), comms(mi));
            end
            retained = false(numel(trialIds), 1);
            fullRows = false(numel(trialIds), 1);
            for ti = 1:numel(trialIds)
                B = C(C.trial_id == trialIds(ti), :);
                fullRows(ti) = height(B) == numel(algorithmOrder) && ...
                    isequal(sort(unique(B.algorithm))', sort(algorithmOrder));
                retained(ti) = fullRows(ti) && all(B.completed) && ...
                    all(B.finite_max_agent_steps);
                if retained(ti)
                    T.common_block_eligible(B.row_id) = true;
                end
            end
            % Refresh the condition slice after propagating trial-block
            % eligibility back to the full mission table.
            C = T(conditionMask, :);

            rawCompleted = sum(C.completed);
            rawFailed = height(C) - rawCompleted;
            ei = ei + 1;
            eligibilityRows{ei} = table(mission, grids(gi), grids(gi)^2, ...
                densities(di), comms(mi), numel(trialIds), sum(fullRows), ...
                sum(retained), numel(trialIds) - sum(retained), height(C), ...
                rawCompleted, rawFailed, sum(C.finite_max_agent_steps), ...
                sum(C.scheduler_cap), sum(C.stagnation_failure), sum(C.other_failure), ...
                "all six named algorithms completed with finite maximum-agent steps", ...
                'VariableNames', {'scenario', 'grid_size', 'grid_cells', ...
                'target_cells_per_robot', 'comm_label', 'attempted_block_n', ...
                'six_algorithm_row_complete_block_n', 'common_block_eligible_n', ...
                'excluded_block_n', 'raw_algorithm_rows', 'raw_completed_rows', ...
                'raw_failed_rows', 'finite_max_agent_step_rows', ...
                'event_cap_failure_runs', 'stagnation_failure_runs', ...
                'other_failure_runs', 'eligibility_rule'});

            X = nan(sum(retained), numel(algorithmOrder));
            keptIds = trialIds(retained);
            for ai = 1:numel(algorithmOrder)
                A = C(C.algorithm == algorithmOrder(ai), :);
                eligible = A.common_block_eligible;
                values = A.max_agent_steps(eligible);
                [lo, hi] = meanCI(values);
                ri = ri + 1;
                conditionRows{ri} = table(mission, grids(gi), grids(gi)^2, ...
                    densities(di), mode(A.robot_count), comms(mi), upper(algorithmOrder(ai)), ...
                    numel(trialIds), sum(A.completed), height(A) - sum(A.completed), ...
                    sum(A.finite_max_agent_steps), sum(eligible), ...
                    numel(trialIds) - sum(eligible), mean(values), median(values), ...
                    std(values, 0), lo, hi, ...
                    "all six named algorithms completed with finite maximum-agent steps", ...
                    'VariableNames', {'scenario', 'grid_size', 'grid_cells', ...
                    'target_cells_per_robot', 'robot_count', 'comm_label', 'algorithm', ...
                    'attempted_block_n', 'raw_completed_n', 'raw_failed_n', ...
                    'finite_max_agent_step_n', 'common_block_eligible_n', ...
                    'excluded_from_continuous_n', 'condition_mean_max_agent_steps', ...
                    'condition_median_max_agent_steps', 'condition_sd_max_agent_steps', ...
                    'condition_ci95_low', 'condition_ci95_high', 'eligibility_rule'});
                for ki = 1:numel(keptIds)
                    index = A.trial_id == keptIds(ki);
                    if sum(index) ~= 1
                        error('%s condition block has duplicate or absent algorithm/trial rows.', mission);
                    end
                    X(ki, ai) = A.max_agent_steps(index);
                end
            end
            ci = ci + 1;
            comparisonRows{ci} = makeFriedmanRow(mission, grids(gi), densities(di), ...
                comms(mi), X, numel(trialIds), algorithmOrder);
        end
    end
end
conditionTable = vertcat(conditionRows{:});
eligibilityTable = vertcat(eligibilityRows{:});
comparisonTable = vertcat(comparisonRows{:});
end

function conditionTable = addConditionRanks(conditionTable)
conditionTable.condition_rank = nan(height(conditionTable), 1);
conditionTable.condition_best_mean = nan(height(conditionTable), 1);
conditionTable.percent_above_condition_best = nan(height(conditionTable), 1);
conditionTable.is_leader = false(height(conditionTable), 1);
conditionTable.is_top_two = false(height(conditionTable), 1);

[groupId, ~] = findgroups(conditionTable.grid_size, ...
    conditionTable.target_cells_per_robot, conditionTable.comm_label);
for group = unique(groupId)'
    index = groupId == group;
    means = conditionTable.condition_mean_max_agent_steps(index);
    if sum(index) ~= 6 || any(~isfinite(means))
        error('Condition rankings require six finite complete-block means.');
    end
    best = min(means);
    ranks = tiedrank(means);
    conditionTable.condition_rank(index) = ranks;
    conditionTable.condition_best_mean(index) = best;
    conditionTable.percent_above_condition_best(index) = 100 * (means - best) / best;
    conditionTable.is_leader(index) = ranks == 1;
    conditionTable.is_top_two(index) = ranks <= 2;
end
end

function algorithmTable = summarizeAlgorithms(conditionTable, mission, algorithmOrder)
rows = cell(numel(algorithmOrder), 1);
for ai = 1:numel(algorithmOrder)
    algorithm = upper(algorithmOrder(ai));
    A = conditionTable(conditionTable.algorithm == algorithm, :);
    if height(A) ~= 32
        error('%s/%s does not have 32 condition summaries.', mission, algorithm);
    end
    rows{ai} = table(mission, algorithm, height(A), ...
        mean(A.condition_rank), median(A.condition_rank), sum(A.is_leader), ...
        sum(A.is_top_two), mean(A.percent_above_condition_best), ...
        median(A.percent_above_condition_best), sum(A.attempted_block_n), ...
        sum(A.raw_completed_n), sum(A.common_block_eligible_n), ...
        sum(A.raw_failed_n), ...
        "unweighted across 32 complete-block condition means", ...
        'VariableNames', {'scenario', 'algorithm', 'scale_condition_count', ...
        'mean_condition_rank', 'median_condition_rank', ...
        'first_place_condition_count', 'top2_condition_count', ...
        'mean_percent_above_condition_best', 'median_percent_above_condition_best', ...
        'attempted_block_total', 'raw_completed_n_total', ...
        'common_block_eligible_n_total', 'raw_failed_n_total', 'summary_rule'});
end
algorithmTable = vertcat(rows{:});
algorithmTable = sortrows(algorithmTable, 'mean_condition_rank');
end

function plotTable = makePlotSource(T, mission, grids, densities, comms, algorithmOrder)
rows = {};
ri = 0;
factors = ["grid_size", "target_cells_per_robot"];
factorLevels = {grids, densities};
for fi = 1:numel(factors)
    factor = factors(fi);
    for ai = 1:numel(algorithmOrder)
        for li = 1:numel(factorLevels{fi})
            level = factorLevels{fi}(li);
            if factor == "grid_size"
                base = T.grid_size == level;
                gridValue = level;
                densityValue = nan;
                componentRule = "four nominal-density levels per communication setting";
            else
                base = T.target_cells_per_robot == level;
                gridValue = nan;
                densityValue = level;
                componentRule = "four grid-size levels per communication setting";
            end
            base = base & T.algorithm == algorithmOrder(ai);
            pooled = T(base & T.common_block_eligible, :);
            ideal = T(base & T.common_block_eligible & T.comm_label == comms(1), :);
            degraded = T(base & T.common_block_eligible & T.comm_label == comms(2), :);
            raw = T(base, :);
            [lo, hi] = meanCI(pooled.max_agent_steps);
            [idealLo, idealHi] = meanCI(ideal.max_agent_steps);
            [degradedLo, degradedHi] = meanCI(degraded.max_agent_steps);
            if isempty(pooled) || numel(unique(pooled.comm_label)) ~= 2
                error('%s/%s %s=%g is missing a communication component.', ...
                    mission, algorithmOrder(ai), factor, level);
            end
            ri = ri + 1;
            rows{ri} = table(missionDisplayName(mission), mission, factor, level, ...
                gridValue, densityValue, "pooled_ideal_bernoulli_025", ...
                upper(algorithmOrder(ai)), "Maximum-agent steps", "steps", ...
                mean(pooled.max_agent_steps), lo, hi, mean(ideal.max_agent_steps), ...
                mean(degraded.max_agent_steps), idealLo, idealHi, degradedLo, degradedHi, ...
                height(raw), sum(raw.completed), height(pooled), ...
                height(raw) - sum(raw.completed), height(ideal), height(degraded), ...
                8, "pooled mean across all retained complete-block trials; " + componentRule, ...
                "grid_density_maximum_agent_steps_summary", ...
                "all six algorithms completed with finite maximum-agent steps; failed raw rows remain in status and failure summaries", ...
                'VariableNames', {'mission', 'scenario', 'factor', 'factor_value', ...
                'grid_size', 'target_cells_per_robot', 'comm_label', 'algorithm', ...
                'metric_label', 'units', 'plotted_mean', 'plotted_ci95_low', ...
                'plotted_ci95_high', 'ideal_mean', 'degraded_mean', ...
                'ideal_ci95_low', 'ideal_ci95_high', 'degraded_ci95_low', ...
                'degraded_ci95_high', 'attempted_n', 'completed_n', 'eligible_n', ...
                'failed_n', 'ideal_eligible_n', 'degraded_eligible_n', ...
                'contributing_condition_means', 'aggregation_rule', ...
                'figure_stem', 'continuous_metric_scope'});
        end
    end
end
plotTable = vertcat(rows{:});
end

function statusTable = summarizeTrialStatus(T, mission, grids)
rows = cell(numel(grids) + 1, 1);
for gi = 1:numel(grids)
    G = T(T.grid_size == grids(gi), :);
    rows{gi} = statusRow(mission, grids(gi), G);
end
rows{end} = statusRow(mission, nan, T);
statusTable = vertcat(rows{:});
end

function row = statusRow(mission, gridSize, T)
row = table(mission, gridSize, height(T), sum(T.completed), ...
    sum(~T.completed), sum(T.scheduler_cap), sum(T.stagnation_failure), ...
    sum(T.other_failure), ...
    "raw trial-status rows retained; summary only", ...
    'VariableNames', {'scenario', 'grid_size', 'raw_algorithm_rows', ...
    'raw_completed_rows', 'raw_failed_rows', 'event_cap_failure_runs', ...
    'stagnation_failure_runs', 'other_failure_runs', 'scope'});
end

function row = makeFriedmanRow(mission, gridSize, density, comm, X, attemptedN, algorithmOrder)
if isempty(X) || any(~isfinite(X), 'all')
    error('%s continuous comparison received a non-complete block.', mission);
end
n = size(X, 1);
k = size(X, 2);
ranks = tiedrank(X')';
rankSums = sum(ranks, 1);
q = 12 / (n * k * (k + 1)) * sum(rankSums .^ 2) - 3 * n * (k + 1);
tieAdjustment = 0;
for i = 1:n
    [~, ~, tieGroups] = unique(X(i, :));
    tieSizes = accumarray(tieGroups(:), 1);
    tieAdjustment = tieAdjustment + sum(tieSizes .^ 3 - tieSizes);
end
if tieAdjustment > 0
    q = q / (1 - tieAdjustment / (n * (k^3 - k)));
end
p = 1 - chi2cdf(q, k - 1);
row = table(mission, gridSize, density, comm, attemptedN, n, attemptedN - n, ...
    k, string(strjoin(cellstr(upper(algorithmOrder)), ',')), q, k - 1, p, ...
    q / (n * (k - 1)), ...
    "Friedman ranks use only common complete finite six-algorithm trial blocks", ...
    'VariableNames', {'scenario', 'grid_size', 'target_cells_per_robot', ...
    'comm_label', 'attempted_block_n', 'common_block_eligible_n', ...
    'excluded_block_n', 'algorithm_count', 'algorithm_order', ...
    'friedman_chi_square', 'df', 'p_value', 'kendall_w', 'eligibility_rule'});
end

function writeResultsSectionDerivatives(conditionSummary, algorithmSummary, tableDir)
outDir = fullfile(tableDir, 'results_section_aux');
ensureDir(outDir);
detail = table(conditionSummary.scenario, conditionSummary.grid_size, ...
    conditionSummary.target_cells_per_robot, conditionSummary.robot_count, ...
    conditionSummary.comm_label, conditionSummary.algorithm, ...
    conditionSummary.condition_mean_max_agent_steps, conditionSummary.condition_rank, ...
    conditionSummary.percent_above_condition_best, conditionSummary.attempted_block_n, ...
    conditionSummary.raw_completed_n, conditionSummary.common_block_eligible_n, ...
    conditionSummary.raw_failed_n, ...
    'VariableNames', {'scenario', 'grid_size', 'target_cells_per_robot', ...
    'robot_count', 'comm_label', 'algorithm', 'mean_max_agent_steps', ...
    'condition_rank', 'percent_above_condition_best', 'attempted_n', ...
    'completed_n', 'eligible_n', 'failed_n'});
summary = table(algorithmSummary.scenario, algorithmSummary.algorithm, ...
    algorithmSummary.scale_condition_count, algorithmSummary.mean_condition_rank, ...
    algorithmSummary.median_condition_rank, ...
    algorithmSummary.first_place_condition_count, algorithmSummary.top2_condition_count, ...
    algorithmSummary.mean_percent_above_condition_best, ...
    algorithmSummary.median_percent_above_condition_best, ...
    algorithmSummary.attempted_block_total, algorithmSummary.raw_completed_n_total, ...
    algorithmSummary.common_block_eligible_n_total, algorithmSummary.raw_failed_n_total, ...
    'VariableNames', {'scenario', 'algorithm', 'scale_condition_count', ...
    'mean_condition_rank', 'median_condition_rank', 'first_place_condition_count', ...
    'top2_condition_count', 'mean_percent_above_condition_best', ...
    'median_percent_above_condition_best', 'attempted_n_total', 'completed_n_total', ...
    'eligible_n_total', 'failed_n_total'});
writetable(detail, fullfile(outDir, 'scale_max_steps_condition_detail.csv'));
writetable(summary, fullfile(outDir, 'scale_max_steps_consistency_summary.csv'));
end

function fig = plotMaximumAgentSteps(S, style, algorithmOrder, algorithmLabels)
fig = figure('Name', 'Grid and density maximum-agent sensitivity', 'Color', 'w', ...
    'Units', 'inches', 'Position', [1 1 3.49 4.30], 'Visible', 'off');
layout = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'loose');
factors = ["grid_size", "target_cells_per_robot"];
levels = {[14 19 25 34], [50 85 140 220]};
xLabels = ["Grid side length", "Cells per robot"];
missions = ["CLIPS", "CV"];
axesList = gobjects(2, 2);
legendHandles = gobjects(1, numel(algorithmOrder));

for fi = 1:numel(factors)
    for mi = 1:numel(missions)
        ax = nexttile(layout);
        axesList(fi, mi) = ax;
        hold(ax, 'on');
        panel = S(string(S.factor) == factors(fi) & string(S.scenario) == missions(mi), :);
        for ai = 1:numel(algorithmOrder)
            G = panel(string(panel.algorithm) == upper(algorithmOrder(ai)), :);
            [x, order] = sort(asDouble(G.factor_value));
            y = asDouble(G.plotted_mean);
            y = y(order);
            if numel(x) ~= 4
                error('Each Figure 4 curve must have four factor levels.');
            end
            h = plot(ax, x, y, 'LineStyle', '-', 'Color', style.colors(ai, :), ...
                'LineWidth', 0.90, 'Marker', 'o', 'MarkerSize', 2.5, ...
                'MarkerEdgeColor', style.colors(ai, :), ...
                'MarkerFaceColor', style.colors(ai, :));
            if fi == 1 && mi == 1
                legendHandles(ai) = h;
            end
        end
        xticks(ax, levels{fi});
        xlim(ax, [min(levels{fi}) - 0.04 * range(levels{fi}), ...
            max(levels{fi}) + 0.04 * range(levels{fi})]);
        xlabel(ax, xLabels(fi));
        if fi == 1
            title(ax, missions(mi), 'FontWeight', 'normal', ...
                'FontSize', style.titleFontSize);
        end
        if mi == 2
            ax.YAxisLocation = 'right';
        end
        ylim(ax, paddedLimits(asDouble(panel.plotted_mean), 0.10, true));
        formatAxes(ax, style);
    end
end
sharedYLabel = ylabel(layout, 'Mean maximum-agent steps');
set(sharedYLabel, 'FontSize', style.axesFontSize, 'FontWeight', 'normal');
lgd = legend(axesList(1, 1), legendHandles, cellstr(algorithmLabels), ...
    'Orientation', 'horizontal', 'NumColumns', 3, 'Box', 'off', ...
    'FontSize', style.legendFontSize);
lgd.Layout.Tile = 'south';
lgd.ItemTokenSize = [10 7];
end

function validateMission(mission, T, conditionTable, eligibilityTable, algorithmTable, plotTable)
expectedRetained = struct('CLIPS', 1560, 'CV', 1544);
retained = sum(eligibilityTable.common_block_eligible_n);
if retained ~= expectedRetained.(mission)
    error('%s retained %d complete blocks; expected %d.', mission, retained, expectedRetained.(mission));
end
if height(conditionTable) ~= 192 || height(eligibilityTable) ~= 32 || ...
        height(algorithmTable) ~= 6 || height(plotTable) ~= 48
    error('%s complete-block output has unexpected dimensions.', mission);
end
eligibleByAlgorithm = reshape(conditionTable.common_block_eligible_n, 6, []);
if any(any(eligibleByAlgorithm ~= eligibleByAlgorithm(1, :)))
    % The condition rows are created in six-algorithm blocks; this protects
    % against accidental per-algorithm filtering during future changes.
    error('%s has condition rows with unequal common-block counts.', mission);
end
if any(~T.common_block_eligible & T.completed & ~T.finite_max_agent_steps)
    % Non-finite completed rows are correctly excluded; this branch merely
    % documents the independent two-part eligibility criterion.
end
end

function printVerification(conditionSummary, eligibilityCounts, algorithmSummary, statusSummary)
for mission = ["CLIPS", "CV"]
    E = eligibilityCounts(eligibilityCounts.scenario == mission, :);
    A = algorithmSummary(algorithmSummary.scenario == mission, :);
    fprintf('%s retained %d of %d condition-trial blocks.\n', mission, ...
        sum(E.common_block_eligible_n), sum(E.attempted_block_n));
    for i = 1:height(A)
        fprintf('  %s: leaders=%d top2=%d mean-rank=%.4f mean-gap=%.4f%%\n', ...
            A.algorithm(i), A.first_place_condition_count(i), A.top2_condition_count(i), ...
            A.mean_condition_rank(i), A.mean_percent_above_condition_best(i));
    end
end
clips34 = conditionSummary(conditionSummary.scenario == "CLIPS" & ...
    conditionSummary.grid_size == 34, :);
for algorithm = ["CBAA", "ACBBA", "PI", "HIPC", "DMCHBA", "DGA"]
    values = clips34.condition_mean_max_agent_steps(clips34.algorithm == algorithm);
    counts = clips34.common_block_eligible_n(clips34.algorithm == algorithm);
    pooledMean = sum(values .* counts) / sum(counts);
    fprintf('CLIPS 34x34 %s pooled mean=%.5f (n=%d)\n', ...
        algorithm, pooledMean, sum(counts));
end
S = statusSummary(statusSummary.scenario == "CLIPS" | statusSummary.scenario == "CV", :);
allRows = S(isnan(S.grid_size), :);
grid34 = S(S.grid_size == 34, :);
fprintf('Terminal failures: %d total; %d at 34x34.\n', ...
    sum(allRows.raw_failed_rows), sum(grid34.raw_failed_rows));
fprintf('  Event-cap stops: %d total; %d at 34x34.\n', ...
    sum(allRows.event_cap_failure_runs), sum(grid34.event_cap_failure_runs));
fprintf('  Stagnation stops: %d total; %d at 34x34.\n', ...
    sum(allRows.stagnation_failure_runs), sum(grid34.stagnation_failure_runs));
end

function [lo, hi] = meanCI(x)
x = x(isfinite(x));
n = numel(x);
if n == 0
    lo = nan; hi = nan;
elseif n == 1
    lo = x; hi = x;
else
    half = tinv(0.975, n - 1) * std(x, 0) / sqrt(n);
    lo = mean(x) - half;
    hi = mean(x) + half;
end
end

function limits = paddedLimits(values, fraction, nonnegative)
values = values(isfinite(values));
if isempty(values)
    limits = [0 1];
    return;
end
low = min(values);
high = max(values);
span = high - low;
if span <= 0
    span = max(abs(low), 1);
end
limits = [low - fraction * span, high + fraction * span];
if nonnegative
    limits(1) = max(0, limits(1));
end
end

function formatAxes(ax, style)
grid(ax, 'on');
box(ax, 'on');
set(ax, 'FontSize', style.axesFontSize, 'LineWidth', style.axisLineWidth, ...
    'TitleFontSizeMultiplier', 1, 'LabelFontSizeMultiplier', 1, ...
    'GridAlpha', style.gridAlpha, 'MinorGridAlpha', style.gridAlpha / 2, ...
    'TickDir', 'out', 'Layer', 'top');
end

function name = missionDisplayName(mission)
if mission == "CLIPS"
    name = "Clue-Informed Probabilistic Search (CLIPS)";
elseif mission == "CV"
    name = "Collaborative Visit (CV)";
else
    error('Unknown mission: %s', mission);
end
end

function x = asDouble(x)
if isnumeric(x) || islogical(x)
    x = double(x);
else
    x = str2double(string(x));
end
end

function ensureDir(path)
if ~exist(path, 'dir')
    mkdir(path);
end
end
