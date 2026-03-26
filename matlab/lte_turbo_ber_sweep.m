function results = lte_turbo_ber_sweep(cfg)
%LTE_TURBO_BER_SWEEP Run an LTE-style turbo-decoder BER/FER sweep.
%   RESULTS = LTE_TURBO_BER_SWEEP(CFG) simulates a terminated LTE-like
%   rate-1/3 turbo code with QPP interleaving over AWGN using BPSK and a
%   max-log-MAP iterative decoder.
%
%   The implementation is aligned to the current repo reference flow:
%   - LTE QPP interleaver table
%   - terminated 8-state RSC constituent encoders
%   - floating max-log-MAP SISO decoding
%   - RTL-style fixed-point radix-4 windowed decoding
%   - odd half-iteration natural order / even half-iteration interleaved
%   - hard decision rule: bit = 1 if posterior LLR > 0 else 0
%
%   Required CFG fields:
%       k               Information block length
%       snrDbList       Row vector of Eb/N0 points in dB
%
%   Optional CFG fields:
%       decoderMode     "ideal_logmap", "floating", or "rtl_fixed"
%                       default "floating"
%       nHalfIter       Number of half iterations, default 11
%       numFrames       Max simulated frames per SNR, default 40
%       maxBitErrors    Early-stop threshold, default inf
%       maxFrameErrors  Early-stop threshold, default inf
%       seed            RNG seed, default 12345
%       quantizeInputLLR Enable repo-style 5-bit input quantization, default false
%       llrScale        Quantization scale before 5-bit saturation, default 2.0
%       extrinsicScale  Extrinsic scaling factor, default 11/16
%       label           Curve label for plots, default auto-generated
%       verbose         Print progress, default true

cfg = fill_defaults_local(cfg);
[f1, f2] = qpp_params_local(cfg.k);
pi = qpp_permutation_local(cfg.k, f1, f2);

rng(cfg.seed, "twister");

summary = repmat( ...
    struct( ...
        "snrDb", 0, ...
        "bitErrors", 0, ...
        "frameErrors", 0, ...
        "totalBits", 0, ...
        "totalFrames", 0, ...
        "ber", 0.0, ...
        "fer", 0.0 ...
    ), ...
    numel(cfg.snrDbList), ...
    1 ...
);

for snrIdx = 1:numel(cfg.snrDbList)
    snrDb = cfg.snrDbList(snrIdx);
    sigma2 = 1.0 / (2.0 * 10.0^(snrDb / 10.0));

    bitErrors = 0;
    frameErrors = 0;
    totalBits = 0;
    totalFrames = 0;

    while totalFrames < cfg.numFrames && bitErrors < cfg.maxBitErrors && frameErrors < cfg.maxFrameErrors
        bitsOrig = randi([0, 1], 1, cfg.k);
        bitsInt = bitsOrig(pi);

        par1 = rsc_encode_local(bitsOrig);
        par2Int = rsc_encode_local(bitsInt);

        lsysOrig = channel_llr_local(bitsOrig, sigma2);
        lpar1Orig = channel_llr_local(par1, sigma2);
        lpar2Int = channel_llr_local(par2Int, sigma2);

        if strcmp(cfg.decoderMode, "rtl_fixed")
            lsysOrigQ = quantize_input_llr_local(lsysOrig, cfg.llrScale);
            lpar1OrigQ = quantize_input_llr_local(lpar1Orig, cfg.llrScale);
            lpar2IntQ = quantize_input_llr_local(lpar2Int, cfg.llrScale);
            decode = turbo_decode_fixed_windowed_local( ...
                lsysOrigQ, ...
                lpar1OrigQ, ...
                lpar2IntQ, ...
                pi, ...
                cfg.nHalfIter ...
            );
        elseif strcmp(cfg.decoderMode, "ideal_logmap")
            decode = turbo_decode_logmap_local( ...
                lsysOrig, ...
                lpar1Orig, ...
                lpar2Int, ...
                pi, ...
                cfg.nHalfIter ...
            );
        else
            if cfg.quantizeInputLLR
                lsysOrig = quantize_input_llr_local(lsysOrig, cfg.llrScale);
                lpar1Orig = quantize_input_llr_local(lpar1Orig, cfg.llrScale);
                lpar2Int = quantize_input_llr_local(lpar2Int, cfg.llrScale);
            end

            decode = turbo_decode_maxlog_local( ...
                lsysOrig, ...
                lpar1Orig, ...
                lpar2Int, ...
                pi, ...
                cfg.nHalfIter, ...
                cfg.extrinsicScale ...
            );
        end

        hardOrig = decode.hardOrig;
        nErr = nnz(hardOrig ~= bitsOrig);

        bitErrors = bitErrors + nErr;
        frameErrors = frameErrors + (nErr > 0);
        totalBits = totalBits + cfg.k;
        totalFrames = totalFrames + 1;
    end

    summary(snrIdx).snrDb = snrDb;
    summary(snrIdx).bitErrors = bitErrors;
    summary(snrIdx).frameErrors = frameErrors;
    summary(snrIdx).totalBits = totalBits;
    summary(snrIdx).totalFrames = totalFrames;
    summary(snrIdx).ber = bitErrors / max(totalBits, 1);
    summary(snrIdx).fer = frameErrors / max(totalFrames, 1);

    if cfg.verbose
        fprintf( ...
            'mode=%s k=%d snr=%.2f dB frames=%d bit_errors=%d ber=%.6e fer=%.6e\n', ...
            cfg.decoderMode, ...
            cfg.k, ...
            snrDb, ...
            totalFrames, ...
            bitErrors, ...
            summary(snrIdx).ber, ...
            summary(snrIdx).fer ...
        );
    end
