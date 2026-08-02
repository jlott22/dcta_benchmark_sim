% build_dcta_paired_metric_results.m
% Self-contained paired metric analysis for DCTA benchmark results.
%
% The script intentionally writes only into analysisDir. It produces one
% graph-ready long-format CSV, a source manifest, and a text analysis log.

if ~exist("dctaAnalysisRunMode", "var")
    dctaAnalysisRunMode = "full";
end
dctaAnalysisRunMode = string(dctaAnalysisRunMode);
validRunModes = ["coverage_append_only","full"];
if ~ismember(dctaAnalysisRunMode, validRunModes)
    error("Unsupported dctaAnalysisRunMode '%s'. Expected one of: %s", ...
        dctaAnalysisRunMode, strjoin(validRunModes, ", "));
end
clc;

%% Configuration
analysisDir = string(fileparts(mfilename("fullpath")));
projectRoot = string(fileparts(fileparts(analysisDir)));
resultsRoot = fullfile(projectRoot, "results");
bayesianCandidateDir = fullfile(resultsRoot, "clue_search_core_500", "combined");
coverageCandidateDir = fullfile(resultsRoot, "coverage_core_100", "combined");
collaborativeDir = fullfile(resultsRoot, "known_target_visit_core_500", "combined");
coverageScenario = "Coverage area search";

algorithmOrder = ["CBAA","ACBBA","PI","HIPC","DMCHBA","DGA"];
nominalLevels = [0 5 10 20 30 40 50 60 70];
degradedLevels = nominalLevels(2:end);
degradationModels = ["bernoulli","gilbert_elliott","rayleigh_style"];
bootstrapIterations = 10000;
rngSeed = 20260714;

tablesDir = fullfile(analysisDir, "tables");
if ~isfolder(tablesDir)
    mkdir(tablesDir);
end

metricCsvPath = fullfile(tablesDir, "dcta_metric_results.csv");
statCsvPath = fullfile(tablesDir, "dcta_statistical_tests.csv");
manifestPath = fullfile(tablesDir, "dcta_metric_source_manifest.csv");
logPath = fullfile(tablesDir, "dcta_metric_analysis_log.txt");
scriptPath = mfilename("fullpath") + ".m";

rng(rngSeed, "twister");
logFid = fopen(logPath, "w");
cleanupObj = onCleanup(@() fclose(logFid));
logLine(logFid, "DCTA paired metric analysis");
logLine(logFid, "Date/time: %s", string(datetime("now")));
logLine(logFid, "MATLAB version: %s", version);
logLine(logFid, "Project root: %s", projectRoot);
logLine(logFid, "Analysis directory: %s", analysisDir);
logLine(logFid, "Run mode: %s", dctaAnalysisRunMode);
logLine(logFid, "Bootstrap iterations: %d", bootstrapIterations);
logLine(logFid, "RNG seed: %d", rngSeed);
logLine(logFid, "Script path: %s", scriptPath);

if dctaAnalysisRunMode == "coverage_append_only" && (~isfile(metricCsvPath) || ~isfile(statCsvPath))
    error("coverage_append_only requires existing %s and %s. Set dctaAnalysisRunMode = ""full"" to rebuild all scenarios.", ...
        metricCsvPath, statCsvPath);
end

fprintf("Reading DCTA benchmark sources...\n");

%% Read and normalize source data
manifestRows = {};

coverageFiles = dir(fullfile(coverageCandidateDir, "*"));
coverageNames = string({coverageFiles(~[coverageFiles.isdir]).name});
logLine(logFid, "Coverage source folder inspected: %s", coverageCandidateDir);
logLine(logFid, "Coverage source files: %s", strjoin(coverageNames, ", "));

if dctaAnalysisRunMode == "full"
    [clueSystem, manifestRows] = readSourceTable(manifestRows, "Bayesian clue-informed search", ...
        "system_performance", fullfile(bayesianCandidateDir, "system_performance.csv"), true, ...
        "Primary Bayesian system metrics and message publish counts");
    [clueTrial, manifestRows] = readSourceTable(manifestRows, "Bayesian clue-informed search", ...
        "trial_summary", fullfile(bayesianCandidateDir, "trial_summary.csv"), true, ...
        "Bayesian clue-first eligibility and trial identity checks");
    [clueRobot, manifestRows] = readSourceTable(manifestRows, "Bayesian clue-informed search", ...
        "robot_performance", fullfile(bayesianCandidateDir, "robot_performance.csv"), true, ...
        "Robot-level max message and metric validation");
    [clueManifest, manifestRows] = readSourceTable(manifestRows, "Bayesian clue-informed search", ...
        "condition_manifest", fullfile(bayesianCandidateDir, "condition_manifest.csv"), true, ...
        "Bayesian condition definitions and nominal communication labels");

    [knownSystem, manifestRows] = readSourceTable(manifestRows, "Collaborative known-target visit", ...
        "system_performance", fullfile(collaborativeDir, "system_performance.csv"), true, ...
        "Primary known-target system metrics and target completion status");
    [knownTrial, manifestRows] = readSourceTable(manifestRows, "Collaborative known-target visit", ...
        "trial_summary", fullfile(collaborativeDir, "trial_summary.csv"), true, ...
        "Known-target scenario identity and mission completion checks");
    [knownRobot, manifestRows] = readSourceTable(manifestRows, "Collaborative known-target visit", ...
        "robot_performance", fullfile(collaborativeDir, "robot_performance.csv"), true, ...
        "Robot-level max message and target completion balance validation");
    [knownManifest, manifestRows] = readSourceTable(manifestRows, "Collaborative known-target visit", ...
        "condition_manifest", fullfile(collaborativeDir, "condition_manifest.csv"), true, ...
        "Known-target condition definitions and nominal communication labels");

    targetPartFiles = dir(fullfile(collaborativeDir, "target_performance_part_*.csv"));
    for k = 1:numel(targetPartFiles)
        partPath = fullfile(targetPartFiles(k).folder, targetPartFiles(k).name);
        manifestRows = addManifestRow(manifestRows, "Collaborative known-target visit", ...
            "target_performance_part", partPath, NaN, NaN, false, ...
            "Not loaded for metric calculation because duplicate visits and first-completion balance are available in validated system/robot summaries", ...
            "first_finder_robot_id,total_visits,duplicate_visits,completed", false, ...
            "Part files are documented but not appended to avoid unnecessary duplication of summary metrics.");
    end

    clueSystem = normalizeSourceTable(clueSystem);
    clueTrial = normalizeSourceTable(clueTrial);
    clueRobot = normalizeSourceTable(clueRobot);
    clueManifest = normalizeSourceTable(clueManifest);
    knownSystem = normalizeSourceTable(knownSystem);
    knownTrial = normalizeSourceTable(knownTrial);
    knownRobot = normalizeSourceTable(knownRobot);
    knownManifest = normalizeSourceTable(knownManifest);

    logScenarioIdentity(logFid, "Bayesian clue-informed search", bayesianCandidateDir, clueSystem, clueTrial, clueManifest);
    logScenarioIdentity(logFid, "Collaborative known-target visit", collaborativeDir, knownSystem, knownTrial, knownManifest);

    assertAlgorithms(logFid, "Bayesian clue-informed search", clueManifest, algorithmOrder);
    assertAlgorithms(logFid, "Collaborative known-target visit", knownManifest, algorithmOrder);
end

[coverageSystem, manifestRows] = readSourceTable(manifestRows, coverageScenario, ...
    "system_performance", fullfile(coverageCandidateDir, "system_performance.csv"), true, ...
    "Primary coverage system metrics: steps, revisits, messages, replans, and workload balance");
[coverageTrial, manifestRows] = readSourceTable(manifestRows, coverageScenario, ...
    "trial_summary", fullfile(coverageCandidateDir, "trial_summary.csv"), true, ...
    "Coverage trial identity and completion checks; clue and target fields are intentionally ignored");
[coverageRobot, manifestRows] = readSourceTable(manifestRows, coverageScenario, ...
    "robot_performance", fullfile(coverageCandidateDir, "robot_performance.csv"), true, ...
    "Coverage robot-level max message, max step, and workload validation");
[coverageManifest, manifestRows] = readSourceTable(manifestRows, coverageScenario, ...
    "condition_manifest", fullfile(coverageCandidateDir, "condition_manifest.csv"), true, ...
    "Coverage condition definitions and nominal communication labels");

coverageSystem = normalizeSourceTable(coverageSystem);
coverageTrial = normalizeSourceTable(coverageTrial);
coverageRobot = normalizeSourceTable(coverageRobot);
coverageManifest = normalizeSourceTable(coverageManifest);

logScenarioIdentity(logFid, coverageScenario, coverageCandidateDir, coverageSystem, coverageTrial, coverageManifest);
assertAlgorithms(logFid, coverageScenario, coverageManifest, algorithmOrder);

%% Build metric-ready tables
analysisVars = ["scenario","trial_id","algorithm","comm_model","comm_level_raw","comm_level_pct","is_ideal","base_eligible", ...
    "messages_sent_total_metric","total_team_steps_metric","max_agent_steps","max_agent_messages", ...
    "unique_cell_contribution_gini","target_completion_gini","duplicate_target_visits", ...
    "metric_max_agent_steps","metric_total_team_steps","metric_team_messages_per_step", ...
    "metric_max_agent_messages","metric_messages_per_unique_cell","metric_unique_cell_contribution_gini", ...
    "metric_team_task_replans","metric_team_path_replans","metric_system_cell_revisits","metric_duplicate_target_visits", ...
    "metric_target_completion_gini","metric_messages_per_target"];
dataParts = {};
if dctaAnalysisRunMode == "full"
    clueData = buildMetricData("Bayesian clue-informed search", clueSystem, clueTrial, clueRobot, algorithmOrder, logFid);
    knownData = buildMetricData("Collaborative known-target visit", knownSystem, knownTrial, knownRobot, algorithmOrder, logFid);
    dataParts{end+1} = clueData(:, analysisVars); %#ok<SAGROW>
    dataParts{end+1} = knownData(:, analysisVars); %#ok<SAGROW>
end
coverageData = buildMetricData(coverageScenario, coverageSystem, coverageTrial, coverageRobot, algorithmOrder, logFid);
dataParts{end+1} = coverageData(:, analysisVars);
allData = vertcat(dataParts{:});

