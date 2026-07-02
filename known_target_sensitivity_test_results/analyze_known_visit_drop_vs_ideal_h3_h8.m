%% analyze_known_visit_drop_vs_ideal_h3_h8.m
% Compare Bernoulli-drop performance against ideal baseline for fixed horizons h3 and h8.
%
% This is NOT a horizon-sensitivity plot. It uses only h3 and h8 as two
% fixed settings and creates separate ideal-vs-Bernoulli degradation plots.
%
% Convention used for all requested metrics:
%   percent_change_positive_better = 100 * (ideal_mean - bernoulli_mean) / ideal_mean
%
% Therefore:
%   positive value  = Bernoulli used less of the metric than ideal, better
%   zero            = no change from ideal
%   negative value  = Bernoulli used more of the metric than ideal, worse
%
% For these metrics lower is treated as better:
%   total_team_steps, messages_sent_total, path_replans_total,
%   final_target_completion_time_s
%
% Put this file in the same folder as system_performance.csv, or set csvPath below.

clear; clc; close all;

%% ---------------- User settings ----------------
csvPath = "C:\Users\lottj\Desktop\research\decentralized benchmark\dcta_benchmark_sim\known_target_sensitivity_test_results\horizon_results\combined\system_performance.csv";  % auto-detect if blank
outSubdir = 'drop_vs_ideal_figs';

horizonsToPlot = {'h3', 'h8'};
baselineCommModel = 'ideal';
dropCommModel = 'bernoulli';
% Leave blank to use all Bernoulli levels found. If multiple levels are present,
% the script creates separate outputs for each level.
dropCommLevel = "";  % example: "0.25"

metrics = {
    'total_team_steps',                 'Total team steps',                  true
    'messages_sent_total',              'Messages sent',                     true
    'path_replans_total',               'Path replans',                      true
    'final_target_completion_time_s',   'Final target completion time (s)',  true
};

algorithmOrder = {'ACBBA','DGA','DMCHBA','HIPC','PI'};

%% ---------------- Locate CSV and output directory ----------------
scriptDir = fileparts(mfilename('fullpath'));
if strlength(csvPath) == 0
    candidates = {
        fullfile(scriptDir, 'system_performance.csv')
        fullfile(pwd, 'system_performance.csv')
        fullfile(pwd, 'runs', 'sensitivity_known_visit_horizon_300', 'combined', 'system_performance.csv')
        fullfile(scriptDir, 'runs', 'sensitivity_known_visit_horizon_300', 'combined', 'system_performance.csv')
        };
    csvPath = "";
    for i = 1:numel(candidates)
        if isfile(candidates{i})
            csvPath = string(candidates{i});
            break;
        end
    end
end
if strlength(csvPath) == 0 || ~isfile(csvPath)
    error('Could not find system_performance.csv. Set csvPath near the top of this script.');
end
csvPath = char(csvPath);
outDir = fullfile(fileparts(csvPath), outSubdir);
if ~exist(outDir, 'dir')
    mkdir(outDir);
end
fprintf('Reading: %s\n', csvPath);
fprintf('Writing outputs to: %s\n', outDir);

%% ---------------- Load ----------------
opts = detectImportOptions(csvPath, 'NumHeaderLines', 0);
textCols = intersect(opts.VariableNames, {'trial_mode','algorithm','comm_model','condition_id', ...
    'sensitivity_suite','sensitivity_parameter','sensitivity_label','source_comm_folder', ...
    'source_condition_folder','source_out_dir'});
for i = 1:numel(textCols)
    try
        opts = setvartype(opts, textCols{i}, 'string');
    catch
    end
end
T = readtable(csvPath, opts);
T.Properties.VariableNames = matlab.lang.makeValidName(T.Properties.VariableNames);

requiredCols = {'trial_id','algorithm','comm_model','comm_level','sensitivity_label'};
for i = 1:numel(requiredCols)
    if ~ismember(requiredCols{i}, T.Properties.VariableNames)
        error('Missing required column: %s', requiredCols{i});
    end
end

% Normalize key columns.
T.trial_id_str = string(T.trial_id);
T.algorithm = string(T.algorithm);
T.comm_model = lower(strtrim(string(T.comm_model)));
if isnumeric(T.comm_level)
    T.comm_level_str = string(T.comm_level);