end

results = struct();
results.k = cfg.k;
results.f1 = f1;
results.f2 = f2;
results.pi = pi;
results.cfg = cfg;
results.decoderMode = cfg.decoderMode;
results.label = cfg.label;
results.summary = summary;
results.snrDb = [summary.snrDb];
results.ber = [summary.ber];
results.fer = [summary.fer];
results.bitErrors = [summary.bitErrors];
results.frameErrors = [summary.frameErrors];
results.totalBits = [summary.totalBits];
results.totalFrames = [summary.totalFrames];
end


function cfg = fill_defaults_local(cfg)
if nargin < 1 || isempty(cfg)
    cfg = struct();
end
if ~isfield(cfg, "k")
    error("cfg.k is required");
end
if ~isfield(cfg, "snrDbList")
    error("cfg.snrDbList is required");
end
if ~isfield(cfg, "decoderMode"), cfg.decoderMode = "floating"; end
if ~isfield(cfg, "nHalfIter"), cfg.nHalfIter = 11; end
if ~isfield(cfg, "numFrames"), cfg.numFrames = 40; end
if ~isfield(cfg, "maxBitErrors"), cfg.maxBitErrors = inf; end
if ~isfield(cfg, "maxFrameErrors"), cfg.maxFrameErrors = inf; end
if ~isfield(cfg, "seed"), cfg.seed = 12345; end
if ~isfield(cfg, "llrScale"), cfg.llrScale = 2.0; end
if ~isfield(cfg, "extrinsicScale"), cfg.extrinsicScale = 11 / 16; end
if ~isfield(cfg, "verbose"), cfg.verbose = true; end
cfg.decoderMode = lower(string(cfg.decoderMode));
if strcmp(cfg.decoderMode, "rtl_fixed")
    cfg.quantizeInputLLR = true;
else
    if ~isfield(cfg, "quantizeInputLLR"), cfg.quantizeInputLLR = false; end
end
if ~isfield(cfg, "label")
    if strcmp(cfg.decoderMode, "ideal_logmap")
        cfg.label = "ideal log-MAP / BCJR";
    elseif strcmp(cfg.decoderMode, "rtl_fixed")
        cfg.label = "RTL-style fixed radix-4/windowed";
    elseif cfg.quantizeInputLLR
        cfg.label = sprintf("5-bit floating max-log, ext scale %.4f", cfg.extrinsicScale);
    else
        cfg.label = sprintf("floating input LLR, ext scale %.4f", cfg.extrinsicScale);
    end
end
cfg.snrDbList = reshape(cfg.snrDbList, 1, []);
end


function parity = rsc_encode_local(bits)
state = 0;
parity = zeros(1, numel(bits));
for idx = 1:numel(bits)
    [state, parity(idx)] = rsc_step_local(state, bits(idx));
end
for tailIdx = 1:3
    uTail = tail_input_for_state_local(state);
    [state, ~] = rsc_step_local(state, uTail);
    if tailIdx == 3 && state ~= 0
        error("RSC termination failed");
    end
end
end


function [nextState, parity] = rsc_step_local(state, u)
s0 = bitand(state, 1);
s1 = bitand(bitshift(state, -1), 1);
s2 = bitand(bitshift(state, -2), 1);
fb = bitxor(bitxor(u, s0), s2);
parity = bitxor(bitxor(fb, s1), s2);
nextState = bitor(bitshift(fb, 2), bitor(bitshift(s2, 1), s1));
end


function u = tail_input_for_state_local(state)
s0 = bitand(state, 1);
s2 = bitand(bitshift(state, -2), 1);
u = bitxor(s0, s2);
end