logLine(logFid, "Exact clue-first eligibility rule selected: trial_status == completed, system row completed, and nonempty first_clue_robot in trial_summary.");
logLine(logFid, "Collaborative eligibility rule selected: trial_status == completed, all_targets_visited true, completed_target_count == target_count, and required metric data present.");
logLine(logFid, "Coverage eligibility rule selected: completed coverage trial in system and trial summaries; no clue or target domain fields are used.");
logLine(logFid, "Message counting selected: messages_sent_total for team publish count; robot_performance.messages_sent max for max_agent_messages when system max is absent.");
logLine(logFid, "Task-replan definition selected: team_task_replans uses task_cell_replans_total, which increments when a current task/goal is invalidated and replaced.");
logLine(logFid, "Path-replan definition selected: team_path_replans uses path_replans_total, which counts path-planner replans from blocked, infeasible, collision, or navigation-friction conditions.");
logLine(logFid, "Rayleigh nominal mapping selected: -59.40,-56.04,-52.15,-49.17,-46.04,-42.16,-37.79,-32.58 -> 5,10,20,30,40,50,60,70 percent. Worst Rayleigh condition is labeled 70%%.");

validateMetricData(logFid, allData, algorithmOrder);

%% Metric definitions
metricNames = ["max_agent_steps","total_team_steps","team_messages_per_step", ...
    "max_agent_messages","messages_per_unique_cell","unique_cell_contribution_gini", ...
    "team_task_replans","team_path_replans","system_cell_revisits","duplicate_target_visits", ...
    "target_completion_gini","messages_per_target"];

metricCols = ["scenario","metric","metric_family","result_type","comm_model","comm_level_raw", ...
    "comm_level_pct","algorithm","total_trial_count","eligible_paired_trials","excluded_trials", ...
    "mean_value","median_value","standard_deviation","ci95_low","ci95_high","field_mean", ...
    "absolute_advantage_vs_field","percent_advantage_vs_field","units","lower_is_better", ...
    "source_column","inclusion_rule","notes"];
statCols = ["family_id","scenario","metric","metric_family","result_type","comm_model","comm_level_pct", ...
    "test_type","n_trials","n_algorithms","algorithm_a","algorithm_b","algorithm_a_mean", ...
    "algorithm_b_mean","mean_difference_b_minus_a","median_difference_b_minus_a", ...
    "percent_advantage_algorithm_a","difference_ci95_low","difference_ci95_high", ...
    "friedman_chi_square","friedman_df","friedman_p","friedman_significant_0_05","kendall_w", ...
    "wilcoxon_w_positive","wilcoxon_w_negative","wilcoxon_p_raw","wilcoxon_p_holm", ...
    "reject_raw_0_05","reject_holm_0_05","rank_biserial","units","notes"];
metricRows = cell(0, numel(metricCols));
statRows = cell(0, numel(statCols));

fprintf("Calculating condition-specific paired comparisons...\n");
scenarios = unique(allData.scenario, "stable")';
for s = 1:numel(scenarios)
    scenario = scenarios(s);
    scenarioData = allData(allData.scenario == scenario, :);
    scenarioMetrics = metricsForScenario(scenario);
    conditions = unique(scenarioData(:, ["comm_model","comm_level_raw","comm_level_pct","is_ideal"]), "rows", "stable");
    conditions = sortrows(conditions, ["comm_model","comm_level_pct"]);
    for m = 1:numel(scenarioMetrics)
        metric = scenarioMetrics(m);
        for c = 1:height(conditions)
            cond = conditions(c, :);
            [V, trialIDs, totalTrialCount] = conditionMetricMatrix(scenarioData, metric, cond, algorithmOrder);
            [metricRows, bootMeans] = addConditionMetricRows(metricRows, scenario, metric, cond, V, ...
                totalTrialCount, bootstrapIterations, algorithmOrder);
            statRows = addStatisticalRows(statRows, scenario, metric, "condition_metric", cond.comm_model, ...
                cond.comm_level_pct, V, bootstrapIterations, algorithmOrder, bootMeans);
        end
    end
end

fprintf("Calculating PRDA and PRDS degradation summaries...\n");
for s = 1:numel(scenarios)
    scenario = scenarios(s);
    scenarioData = allData(allData.scenario == scenario, :);
    scenarioMetrics = metricsForScenario(scenario);
    for m = 1:numel(scenarioMetrics)
        metric = scenarioMetrics(m);
        for d = 1:numel(degradationModels)
            model = degradationModels(d);
            [prdaV, prdsV, trialIDs, totalTrialCount] = degradationMatrices(scenarioData, metric, model, ...
                algorithmOrder, nominalLevels);
            [metricRows, prdaBootMeans] = addDegradationMetricRows(metricRows, scenario, metric, "prda", model, prdaV, ...
                totalTrialCount, bootstrapIterations, algorithmOrder);
            [metricRows, prdsBootMeans] = addDegradationMetricRows(metricRows, scenario, metric, "prds", model, prdsV, ...
                totalTrialCount, bootstrapIterations, algorithmOrder);
            statRows = addStatisticalRows(statRows, scenario, metric, "prda", model, ...
                NaN, prdaV, bootstrapIterations, algorithmOrder, prdaBootMeans);
            statRows = addStatisticalRows(statRows, scenario, metric, "prds", model, ...
                NaN, prdsV, bootstrapIterations, algorithmOrder, prdsBootMeans);
        end
    end
end

%% Write outputs
metricTable = rowsToMetricTable(metricRows, metricCols);
statTable = rowsToStatTable(statRows, statCols);
manifestTable = rowsToManifestTable(manifestRows);

if dctaAnalysisRunMode == "coverage_append_only"
    existingMetricTable = readtable(metricCsvPath, "TextType", "string");
    existingStatTable = readtable(statCsvPath, "TextType", "string");
    existingMetricTable = existingMetricTable(~contains(lower(existingMetricTable.scenario), "coverage"), :);
    existingStatTable = existingStatTable(~contains(lower(existingStatTable.scenario), "coverage"), :);
    metricTable = [existingMetricTable; metricTable];
    statTable = [existingStatTable; statTable];
    logLine(logFid, "Preserved existing non-coverage metric rows: %d", height(existingMetricTable));
    logLine(logFid, "Preserved existing non-coverage statistical rows: %d", height(existingStatTable));
    logLine(logFid, "Appended refreshed coverage metric rows: %d", height(metricTable) - height(existingMetricTable));
    logLine(logFid, "Appended refreshed coverage statistical rows: %d", height(statTable) - height(existingStatTable));
end

writetable(metricTable, metricCsvPath);
writetable(statTable, statCsvPath);
writetable(manifestTable, manifestPath);

logCounts(logFid, allData, metricTable, algorithmOrder, nominalLevels);
logLine(logFid, "Output metric CSV: %s", metricCsvPath);
logLine(logFid, "Output statistical test CSV: %s", statCsvPath);
logLine(logFid, "Output source manifest CSV: %s", manifestPath);
logLine(logFid, "Output analysis log: %s", logPath);

%% Required final validation
fprintf("Validating generated CSV outputs...\n");
metricGenerated = readtable(metricCsvPath, "TextType", "string");
statGenerated = readtable(statCsvPath, "TextType", "string");
validation = validateTwoFileOutputs(metricGenerated, statGenerated, metricNames, algorithmOrder, logFid);

fprintf("\nValidation summary\n");
fprintf("  Metric rows: %d\n", height(metricGenerated));
fprintf("  Statistical rows: %d\n", height(statGenerated));
fprintf("  Statistical families: %d\n", validation.familyCount);
fprintf("  Friedman omnibus rows: %d\n", validation.omnibusRows);
fprintf("  Wilcoxon pairwise rows: %d\n", validation.pairwiseRows);
fprintf("  Coverage rows: %d\n", validation.coverageRows);
fprintf("  Requested metrics found: %d of %d\n", validation.metricFoundCount, numel(metricNames));
fprintf("  Family structure valid: %d\n", validation.familyStructureValid);
fprintf("  Manual spot checks completed: %d\n", validation.manualSpotChecks);

disp("First condition_metric rows:");
conditionPreview = metricGenerated(metricGenerated.result_type == "condition_metric", 1:min(width(metricGenerated), 12));
disp(conditionPreview(1:min(6, height(conditionPreview)), :));
disp("First PRDA rows:");
prdaPreview = metricGenerated(metricGenerated.result_type == "prda", 1:min(width(metricGenerated), 12));
disp(prdaPreview(1:min(6, height(prdaPreview)), :));
disp("First PRDS rows:");
prdsPreview = metricGenerated(metricGenerated.result_type == "prds", 1:min(width(metricGenerated), 12));
disp(prdsPreview(1:min(6, height(prdsPreview)), :));
disp("First statistical test rows:");
statPreview = statGenerated(:, 1:min(width(statGenerated), 12));
disp(statPreview(1:min(8, height(statPreview)), :));

fprintf("\nGenerated outputs:\n");
fprintf("  %s\n", metricCsvPath);
fprintf("  %s\n", statCsvPath);
fprintf("  %s\n", logPath);

if validation.coverageRows <= 0 || validation.metricFoundCount ~= numel(metricNames) || ...
        validation.familyStructureValid ~= 1 || validation.numericRangesValid ~= 1 || ...
        validation.noTostRows ~= 1 || validation.manualSpotChecks ~= 4
    error("Generated output validation failed. See %s.", logPath);
end

fprintf("DCTA paired metric analysis completed successfully.\n");

%% Local helper functions
function [T, manifestRows] = readSourceTable(manifestRows, scenario, role, path, selected, reason)
    T = readtable(path, "FileType", "text", "Delimiter", ",", "ReadVariableNames", true, ...
        "NumHeaderLines", 0, "TextType", "string");
    important = strjoin(string(T.Properties.VariableNames), ",");
    manifestRows = addManifestRow(manifestRows, scenario, role, path, height(T), width(T), ...
        selected, reason, important, false, "");
end

