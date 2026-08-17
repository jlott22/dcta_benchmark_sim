function regenerate_current_paper_figure_typography
%REGENERATE_CURRENT_PAPER_FIGURE_TYPOGRAPHY Standardize the five paper figures.
% Canvas widths match the measured IEEE full-width and one-column placements
% in Classical_DTA_Benchmark_3 (17).pdf, so 8-point source text remains
% approximately 8 points after LaTeX scaling.

scriptDir = fileparts(mfilename('fullpath'));
figureDir = fullfile(scriptDir, 'figures');
inspectionDir = fullfile(figureDir, 'inspection');
style = final_figure_style();

% The paper uses the compact two-mission PRDS heatmap. Rebuild that active
% asset from its source first.
regenerate_prds_heatmap_option_b;

specs = struct( ...
    'sourceStem', { ...
        'primary_mission_performance_curves', ...
        'communication_performance_tradeoff', ...
        'prds_supplement', ...
        'grid_density_maximum_agent_steps_summary', ...
        'horizon_tuning'}, ...
    'outputStem', { ...
        'primary_mission_performance_curves', ...
        'communication_performance_tradeoff', ...
        'prds_supplement', ...
        'grid_density_maximum_agent_steps_summary', ...
        'horizon_tuning'}, ...
    'widthIn', {7.00, 3.49, 3.49, 3.49, 3.49}, ...
    'heightIn', {2.71, 2.12, 2.82, 4.30, 3.74});

for i = 1:numel(specs)
    sourceFigPath = fullfile(inspectionDir, specs(i).sourceStem + ".fig");
    assert(isfile(sourceFigPath), 'Editable source figure is absent: %s', sourceFigPath);
    fig = openfig(sourceFigPath, 'invisible');
    cleanup = onCleanup(@() closeIfValid(fig));

    widthIn = specs(i).widthIn;
    heightIn = specs(i).heightIn;
    set(fig, 'Units', 'inches', 'Position', [1 1 widthIn heightIn], ...
        'PaperUnits', 'inches', 'PaperPosition', [0 0 widthIn heightIn], ...
        'PaperSize', [widthIn heightIn], 'Color', 'w');
    applyPaperAxisWording(fig, specs(i).outputStem);
    apply_publication_figure_typography(fig, style);
    drawnow;

    pngPath = fullfile(figureDir, specs(i).outputStem + ".png");
    inspectionPngPath = fullfile(inspectionDir, specs(i).outputStem + ".png");
    outputFigPath = fullfile(inspectionDir, specs(i).outputStem + ".fig");
    print(fig, pngPath, '-dpng', sprintf('-r%d', style.exportDpi));
    [copied, message] = copyfile(pngPath, inspectionPngPath, 'f');
    assert(copied, 'Could not copy inspection PNG: %s', message);
    savefig(fig, outputFigPath);

    info = imfinfo(pngPath);
    assert(info.Width == round(widthIn * style.exportDpi) && ...
        info.Height == round(heightIn * style.exportDpi), ...
        'Unexpected exported dimensions for %s.', specs(i).outputStem);
    validateTypography(fig, style.publicationFontSize, specs(i).outputStem);
    fprintf('PASS: %s -> %d x %d px, all text %.1f pt\n', ...
        specs(i).outputStem, info.Width, info.Height, ...
        style.publicationFontSize);

    close(fig);
    clear cleanup;
end
end

function validateTypography(fig, expectedSize, stem)
objects = findall(fig, '-property', 'FontSize');
sizes = nan(numel(objects), 1);
for i = 1:numel(objects)
    sizes(i) = double(objects(i).FontSize);
end
assert(~isempty(sizes) && all(abs(sizes - expectedSize) < 1e-9), ...
    '%s contains inconsistent figure-text sizes.', stem);
layouts = findall(fig, 'Type', 'tiledlayout');
for i = 1:numel(layouts)
    layoutSizes = [layouts(i).XLabel.FontSize, ...
        layouts(i).YLabel.FontSize, layouts(i).Title.FontSize];
    assert(all(abs(layoutSizes - expectedSize) < 1e-9), ...
        '%s contains inconsistent tiled-layout text sizes.', stem);
end
colorbars = findall(fig, 'Type', 'colorbar');
for i = 1:numel(colorbars)
    assert(abs(colorbars(i).FontSize - expectedSize) < 1e-9 && ...
        abs(colorbars(i).Label.FontSize - expectedSize) < 1e-9, ...
        '%s contains inconsistent colorbar text sizes.', stem);
end
end

function applyPaperAxisWording(fig, stem)
    layouts = findall(fig, 'Type', 'tiledlayout');
    switch string(stem)
        case "primary_mission_performance_curves"
            assert(numel(layouts) == 1, ...
                'Expected one tiled layout in the primary performance figure.');
            xlabel(layouts(1), 'Nominal message loss (%)');
        case "communication_performance_tradeoff"
            assert(numel(layouts) == 1, ...
                'Expected one tiled layout in the communication tradeoff figure.');
            xlabel(layouts(1), 'Message publication rate');
    end
end

function closeIfValid(fig)
if isgraphics(fig, 'figure')
    close(fig);
end
end
