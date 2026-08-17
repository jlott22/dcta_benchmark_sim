% generate_final_paper_figures_CLIPS_CV.m
% Single MATLAB entry point for every active CLIPS/CV benchmark-paper figure.
% The script reads existing analysis tables plus selected columns from the
% authoritative combined CLIPS/CV result CSVs. It does not rerun simulations
% or modify any raw benchmark CSV.

clear; clc; close all;

scriptDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(fileparts(scriptDir));
tableDir = fullfile(scriptDir, 'tables');
activeFigureDir = fullfile(scriptDir, 'figures');
inspectionDir = fullfile(activeFigureDir, 'inspection');
sourceDir = fullfile(tableDir, 'final_figure_sources');
archiveRoot = fullfile(repoRoot, 'archive_private', ...
    'figure_regeneration_history');
ensureDir(activeFigureDir); ensureDir(inspectionDir);
ensureDir(sourceDir); ensureDir(archiveRoot);

missionKeys = ["CLIPS", "CV"];
missionNames = ["Clue-Informed Probabilistic Search (CLIPS)", ...
    "Collaborative Visit (CV)"];
activeStems = [ ...
    "primary_mission_performance_curves", ...
    "communication_performance_tradeoff", ...
    "prds_supplement", ...
    "grid_density_maximum_agent_steps_summary", ...
    "horizon_tuning"];

logPath = fullfile(tableDir, 'paper_figure_generation_log.txt');
if isfile(logPath), delete(logPath); end
diary(logPath);
cleanupDiary = onCleanup(@() diary('off'));

style = final_figure_style();
fprintf('Final CLIPS/CV DCTA MATLAB figure regeneration\n');
fprintf('Started: %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss Z')));
fprintf('MATLAB: %s\n', version);
fprintf('Repository: repository root\n\n');

inputPaths = finalInputPaths(tableDir);
sourceManifest = buildSourceManifest(inputPaths, repoRoot);
manifestPath = fullfile(tableDir, 'paper_figure_source_manifest.csv');
writetable(sourceManifest, manifestPath);
fprintf('Wrote source manifest: %s\n', displayPath(manifestPath));

inputs = loadInputs(inputPaths);
validationChecks = validateAuthoritativeInputs(inputs, style, missionKeys);
fprintf('PASS: active-table structure and cross-table numerical provenance verified.\n');

archiveManifestPath = fullfile(archiveRoot, 'archive_manifest.csv');
if isfile(archiveManifestPath)
    archiveOptions = detectImportOptions(archiveManifestPath, ...
        'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve', 'VariableNamesLine', 1);
    archiveOptions.DataLines = [2 Inf];
    previousArchiveManifest = readtable(archiveManifestPath, archiveOptions);
else
    previousArchiveManifest = table();
end
newArchiveManifest = archiveSupersededOutputs( ...
    activeFigureDir, inspectionDir, sourceDir, archiveRoot);
archiveManifest = [previousArchiveManifest; newArchiveManifest];
if ~isempty(archiveManifest)
    [~, uniqueRows] = unique(archiveManifest.archived_path, 'stable');
    archiveManifest = archiveManifest(sort(uniqueRows), :);
end
writetable(archiveManifest, archiveManifestPath);
fprintf('Wrote archive manifest: %s\n', displayPath(archiveManifestPath));

figureInventory = table('Size', [0 9], ...
    'VariableTypes', {'string','string','double','double','double','double', ...
    'string','string','double'}, ...
    'VariableNames', {'figure_id','stem','canvas_width_in','canvas_height_in', ...
    'png_width_px','png_height_px','png_path','fig_path','source_rows'});

% Figure 1: full-width, two mission rows by three communication columns.
S1 = preparePrimaryMissionSource(inputs.maximumAgent, inputs.metricResults, style);
S1 = writeAndReloadSource(S1, fullfile(sourceDir, ...
    'source_primary_mission_performance_curves.csv'));
fig = plotPrimaryMissionPerformance(S1, style, missionKeys);
figureInventory = [figureInventory; exportFinalFigure(fig, ...
    "Figure 1", "primary_mission_performance_curves", 7.00, 2.71, ...
    activeFigureDir, inspectionDir, style, height(S1))];

% Figure 2: one-column, side-by-side mission communication tradeoff.
S2 = prepareCommunicationSummary(inputs.communicationTradeoff, style, ...
    missionKeys, missionNames);
S2 = writeAndReloadSource(S2, fullfile(sourceDir, ...
    'source_communication_performance_tradeoff.csv'));
fig = plotCommunicationPerformanceTradeoff(S2, style, missionKeys);
figureInventory = [figureInventory; exportFinalFigure(fig, ...
    "Figure 2", "communication_performance_tradeoff", 3.49, 2.12, ...
    activeFigureDir, inspectionDir, style, height(S2))];

% Figure 4: maximum-agent scale means from the raw-data complete-block
% cohort.  This must not reuse independently eligible algorithm summaries.
S3B = prepareCompleteBlockGridDensityMaxStepsSource( ...
    inputs.gridDensityCompleteBlocks, style, ...
    missionKeys, missionNames);
S3B = writeAndReloadSource(S3B, fullfile(sourceDir, ...
    'source_grid_density_maximum_agent_steps_summary.csv'));
fig = plotGridDensityMaxStepsSummary(S3B, style, missionKeys);
figureInventory = [figureInventory; exportFinalFigure(fig, ...
    "Figure 4", "grid_density_maximum_agent_steps_summary", 3.49, 4.30, ...
    activeFigureDir, inspectionDir, style, height(S3B))];

% Horizon tuning: the exact combined robust-score formula used for selection.
SH = prepareHorizonRobustSource(inputs.horizonDecisionClips, ...
    inputs.horizonDecisionCv, missionNames);
SH.figure_stem = repmat("horizon_tuning", height(SH), 1);
SH.plot_rule = repmat( ...
    "one robust-score curve per algorithm; pentagram marks decision-table selection; higher is better", ...
    height(SH), 1);
SH = writeAndReloadSource(SH, fullfile(sourceDir, ...
    'source_horizon_tuning_line_option_a.csv'));
fig = plotHorizonTuning(SH, style, missionNames, missionKeys);
figureInventory = [figureInventory; exportFinalFigure(fig, ...
    "Figure 5", "horizon_tuning", 3.49, 3.74, ...
    activeFigureDir, inspectionDir, style, height(SH))];

% Figure 3: one-column heatmap of the maximum-agent PRDS means.
S4 = preparePrdsSource(inputs.prds, style, missionKeys);
S4B = S4;
S4B.figure_stem = repmat("prds_supplement", height(S4B), 1);
S4B.plot_rule = repmat( ...
    "mean PRDS summary values; 1025-color green-yellow-red scale clipped to the 10th-90th percentile range so outliers do not compress other cells; exact annotations retained", ...
    height(S4B), 1);
S4B = writeAndReloadSource(S4B, fullfile(sourceDir, ...
    'source_prds_heatmap_option_b.csv'));
fig = plotPrdsHeatmapOptionB(S4B, style, missionKeys);
figureInventory = [figureInventory; exportFinalFigure(fig, ...
    "Figure 3", "prds_supplement", 3.49, 2.82, ...
    activeFigureDir, inspectionDir, style, height(S4B))];

releaseInventory = relativizeInventory(figureInventory, repoRoot);
inventoryPath = fullfile(tableDir, 'paper_figure_inventory.csv');
writetable(releaseInventory, inventoryPath);

captionPath = fullfile(scriptDir, 'FIGURE_CAPTIONS_REVISED_CLIPS_CV.tex');
writeRevisedCaptions(captionPath);
reportPath = fullfile(scriptDir, 'PAPER_FIGURE_VALIDATION.md');
writeValidationReport(reportPath, sourceManifest, archiveManifest, ...
    releaseInventory, validationChecks, style, sourceDir, captionPath);

validateFinalInventory(activeFigureDir, inspectionDir, sourceDir, ...
    figureInventory, sourceManifest, archiveManifest, activeStems, style);

fprintf('\nPASS: all five active CLIPS/CV paper figures regenerated and validated in MATLAB.\n');
fprintf('Active 600-dpi PNGs: %s\n', displayPath(activeFigureDir));
fprintf('Inspection PNG/FIG copies: %s\n', displayPath(inspectionDir));
fprintf('Dedicated source CSVs: %s\n', displayPath(sourceDir));
fprintf('Validation report: %s\n', displayPath(reportPath));

function paths = finalInputPaths(tableDir)
    names = [ ...
        "dcta_metric_results.csv", ...
        "figure_maximum_agent_steps_source.csv", ...
        "figure_communication_tradeoff_source.csv", ...
        "grid_density_analysis_results.csv", ...
        "grid_density_complete_block_plot_source.csv", ...
        "revised_prds.csv", ...
        "figure_prds_supplement_source.csv", ...
        "horizon_tuning_paired_trial_delta_summary.csv", ...
        "trajectory_sample_sizes.csv", ...
        "clue_horizon_tuning_decision.csv", ...
        "known_horizon_tuning_decision.csv"];
    repositoryRoot = fileparts(fileparts(fileparts(tableDir)));
    paths = [fullfile(tableDir, names), ...
        fullfile(repositoryRoot, 'results', 'clue_search_core_500', ...
            'combined', 'clue_search_core_500_combined_system_performance.csv'), ...
        fullfile(repositoryRoot, 'results', 'known_target_visit_core_500', ...
            'combined', 'known_target_visit_core_500_combined_system_performance.csv')];
end

function inputs = loadInputs(paths)
    inputs.metricResults = readCsv(paths(1));
    inputs.maximumAgent = readCsv(paths(2));
    inputs.communicationTradeoff = readCsv(paths(3));
    inputs.gridDensity = readCsv(paths(4));
    inputs.gridDensityCompleteBlocks = readCsv(paths(5));
    inputs.prds = readCsv(paths(6));
    inputs.prdsFigureReference = readCsv(paths(7));
    inputs.horizon = readCsv(paths(8));
    inputs.trajectorySampleSizes = readCsv(paths(9));
    inputs.horizonDecisionClips = readCsv(paths(10));
    inputs.horizonDecisionCv = readCsv(paths(11));
    inputs.prdsRawClips = readSelectedCsv(paths(12), ...
        {'trial_id','algorithm_key','comm_label','max_steps_any_robot'});
    inputs.prdsRawCv = readSelectedCsv(paths(13), ...
        {'trial_id','algorithm_key','comm_label','max_robot_steps'});
end