function [T, manifestRows] = readSourceTableParts(manifestRows, scenario, role, folder, pattern, selected, reason)
    files = dir(fullfile(folder, pattern));
    if isempty(files)
        error("No source parts matched %s", fullfile(folder, pattern));
    end
    [~, order] = sort(string({files.name}));
    files = files(order);
    tables = cell(numel(files), 1);
    expectedVars = strings(0, 1);
    for k = 1:numel(files)
        path = fullfile(files(k).folder, files(k).name);
        tables{k} = readtable(path, "FileType", "text", "Delimiter", ",", ...
            "ReadVariableNames", true, "NumHeaderLines", 0, "TextType", "string");
        vars = string(tables{k}.Properties.VariableNames);
        if k == 1
            expectedVars = vars;
        elseif ~isequal(vars, expectedVars)
            error("CSV part header mismatch in %s", path);
        end
        manifestRows = addManifestRow(manifestRows, scenario, role, path, ...
            height(tables{k}), width(tables{k}), selected, reason, ...
            strjoin(vars, ","), false, "Ordered CSV part");
    end
    T = vertcat(tables{:});
end

function rows = addManifestRow(rows, scenario, role, path, rowCount, colCount, selected, reason, important, duplicate, notes)
    [~, fileName, ext] = fileparts(path);
    rows(end+1, :) = {string(scenario), string(role), string(path), string(string(fileName) + string(ext)), ...
        rowCount, colCount, logical(selected), string(reason), string(important), ...
        logical(duplicate), string(notes)};
end

function T = normalizeSourceTable(T)
    vars = string(T.Properties.VariableNames);
    textVars = ["trial_id","algorithm","comm_model","comm_level","comm_label","trial_status", ...
        "trial_mode","stage","environment","algorithm_key","condition_id","scenario_file", ...
        "out_dir","run_id","first_clue_robot","target_found_by_robot"];
    for v = textVars
        if any(vars == v)
            T.(v) = string(T.(v));
            T.(v) = standardizeMissing(T.(v), ["<missing>","missing","NaN","nan"]);
        end
    end
    if any(vars == "trial_id")
        T.trial_id = string(T.trial_id);
    end
    if any(vars == "algorithm")
        T.algorithm = normalizeAlgorithm(T.algorithm);
    end
    if any(vars == "comm_model")
        T.comm_model = lower(string(T.comm_model));
    end
    if any(vars == "comm_level")
        T.comm_level_raw = normalizeCommRaw(T.comm_level, T.comm_model);
    elseif any(vars == "comm_label")
        T.comm_level_raw = strings(height(T), 1);
    else
        T.comm_level_raw = strings(height(T), 1);
    end
    if any(vars == "comm_label")
        T.comm_label = string(T.comm_label);
    else
        T.comm_label = strings(height(T), 1);
    end
    T.comm_level_pct = nominalCommPct(T.comm_model, T.comm_level_raw, T.comm_label);
    T.is_ideal = T.comm_model == "ideal";
end

function alg = normalizeAlgorithm(alg)
    alg = upper(strtrim(string(alg)));
    alg(alg == "A-CBBA") = "ACBBA";
    alg(alg == "D-MCHBA") = "DMCHBA";
end

function raw = normalizeCommRaw(level, model)
    n = numel(model);
    raw = strings(n, 1);
    if isnumeric(level)
        for i = 1:n
            if model(i) == "ideal" || isnan(level(i))
                raw(i) = "ideal";
            else
                raw(i) = stripZeros(level(i));
            end
        end
    else
        level = string(level);
        for i = 1:n
            if model(i) == "ideal" || ismissing(level(i)) || strlength(strtrim(level(i))) == 0
                raw(i) = "ideal";
            else
                raw(i) = stripZeros(str2double(level(i)));
            end
        end
    end
end

function pct = nominalCommPct(model, raw, label)
    pct = NaN(numel(model), 1);
    rayRaw = [-59.40 -56.04 -52.15 -49.17 -46.04 -42.16 -37.79 -32.58];
    rayPct = [5 10 20 30 40 50 60 70];
    for i = 1:numel(model)
        m = model(i);
        r = str2double(raw(i));
        if m == "ideal"
            pct(i) = 0;
        elseif m == "bernoulli"
            pct(i) = round(100 * r);
        elseif m == "gilbert_elliott"
            pct(i) = round(100 * (1 - r));
        elseif m == "rayleigh_style"
            [delta, idx] = min(abs(rayRaw - r));
            if delta < 0.02
                pct(i) = rayPct(idx);
            else
                pct(i) = parsePctFromLabel(label(i));
            end
        else
            pct(i) = NaN;
        end
    end
end

function out = parsePctFromLabel(label)
    label = string(label);
    tokens = regexp(label, "(\d+)$", "tokens", "once");
    if isempty(tokens)
        out = NaN;
    else
        out = str2double(tokens{1});
    end
end

function s = stripZeros(x)
    if isnan(x)
        s = "";
    else
        s = string(regexprep(sprintf("%.10g", x), "\.?0+$", ""));
    end
end

function logScenarioIdentity(fid, scenario, folder, systemT, trialT, manifestT)
    logLine(fid, "%s source folder: %s", scenario, folder);
    logLine(fid, "%s system trial_mode values: %s", scenario, joinUnique(systemT, "trial_mode"));
    logLine(fid, "%s trial environment values: %s", scenario, joinUnique(trialT, "environment"));
    logLine(fid, "%s manifest stage values: %s", scenario, joinUnique(manifestT, "stage"));
    logLine(fid, "%s manifest communication labels: %s", scenario, joinUnique(manifestT, "comm_label"));
end

function assertAlgorithms(fid, scenario, manifestT, expectedAlgorithms)
    found = unique(manifestT.algorithm, "stable")';
    logLine(fid, "%s algorithms found: %s", scenario, strjoin(found, ", "));
    missing = setdiff(expectedAlgorithms, found);
    extra = setdiff(found, expectedAlgorithms);
    if ~isempty(missing) || ~isempty(extra)
        error("%s algorithm set mismatch. Missing: %s Extra: %s", scenario, strjoin(missing, ","), strjoin(extra, ","));
    end
end

function out = joinUnique(T, varName)
    if any(string(T.Properties.VariableNames) == varName)
        vals = unique(string(T.(varName)), "stable")';
        vals = vals(~ismissing(vals) & strlength(vals) > 0);
        out = strjoin(vals, ", ");
    else
        out = "<missing column>";
    end
end

function data = buildMetricData(scenario, systemT, trialT, robotT, algorithmOrder, fid)
    keyVars = ["trial_id","algorithm","comm_model","comm_level_raw"];
    systemT.scenario = repmat(string(scenario), height(systemT), 1);
    trialT.scenario = repmat(string(scenario), height(trialT), 1);
    robotT.scenario = repmat(string(scenario), height(robotT), 1);
    keyVarsWithScenario = ["scenario", keyVars];

    dupSystem = duplicateKeyCount(systemT, keyVarsWithScenario);
    logLine(fid, "%s duplicate system primary keys: %d", scenario, dupSystem);
    if dupSystem > 0
        error("%s has duplicate system primary keys.", scenario);
    end

    robotAgg = aggregateRobotMetrics(robotT, keyVarsWithScenario);
    data = outerjoin(systemT, robotAgg, "Keys", keyVarsWithScenario, "MergeKeys", true, "Type", "left");

    if scenario == "Bayesian clue-informed search"
        trialKeep = trialT(:, [keyVarsWithScenario, "first_clue_robot", "trial_status"]);
        trialKeep.Properties.VariableNames(end-1:end) = ["trial_first_clue_robot","trial_trial_status"];
        data = outerjoin(data, trialKeep, "Keys", keyVarsWithScenario, "MergeKeys", true, "Type", "left");
        clueFirst = ~ismissing(data.trial_first_clue_robot) & strlength(strtrim(data.trial_first_clue_robot)) > 0;
        data.base_eligible = lower(string(data.trial_status)) == "completed" & ...
            lower(string(data.trial_trial_status)) == "completed" & clueFirst;
    elseif scenario == "Coverage area search"
        trialKeep = trialT(:, [keyVarsWithScenario, "trial_status"]);
        trialKeep.Properties.VariableNames(end) = "trial_trial_status";
        data = outerjoin(data, trialKeep, "Keys", keyVarsWithScenario, "MergeKeys", true, "Type", "left");
        data.base_eligible = lower(string(data.trial_status)) == "completed" & ...
            lower(string(data.trial_trial_status)) == "completed";
    else
        data.base_eligible = lower(string(data.trial_status)) == "completed" & ...
            toLogical(data.all_targets_visited) & ...
            toDouble(data.completed_target_count) == toDouble(data.target_count);
    end

    data.max_agent_steps = selectFirstNumeric(data, ["max_steps_any_robot","max_robot_steps","derived_max_steps_any_robot"]);
    data.total_team_steps_metric = selectFirstNumeric(data, ["total_team_steps","derived_total_team_steps"]);
    data.messages_sent_total_metric = toDouble(data.messages_sent_total);
    data.team_messages_per_step = safeDivide(data.messages_sent_total_metric, data.total_team_steps_metric);
    data.max_agent_messages = selectFirstNumeric(data, ["derived_max_messages_any_robot","max_messages_any_robot"]);

    if scenario == "Bayesian clue-informed search" || scenario == "Coverage area search"
        data.messages_per_unique_cell_metric = selectFirstNumeric(data, ["messages_per_unique_cell"]);
        missingMsgUnique = isnan(data.messages_per_unique_cell_metric);
        data.messages_per_unique_cell_metric(missingMsgUnique) = safeDivide(data.messages_sent_total_metric(missingMsgUnique), toDouble(data.unique_cells_searched(missingMsgUnique)));
        data.system_cell_revisits = toDouble(data.system_revisits);
        data.duplicate_target_visits = NaN(height(data), 1);
        data.target_completion_gini = NaN(height(data), 1);
        data.messages_per_target = NaN(height(data), 1);
    else
        data.messages_per_unique_cell_metric = safeDivide(data.messages_sent_total_metric, toDouble(data.unique_cells_visited));
        data.system_cell_revisits = NaN(height(data), 1);
        data.duplicate_target_visits = toDouble(data.duplicate_target_visits);
        data.target_completion_gini = selectFirstNumeric(data, ["workload_gini_targets_found","derived_target_completion_gini"]);
        data.messages_per_target = safeDivide(data.messages_sent_total_metric, toDouble(data.completed_target_count));
    end

    data.unique_cell_contribution_gini = selectFirstNumeric(data, ["workload_gini_unique_cells_contributed","derived_unique_cell_contribution_gini"]);
    data.team_task_replans = toDouble(data.task_cell_replans_total);
    data.team_path_replans = toDouble(data.path_replans_total);

    data.metric_max_agent_steps = data.max_agent_steps;
    data.metric_total_team_steps = data.total_team_steps_metric;
    data.metric_team_messages_per_step = data.team_messages_per_step;
    data.metric_max_agent_messages = data.max_agent_messages;
    data.metric_messages_per_unique_cell = data.messages_per_unique_cell_metric;
    data.metric_unique_cell_contribution_gini = data.unique_cell_contribution_gini;
    data.metric_team_task_replans = data.team_task_replans;
    data.metric_team_path_replans = data.team_path_replans;
    data.metric_system_cell_revisits = data.system_cell_revisits;
    data.metric_duplicate_target_visits = data.duplicate_target_visits;
    data.metric_target_completion_gini = data.target_completion_gini;
    data.metric_messages_per_target = data.messages_per_target;

    foundAlgorithms = unique(data.algorithm, "stable")';
    missing = setdiff(algorithmOrder, foundAlgorithms);
    if ~isempty(missing)
        error("%s missing algorithms in system data: %s", scenario, strjoin(missing, ","));
    end
