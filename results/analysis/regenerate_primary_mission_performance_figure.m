% regenerate_primary_mission_performance_figure.m
% Rebuild Figure 1 only. Means and eligibility come from the six-way-paired
% primary source; confidence limits come from the seeded 10,000-resample
% paired bootstrap in dcta_metric_results.csv. Raw simulation CSVs are read
% indirectly through those derived tables and are never modified here.

clear; clc; close all;

scriptDir = fileparts(mfilename('fullpath'));
tableDir = fullfile(scriptDir, 'tables');
figureDir = fullfile(scriptDir, 'figures');
inspectionDir = fullfile(figureDir, 'inspection');
sourceDir = fullfile(tableDir, 'final_figure_sources');
ensureDir(figureDir); ensureDir(inspectionDir); ensureDir(sourceDir);

style = final_figure_style();
legacyPath = fullfile(tableDir, 'figure_maximum_agent_steps_source.csv');
masterPath = fullfile(tableDir, 'dcta_metric_results.csv');
sourcePath = fullfile(sourceDir, 'source_primary_mission_performance_curves.csv');

allSource = readCsv(legacyPath);
activeRows = ismember(string(allSource.scenario), style.missionKeys(1:2));
S = allSource(activeRows, :);
master = readCsv(masterPath);
master = master( ...
    string(master.result_type) == "condition_metric" & ...
    string(master.metric) == "max_agent_steps" & ...
    ismember(string(master.scenario), style.missionNames(1:2)), :);

assert(height(S) == 324, ...
    'Expected 324 Figure 1 rows before bootstrap-CI reconciliation.');
for i = 1:height(S)
    missionIndex = find(style.missionKeys(1:2) == string(S.scenario(i)), 1);
    assert(~isempty(missionIndex), 'Unknown mission in Figure 1 source.');
    match = string(master.scenario) == style.missionNames(missionIndex) & ...
        string(master.comm_model) == string(S.comm_model(i)) & ...
        asDouble(master.comm_level_pct) == asDouble(S.degradation_pct(i)) & ...
        string(master.algorithm) == string(S.algorithm(i));
    assert(sum(match) == 1, ...
        'Bootstrap source key is absent or duplicated at row %d.', i);
    assert(abs(asDouble(S.mean(i)) - asDouble(master.mean_value(match))) < 1e-10, ...
        'Mean mismatch against paired master table at row %d.', i);
    assert(asDouble(S.eligible_n(i)) == ...
        asDouble(master.eligible_paired_trials(match)), ...
        'Eligibility-count mismatch against paired master table at row %d.', i);
    S.ci95_low(i) = master.ci95_low(match);
    S.ci95_high(i) = master.ci95_high(match);
    S.ci_method(i) = ...
        "paired nonparametric bootstrap percentile interval; 10,000 resamples; RNG seed 20260714";
end

% Keep the active derived table and the figure-specific copy synchronized,
% while leaving the unrelated FGS rows unchanged.
allSource.ci95_low(activeRows) = S.ci95_low;
allSource.ci95_high(activeRows) = S.ci95_high;
allSource.ci_method(activeRows) = S.ci_method;
writetable(allSource, legacyPath);
S.metric_display = repmat("Maximum-agent steps", height(S), 1);
S.mission_row = nan(height(S), 1);
S.mission_row(string(S.scenario) == "CLIPS") = 1;
S.mission_row(string(S.scenario) == "CV") = 2;
S.figure_stem = repmat("primary_mission_performance_curves", height(S), 1);
writetable(S, sourcePath);

fig = plotPrimaryMissionPerformance(S, style);
widthIn = 7.00; heightIn = 2.71;
set(fig, 'Units', 'inches', 'Position', [1 1 widthIn heightIn], ...
    'PaperUnits', 'inches', 'PaperPosition', [0 0 widthIn heightIn], ...
    'PaperSize', [widthIn heightIn], 'Color', 'w');
apply_publication_figure_typography(fig, style);
drawnow;

pngPath = fullfile(figureDir, 'primary_mission_performance_curves.png');
inspectionPngPath = fullfile(inspectionDir, 'primary_mission_performance_curves.png');
figPath = fullfile(inspectionDir, 'primary_mission_performance_curves.fig');
print(fig, pngPath, '-dpng', sprintf('-r%d', style.exportDpi));
copyfile(pngPath, inspectionPngPath, 'f');
savefig(fig, figPath);
close(fig);

