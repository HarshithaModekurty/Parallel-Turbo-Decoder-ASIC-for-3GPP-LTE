# `batcher_master` / `batcher_slave` Cell-Level Guide

This folder adds the same last-level schematic view that already exists for
`siso_maxlogmap`, but now for:

- [`rtl/batcher_master.vhd`](../../../rtl/batcher_master.vhd)
- [`rtl/batcher_slave.vhd`](../../../rtl/batcher_slave.vhd)

The goal is not another black-box architecture drawing. The goal here is:

- explicit block split chosen directly from RTL
- pure isomorphic operator-level symbols
- visible mux / decode / compare wiring
- repeated-cell diagrams that show a few instances, `...`, and the total count

These two modules are entirely combinational, so there are no registers or FSM
blocks in this package.

## 1. `batcher_master` Block Split

The RTL naturally splits into four blocks:

1. input unpack
   - `8` address slices are unpacked from `addr_in`
2. lane-tag initializer
   - `lane_v(i) := i` for `i = 0..7`
3. compare-swap fabric
   - `19` compare-swap cells arranged in `6` Batcher stages
4. output pack
   - `addr_sorted`, `perm_out`, and `ctrl_out`

That split is shown in:

- [`BATCHER_MASTER_BLOCK_SPLIT.svg`](BATCHER_MASTER_BLOCK_SPLIT.svg)

### 1.1 Master Primitive Cell

The true deep primitive is one `compare_swap(left_idx,right_idx,ctrl_idx)` cell.
At cell level it contains:

- `1` greater-than comparator over the two address inputs
- `2` address muxes
- `2` lane-tag muxes
- `1` control-bit tap, where `ctrl_out(ctrl_idx) = swap`

That primitive is shown in:

- [`BATCHER_MASTER_COMPARE_SWAP_CELL_LEVEL.svg`](BATCHER_MASTER_COMPARE_SWAP_CELL_LEVEL.svg)

### 1.2 Master Network Replication

The full network is just that primitive replicated `19` times:

- Stage 0: `4` cells
- Stage 1: `4` cells
- Stage 2: `2` cells
- Stage 3: `4` cells
- Stage 4: `2` cells
- Stage 5: `3` cells

That stage-level replication is shown in:

- [`BATCHER_MASTER_SORTING_NETWORK_CELL_LEVEL.svg`](BATCHER_MASTER_SORTING_NETWORK_CELL_LEVEL.svg)

## 2. `batcher_slave` Block Split

The slave RTL naturally splits into five blocks:

1. payload unpack
   - `G_P` data slices are unpacked from `data_in`
2. permutation-slice decode
   - one `perm_i` decode for each slot
3. validity check
   - `0 <= perm_i < G_P`
4. mode-controlled router cell bank
   - forward mapping when `G_REVERSE = false`
   - reverse mapping when `G_REVERSE = true`
5. output pack
   - `out_v` repacked into `data_out`

That split is shown in:

- [`BATCHER_SLAVE_BLOCK_SPLIT.svg`](BATCHER_SLAVE_BLOCK_SPLIT.svg)

### 2.1 Slave Primitive Cell

The deep primitive is one per-slot router cell. It contains:

- one permutation decode
- one validity check
- one forward branch:
  - fixed source `in_v(slot)`
  - `1-of-G_P` destination decode / demux
- one reverse branch:
  - `G_P:1` source mux controlled by `perm_i`
  - fixed destination `out_v(slot)`
- one mode select by `G_REVERSE`

That primitive is shown in:

- [`BATCHER_SLAVE_SLOT_ROUTER_CELL_LEVEL.svg`](BATCHER_SLAVE_SLOT_ROUTER_CELL_LEVEL.svg)

### 2.2 Slave Network Replication

The full slave is the per-slot router cell repeated:

- total router cells = `G_P`
- paper-aligned parallel decoder case: `G_P = 8`

The network figure is drawn for the paper case, so it shows:

- `8` slot router cells total
- first cells explicitly
- `...`
- last cell explicitly

That replication is shown in:

- [`BATCHER_SLAVE_PERMUTATION_NETWORK_CELL_LEVEL.svg`](BATCHER_SLAVE_PERMUTATION_NETWORK_CELL_LEVEL.svg)

## 3. Reading Convention

This package uses the following convention:

- comparator: diamond `>`
- mux: trapezoid `MUX`
- decoder / demux: rounded box
- buses / packed ports: parallelogram
- repeated blocks: explicit first blocks, `...`, explicit last block, with total count

So the cell-level package is meant to answer these questions directly:

- where are the swap muxes in the master?
- where does each `ctrl_out` bit come from?
- where are the slave’s forward and reverse routing branches?
- what exactly repeats across the `8` lanes / slots?
