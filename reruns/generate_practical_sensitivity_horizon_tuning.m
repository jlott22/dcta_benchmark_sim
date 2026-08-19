% generate_practical_sensitivity_horizon_tuning.m
% Recompute CLIPS/CV horizon tuning with a standalone 1% practical-
% sensitivity rule and render one panel per mission. All inputs and outputs
% remain under the repository-root reruns directory.

clear; clc; close all;

scriptDir = fileparts(mfilename('fullpath'));
rawDir = fullfile(scriptDir, 'raw');
analysisDir = fullfile(scriptDir, 'analysis');
figureDir = fullfile(scriptDir, 'figures');
if ~isfolder(analysisDir), mkdir(analysisDir); end
if ~isfolder(figureDir), mkdir(figureDir); end

horizons = [1 2 3 5 8 12];
eligibleHorizons = [2 3 5 8 12];
commLabels = ["ideal", "bernoulli_025"];
algorithms = ["ACBBA", "PI", "HIPC", "DMCHBA", "DGA"];
plateauThresholdPct = 1.0;
nativeDefaultHorizon = 3;

missions = struct( ...
    'key', {"CLIPS", "CV"}, ...
    'rawFile', {fullfile(rawDir, 'clips_horizon_tuning_raw.csv'), ...
                fullfile(rawDir, 'cv_horizon_tuning_raw.csv')}, ...
    'metric', {"max_steps_any_robot", "max_robot_steps"}, ...
    'previous', {[8 3 5 5 3], [3 5 8 3 3]});

summaryRows = table();
selectionRows = table();

for mi = 1:numel(missions)
    mission = missions(mi);
    assert(isfile(mission.rawFile), 'Missing raw tuning file: %s', mission.rawFile);
    T = readCsv(mission.rawFile);

    for ai = 1:numel(algorithms)
        algorithm = algorithms(ai);
        previous = mission.previous(ai);
        algorithmKey = lower(algorithm);
        mask = lower(string(T.algorithm_key)) == algorithmKey & ...
            ismember(lower(string(T.comm_label)), commLabels);
        A = T(mask, :);

        [trialMeans, retainedTrialIds] = buildCompleteTrialMatrix( ...
            A, horizons, commLabels, mission.metric);
        nMatched = height(trialMeans);
        assert(nMatched > 1, '%s %s has fewer than two complete trials.', ...
            mission.key, algorithm);

        means = mean(trialMeans{:, 2:end}, 1, 'omitnan');
        standardErrors = std(trialMeans{:, 2:end}, 0, 1, 'omitnan') ./ sqrt(nMatched);
        eligibleMask = ismember(horizons, eligibleHorizons);
        eligibleMeans = means(eligibleMask);
        eligibleSE = standardErrors(eligibleMask);
        [bestMean, bestLocalIndex] = min(eligibleMeans);
        eligibleList = horizons(eligibleMask);
        empiricalBest = eligibleList(bestLocalIndex);
        worstMean = max(eligibleMeans);
        relativeRangePct = 100 * (worstMean - bestMean) / bestMean;
        horizonInformative = relativeRangePct > plateauThresholdPct + 1e-12;
        if horizonInformative
            selected = empiricalBest;
            classification = "horizon-informative";
            action = "selected empirical minimum";
        else
            selected = nativeDefaultHorizon;
            classification = "horizon-insensitive";
            action = "selected native default for flat curve";
        end

        for hi = 1:numel(horizons)
            h = horizons(hi);
            row = table(mission.key, algorithm, h, mission.metric, nMatched, ...
                means(hi), standardErrors(hi), ismember(h, eligibleHorizons), ...
                empiricalBest, bestMean, worstMean, relativeRangePct, ...
                plateauThresholdPct, horizonInformative, classification, ...
                nativeDefaultHorizon, selected, h == selected, ...
                'VariableNames', {'scenario','algorithm','horizon','metric_column', ...
                'n_matched_trials','mean_primary_steps','standard_error_steps', ...
                'eligible','empirical_best_horizon','empirical_best_mean', ...
                'eligible_worst_mean','relative_range_pct', ...
                'plateau_threshold_pct','horizon_informative','classification', ...
                'native_default_horizon','selected_horizon','selected'});
            summaryRows = [summaryRows; row]; %#ok<AGROW>
        end

        selectionRow = table(mission.key, algorithm, previous, selected, ...
            selected ~= previous, empiricalBest, relativeRangePct, ...
            plateauThresholdPct, horizonInformative, classification, ...
            nativeDefaultHorizon, nMatched, mission.metric, action, ...
            'VariableNames', {'scenario','algorithm','previous_horizon', ...
            'final_horizon','changed','empirical_best_horizon', ...
            'relative_range_pct','plateau_threshold_pct','horizon_informative', ...
            'classification','native_default_horizon','n_matched_trials', ...
            'metric_column','selection_action'});
        selectionRows = [selectionRows; selectionRow]; %#ok<AGROW>

        assert(numel(retainedTrialIds) == nMatched);
    end