info = imfinfo(pngPath);
assert(abs(double(info.Width) - round(widthIn * style.exportDpi)) <= 2);
assert(abs(double(info.Height) - round(heightIn * style.exportDpi)) <= 2);
assert(isfile(figPath) && isfile(sourcePath));
fprintf('PASS: Figure 1 regenerated with 10,000-resample paired bootstrap CIs.\n');
fprintf('PNG: %s (%d x %d px)\n', pngPath, info.Width, info.Height);
fprintf('FIG: %s\n', figPath);
fprintf('Source: %s (%d rows)\n', sourcePath, height(S));

function T = readCsv(path)
    opts = detectImportOptions(path, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve', 'VariableNamesLine', 1);
    opts.DataLines = [2 Inf];
    T = readtable(path, opts);
end

function fig = plotPrimaryMissionPerformance(S, style)
    fig = figure('Name', 'Primary mission performance', 'Color', 'w', ...
        'Units', 'inches', 'Position', [1 1 7.00 2.71], 'Visible', 'off');
    layout = tiledlayout(fig, 2, 3, ...
        'TileSpacing', 'compact', 'Padding', 'compact');
    axesList = gobjects(2, 3); legendHandles = gobjects(1, 6);
    missionYLimits = zeros(2, 2);

    for mi = 1:2
        missionData = S(asDouble(S.mission_row) == mi, :);
        low = min(asDouble(missionData.ci95_low));
        high = max(asDouble(missionData.ci95_high));
        span = max(high - low, 1);
        missionYLimits(mi, :) = [max(0, low - 0.06 * span), high + 0.06 * span];
    end

    for mi = 1:2
        for ci = 1:3
            ax = nexttile(layout); axesList(mi, ci) = ax; hold(ax, 'on');
            for ai = 1:6
                G = S(asDouble(S.mission_row) == mi & ...
                    string(S.panel_model) == style.communicationKeys(ci) & ...
                    string(S.algorithm) == style.algorithmKeys(ai), :);
                assert(height(G) == 9, 'Incomplete Figure 1 curve.');
                [x, order] = sort(asDouble(G.degradation_pct));
                y = asDouble(G.mean); y = y(order);
                low = asDouble(G.ci95_low); low = low(order);
                high = asDouble(G.ci95_high); high = high(order);
                h = errorbar(ax, x, y, y - low, high - y, ...
                    'Color', style.colors(ai, :), 'LineStyle', '-', ...
                    'Marker', style.markers{ai}, ...
                    'MarkerFaceColor', style.colors(ai, :), ...
                    'MarkerSize', 2.4, 'LineWidth', 0.78, 'CapSize', 1.5);
                if mi == 1 && ci == 1, legendHandles(ai) = h; end
            end
            xlim(ax, [-2 72]); xticks(ax, [0 20 40 60]);
            ylim(ax, missionYLimits(mi, :));
            formatAxes(ax, style);
            if ci == 1
                text(ax, 0.02, 0.92, style.missionKeys(mi), ...
                    'Units', 'normalized', 'FontSize', style.axesFontSize, ...
                    'FontWeight', 'bold', 'VerticalAlignment', 'top', ...
                    'HorizontalAlignment', 'left', ...
                    'BackgroundColor', 'w', 'Margin', 0.6);
            else
                ax.YTickLabel = [];
            end
            if mi == 1
                title(ax, style.communicationLabels(ci), ...
                    'FontWeight', 'normal', 'FontSize', style.titleFontSize);
                ax.XTickLabel = [];
            end
        end
    end
    lgd = legend(axesList(1, 1), legendHandles, ...
        cellstr(style.algorithmLabels), 'Orientation', 'horizontal', ...
        'NumColumns', 6, 'Box', 'off', 'FontSize', style.legendFontSize);
    lgd.Layout.Tile = 'south'; lgd.ItemTokenSize = [12 7];
    xlabel(layout, 'Nominal message loss (%)');
    ylabel(layout, 'Maximum-agent steps');
end

function formatAxes(ax, style)
    grid(ax, 'on'); box(ax, 'on');
    set(ax, 'FontSize', style.axesFontSize, ...
        'TitleFontSizeMultiplier', 1, 'LabelFontSizeMultiplier', 1, ...
        'LineWidth', style.axisLineWidth, 'GridAlpha', style.gridAlpha, ...
        'MinorGridAlpha', style.gridAlpha / 2, 'TickDir', 'out', ...
        'Layer', 'top');
end

function value = asDouble(value)
    if isnumeric(value) || islogical(value)
        value = double(value);
    else
        value = str2double(string(value));
    end
end

function ensureDir(path)
    if ~exist(path, 'dir'), mkdir(path); end
end
