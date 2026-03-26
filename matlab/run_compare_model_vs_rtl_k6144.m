%RUN_COMPARE_MODEL_VS_RTL_K6144 Overlay MATLAB model BER against actual RTL BER.

clear;
clc;

scriptDir = fileparts(mfilename("fullpath"));
resultsDir = fullfile(scriptDir, "results");
if ~isfolder(resultsDir)
    mkdir(resultsDir);
end

matPath = fullfile(resultsDir, "ber_fer_k6144_halfiter11_heavy.mat");
if isfile(matPath)
    load(matPath, "resultsIdeal", "resultsFloat", "resultsFixed");
else
    run(fullfile(scriptDir, "run_turbo_ber_k6144_heavy.m"));
    load(matPath, "resultsIdeal", "resultsFloat", "resultsFixed");
end

rtlSweepCsv = fullfile(scriptDir, "..", "sim_vectors", "ber_sweep", "ber_sweep_summary.csv");
rtlResults = load_rtl_ber_summary(rtlSweepCsv, 6144);

plotPath = fullfile(resultsDir, "ber_compare_model_vs_rtl_k6144.png");
plot_lte_turbo_results([resultsIdeal, resultsFloat, resultsFixed, rtlResults], plotPath);

compareTable = table();
for item = [resultsIdeal, resultsFloat, resultsFixed, rtlResults]
    localTable = table( ...
        item.snrDb(:), ...
        item.ber(:), ...
        repmat(string(item.label), numel(item.snrDb), 1), ...
        repmat(string(item.decoderMode), numel(item.snrDb), 1), ...
        'VariableNames', {'snrDb', 'ber', 'curve', 'decoderMode'} ...
    );
    compareTable = [compareTable; localTable]; %#ok<AGROW>
end

csvPath = fullfile(resultsDir, "ber_compare_model_vs_rtl_k6144.csv");
writetable(compareTable, csvPath);

disp(compareTable);
fprintf("Saved overlay plot to %s\n", plotPath);
fprintf("Saved overlay CSV to %s\n", csvPath);