function llr = channel_llr_local(bits, sigma2)
x = 1.0 - 2.0 * double(bits);
y = x + sqrt(sigma2) * randn(size(bits));
llr = 2.0 * y / sigma2;
end


function q = quantize_input_llr_local(llr, scale)
q = round(llr .* scale);
q = min(max(q, -16), 15);
q = double(q);
end


function decode = turbo_decode_maxlog_local(lsysOrig, lpar1Orig, lpar2Int, pi, nHalfIter, extrinsicScale)
kLen = numel(lsysOrig);
lsysInt = lsysOrig(pi);

lapriOrig = zeros(1, kLen);
lapriInt = zeros(1, kLen);
postOrig = zeros(1, kLen);
postInt = zeros(1, kLen);
hardOrig = zeros(1, kLen);
hardInt = zeros(1, kLen);

for half = 1:nHalfIter
    if mod(half - 1, 2) == 0
        [ext1Orig, post1Orig] = siso_maxlog_local(lsysOrig, lpar1Orig, lapriOrig, extrinsicScale);
        lapriInt = ext1Orig(pi);
        if half == nHalfIter
            postOrig = post1Orig;
            hardOrig = double(postOrig > 0.0);
            postInt = postOrig(pi);
            hardInt = hardOrig(pi);
        end
    else
        [ext2Int, post2Int] = siso_maxlog_local(lsysInt, lpar2Int, lapriInt, extrinsicScale);
        lapriOrig = zeros(1, kLen);
        lapriOrig(pi) = ext2Int;
        if half == nHalfIter
            postInt = post2Int;
            hardInt = double(postInt > 0.0);
            postOrig = zeros(1, kLen);
            hardOrig = zeros(1, kLen);
            postOrig(pi) = postInt;
            hardOrig(pi) = hardInt;
        end
    end
end

decode = struct();
decode.postOrig = postOrig;
decode.postInt = postInt;
decode.hardOrig = hardOrig;
decode.hardInt = hardInt;
end


function decode = turbo_decode_logmap_local(lsysOrig, lpar1Orig, lpar2Int, pi, nHalfIter)
kLen = numel(lsysOrig);
lsysInt = lsysOrig(pi);

lapriOrig = zeros(1, kLen);
lapriInt = zeros(1, kLen);
postOrig = zeros(1, kLen);
postInt = zeros(1, kLen);
hardOrig = zeros(1, kLen);
hardInt = zeros(1, kLen);

for half = 1:nHalfIter
    if mod(half - 1, 2) == 0
        [ext1Orig, post1Orig] = siso_logmap_local(lsysOrig, lpar1Orig, lapriOrig);
        lapriInt = ext1Orig(pi);
        if half == nHalfIter
            postOrig = post1Orig;
            hardOrig = double(postOrig > 0.0);
            postInt = postOrig(pi);
            hardInt = hardOrig(pi);
        end
    else
        [ext2Int, post2Int] = siso_logmap_local(lsysInt, lpar2Int, lapriInt);
        lapriOrig = zeros(1, kLen);
        lapriOrig(pi) = ext2Int;
        if half == nHalfIter
            postInt = post2Int;
            hardInt = double(postInt > 0.0);
            postOrig = zeros(1, kLen);
            hardOrig = zeros(1, kLen);
            postOrig(pi) = postInt;
            hardOrig(pi) = hardInt;
        end
    end
end

decode = struct();
decode.postOrig = postOrig;
decode.postInt = postInt;
decode.hardOrig = hardOrig;
decode.hardInt = hardInt;
end


function decode = turbo_decode_fixed_windowed_local(lsysOrigQ, lpar1OrigQ, lpar2IntQ, pi, nHalfIter)
kLen = numel(lsysOrigQ);
lsysIntQ = lsysOrigQ(pi);

lapriOrig = zeros(1, kLen);
lapriInt = zeros(1, kLen);
postOrig = zeros(1, kLen);
postInt = zeros(1, kLen);

for half = 1:nHalfIter
    if mod(half - 1, 2) == 0
        [ext1Orig, post1Orig] = siso_fixed_windowed_local( ...
            lsysOrigQ, ...
            lpar1OrigQ, ...
            lapriOrig, ...
            true, ...
            true ...
        );
        lapriInt = ext1Orig(pi);
        if half == nHalfIter
            postOrig = post1Orig;
            postInt = postOrig(pi);
        end
    else
        [ext2Int, post2Int] = siso_fixed_windowed_local( ...
            lsysIntQ, ...
            lpar2IntQ, ...
            lapriInt, ...
            true, ...
            true ...
        );
        lapriOrig = zeros(1, kLen);
        lapriOrig(pi) = ext2Int;
        if half == nHalfIter
            postInt = post2Int;
            postOrig = zeros(1, kLen);
            postOrig(pi) = post2Int;
        end
    end