end

% Add the fixed single-task baseline to the compact final table.
for mi = 1:numel(missions)
    fixedRow = table(missions(mi).key, "CBAA", 1, 1, false, 1, NaN, ...
        plateauThresholdPct, false, "fixed", 1, NaN, ...
        "fixed_single_task", "fixed single-task horizon", ...
        'VariableNames', selectionRows.Properties.VariableNames);
    selectionRows = [selectionRows; fixedRow]; %#ok<AGROW>
end

summaryRows = sortrows(summaryRows, {'scenario','algorithm','horizon'});
selectionRows = sortrows(selectionRows, {'scenario','algorithm'});
writetable(summaryRows, fullfile(analysisDir, ...
    'practical_sensitivity_horizon_summary.csv'));
writetable(selectionRows, fullfile(analysisDir, 'final_tuning_values.csv'));

% Locked verification for the standalone rule. CLIPS PI changes to h=2;
% CV ACBBA, HIPC, and PI change to h=2. DGA and DMCHBA retain their existing
% horizons because the rule independently selects those values.
expected = table( ...
    [repmat("CLIPS", 6, 1); repmat("CV", 6, 1)], ...
    ["ACBBA";"CBAA";"DGA";"DMCHBA";"HIPC";"PI"; ...
     "ACBBA";"CBAA";"DGA";"DMCHBA";"HIPC";"PI"], ...
    [8;1;3;5;5;2; 2;1;3;3;2;2], ...
    'VariableNames', {'scenario','algorithm','expected_final_horizon'});
actual = selectionRows(:, {'scenario','algorithm','final_horizon'});
actual = sortrows(actual, {'scenario','algorithm'});
expected = sortrows(expected, {'scenario','algorithm'});
assert(isequal(actual.scenario, expected.scenario));
assert(isequal(actual.algorithm, expected.algorithm));
assert(isequal(actual.final_horizon, expected.expected_final_horizon), ...
    'Final horizons do not match the locked expected values.');

clipsChanged = selectionRows.scenario == "CLIPS" & selectionRows.changed;
cvChanged = selectionRows.scenario == "CV" & selectionRows.changed;
actualCLIPSChanged = sort(selectionRows.algorithm(clipsChanged));
actualCVChanged = sort(selectionRows.algorithm(cvChanged));
expectedCLIPSChanged = "PI";
expectedCVChanged = sort(["ACBBA"; "HIPC"; "PI"]);
assert(isequal(actualCLIPSChanged, expectedCLIPSChanged), ...
    'CLIPS changed-algorithm set is not exactly PI.');
assert(isequal(actualCVChanged, expectedCVChanged), ...
    'CV changed-algorithm set is not exactly ACBBA, HIPC, and PI.');

plateauRows = selectionRows.classification == "horizon-insensitive";
actualPlateaus = sort(selectionRows.scenario(plateauRows) + ":" + ...
    selectionRows.algorithm(plateauRows));
expectedPlateaus = sort(["CLIPS:DGA"; "CV:DMCHBA"]);
assert(isequal(actualPlateaus, expectedPlateaus), ...
    'Horizon-insensitive classification set is incorrect.');

verification = table( ...
    ["clips_only_pi_changed"; "cv_only_expected_algorithms_changed"; ...
     "flat_curve_classifications_match"; ...
     "final_horizons_match_locked_expectation"], ...
    [isequal(actualCLIPSChanged, expectedCLIPSChanged); ...
     isequal(actualCVChanged, expectedCVChanged); ...
     isequal(actualPlateaus, expectedPlateaus); true], ...
    ["Only PI changed in CLIPS"; ...
     "Only ACBBA, HIPC, and PI changed in CV"; ...
     "Only CLIPS DGA and CV DMCHBA were classified horizon-insensitive"; ...
     "CLIPS=[8,1,3,5,5,2]; CV=[2,1,3,3,2,2] in sorted algorithm order"], ...
    'VariableNames', {'check','passed','detail'});
writetable(verification, fullfile(analysisDir, 'verification_summary.csv'));

% Publication-style two-panel figure: one mission per panel, one curve per
% allocator, error bars are +/- one standard error, and pentagrams mark the
% final selected horizons. Horizon 1 is shown but was ineligible for tuning.
colors = [0.0000 0.4470 0.7410; 0.8500 0.3250 0.0980; ...
          0.4660 0.6740 0.1880; 0.4940 0.1840 0.5560; ...
          0.3010 0.7450 0.9330];
fig = figure('Name', 'Practical-sensitivity horizon tuning', 'Color', 'w', ...
    'Units', 'inches', 'Position', [1 1 3.49 4.30], 'Visible', 'off');
layout = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
axesList = gobjects(1, 2);
legendHandles = gobjects(1, numel(algorithms));