else
    T.comm_level_str = string(T.comm_level);
end
T.comm_level_str(ismissing(T.comm_level_str) | strlength(strtrim(T.comm_level_str)) == 0) = "";
T.comm_level_str(T.comm_model == "ideal") = "1";
T.sensitivity_label = lower(strtrim(string(T.sensitivity_label)));

% Normalize h labels to h3/h8/etc.
T.h_label = strings(height(T), 1);
for i = 1:height(T)
    tok = regexp(char(T.sensitivity_label(i)), '\d+', 'match');
    if ~isempty(tok)
        T.h_label(i) = "h" + string(tok{1});
    else
        T.h_label(i) = T.sensitivity_label(i);
    end
end

% Keep requested horizons and ideal/Bernoulli only.
keepH = ismember(T.h_label, string(horizonsToPlot));
keepComm = T.comm_model == string(baselineCommModel) | T.comm_model == string(dropCommModel);
T = T(keepH & keepComm, :);

if strlength(dropCommLevel) > 0
    T = T(T.comm_model == string(baselineCommModel) | T.comm_level_str == string(dropCommLevel), :);
end

if isempty(T)
    error('No rows left after filtering to h3/h8 and ideal/Bernoulli.');
end

% Verify metrics exist.
metricNames = metrics(:,1);
for i = 1:numel(metricNames)
    if ~ismember(metricNames{i}, T.Properties.VariableNames)
        error('Requested metric column not found: %s', metricNames{i});
    end
end

%% ---------------- Collapse duplicate rows ----------------
% One row per trial/algorithm/comm/horizon. If accidental duplicates exist,
% mean-collapse them before pairing.
groupVars = {'trial_id_str','algorithm','comm_model','comm_level_str','h_label'};
[G, K] = findgroups(T(:, groupVars));
Tc = K;
for mi = 1:numel(metricNames)
    col = metricNames{mi};
    Tc.(col) = splitapply(@mean_omitnan, double(T.(col)), G);
end
T = Tc;

%% ---------------- Compute ideal-vs-Bernoulli percent change ----------------
summaryRows = table();
trialRows = table();

algs = string(algorithmOrder(:));
algs = algs(ismember(algs, unique(T.algorithm)));
extraAlgs = setdiff(unique(T.algorithm, 'stable'), algs, 'stable');
algs = [algs; extraAlgs];

dropLevels = unique(T.comm_level_str(T.comm_model == string(dropCommModel)), 'stable');
if isempty(dropLevels)
    error('No Bernoulli rows found.');
end