function T = readCsv(path)
    if ~isfile(path), error('Required input is absent: %s', path); end
    opts = detectImportOptions(path, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve', 'VariableNamesLine', 1);
    opts.DataLines = [2 Inf];
    T = readtable(path, opts);
end

function T = readSelectedCsv(path, variableNames)
    if ~isfile(path), error('Required input is absent: %s', path); end
    opts = detectImportOptions(path, 'Delimiter', ',', 'TextType', 'string', ...
        'VariableNamingRule', 'preserve', 'VariableNamesLine', 1);
    opts.DataLines = [2 Inf];
    opts.SelectedVariableNames = variableNames;
    T = readtable(path, opts);
end

function manifest = buildSourceManifest(paths, repoRoot)
    rows = cell(numel(paths), 1);
    for i = 1:numel(paths)
        path = char(paths(i));
        if ~isfile(path), error('Required source file is absent: %s', path); end
        info = dir(path);
        normalized = lower(strrep(path, '/', '\'));
        archived = contains(normalized, '\archive\') || contains(normalized, 'pre_correct');
        if archived
            error('Archived or pre-correction input is not permitted: %s', path);
        end
        repositoryPath = string(strrep(relativePath(path, repoRoot), '\', '/'));
        rows{i} = table(repositoryPath, info.bytes, countCsvRows(path), ...
            string(datetime(info.datenum, 'ConvertFrom', 'datenum', ...
            'Format', 'yyyy-MM-dd HH:mm:ss Z')), string(sha256File(path)), ...
            ~archived, 'VariableNames', {'repository_path','bytes','data_rows', ...
            'last_modified','sha256','active_source_verified'});
    end
    manifest = vertcat(rows{:});
end

function checks = validateAuthoritativeInputs(inputs, style, missionKeys)
    % Every retained core source must identify the current fixed-rho
    % Gilbert--Elliott campaign and all eight impaired levels.
    geTables = {inputs.maximumAgent, inputs.communicationTradeoff};
    for ti = 1:numel(geTables)
        T = geTables{ti};
        if ismember('scenario', T.Properties.VariableNames)
            T = T(ismember(string(T.scenario), missionKeys), :);
        end
        isGe = string(T.comm_model) == "gilbert_elliott";
        assert(any(isGe), 'A retained core figure source lacks Gilbert--Elliott rows.');
        assert(all(contains(string(T.comm_label(isGe)), "rho_0_8")), ...
            'A retained core figure source contains nonfinal Gilbert--Elliott labels.');
        assert(isequal(sort(unique(asDouble(T.degradation_pct(isGe))))', style.lossLevels), ...
            'Gilbert--Elliott loss levels do not match the final eight-level design.');
    end

    maximumAgent = inputs.maximumAgent( ...
        ismember(string(inputs.maximumAgent.scenario), missionKeys), :);
    assert(height(maximumAgent) == 324, ...
        'Maximum-agent source must contain 2 missions x 3 panels x 9 levels x 6 algorithms.');
    for mi = 1:2
        for ci = 1:3
            for ai = 1:6
                G = maximumAgent(string(maximumAgent.scenario) == missionKeys(mi) & ...
                    string(maximumAgent.panel_model) == style.communicationKeys(ci) & ...
                    string(maximumAgent.algorithm) == style.algorithmKeys(ai), :);
                assert(height(G) == 9 && ...
                    isequal(sort(asDouble(G.degradation_pct))', [0 style.lossLevels]), ...
                    'A primary-curve series is incomplete or duplicated.');
            end
        end
    end

    communication = inputs.communicationTradeoff( ...
        ismember(string(inputs.communicationTradeoff.scenario), missionKeys), :);
    assert(height(communication) == 288, ...
        'Communication source must contain 2 missions x 24 conditions x 6 algorithms.');
    for mi = 1:2
        for ai = 1:6
            G = communication(string(communication.scenario) == missionKeys(mi) & ...
                string(communication.algorithm) == style.algorithmKeys(ai), :);
            assert(height(G) == 24 && all(asDouble(G.degradation_pct) > 0), ...
                'A communication-summary cohort is incomplete or includes ideal rows.');
        end
    end

    [primaryMeanDifference, primaryEligibleMismatch] = ...
        reconcileFigureMetric(maximumAgent(string(maximumAgent.comm_model) ~= "ideal", :), ...
        inputs.metricResults, "max_agent_steps", "mean", "eligible_n", style);
    [communicationMaxDifference, communicationMaxEligibleMismatch] = ...
        reconcileFigureMetric(communication, inputs.metricResults, ...
        "max_agent_steps", "mean_max_steps", "eligible_n_max_steps", style);
    [communicationRateDifference, communicationRateEligibleMismatch] = ...
        reconcileFigureMetric(communication, inputs.metricResults, ...
        "team_messages_per_step", "mean_message_rate", ...
        "eligible_n_message_rate", style);

    gridAudit = inputs.gridDensity(string(inputs.gridDensity.table_type) == "input_audit", :);
    assert(height(gridAudit) >= 2, 'Grid-density input audit rows are absent.');
    gridAuditFailures = sum(~asLogical(gridAudit.audit_passed));
    prdsRows = inputs.prds(string(inputs.prds.metric) == "max_agent_steps" & ...
        ismember(string(inputs.prds.scenario), missionKeys), :);
    assert(height(prdsRows) == 36, ...
        'Maximum-agent PRDS source must contain 2 missions x 3 models x 6 algorithms.');
    for mi = 1:2
        for ai = 1:6
            G = prdsRows(string(prdsRows.scenario) == missionKeys(mi) & ...
                string(prdsRows.algorithm) == style.algorithmKeys(ai), :);
            assert(height(G) == 3 && ...
                isequal(sort(string(G.comm_model)), sort(style.communicationKeys(:))), ...
                'A mission-algorithm PRDS series is incomplete or duplicated.');
        end
    end
    [prdsMeanDifference, prdsEligibleMismatch] = ...
        reconcilePrdsSource(prdsRows, inputs.prdsFigureReference, style);

    horizonMissionNames = ["Clue-Informed Probabilistic Search (CLIPS)", ...
        "Collaborative Visit (CV)"];
    horizonRows = inputs.horizon( ...
        ismember(string(inputs.horizon.scenario), horizonMissionNames), :);
    assert(height(horizonRows) == 120, ...
        'Paired horizon sensitivity source must contain 120 CLIPS/CV rows.');
    assert(isequal(sort(unique(asDouble(horizonRows.horizon)))', [1 2 3 5 8 12]), ...
        'Active horizon source does not contain the six expected horizon levels.');
    horizonDecisions = [inputs.horizonDecisionClips; inputs.horizonDecisionCv];
    horizonDecisionChosen = sum(asLogical(horizonDecisions.chosen));
    assert(height(horizonDecisions) == 60 && horizonDecisionChosen == 10, ...
        'Robust horizon decisions must contain 60 candidates and 10 selections.');
    assert(isequal(sort(unique(asDouble(horizonDecisions.candidate)))', ...
        [1 2 3 5 8 12]), ...
        'Robust horizon decisions do not contain the six expected levels.');
    reconstructedRobustScore = ...
        asDouble(horizonDecisions.average_improvement_pct) - ...
        asDouble(horizonDecisions.robust_disagreement_weight) .* ...
            asDouble(horizonDecisions.comm_disagreement_penalty) - ...
        asDouble(horizonDecisions.robust_bad_comm_weight) .* ...
            asDouble(horizonDecisions.bad_comm_penalty) - ...
        asDouble(horizonDecisions.robust_steepness_weight) .* ...
            asDouble(horizonDecisions.local_steepness);
    horizonScoreFormulaError = max(abs( ...
        asDouble(horizonDecisions.robust_score) - reconstructedRobustScore));

    trajectoryRows = inputs.trajectorySampleSizes( ...
        string(inputs.trajectorySampleSizes.method) == "PRDS common-six complete" & ...
        string(inputs.trajectorySampleSizes.metric) == "max_agent_steps" & ...
        ismember(string(inputs.trajectorySampleSizes.scenario), missionKeys), :);
    assert(height(trajectoryRows) == 36, ...
        'PRDS trajectory sample-size table must contain 2 x 3 x 6 active rows.');
    trajectoryEligibleMismatch = 0;
    for i = 1:height(trajectoryRows)
        match = string(prdsRows.scenario) == string(trajectoryRows.scenario(i)) & ...
            string(prdsRows.comm_model) == string(trajectoryRows.comm_model(i)) & ...
            string(prdsRows.algorithm) == string(trajectoryRows.algorithm_a(i));
        assert(sum(match) == 1, ...
            'PRDS trajectory sample-size key is absent or duplicated.');
        trajectoryEligibleMismatch = trajectoryEligibleMismatch + ...
            (asDouble(trajectoryRows.eligible_n(i)) ~= ...
            asDouble(prdsRows.eligible_n(match)));
    end
    assert(height(inputs.prdsRawClips) == 75000 && ...
        height(inputs.prdsRawCv) == 75000, ...
        'Combined CLIPS/CV PRDS source tables have unexpected row counts.');

    checkNames = strings(0, 1); observed = []; expected = []; tolerance = [];
    [checkNames, observed, expected, tolerance] = appendCheck( ...
        checkNames, observed, expected, tolerance, ...
        "Primary max-step source: maximum absolute mean difference vs master table", ...
        primaryMeanDifference, 0, 1e-10);
    [checkNames, observed, expected, tolerance] = appendCheck( ...
        checkNames, observed, expected, tolerance, ...
        "Primary max-step source: eligible-count mismatches vs master table", ...
        primaryEligibleMismatch, 0, 0);
    [checkNames, observed, expected, tolerance] = appendCheck( ...
        checkNames, observed, expected, tolerance, ...
        "Communication source max steps: maximum absolute difference vs master table", ...
        communicationMaxDifference, 0, 1e-10);
    [checkNames, observed, expected, tolerance] = appendCheck( ...
        checkNames, observed, expected, tolerance, ...
        "Communication source max steps: eligible-count mismatches vs master table", ...
        communicationMaxEligibleMismatch, 0, 0);
    [checkNames, observed, expected, tolerance] = appendCheck( ...
        checkNames, observed, expected, tolerance, ...
        "Communication source message rate: maximum absolute difference vs master table", ...
        communicationRateDifference, 0, 1e-10);
    [checkNames, observed, expected, tolerance] = appendCheck( ...
        checkNames, observed, expected, tolerance, ...
        "Communication source message rate: eligible-count mismatches vs master table", ...
        communicationRateEligibleMismatch, 0, 0);
    [checkNames, observed, expected, tolerance] = appendCheck( ...
        checkNames, observed, expected, tolerance, ...
        "Grid-density input-audit failures", gridAuditFailures, 0, 0);
    [checkNames, observed, expected, tolerance] = appendCheck( ...
        checkNames, observed, expected, tolerance, ...
        "CLIPS/CV maximum-step PRDS: maximum mean/CI difference vs common-six reference", ...
        prdsMeanDifference, 0, 1e-10);
    [checkNames, observed, expected, tolerance] = appendCheck( ...
        checkNames, observed, expected, tolerance, ...
        "CLIPS/CV maximum-step PRDS: eligible-count mismatches vs common-six reference", ...
        prdsEligibleMismatch, 0, 0);
    [checkNames, observed, expected, tolerance] = appendCheck( ...
        checkNames, observed, expected, tolerance, ...
        "CLIPS/CV horizon source rows", height(horizonRows), 120, 0);
    [checkNames, observed, expected, tolerance] = appendCheck( ...
        checkNames, observed, expected, tolerance, ...
        "CLIPS/CV robust-score decision rows", height(horizonDecisions), 60, 0);
    [checkNames, observed, expected, tolerance] = appendCheck( ...
        checkNames, observed, expected, tolerance, ...
        "CLIPS/CV robust-score selected horizons", horizonDecisionChosen, 10, 0);
    [checkNames, observed, expected, tolerance] = appendCheck( ...
        checkNames, observed, expected, tolerance, ...
        "CLIPS/CV robust-score formula reconstruction error", ...
        horizonScoreFormulaError, 0, 2e-8);
    [checkNames, observed, expected, tolerance] = appendCheck( ...
        checkNames, observed, expected, tolerance, ...
        "PRDS trajectory eligible-count mismatches vs PRDS summary", ...
        trajectoryEligibleMismatch, 0, 0);

    assert(all(abs(observed - expected) <= tolerance), ...
        'An active-table source reconciliation failed.');
    checks = table(checkNames, observed, expected, tolerance, ...
        abs(observed - expected), abs(observed - expected) <= tolerance, ...
        'VariableNames', {'check','observed','expected','tolerance', ...
        'absolute_error','passed'});
end

function [maxDifference, eligibleMismatch] = reconcileFigureMetric( ...
        figureSource, metricResults, metric, meanColumn, eligibleColumn, style)
    master = metricResults(string(metricResults.result_type) == "condition_metric" & ...
        string(metricResults.metric) == metric & ...
        string(metricResults.comm_model) ~= "ideal" & ...
        ismember(string(metricResults.scenario), style.missionNames(1:2)), :);
    assert(height(figureSource) == 288 && height(master) == 288, ...
        'Expected 288 impaired CLIPS/CV rows in both reconciled sources.');
    differences = nan(height(figureSource), 1);
    eligibleMismatch = 0;
    for i = 1:height(figureSource)
        missionIndex = find(style.missionKeys(1:2) == ...
            string(figureSource.scenario(i)), 1);
        assert(~isempty(missionIndex), 'Unknown mission in figure source.');
        match = string(master.scenario) == style.missionNames(missionIndex) & ...
            string(master.comm_model) == string(figureSource.comm_model(i)) & ...
            asDouble(master.comm_level_pct) == ...
                asDouble(figureSource.degradation_pct(i)) & ...
            string(master.algorithm) == string(figureSource.algorithm(i));
        assert(sum(match) == 1, 'Figure-to-master reconciliation key is not unique.');
        differences(i) = abs(asDouble(figureSource.(meanColumn)(i)) - ...
            asDouble(master.mean_value(match)));
        eligibleMismatch = eligibleMismatch + ...
            (asDouble(figureSource.(eligibleColumn)(i)) ~= ...
            asDouble(master.eligible_paired_trials(match)));
    end
    maxDifference = max(differences);
end

function [maxDifference, eligibleMismatch] = reconcilePrdsSource( ...
        prdsSource, figureReference, style)
    reference = figureReference(string(figureReference.metric) == "max_agent_steps" & ...
        ismember(string(figureReference.scenario), style.missionKeys(1:2)), :);
    assert(height(prdsSource) == 36 && height(reference) == 36, ...
        'Expected 36 common-six maximum-agent PRDS rows in both sources.');
    differences = nan(height(prdsSource), 1);
    eligibleMismatch = 0;
    for i = 1:height(prdsSource)
        match = string(reference.scenario) == string(prdsSource.scenario(i)) & ...
            string(reference.comm_model) == string(prdsSource.comm_model(i)) & ...
            string(reference.algorithm) == string(prdsSource.algorithm(i));
        assert(sum(match) == 1, 'PRDS figure-source reconciliation key is not unique.');
        differences(i) = max(abs([ ...
            asDouble(prdsSource.mean(i)) - asDouble(reference.mean(match)), ...
            asDouble(prdsSource.ci95_low(i)) - asDouble(reference.ci95_low(match)), ...
            asDouble(prdsSource.ci95_high(i)) - asDouble(reference.ci95_high(match))]));
        eligibleMismatch = eligibleMismatch + ...
            (asDouble(prdsSource.eligible_n(i)) ~= ...
            asDouble(reference.eligible_n(match)));
    end
    maxDifference = max(differences);
end

function [names, obs, exp, tol] = appendCheck(names, obs, exp, tol, ...
        name, observed, expected, tolerance)
    names(end + 1, 1) = name;
    obs(end + 1, 1) = observed;
    exp(end + 1, 1) = expected;
    tol(end + 1, 1) = tolerance;
end

function manifest = archiveSupersededOutputs(activeDir, inspectionDir, ...
        sourceDir, archiveRoot)
    rows = {};
    figureArchive = fullfile(archiveRoot, 'figures');
    inspectionArchive = fullfile(archiveRoot, 'inspection');
    alternateArchive = fullfile(archiveRoot, 'alternates');
    sourceArchive = fullfile(archiveRoot, 'sources');
    ensureDir(figureArchive); ensureDir(inspectionArchive);
    ensureDir(alternateArchive); ensureDir(sourceArchive);

    patterns = {'*.pdf', '*.png', '*.fig'};
    files = [];
    for i = 1:numel(patterns)
        files = [files; dir(fullfile(activeDir, patterns{i}))]; %#ok<AGROW>
    end
    for i = 1:numel(files)
        source = fullfile(files(i).folder, files(i).name);
        % Archive every existing top-level figure before regeneration,
        % including same-stem PNGs that would otherwise be overwritten.
        rows{end + 1} = archiveOne(source, figureArchive, "active_figure"); %#ok<AGROW>
    end

    files = [dir(fullfile(inspectionDir, '*.png')); ...
        dir(fullfile(inspectionDir, '*.fig')); ...
        dir(fullfile(inspectionDir, '*.pdf'))];
    for i = 1:numel(files)
        source = fullfile(files(i).folder, files(i).name);
        rows{end + 1} = archiveOne(source, inspectionArchive, ...
            "inspection_output"); %#ok<AGROW>
    end

    alternateDir = fullfile(activeDir, 'alternates');
    if isfolder(alternateDir)
        files = [dir(fullfile(alternateDir, '*.png')); ...
            dir(fullfile(alternateDir, '*.fig')); ...
            dir(fullfile(alternateDir, '*.pdf'))];
        for i = 1:numel(files)
            source = fullfile(files(i).folder, files(i).name);
            rows{end + 1} = archiveOne(source, alternateArchive, ...
                "alternate_output"); %#ok<AGROW>
        end
    end

    files = dir(fullfile(sourceDir, 'source_*.csv'));
    for i = 1:numel(files)
        source = fullfile(files(i).folder, files(i).name);
        rows{end + 1} = archiveOne(source, sourceArchive, ...
            "dedicated_source"); %#ok<AGROW>
    end

    if isempty(rows)
        manifest = table('Size', [0 6], ...
            'VariableTypes', {'string','string','string','double','string','string'}, ...
            'VariableNames', {'category','original_path','archived_path', ...
            'bytes','sha256','archived_at'});
    else
        manifest = vertcat(rows{:});
    end
end

function row = archiveOne(source, destinationDir, category)
    destination = uniqueArchivePath(fullfile(destinationDir, ...
        getFileName(source)));
    beforeHash = string(sha256File(source));
    [ok, message] = movefile(source, destination);
    if ~ok, error('Could not archive %s: %s', source, message); end
    afterHash = string(sha256File(destination));
    assert(beforeHash == afterHash, 'Archived-file SHA-256 mismatch.');
    info = dir(destination);
    row = table(category, string(source), string(destination), info.bytes, ...
        afterHash, string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss Z')), ...
        'VariableNames', {'category','original_path','archived_path', ...
        'bytes','sha256','archived_at'});
end

function name = getFileName(path)
    [~, stem, extension] = fileparts(char(path));
    name = [stem extension];
end

function path = uniqueArchivePath(path)
    if ~isfile(path), return; end
    [folder, stem, extension] = fileparts(path);
    index = 2;
    while isfile(fullfile(folder, sprintf('%s_%02d%s', stem, index, extension)))
        index = index + 1;
    end
    path = fullfile(folder, sprintf('%s_%02d%s', stem, index, extension));
end

function S = preparePrimaryMissionSource(maximumAgent, metricResults, style)
    % The legacy figure table contains the desired labels and panel layout,
    % but its confidence limits were Student-t intervals.  Figure 1 is
    % required to use the seeded 10,000-resample paired bootstrap intervals
    % already computed in dcta_metric_results.csv.
    master = metricResults( ...
        string(metricResults.result_type) == "condition_metric" & ...
        string(metricResults.metric) == "max_agent_steps" & ...
        ismember(string(metricResults.scenario), style.missionNames(1:2)), :);
    maximumAgent = maximumAgent( ...
        ismember(string(maximumAgent.scenario), style.missionKeys(1:2)), :);
    for i = 1:height(maximumAgent)
        missionIndex = find(style.missionKeys(1:2) == ...
            string(maximumAgent.scenario(i)), 1);
        assert(~isempty(missionIndex), 'Unknown mission in primary source.');
        match = string(master.scenario) == style.missionNames(missionIndex) & ...
            string(master.comm_model) == string(maximumAgent.comm_model(i)) & ...
            asDouble(master.comm_level_pct) == ...
                asDouble(maximumAgent.degradation_pct(i)) & ...
            string(master.algorithm) == string(maximumAgent.algorithm(i));
        assert(sum(match) == 1, ...
            'Bootstrap primary-source key is absent or duplicated.');
        maximumAgent.ci95_low(i) = master.ci95_low(match);
        maximumAgent.ci95_high(i) = master.ci95_high(match);
        maximumAgent.ci_method(i) = ...
            "paired nonparametric bootstrap percentile interval; 10,000 resamples; RNG seed 20260714";
    end
    C = maximumAgent(string(maximumAgent.scenario) == "CLIPS", :);
    C.metric_display = repmat("Maximum-agent steps", height(C), 1);
    C.mission_row = ones(height(C), 1);

    V = maximumAgent(string(maximumAgent.scenario) == "CV", :);
    V.metric_display = repmat("Maximum-agent steps", height(V), 1);
    V.mission_row = 2 * ones(height(V), 1);

    vars = {'mission','scenario','comm_model','comm_label','degradation_pct', ...
        'metric','metric_display','algorithm','attempted_trial_n','six_way_paired_n', ...
        'eligible_n','mean','median','sd','ci95_low','ci95_high','source_column', ...
        'scope','ci_method','panel_model','mission_row'};
    S = [C(:, vars); V(:, vars)];
    S.figure_stem = repmat("primary_mission_performance_curves", height(S), 1);
end

function S = prepareCvWorkloadSource(T)
    S = T;
    S.figure_stem = repmat("cv_workload_tradeoff", height(S), 1);
    S.aggregation_rule = repmat( ...
        "unweighted mean of the 24 impaired condition means", height(S), 1);
end

function S = prepareCommunicationSummary(T, style, missionKeys, missionNames)
    rows = cell(12, 1); ri = 0;
    for mi = 1:2
        for ai = 1:6
            G = T(string(T.scenario) == missionKeys(mi) & ...
                string(T.algorithm) == style.algorithmKeys(ai), :);
            assert(height(G) == 24, ...
                'Communication summary requires 24 impaired condition means.');
            ri = ri + 1;
            rows{ri} = table(missionNames(mi), missionKeys(mi), ...
                style.algorithmKeys(ai), mean(asDouble(G.mean_message_rate)), ...
                mean(asDouble(G.mean_max_steps)), height(G), ...
                sum(asDouble(G.eligible_n_max_steps)), ...
                min(asDouble(G.eligible_n_max_steps)), ...
                max(asDouble(G.eligible_n_max_steps)), ...
                "unweighted mean of 24 condition means (3 communication models x 8 impaired levels)", ...
                'VariableNames', {'mission','scenario','algorithm', ...
                'mean_message_publications_per_team_step','mean_maximum_agent_steps', ...
                'source_condition_count','sum_condition_eligible_n', ...
                'min_condition_eligible_n','max_condition_eligible_n', ...
                'aggregation_rule'});
        end
    end
    S = vertcat(rows{:});
    S.figure_stem = repmat("communication_performance_tradeoff", height(S), 1);
end

function S = prepareHorizonRobustSource(clipsDecision, cvDecision, missionNames)
    clipsDecision.scenario = repmat(missionNames(1), height(clipsDecision), 1);
    cvDecision.scenario = repmat(missionNames(2), height(cvDecision), 1);
    S = [clipsDecision; cvDecision];
    S.algorithm = upper(string(S.algorithm_key));
    S.horizon = asDouble(S.candidate);
    S.selected_for_main_benchmark = asLogical(S.chosen);
    algorithms = ["ACBBA", "PI", "HIPC", "DMCHBA", "DGA"];
    expectedHorizons = [1 2 3 5 8 12];
    assert(height(S) == 60, ...
        'Robust horizon source must contain 2 missions x 5 algorithms x 6 horizons.');
    for mi = 1:2
        for ai = 1:5
            G = S(string(S.scenario) == missionNames(mi) & ...
                string(S.algorithm) == algorithms(ai), :);
            assert(height(G) == 6 && ...
                isequal(sort(asDouble(G.horizon))', expectedHorizons), ...
                'A robust-score mission-algorithm series is incomplete.');
            assert(sum(asLogical(G.selected_for_main_benchmark)) == 1, ...
                'Each robust-score series must contain exactly one selected point.');
        end
    end
    S.score_formula = repmat( ...
        "R = average_improvement_pct - 0.5*comm_disagreement_penalty - 0.5*bad_comm_penalty - 0.1*local_steepness", ...
        height(S), 1);
    S.score_direction = repmat("higher is better", height(S), 1);
end

function S = prepareDgaIterationSource(T)
    S = T;
    sem = asDouble(S.sem_delta_from_trial_baseline);
    n = asDouble(S.n_trials);
    critical = tinv(0.975, n - 1);
    delta = asDouble(S.mean_delta_from_trial_baseline);
    S.ci95_low = delta - critical .* sem;
    S.ci95_high = delta + critical .* sem;
    S.selected_k = repmat(25, height(S), 1);
    S.selected_for_main_benchmark = asDouble(S.dga_iterations) == 25;
    S.figure_stem = repmat("DGA_iteration", height(S), 1);
    S.baseline_rule = repmat( ...
        "paired deviation from each trial's mean over all tested DGA iteration levels and both communication settings", ...
        height(S), 1);
end

function S = prepareGridDensitySource(T, style, missionKeys, missionNames)
    M = T(string(T.table_type) == "metric_summary" & ...
        string(T.metric_key) == "normalized_primary" & ...
        ismember(string(T.mission_short), missionKeys), :);
    gridSource = T(string(T.table_type) == "figure_grid_size_source" & ...
        ismember(string(T.mission_short), missionKeys), :);
    densitySource = T(string(T.table_type) == "figure_robot_density_source" & ...
        ismember(string(T.mission_short), missionKeys), :);

    rows = cell(96, 1); ri = 0;
    factorTypes = ["grid_size", "target_cells_per_robot"];
    factorLevels = {[14 19 25 34], [50 85 140 220]};
    plottedSources = {gridSource, densitySource};
    comms = ["ideal", "bernoulli_025"];

    for fi = 1:2
        P = plottedSources{fi};
        factor = factorTypes(fi);
        levels = factorLevels{fi};
        for mi = 1:2
            for ai = 1:6
                for li = 1:numel(levels)
                    componentMean = nan(2, 1);
                    componentCiLow = nan(2, 1);
                    componentCiHigh = nan(2, 1);
                    attempted = nan(2, 1);
                    completed = nan(2, 1);
                    eligible = nan(2, 1);
                    failed = nan(2, 1);
                    metricLabels = strings(2, 1);
                    unitLabels = strings(2, 1);
                    for ci = 1:2
                        matchP = string(P.mission_short) == missionKeys(mi) & ...
                            string(P.comm_label) == comms(ci) & ...
                            string(P.algorithm_key) == style.algorithmKeysLower(ai) & ...
                            asDouble(P.(factor)) == levels(li);
                        Gp = P(matchP, :);
                        assert(height(Gp) == 1, ...
                            'Grid-density plotted aggregation is not unique.');

                        matchM = string(M.mission_short) == missionKeys(mi) & ...
                            string(M.comm_label) == comms(ci) & ...
                            string(M.algorithm_key) == style.algorithmKeysLower(ai) & ...
                            asDouble(M.(factor)) == levels(li);
                        Gm = M(matchM, :);
                        assert(height(Gm) == 4, ...
                            'Each grid-density marginal must aggregate four opposite-factor conditions.');
                        componentMean(ci) = asDouble(Gp.mean_normalized_primary);
                        componentCiLow(ci) = asDouble(Gp.ci95_low);
                        componentCiHigh(ci) = asDouble(Gp.ci95_high);
                        attempted(ci) = sum(asDouble(Gm.attempted_n));
                        completed(ci) = sum(asDouble(Gm.completed_n));
                        eligible(ci) = sum(asDouble(Gm.eligible_n));
                        failed(ci) = sum(asDouble(Gm.failed_n));
                        metricLabels(ci) = string(Gp.metric_label);
                        unitLabels(ci) = string(Gp.units);
                    end
                    assert(numel(unique(metricLabels)) == 1 && ...
                        numel(unique(unitLabels)) == 1, ...
                        'Ideal and degraded grid-density components use inconsistent metrics.');

                    ri = ri + 1;
                    if factor == "grid_size"
                        gridSize = levels(li); density = nan;
                        marginalRule = ...
                            "four nominal-density condition means per communication setting";
                    else
                        gridSize = nan; density = levels(li);
                        marginalRule = ...
                            "four independent grid-level condition means per communication setting";
                    end
                    aggregation = "equal-weight mean of the ideal and Bernoulli 0.25 marginal means; " + marginalRule;

                    rows{ri} = table(missionNames(mi), missionKeys(mi), ...
                        factor, levels(li), gridSize, density, ...
                        "ideal_degraded_average", style.algorithmKeys(ai), ...
                        metricLabels(1), unitLabels(1), mean(componentMean), ...
                        componentMean(1), componentMean(2), ...
                        componentCiLow(1), componentCiHigh(1), ...
                        componentCiLow(2), componentCiHigh(2), ...
                        sum(attempted), sum(completed), sum(eligible), sum(failed), ...
                        8, aggregation, ...
                        'VariableNames', {'mission','scenario','factor','factor_value', ...
                        'grid_size','target_cells_per_robot','comm_label','algorithm', ...
                        'metric_label','units','plotted_mean','ideal_mean','degraded_mean', ...
                        'ideal_ci95_low','ideal_ci95_high', ...
                        'degraded_ci95_low','degraded_ci95_high', ...
                        'attempted_n','completed_n','eligible_n','failed_n', ...
                        'contributing_condition_means','aggregation_rule'});
                end
            end
        end
    end
    S = vertcat(rows{:});
    assert(height(S) == 96 && max(abs(asDouble(S.plotted_mean) - ...
        0.5 * (asDouble(S.ideal_mean) + asDouble(S.degraded_mean)))) < 1e-12, ...
        'Grid-density communication averaging failed validation.');
    S.figure_stem = repmat("grid_density_sensitivity_summary", height(S), 1);
    S.continuous_metric_scope = repmat( ...
        "completed eligible trials only; scheduler-event-cap rows excluded and retained in failed_n", ...
        height(S), 1);
end

function S = prepareGridDensityMaxStepsSource(T, style, missionKeys, missionNames)
    M = T(string(T.table_type) == "metric_summary" & ...
        string(T.metric_key) == "max_agent_steps" & ...
        ismember(string(T.mission_short), missionKeys) & ...
        ismember(string(T.comm_label), ["ideal", "bernoulli_025"]), :);
    assert(height(M) == 384, ...
        'Maximum-agent grid-density source must contain 384 CLIPS/CV condition rows.');

    rows = cell(96, 1); ri = 0;
    factorTypes = ["grid_size", "target_cells_per_robot"];
    factorLevels = {[14 19 25 34], [50 85 140 220]};
    comms = ["ideal", "bernoulli_025"];

    for fi = 1:2
        factor = factorTypes(fi);
        levels = factorLevels{fi};
        for mi = 1:2
            for ai = 1:6
                for li = 1:numel(levels)
                    componentMean = nan(2, 1);
                    componentCiLow = nan(2, 1);
                    componentCiHigh = nan(2, 1);
                    attempted = nan(2, 1);
                    completed = nan(2, 1);
                    eligible = nan(2, 1);
                    failed = nan(2, 1);
                    allConditionMeans = nan(8, 1);
                    for ci = 1:2
                        match = string(M.mission_short) == missionKeys(mi) & ...
                            string(M.comm_label) == comms(ci) & ...
                            string(M.algorithm_key) == style.algorithmKeysLower(ai) & ...
                            asDouble(M.(factor)) == levels(li);
                        G = M(match, :);
                        assert(height(G) == 4, ...
                            'Each maximum-step marginal must contain four opposite-factor conditions.');
                        conditionMeans = asDouble(G.mean);
                        componentMean(ci) = mean(conditionMeans);
                        componentSem = std(conditionMeans) / sqrt(numel(conditionMeans));
                        componentHalfWidth = tinv(0.975, numel(conditionMeans) - 1) * componentSem;
                        componentCiLow(ci) = componentMean(ci) - componentHalfWidth;
                        componentCiHigh(ci) = componentMean(ci) + componentHalfWidth;
                        allConditionMeans((ci - 1) * 4 + (1:4)) = conditionMeans;
                        attempted(ci) = sum(asDouble(G.attempted_n));
                        completed(ci) = sum(asDouble(G.completed_n));
                        eligible(ci) = sum(asDouble(G.eligible_n));
                        failed(ci) = sum(asDouble(G.failed_n));
                    end

                    plottedMean = mean(componentMean);
                    plottedSem = std(allConditionMeans) / sqrt(numel(allConditionMeans));
                    plottedHalfWidth = tinv(0.975, numel(allConditionMeans) - 1) * plottedSem;
                    ri = ri + 1;
                    if factor == "grid_size"
                        gridSize = levels(li); density = nan;
                        marginalRule = ...
                            "four nominal-density condition means per communication setting";
                    else
                        gridSize = nan; density = levels(li);
                        marginalRule = ...
                            "four independent grid-level condition means per communication setting";
                    end
                    aggregation = ...
                        "equal-weight mean of ideal and Bernoulli 0.25 marginals; " + marginalRule;
                    rows{ri} = table(missionNames(mi), missionKeys(mi), ...
                        factor, levels(li), gridSize, density, ...
                        "ideal_degraded_average", style.algorithmKeys(ai), ...
                        "Maximum-agent steps", "steps", plottedMean, ...
                        plottedMean - plottedHalfWidth, plottedMean + plottedHalfWidth, ...
                        componentMean(1), componentMean(2), ...
                        componentCiLow(1), componentCiHigh(1), ...
                        componentCiLow(2), componentCiHigh(2), ...
                        sum(attempted), sum(completed), sum(eligible), sum(failed), ...
                        8, aggregation, ...
                        'VariableNames', {'mission','scenario','factor','factor_value', ...
                        'grid_size','target_cells_per_robot','comm_label','algorithm', ...
                        'metric_label','units','plotted_mean','plotted_ci95_low', ...
                        'plotted_ci95_high','ideal_mean','degraded_mean', ...
                        'ideal_ci95_low','ideal_ci95_high', ...
                        'degraded_ci95_low','degraded_ci95_high', ...
                        'attempted_n','completed_n','eligible_n','failed_n', ...
                        'contributing_condition_means','aggregation_rule'});
                end
            end
        end
    end
    S = vertcat(rows{:});
    assert(height(S) == 96 && max(abs(asDouble(S.plotted_mean) - ...
        0.5 * (asDouble(S.ideal_mean) + asDouble(S.degraded_mean)))) < 1e-12, ...
        'Maximum-agent grid-density communication averaging failed validation.');
    S.figure_stem = repmat( ...
        "grid_density_maximum_agent_steps_summary", height(S), 1);
    S.continuous_metric_scope = repmat( ...
        "completed eligible trials only; scheduler-event-cap rows excluded and retained in failed_n", ...
        height(S), 1);
end

function S = prepareCompleteBlockGridDensityMaxStepsSource(T, style, ...
        missionKeys, missionNames)
    required = ["mission", "scenario", "factor", "factor_value", ...
        "grid_size", "target_cells_per_robot", "comm_label", "algorithm", ...
        "metric_label", "units", "plotted_mean", "plotted_ci95_low", ...
        "plotted_ci95_high", "ideal_mean", "degraded_mean", "ideal_ci95_low", ...
        "ideal_ci95_high", "degraded_ci95_low", "degraded_ci95_high", ...
        "attempted_n", "completed_n", "eligible_n", "failed_n", ...
        "ideal_eligible_n", "degraded_eligible_n", ...
        "contributing_condition_means", "aggregation_rule", "figure_stem", ...
        "continuous_metric_scope"];
    missing = setdiff(required, string(T.Properties.VariableNames));
    assert(isempty(missing), ...
        'Complete-block Figure 4 source is missing: %s', strjoin(cellstr(missing), ', '));

    S = T(ismember(string(T.scenario), missionKeys), :);
    assert(height(S) == 96, ...
        'Figure 4 requires 96 CLIPS/CV complete-block plotted rows.');
    assert(all(ismember(string(S.algorithm), style.algorithmKeys)) && ...
        all(ismember(string(S.factor), ["grid_size", "target_cells_per_robot"])) && ...
        all(isfinite(asDouble(S.plotted_mean))) && ...
        all(asDouble(S.contributing_condition_means) == 8), ...
        'Complete-block Figure 4 source has invalid plotted values.');
    assert(all(contains(string(S.aggregation_rule), "pooled mean across all retained complete-block trials")) && ...
        all(contains(string(S.continuous_metric_scope), "all six algorithms completed")), ...
        'Figure 4 source does not document the common-block estimand.');
    assert(all(ismember(string(S.mission), missionNames)), ...
        'Figure 4 source mission labels are inconsistent.');
end

function S = prepareGridDensityNormalizedMaxStepsSource(T, style, ...
        missionKeys, missionNames)
    M = T(string(T.table_type) == "metric_summary" & ...
        string(T.metric_key) == "max_agent_steps" & ...
        ismember(string(T.mission_short), missionKeys) & ...
        ismember(string(T.comm_label), ["ideal", "bernoulli_025"]), :);
    assert(height(M) == 384, ...
        'Normalized maximum-agent source must contain 384 CLIPS/CV rows.');

    % Recover and verify the established CV denominator from the existing
    % primary and normalized-primary analysis rows rather than hard-coding an
    % unverified target count. Every CV condition uses exactly ten targets.
    primaryCv = T(string(T.table_type) == "metric_summary" & ...
        string(T.metric_key) == "primary_metric" & ...
        string(T.mission_short) == "CV", :);
    normalizedCv = T(string(T.table_type) == "metric_summary" & ...
        string(T.metric_key) == "normalized_primary" & ...
        string(T.mission_short) == "CV", :);
    denominatorChecks = nan(height(primaryCv), 1);
    for i = 1:height(primaryCv)
        match = asDouble(normalizedCv.grid_size) == asDouble(primaryCv.grid_size(i)) & ...
            asDouble(normalizedCv.target_cells_per_robot) == ...
                asDouble(primaryCv.target_cells_per_robot(i)) & ...
            string(normalizedCv.comm_label) == string(primaryCv.comm_label(i)) & ...
            string(normalizedCv.algorithm_key) == string(primaryCv.algorithm_key(i));
        assert(sum(match) == 1, ...
            'A CV normalization-denominator audit key is absent or duplicated.');
        denominatorChecks(i) = asDouble(primaryCv.mean(i)) / ...
            asDouble(normalizedCv.mean(match));
    end
    assert(max(abs(denominatorChecks - 10)) < 1e-10, ...
        'CV normalized-primary rows do not verify the ten-target denominator.');

    rows = cell(96, 1); ri = 0;
    factorTypes = ["grid_size", "target_cells_per_robot"];
    factorLevels = {[14 19 25 34], [50 85 140 220]};
    comms = ["ideal", "bernoulli_025"];

    for fi = 1:2
        factor = factorTypes(fi);
        levels = factorLevels{fi};
        for mi = 1:2
            if missionKeys(mi) == "CLIPS"
                metricLabel = "Maximum-agent steps per grid cell";
                unitLabel = "steps/cell";
                normalizationRule = "maximum-agent steps divided by grid_cells for each condition";
            else
                metricLabel = "Maximum-agent steps per target";
                unitLabel = "steps/target";
                normalizationRule = "maximum-agent steps divided by the verified constant target_count of 10";
            end
            for ai = 1:6
                for li = 1:numel(levels)
                    componentMean = nan(2, 1);
                    componentCiLow = nan(2, 1);
                    componentCiHigh = nan(2, 1);
                    attempted = nan(2, 1);
                    completed = nan(2, 1);
                    eligible = nan(2, 1);
                    failed = nan(2, 1);
                    allConditionMeans = nan(8, 1);
                    allDenominators = nan(8, 1);
                    for ci = 1:2
                        match = string(M.mission_short) == missionKeys(mi) & ...
                            string(M.comm_label) == comms(ci) & ...
                            string(M.algorithm_key) == style.algorithmKeysLower(ai) & ...
                            asDouble(M.(factor)) == levels(li);
                        G = M(match, :);
                        assert(height(G) == 4, ...
                            'Each normalized maximum-step marginal must contain four opposite-factor conditions.');
                        if missionKeys(mi) == "CLIPS"
                            denominators = asDouble(G.grid_cells);
                        else
                            denominators = 10 * ones(height(G), 1);
                        end
                        conditionMeans = asDouble(G.mean) ./ denominators;
                        componentMean(ci) = mean(conditionMeans);
                        componentSem = std(conditionMeans) / sqrt(numel(conditionMeans));
                        componentHalfWidth = tinv(0.975, numel(conditionMeans) - 1) * componentSem;
                        componentCiLow(ci) = componentMean(ci) - componentHalfWidth;
                        componentCiHigh(ci) = componentMean(ci) + componentHalfWidth;
                        indices = (ci - 1) * 4 + (1:4);
                        allConditionMeans(indices) = conditionMeans;
                        allDenominators(indices) = denominators;
                        attempted(ci) = sum(asDouble(G.attempted_n));
                        completed(ci) = sum(asDouble(G.completed_n));
                        eligible(ci) = sum(asDouble(G.eligible_n));
                        failed(ci) = sum(asDouble(G.failed_n));
                    end

                    plottedMean = mean(componentMean);
                    plottedSem = std(allConditionMeans) / sqrt(numel(allConditionMeans));
                    plottedHalfWidth = tinv(0.975, numel(allConditionMeans) - 1) * plottedSem;
                    ri = ri + 1;
                    if factor == "grid_size"
                        gridSize = levels(li); density = nan;
                        marginalRule = ...
                            "four nominal-density condition means per communication setting";
                    else
                        gridSize = nan; density = levels(li);
                        marginalRule = ...
                            "four independent grid-level condition means per communication setting";
                    end
                    aggregation = ...
                        "equal-weight mean of ideal and Bernoulli 0.25 marginals; " + marginalRule;
                    rows{ri} = table(missionNames(mi), missionKeys(mi), ...
                        factor, levels(li), gridSize, density, ...
                        "ideal_degraded_average", style.algorithmKeys(ai), ...
                        metricLabel, unitLabel, plottedMean, ...
                        plottedMean - plottedHalfWidth, plottedMean + plottedHalfWidth, ...
                        componentMean(1), componentMean(2), ...
                        componentCiLow(1), componentCiHigh(1), ...
                        componentCiLow(2), componentCiHigh(2), ...
                        min(allDenominators), max(allDenominators), ...
                        sum(attempted), sum(completed), sum(eligible), sum(failed), ...
                        8, normalizationRule, aggregation, ...
                        'VariableNames', {'mission','scenario','factor','factor_value', ...
                        'grid_size','target_cells_per_robot','comm_label','algorithm', ...
                        'metric_label','units','plotted_mean','plotted_ci95_low', ...
                        'plotted_ci95_high','ideal_mean','degraded_mean', ...
                        'ideal_ci95_low','ideal_ci95_high', ...
                        'degraded_ci95_low','degraded_ci95_high', ...
                        'normalization_denominator_min','normalization_denominator_max', ...
                        'attempted_n','completed_n','eligible_n','failed_n', ...
                        'contributing_condition_means','normalization_rule','aggregation_rule'});
                end
            end
        end
    end
    S = vertcat(rows{:});
    assert(height(S) == 96 && max(abs(asDouble(S.plotted_mean) - ...
        0.5 * (asDouble(S.ideal_mean) + asDouble(S.degraded_mean)))) < 1e-12, ...
        'Normalized maximum-agent communication averaging failed validation.');
    S.figure_stem = repmat( ...
        "grid_density_normalized_maximum_agent_steps_summary", height(S), 1);
    S.continuous_metric_scope = repmat( ...
        "completed eligible trials only; scheduler-event-cap rows excluded and retained in failed_n", ...
        height(S), 1);
end

function S = preparePrdsDegradationCurveSource(inputs, style, ...
        missionKeys, missionNames)
    sampleSizes = inputs.trajectorySampleSizes( ...
        string(inputs.trajectorySampleSizes.method) == "PRDS common-six complete" & ...
        string(inputs.trajectorySampleSizes.metric) == "max_agent_steps" & ...
        ismember(string(inputs.trajectorySampleSizes.scenario), missionKeys), :);
    assert(height(sampleSizes) == 36, ...
        'Expected 36 common-six PRDS trajectory definitions.');

    rawTables = {inputs.prdsRawClips, inputs.prdsRawCv};
    metricVariables = ["max_steps_any_robot", "max_robot_steps"];
    sourceColumns = ["max_steps_any_robot", "max_robot_steps"];
    sourceFiles = ["clue_search_core_500_combined_system_performance.csv", ...
        "known_target_visit_core_500_combined_system_performance.csv"];
    levels = [0 style.lossLevels];
    rows = cell(324, 1); ri = 0;

    for mi = 1:2
        raw = rawTables{mi};
        metricVariable = metricVariables(mi);
        for ci = 1:3
            for ai = 1:6
                sizeRow = sampleSizes( ...
                    string(sampleSizes.scenario) == missionKeys(mi) & ...
                    string(sampleSizes.comm_model) == style.communicationKeys(ci) & ...
                    string(sampleSizes.algorithm_a) == style.algorithmKeys(ai), :);
                assert(height(sizeRow) == 1, ...
                    'A PRDS trajectory sample-size definition is absent or duplicated.');
                trialIds = parseTrialIdList(sizeRow.eligible_trial_ids);
                eligibleN = asDouble(sizeRow.eligible_n);
                assert(numel(trialIds) == eligibleN && numel(unique(trialIds)) == eligibleN, ...
                    'A PRDS eligible-trial list does not match its declared n.');
                sortedTrialIds = sort(trialIds(:));
                curve = nan(eligibleN, numel(levels));
                rawLabels = strings(1, numel(levels));
                means = nan(1, numel(levels));
                medians = nan(1, numel(levels));
                standardDeviations = nan(1, numel(levels));
                ciLow = nan(1, numel(levels));
                ciHigh = nan(1, numel(levels));

                for li = 1:numel(levels)
                    mapRows = inputs.maximumAgent( ...
                        string(inputs.maximumAgent.scenario) == missionKeys(mi) & ...
                        string(inputs.maximumAgent.panel_model) == style.communicationKeys(ci) & ...
                        asDouble(inputs.maximumAgent.degradation_pct) == levels(li), :);
                    rawLabel = unique(string(mapRows.comm_label));
                    assert(numel(rawLabel) == 1, ...
                        'A PRDS degradation level does not map to one raw communication label.');
                    rawLabels(li) = rawLabel;
                    match = string(raw.algorithm_key) == style.algorithmKeysLower(ai) & ...
                        string(raw.comm_label) == rawLabel & ...
                        ismember(asDouble(raw.trial_id), trialIds);
                    G = raw(match, :);
                    assert(height(G) == eligibleN && ...
                        numel(unique(asDouble(G.trial_id))) == eligibleN, ...
                        'A raw PRDS curve level does not contain exactly its eligible trial cohort.');
                    [rawTrialIds, order] = sort(asDouble(G.trial_id));
                    assert(isequal(rawTrialIds(:), sortedTrialIds), ...
                        'Raw PRDS curve trial IDs do not match the saved common-six cohort.');
                    y = asDouble(G.(metricVariable)); y = y(order);
                    assert(all(isfinite(y) & y > 0), ...
                        'A raw PRDS curve contains a nonpositive or nonfinite maximum-step value.');
                    curve(:, li) = y;
                    means(li) = mean(y);
                    medians(li) = median(y);
                    standardDeviations(li) = std(y, 0);
                    critical = tinv(0.975, eligibleN - 1);
                    halfWidth = critical * standardDeviations(li) / sqrt(eligibleN);
                    ciLow(li) = means(li) - halfWidth;
                    ciHigh(li) = means(li) + halfWidth;
                end

                centeredLevels = levels - mean(levels);
                logCurve = log(curve);
                beta = sum((logCurve - mean(logCurve, 2)) .* centeredLevels, 2) ./ ...
                    sum(centeredLevels .^ 2);
                trialPrds = 100 * (exp(beta) - 1);
                recomputedPrds = mean(trialPrds);
                referenceRow = inputs.prds( ...
                    string(inputs.prds.metric) == "max_agent_steps" & ...
                    string(inputs.prds.scenario) == missionKeys(mi) & ...
                    string(inputs.prds.comm_model) == style.communicationKeys(ci) & ...
                    string(inputs.prds.algorithm) == style.algorithmKeys(ai), :);
                assert(height(referenceRow) == 1 && ...
                    asDouble(referenceRow.eligible_n) == eligibleN, ...
                    'Recomputed PRDS curve does not match its summary-row cohort.');
                referencePrds = asDouble(referenceRow.mean);
                validationError = recomputedPrds - referencePrds;
                assert(abs(validationError) < 1e-10, ...
                    'Trial-level PRDS recomputation failed to match revised_prds.csv.');

                for li = 1:numel(levels)
                    ri = ri + 1;
                    rows{ri} = table(missionNames(mi), missionKeys(mi), ...
                        style.communicationKeys(ci), style.communicationLabels(ci), ...
                        rawLabels(li), levels(li), style.algorithmKeys(ai), ...
                        eligibleN, means(li), medians(li), standardDeviations(li), ...
                        ciLow(li), ciHigh(li), sourceColumns(mi), sourceFiles(mi), ...
                        recomputedPrds, referencePrds, validationError, ...
                        ai, ci, ...
                        "common-six complete: identical trial IDs for all six algorithms at ideal and all eight degradation levels", ...
                        "two-sided 95% Student-t interval for the level mean", ...
                        'VariableNames', {'mission','scenario','comm_model','comm_label', ...
                        'raw_comm_label','degradation_pct','algorithm','eligible_n', ...
                        'mean','median','sd','ci95_low','ci95_high','source_column', ...
                        'source_file','recomputed_mean_prds','reference_mean_prds', ...
                        'prds_validation_error','algorithm_order','communication_order', ...
                        'eligibility_rule','ci_method'});
                end
            end
        end
    end
    S = vertcat(rows{:});
    assert(height(S) == 324 && ...
        max(abs(asDouble(S.prds_validation_error))) < 1e-10, ...
        'PRDS degradation-curve source failed final validation.');
end

function ids = parseTrialIdList(value)
    parts = split(string(value), ';');
    ids = str2double(parts);
    ids = ids(isfinite(ids));
end

function S = preparePrdsSource(P, style, missionKeys)
    S = P(string(P.metric) == "max_agent_steps" & ...
        ismember(string(P.scenario), missionKeys), :);
    assert(height(S) == 36, 'PRDS source must contain 2 x 3 x 6 rows.');
    S.algorithm_order = algorithmOrder(string(S.algorithm), style);
    S.communication_order = nan(height(S), 1);
    for ci = 1:3
        S.communication_order(string(S.comm_model) == ...
            style.communicationKeys(ci)) = ci;
    end
    assert(all(isfinite(S.communication_order)), ...
        'Unknown communication model in PRDS source.');
end

function order = algorithmOrder(values, style)
    order = nan(numel(values), 1);
    for ai = 1:6
        order(values == style.algorithmKeys(ai) | ...
            values == style.algorithmKeysLower(ai)) = ai;
    end
    assert(all(isfinite(order)), 'Unknown algorithm encountered.');
end

function order = pairOrder(a, b)
    order = nan(size(a)); index = 0;
    for ai = 1:5
        for bi = ai + 1:6
            index = index + 1;
            order(a == ai & b == bi) = index;
        end
    end
    assert(all(isfinite(order)), 'Unknown algorithm pair encountered.');
end

function R = writeAndReloadSource(T, path)
    writetable(T, path);
    R = readCsv(path);
    assert(height(R) == height(T), ...
        'Dedicated source CSV row-count mismatch: %s', path);
    assert(width(R) == width(T), ...
        'Dedicated source CSV column-count mismatch: %s', path);
    fprintf('Wrote dedicated source: %s (%d rows)\n', displayPath(path), height(R));
end

function fig = plotPrimaryMissionPerformance(S, style, missionKeys)
    fig = newFigure('Primary mission performance', 7.00, 2.71);
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
                text(ax, 0.02, 0.92, missionKeys(mi), 'Units', 'normalized', ...
                    'FontSize', style.axesFontSize, 'FontWeight', 'bold', ...
                    'VerticalAlignment', 'top', 'HorizontalAlignment', 'left', ...
                    'BackgroundColor', 'w', 'Margin', 0.6);
            else
                ax.YTickLabel = [];
            end
            if mi == 1
                title(ax, style.communicationLabels(ci), ...
                    'FontWeight', 'normal', 'FontSize', style.titleFontSize);
            end
            if mi == 1
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

function fig = plotCvWorkloadTradeoff(S, style)
    fig = newFigure('CV travel workload tradeoff', 3.45, 2.20);
    ax = axes(fig); hold(ax, 'on'); handles = gobjects(1, 6);
    for ai = 1:6
        G = S(string(S.algorithm) == style.algorithmKeys(ai), :);
        handles(ai) = plot(ax, asDouble(G.mean_total_team_steps), ...
            asDouble(G.mean_unique_cell_contribution_gini), ...
            'LineStyle', 'none', 'Marker', style.markers{ai}, ...
            'MarkerSize', 6.0, 'MarkerFaceColor', style.colors(ai, :), ...
            'MarkerEdgeColor', style.colors(ai, :), ...
            'DisplayName', char(style.algorithmLabels(ai)));
    end
    x = asDouble(S.mean_total_team_steps);
    y = asDouble(S.mean_unique_cell_contribution_gini);
    xlim(ax, paddedLimits(x, 0.10, false));
    ylim(ax, paddedLimits(y, 0.12, false));
    xlabel(ax, 'Mean total team steps');
    ylabel(ax, {'Unique-cell','contribution Gini'});
    formatAxes(ax, style);
    lgd = legend(ax, handles, cellstr(style.algorithmLabels), ...
        'Orientation', 'horizontal', 'NumColumns', 3, ...
        'Location', 'southoutside', 'Box', 'off', ...
        'FontSize', style.legendFontSize);
    lgd.ItemTokenSize = [10 7];
end

function fig = plotCommunicationPerformanceTradeoff(S, style, missionKeys)
    fig = newFigure('Communication performance tradeoff', 3.49, 2.12);
    layout = tiledlayout(fig, 1, 2, ...
        'TileSpacing', 'compact', 'Padding', 'compact');
    axesList = gobjects(1, 2);
    algorithmHandles = gobjects(1, 6);
    for mi = 1:2
        ax = nexttile(layout); axesList(mi) = ax; hold(ax, 'on');
        Gm = S(string(S.scenario) == missionKeys(mi), :);
        for ai = 1:6
            G = Gm(string(Gm.algorithm) == style.algorithmKeys(ai), :);
            h = plot(ax, asDouble(G.mean_message_publications_per_team_step), ...
                asDouble(G.mean_maximum_agent_steps), ...
                'LineStyle', 'none', 'Marker', style.markers{ai}, ...
                'MarkerSize', 4.5, 'MarkerFaceColor', style.colors(ai, :), ...
                'MarkerEdgeColor', style.colors(ai, :), 'LineWidth', 0.55);
            if mi == 1, algorithmHandles(ai) = h; end
        end
        xlim(ax, paddedLimits(asDouble(Gm.mean_message_publications_per_team_step), ...
            0.12, true));
        ylim(ax, paddedLimits(asDouble(Gm.mean_maximum_agent_steps), 0.12, true));
        title(ax, missionKeys(mi), 'FontWeight', 'normal', ...
            'FontSize', style.titleFontSize);
        formatAxes(ax, style);
        pbaspect(ax, [1 1 1]);
    end
    xlabel(layout, 'Message publication rate');
    ylabel(axesList(1), 'Maximum-agent steps');
    lgd = legend(axesList(1), algorithmHandles, cellstr(style.algorithmLabels), ...
        'Orientation', 'horizontal', 'NumColumns', 3, 'Box', 'off', ...
        'FontSize', style.legendFontSize);
    lgd.Layout.Tile = 'south'; lgd.ItemTokenSize = [10 7];
end

function fig = plotHorizonTuning(S, style, missionNames, missionKeys)
    fig = newFigure('Horizon sensitivity', 3.49, 3.74);
    layout = tiledlayout(fig, 2, 1, ...
        'TileSpacing', 'compact', 'Padding', 'compact');
    algorithms = ["ACBBA", "PI", "HIPC", "DMCHBA", "DGA"];
    axesList = gobjects(1, 2); legendHandles = gobjects(1, 5);

    for mi = 1:2
        ax = nexttile(layout); axesList(mi) = ax; hold(ax, 'on');
        for ai = 1:numel(algorithms)
            styleIndex = find(style.algorithmKeys == algorithms(ai), 1);
            G = S(string(S.scenario) == missionNames(mi) & ...
                string(S.algorithm) == algorithms(ai), :);
            [x, order] = sort(asDouble(G.horizon));
            y = asDouble(G.robust_score); y = y(order);
            h = plot(ax, x, y, 'LineStyle', '-', ...
                'Color', style.colors(styleIndex, :), ...
                'LineWidth', style.lineWidth, ...
                'Marker', 'o', 'MarkerSize', 2.7, ...
                'MarkerFaceColor', style.colors(styleIndex, :), ...
                'MarkerEdgeColor', style.colors(styleIndex, :));
            if mi == 1, legendHandles(ai) = h; end
            selected = asLogical(G.selected_for_main_benchmark);
            if any(selected)
                plot(ax, asDouble(G.horizon(selected)), ...
                    asDouble(G.robust_score(selected)), ...
                    'LineStyle', 'none', 'Marker', 'p', 'MarkerSize', 4.5, ...
                    'MarkerFaceColor', style.colors(styleIndex, :), ...
                    'MarkerEdgeColor', [0 0 0], 'LineWidth', 0.75, ...
                    'HandleVisibility', 'off');
            end
        end
        yline(ax, 0, '-', 'Color', style.zeroColor, ...
            'LineWidth', 0.6, 'HandleVisibility', 'off');
        title(ax, missionKeys(mi), 'FontWeight', 'normal', ...
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
end

function fig = plotHorizonTuningHeatmap(S, style, missionNames, missionKeys)
    fig = newFigure('Horizon sensitivity heatmap', 3.45, 4.60);
    layout = tiledlayout(fig, 2, 2, ...
        'TileSpacing', 'compact', 'Padding', 'loose');
    algorithms = ["ACBBA", "PI", "HIPC", "DMCHBA", "DGA"];
    comms = ["ideal", "bernoulli_025"];
    commLabels = ["Ideal", "Bernoulli 0.25"];
    horizons = [1 2 3 5 8 12];
    values = asDouble(S.mean_delta_from_trial_baseline);
    bound = max(abs(values));
    limits = [-bound bound];
    map = blueWhiteRed(257);
    axesList = gobjects(2, 2);

    for mi = 1:2
        for ci = 1:2
            ax = nexttile(layout); axesList(mi, ci) = ax;
            matrix = nan(5, 6);
            selectedMask = false(5, 6);
            for ai = 1:5
                G = S(string(S.scenario) == missionNames(mi) & ...
                    string(S.algorithm) == algorithms(ai) & ...
                    string(S.comm_label) == comms(ci), :);
                [sortedHorizons, order] = sort(asDouble(G.horizon));
                assert(isequal(sortedHorizons', horizons), ...
                    'A horizon heatmap series is incomplete or out of order.');
                matrix(ai, :) = asDouble(G.mean_delta_from_trial_baseline(order))';
                selectedMask(ai, :) = ...
                    asDouble(G.selected_for_main_benchmark(order))' == 1;
            end
            imagesc(ax, 1:6, 1:5, matrix);
            hold(ax, 'on');
            set(ax, 'YDir', 'reverse');
            clim(ax, limits); colormap(ax, map);
            xlim(ax, [0.5 6.5]); ylim(ax, [0.5 5.5]);
            xticks(ax, 1:6); yticks(ax, 1:5);
            if mi == 2
                xticklabels(ax, string(horizons));
                xlabel(ax, 'Horizon');
            else
                xticklabels(ax, strings(6, 1));
            end
            if ci == 1
                yticklabels(ax, algorithms);
            else
                yticklabels(ax, strings(5, 1));
            end
            [selectedRows, selectedColumns] = find(selectedMask);
            plot(ax, selectedColumns, selectedRows, 'LineStyle', 'none', ...
                'Marker', 'p', 'MarkerSize', 5.5, ...
                'MarkerFaceColor', [1 1 1], 'MarkerEdgeColor', [0 0 0], ...
                'LineWidth', 0.85, 'HandleVisibility', 'off');
            title(ax, {char(missionKeys(mi)), char(commLabels(ci))}, ...
                'FontWeight', 'normal', 'FontSize', style.titleFontSize);
            box(ax, 'on');
            set(ax, 'FontSize', style.axesFontSize, ...
                'LineWidth', style.axisLineWidth, 'TickDir', 'out', ...
                'Layer', 'top');
        end
    end
    ylabel(layout, 'Algorithm');
    cb = colorbar(axesList(2, 2));
    cb.Layout.Tile = 'south';
    cb.Label.String = 'Mean steps vs. paired baseline';
    cb.FontSize = style.legendFontSize;
end

function fig = plotHorizonTuningSplitConditions(S, style, missionNames, missionKeys)
    % Option B separates communication conditions into columns, cutting the
    % number of curves per panel in half while preserving a single-column size.
    fig = newFigure('Horizon sensitivity option B', 3.45, 4.70);
    layout = tiledlayout(fig, 2, 2, ...
        'TileSpacing', 'compact', 'Padding', 'compact');
    algorithms = ["ACBBA", "PI", "HIPC", "DMCHBA", "DGA"];
    comms = ["ideal", "bernoulli_025"];
    commLabels = ["Ideal", "Bernoulli p_d=0.25"];
    axesList = gobjects(2, 2); legendHandles = gobjects(1, 5);

    missionYLimits = zeros(2, 2);
    for mi = 1:2
        values = asDouble(S.mean_delta_from_trial_baseline( ...
            string(S.scenario) == missionNames(mi)));
        missionYLimits(mi, :) = paddedLimits(values, 0.08, false);
    end

    for mi = 1:2
        for ci = 1:2
            ax = nexttile(layout); axesList(mi, ci) = ax; hold(ax, 'on');
            for ai = 1:numel(algorithms)
                styleIndex = find(style.algorithmKeys == algorithms(ai), 1);
                G = S(string(S.scenario) == missionNames(mi) & ...
                    string(S.algorithm) == algorithms(ai) & ...
                    string(S.comm_label) == comms(ci), :);
                [x, order] = sort(asDouble(G.horizon));
                y = asDouble(G.mean_delta_from_trial_baseline); y = y(order);
                h = plot(ax, x, y, 'LineStyle', '-', ...
                    'Color', style.colors(styleIndex, :), ...
                    'LineWidth', style.lineWidth, 'Marker', 'o', ...
                    'MarkerSize', 2.7, 'MarkerFaceColor', 'w');
                if mi == 1 && ci == 1, legendHandles(ai) = h; end
                selected = asDouble(G.selected_for_main_benchmark) == 1;
                if any(selected)
                    plot(ax, asDouble(G.horizon(selected)), ...
                        asDouble(G.mean_delta_from_trial_baseline(selected)), ...
                        'LineStyle', 'none', 'Marker', 'o', 'MarkerSize', 4.2, ...
                        'MarkerFaceColor', style.colors(styleIndex, :), ...
                        'MarkerEdgeColor', [0 0 0], 'LineWidth', 0.5, ...
                        'HandleVisibility', 'off');
                end
            end
            yline(ax, 0, '-', 'Color', style.zeroColor, ...
                'LineWidth', 0.6, 'HandleVisibility', 'off');
            xlim(ax, [0.5 12.5]); xticks(ax, [1 2 3 5 8 12]);
            ylim(ax, missionYLimits(mi, :));
            if mi == 1
                title(ax, commLabels(ci), 'FontWeight', 'normal', ...
                    'FontSize', style.titleFontSize);
                ax.XTickLabel = [];
            else
                xlabel(ax, 'Horizon');
            end
            if ci == 1
                ylabel(ax, 'Steps vs. baseline');
                text(ax, 0.03, 0.94, missionKeys(mi), 'Units', 'normalized', ...
                    'FontSize', style.axesFontSize, 'VerticalAlignment', 'top');
            else
                ax.YTickLabel = [];
            end
            formatAxes(ax, style);
        end
    end
    lgd = legend(axesList(1, 1), legendHandles, cellstr(algorithms), ...
        'Orientation', 'horizontal', 'NumColumns', 3, 'Box', 'off', ...
        'FontSize', style.legendFontSize);
    lgd.Layout.Tile = 'south'; lgd.ItemTokenSize = [10 7];
end

function fig = plotDgaIteration(S, style)
    fig = newFigure('DGA iteration sensitivity', 3.45, 2.00);
    ax = axes(fig); hold(ax, 'on');
    comms = ["ideal", "bernoulli_025"];
    labels = ["Ideal", "Bernoulli p_d=0.25"];
    lineStyles = {'-', ':'};
    colors = [0.15 0.38 0.68; 0.78 0.30 0.18];
    handles = gobjects(1, 2);
    for ci = 1:2
        G = S(string(S.comm_label) == comms(ci), :);
        [iterationValues, order] = sort(asDouble(G.dga_iterations));
        x = 1:numel(iterationValues);
        y = asDouble(G.mean_delta_from_trial_baseline); y = y(order);
        handles(ci) = plot(ax, x, y, 'LineStyle', lineStyles{ci}, ...
            'Color', colors(ci, :), 'LineWidth', 1.05, 'Marker', 'o', ...
            'MarkerSize', 3.2, 'MarkerFaceColor', 'w', ...
            'DisplayName', char(labels(ci)));
        selectedPosition = find(iterationValues == 25, 1);
        plot(ax, selectedPosition, y(selectedPosition), ...
            'LineStyle', 'none', 'Marker', 'o', 'MarkerSize', 5.2, ...
            'MarkerFaceColor', colors(ci, :), 'MarkerEdgeColor', [0 0 0], ...
            'LineWidth', 0.55, 'HandleVisibility', 'off');
    end
    yline(ax, 0, '-', 'Color', style.zeroColor, ...
        'LineWidth', 0.6, 'HandleVisibility', 'off');
    xticks(ax, 1:6); xticklabels(ax, ["1","2","5","10","25","50"]);
    xlim(ax, [0.7 6.3]);
    ylim(ax, [-6 6]); yticks(ax, -6:3:6);
    xlabel(ax, 'DGA iteration count, k');
    ylabel(ax, {'Steps vs.','paired baseline'});
    formatAxes(ax, style);
    legend(ax, handles, cellstr(labels), 'Location', 'southoutside', ...
        'Orientation', 'horizontal', 'NumColumns', 2, 'Box', 'off', ...
        'FontSize', style.legendFontSize);
end

function fig = plotGridDensitySummary(S, style, missionKeys)
    fig = newFigure('Grid and robot density sensitivity', 3.45, 4.15);
    layout = tiledlayout(fig, 2, 2, ...
        'TileSpacing', 'compact', 'Padding', 'compact');
    factors = ["grid_size", "target_cells_per_robot"];
    levels = {[14 19 25 34], [50 85 140 220]};
    xLabels = ["Grid side length", "Cells per robot"];
    axesList = gobjects(2, 2); legendHandles = gobjects(1, 6);

    for fi = 1:2
        for mi = 1:2
            ax = nexttile(layout); axesList(fi, mi) = ax; hold(ax, 'on');
            panel = S(string(S.factor) == factors(fi) & ...
                string(S.scenario) == missionKeys(mi), :);
            for ai = 1:6
                G = panel(string(panel.algorithm) == style.algorithmKeys(ai), :);
                [x, order] = sort(asDouble(G.factor_value));
                y = asDouble(G.plotted_mean); y = y(order);
                assert(numel(x) == 4, ...
                    'Each averaged grid-density curve must have four scale points.');
                h = plot(ax, x, y, 'LineStyle', '-', ...
                    'Color', style.colors(ai, :), 'LineWidth', 0.90, ...
                    'Marker', style.markers{ai}, 'MarkerSize', 2.5, ...
                    'MarkerFaceColor', style.colors(ai, :));
                if fi == 1 && mi == 1
                    legendHandles(ai) = h;
                end
            end
            xticks(ax, levels{fi});
            xlim(ax, [min(levels{fi}) - 0.03 * range(levels{fi}), ...
                max(levels{fi}) + 0.03 * range(levels{fi})]);
            xlabel(ax, xLabels(fi));
            if fi == 1
                title(ax, missionKeys(mi), 'FontWeight', 'normal', ...
                    'FontSize', style.titleFontSize);
            end
            if mi == 2
                ax.YAxisLocation = 'right';
            end
            ylim(ax, paddedLimits(asDouble(panel.plotted_mean), 0.08, true));
            formatAxes(ax, style);
        end
    end
    lgd = legend(axesList(1, 1), legendHandles, ...
        cellstr(style.algorithmLabels), 'Orientation', 'horizontal', ...
        'NumColumns', 3, 'Box', 'off', 'FontSize', style.legendFontSize);
    lgd.Layout.Tile = 'south'; lgd.ItemTokenSize = [10 7];
    labelLayer = axes(fig, 'Position', [0 0 1 1], 'Color', 'none', ...
        'XLim', [0 1], 'YLim', [0 1], 'Visible', 'off', ...
        'HitTest', 'off');
    text(labelLayer, 0.018, 0.56, 'Post-clue steps/cell', ...
        'Rotation', 90, 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', 'FontSize', style.axesFontSize);
    text(labelLayer, 0.982, 0.56, 'Team steps/target', ...
        'Rotation', 90, 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', 'FontSize', style.axesFontSize);
end

function fig = plotGridDensityMaxStepsSummary(S, style, missionKeys)
    fig = newFigure('Grid and density maximum-agent sensitivity', 3.49, 4.30);
    layout = tiledlayout(fig, 2, 2, ...
        'TileSpacing', 'compact', 'Padding', 'loose');
    factors = ["grid_size", "target_cells_per_robot"];
    levels = {[14 19 25 34], [50 85 140 220]};
    xLabels = ["Grid side length", "Cells per robot"];
    axesList = gobjects(2, 2);
    legendHandles = gobjects(1, 6);

    for fi = 1:2
        for mi = 1:2
            ax = nexttile(layout); axesList(fi, mi) = ax; hold(ax, 'on');
            panel = S(string(S.factor) == factors(fi) & ...
                string(S.scenario) == missionKeys(mi), :);
            for ai = 1:6
                G = panel(string(panel.algorithm) == style.algorithmKeys(ai), :);
                [x, order] = sort(asDouble(G.factor_value));
                y = asDouble(G.plotted_mean); y = y(order);
                assert(numel(x) == 4, ...
                    'Each maximum-step grid-density curve must have four points.');
                h = plot(ax, x, y, 'LineStyle', '-', ...
                    'Color', style.colors(ai, :), 'LineWidth', 0.90, ...
                    'Marker', 'o', 'MarkerSize', 2.5, ...
                    'MarkerEdgeColor', style.colors(ai, :), ...
                    'MarkerFaceColor', style.colors(ai, :));
                if fi == 1 && mi == 1, legendHandles(ai) = h; end
            end
            xticks(ax, levels{fi});
            xlim(ax, [min(levels{fi}) - 0.04 * range(levels{fi}), ...
                max(levels{fi}) + 0.04 * range(levels{fi})]);
            xlabel(ax, xLabels(fi));
            if fi == 1
                title(ax, missionKeys(mi), 'FontWeight', 'normal', ...
                    'FontSize', style.titleFontSize);
            end
            if mi == 2, ax.YAxisLocation = 'right'; end
            ylim(ax, paddedLimits(asDouble(panel.plotted_mean), 0.10, true));
            formatAxes(ax, style);
        end
    end
    sharedYLabel = ylabel(layout, 'Mean maximum-agent steps');
    set(sharedYLabel, 'FontSize', style.axesFontSize, 'FontWeight', 'normal');
    lgd = legend(axesList(1, 1), legendHandles, ...
        cellstr(style.algorithmLabels), 'Orientation', 'horizontal', ...
        'NumColumns', 3, 'Box', 'off', 'FontSize', style.legendFontSize);
    lgd.Layout.Tile = 'south'; lgd.ItemTokenSize = [10 7];
end

function fig = plotGridDensityNormalizedMaxStepsSummary(S, style, missionKeys)
    fig = newFigure('Normalized maximum-agent grid and density sensitivity', ...
        3.45, 4.25);
    layout = tiledlayout(fig, 2, 2, ...
        'TileSpacing', 'compact', 'Padding', 'loose');
    factors = ["grid_size", "target_cells_per_robot"];
    levels = {[14 19 25 34], [50 85 140 220]};
    xLabels = ["Grid side length", "Cells per robot"];
    titleLabels = ["CLIPS (steps/cell)", "CV (steps/target)"];
    axesList = gobjects(2, 2);
    legendHandles = gobjects(1, 6);

    for fi = 1:2
        for mi = 1:2
            ax = nexttile(layout); axesList(fi, mi) = ax; hold(ax, 'on');
            panel = S(string(S.factor) == factors(fi) & ...
                string(S.scenario) == missionKeys(mi), :);
            for ai = 1:6
                G = panel(string(panel.algorithm) == style.algorithmKeys(ai), :);
                [x, order] = sort(asDouble(G.factor_value));
                y = asDouble(G.plotted_mean); y = y(order);
                assert(numel(x) == 4, ...
                    'Each normalized maximum-step curve must have four points.');
                h = plot(ax, x, y, 'LineStyle', '-', ...
                    'Color', style.colors(ai, :), 'LineWidth', 0.90, ...
                    'Marker', 'o', 'MarkerSize', 2.5, ...
                    'MarkerEdgeColor', style.colors(ai, :), ...
                    'MarkerFaceColor', style.colors(ai, :));
                if fi == 1 && mi == 1, legendHandles(ai) = h; end
            end
            xticks(ax, levels{fi});
            xlim(ax, [min(levels{fi}) - 0.04 * range(levels{fi}), ...
                max(levels{fi}) + 0.04 * range(levels{fi})]);
            xlabel(ax, xLabels(fi));
            if fi == 1
                title(ax, titleLabels(mi), 'FontWeight', 'normal', ...
                    'FontSize', style.titleFontSize);
            end
            if mi == 2, ax.YAxisLocation = 'right'; end
            ylim(ax, paddedLimits(asDouble(panel.plotted_mean), 0.10, true));
            formatAxes(ax, style);
        end
    end
    ylabel(layout, 'Normalized maximum-agent steps');
    lgd = legend(axesList(1, 1), legendHandles, ...
        cellstr(style.algorithmLabels), 'Orientation', 'horizontal', ...
        'NumColumns', 3, 'Box', 'off', 'FontSize', style.legendFontSize);
    lgd.Layout.Tile = 'south'; lgd.ItemTokenSize = [10 7];
end

function fig = plotPrdsPanelOptionA(S, style, missionKeys)
    fig = newFigure('PRDS degradation curves option A', 7.10, 5.15);
    layout = tiledlayout(fig, 3, 2, ...
        'TileSpacing', 'compact', 'Padding', 'compact');
    missionLimits = zeros(2, 2);
    for mi = 1:2
        missionLimits(mi, :) = paddedLimits(asDouble(S.mean( ...
            string(S.scenario) == missionKeys(mi))), 0.07, true);
    end
    axesList = gobjects(3, 2);
    legendHandles = gobjects(1, 6);

    for ci = 1:3
        for mi = 1:2
            ax = nexttile(layout); axesList(ci, mi) = ax; hold(ax, 'on');
            panel = S(string(S.scenario) == missionKeys(mi) & ...
                string(S.comm_model) == style.communicationKeys(ci), :);
            for ai = 1:6
                G = panel(string(panel.algorithm) == style.algorithmKeys(ai), :);
                G = sortrows(G, 'degradation_pct');
                assert(height(G) == 9 && ...
                    isequal(asDouble(G.degradation_pct)', [0 style.lossLevels]), ...
                    'A PRDS degradation curve is incomplete or out of order.');
                h = plot(ax, asDouble(G.degradation_pct), asDouble(G.mean), ...
                    'LineStyle', '-', 'Color', style.colors(ai, :), ...
                    'LineWidth', style.lineWidth, 'Marker', 'o', ...
                    'MarkerSize', 2.5, ...
                    'MarkerEdgeColor', style.colors(ai, :), ...
                    'MarkerFaceColor', style.colors(ai, :));
                if ci == 1 && mi == 1, legendHandles(ai) = h; end
            end
            xlim(ax, [-2 72]); ylim(ax, missionLimits(mi, :));
            xticks(ax, [0 20 40 60 70]);
            if ci == 3
                xticklabels(ax, ["0","20","40","60","70"]);
            else
                xticklabels(ax, strings(5, 1));
            end
            title(ax, missionKeys(mi) + ": " + style.communicationLabels(ci), ...
                'FontWeight', 'normal', 'FontSize', style.titleFontSize);
            formatAxes(ax, style);
        end
    end
    xlabel(layout, 'Communication degradation (%)');
    ylabel(layout, 'Mean maximum-agent steps');
    lgd = legend(axesList(1, 1), legendHandles, ...
        cellstr(style.algorithmLabels), 'Orientation', 'horizontal', ...
        'NumColumns', 6, 'Box', 'off', 'FontSize', style.legendFontSize);
    lgd.Layout.Tile = 'south'; lgd.ItemTokenSize = [10 7];
end

function fig = plotPrdsHeatmapOptionB(S, style, missionKeys)
    fig = prds_heatmap_option_b_figure(S, style, missionKeys);
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

function labels = makePairLabels(style)
    labels = strings(15, 1); index = 0;
    for ai = 1:5
        for bi = ai + 1:6
            index = index + 1;
            labels(index) = style.algorithmKeys(ai) + "–" + style.algorithmKeys(bi);
        end
    end
end

function map = blueWhiteRed(count)
    lower = [0.16 0.36 0.72];
    middle = [1.00 1.00 1.00];
    upper = [0.76 0.18 0.18];
    lowerCount = ceil(count / 2);
    upperCount = count - lowerCount + 1;
    first = [linspace(lower(1), middle(1), lowerCount)', ...
        linspace(lower(2), middle(2), lowerCount)', ...
        linspace(lower(3), middle(3), lowerCount)'];
    second = [linspace(middle(1), upper(1), upperCount)', ...
        linspace(middle(2), upper(2), upperCount)', ...
        linspace(middle(3), upper(3), upperCount)'];
    map = [first; second(2:end, :)];
end

function row = exportFinalFigure(fig, figureId, stem, widthIn, heightIn, ...
        activeDir, inspectionDir, style, sourceRows)
    set(fig, 'Units', 'inches', 'Position', [1 1 widthIn heightIn], ...
        'PaperUnits', 'inches', 'PaperPosition', [0 0 widthIn heightIn], ...
        'PaperSize', [widthIn heightIn], 'Color', 'w');
    apply_publication_figure_typography(fig, style);
    drawnow;
    pngPath = fullfile(activeDir, stem + ".png");
    inspectionPngPath = fullfile(inspectionDir, stem + ".png");
    figPath = fullfile(inspectionDir, stem + ".fig");
    print(fig, char(pngPath), '-dpng', sprintf('-r%d', style.exportDpi));
    [copied, message] = copyfile(pngPath, inspectionPngPath, 'f');
    if ~copied
        error('Could not copy inspection PNG for %s: %s', stem, message);
    end
    savefig(fig, figPath);
    close(fig);
    assert(isfile(pngPath) && isfile(inspectionPngPath) && isfile(figPath), ...
        'An expected export is absent for %s.', stem);
    pngInfo = imfinfo(pngPath);
    row = table(figureId, stem, widthIn, heightIn, ...
        double(pngInfo.Width), double(pngInfo.Height), ...
        string(pngPath), string(figPath), sourceRows, ...
        'VariableNames', {'figure_id','stem','canvas_width_in','canvas_height_in', ...
        'png_width_px','png_height_px','png_path','fig_path','source_rows'});
    fprintf('Exported %s [active PNG 600 dpi, inspection PNG, FIG] at %.2f x %.2f in\n', ...
        stem, widthIn, heightIn);
end

function exportAlternateFigure(fig, outputPath, widthIn, heightIn, style)
    set(fig, 'Units', 'inches', 'Position', [1 1 widthIn heightIn], ...
        'PaperUnits', 'inches', 'PaperPosition', [0 0 widthIn heightIn], ...
        'PaperSize', [widthIn heightIn], 'Color', 'w');
    apply_publication_figure_typography(fig, style);
    drawnow;
    exportgraphics(fig, outputPath, 'Resolution', style.exportDpi);
    close(fig);
    assert(isfile(outputPath), 'Alternate figure export is absent: %s', outputPath);
    fprintf('Exported alternate: %s [PNG %d dpi]\n', outputPath, style.exportDpi);
end

function fig = newFigure(name, widthIn, heightIn)
    fig = figure('Name', name, 'Color', 'w', 'Units', 'inches', ...
        'Position', [1 1 widthIn heightIn], 'Visible', 'off');
end

function formatAxes(ax, style)
    grid(ax, 'on'); box(ax, 'on');
    set(ax, 'FontSize', style.axesFontSize, ...
        'TitleFontSizeMultiplier', 1, 'LabelFontSizeMultiplier', 1, ...
        'LineWidth', style.axisLineWidth, 'GridAlpha', style.gridAlpha, ...
        'MinorGridAlpha', style.gridAlpha / 2, 'TickDir', 'out', ...
        'Layer', 'top');
end

function limits = paddedLimits(values, fraction, nonnegative)
    values = values(isfinite(values));
    if isempty(values), limits = [0 1]; return; end
    low = min(values); high = max(values); span = high - low;
    if span <= 0, span = max(abs(low), 1); end
    limits = [low - fraction * span, high + fraction * span];
    if nonnegative, limits(1) = max(0, limits(1)); end
end

function writeRevisedCaptions(path)
    fid = fopen(path, 'w');
    if fid < 0, error('Could not write caption file: %s', path); end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%% Generated by generate_final_paper_figures_CLIPS_CV.m.\n');
    fprintf(fid, '%% Active main-paper figures\n\n');

    writeFigureEnvironment(fid, true, 'primary_mission_performance_curves', ...
        ['Mission-specific paired performance under Bernoulli, Gilbert--Elliott ($\rho=0.8$), and Rayleigh-style degradation. ', ...
        'CLIPS and CV both report maximum-agent steps. Curves show paired means with 95\% confidence intervals.'], ...
        'fig:primary_mission_performance');
    writeFigureEnvironment(fid, false, 'communication_performance_tradeoff', ...
        ['Communication--performance tradeoff for CLIPS and CV. Each point is an algorithm''s unweighted mean across the 24 impaired condition means. ', ...
        'The left panel reports CLIPS and the right panel CV. The horizontal axis is message publications per team step and the vertical axis is maximum-agent steps; lower-left is preferable.'], ...
        'fig:communication_performance_tradeoff');
    writeFigureEnvironment(fid, false, 'prds_supplement', ...
        ['Paired relative degradation slope (PRDS) for maximum-agent steps. Columns B, GE, and R denote Bernoulli, Gilbert--Elliott, and Rayleigh-style degradation, respectively. ', ...
        'Each cell reports the mean fitted percentage change in $S_{\max}$ per one-percentage-point increase in communication degradation. ', ...
        'Within each mission and communication model, all six algorithms use the same complete trial trajectories across ideal communication and all eight degraded levels. ', ...
        'Smaller positive values indicate slower degradation from ideal performance, while negative values indicate a decreasing fitted trajectory.'], ...
        'fig:prds_supplement');
    writeFigureEnvironment(fid, false, 'grid_density_maximum_agent_steps_summary', ...
        ['Maximum-agent-step sensitivity to grid side length and nominal cells per robot. Columns show CLIPS and CV; rows show the two scale factors. ', ...
        'Each point pools retained trial blocks across both communication settings and all four opposite-factor levels; a block contributes only when all six algorithms completed with finite maximum-agent steps.'], ...
        'fig:grid_density_maximum_agent_steps');
    writeFigureEnvironment(fid, false, 'horizon_tuning', ...
        ['Commitment-horizon robust scores for CLIPS and CV. Higher scores indicate a more favorable balance of average improvement, communication-condition agreement, bad-condition performance, and local stability. ', ...
        'Pentagrams mark the robust-score decision-table selections.'], ...
        'fig:horizon_sensitivity');
end

function writeFigureEnvironment(fid, isWide, stem, caption, label)
    if isWide
        environment = 'figure*'; width = '\textwidth';
    else
        environment = 'figure'; width = '\columnwidth';
    end
    fprintf(fid, '\\begin{%s}[!t]\n', environment);
    fprintf(fid, '    \\centering\n');
    fprintf(fid, '    \\includegraphics[width=%s]{figures/%s.png}\n', width, stem);
    fprintf(fid, '    \\caption{%s}\n', caption);
    fprintf(fid, '    \\label{%s}\n', label);
    fprintf(fid, '\\end{%s}\n\n', environment);
end

function writeValidationReport(path, sources, archive, inventory, checks, ...
        style, sourceDir, captionPath)
    fid = fopen(path, 'w');
    if fid < 0, error('Could not write validation report: %s', path); end
    cleanup = onCleanup(@() fclose(fid));

    fprintf(fid, '# MATLAB figure validation report: CLIPS/CV revision\n\n');
    fprintf(fid, ['Generated by `results/analysis/generate_final_paper_figures_CLIPS_CV.m`. ', ...
        'All active PNG and editable FIG outputs were produced directly by MATLAB %s. ', ...
        'No simulation was rerun and no raw benchmark CSV was modified.\n\n'], version);

    products = ver;
    fprintf(fid, '## MATLAB environment\n\n');
    fprintf(fid, '| Product | Version |\n|---|---|\n');
    for i = 1:numel(products)
        fprintf(fid, '| %s | %s |\n', products(i).Name, products(i).Version);
    end
    fprintf(fid, '\n');

    fprintf(fid, '## Authoritative input manifest\n\n');
    fprintf(fid, ['The machine-readable manifest is `results/analysis/tables/paper_figure_source_manifest.csv`. ', ...
        'Every input was checked to exclude archive and pre-correction locations.\n\n']);
    fprintf(fid, '| Data rows | Bytes | Modified | SHA-256 | Repository path |\n');
    fprintf(fid, '|---:|---:|---|---|---|\n');
    for i = 1:height(sources)
        fprintf(fid, '| %d | %d | %s | `%s` | `%s` |\n', ...
            sources.data_rows(i), sources.bytes(i), ...
            char(sources.last_modified(i)), char(sources.sha256(i)), ...
            char(sources.repository_path(i)));
    end
    fprintf(fid, '\n');

    fprintf(fid, '## Source-derived cross-checks\n\n');
    fprintf(fid, ['Retained sources identify the current Gilbert--Elliott campaign with fixed `rho_0_8`. ', ...
        'Every expected value below is a structural invariant or an independently matched value from another active repository table; no prompt-supplied result is used.\n\n']);
    fprintf(fid, '| Check | Observed | Expected | Error | Passed |\n');
    fprintf(fid, '|---|---:|---:|---:|---|\n');
    for i = 1:height(checks)
        fprintf(fid, '| %s | %.10g | %.10g | %.3g | %s |\n', ...
            char(checks.check(i)), checks.observed(i), checks.expected(i), ...
            checks.absolute_error(i), yesNo(checks.passed(i)));
    end
    fprintf(fid, '\n');

    fprintf(fid, '## Figure definitions and cohorts\n\n');
    fprintf(fid, '- **Figure 1:** CLIPS and CV six-way paired maximum-agent steps, with absolute paired means and 95%% intervals.\n');
    fprintf(fid, '- **Figure 2:** one-column, side-by-side mission summaries of 24 impaired condition means for publications per team step and maximum-agent steps.\n');
    fprintf(fid, '- **Figure 3:** one-column CLIPS/CV heatmaps of 36 common-six PRDS slope means, with communication models kept separate.\n');
    fprintf(fid, '- **Figure 4:** one-column 2-by-2 maximum-agent-step grid/density sensitivity curves computed from complete six-algorithm trial blocks.\n');
    fprintf(fid, '- **Figure 5:** one-column, vertically stacked CLIPS/CV robust-score horizon curves; decision-table selections are marked by pentagrams.\n\n');
    fprintf(fid, ['All canvases use the same physical axis, title, and legend font sizes. ', ...
        'Full-width and one-column dimensions match their intended IEEE placements, so labels are not normalized by post-export scaling.\n\n']);

    fprintf(fid, '## Output inventory and physical dimensions\n\n');
    fprintf(fid, '| Figure | Stem | Canvas (in) | PNG pixels | Source rows | Active PNG |\n');
    fprintf(fid, '|---|---|---:|---:|---:|---|\n');
    for i = 1:height(inventory)
        fprintf(fid, '| %s | `%s` | %.2f x %.2f | %d x %d | %d | `%s` |\n', ...
            char(inventory.figure_id(i)), char(inventory.stem(i)), ...
            inventory.canvas_width_in(i), inventory.canvas_height_in(i), ...
            inventory.png_width_px(i), inventory.png_height_px(i), ...
            inventory.source_rows(i), char(inventory.png_path(i)));
    end
    fprintf(fid, ['\nActive 600-dpi PNGs are in `results/analysis/figures/`; ', ...
        'matching inspection PNGs and MATLAB FIG files are in ', ...
        '`results/analysis/figures/inspection/`. Dedicated plotted-value CSVs are in ', ...
        '`results/analysis/tables/final_figure_sources/`. Algorithm mapping remains %s.\n\n'], ...
        strjoin(style.algorithmLabels, ', '));

    fprintf(fid, '## Private regeneration archive\n\n');
    fprintf(fid, ['This run preserved %d superseded local outputs under ', ...
        '`archive_private/figure_regeneration_history/`. That directory is intentionally ', ...
        'excluded from the public repository.\n\n'], height(archive));

    fprintf(fid, '## Validation result\n\n');
    fprintf(fid, ['PASS. Exactly the five requested paper-figure stems remain. Every active stem has one top-level 600-dpi PNG, ', ...
        'one matching inspection PNG, one MATLAB FIG file, and one dedicated source CSV. ', ...
        'No active plot substitutes penalties for noncompleted rows. Captions are in `%s`.\n'], ...
        displayPath(captionPath));
end

function validateFinalInventory(activeDir, inspectionDir, sourceDir, ...
        inventory, sources, archive, activeStems, style)
    assert(height(inventory) == 5, 'Exactly five final paper figures are required.');
    assert(isequal(sort(string(inventory.stem)), sort(activeStems(:))), ...
        'Active figure stems do not match the requested five-stem set.');
    assert(height(sources) == 13, 'Unexpected source-manifest input count.');
    assert(all(sources.active_source_verified), ...
        'An archived input entered the manifest.');

    activePdf = dir(fullfile(activeDir, '*.pdf'));
    activePng = dir(fullfile(activeDir, '*.png'));
    activeFig = dir(fullfile(activeDir, '*.fig'));
    assert(numel(activePng) == 5, ...
        'Active figure directory must contain exactly five top-level PNGs.');
    assert(isempty(activePdf) && isempty(activeFig), ...
        'Top-level active figure directory must contain PNG outputs only.');
    assert(numel(dir(fullfile(inspectionDir, '*.png'))) == 5, ...
        'Expected five inspection PNGs.');
    assert(numel(dir(fullfile(inspectionDir, '*.fig'))) == 5, ...
        'Expected five MATLAB FIG files.');
    assert(isempty(dir(fullfile(inspectionDir, '*.pdf'))), ...
        'Inspection directory must not retain stale PDFs.');
    alternateDir = fullfile(activeDir, 'alternates');
    if isfolder(alternateDir)
        assert(isempty([dir(fullfile(alternateDir, '*.png')); ...
            dir(fullfile(alternateDir, '*.fig')); ...
            dir(fullfile(alternateDir, '*.pdf'))]), ...
            'Alternate directory retains superseded figure outputs.');
    end
    assert(numel(dir(fullfile(sourceDir, 'source_*.csv'))) == 5, ...
        'Expected five dedicated source CSVs.');

    for i = 1:height(inventory)
        assert(isfile(inventory.png_path(i)) && isfile(inventory.fig_path(i)), ...
            'Final output inventory contains an absent file.');
        info = dir(inventory.png_path(i));
        assert(info.bytes > 10000, 'Active PNG is unexpectedly small.');
        assert(inventory.png_width_px(i) > 1000 && ...
            inventory.png_height_px(i) > 700, ...
            'Active 600-dpi PNG dimensions are unexpectedly small.');
        expectedWidth = round(inventory.canvas_width_in(i) * style.exportDpi);
        expectedHeight = round(inventory.canvas_height_in(i) * style.exportDpi);
        assert(abs(inventory.png_width_px(i) - expectedWidth) <= 2 && ...
            abs(inventory.png_height_px(i) - expectedHeight) <= 2, ...
            'PNG pixel dimensions do not preserve the declared physical canvas.');
    end
    if ~isempty(archive)
        assert(all(arrayfun(@(i) isfile(archive.archived_path(i)), ...
            1:height(archive))), 'An archived output is absent.');
    end
    fprintf(['PASS: source inventory, archive, dimensions, formats, ', ...
        'and active-directory uniqueness.\n']);
end

function tf = asLogical(value)
    if islogical(value)
        tf = value;
    elseif isnumeric(value)
        tf = value ~= 0;
    else
        text = lower(strtrim(string(value)));
        tf = text == "true" | text == "1" | text == "yes";
    end
end

function value = asDouble(value)
    if isnumeric(value) || islogical(value)
        value = double(value);
    else
        value = str2double(string(value));
    end
end

function inventory = relativizeInventory(inventory, repoRoot)
    for i = 1:height(inventory)
        inventory.png_path(i) = string(strrep( ...
            relativePath(inventory.png_path(i), repoRoot), '\', '/'));
        inventory.fig_path(i) = string(strrep( ...
            relativePath(inventory.fig_path(i), repoRoot), '\', '/'));
    end
end

function relative = relativePath(path, repoRoot)
    path = string(path);
    repoRoot = strip(string(repoRoot), 'right', filesep);
    prefix = repoRoot + filesep;
    assert(startsWith(lower(path), lower(prefix)), ...
        'Path is outside the repository root: %s', path);
    relative = extractAfter(path, strlength(prefix));
end

function text = displayPath(path)
    normalized = replace(string(path), "\", "/");
    token = regexp(char(normalized), '(results|archive_private)/.*$', ...
        'match', 'once');
    if isempty(token)
        text = normalized;
    else
        text = string(token);
    end
end

function ensureDir(path)
    if ~exist(path, 'dir'), mkdir(path); end
end

function n = countCsvRows(path)
    fid = fopen(path, 'r');
    if fid < 0, error('Could not count CSV rows: %s', path); end
    cleanup = onCleanup(@() fclose(fid));
    n = -1;
    while ~feof(fid)
        line = fgetl(fid);
        if ischar(line), n = n + 1; end
    end
    n = max(0, n);
end

function hash = sha256File(path)
    fid = fopen(path, 'r');
    if fid < 0, error('Could not hash file: %s', path); end
    cleanup = onCleanup(@() fclose(fid));
    bytes = fread(fid, inf, '*uint8');
    engine = java.security.MessageDigest.getInstance('SHA-256');
    engine.update(bytes);
    digest = typecast(engine.digest(), 'uint8');
    hash = lower(reshape(dec2hex(digest, 2).', 1, []));
end

function text = yesNo(value)
    if value, text = 'yes'; else, text = 'no'; end
end
