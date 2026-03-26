function results = load_rtl_ber_summary(csvPath, kFilter)
%LOAD_RTL_BER_SUMMARY Load actual RTL BER sweep data from CSV.

if nargin < 2
    kFilter = [];
end

tbl = readtable(csvPath, "TextType", "string");
if ~isempty(kFilter)
    tbl = tbl(tbl.k == kFilter, :);
end
tbl = sortrows(tbl, "snr_db");

results = struct();
results.k = [];
if ~isempty(tbl)
    results.k = tbl.k(1);
end
results.f1 = [];
results.f2 = [];
results.pi = [];
results.cfg = struct("sourceCsv", string(csvPath));
results.decoderMode = "rtl_actual";
results.label = "actual RTL BER";
results.summary = repmat( ...
    struct( ...
        "snrDb", 0, ...
        "bitErrors", 0, ...
        "frameErrors", NaN, ...
        "totalBits", 0, ...
        "totalFrames", NaN, ...
        "ber", 0.0, ...
        "fer", NaN ...
    ), ...
    height(tbl), ...
    1 ...
);

for idx = 1:height(tbl)
    results.summary(idx).snrDb = tbl.snr_db(idx);
    results.summary(idx).bitErrors = tbl.bit_errors(idx);
    if ismember("frame_errors", tbl.Properties.VariableNames)
        results.summary(idx).frameErrors = tbl.frame_errors(idx);
    else
        results.summary(idx).frameErrors = NaN;
    end
    results.summary(idx).totalBits = tbl.total_bits(idx);
    if ismember("frames_run", tbl.Properties.VariableNames)
        results.summary(idx).totalFrames = tbl.frames_run(idx);
    else
        results.summary(idx).totalFrames = NaN;
    end
    results.summary(idx).ber = tbl.ber_total(idx);
    if ismember("fer", tbl.Properties.VariableNames)
        results.summary(idx).fer = tbl.fer(idx);
    else
        results.summary(idx).fer = NaN;
    end
end

results.snrDb = [results.summary.snrDb];
results.ber = [results.summary.ber];
results.fer = [results.summary.fer];
results.bitErrors = [results.summary.bitErrors];
results.frameErrors = [results.summary.frameErrors];
results.totalBits = [results.summary.totalBits];
results.totalFrames = [results.summary.totalFrames];
end
