% regenerate_horizon_tuning_figure.m
% Rebuild the active CLIPS/CV horizon figure from the current decision
% records. Pentagrams mark the robust-score decision-table selections.

clear; clc; close all;
scriptDir = fileparts(mfilename('fullpath'));
tableDir = fullfile(scriptDir, 'tables');
figureDir = fullfile(scriptDir, 'figures');
inspectionDir = fullfile(figureDir, 'inspection');
sourceDir = fullfile(tableDir, 'final_figure_sources');
style = final_figure_style();

clips = readCsv(fullfile(tableDir, 'clue_horizon_tuning_decision.csv'));
cv = readCsv(fullfile(tableDir, 'known_horizon_tuning_decision.csv'));
clips.scenario = repmat(style.missionNames(1), height(clips), 1);
cv.scenario = repmat(style.missionNames(2), height(cv), 1);
S = [clips; cv];
S.algorithm = upper(string(S.algorithm_key));
S.horizon = asDouble(S.candidate);
S.selected_for_main_benchmark = asLogical(S.chosen);
S.score_formula = repmat( ...
    "R = average_improvement_pct - 0.5*comm_disagreement_penalty - 0.5*bad_comm_penalty - 0.1*local_steepness", ...
    height(S), 1);
S.score_direction = repmat("higher is better", height(S), 1);
S.figure_stem = repmat("horizon_tuning", height(S), 1);
S.plot_rule = repmat( ...
    "robust-score curves; pentagram marks the decision-table selection", ...
    height(S), 1);

expected = table( ...
    [repmat("Clue-Informed Probabilistic Search (CLIPS)", 5, 1); ...
     repmat("Collaborative Visit (CV)", 5, 1)], ...
    ["ACBBA";"PI";"HIPC";"DMCHBA";"DGA"; ...
     "ACBBA";"PI";"HIPC";"DMCHBA";"DGA"], ...
    [8;3;5;5;3; 3;5;8;3;3], ...
    'VariableNames', {'scenario','algorithm','horizon'});
selected = S(S.selected_for_main_benchmark, {'scenario','algorithm','horizon'});
selected = sortrows(selected, {'scenario','algorithm'});
expected = sortrows(expected, {'scenario','algorithm'});
assert(isequal(selected, expected), ...
    'Horizon selections do not match the corrected decision table.');
writetable(S, fullfile(sourceDir, 'source_horizon_tuning_line_option_a.csv'));

% Synchronize the selected-point flags in the paired-baseline source.  The
% plotted baseline and robust score are different summaries, but both must
% identify the same final decision-table horizon.
pairedPath = fullfile(tableDir, 'horizon_tuning_paired_trial_delta_summary.csv');
paired = readCsv(pairedPath);
active = ismember(string(paired.scenario), style.missionNames(1:2));
paired.selected_for_main_benchmark(active) = 0;
for i = 1:height(expected)
    match = string(paired.scenario) == expected.scenario(i) & ...
        upper(string(paired.algorithm_key)) == expected.algorithm(i) & ...
        asDouble(paired.horizon) == expected.horizon(i);
    assert(sum(match) == 2, ...
        'Expected ideal and Bernoulli rows for each selected horizon.');
    paired.selected_for_main_benchmark(match) = 1;
end
writetable(paired, pairedPath);

% Compact source-of-truth table for the manuscript. CBAA is fixed at one;
% the other five values are the robust-score decision-table selections.
horizonTable = table( ...
    ["CBAA";"ACBBA";"PI";"HIPC";"DMCHBA";"DGA"], ...
    [1;8;3;5;5;3], [1;3;5;8;3;3], ...
    ["fixed non-bundle value"; repmat("robust-score decision table", 5, 1)], ...
    'VariableNames', {'algorithm','clips_horizon','cv_horizon','selection_basis'});
writetable(horizonTable, fullfile(tableDir, ...
    'corrected_main_benchmark_horizons.csv'));
writeLatexHorizonTable(horizonTable, fullfile(tableDir, ...
    'corrected_main_benchmark_horizons.tex'));

fig = figure('Name', 'Horizon sensitivity', 'Color', 'w', ...
    'Units', 'inches', 'Position', [1 1 3.49 3.74], 'Visible', 'off');
