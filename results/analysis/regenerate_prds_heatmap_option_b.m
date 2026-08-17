function regenerate_prds_heatmap_option_b
%REGENERATE_PRDS_HEATMAP_OPTION_B Refresh the PRDS source and heatmap assets.
% Reads the common-six PRDS analysis table and rewrites only the dedicated
% Figure 3 source, PNG, inspection PNG, and editable FIG.

scriptDir = fileparts(mfilename('fullpath'));
figureDir = fullfile(scriptDir, 'figures');
inspectionDir = fullfile(figureDir, 'inspection');
sourcePath = fullfile(scriptDir, 'tables', 'final_figure_sources', ...
    'source_prds_heatmap_option_b.csv');
referencePath = fullfile(scriptDir, 'tables', ...
    'figure_prds_supplement_source.csv');
analysisPath = fullfile(scriptDir, 'tables', 'revised_prds.csv');
assert(isfile(analysisPath), 'Required common-six PRDS table is absent: %s', analysisPath);

opts = detectImportOptions(analysisPath, 'Delimiter', ',', 'TextType', 'string', ...
    'VariableNamingRule', 'preserve');
opts.DataLines = [2 Inf];
P = readtable(analysisPath, opts);
style = final_figure_style();
Pmax = P(string(P.metric) == "max_agent_steps", :);
writetable(Pmax, referencePath);
S = P(string(P.metric) == "max_agent_steps" & ...
    ismember(string(P.scenario), ["CLIPS", "CV"]), :);
assert(height(S) == 36, ...
    'Common-six PRDS source must contain 2 missions x 3 models x 6 algorithms.');
S.algorithm_order = nan(height(S), 1);
S.communication_order = nan(height(S), 1);
for ai = 1:6
    S.algorithm_order(string(S.algorithm) == style.algorithmKeys(ai)) = ai;
end
for ci = 1:3
    S.communication_order(string(S.comm_model) == style.communicationKeys(ci)) = ci;
end
assert(all(isfinite(S.algorithm_order)) && all(isfinite(S.communication_order)), ...
    'Unknown algorithm or communication model in common-six PRDS source.');
S = sortrows(S, {'scenario','algorithm_order','communication_order'});
if ~isfolder(fileparts(sourcePath)), mkdir(fileparts(sourcePath)); end
writetable(S, sourcePath);

fig = prds_heatmap_option_b_figure(S, style, ["CLIPS", "CV"]);

widthIn = 3.49;
heightIn = 2.82;
set(fig, 'Units', 'inches', 'Position', [1 1 widthIn heightIn], ...
    'PaperUnits', 'inches', 'PaperPosition', [0 0 widthIn heightIn], ...
    'PaperSize', [widthIn heightIn], 'Color', 'w');
apply_publication_figure_typography(fig, style);
drawnow;
stems = "prds_supplement";
for i = 1:numel(stems)
    pngPath = fullfile(figureDir, stems(i) + ".png");
    inspectionPngPath = fullfile(inspectionDir, stems(i) + ".png");
    figPath = fullfile(inspectionDir, stems(i) + ".fig");
    print(fig, pngPath, '-dpng', sprintf('-r%d', style.exportDpi));
    [copied, message] = copyfile(pngPath, inspectionPngPath, 'f');
    assert(copied, 'Could not copy inspection PNG: %s', message);
    savefig(fig, figPath);

    info = imfinfo(pngPath);
    assert(info.Width == round(widthIn * style.exportDpi) && ...
        info.Height == round(heightIn * style.exportDpi), ...
        'The PRDS heatmap dimensions do not match the paper canvas.');
    fprintf('PASS: regenerated publication-ready PRDS heatmap: %s\n', pngPath);
end
close(fig);
end
