function report = compare_rtl_llr_dump(vecPath, llrPath)
%COMPARE_RTL_LLR_DUMP Compute BER from one RTL final-LLR dump.

vecLines = string(splitlines(fileread(vecPath)));
vecLines = vecLines(strlength(strtrim(vecLines)) > 0);
header = sscanf(vecLines(1), "%d");
if isempty(header)
    error("Malformed vector file header: %s", vecPath);
end
k = header(1);

bitOrig = zeros(k, 1);
for lineIdx = 2:numel(vecLines)
    line = strtrim(vecLines(lineIdx));
    if startsWith(line, "#")
        continue;
    end
    vals = sscanf(line, "%d");
    if numel(vals) < 2
        continue;
    end
    idx = vals(1) + 1;
    bitOrig(idx) = vals(2);
end

finalLlr = zeros(k, 1);
seen = zeros(k, 1);
llrLines = string(splitlines(fileread(llrPath)));
for lineIdx = 1:numel(llrLines)
    line = strtrim(llrLines(lineIdx));
    if strlength(line) == 0 || startsWith(line, "#")
        continue;
    end
    vals = sscanf(line, "%d");
    if numel(vals) < 3
        continue;
    end
    idx = vals(1) + 1;
    finalLlr(idx) = vals(2);
    seen(idx) = vals(3);
end

hard = double(finalLlr > 0);
validMask = (seen == 1);
bitErrors = nnz(hard(validMask) ~= bitOrig(validMask));
missingOutputs = nnz(~validMask);
validOutputs = nnz(validMask);

report = struct();
report.k = k;
report.validOutputs = validOutputs;
report.missingOutputs = missingOutputs;
report.bitErrors = bitErrors;
report.berTotal = bitErrors / max(k, 1);
report.berSeenOnly = bitErrors / max(validOutputs, 1);
report.berWithMissingAsErrors = (bitErrors + missingOutputs) / max(k, 1);
report.hardOneCount = nnz(hard(validMask));
report.bitOrig = bitOrig;
report.finalLlr = finalLlr;
report.seen = seen;
report.hard = hard;
end