end

decode = struct();
decode.postOrig = postOrig;
decode.postInt = postInt;
decode.hardOrig = double(postOrig > 0);
decode.hardInt = double(postInt > 0);
end


function [ext, post] = siso_fixed_windowed_local(lsys, lpar, lapri, segFirst, segLast)
segLen = numel(lsys);
pairCount = floor((segLen + 1) / 2);
winCount = floor((segLen + 29) / 30);

sysEvenMem = zeros(1, pairCount);
sysOddMem = zeros(1, pairCount);
parEvenMem = zeros(1, pairCount);
parOddMem = zeros(1, pairCount);
apriEvenMem = zeros(1, pairCount);
apriOddMem = zeros(1, pairCount);
gammaMem = zeros(pairCount, 16);
alphaSeedMem = zeros(max(1, winCount), 8);

for pairIdx = 0:(pairCount - 1)
    evenIdx = pairIdx * 2 + 1;
    oddIdx = evenIdx + 1;
    sysEvenMem(pairIdx + 1) = lsys(evenIdx);
    parEvenMem(pairIdx + 1) = lpar(evenIdx);
    apriEvenMem(pairIdx + 1) = lapri(evenIdx);
    if oddIdx <= segLen
        sysOddMem(pairIdx + 1) = lsys(oddIdx);
        parOddMem(pairIdx + 1) = lpar(oddIdx);
        apriOddMem(pairIdx + 1) = lapri(oddIdx);
    end
    gammaMem(pairIdx + 1, :) = radix4_bmu_fixed_local( ...
        sysEvenMem(pairIdx + 1), ...
        sysOddMem(pairIdx + 1), ...
        parEvenMem(pairIdx + 1), ...
        parOddMem(pairIdx + 1), ...
        apriEvenMem(pairIdx + 1), ...
        apriOddMem(pairIdx + 1) ...
    );
end

if segFirst
    startSeed = terminated_state_fixed_local();
else
    startSeed = zeros(1, 8);
end
if segLast
    endSeed = terminated_state_fixed_local();
else
    endSeed = zeros(1, 8);
end

alphaSeedMem(1, :) = startSeed;
alphaCur = startSeed;
for winIdx = 0:(winCount - 1)
    startPair = winIdx * 15;
    winPairCount = window_pairs_for_local(segLen, winIdx);
    for localIdx = 0:(winPairCount - 1)
        alphaCur = radix4_acs_fixed_local(alphaCur, gammaMem(startPair + localIdx + 1, :), false);
    end
    if winIdx + 1 < winCount
        alphaSeedMem(winIdx + 2, :) = alphaCur;
    end
end

ext = zeros(1, segLen);
post = zeros(1, segLen);
for winIdx = (winCount - 1):-1:0
    startPair = winIdx * 15;
    winPairCount = window_pairs_for_local(segLen, winIdx);

    if winIdx == winCount - 1
        betaSeed = endSeed;
    else
        betaSeed = zeros(1, 8);
        nextStartPair = (winIdx + 1) * 15;
        nextPairCount = window_pairs_for_local(segLen, winIdx + 1);
        for localIdx = (nextPairCount - 1):-1:0
            betaSeed = radix4_acs_fixed_local(betaSeed, gammaMem(nextStartPair + localIdx + 1, :), true);
        end
    end

    alphaLocal = metric_init_neg_local() * ones(winPairCount, 8);
    gammaLocal = zeros(winPairCount, 16);
    alphaCur = alphaSeedMem(winIdx + 1, :);
    for localIdx = 0:(winPairCount - 1)
        pairIdx = startPair + localIdx;
        alphaLocal(localIdx + 1, :) = alphaCur;
        gammaLocal(localIdx + 1, :) = gammaMem(pairIdx + 1, :);
        alphaCur = radix4_acs_fixed_local(alphaCur, gammaLocal(localIdx + 1, :), false);
    end

    betaCur = betaSeed;
    for localIdx = (winPairCount - 1):-1:0
        pairIdx = startPair + localIdx;
        [extEven, extOdd, postEven, postOdd] = radix4_extract_windowed_fixed_local( ...
            alphaLocal(localIdx + 1, :), ...
            betaCur, ...
            sysEvenMem(pairIdx + 1), ...
            sysOddMem(pairIdx + 1), ...
            parEvenMem(pairIdx + 1), ...
            parOddMem(pairIdx + 1), ...
            apriEvenMem(pairIdx + 1), ...
            apriOddMem(pairIdx + 1) ...
        );
        evenIdx = pairIdx * 2 + 1;
        oddIdx = evenIdx + 1;
        ext(evenIdx) = extEven;
        post(evenIdx) = postEven;
        if oddIdx <= segLen
            ext(oddIdx) = extOdd;
            post(oddIdx) = postOdd;
        end
        betaCur = radix4_acs_fixed_local(betaCur, gammaLocal(localIdx + 1, :), true);
    end
