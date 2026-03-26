# FPGA Deviation Report

Date: 2026-03-25

## Scope

This report explains which RTL blocks from the paper-oriented architecture are not used by the current active top module, what has deviated from the JSSC paper implementation, and why those deviations were made for FPGA synthesis on the current Vivado target.

## Direct Answer

The current active top module, [rtl/turbo_decoder_top.vhd](c:/VAMSHI/IIT Mandi Academic Folder/IITM 6th Sem/DVAD/TURBO_DECODER_HDL/Parallel-Turbo-Decoder-ASIC-for-3GPP-LTE/rtl/turbo_decoder_top.vhd), does not instantiate:

- `qpp_parallel_scheduler`
- `turbo_iteration_ctrl`
- `batcher_router`
- `batcher_master`
- `batcher_slave`
- `multiport_row_bram`
- `folded_llr_ram`

Those blocks belong to the older paper-driven parallel architecture kept in [rtl/turbo_decoder_top_parallel8_backup.vhd](c:/VAMSHI/IIT Mandi Academic Folder/IITM 6th Sem/DVAD/TURBO_DECODER_HDL/Parallel-Turbo-Decoder-ASIC-for-3GPP-LTE/rtl/turbo_decoder_top_parallel8_backup.vhd), where the following are instantiated directly:

- `turbo_iteration_ctrl` at line 212
- `qpp_parallel_scheduler` at lines 265 and 281
- `batcher_master` at lines 297 and 310
- `multiport_row_bram` across the memory banks starting at line 323
- `batcher_slave` across the router/unrouter path starting at line 678

`batcher_router` exists as a wrapper module, but it is not instantiated in the active top and is not even used by the backup top. The backup top directly instantiates `batcher_master` and `batcher_slave`, so `batcher_router` is effectively a parked helper block plus a standalone testbench target.

## What The Active Top Actually Uses

The active top, [rtl/turbo_decoder_top.vhd](c:/VAMSHI/IIT Mandi Academic Folder/IITM 6th Sem/DVAD/TURBO_DECODER_HDL/Parallel-Turbo-Decoder-ASIC-for-3GPP-LTE/rtl/turbo_decoder_top.vhd), is a folded single-SISO controller. Its main structure is:

- Three `simple_dp_bram` instances at lines 169, 187, and 205
- One `siso_maxlogmap` instance at line 222
- A monolithic internal FSM handling iteration scheduling, interleaving, deinterleaving, and frame movement
- Direct scalar use of `qpp_value(...)` inside states such as `ST_BUILD_SYS_INT`, `ST_EXT_NAT_TO_INT`, `ST_EXT_INT_TO_NAT`, and `ST_FINAL_INT_TO_NAT`

The SISO is driven as one whole-frame engine, not as a segmented parallel bank:

- `seg_first => '1'` at line 231
- `seg_last  => '1'` at line 232

That means the active implementation does not run the paper's eight concurrent MAP windows with a contention-management network around them. It runs one SISO over the frame and performs the needed permutations and extrinsic moves with sequential top-level control.

## Major Deviations From The Paper

### 1. Parallel SISOs Removed

Paper intent:

- Multiple SISOs operate in parallel on different frame segments.
- Throughput comes from concurrent trellis processing.

Current implementation:

- One `siso_maxlogmap` is instantiated in the active top.
- The frame is processed in a folded manner instead of eight-lane parallel execution.

Reason for removal:

- The parallel architecture was far more expensive in LUTs on the target FPGA.
- Your earlier synthesis history already showed the parallel version blowing up badly in LUT use and giving poor memory inference.

### 2. Dedicated Iteration Controller Removed From Active Path

Paper intent:

- A separate global control block manages iteration and half-iteration sequencing.

Current implementation:

- `turbo_iteration_ctrl` is not instantiated in the active top.
- Iteration sequencing is absorbed into the top-level FSM and local counters.

Reason for removal:

- On FPGA, flattening control into one FSM avoids extra glue logic, interconnect, and module boundaries.
- The simplified control path is easier for Vivado to optimize in the folded architecture.

### 3. Parallel QPP Scheduler Removed From Active Path

Paper intent:

- QPP addresses are generated in parallel to feed multiple lanes without collisions.

Current implementation:

- `qpp_parallel_scheduler` is not used in the active top.
- The active top computes `qpp_value(...)` directly and issues one scalar permutation at a time.

Reason for removal:

- A parallel scheduler only pays off when there are multiple concurrent lanes to feed.
- Once the datapath was collapsed to one SISO, the parallel address scheduler became unnecessary area overhead.

### 4. Batcher Routing Network Removed From Active Path

Paper intent:

- Batcher sorting and unsorting networks resolve write/read ordering across parallel lanes.
- These networks are central to contention-free parallel interleaving memory access.

Current implementation:

- `batcher_router`, `batcher_master`, and `batcher_slave` are not in the active top.
- Data movement is serialized by the top FSM instead of being routed through a parallel permutation network.

