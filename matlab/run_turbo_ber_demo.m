%RUN_TURBO_BER_DEMO Quick BER/FER demo for the MATLAB LTE turbo decoder.
%
% This script runs two curves:
%   1) floating max-log reference
%   2) RTL-style fixed-point radix-4/windowed model
%
% The defaults are intentionally moderate so the script finishes in a
% practical amount of time. For a more paper-like sweep around K=3200, see
% the commented configuration block near the bottom.

clear;
clc;

scriptDir = fileparts(mfilename("fullpath"));
resultsDir = fullfile(scriptDir, "results");
if ~isfolder(resultsDir)
    mkdir(resultsDir);
end

baseCfg = struct();
baseCfg.k = 320;
baseCfg.snrDbList = 0.0:0.5:2.5;
baseCfg.nHalfIter = 11;
baseCfg.numFrames = 30;
baseCfg.maxBitErrors = 500;
baseCfg.maxFrameErrors = 25;
baseCfg.seed = 12345;
baseCfg.extrinsicScale = 11 / 16;
baseCfg.verbose = true;

cfgFloat = baseCfg;
cfgFloat.decoderMode = "floating";
cfgFloat.quantizeInputLLR = false;
cfgFloat.label = "floating max-log";

cfgFixed = baseCfg;
cfgFixed.decoderMode = "rtl_fixed";
cfgFixed.llrScale = 2.0;
cfgFixed.label = "RTL-style fixed radix-4/windowed";

resultsFloat = lte_turbo_ber_sweep(cfgFloat);
resultsFixed = lte_turbo_ber_sweep(cfgFixed);

resultsArray = [resultsFloat, resultsFixed];
plotPath = fullfile(resultsDir, sprintf("ber_fer_k%d_halfiter%d.png", baseCfg.k, baseCfg.nHalfIter));
plot_lte_turbo_results(resultsArray, plotPath);

summaryTable = table();
for idx = 1:numel(resultsArray)
    curveTable = struct2table(resultsArray(idx).summary);
    curveTable.curve = repmat(string(resultsArray(idx).label), height(curveTable), 1);
    summaryTable = [summaryTable; curveTable]; %#ok<AGROW>
end
summaryTable = movevars(summaryTable, "curve", "Before", 1);

csvPath = fullfile(resultsDir, sprintf("ber_fer_k%d_halfiter%d.csv", baseCfg.k, baseCfg.nHalfIter));
writetable(summaryTable, csvPath);

disp(summaryTable);
fprintf("Saved plot to %s\n", plotPath);
fprintf("Saved CSV to %s\n", csvPath);

% For a heavier K=3200 run, use:
% run("matlab/run_turbo_ber_k3200_heavy.m");
