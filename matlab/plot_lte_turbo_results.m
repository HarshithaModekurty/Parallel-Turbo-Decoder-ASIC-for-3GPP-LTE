function fig = plot_lte_turbo_results(resultsList, outPath)
%PLOT_LTE_TURBO_RESULTS Plot BER curves for one or more sweep results.

if nargin < 2
    outPath = "";
end

if iscell(resultsList)
    resultsList = [resultsList{:}];
end

fig = figure("Visible", "off", "Color", "w");
hold on;
grid on;
for idx = 1:numel(resultsList)
    semilogy(resultsList(idx).snrDb, resultsList(idx).ber, "-o", ...
        "LineWidth", 1.5, ...
        "MarkerSize", 6, ...
        "DisplayName", resultsList(idx).label);
end
xlabel("E_b/N_0 (dB)");
ylabel("BER");
title("Turbo Decoder BER");
legend("Location", "southwest");

if strlength(string(outPath)) > 0
    outDir = fileparts(char(outPath));
    if ~isempty(outDir) && ~isfolder(outDir)
        mkdir(outDir);
    end
    drawnow;
    print(fig, char(outPath), "-dpng", "-r150");
end
end