for mi = 1:numel(missions)
    ax = nexttile(layout); axesList(mi) = ax; hold(ax, 'on');
    for ai = 1:numel(algorithms)
        G = summaryRows(summaryRows.scenario == missions(mi).key & ...
            summaryRows.algorithm == algorithms(ai), :);
        G = sortrows(G, 'horizon');
        h = errorbar(ax, G.horizon, G.mean_primary_steps, ...
            G.standard_error_steps, '-o', 'Color', colors(ai, :), ...
            'LineWidth', 1.05, 'MarkerSize', 3.0, ...
            'MarkerFaceColor', colors(ai, :), 'CapSize', 2.5);
        if mi == 1, legendHandles(ai) = h; end
        chosen = G.selected;
        plot(ax, G.horizon(chosen), G.mean_primary_steps(chosen), ...
            'LineStyle', 'none', 'Marker', 'p', 'MarkerSize', 7.0, ...
            'MarkerFaceColor', colors(ai, :), 'MarkerEdgeColor', 'k', ...
            'LineWidth', 0.8, 'HandleVisibility', 'off');
    end
    title(ax, missions(mi).key, 'FontWeight', 'normal', 'FontSize', 8);
    xticks(ax, horizons); xlim(ax, [0.5 12.5]);
    if mi == 1, xticklabels(ax, []); end
    grid(ax, 'on'); box(ax, 'on');
    set(ax, 'FontName', 'Arial', 'FontSize', 7, 'LineWidth', 0.65, ...
        'GridAlpha', 0.16, 'TickDir', 'out', 'Layer', 'top');
end
xlabel(layout, 'Commitment horizon', 'FontName', 'Arial', 'FontSize', 8);
ylabel(layout, 'Mean maximum-agent steps (+/- 1 SE)', ...
    'FontName', 'Arial', 'FontSize', 8);
lgd = legend(axesList(1), legendHandles, cellstr(algorithms), ...
    'Orientation', 'horizontal', 'NumColumns', 3, 'Box', 'off', ...
    'FontName', 'Arial', 'FontSize', 6.5);
lgd.Layout.Tile = 'south';
lgd.ItemTokenSize = [11 7];

set(fig, 'PaperUnits', 'inches', 'PaperPosition', [0 0 3.49 4.30], ...
    'PaperSize', [3.49 4.30]);
drawnow;
pngPath = fullfile(figureDir, 'practical_sensitivity_horizon_tuning.png');
pdfPath = fullfile(figureDir, 'practical_sensitivity_horizon_tuning.pdf');
figPath = fullfile(figureDir, 'practical_sensitivity_horizon_tuning.fig');
print(fig, pngPath, '-dpng', '-r600');
exportgraphics(fig, pdfPath, 'ContentType', 'vector');
savefig(fig, figPath);
close(fig);

info = imfinfo(pngPath);
assert(info.Width > 1500 && info.Height > 2000, ...
    'Rendered PNG resolution is unexpectedly low.');

fprintf('PASS: practical-sensitivity tuning tables and figure generated.\n');
disp(selectionRows(:, {'scenario','algorithm','previous_horizon', ...
    'final_horizon','changed','relative_range_pct','classification'}));

function T = readCsv(path)
    opts = detectImportOptions(path, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve', 'VariableNamesLine', 1);
    opts.DataLines = [2 Inf];
    T = readtable(path, opts);
end

function [trialMeans, retainedTrialIds] = buildCompleteTrialMatrix( ...
        T, horizons, commLabels, metricName)
    trialIds = unique(string(T.trial_id), 'stable');
    matrix = NaN(numel(trialIds), numel(horizons));
    keep = false(numel(trialIds), 1);
    values = asDouble(T.value);
    metric = asDouble(T.(metricName));
    comm = lower(string(T.comm_label));
    ids = string(T.trial_id);

    for ti = 1:numel(trialIds)
        complete = true;
        for hi = 1:numel(horizons)
            conditionValues = NaN(1, numel(commLabels));
            for ci = 1:numel(commLabels)
                match = ids == trialIds(ti) & values == horizons(hi) & ...
                    comm == commLabels(ci) & isfinite(metric);
                if sum(match) ~= 1
                    complete = false;
                    break;
                end
                conditionValues(ci) = metric(match);
            end
            if ~complete, break; end
            matrix(ti, hi) = mean(conditionValues);
        end
        keep(ti) = complete;
    end

    retainedTrialIds = trialIds(keep);
    matrix = matrix(keep, :);
    variableNames = ["trial_id", "h" + string(horizons)];
    trialMeans = array2table(matrix, 'VariableNames', cellstr(variableNames(2:end)));
    trialMeans = addvars(trialMeans, retainedTrialIds, 'Before', 1, ...
        'NewVariableNames', 'trial_id');
end

function value = asDouble(value)
    if isnumeric(value) || islogical(value)
        value = double(value);
    else
        value = str2double(string(value));
    end
end
