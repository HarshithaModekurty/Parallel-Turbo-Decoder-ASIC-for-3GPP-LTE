%RUN_TURBO_BER_K3200_HEAVY Heavier BER/FER run at K=3200.
%
% This script compares:
%   1) ideal log-MAP / BCJR reference
%   2) floating max-log reference
%   3) RTL-style fixed-point radix-4/windowed model
%
% The settings are intentionally heavier than the smoke demo while still
% staying practical for a scripted MATLAB run.

clear;
clc;

scriptDir = fileparts(mfilename("fullpath"));
resultsDir = fullfile(scriptDir, "results");
if ~isfolder(resultsDir)
    mkdir(resultsDir);
end

baseCfg = struct();
baseCfg.k = 3200;
baseCfg.snrDbList = 0.0:0.5:2.5;
baseCfg.nHalfIter = 11;
baseCfg.numFrames = 24;
baseCfg.maxBitErrors = 2500;
baseCfg.maxFrameErrors = 24;
baseCfg.seed = 12345;
baseCfg.llrScale = 2.0;
baseCfg.extrinsicScale = 11 / 16;
baseCfg.verbose = true;

cfgIdeal = baseCfg;
cfgIdeal.decoderMode = "ideal_logmap";
cfgIdeal.label = "ideal log-MAP / BCJR";

cfgFloat = baseCfg;
cfgFloat.decoderMode = "floating";
cfgFloat.quantizeInputLLR = false;
cfgFloat.extrinsicScale = 1.0;
cfgFloat.label = "floating max-log";

cfgFixed = baseCfg;
cfgFixed.decoderMode = "rtl_fixed";
cfgFixed.label = "RTL-style fixed radix-4/windowed";

resultsIdeal = lte_turbo_ber_sweep(cfgIdeal);
resultsFloat = lte_turbo_ber_sweep(cfgFloat);
resultsFixed = lte_turbo_ber_sweep(cfgFixed);

resultsArray = [resultsIdeal, resultsFloat, resultsFixed];
plotPath = fullfile(resultsDir, "ber_fer_k3200_halfiter11_heavy.png");
csvPath = fullfile(resultsDir, "ber_fer_k3200_halfiter11_heavy.csv");
matPath = fullfile(resultsDir, "ber_fer_k3200_halfiter11_heavy.mat");

plot_lte_turbo_results(resultsArray, plotPath);

summaryTable = table();
for idx = 1:numel(resultsArray)
    curveTable = struct2table(resultsArray(idx).summary);
    curveTable.curve = repmat(string(resultsArray(idx).label), height(curveTable), 1);
    curveTable.decoderMode = repmat(string(resultsArray(idx).decoderMode), height(curveTable), 1);
    summaryTable = [summaryTable; curveTable]; %#ok<AGROW>
end
summaryTable = movevars(summaryTable, ["curve", "decoderMode"], "Before", 1);

writetable(summaryTable, csvPath);
save(matPath, "resultsIdeal", "resultsFloat", "resultsFixed");

disp(summaryTable);
fprintf("Saved plot to %s\n", plotPath);
fprintf("Saved CSV to %s\n", csvPath);
fprintf("Saved MAT to %s\n", matPath);