for hi = 1:numel(horizonsToPlot)
    h = string(horizonsToPlot{hi});
    for li = 1:numel(dropLevels)
        level = dropLevels(li);
        for ai = 1:numel(algs)
            alg = algs(ai);
            I = T(T.h_label == h & T.algorithm == alg & T.comm_model == string(baselineCommModel), :);
            B = T(T.h_label == h & T.algorithm == alg & T.comm_model == string(dropCommModel) & T.comm_level_str == level, :);
            if isempty(I) || isempty(B)
                continue;
            end

            for mi = 1:size(metrics,1)
                metricCol = metrics{mi,1};
                metricLabel = metrics{mi,2};
                lowerBetter = logical(metrics{mi,3});

                Itab = table(I.trial_id_str, I.(metricCol), 'VariableNames', {'trial_id_str','ideal_value'});
                Btab = table(B.trial_id_str, B.(metricCol), 'VariableNames', {'trial_id_str','drop_value'});
                P = innerjoin(Itab, Btab, 'Keys', 'trial_id_str');
                P = P(isfinite(P.ideal_value) & isfinite(P.drop_value), :);
                if isempty(P)
                    continue;
                end

                idealMean = mean_omitnan(P.ideal_value);
                dropMean = mean_omitnan(P.drop_value);

                if lowerBetter
                    pctOfMeans = safe_pct(idealMean - dropMean, idealMean);
                    pairedPct = arrayfun(@(iv,dv) safe_pct(iv - dv, iv), P.ideal_value, P.drop_value);
                else
                    pctOfMeans = safe_pct(dropMean - idealMean, idealMean);
                    pairedPct = arrayfun(@(iv,dv) safe_pct(dv - iv, iv), P.ideal_value, P.drop_value);
                end
                pairedPct = pairedPct(isfinite(pairedPct));

                meanPairedPct = mean_omitnan(pairedPct);
                medPairedPct = median_omitnan(pairedPct);
                ciPairedPct = ci95_halfwidth_omitnan(pairedPct);

                row = table(h, alg, level, string(metricCol), string(metricLabel), height(P), ...
                    idealMean, dropMean, pctOfMeans, meanPairedPct, medPairedPct, ciPairedPct, ...
                    'VariableNames', {'horizon','algorithm','bernoulli_level','metric','metric_label','n_pairs', ...
                    'ideal_mean','bernoulli_mean','pct_change_of_means_positive_better', ...
                    'mean_paired_pct_change_positive_better','median_paired_pct_change_positive_better', ...
                    'ci95_halfwidth_paired_pct_change'});
                summaryRows = [summaryRows; row]; %#ok<AGROW>

                trialMetric = repmat(string(metricCol), height(P), 1);
                trialLabel = repmat(string(metricLabel), height(P), 1);
                trialH = repmat(h, height(P), 1);
                trialAlg = repmat(alg, height(P), 1);
                trialLevel = repmat(level, height(P), 1);
                if lowerBetter
                    trialPct = arrayfun(@(iv,dv) safe_pct(iv - dv, iv), P.ideal_value, P.drop_value);
                else
                    trialPct = arrayfun(@(iv,dv) safe_pct(dv - iv, iv), P.ideal_value, P.drop_value);
                end
                trialOut = table(trialH, trialAlg, trialLevel, trialMetric, trialLabel, P.trial_id_str, ...
                    P.ideal_value, P.drop_value, trialPct, ...
                    'VariableNames', {'horizon','algorithm','bernoulli_level','metric','metric_label','trial_id', ...
                    'ideal_value','bernoulli_value','paired_pct_change_positive_better'});
                trialRows = [trialRows; trialOut]; %#ok<AGROW>
            end
        end
    end
end

if isempty(summaryRows)
    error('No paired ideal/Bernoulli summary rows were generated. Check trial IDs and filters.');
end

summaryRows = sortrows(summaryRows, {'horizon','bernoulli_level','metric','algorithm'});
writetable(summaryRows, fullfile(outDir, 'ideal_vs_bernoulli_h3_h8_percent_summary.csv'));
writetable(trialRows, fullfile(outDir, 'ideal_vs_bernoulli_h3_h8_paired_trial_values.csv'));