end

function robotAgg = aggregateRobotMetrics(robotT, keyVars)
    [G, scenarioKey, trialKey, algorithmKey, modelKey, rawKey] = findgroups( ...
        robotT.scenario, robotT.trial_id, robotT.algorithm, robotT.comm_model, robotT.comm_level_raw);
    scenarioKey = scenarioKey(:);
    trialKey = trialKey(:);
    algorithmKey = algorithmKey(:);
    modelKey = modelKey(:);
    rawKey = rawKey(:);
    keyTable = table(scenarioKey, trialKey, algorithmKey, modelKey, rawKey, ...
        'VariableNames', cellstr(keyVars));
    maxMsg = splitapply(@maxNoNan, toDouble(robotT.messages_sent), G);
    maxSteps = splitapply(@maxNoNan, toDouble(robotT.steps_total), G);
    totalSteps = splitapply(@sumNoNan, toDouble(robotT.steps_total), G);
    uniqueGini = splitapply(@giniLocal, toDouble(robotT.unique_cells_contributed), G);
    robotAgg = keyTable;
    robotAgg.derived_max_messages_any_robot = maxMsg;
    robotAgg.derived_max_steps_any_robot = maxSteps;
    robotAgg.derived_total_team_steps = totalSteps;
    robotAgg.derived_unique_cell_contribution_gini = uniqueGini;
    if any(string(robotT.Properties.VariableNames) == "targets_found")
        targetGini = splitapply(@giniLocal, toDouble(robotT.targets_found), G);
        robotAgg.derived_target_completion_gini = targetGini;
    else
        robotAgg.derived_target_completion_gini = NaN(height(robotAgg), 1);
    end
end