layout = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
algorithms = ["ACBBA", "PI", "HIPC", "DMCHBA", "DGA"];
axesList = gobjects(1, 2); legendHandles = gobjects(1, 5);
for mi = 1:2
    ax = nexttile(layout); axesList(mi) = ax; hold(ax, 'on');
    for ai = 1:numel(algorithms)
        styleIndex = find(style.algorithmKeys == algorithms(ai), 1);
        G = S(string(S.scenario) == style.missionNames(mi) & ...
            string(S.algorithm) == algorithms(ai), :);
        [x, order] = sort(asDouble(G.horizon));
        y = asDouble(G.robust_score); y = y(order);
        h = plot(ax, x, y, '-', 'Color', style.colors(styleIndex, :), ...
            'LineWidth', style.lineWidth, 'Marker', 'o', 'MarkerSize', 2.7, ...
            'MarkerFaceColor', style.colors(styleIndex, :), ...
            'MarkerEdgeColor', style.colors(styleIndex, :));
        if mi == 1, legendHandles(ai) = h; end
        chosen = asLogical(G.selected_for_main_benchmark);
        plot(ax, asDouble(G.horizon(chosen)), asDouble(G.robust_score(chosen)), ...
            'LineStyle', 'none', 'Marker', 'p', 'MarkerSize', 4.5, ...
            'MarkerFaceColor', style.colors(styleIndex, :), ...
            'MarkerEdgeColor', [0 0 0], 'LineWidth', 0.75, ...
            'HandleVisibility', 'off');
    end
    yline(ax, 0, '-', 'Color', style.zeroColor, 'LineWidth', 0.6, ...
        'HandleVisibility', 'off');
    title(ax, style.missionKeys(mi), 'FontWeight', 'normal', ...
        'FontSize', style.titleFontSize);
    xticks(ax, [1 2 3 5 8 12]); xlim(ax, [0.5 12.5]);
    if mi < 2, xticklabels(ax, []); end
    formatAxes(ax, style);
end
xlabel(layout, 'Commitment horizon');
ylabel(layout, 'Robust tuning score (percentage points)');
lgd = legend(axesList(1), legendHandles, cellstr(algorithms), ...
    'Orientation', 'horizontal', 'NumColumns', 3, 'Box', 'off', ...
    'FontSize', style.legendFontSize);
lgd.Layout.Tile = 'south'; lgd.ItemTokenSize = [12 7];

set(fig, 'PaperUnits', 'inches', 'PaperPosition', [0 0 3.49 3.74], ...
    'PaperSize', [3.49 3.74]);
apply_publication_figure_typography(fig, style); drawnow;
pngPath = fullfile(figureDir, 'horizon_tuning.png');
inspectionPng = fullfile(inspectionDir, 'horizon_tuning.png');
figPath = fullfile(inspectionDir, 'horizon_tuning.fig');
print(fig, pngPath, '-dpng', sprintf('-r%d', style.exportDpi));
copyfile(pngPath, inspectionPng, 'f'); savefig(fig, figPath); close(fig);
info = imfinfo(pngPath);
assert(abs(double(info.Width) - round(3.49 * style.exportDpi)) <= 2);
assert(abs(double(info.Height) - round(3.74 * style.exportDpi)) <= 2);
fprintf('PASS: horizon figure regenerated from robust-score selections.\n');

function T = readCsv(path)
    opts = detectImportOptions(path, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve', 'VariableNamesLine', 1);
    opts.DataLines = [2 Inf]; T = readtable(path, opts);
end

function tf = asLogical(value)
    if islogical(value), tf = value;
    elseif isnumeric(value), tf = value ~= 0;
    else, tf = ismember(lower(strtrim(string(value))), ["true","1","yes"]);
    end
end

function value = asDouble(value)
    if isnumeric(value) || islogical(value), value = double(value);
    else, value = str2double(string(value));
    end
end

function formatAxes(ax, style)
    grid(ax, 'on'); box(ax, 'on');
    set(ax, 'FontSize', style.axesFontSize, ...
        'TitleFontSizeMultiplier', 1, 'LabelFontSizeMultiplier', 1, ...
        'LineWidth', style.axisLineWidth, 'GridAlpha', style.gridAlpha, ...
        'MinorGridAlpha', style.gridAlpha / 2, 'TickDir', 'out', ...
        'Layer', 'top');
end

function writeLatexHorizonTable(T, path)
    fid = fopen(path, 'w');
    if fid < 0, error('Could not write LaTeX horizon table: %s', path); end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '\\begin{table}[t]\n');
    fprintf(fid, '    \\centering\n');
    fprintf(fid, '    \\caption{Commitment horizons used in the main benchmarks.}\n');
    fprintf(fid, '    \\label{tab:default_horizons}\n');
    fprintf(fid, '    \\begin{tabular}{lcc}\n');
    fprintf(fid, '        \\hline\n');
    fprintf(fid, '        Algorithm & CLIPS & CV \\\\\n');
    fprintf(fid, '        \\hline\n');
    for i = 1:height(T)
        fprintf(fid, '        %s & %d & %d \\\\\n', ...
            char(T.algorithm(i)), T.clips_horizon(i), T.cv_horizon(i));
    end
    fprintf(fid, '        \\hline\n');
    fprintf(fid, '    \\end{tabular}\n');
    fprintf(fid, '\\end{table}\n');
end
