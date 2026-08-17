function style = final_figure_style()
%FINAL_FIGURE_STYLE Frozen visual configuration for all active paper figures.
% The algorithm order, colors, and markers must not be changed independently
% in individual plotting functions.

style.algorithmKeys = ["CBAA", "ACBBA", "PI", "HIPC", "DMCHBA", "DGA"];
style.algorithmKeysLower = lower(style.algorithmKeys);
style.algorithmLabels = style.algorithmKeys;
style.colors = lines(6);
% Algorithms are distinguished by the frozen color order; use one simple
% circular marker throughout so shape does not add redundant visual encoding.
style.markers = repmat({'o'}, 1, 6);

style.missionKeys = ["CLIPS", "CV", "FGS"];
style.missionNames = [ ...
    "Clue-Informed Probabilistic Search (CLIPS)", ...
    "Collaborative Visit (CV)", ...
    "Full Grid Search (FGS)"];

style.communicationKeys = ["bernoulli", "gilbert_elliott", "rayleigh_style"];
style.communicationLabels = ["Bernoulli", "Gilbert-Elliott", "Rayleigh-style"];
style.lossLevels = [5 10 20 30 40 50 60 70];

% All figure text is fixed at one publication size.  MATLAB otherwise makes
% titles and axis labels larger through inherited font-size multipliers,
% which becomes especially visible when full-width and one-column figures
% are scaled independently by LaTeX.
style.publicationFontSize = 8.0;
style.axesFontSize = style.publicationFontSize;
style.titleFontSize = style.publicationFontSize;
style.legendFontSize = style.publicationFontSize;
style.lineWidth = 0.95;
style.axisLineWidth = 0.65;
style.markerSize = 3.8;
style.exportDpi = 600;
style.zeroColor = [0.45 0.45 0.45];
style.gridAlpha = 0.16;
end
