function fig = prds_heatmap_option_b_figure(S, style, missionKeys)
%PRDS_HEATMAP_OPTION_B_FIGURE Build the one-column PRDS heatmap.
% The label row is intentionally separate from the heatmaps and colorbar so
% the communication-model axis title cannot overlap either tick labels.

fig = figure('Name', 'Maximum-agent PRDS option B', 'Color', 'w', ...
    'Units', 'inches', 'Position', [1 1 3.49 2.82], 'Visible', 'off');
% Explicit positions reserve separate, fixed bands for the tick labels,
% communication-model label, and colorbar at one-column width.
% Keep the three related elements visually grouped without allowing overlap.
axisPositions = [0.20 0.42 0.32 0.50; 0.60 0.42 0.32 0.50];

values = asDouble(S.mean);
limits = quantile(values, [0.10 0.90]);
assert(limits(1) < limits(2), 'Robust PRDS heatmap color limits are invalid.');
map = redYellowGreen(1025, 0.5);
colormap(fig, map);
axesList = gobjects(1, 2);

for mi = 1:2
    ax = axes(fig, 'Position', axisPositions(mi, :));
    axesList(mi) = ax;
    matrix = nan(6, 3);
    panel = S(string(S.scenario) == missionKeys(mi), :);
    for ai = 1:6
        for ci = 1:3
            row = panel(string(panel.algorithm) == style.algorithmKeys(ai) & ...
                string(panel.comm_model) == style.communicationKeys(ci), :);
            assert(height(row) == 1, ...
                'A PRDS option-B heatmap cell is absent or duplicated.');
            matrix(ai, ci) = asDouble(row.mean);
        end
    end
    imagesc(ax, 1:3, 1:6, matrix);
    set(ax, 'YDir', 'reverse');
    clim(ax, limits);
    xlim(ax, [0.5 3.5]);
    ylim(ax, [0.5 6.5]);
    xticks(ax, 1:3);
    xticklabels(ax, {'B', 'GE', 'R'});
    yticks(ax, 1:6);
    if mi == 1
        yticklabels(ax, style.algorithmLabels);
    else
        yticklabels(ax, strings(6, 1));
    end
    title(ax, missionKeys(mi), 'FontWeight', 'normal', ...
        'FontSize', style.titleFontSize);
    box(ax, 'on');
    set(ax, 'FontSize', style.axesFontSize, ...
        'TitleFontSizeMultiplier', 1, 'LabelFontSizeMultiplier', 1, ...
        'LineWidth', style.axisLineWidth, 'TickDir', 'out', 'Layer', 'top');

    for ai = 1:6
        for ci = 1:3
            colorIndex = 1 + round((matrix(ai, ci) - limits(1)) / ...
                diff(limits) * (size(map, 1) - 1));
            colorIndex = max(1, min(size(map, 1), colorIndex));
            rgb = map(colorIndex, :);
            luminance = 0.2126 * rgb(1) + 0.7152 * rgb(2) + 0.0722 * rgb(3);
            textColor = [0.08 0.08 0.08];
            if luminance < 0.46
                textColor = [1 1 1];
            end
            text(ax, ci, ai, sprintf('%.2f', matrix(ai, ci)), ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                'FontSize', style.legendFontSize, 'Color', textColor);
        end
    end
end

labelAxes = axes(fig, 'Position', [0.20 0.315 0.72 0.045]);
set(labelAxes, 'Color', 'none', 'XColor', 'none', 'YColor', 'none', ...
    'XTick', [], 'YTick', [], 'XLim', [0 1], 'YLim', [0 1]);
text(labelAxes, 0.5, 0.5, 'Communication model', ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
    'FontSize', style.axesFontSize, 'FontWeight', 'normal', ...
    'Tag', 'prdsCommunicationModelLabel');

sharedYLabel = ylabel(axesList(1), 'Algorithm');
set(sharedYLabel, 'FontSize', style.axesFontSize, 'FontWeight', 'normal');
cb = colorbar(axesList(2), 'southoutside');
cb.Location = 'southoutside';
cb.Units = 'normalized';
cb.Position = [0.20 0.225 0.72 0.045];
cb.Label.String = 'Mean PRDS (10th-90th percentile color range)';
cb.FontSize = style.legendFontSize;
cb.Label.FontSize = style.legendFontSize;
cb.Label.FontWeight = 'normal';
end

function map = redYellowGreen(count, zeroFraction)
green = [0.08 0.55 0.20];
yellow = [1.00 0.91 0.24];
red = [0.78 0.10 0.08];
split = max(2, min(count - 1, 1 + round(zeroFraction * (count - 1))));
lower = [linspace(green(1), yellow(1), split)', ...
    linspace(green(2), yellow(2), split)', ...
    linspace(green(3), yellow(3), split)'];
upperCount = count - split + 1;
upper = [linspace(yellow(1), red(1), upperCount)', ...
    linspace(yellow(2), red(2), upperCount)', ...
    linspace(yellow(3), red(3), upperCount)'];
map = [lower; upper(2:end, :)];
end

function x = asDouble(x)
if isnumeric(x) || islogical(x)
    x = double(x);
else
    x = str2double(string(x));
end
end