end
end


function out = radix4_bmu_fixed_local(sysEven, sysOdd, parEven, parOdd, apriEven, apriOdd)
g0 = branch_metric_unit_fixed_local(sysEven, parEven, apriEven);
g1 = branch_metric_unit_fixed_local(sysOdd, parOdd, apriOdd);
out = zeros(1, 16);
for u0 = 0:1
    for p0 = 0:1
        for u1 = 0:1
            for p1 = 0:1
                idx = (u0 * 8) + (p0 * 4) + (u1 * 2) + p1 + 1;
                out(idx) = mod_add_fixed_local(g0(u0 * 2 + p0 + 1), g1(u1 * 2 + p1 + 1));
            end
        end
    end
end
end


function out = branch_metric_unit_fixed_local(lsys, lpar, lapri)
tmp = mod_add_fixed_local(lsys, lapri);
out = zeros(1, 4);
out(1) = wrap_metric_local(floor(mod_add_fixed_local(tmp, lpar) / 2));
out(2) = wrap_metric_local(floor(mod_add_fixed_local(tmp, -lpar) / 2));
out(3) = wrap_metric_local(floor(mod_add_fixed_local(mod_add_fixed_local(-lsys, -lapri), lpar) / 2));
out(4) = wrap_metric_local(floor(mod_add_fixed_local(mod_add_fixed_local(-lsys, -lapri), -lpar) / 2));
end


function out = radix4_acs_fixed_local(stateIn, gammaIn, modeBwd)
trellis = radix4_trellis_local(modeBwd);
out = zeros(1, 8);
for s = 1:8
    paths = trellis{s};
    m0 = mod_add_fixed_local(stateIn(paths(1, 1)), gammaIn(paths(1, 2)));
    m1 = mod_add_fixed_local(stateIn(paths(2, 1)), gammaIn(paths(2, 2)));
    m2 = mod_add_fixed_local(stateIn(paths(3, 1)), gammaIn(paths(3, 2)));
    m3 = mod_add_fixed_local(stateIn(paths(4, 1)), gammaIn(paths(4, 2)));
    out(s) = mod_max4_fixed_local(m0, m1, m2, m3);
end
end


function [ext0, ext1, post0, post1] = radix4_extract_windowed_fixed_local(alphaIn, betaIn, sysEven, sysOdd, parEven, parOdd, apriEven, apriOdd)
[ns, par] = trellis_tables_local();
g0 = branch_metric_unit_fixed_local(sysEven, parEven, apriEven);
g1 = branch_metric_unit_fixed_local(sysOdd, parOdd, apriOdd);

alphaMid = metric_init_neg_local() * ones(1, 8);
betaMid = metric_init_neg_local() * ones(1, 8);
alphaMidSet = false(1, 8);
betaMidSet = false(1, 8);

max0u0 = 0;
max1u0 = 0;
max0u1 = 0;
max1u1 = 0;
init0u0 = true;
init1u0 = true;
init0u1 = true;
init1u1 = true;

for startState = 0:7
    for u = 0:1
        midState = ns(startState + 1, u + 1);
        parity = par(startState + 1, u + 1);
        idx = u * 2 + parity + 1;
        metricV = mod_add_fixed_local(alphaIn(startState + 1), g0(idx));
        if ~alphaMidSet(midState + 1)
            alphaMid(midState + 1) = metricV;
            alphaMidSet(midState + 1) = true;
        else
            alphaMid(midState + 1) = mod_max_fixed_local(alphaMid(midState + 1), metricV);
        end
    end
end

for midState = 0:7
    for u = 0:1
        endState = ns(midState + 1, u + 1);
        parity = par(midState + 1, u + 1);
        idx = u * 2 + parity + 1;
        metricV = mod_add_fixed_local(g1(idx), betaIn(endState + 1));
        if ~betaMidSet(midState + 1)
            betaMid(midState + 1) = metricV;
            betaMidSet(midState + 1) = true;
        else
            betaMid(midState + 1) = mod_max_fixed_local(betaMid(midState + 1), metricV);
        end
    end
end

for startState = 0:7
    for u = 0:1
        midState = ns(startState + 1, u + 1);
        parity = par(startState + 1, u + 1);
        idx = u * 2 + parity + 1;
        metricV = mod_add_fixed_local(mod_add_fixed_local(alphaIn(startState + 1), g0(idx)), betaMid(midState + 1));
        if u == 0
            if init0u0
                max0u0 = metricV;
                init0u0 = false;
            else
                max0u0 = mod_max_fixed_local(max0u0, metricV);
            end
        else
            if init1u0
                max1u0 = metricV;
                init1u0 = false;
            else
                max1u0 = mod_max_fixed_local(max1u0, metricV);
            end
        end
    end