%% ---------------- Plots ----------------
for hi = 1:numel(horizonsToPlot)
    h = string(horizonsToPlot{hi});
    for li = 1:numel(dropLevels)
        level = dropLevels(li);
        for mi = 1:size(metrics,1)
            metricCol = string(metrics{mi,1});
            metricLabel = string(metrics{mi,2});
            D = summaryRows(summaryRows.horizon == h & summaryRows.bernoulli_level == level & summaryRows.metric == metricCol, :);
            if isempty(D)
                continue;
            end
            D.algorithm = categorical(D.algorithm, algs, algs, 'Ordinal', true);
            D = sortrows(D, 'algorithm');

            f = figure('Color', 'w', 'Position', [100 100 1050 600], 'Visible', 'off');
            b = bar(D.algorithm, D.pct_change_of_means_positive_better);
            b.FaceAlpha = 0.88;
            grid on; box on;
            yline(0, '--', 'Ideal baseline', 'LabelHorizontalAlignment', 'left');
            ylabel('% change vs ideal (positive is better)');
            xlabel('Algorithm');
            title(sprintf('%s: Bernoulli drop vs ideal at %s', metricLabel, upper(char(h))), 'Interpreter', 'none');
            subtitle(sprintf('Bernoulli level %s; %% = 100*(ideal - drop)/ideal', char(level)), 'Interpreter', 'none');
            set(gca, 'FontSize', 12);
            xtickangle(0);

            % Add readable labels on bars.
            y = D.pct_change_of_means_positive_better;
            for k = 1:numel(y)
                if isfinite(y(k))
                    if y(k) >= 0
                        va = 'bottom'; offset = 0.6;
                    else
                        va = 'top'; offset = -0.6;
                    end
                    text(k, y(k) + offset, sprintf('%.1f%%', y(k)), ...
                        'HorizontalAlignment', 'center', 'VerticalAlignment', va, 'FontSize', 10);
                end
            end

            safeMetric = regexprep(char(metricCol), '[^\w\-]', '_');
            safeLevel = regexprep(char(level), '[^\w\-]', '_');
            pngPath = fullfile(outDir, sprintf('drop_vs_ideal_%s_%s_bernoulli_%s.png', safeMetric, char(h), safeLevel));
            figPath = fullfile(outDir, sprintf('drop_vs_ideal_%s_%s_bernoulli_%s.fig', safeMetric, char(h), safeLevel));
            try
                exportgraphics(f, pngPath, 'Resolution', 300);
            catch
                saveas(f, pngPath);
            end
            try
                savefig(f, figPath);
            catch
                saveas(f, figPath);
            end
            close(f);
            fprintf('Saved %s\n', pngPath);
        end

        % Optional compact multi-metric graph for the horizon.
        Dh = summaryRows(summaryRows.horizon == h & summaryRows.bernoulli_level == level, :);
        f = figure('Color', 'w', 'Position', [100 100 1200 650], 'Visible', 'off');
        hold on; grid on; box on;
        for mi = 1:size(metrics,1)
            metricCol = string(metrics{mi,1});
            metricLabel = string(metrics{mi,2});
            Dm = Dh(Dh.metric == metricCol, :);
            Dm.algorithm = categorical(Dm.algorithm, algs, algs, 'Ordinal', true);
            Dm = sortrows(Dm, 'algorithm');
            x = 1:height(Dm);
            plot(x, Dm.pct_change_of_means_positive_better, '-o', 'LineWidth', 1.8, ...
                'MarkerSize', 6, 'DisplayName', char(metricLabel));
        end
        yline(0, '--', 'Ideal baseline', 'HandleVisibility', 'off');
        xlim([0.75, numel(algs)+0.25]);
        xticks(1:numel(algs));
        xticklabels(cellstr(algs));
        xlabel('Algorithm');
        ylabel('% change vs ideal (positive is better)');
        title(sprintf('Bernoulli drop performance vs ideal at %s', upper(char(h))), 'Interpreter', 'none');
        subtitle(sprintf('Bernoulli level %s; lower-is-better metrics converted so positive is better', char(level)), 'Interpreter', 'none');
        legend('Location', 'bestoutside', 'Interpreter', 'none');
        set(gca, 'FontSize', 12);
        safeLevel = regexprep(char(level), '[^\w\-]', '_');
        pngPath = fullfile(outDir, sprintf('drop_vs_ideal_all_metrics_%s_bernoulli_%s.png', char(h), safeLevel));
        figPath = fullfile(outDir, sprintf('drop_vs_ideal_all_metrics_%s_bernoulli_%s.fig', char(h), safeLevel));
        try
            exportgraphics(f, pngPath, 'Resolution', 300);
        catch
            saveas(f, pngPath);
        end
        try
            savefig(f, figPath);
        catch
            saveas(f, figPath);
        end
        close(f);
        fprintf('Saved %s\n', pngPath);
    end
end

fprintf('\nDone. Main outputs:\n');
fprintf('  %s\n', fullfile(outDir, 'ideal_vs_bernoulli_h3_h8_percent_summary.csv'));
fprintf('  %s\n', fullfile(outDir, 'ideal_vs_bernoulli_h3_h8_paired_trial_values.csv'));
fprintf('  Figures in %s\n', outDir);

%% ========================================================================
% Local helper functions
%% ========================================================================
function m = mean_omitnan(x)
    x = x(~isnan(x) & isfinite(x));
    if isempty(x), m = NaN; else, m = mean(x); end
end

function med = median_omitnan(x)
    x = x(~isnan(x) & isfinite(x));
    if isempty(x), med = NaN; else, med = median(x); end
end

function hw = ci95_halfwidth_omitnan(x)
    x = x(~isnan(x) & isfinite(x));
    n = numel(x);
    if n <= 1
        hw = NaN;
        return;
    end
    se = std(x) / sqrt(n);
    try
        tcrit = tinv(0.975, n - 1);
    catch
        tcrit = 1.96;
    end
    hw = tcrit * se;
end

function p = safe_pct(numer, denom)
    if ~isfinite(numer) || ~isfinite(denom) || abs(denom) <= eps
        p = NaN;
    else
        p = 100 * numer / denom;
    end
end