Reason for removal:

- Batcher networks are comparator-heavy and routing-heavy.
- That cost is acceptable in the original high-throughput architecture only if the rest of the parallel system is retained.
- After moving to a single-SISO folded architecture, the batcher path became pure overhead.

### 5. Multiport Parallel Memory System Removed

Paper intent:

- The architecture relies on banked or effectively multiported memories to support simultaneous lane accesses.
- Memory organization is part of the contention-free parallel decoder concept.

Current implementation:

- `multiport_row_bram` is not used in the active top.
- The active top uses three `simple_dp_bram` blocks and performs extra copies/permutations across phases.

Reason for removal:

- True multiport memory is not a native FPGA primitive.
- FPGA implementations of multiport behavior usually expand into LUTRAM, replication, mux networks, or several BRAM copies, all of which grow area quickly.
- The paper assumes an ASIC-oriented memory organization that maps poorly to a small Zynq FPGA when kept literally.

### 6. Folded LLR RAM Not Used In The Active Top

Observation:

- [rtl/folded_llr_ram.vhd](c:/VAMSHI/IIT Mandi Academic Folder/IITM 6th Sem/DVAD/TURBO_DECODER_HDL/Parallel-Turbo-Decoder-ASIC-for-3GPP-LTE/rtl/folded_llr_ram.vhd) exists and has its own testbench, but it is not instantiated in the current active top.

Interpretation:

- It appears to be an intermediate attempt to preserve more of the original dataflow while reducing FPGA cost.
- The final active top moved to an even simpler memory strategy around `simple_dp_bram` plus sequential copy/permutation phases.

### 7. Segmented Parallel Dataflow Replaced By Sequential Frame Transforms

Paper intent:

- Natural-domain and interleaved-domain data are handled in a pipeline around concurrent SISOs and contention-free memory banking.

Current implementation:

- The top-level FSM explicitly performs build, interleave, deinterleave, and final remap stages.
- States such as `ST_BUILD_SYS_INT`, `ST_EXT_NAT_TO_INT`, `ST_EXT_INT_TO_NAT`, and `ST_FINAL_INT_TO_NAT` show this shift clearly.

Reason for removal:

- Sequential transforms cost cycles, but they reduce concurrent hardware.
- This is the main throughput-for-area trade made to give the design a chance on FPGA.

## What Still Matches The Paper

The current design is not arbitrary. It still keeps several algorithmic pieces from the paper:

- Turbo decoding structure with alternating constituent decoding
- LTE QPP permutation law itself
- Max-log-MAP style SISO computation
- Fixed-point LLR-based datapath
- Forward and backward recursion structure inside the SISO
- Iterative exchange of extrinsic information between natural and interleaved domains

So the main deviation is architectural, not algorithmic. The math is still trying to follow the paper's decoder behavior, but the hardware organization has been simplified heavily for FPGA feasibility.

## Why FPGA Forced These Deviations

The current target pressure is visible in synthesis even after simplifying the architecture.

From the latest synthesis results:

- Slice LUTs: 22282 used out of 17600, or 126.60%
- LUT as Logic: 19946
- LUT as Memory: 2336
- RAMB36: 16
- DSPs: 0

These numbers mean the folded active design still does not fit on the present `xc7z010` synthesis target. That strongly implies the older parallel backup architecture is even less realistic for the same device.

The remaining synthesis warnings also show why the FPGA mapping is difficult. Vivado is still refusing to infer BRAM for six internal SISO frame memories and implements them as LUTRAM instead:

- `sys_even_mem_reg`
- `par_even_mem_reg`
- `apri_even_mem_reg`
- `sys_odd_mem_reg`
- `par_odd_mem_reg`
- `apri_odd_mem_reg`

This is exactly the kind of issue that hurts FPGA viability:

- LUTs are already overfull.
- Any memory that falls back to LUTRAM makes the LUT problem worse.
- Parallel memory systems from the paper depend on access patterns that are not BRAM-friendly on this FPGA.

In short, the FPGA is forcing the design away from paper-faithful parallelism because:

- the logic fabric is too small for the full routing/control/memory network,
- the memory access style does not infer clean BRAM structures,
- and the ASIC-oriented multi-lane memory architecture does not translate efficiently to this class of FPGA.

## Bottom Line

The current active top is not the paper architecture anymore. It is an FPGA-rescue architecture derived from the paper:

- one SISO instead of the parallel SISO array,
- scalar QPP access instead of the parallel scheduler,
- FSM-controlled movement instead of a separate iteration controller plus routing fabric,
- simple BRAM-backed frame stores instead of the full contention-free multiport memory system.

So yes: the other RTL blocks you named are not used by the new top module. They are absent because the design had to trade throughput and paper-faithful parallelism for a much smaller hardware footprint. Even after those reductions, the current `xc7z010` target is still LUT-limited, which is the clearest evidence that the original paper-style parallel version is not a practical fit for that device.
