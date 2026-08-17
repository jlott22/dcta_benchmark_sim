% Reproduce the CV DGA-generation selection used by the paper.
%
% Primary outcome: maximum agent steps (max_robot_steps).
% Selection rule: minimize the unweighted mean normalized regret across
% ideal communication and Bernoulli loss with p_d = 0.25.
%
% This script intentionally creates tables and a validation log only. DGA
% tuning is reported in the methods text and is not a numbered paper figure.

clear; clc;

scriptDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(fileparts(scriptDir));
tableDir = fullfile(scriptDir, 'tables');
if ~exist(tableDir, 'dir')
    mkdir(tableDir);
end

inputFile = fullfile(repoRoot, 'results', ...
    'sensitivity_known_target_visit_dga_iteration_300', 'combined', ...
    'sensitivity_known_target_visit_dga_iteration_300_combined_system_performance.csv');
summaryFile = fullfile(tableDir, 'dga_iteration_condition_summary.csv');
selectionFile = fullfile(tableDir, 'dga_iteration_selection.csv');
manifestFile = fullfile(tableDir, 'dga_iteration_source_manifest.csv');
logFile = fullfile(tableDir, 'dga_iteration_analysis_log.txt');

requiredColumns = ["algorithm", "comm_model", "comm_label", "trial_id", ...
    "trial_status", "all_targets_visited", "completed_target_count", ...
    "target_count", "value", "max_robot_steps"];
testedIterations = [1; 2; 5; 10; 25; 50];
communicationOrder = ["ideal"; "bernoulli_025"];
selectedIterations = 25;

T = readtable(inputFile, 'TextType', 'string');
missingColumns = setdiff(requiredColumns, string(T.Properties.VariableNames));
if ~isempty(missingColumns)
    error('DGA tuning input is missing required columns: %s', ...
        strjoin(missingColumns, ', '));
end

T.algorithm = upper(strtrim(string(T.algorithm)));
T.comm_key = lower(strtrim(string(T.comm_label)));
T.iterations = double(T.value);
T.maximum_agent_steps = double(T.max_robot_steps);
T.eligible = T.algorithm == "DGA" & ...
    lower(strtrim(string(T.trial_status))) == "completed" & ...
    logicalColumn(T.all_targets_visited) & ...
    double(T.completed_target_count) == double(T.target_count) & ...
    isfinite(T.maximum_agent_steps) & T.maximum_agent_steps > 0;

if height(T) ~= 3600
    error('Expected 3,600 CV DGA tuning rows; found %d.', height(T));
end
if ~isequal(sort(unique(T.iterations)), testedIterations)
    error('Unexpected DGA iteration levels in the raw input.');
end
if ~isequal(sort(unique(T.comm_key)), sort(communicationOrder))
    error('Unexpected communication conditions in the raw input.');
end

conditionRows = cell(0, 14);
for ci = 1:numel(communicationOrder)
    comm = communicationOrder(ci);
    commLabel = displayCommunication(comm);
    conditionMeans = nan(numel(testedIterations), 1);
    attemptedCounts = zeros(numel(testedIterations), 1);
    eligibleCounts = zeros(numel(testedIterations), 1);

    for ki = 1:numel(testedIterations)
        k = testedIterations(ki);
        rows = T(T.comm_key == comm & T.iterations == k, :);
        attemptedCounts(ki) = height(rows);
        values = rows.maximum_agent_steps(rows.eligible);
        eligibleCounts(ki) = numel(values);
        if attemptedCounts(ki) ~= 300 || eligibleCounts(ki) ~= 300
            error(['Expected 300 attempted and eligible rows for %s, k=%d; ' ...
                'found %d attempted and %d eligible.'], comm, k, ...
                attemptedCounts(ki), eligibleCounts(ki));
        end
        conditionMeans(ki) = mean(values);
    end

    bestMean = min(conditionMeans);
    for ki = 1:numel(testedIterations)
        k = testedIterations(ki);
        rows = T(T.comm_key == comm & T.iterations == k & T.eligible, :);
        values = rows.maximum_agent_steps;
        regret = 100 * (conditionMeans(ki) - bestMean) / bestMean;
        conditionRows(end + 1, :) = { ... %#ok<SAGROW>
            "Collaborative Visit (CV)", comm, commLabel, k, ...
            attemptedCounts(ki), eligibleCounts(ki), mean(values), ...
            median(values), std(values, 0), min(values), max(values), ...
            bestMean, regret, k == selectedIterations};
    end
end

conditionSummary = cell2table(conditionRows, 'VariableNames', { ...
    'mission', 'comm_model', 'comm_label', 'dga_iterations', ...
    'attempted_trials', 'eligible_trials', 'mean_maximum_agent_steps', ...
    'median_maximum_agent_steps', 'sd_maximum_agent_steps', ...
    'minimum_maximum_agent_steps', 'maximum_maximum_agent_steps', ...
    'best_condition_mean', 'normalized_regret_pct', ...
    'selected_for_main_benchmark'});

selectionRows = cell(numel(testedIterations), 8);
for ki = 1:numel(testedIterations)
    k = testedIterations(ki);
    ideal = conditionSummary(conditionSummary.comm_model == "ideal" & ...
        conditionSummary.dga_iterations == k, :);
    bernoulli = conditionSummary(conditionSummary.comm_model == "bernoulli_025" & ...
        conditionSummary.dga_iterations == k, :);
    meanRegret = mean([ideal.normalized_regret_pct, bernoulli.normalized_regret_pct]);
    selectionRows(ki, :) = {k, ideal.mean_maximum_agent_steps, ...
        bernoulli.mean_maximum_agent_steps, ideal.normalized_regret_pct, ...
        bernoulli.normalized_regret_pct, meanRegret, ...
        k == selectedIterations, "minimum mean normalized regret"};
