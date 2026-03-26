%RUN_COMPARE_MODEL_VS_RTL_K3200 Overlay MATLAB model BER against actual RTL BER.

clear;
clc;

scriptDir = fileparts(mfilename("fullpath"));
resultsDir = fullfile(scriptDir, "results");
if ~isfolder(resultsDir)
    mkdir(resultsDir);
end

matPath = fullfile(resultsDir, "ber_fer_k3200_halfiter11_heavy.mat");
if isfile(matPath)
    load(matPath, "resultsIdeal", "resultsFloat", "resultsFixed");
else
    run(fullfile(scriptDir, "run_turbo_ber_k3200_heavy.m"));
    load(matPath, "resultsIdeal", "resultsFloat", "resultsFixed");
end

rtlSweepCsv = fullfile(scriptDir, "..", "sim_vectors", "ber_sweep", "ber_sweep_summary.csv");
rtlResults = load_rtl_ber_summary(rtlSweepCsv, 3200);

plotPath = fullfile(resultsDir, "ber_compare_model_vs_rtl_k3200.png");
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

csvPath = fullfile(resultsDir, "ber_compare_model_vs_rtl_k3200.csv");
writetable(compareTable, csvPath);

dumpVecPath = fullfile(scriptDir, "..", "sim_vectors", "lte_frame_input_vectors.txt");
dumpLlrPath = fullfile(scriptDir, "..", "tb_turbo_top_final_llrs.txt");
singleDumpReport = compare_rtl_llr_dump(dumpVecPath, dumpLlrPath);
singleDumpPath = fullfile(resultsDir, "current_root_rtl_dump_report.txt");
fid = fopen(singleDumpPath, "w");
fprintf(fid, "Current Root RTL Dump Report\n");
fprintf(fid, "vector_file=%s\n", dumpVecPath);
fprintf(fid, "llr_file=%s\n", dumpLlrPath);
fprintf(fid, "k=%d\n", singleDumpReport.k);
fprintf(fid, "valid_outputs=%d\n", singleDumpReport.validOutputs);
fprintf(fid, "missing_outputs=%d\n", singleDumpReport.missingOutputs);
fprintf(fid, "bit_errors=%d\n", singleDumpReport.bitErrors);
fprintf(fid, "ber_total=%.12f\n", singleDumpReport.berTotal);
fprintf(fid, "ber_seen_only=%.12f\n", singleDumpReport.berSeenOnly);
fprintf(fid, "ber_with_missing_as_errors=%.12f\n", singleDumpReport.berWithMissingAsErrors);
fprintf(fid, "hard_one_count=%d\n", singleDumpReport.hardOneCount);
fclose(fid);

disp(compareTable);
fprintf("Saved overlay plot to %s\n", plotPath);
fprintf("Saved overlay CSV to %s\n", csvPath);
fprintf("Saved single-dump report to %s\n", singleDumpPath);