end

for midState = 0:7
    for u = 0:1
        endState = ns(midState + 1, u + 1);
        parity = par(midState + 1, u + 1);
        idx = u * 2 + parity + 1;
        metricV = mod_add_fixed_local(mod_add_fixed_local(alphaMid(midState + 1), g1(idx)), betaIn(endState + 1));
        if u == 0
            if init0u1
                max0u1 = metricV;
                init0u1 = false;
            else
                max0u1 = mod_max_fixed_local(max0u1, metricV);
            end
        else
            if init1u1
                max1u1 = metricV;
                init1u1 = false;
            else
                max1u1 = mod_max_fixed_local(max1u1, metricV);
            end
        end
    end
end

post0 = sat_post_fixed_local(mod_sub_fixed_local(max1u0, max0u0));
post1 = sat_post_fixed_local(mod_sub_fixed_local(max1u1, max0u1));
ext0 = scale_ext_fixed_local(mod_sub_fixed_local(mod_sub_fixed_local(post0, sysEven), apriEven));
ext1 = scale_ext_fixed_local(mod_sub_fixed_local(mod_sub_fixed_local(post1, sysOdd), apriOdd));
end


function value = window_pairs_for_local(segLen, winIdx)
startBit = winIdx * 30;
if segLen <= startBit
    value = 0;
    return;
end
remBits = segLen - startBit;
if remBits > 30
    remBits = 30;
end
value = floor((remBits + 1) / 2);
end


function value = metric_init_neg_local()
value = -256;
end


function state = terminated_state_fixed_local()
state = [0, metric_init_neg_local() * ones(1, 7)];
end


function value = wrap_metric_local(v)
value = mod(v + 512, 1024) - 512;
end


function value = mod_add_fixed_local(a, b)
value = wrap_metric_local(a + b);
end


function value = mod_sub_fixed_local(a, b)
value = wrap_metric_local(a - b);
end


function value = mod_max_fixed_local(a, b)
if mod_sub_fixed_local(a, b) >= 0
    value = a;
else
    value = b;
end
end


function value = mod_max4_fixed_local(a, b, c, d)
value = mod_max_fixed_local(mod_max_fixed_local(a, b), mod_max_fixed_local(c, d));
end


function value = sat_ext_fixed_local(v)
value = min(max(v, -32), 31);
end


function value = sat_post_fixed_local(v)
value = min(max(v, -64), 63);
end


function value = scale_ext_fixed_local(v)
value = sat_ext_fixed_local(floor((11 * v) / 16));
end


function trellis = radix4_trellis_local(modeBwd)
persistent fwdTrellis bwdTrellis
if isempty(fwdTrellis)
    [ns, par] = trellis_tables_local();
    fwdTrellis = cell(8, 1);
    bwdTrellis = cell(8, 1);
    for idx = 1:8
        fwdTrellis{idx} = zeros(0, 2);
        bwdTrellis{idx} = zeros(0, 2);
    end
    for startState = 0:7
        for u0 = 0:1
            for u1 = 0:1
                midState = ns(startState + 1, u0 + 1);
                nextState = ns(midState + 1, u1 + 1);
                p0 = par(startState + 1, u0 + 1);
                p1 = par(midState + 1, u1 + 1);
                gammaIdx = (u0 * 8) + (p0 * 4) + (u1 * 2) + p1 + 1;
                bwdTrellis{startState + 1}(end + 1, :) = [nextState + 1, gammaIdx]; %#ok<AGROW>
                fwdTrellis{nextState + 1}(end + 1, :) = [startState + 1, gammaIdx]; %#ok<AGROW>
            end
        end
    end
end
if modeBwd
    trellis = bwdTrellis;
else
    trellis = fwdTrellis;
end
end


function [ext, post] = siso_maxlog_local(lsys, lpar, lapri, extrinsicScale)
[ns, par] = trellis_tables_local();
kLen = numel(lsys);
negInf = -1.0e30;

alpha = negInf * ones(kLen + 1, 8);
beta = negInf * ones(kLen + 1, 8);

alpha(1, 1) = 0.0;
for k = 1:kLen
    for ps = 1:8
        a = alpha(k, ps);
        if a <= negInf / 2
            continue;
        end
        for uIdx = 1:2
            nextState = ns(ps, uIdx) + 1;
            parity = par(ps, uIdx);
            metric = a + gamma_local(lsys(k), lpar(k), lapri(k), uIdx - 1, parity);
            if metric > alpha(k + 1, nextState)
                alpha(k + 1, nextState) = metric;
            end
        end
    end
    alpha(k + 1, :) = alpha(k + 1, :) - max(alpha(k + 1, :));