end

selectionSummary = cell2table(selectionRows, 'VariableNames', { ...
    'dga_iterations', 'ideal_mean_maximum_agent_steps', ...
    'bernoulli_025_mean_maximum_agent_steps', ...
    'ideal_normalized_regret_pct', ...
    'bernoulli_025_normalized_regret_pct', ...
    'mean_normalized_regret_pct', 'selected_for_main_benchmark', ...
    'selection_rule'});

[~, selectedIndex] = min(selectionSummary.mean_normalized_regret_pct);
calculatedSelection = selectionSummary.dga_iterations(selectedIndex);
if calculatedSelection ~= selectedIterations
    error('Selection mismatch: expected k=25, calculated k=%d.', calculatedSelection);
end

assertNear(conditionMean(conditionSummary, "ideal", 50), 21.6266666667, 1e-9, ...
    'ideal k=50 mean');
assertNear(conditionMean(conditionSummary, "ideal", 25), 21.8666666667, 1e-9, ...
    'ideal k=25 mean');
assertNear(conditionMean(conditionSummary, "bernoulli_025", 25), 23.1833333333, 1e-9, ...
    'Bernoulli k=25 mean');

writetable(conditionSummary, summaryFile);
writetable(selectionSummary, selectionFile);

fileInfo = dir(inputFile);
sourceManifest = table("CV DGA-generation sensitivity", ...
    string(repositoryRelative(inputFile, repoRoot)), fileInfo.bytes, ...
    string(datetime(fileInfo.datenum, 'ConvertFrom', 'datenum', ...
    'Format', 'yyyy-MM-dd HH:mm:ss')), height(T), ...
    "max_robot_steps", ...
    "completed + all targets visited + finite positive maximum-agent steps", ...
    'VariableNames', {'dataset', 'repository_path', 'bytes', ...
    'last_modified', 'raw_rows', 'outcome_column', 'eligibility_rule'});
writetable(sourceManifest, manifestFile);

selectedRow = selectionSummary(selectionSummary.selected_for_main_benchmark, :);
fid = fopen(logFile, 'w');
if fid < 0
    error('Could not open validation log: %s', logFile);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, 'CV DGA-generation sensitivity validation\n');
fprintf(fid, 'Input: %s\n', repositoryRelative(inputFile, repoRoot));
fprintf(fid, 'Raw rows: %d\n', height(T));
fprintf(fid, 'Outcome: max_robot_steps (maximum-agent steps)\n');
fprintf(fid, ['Eligibility: completed + all targets visited + completed target count ' ...
    'equals target count + finite positive outcome\n']);
fprintf(fid, 'Eligible rows: %d / %d\n', nnz(T.eligible), height(T));
fprintf(fid, 'Trials per communication x k condition: 300\n');
fprintf(fid, 'Selected k: %d\n', selectedIterations);
fprintf(fid, 'Selection rule: minimum unweighted mean normalized regret across ideal and Bernoulli p_d=0.25\n');
fprintf(fid, 'Selected mean normalized regret: %.9f%%\n', ...
    selectedRow.mean_normalized_regret_pct);
fprintf(fid, 'Ideal means: k=50 %.6f, k=25 %.6f maximum-agent steps\n', ...
    conditionMean(conditionSummary, "ideal", 50), ...
    conditionMean(conditionSummary, "ideal", 25));
fprintf(fid, 'Bernoulli p_d=0.25 mean: k=25 %.6f maximum-agent steps\n', ...
    conditionMean(conditionSummary, "bernoulli_025", 25));
fprintf(fid, 'Validation: PASS\n');

fprintf('DGA tuning selection: k=%d (mean normalized regret %.6f%%)\n', ...
    selectedIterations, selectedRow.mean_normalized_regret_pct);
fprintf('Wrote %s\n', repositoryRelative(summaryFile, repoRoot));
fprintf('Wrote %s\n', repositoryRelative(selectionFile, repoRoot));
fprintf('Wrote %s\n', repositoryRelative(manifestFile, repoRoot));
fprintf('Wrote %s\n', repositoryRelative(logFile, repoRoot));

function result = logicalColumn(values)
    if islogical(values)
        result = values;
    elseif isnumeric(values)
        result = values ~= 0 & isfinite(values);
    else
        normalized = lower(strtrim(string(values)));
        result = ismember(normalized, ["true", "1", "yes"]);
    end
end

function label = displayCommunication(comm)
    if comm == "ideal"
        label = "Ideal";
    elseif comm == "bernoulli_025"
        label = "Bernoulli loss, p_d=0.25";
    else
        label = comm;
    end
end

function value = conditionMean(summary, comm, iterations)
    row = summary(summary.comm_model == comm & ...
        summary.dga_iterations == iterations, :);
    if height(row) ~= 1
        error('Expected one summary row for %s, k=%d.', comm, iterations);
    end
    value = row.mean_maximum_agent_steps;
end

function assertNear(actual, expected, tolerance, label)
    if abs(actual - expected) > tolerance
        error('%s mismatch: expected %.12g, found %.12g.', ...
            label, expected, actual);
    end
end

function relative = repositoryRelative(pathValue, repoRoot)
    normalizedPath = replace(string(pathValue), "\", "/");
    normalizedRoot = replace(string(repoRoot), "\", "/");
    prefix = normalizedRoot + "/";
    if startsWith(lower(normalizedPath), lower(prefix))
        relative = extractAfter(normalizedPath, strlength(prefix));
    else
        relative = normalizedPath;
    end
end
