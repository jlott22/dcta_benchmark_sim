function apply_publication_figure_typography(fig, style)
%APPLY_PUBLICATION_FIGURE_TYPOGRAPHY Enforce one final-size font everywhere.
% This is intentionally applied immediately before export so tiled-layout
% labels, colorbars, legends, annotations, titles, and ordinary axes cannot
% retain MATLAB's different inherited defaults.

assert(isgraphics(fig, 'figure'), 'A valid MATLAB figure is required.');
assert(isfield(style, 'publicationFontSize'), ...
    'final_figure_style must define publicationFontSize.');

fontSize = style.publicationFontSize;
axesObjects = findall(fig, 'Type', 'axes');
for i = 1:numel(axesObjects)
    ax = axesObjects(i);
    ax.FontSize = fontSize;
    if isprop(ax, 'TitleFontSizeMultiplier')
        ax.TitleFontSizeMultiplier = 1;
    end
    if isprop(ax, 'LabelFontSizeMultiplier')
        ax.LabelFontSizeMultiplier = 1;
    end
end

% Tiled-layout labels are matlab.graphics.layout.Text objects and are not
% returned by findall(fig, '-property', 'FontSize'). Normalize them
% explicitly; otherwise MATLAB leaves shared labels at its 12/13-point
% defaults even when every ordinary axes object is set to 8 points.
layoutObjects = findall(fig, 'Type', 'tiledlayout');
for i = 1:numel(layoutObjects)
    layoutObjects(i).XLabel.FontSize = fontSize;
    layoutObjects(i).YLabel.FontSize = fontSize;
    layoutObjects(i).Title.FontSize = fontSize;
end

colorbarObjects = findall(fig, 'Type', 'colorbar');
for i = 1:numel(colorbarObjects)
    colorbarObjects(i).FontSize = fontSize;
    colorbarObjects(i).Label.FontSize = fontSize;
end

fontObjects = findall(fig, '-property', 'FontSize');
for i = 1:numel(fontObjects)
    try
        fontObjects(i).FontSize = fontSize;
    catch err
        error('Could not normalize figure typography for %s: %s', ...
            class(fontObjects(i)), err.message);
    end
end

drawnow;

% Recheck after layout resolution because tiled layouts can instantiate or
% update shared labels during drawnow.
fontObjects = findall(fig, '-property', 'FontSize');
observed = nan(numel(fontObjects), 1);
for i = 1:numel(fontObjects)
    observed(i) = double(fontObjects(i).FontSize);
end
assert(all(abs(observed - fontSize) < 1e-9), ...
    'Figure contains text that does not use the publication font size.');

for i = 1:numel(layoutObjects)
    layoutFontSizes = [layoutObjects(i).XLabel.FontSize, ...
        layoutObjects(i).YLabel.FontSize, layoutObjects(i).Title.FontSize];
    assert(all(abs(layoutFontSizes - fontSize) < 1e-9), ...
        'Tiled-layout text does not use the publication font size.');
end
for i = 1:numel(colorbarObjects)
    assert(abs(colorbarObjects(i).FontSize - fontSize) < 1e-9 && ...
        abs(colorbarObjects(i).Label.FontSize - fontSize) < 1e-9, ...
        'Colorbar text does not use the publication font size.');
end
end