end

beta(kLen + 1, 1) = 0.0;
for k = kLen:-1:1
    for ps = 1:8
        bestMetric = negInf;
        for uIdx = 1:2
            nextState = ns(ps, uIdx) + 1;
            parity = par(ps, uIdx);
            metric = beta(k + 1, nextState) + gamma_local(lsys(k), lpar(k), lapri(k), uIdx - 1, parity);
            if metric > bestMetric
                bestMetric = metric;
            end
        end
        beta(k, ps) = bestMetric;
    end
    beta(k, :) = beta(k, :) - max(beta(k, :));
end

post = zeros(1, kLen);
ext = zeros(1, kLen);
for k = 1:kLen
    max0 = negInf;
    max1 = negInf;
    for ps = 1:8
        a = alpha(k, ps);
        if a <= negInf / 2
            continue;
        end
        for uIdx = 1:2
            nextState = ns(ps, uIdx) + 1;
            parity = par(ps, uIdx);
            metric = a + gamma_local(lsys(k), lpar(k), lapri(k), uIdx - 1, parity) + beta(k + 1, nextState);
            if uIdx == 1
                if metric > max0
                    max0 = metric;
                end
            else
                if metric > max1
                    max1 = metric;
                end
            end
        end
    end
    post(k) = max1 - max0;
    ext(k) = extrinsicScale * (post(k) - lsys(k) - lapri(k));
end
end


function [ext, post] = siso_logmap_local(lsys, lpar, lapri)
[ns, par] = trellis_tables_local();
kLen = numel(lsys);
negInf = -1.0e30;

alpha = negInf * ones(kLen + 1, 8);
beta = negInf * ones(kLen + 1, 8);

alpha(1, 1) = 0.0;
for k = 1:kLen
    for ps = 1:8
        a = alpha(k, ps);
        if a <= negInf / 2
            continue;
        end
        for uIdx = 1:2
            nextState = ns(ps, uIdx) + 1;
            parity = par(ps, uIdx);
            metric = a + gamma_local(lsys(k), lpar(k), lapri(k), uIdx - 1, parity);
            alpha(k + 1, nextState) = log_add_local(alpha(k + 1, nextState), metric);
        end
    end
    alpha(k + 1, :) = alpha(k + 1, :) - max(alpha(k + 1, :));
end

beta(kLen + 1, 1) = 0.0;
for k = kLen:-1:1
    for ps = 1:8
        acc = negInf;
        for uIdx = 1:2
            nextState = ns(ps, uIdx) + 1;
            parity = par(ps, uIdx);
            metric = beta(k + 1, nextState) + gamma_local(lsys(k), lpar(k), lapri(k), uIdx - 1, parity);
            acc = log_add_local(acc, metric);
        end
        beta(k, ps) = acc;
    end
    beta(k, :) = beta(k, :) - max(beta(k, :));
end

post = zeros(1, kLen);
ext = zeros(1, kLen);
for k = 1:kLen
    sum0 = negInf;
    sum1 = negInf;
    for ps = 1:8
        a = alpha(k, ps);
        if a <= negInf / 2
            continue;
        end
        for uIdx = 1:2
            nextState = ns(ps, uIdx) + 1;
            parity = par(ps, uIdx);
            metric = a + gamma_local(lsys(k), lpar(k), lapri(k), uIdx - 1, parity) + beta(k + 1, nextState);
            if uIdx == 1
                sum0 = log_add_local(sum0, metric);
            else
                sum1 = log_add_local(sum1, metric);
            end
        end
    end
    post(k) = sum1 - sum0;
    ext(k) = post(k) - lsys(k) - lapri(k);
end
end


function value = log_add_local(a, b)
if a < b
    tmp = a;
    a = b;
    b = tmp;
end
if b <= -1.0e29
    value = a;
else
    value = a + log1p(exp(b - a));
end
end


function value = gamma_local(lsys, lpar, lapri, u, parity)
if u == 0
    su = 1.0;
else
    su = -1.0;
end
if parity == 0
    sp = 1.0;
else
    sp = -1.0;
end
value = 0.5 * (su * (lsys + lapri) + sp * lpar);
end


function [ns, par] = trellis_tables_local()
persistent nsPersistent parPersistent
if isempty(nsPersistent)
    nsPersistent = zeros(8, 2);
    parPersistent = zeros(8, 2);
    for state = 0:7
        for u = 0:1
            [nextState, parity] = rsc_step_local(state, u);
            nsPersistent(state + 1, u + 1) = nextState;
            parPersistent(state + 1, u + 1) = parity;
        end
    end