function validateMetricData(fid, data, algorithmOrder)
    logLine(fid, "Validation: total metric-ready rows: %d", height(data));
    logLine(fid, "Validation: scenarios present: %s", strjoin(unique(data.scenario, "stable")', ", "));
    logLine(fid, "Validation: communication models present: %s", strjoin(unique(data.comm_model, "stable")', ", "));
    logLine(fid, "Validation: algorithms present: %s", strjoin(unique(data.algorithm, "stable")', ", "));
    if any(data.messages_sent_total_metric < 0)
        error("Negative message totals found.");
    end
    if any(data.total_team_steps_metric < 0) || any(data.max_agent_steps < 0)
        error("Negative step totals found.");
    end
    badGini = (data.unique_cell_contribution_gini < 0 | data.unique_cell_contribution_gini > 1) & ~isnan(data.unique_cell_contribution_gini);
    badGini = badGini | ((data.target_completion_gini < 0 | data.target_completion_gini > 1) & ~isnan(data.target_completion_gini));
    if any(badGini)
        error("Gini values outside [0,1] found.");
    end
    badSteps = data.max_agent_steps > data.total_team_steps_metric & ~isnan(data.max_agent_steps) & ~isnan(data.total_team_steps_metric);
    if any(badSteps)
        error("Maximum-agent steps exceed total team steps.");
    end
    badMsgs = data.max_agent_messages > data.messages_sent_total_metric & ~isnan(data.max_agent_messages) & ~isnan(data.messages_sent_total_metric);
    if any(badMsgs)
        error("Maximum-agent messages exceed total team messages.");
    end
    badDup = data.duplicate_target_visits < 0 & ~isnan(data.duplicate_target_visits);
    if any(badDup)
        error("Negative duplicate target visits found.");
    end
    for s = unique(data.scenario, "stable")'
        sub = data(data.scenario == s, :);
        for model = ["ideal","bernoulli","gilbert_elliott","rayleigh_style"]
            if any(sub.comm_model == model)
                levels = unique(sub.comm_level_pct(sub.comm_model == model))';
                logLine(fid, "%s %s nominal levels present: %s", s, model, mat2str(levels));
            end
        end
        found = unique(sub.algorithm, "stable")';
        missing = setdiff(algorithmOrder, found);
        if ~isempty(missing)
            error("%s missing algorithms after metric normalization: %s", s, strjoin(missing, ","));
        end
    end
    coverageRows = data.scenario == "Coverage area search";
    if any(coverageRows)
        coverageTargetVals = [data.metric_duplicate_target_visits(coverageRows), ...
            data.metric_target_completion_gini(coverageRows), data.metric_messages_per_target(coverageRows)];
        if any(isfinite(coverageTargetVals), "all")
            error("Coverage scenario contains target-domain metric values.");
        end
    end
end

function metrics = metricsForScenario(scenario)
    shared = ["max_agent_steps","total_team_steps","team_messages_per_step", ...
        "max_agent_messages","messages_per_unique_cell","unique_cell_contribution_gini", ...
        "team_task_replans","team_path_replans"];
    if scenario == "Bayesian clue-informed search" || scenario == "Coverage area search"
        metrics = [shared, "system_cell_revisits"];
    else
        metrics = [shared, "duplicate_target_visits","target_completion_gini","messages_per_target"];
    end
end

function [V, trialIDs, totalTrialCount] = conditionMetricMatrix(data, metric, cond, algorithmOrder)
    metricVar = "metric_" + metric;
    mask = data.comm_model == cond.comm_model & data.comm_level_pct == cond.comm_level_pct & ...
        data.comm_level_raw == cond.comm_level_raw;
    sub = data(mask, :);
    totalTrialCount = numel(unique(sub.trial_id));
    sub = sub(sub.base_eligible, :);
    [V, trialIDs] = makeAlgorithmMatrix(sub, metricVar, algorithmOrder, true);
end

function [V, trialIDs] = makeAlgorithmMatrix(sub, metricVar, algorithmOrder, requireFinite)
    allTrials = unique(sub.trial_id, "stable");
    mat = NaN(numel(allTrials), numel(algorithmOrder));
    for r = 1:height(sub)
        t = find(allTrials == sub.trial_id(r), 1);
        a = find(algorithmOrder == sub.algorithm(r), 1);
        if ~isempty(t) && ~isempty(a)
            mat(t, a) = sub.(metricVar)(r);
        end
    end
    complete = all(~isnan(mat), 2);
    if requireFinite
        complete = complete & all(isfinite(mat), 2);
    end
    V = mat(complete, :);
    trialIDs = allTrials(complete);
end

function rows = addConditionResultRows(rows, scenario, metric, cond, V, trialIDs, totalTrialCount, B, algorithmOrder)
    n = size(V, 1);
    excluded = totalTrialCount - n;
    family = metricFamily(metric);
    units = metricUnits(metric);
    sourceColumn = metricSourceColumn(scenario, metric);
    inclusionRule = conditionInclusionRule(scenario);
    notes = "Positive advantage means the focal algorithm is lower/better on the paired trial set.";
    offset = metricOffset(metric);
    lowerIsBetter = true;
    bootMeans = bootstrapMeans(V, B);
    field = mean(V, 2);
    bootField = mean(bootMeans, 2, "omitnan");

    for a = 1:numel(algorithmOrder)
        vals = V(:, a);
        [ciLow, ciHigh] = meanCiFromBootstrap(bootMeans(:, a));
        rows(end+1, :) = resultRow(scenario, metric, family, "condition_metric", "algorithm_summary", ...
            cond.comm_model, cond.comm_level_raw, cond.comm_level_pct, cond.is_ideal, ...
            algorithmOrder(a), "", "", totalTrialCount, n, excluded, ...
            meanNoNan(vals), NaN, medianNoNan(vals), NaN, NaN, NaN, NaN, NaN, NaN, ...
            NaN, NaN, NaN, NaN, ciLow, ciHigh, NaN, NaN, offset, lowerIsBetter, units, sourceColumn, inclusionRule, notes);
    end

    for a = 1:numel(algorithmOrder)
        focal = V(:, a);
        for b = 1:numel(algorithmOrder)
            if a == b
                continue;
            end
            comp = V(:, b);
            diff = comp - focal;
            bootDiff = bootMeans(:, b) - bootMeans(:, a);
            [ciLow, ciHigh] = meanCiFromBootstrap(bootDiff);
            [pctLow, pctHigh] = percentCi(bootMeans(:, a), bootMeans(:, b));
            [fciLow, fciHigh] = meanCiFromBootstrap(bootMeans(:, a));
            [cciLow, cciHigh] = meanCiFromBootstrap(bootMeans(:, b));
            pct = percentAdvantage(meanNoNan(focal), meanNoNan(comp));
            rows(end+1, :) = resultRow(scenario, metric, family, "condition_metric", "algorithm_pair", ...
                cond.comm_model, cond.comm_level_raw, cond.comm_level_pct, cond.is_ideal, ...
                algorithmOrder(a), algorithmOrder(b), canonicalPair(algorithmOrder(a), algorithmOrder(b)), ...
                totalTrialCount, n, excluded, meanNoNan(focal), meanNoNan(comp), medianNoNan(focal), medianNoNan(comp), ...
                meanNoNan(diff), medianNoNan(diff), pct, stdNoNan(diff), seNoNan(diff), ciLow, ciHigh, pctLow, pctHigh, ...
                fciLow, fciHigh, cciLow, cciHigh, offset, lowerIsBetter, units, sourceColumn, inclusionRule, notes);
        end
    end

    for a = 1:numel(algorithmOrder)
        focal = V(:, a);
        diff = field - focal;
        bootDiff = bootField - bootMeans(:, a);
        [ciLow, ciHigh] = meanCiFromBootstrap(bootDiff);
        [pctLow, pctHigh] = percentCi(bootMeans(:, a), bootField);
        [fciLow, fciHigh] = meanCiFromBootstrap(bootMeans(:, a));
        [cciLow, cciHigh] = meanCiFromBootstrap(bootField);
        pct = percentAdvantage(meanNoNan(focal), meanNoNan(field));
        rows(end+1, :) = resultRow(scenario, metric, family, "condition_metric", "vs_field_mean", ...
            cond.comm_model, cond.comm_level_raw, cond.comm_level_pct, cond.is_ideal, ...
            algorithmOrder(a), "FIELD_MEAN", algorithmOrder(a) + "__FIELD_MEAN", ...
            totalTrialCount, n, excluded, meanNoNan(focal), meanNoNan(field), medianNoNan(focal), medianNoNan(field), ...
            meanNoNan(diff), medianNoNan(diff), pct, stdNoNan(diff), seNoNan(diff), ciLow, ciHigh, pctLow, pctHigh, ...
            fciLow, fciHigh, cciLow, cciHigh, offset, lowerIsBetter, units, sourceColumn, inclusionRule, ...
            "Graph-helper comparison against the six-algorithm trial mean; not for formal pairwise claims.");
    end
end

function [prdaV, prdsV, trialIDs, totalTrialCount] = degradationMatrices(data, metric, model, algorithmOrder, levels)
    metricVar = "metric_" + metric;
    offset = metricOffset(metric);
    totalTrialCount = numel(unique(data.trial_id));
    curveMask = (data.comm_model == "ideal" & data.comm_level_pct == 0) | ...
        (data.comm_model == model & ismember(data.comm_level_pct, levels(2:end)));
    sub = data(curveMask & data.base_eligible, :);
    allTrials = unique(sub.trial_id, "stable");
    prda = NaN(numel(allTrials), numel(algorithmOrder));
    prds = NaN(numel(allTrials), numel(algorithmOrder));
    complete = false(numel(allTrials), 1);

    for t = 1:numel(allTrials)
        Y = NaN(numel(levels), numel(algorithmOrder));
        for l = 1:numel(levels)
            if levels(l) == 0
                levelMask = sub.trial_id == allTrials(t) & sub.comm_model == "ideal" & sub.comm_level_pct == 0;
            else
                levelMask = sub.trial_id == allTrials(t) & sub.comm_model == model & sub.comm_level_pct == levels(l);
            end
            levelRows = sub(levelMask, :);
            for a = 1:numel(algorithmOrder)
                idx = find(levelRows.algorithm == algorithmOrder(a), 1);
                if ~isempty(idx)
                    Y(l, a) = levelRows.(metricVar)(idx);
                end
            end
        end
        if all(isfinite(Y), "all") && (offset > 0 || all(Y > 0, "all"))
            Z = log(Y + offset);
            Zfield = mean(Z, 2);
            R = Z - Zfield;
            D = R - R(1, :);
            for a = 1:numel(algorithmOrder)
                prda(t, a) = 100 * trapz(levels, D(:, a)) / 70;
                p = polyfit(levels, Z(:, a)', 1);
                prds(t, a) = 100 * (exp(p(1)) - 1);
            end
            complete(t) = true;
        end
    end
    prdaV = prda(complete, :);
    prdsV = prds(complete, :);
    trialIDs = allTrials(complete);
end

function rows = addDegradationResultRows(rows, scenario, metric, resultType, model, V, trialIDs, totalTrialCount, B, algorithmOrder)
    n = size(V, 1);
    excluded = totalTrialCount - n;
    family = metricFamily(metric);
    if resultType == "prda"
        units = "prda_percentage_points";
        notes = "PRDA lower is more robust; positive pair advantage means focal has lower PRDA than comparator.";
    else
        units = "percent_metric_change_per_1pct_degradation";
        notes = "PRDS lower is more robust; positive pair advantage means focal degrades more slowly than comparator.";
    end
    sourceColumn = metricSourceColumn(scenario, metric);
    inclusionRule = "Balanced degradation curve: ideal plus all eight degraded nominal levels, all six algorithms, eligible rows, and finite metric values.";
    offset = metricOffset(metric);
    lowerIsBetter = true;
    bootMeans = bootstrapMeans(V, B);

    for a = 1:numel(algorithmOrder)
        vals = V(:, a);
        [ciLow, ciHigh] = meanCiFromBootstrap(bootMeans(:, a));
        rows(end+1, :) = resultRow(scenario, metric, family, resultType, "algorithm_summary", ...
            model, "", NaN, false, algorithmOrder(a), "", "", totalTrialCount, n, excluded, ...
            meanNoNan(vals), NaN, medianNoNan(vals), NaN, NaN, NaN, NaN, stdNoNan(vals), seNoNan(vals), ...
            NaN, NaN, NaN, NaN, ciLow, ciHigh, NaN, NaN, offset, lowerIsBetter, units, sourceColumn, inclusionRule, notes);
    end

    for a = 1:numel(algorithmOrder)
        focal = V(:, a);
        for b = 1:numel(algorithmOrder)
            if a == b
                continue;
            end
            comp = V(:, b);
            diff = comp - focal;
            bootDiff = bootMeans(:, b) - bootMeans(:, a);
            [ciLow, ciHigh] = meanCiFromBootstrap(bootDiff);
            [fciLow, fciHigh] = meanCiFromBootstrap(bootMeans(:, a));
            [cciLow, cciHigh] = meanCiFromBootstrap(bootMeans(:, b));
            rows(end+1, :) = resultRow(scenario, metric, family, resultType, "algorithm_pair", ...
                model, "", NaN, false, algorithmOrder(a), algorithmOrder(b), canonicalPair(algorithmOrder(a), algorithmOrder(b)), ...
                totalTrialCount, n, excluded, meanNoNan(focal), meanNoNan(comp), medianNoNan(focal), medianNoNan(comp), ...
                meanNoNan(diff), medianNoNan(diff), NaN, stdNoNan(diff), seNoNan(diff), ciLow, ciHigh, NaN, NaN, ...
                fciLow, fciHigh, cciLow, cciHigh, offset, lowerIsBetter, units, sourceColumn, inclusionRule, notes);
        end
    end
end

function [rows, bootMeans] = addConditionMetricRows(rows, scenario, metric, cond, V, totalTrialCount, B, algorithmOrder)
    n = size(V, 1);
    excluded = totalTrialCount - n;
    family = metricFamily(metric);
    units = metricUnits(metric);
    sourceColumn = metricSourceColumn(scenario, metric);
    inclusionRule = conditionInclusionRule(scenario);
    notes = "Condition metric summary from paired eligible trials. Positive field advantage means the algorithm is lower/better than the six-algorithm trial mean.";
    bootMeans = bootstrapMeans(V, B);
    field = mean(V, 2);
    bootField = mean(bootMeans, 2, "omitnan");
    fieldMean = meanNoNan(field);

    for a = 1:numel(algorithmOrder)
        vals = V(:, a);
        [ciLow, ciHigh] = meanCiFromBootstrap(bootMeans(:, a));
        fieldAdv = field - vals;
        pctAdv = percentAdvantage(meanNoNan(vals), fieldMean);
        rows(end+1, :) = metricRow(scenario, metric, family, "condition_metric", cond.comm_model, ...
            cond.comm_level_raw, cond.comm_level_pct, algorithmOrder(a), totalTrialCount, n, excluded, ...
            meanNoNan(vals), medianNoNan(vals), stdNoNan(vals), ciLow, ciHigh, fieldMean, ...
            meanNoNan(fieldAdv), pctAdv, units, true, sourceColumn, inclusionRule, notes);
    end
end

function [rows, bootMeans] = addDegradationMetricRows(rows, scenario, metric, resultType, model, V, totalTrialCount, B, algorithmOrder)
    n = size(V, 1);
    excluded = totalTrialCount - n;
    family = metricFamily(metric);
    if resultType == "prda"
        units = "prda_percentage_points";
        notes = "Trial-level PRDA summary from complete balanced degradation curves; lower is more robust.";
    else
        units = "percent_metric_change_per_1pct_degradation";
        notes = "Trial-level PRDS summary from complete balanced degradation curves; lower is more robust.";
    end
    sourceColumn = metricSourceColumn(scenario, metric);
    inclusionRule = "Balanced degradation curve: ideal plus all eight degraded nominal levels, all six algorithms, eligible rows, and finite metric values.";
    bootMeans = bootstrapMeans(V, B);
    for a = 1:numel(algorithmOrder)
        vals = V(:, a);
        [ciLow, ciHigh] = meanCiFromBootstrap(bootMeans(:, a));
        rows(end+1, :) = metricRow(scenario, metric, family, resultType, model, "", NaN, ...
            algorithmOrder(a), totalTrialCount, n, excluded, meanNoNan(vals), medianNoNan(vals), ...
            stdNoNan(vals), ciLow, ciHigh, NaN, NaN, NaN, units, true, sourceColumn, inclusionRule, notes);
    end
end

function row = metricRow(scenario, metric, family, resultType, commModel, commRaw, commPct, algorithm, totalCount, eligibleCount, excludedCount, meanValue, medianValue, sdValue, ciLow, ciHigh, fieldMean, fieldAdv, pctFieldAdv, units, lowerIsBetter, sourceColumn, inclusionRule, notes)
    row = {string(scenario), string(metric), string(family), string(resultType), string(commModel), ...
        string(commRaw), commPct, string(algorithm), totalCount, eligibleCount, excludedCount, ...
        meanValue, medianValue, sdValue, ciLow, ciHigh, fieldMean, fieldAdv, pctFieldAdv, ...
        string(units), logical(lowerIsBetter), string(sourceColumn), string(inclusionRule), string(notes)};
end

function rows = addStatisticalRows(rows, scenario, metric, resultType, commModel, commPct, V, B, algorithmOrder, bootMeans)
    family = metricFamily(metric);
    units = statisticalUnits(metric, resultType);
    familyId = makeFamilyId(scenario, metric, resultType, commModel, commPct);
    n = size(V, 1);
    k = numel(algorithmOrder);
    [friedmanChi, friedmanDf, friedmanP, kendallW] = friedmanLocal(V);
    friedmanSig = isfinite(friedmanP) && friedmanP < 0.05;
    notes = "All tests use paired trial-level observations with all six algorithms present; lower values are better.";
    if nargin < 10 || isempty(bootMeans)
        bootMeans = bootstrapMeans(V, B);
    end

    rows(end+1, :) = statRow(familyId, scenario, metric, family, resultType, commModel, commPct, ...
        "friedman_omnibus", n, k, "", "", NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
        friedmanChi, friedmanDf, friedmanP, friedmanSig, kendallW, NaN, NaN, NaN, NaN, ...
        false, false, NaN, units, "Friedman omnibus test across all six algorithms. " + notes);

    pairCount = k * (k - 1) / 2;
    pairRows = cell(pairCount, 1);
    rawP = NaN(pairCount, 1);
    idx = 0;
    for a = 1:k-1
        for b = a+1:k
            idx = idx + 1;
            va = V(:, a);
            vb = V(:, b);
            diff = vb - va;
            [wPos, wNeg, pRaw, rankBiserial] = wilcoxonSignedRankLocal(diff);
            rawP(idx) = pRaw;
            [ciLow, ciHigh] = meanCiFromBootstrap(bootMeans(:, b) - bootMeans(:, a));
            meanA = meanNoNan(va);
            meanB = meanNoNan(vb);
            pctAdv = percentAdvantage(meanA, meanB);
            pairRows{idx} = statRow(familyId, scenario, metric, family, resultType, commModel, commPct, ...
                "wilcoxon_pairwise", n, k, algorithmOrder(a), algorithmOrder(b), meanA, meanB, ...
                meanNoNan(diff), medianNoNan(diff), pctAdv, ciLow, ciHigh, friedmanChi, friedmanDf, ...
                friedmanP, friedmanSig, kendallW, wPos, wNeg, pRaw, NaN, pRaw < 0.05, false, ...
                rankBiserial, units, "Wilcoxon signed-rank test on B minus A; positive difference and rank-biserial favor algorithm A. " + notes);
        end
    end

    holmP = holmAdjust(rawP);
    for i = 1:numel(pairRows)
        r = pairRows{i};
        r{28} = holmP(i);
        r{30} = isfinite(holmP(i)) && holmP(i) < 0.05;
        rows(end+1, :) = r;
    end
end

function row = statRow(familyId, scenario, metric, family, resultType, commModel, commPct, testType, nTrials, nAlgorithms, algA, algB, meanA, meanB, meanDiff, medianDiff, pctAdvA, diffCiLow, diffCiHigh, friedmanChi, friedmanDf, friedmanP, friedmanSig, kendallW, wPos, wNeg, pRaw, pHolm, rejectRaw, rejectHolm, rankBiserial, units, notes)
    row = {string(familyId), string(scenario), string(metric), string(family), string(resultType), ...
        string(commModel), commPct, string(testType), nTrials, nAlgorithms, string(algA), string(algB), ...
        meanA, meanB, meanDiff, medianDiff, pctAdvA, diffCiLow, diffCiHigh, friedmanChi, friedmanDf, ...
        friedmanP, logical(friedmanSig), kendallW, wPos, wNeg, pRaw, pHolm, logical(rejectRaw), ...
        logical(rejectHolm), rankBiserial, string(units), string(notes)};
end

function T = rowsToMetricTable(rows, cols)
    T = cell2table(rows, "VariableNames", cellstr(cols));
    textCols = ["scenario","metric","metric_family","result_type","comm_model","comm_level_raw", ...
        "algorithm","units","source_column","inclusion_rule","notes"];
    numCols = ["comm_level_pct","total_trial_count","eligible_paired_trials","excluded_trials", ...
        "mean_value","median_value","standard_deviation","ci95_low","ci95_high","field_mean", ...
        "absolute_advantage_vs_field","percent_advantage_vs_field"];
    for c = textCols
        T.(c) = string(T.(c));
    end
    for c = numCols
        T.(c) = numericColumn(T.(c));
    end
    T.lower_is_better = logicalColumn(T.lower_is_better);
end

function T = rowsToStatTable(rows, cols)
    T = cell2table(rows, "VariableNames", cellstr(cols));
    textCols = ["family_id","scenario","metric","metric_family","result_type","comm_model", ...
        "test_type","algorithm_a","algorithm_b","units","notes"];
    numCols = ["comm_level_pct","n_trials","n_algorithms","algorithm_a_mean","algorithm_b_mean", ...
        "mean_difference_b_minus_a","median_difference_b_minus_a","percent_advantage_algorithm_a", ...
        "difference_ci95_low","difference_ci95_high","friedman_chi_square","friedman_df", ...
        "friedman_p","kendall_w","wilcoxon_w_positive","wilcoxon_w_negative","wilcoxon_p_raw", ...
        "wilcoxon_p_holm","rank_biserial"];
    for c = textCols
        T.(c) = string(T.(c));
    end
    for c = numCols
        T.(c) = numericColumn(T.(c));
    end
    T.friedman_significant_0_05 = logicalColumn(T.friedman_significant_0_05);
    T.reject_raw_0_05 = logicalColumn(T.reject_raw_0_05);
    T.reject_holm_0_05 = logicalColumn(T.reject_holm_0_05);
end

function row = resultRow(scenario, metric, family, resultType, comparisonType, commModel, commRaw, commPct, isIdeal, focal, comp, pairId, totalCount, eligibleCount, excludedCount, focalMean, compMean, focalMedian, compMedian, meanAdv, medianAdv, pctAdv, diffSd, diffSe, ciLow, ciHigh, pctLow, pctHigh, fciLow, fciHigh, cciLow, cciHigh, offset, lowerIsBetter, units, sourceColumn, inclusionRule, notes)
    row = {string(scenario), string(metric), string(family), string(resultType), string(comparisonType), ...
        string(commModel), string(commRaw), commPct, logical(isIdeal), string(focal), string(comp), string(pairId), ...
        totalCount, eligibleCount, excludedCount, focalMean, compMean, focalMedian, compMedian, meanAdv, medianAdv, pctAdv, ...
        diffSd, diffSe, ciLow, ciHigh, pctLow, pctHigh, fciLow, fciHigh, cciLow, cciHigh, offset, logical(lowerIsBetter), ...
        string(units), string(sourceColumn), string(inclusionRule), string(notes)};
end

function T = rowsToResultTable(rows, cols)
    T = cell2table(rows, "VariableNames", cellstr(cols));
    textCols = ["scenario","metric","metric_family","result_type","comparison_type","comm_model", ...
        "comm_level_raw","focal_algorithm","comparison_algorithm","pair_id","units", ...
        "source_column","inclusion_rule","notes"];
    numCols = ["comm_level_pct","total_trial_count","eligible_paired_trials","excluded_trials", ...
        "focal_mean","comparison_mean","focal_median","comparison_median","mean_absolute_advantage", ...
        "median_absolute_advantage","percent_advantage","paired_difference_sd","paired_difference_se", ...
        "ci95_low","ci95_high","percent_ci95_low","percent_ci95_high","focal_ci95_low", ...
        "focal_ci95_high","comparison_ci95_low","comparison_ci95_high","metric_offset_c"];
    for c = textCols
        T.(c) = string(T.(c));
    end
    for c = numCols
        T.(c) = numericColumn(T.(c));
    end
    T.is_ideal = logicalColumn(T.is_ideal);
    T.lower_is_better = logicalColumn(T.lower_is_better);
end

function T = rowsToManifestTable(rows)
    cols = ["scenario","file_role","full_file_path","file_name","row_count","column_count", ...
        "selected","selection_reason","important_columns_found","duplicate_or_superseded","notes"];
    T = cell2table(rows, "VariableNames", cellstr(cols));
    for c = ["scenario","file_role","full_file_path","file_name","selection_reason","important_columns_found","notes"]
        T.(c) = string(T.(c));
    end
    T.row_count = numericColumn(T.row_count);
    T.column_count = numericColumn(T.column_count);
    T.selected = logicalColumn(T.selected);
    T.duplicate_or_superseded = logicalColumn(T.duplicate_or_superseded);
end

function y = numericColumn(x)
    if iscell(x)
        y = cell2mat(x);
    else
        y = double(x);
    end
end

function y = logicalColumn(x)
    if iscell(x)
        y = cell2mat(x);
    else
        y = logical(x);
    end
end

function bootMeans = bootstrapMeans(V, B)
    if isempty(V)
        bootMeans = NaN(B, size(V, 2));
        return;
    end
    n = size(V, 1);
    k = size(V, 2);
    idx = randi(n, n, B);
    bootMeans = NaN(B, k);
    for a = 1:k
        vals = V(:, a);
        bootMeans(:, a) = mean(vals(idx), 1)';
    end
end

function [lo, hi] = meanCiFromBootstrap(x)
    x = x(isfinite(x));
    if isempty(x)
        lo = NaN; hi = NaN;
    else
        lo = percentileLocal(x, 2.5);
        hi = percentileLocal(x, 97.5);
    end
end

function [lo, hi] = percentCi(focalBoot, compBoot)
    pct = NaN(size(focalBoot));
    ok = isfinite(focalBoot) & isfinite(compBoot) & compBoot ~= 0;
    pct(ok) = 100 * (compBoot(ok) - focalBoot(ok)) ./ compBoot(ok);
    [lo, hi] = meanCiFromBootstrap(pct);
end

function p = percentileLocal(x, pct)
    x = sort(x(:));
    n = numel(x);
    if n == 0
        p = NaN;
    elseif n == 1
        p = x(1);
    else
        pos = 1 + (pct / 100) * (n - 1);
        lo = floor(pos);
        hi = ceil(pos);
        if lo == hi
            p = x(lo);
        else
            p = x(lo) + (pos - lo) * (x(hi) - x(lo));
        end
    end
end

function fam = metricFamily(metric)
    switch string(metric)
        case "max_agent_steps"
            fam = "mission_timeliness";
        case "total_team_steps"
            fam = "team_resource_use";
        case "team_messages_per_step"
            fam = "communication_intensity";
        case "max_agent_messages"
            fam = "communication_bottleneck";
        case {"messages_per_unique_cell","messages_per_target"}
            fam = "communication_productivity";
        case {"system_cell_revisits","duplicate_target_visits"}
            fam = "repeated_effort";
        case {"unique_cell_contribution_gini","target_completion_gini"}
            fam = "workload_balance";
        case {"team_task_replans","team_path_replans"}
            fam = "planning_stability";
        otherwise
            fam = "robustness";
    end
end

function units = metricUnits(metric)
    switch string(metric)
        case {"max_agent_steps","total_team_steps"}
            units = "steps";
        case "team_messages_per_step"
            units = "messages_per_step";
        case "max_agent_messages"
            units = "messages";
        case "messages_per_unique_cell"
            units = "messages_per_unique_cell";
        case {"unique_cell_contribution_gini","target_completion_gini"}
            units = "gini";
        case {"team_task_replans","team_path_replans"}
            units = "replan_events";
        case "system_cell_revisits"
            units = "revisits";
        case "duplicate_target_visits"
            units = "duplicate_target_visits";
        case "messages_per_target"
            units = "messages_per_target";
        otherwise
            units = "";
    end
end

function offset = metricOffset(metric)
    switch string(metric)
        case {"max_agent_steps","total_team_steps","team_messages_per_step","max_agent_messages","messages_per_unique_cell","messages_per_target"}
            offset = 0;
        otherwise
            offset = 1;
    end
end

function src = metricSourceColumn(scenario, metric)
    if scenario == "Bayesian clue-informed search" || scenario == "Coverage area search"
        switch string(metric)
            case "max_agent_steps"
                src = "max_steps_any_robot";
            case "total_team_steps"
                src = "total_team_steps";
            case "team_messages_per_step"
                src = "messages_sent_total / total_team_steps";
            case "max_agent_messages"
                src = "max robot_performance.messages_sent";
            case "messages_per_unique_cell"
                src = "messages_per_unique_cell";
            case "unique_cell_contribution_gini"
                src = "workload_gini_unique_cells_contributed";
            case "team_task_replans"
                src = "task_cell_replans_total";
            case "team_path_replans"
                src = "path_replans_total";
            case "system_cell_revisits"
                src = "system_revisits";
            otherwise
                src = "";
        end
    else
        switch string(metric)
            case "max_agent_steps"
                src = "max_robot_steps";
            case "total_team_steps"
                src = "total_team_steps";
            case "team_messages_per_step"
                src = "messages_sent_total / total_team_steps";
            case "max_agent_messages"
                src = "max robot_performance.messages_sent";
            case "messages_per_unique_cell"
                src = "messages_sent_total / unique_cells_visited";
            case "unique_cell_contribution_gini"
                src = "workload_gini_unique_cells_contributed";
            case "team_task_replans"
                src = "task_cell_replans_total";
            case "team_path_replans"
                src = "path_replans_total";
            case "duplicate_target_visits"
                src = "duplicate_target_visits";
            case "target_completion_gini"
                src = "workload_gini_targets_found";
            case "messages_per_target"
                src = "messages_sent_total / completed_target_count";
            otherwise
                src = "";
        end
    end
end

function rule = conditionInclusionRule(scenario)
    if scenario == "Bayesian clue-informed search"
        rule = "All six algorithms present and eligible for the exact trial and communication condition; completed and first_clue_robot nonempty.";
    elseif scenario == "Coverage area search"
        rule = "All six algorithms present and eligible for the exact trial and communication condition; completed in system and trial summaries; clue and target fields ignored.";
    else
        rule = "All six algorithms present and eligible for the exact trial and communication condition; completed, all targets visited, and completed_target_count equals target_count.";
    end
end

function pair = canonicalPair(a, b)
    vals = sort([string(a), string(b)]);
    pair = vals(1) + "__" + vals(2);
end

function y = toDouble(x)
    if isnumeric(x)
        y = double(x);
    elseif islogical(x)
        y = double(x);
    else
        y = str2double(string(x));
    end
end

function y = toLogical(x)
    if islogical(x)
        y = x;
    elseif isnumeric(x)
        y = x ~= 0;
    else
        sx = lower(strtrim(string(x)));
        y = sx == "true" | sx == "1" | sx == "yes";
    end
end

function y = selectFirstNumeric(T, names)
    y = NaN(height(T), 1);
    vars = string(T.Properties.VariableNames);
    for n = names
        if any(vars == n)
            cand = toDouble(T.(n));
            take = isnan(y) & ~isnan(cand);
            y(take) = cand(take);
        end
    end
end

function z = safeDivide(num, den)
    z = NaN(size(num));
    ok = isfinite(num) & isfinite(den) & den ~= 0;
    z(ok) = num(ok) ./ den(ok);
end

function n = duplicateKeyCount(T, keyVars)
    G = findgroups(T(:, keyVars));
    counts = splitapply(@numel, G, G);
    n = sum(counts > 1);
end

function y = maxNoNan(x)
    x = x(isfinite(x));
    if isempty(x)
        y = NaN;
    else
        y = max(x);
    end
end

function y = sumNoNan(x)
    x = x(isfinite(x));
    if isempty(x)
        y = NaN;
    else
        y = sum(x);
    end
end

function g = giniLocal(x)
    x = x(isfinite(x) & x >= 0);
    if isempty(x) || sum(x) == 0
        g = 0;
        return;
    end
    x = sort(x(:));
    n = numel(x);
    total = sum(x);
    weighted = sum((1:n)' .* x);
    g = (2 * weighted) / (n * total) - (n + 1) / n;
end

function m = meanNoNan(x)
    x = x(isfinite(x));
    if isempty(x)
        m = NaN;
    else
        m = mean(x);
    end
end

function m = medianNoNan(x)
    x = x(isfinite(x));
    if isempty(x)
        m = NaN;
    else
        m = median(x);
    end
end

function s = stdNoNan(x)
    x = x(isfinite(x));
    if numel(x) < 2
        s = NaN;
    else
        s = std(x, 0);
    end
end

function s = seNoNan(x)
    x = x(isfinite(x));
    if numel(x) < 2
        s = NaN;
    else
        s = std(x, 0) / sqrt(numel(x));
    end
end

function pct = percentAdvantage(focalMean, comparisonMean)
    if ~isfinite(comparisonMean) || comparisonMean == 0
        pct = NaN;
    else
        pct = 100 * (comparisonMean - focalMean) / comparisonMean;
    end
end

function units = statisticalUnits(metric, resultType)
    if resultType == "prda"
        units = "prda_percentage_points";
    elseif resultType == "prds"
        units = "percent_metric_change_per_1pct_degradation";
    else
        units = metricUnits(metric);
    end
end

function id = makeFamilyId(scenario, metric, resultType, commModel, commPct)
    if isfinite(commPct)
        levelText = stripTrailingZeros(commPct);
    else
        levelText = "NaN";
    end
    id = string(scenario) + "|" + string(metric) + "|" + string(resultType) + "|" + string(commModel) + "|" + levelText;
end

function s = stripTrailingZeros(x)
    if isnan(x)
        s = "NaN";
    elseif abs(x - round(x)) < 1e-12
        s = string(sprintf("%.0f", x));
    else
        s = string(regexprep(sprintf("%.10g", x), "0+$", ""));
        s = string(regexprep(s, "\.$", ""));
    end
end

function [chiSquare, df, pValue, kendallW] = friedmanLocal(V)
    [n, k] = size(V);
    df = k - 1;
    if n == 0 || k < 2 || any(~isfinite(V), "all")
        chiSquare = NaN;
        pValue = NaN;
        kendallW = NaN;
        return;
    end
    ranks = NaN(n, k);
    for i = 1:n
        ranks(i, :) = averageRanks(V(i, :));
    end
    rankSums = sum(ranks, 1);
    chiSquare = (12 / (n * k * (k + 1))) * sum(rankSums .^ 2) - 3 * n * (k + 1);
    chiSquare = max(0, chiSquare);
    kendallW = chiSquare / (n * (k - 1));
    kendallW = min(max(kendallW, 0), 1);
    pValue = 1 - gammainc(chiSquare / 2, df / 2);
    pValue = min(max(pValue, 0), 1);
end

function ranks = averageRanks(values)
    values = values(:)';
    [sortedVals, order] = sort(values);
    ranksSorted = NaN(size(sortedVals));
    i = 1;
    while i <= numel(sortedVals)
        j = i;
        while j < numel(sortedVals) && sortedVals(j + 1) == sortedVals(i)
            j = j + 1;
        end
        ranksSorted(i:j) = mean(i:j);
        i = j + 1;
    end
    ranks = NaN(size(values));
    ranks(order) = ranksSorted;
end

function [wPositive, wNegative, pValue, rankBiserial] = wilcoxonSignedRankLocal(diffValues)
    diffValues = diffValues(isfinite(diffValues) & diffValues ~= 0);
    if isempty(diffValues)
        wPositive = 0;
        wNegative = 0;
        pValue = 1;
        rankBiserial = NaN;
        return;
    end
    ranks = averageRanks(abs(diffValues));
    wPositive = sum(ranks(diffValues > 0));
    wNegative = sum(ranks(diffValues < 0));
    denom = wPositive + wNegative;
    if denom == 0
        rankBiserial = NaN;
    else
        rankBiserial = (wPositive - wNegative) / denom;
        rankBiserial = min(max(rankBiserial, -1), 1);
    end
    meanW = denom / 2;
    varW = sum(ranks .^ 2) / 4;
    if varW <= 0
        pValue = 1;
    else
        continuity = 0.5 * sign(wPositive - meanW);
        z = (wPositive - meanW - continuity) / sqrt(varW);
        pValue = erfc(abs(z) / sqrt(2));
        pValue = min(max(pValue, 0), 1);
    end
end

function adjusted = holmAdjust(pValues)
    adjusted = NaN(size(pValues));
    finiteMask = isfinite(pValues);
    finiteP = pValues(finiteMask);
    if isempty(finiteP)
        return;
    end
    [sortedP, order] = sort(finiteP);
    m = numel(sortedP);
    sortedAdjusted = NaN(size(sortedP));
    runningMax = 0;
    for i = 1:m
        candidate = (m - i + 1) * sortedP(i);
        runningMax = max(runningMax, candidate);
        sortedAdjusted(i) = min(runningMax, 1);
    end
    finiteAdjusted = NaN(size(finiteP));
    finiteAdjusted(order) = sortedAdjusted;
    adjusted(finiteMask) = finiteAdjusted;
end

function [lo, hi] = bootstrapMeanDiffCi(diffValues, B)
    diffValues = diffValues(isfinite(diffValues));
    if isempty(diffValues)
        lo = NaN;
        hi = NaN;
        return;
    end
    n = numel(diffValues);
    idx = randi(n, n, B);
    boot = mean(diffValues(idx), 1);
    [lo, hi] = meanCiFromBootstrap(boot(:));
end

function logCounts(fid, data, resultTable, algorithmOrder, nominalLevels)
    for scenario = unique(data.scenario, "stable")'
        sub = data(data.scenario == scenario, :);
        logLine(fid, "%s total system rows: %d", scenario, height(sub));
        for model = unique(sub.comm_model, "stable")'
            msub = sub(sub.comm_model == model, :);
            logLine(fid, "%s %s condition count: %d rows, %d trials", scenario, model, height(msub), numel(unique(msub.trial_id)));
        end
        for model = ["bernoulli","gilbert_elliott","rayleigh_style"]
            balancedRows = resultTable(resultTable.scenario == scenario & resultTable.result_type == "prda" & ...
                resultTable.comm_model == model, :);
            if ~isempty(balancedRows)
                logLine(fid, "%s balanced degradation curves for %s: min=%d max=%d", scenario, model, ...
                    min(balancedRows.eligible_paired_trials), max(balancedRows.eligible_paired_trials));
            end
        end
    end
    logLine(fid, "Main result rows by type: condition_metric=%d prda=%d prds=%d", ...
        sum(resultTable.result_type == "condition_metric"), sum(resultTable.result_type == "prda"), sum(resultTable.result_type == "prds"));
end

function validation = validateTwoFileOutputs(metricT, statT, metricNames, algorithmOrder, fid)
    validation.coverageRows = sum(contains(lower(metricT.scenario), "coverage")) + sum(contains(lower(statT.scenario), "coverage"));
    foundMetrics = union(unique(metricT.metric), unique(statT.metric));
    validation.metricFoundCount = sum(ismember(metricNames, foundMetrics));
    validation.familyCount = numel(unique(statT.family_id));
    validation.omnibusRows = sum(statT.test_type == "friedman_omnibus");
    validation.pairwiseRows = sum(statT.test_type == "wilcoxon_pairwise");
    validation.familyStructureValid = validateFamilyStructure(statT, algorithmOrder);
    validation.numericRangesValid = validateStatNumericRanges(statT);
    validation.noTostRows = ~any(contains(lower(statT.test_type), "tost") | contains(lower(statT.test_type), "equivalence"));
    validation.manualSpotChecks = manualSpotChecks(statT);

    if any(metricT.metric == "team_path_churn") || any(statT.metric == "team_path_churn")
        validation.metricFoundCount = -1;
    end
    rayleighRows = metricT(metricT.comm_model == "rayleigh_style" & metricT.result_type == "condition_metric", :);
    expectedRaw = ["-59.4","-56.04","-52.15","-49.17","-46.04","-42.16","-37.79","-32.58"];
    expectedPct = [5 10 20 30 40 50 60 70];
    for i = 1:numel(expectedRaw)
        rawMask = string(rayleighRows.comm_level_raw) == expectedRaw(i);
        observed = unique(rayleighRows.comm_level_pct(rawMask));
        if numel(observed) ~= 1 || observed ~= expectedPct(i)
            validation.numericRangesValid = 0;
        end
    end
    bayesDeg = metricT(metricT.scenario == "Bayesian clue-informed search" & ismember(metricT.result_type, ["prda","prds"]), :);
    if any(bayesDeg.total_trial_count ~= 500) || any(bayesDeg.excluded_trials ~= 500 - bayesDeg.eligible_paired_trials)
        validation.numericRangesValid = 0;
    end
    algorithmsFound = unique(metricT.algorithm);
    if ~isempty(setdiff(algorithmOrder, algorithmsFound))
        validation.numericRangesValid = 0;
    end
    logLine(fid, "Final validation metrics found: %s", strjoin(foundMetrics', ", "));
    logLine(fid, "Final validation statistical families: %d", validation.familyCount);
    logLine(fid, "Final validation omnibus rows: %d pairwise rows: %d", validation.omnibusRows, validation.pairwiseRows);
end

function ok = validateFamilyStructure(statT, algorithmOrder)
    ok = 1;
    families = unique(statT.family_id);
    rank = @(alg) find(algorithmOrder == string(alg), 1);
    for f = 1:numel(families)
        sub = statT(statT.family_id == families(f), :);
        if sum(sub.test_type == "friedman_omnibus") ~= 1 || sum(sub.test_type == "wilcoxon_pairwise") ~= 15
            ok = 0;
            return;
        end
        pairRows = sub(sub.test_type == "wilcoxon_pairwise", :);
        seen = strings(height(pairRows), 1);
        for i = 1:height(pairRows)
            aRank = rank(pairRows.algorithm_a(i));
            bRank = rank(pairRows.algorithm_b(i));
            if isempty(aRank) || isempty(bRank) || aRank >= bRank
                ok = 0;
                return;
            end
            seen(i) = pairRows.algorithm_a(i) + "__" + pairRows.algorithm_b(i);
        end
        if numel(unique(seen)) ~= 15
            ok = 0;
            return;
        end
    end
end

function ok = validateStatNumericRanges(statT)
    ok = 1;
    w = statT.kendall_w(isfinite(statT.kendall_w));
    rb = statT.rank_biserial(isfinite(statT.rank_biserial));
    pRaw = statT.wilcoxon_p_raw(isfinite(statT.wilcoxon_p_raw));
    pHolm = statT.wilcoxon_p_holm(isfinite(statT.wilcoxon_p_holm));
    if any(w < -1e-12 | w > 1 + 1e-12) || any(rb < -1 - 1e-12 | rb > 1 + 1e-12)
        ok = 0;
    end
    if any(pRaw < -1e-12 | pRaw > 1 + 1e-12) || any(pHolm < -1e-12 | pHolm > 1 + 1e-12)
        ok = 0;
    end
    pairRows = statT(statT.test_type == "wilcoxon_pairwise" & isfinite(statT.wilcoxon_p_raw) & isfinite(statT.wilcoxon_p_holm), :);
    if any(pairRows.wilcoxon_p_holm + 1e-12 < pairRows.wilcoxon_p_raw)
        ok = 0;
    end
    if any(abs(pairRows.mean_difference_b_minus_a - (pairRows.algorithm_b_mean - pairRows.algorithm_a_mean)) > 1e-8)
        ok = 0;
    end
end

function count = manualSpotChecks(statT)
    count = 0;
    pairRows = statT(statT.test_type == "wilcoxon_pairwise", :);
    if ~isempty(pairRows)
        r = pairRows(1, :);
        if abs(r.mean_difference_b_minus_a - (r.algorithm_b_mean - r.algorithm_a_mean)) < 1e-8
            count = count + 1;
        end
        denom = r.wilcoxon_w_positive + r.wilcoxon_w_negative;
        if denom > 0
            rb = (r.wilcoxon_w_positive - r.wilcoxon_w_negative) / denom;
            if abs(rb - r.rank_biserial) < 1e-8
                count = count + 1;
            end
        end
        fam = r.family_id;
        famPairs = pairRows(pairRows.family_id == fam, :);
        adjusted = holmAdjust(famPairs.wilcoxon_p_raw);
        if all(abs(adjusted - famPairs.wilcoxon_p_holm) < 1e-8 | (isnan(adjusted) & isnan(famPairs.wilcoxon_p_holm)))
            count = count + 1;
        end
    end
    omnibus = statT(statT.test_type == "friedman_omnibus" & isfinite(statT.friedman_chi_square), :);
    if ~isempty(omnibus)
        r = omnibus(1, :);
        w = r.friedman_chi_square / (r.n_trials * (r.n_algorithms - 1));
        if abs(w - r.kendall_w) < 1e-8
            count = count + 1;
        end
    end
end

function validation = validateGeneratedResults(T, metricNames, fid)
    validation.bayesianConditionRows = sum(T.scenario == "Bayesian clue-informed search" & T.result_type == "condition_metric");
    validation.knownConditionRows = sum(T.scenario == "Collaborative known-target visit" & T.result_type == "condition_metric");
    validation.bayesianPrdaRows = sum(T.scenario == "Bayesian clue-informed search" & T.result_type == "prda");
    validation.bayesianPrdsRows = sum(T.scenario == "Bayesian clue-informed search" & T.result_type == "prds");
    validation.knownPrdaRows = sum(T.scenario == "Collaborative known-target visit" & T.result_type == "prda");
    validation.knownPrdsRows = sum(T.scenario == "Collaborative known-target visit" & T.result_type == "prds");
    validation.coverageRows = sum(contains(lower(T.scenario), "coverage"));
    validation.metricFoundCount = sum(ismember(metricNames, unique(T.metric)));
    validation.fieldMeanRows = sum(T.comparison_type == "vs_field_mean");
    [checks, maxErr] = reciprocalCheck(T);
    validation.reciprocalChecks = checks;
    validation.reciprocalMaxAbsError = maxErr;
    logLine(fid, "Final validation metric names found: %s", strjoin(unique(T.metric, "stable")', ", "));
    logLine(fid, "Final validation field mean rows: %d", validation.fieldMeanRows);
    logLine(fid, "Final validation reciprocal checks: %d max_abs_error=%g", checks, maxErr);
end

function [checks, maxErr] = reciprocalCheck(T)
    P = T(T.comparison_type == "algorithm_pair", :);
    checks = 0;
    maxErr = 0;
    for i = 1:height(P)
        focal = P.focal_algorithm(i);
        comp = P.comparison_algorithm(i);
        mask = P.scenario == P.scenario(i) & P.metric == P.metric(i) & ...
            P.result_type == P.result_type(i) & P.comm_model == P.comm_model(i) & ...
            P.comm_level_raw == P.comm_level_raw(i) & P.focal_algorithm == comp & ...
            P.comparison_algorithm == focal;
        j = find(mask, 1);
        if ~isempty(j) && isfinite(P.mean_absolute_advantage(i)) && isfinite(P.mean_absolute_advantage(j))
            err = abs(P.mean_absolute_advantage(i) + P.mean_absolute_advantage(j));
            maxErr = max(maxErr, err);
            checks = checks + 1;
        end
    end
end

function logLine(fid, fmt, varargin)
    fprintf(fid, char(string(fmt) + newline), varargin{:});
end