end
ns = nsPersistent;
par = parPersistent;
end


function pi = qpp_permutation_local(k, f1, f2)
i = 0:(k - 1);
pi = mod(f1 .* i + f2 .* i .* i, k) + 1;
end


function [f1, f2] = qpp_params_local(k)
table = [
      40    3   10;
      48    7   12;
      56   19   42;
      64    7   16;
      72    7   18;
      80   11   20;
      88    5   22;
      96   11   24;
     104    7   26;
     112   41   84;
     120  103   90;
     128   15   32;
     136    9   34;
     144   17  108;
     152    9   38;
     160   21  120;
     168  101   84;
     176   21   44;
     184   57   46;
     192   23   48;
     200   13   50;
     208   27   52;
     216   11   36;
     224   27   56;
     232   85   58;
     240   29   60;
     248   33   62;
     256   15   32;
     264   17  198;
     272   33   68;
     280  103  210;
     288   19   36;
     296   19   74;
     304   37   76;
     312   19   78;
     320   21  120;
     328   21   82;
     336  115   84;
     344  193   86;
     352   21   44;
     360  133   90;
     368   81   46;
     376   45   94;
     384   23   48;
     392  243   98;
     400  151   40;
     408  155  102;
     416   25   52;
     424   51  106;
     432   47   72;
     440   91  110;
     448   29  168;
     456   29  114;
     464  247   58;
     472   29  118;
     480   89  180;
     488   91  122;
     496  157   62;
     504   55   84;
     512   31   64;
     528   17   66;
     544   35   68;
     560  227  420;
     576   65   96;
     592   19   74;
     608   37   76;
     624   41  234;
     640   39   80;
     656  185   82;
     672   43  252;
     688   21   86;
     704  155   44;
     720   79  120;
     736  139   92;
     752   23   94;
     768  217   48;
     784   25   98;
     800   17   80;
     816  127  102;
     832   25   52;
     848  239  106;
     864   17   48;
     880  137  110;
     896  215  112;
     912   29  114;
     928   15   58;
     944  147  118;
     960   29   60;
     976   59  122;
     992   65  124;
    1008   55   84;
    1024   31   64;
    1056   17   66;
    1088  171  204;
    1120   67  140;
    1152   35   72;
    1184   19   74;
    1216   39   76;
    1248   19   78;
    1280  199  240;
    1312   21   82;
    1344  211  252;
    1376   21   86;
    1408   43   88;
    1440  149   60;
    1472   45   92;
    1504   49  846;
    1536   71   48;
    1568   13   28;
    1600   17   80;
    1632   25  102;
    1664  183  104;
    1696   55  954;
    1728  127   96;
    1760   27  110;
    1792   29  112;
    1824   29  114;
    1856   57  116;
    1888   45  354;
    1920   31  120;
    1952   59  610;
    1984  185  124;
    2016  113  420;
    2048   31   64;
    2112   17   66;
    2176  171  136;
    2240  209  420;
    2304  253  216;
    2368  367  444;
    2432  265  456;
    2496  181  468;
    2560   39   80;
    2624   27  164;
    2688  127  504;
    2752  143  172;
    2816   43   88;
    2880   29  300;
    2944   45   92;
    3008  157  188;
    3072   47   96;
    3136   13   28;
    3200  111  240;
    3264  443  204;
    3328   51  104;
    3392   51  212;
    3456  451  192;
    3520  257  220;
    3584   57  336;
    3648  313  228;
    3712  271  232;
    3776  179  236;
    3840  331  120;
    3904  363  244;
    3968  375  248;
    4032  127  168;
    4096   31   64;
    4160   33  130;
    4224   43  264;
    4288   33  134;
    4352  477  408;
    4416   35  138;
    4480  233  280;
    4544  357  142;
    4608  337  480;
    4672   37  146;
    4736   71  444;
    4800   71  120;
    4864   37  152;
    4928   39  462;
    4992  127  234;
    5056   39  158;
    5120   39   80;
    5184   31   96;
    5248  113  902;
    5312   41  166;
    5376  251  336;
    5440   43  170;
    5504   21   86;
    5568   43  174;
    5632   45  176;
    5696   45  178;
    5760  161  120;
    5824   89  182;
    5888  323  184;
    5952   47  186;
    6016   23   94;
    6080   47  190;
    6144  263  480;
];
rowIdx = find(table(:, 1) == k, 1, "first");
if isempty(rowIdx)
    error("K=%d is not present in the LTE QPP table", k);
end
f1 = table(rowIdx, 2);
f2 = table(rowIdx, 3);
end
