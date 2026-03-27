# `batcher_master` / `batcher_slave` Internal Functional Guide

This note decomposes the **purely combinational** internal units inside:

- [`rtl/batcher_master.vhd`](../../../rtl/batcher_master.vhd)
- [`rtl/batcher_slave.vhd`](../../../rtl/batcher_slave.vhd)

The goal here is deeper than the earlier architecture package:
- not just master/slave black boxes
- specifically the internal functional cells and networks

These modules have no registers and no FSMs.
Everything here is combinational.

## 1. `batcher_master` Internal Units

`batcher_master` contains three real internal functional objects:

1. address unpack / lane-tag initialization
2. compare-swap cell
3. 6-stage `N=8` Batcher sorting network

### 1.1 Address / Tag Initialization

Before sorting:

```text
addr_v(i) = addr_in(i)
lane_v(i) = i
```

So every address carries an attached lane tag.

This means the network is not sorting addresses only.
It is sorting:
- the address value
- its original lane identity

### 1.2 Compare-Swap Cell

The primitive cell is `compare_swap(left_idx,right_idx,ctrl_idx)`.

Functional behavior:

```text
cmp = (addr_v(L) > addr_v(R))

if cmp = 1:
    swap addr_v(L), addr_v(R)
    swap lane_v(L), lane_v(R)
    c_tmp(ctrl_idx) = 1
else
    keep addr_v(L), addr_v(R)
    keep lane_v(L), lane_v(R)
    c_tmp(ctrl_idx) = 0
```

So one compare-swap cell contains:
- one greater-than comparator
- one address swap mux pair
- one lane-tag swap mux pair
- one control-bit output

This is the most important internal unit of the master.

### 1.3 Six-Stage Sorting Network

The master instantiates this fixed stage schedule:

Stage 0:
- `(0,1)`, `(2,3)`, `(4,5)`, `(6,7)`

Stage 1:
- `(0,2)`, `(1,3)`, `(4,6)`, `(5,7)`

Stage 2:
- `(1,2)`, `(5,6)`

Stage 3:
- `(0,4)`, `(1,5)`, `(2,6)`, `(3,7)`

Stage 4:
- `(2,4)`, `(3,5)`

Stage 5:
- `(1,2)`, `(3,4)`, `(5,6)`

So the full internal master network is:

```text
init addr_v/lane_v
    -> stage0 compare-swap cells
    -> stage1 compare-swap cells
    -> stage2 compare-swap cells
    -> stage3 compare-swap cells
    -> stage4 compare-swap cells
    -> stage5 compare-swap cells
    -> pack addr_sorted / perm_out / ctrl_out
```

### 1.4 `ctrl_out` As Structural Trace

`ctrl_out[18:0]` is not extra logic separate from the network.
It is literally the record of the compare-swap decisions made by the 19 cells.

So architecturally:
- `perm_out` is the routing result
- `ctrl_out` is the internal swap history

## 2. `batcher_slave` Internal Units

`batcher_slave` contains four real internal functional objects:

1. input unpack
2. per-slot permutation decode
3. mode-controlled routing cell
4. output repack

### 2.1 Input Unpack

The input bus is unpacked into:

```text
in_v(i) = data_in lane i
out_v(i) = 0 initially
```

So the internal routing object is a lane array, not the packed bus.

### 2.2 Permutation Decode Cell

For each `slot`:

```text
perm_i = to_integer(to_01(perm_in(slot)))
```

Then the cell checks:

```text
0 <= perm_i < G_P
```

So every slot has:
- a decode unit
- a bounds-check unit

### 2.3 Mode-Controlled Router Cell

The deep functional primitive of the slave is the per-slot router cell.

If `G_REVERSE = false`:

```text
out_v(perm_i) = in_v(slot)
```

If `G_REVERSE = true`:

```text
out_v(slot) = in_v(perm_i)
```

So the router cell contains:
- decoded `perm_i`
- mode select
- source/destination selection
- gated assignment enable

### 2.4 Permutation Network

The full slave is a replicated bank of these per-slot router cells:

```text
for slot in 0 .. G_P-1:
    decode perm_i
    bounds-check
    apply forward or reverse assignment
```

Then `out_v` is packed back into `data_out`.

Architecturally it behaves like a payload crossbar controlled by the permutation vector.

## 3. Master vs Slave Deep Structure

The deep difference is:

- `batcher_master`
  - transforms the address vector itself
  - uses a fixed compare-swap sorting network

- `batcher_slave`
  - does not sort anything
  - simply routes payload data according to `perm_in`

So:

```text
Master deep unit = compare-swap network
Slave deep unit  = permutation router network
```

## 4. Diagram Files In This Folder

- [`BATCHER_MASTER_FUNCTIONAL_UNITS.svg`](BATCHER_MASTER_FUNCTIONAL_UNITS.svg)
  - master internal functional overview
- [`BATCHER_MASTER_COMPARE_SWAP_CELL.svg`](BATCHER_MASTER_COMPARE_SWAP_CELL.svg)
  - one deep compare-swap primitive
- [`BATCHER_MASTER_SORTING_NETWORK.svg`](BATCHER_MASTER_SORTING_NETWORK.svg)
  - the 6-stage `N=8` sorting network
- [`BATCHER_SLAVE_FUNCTIONAL_UNITS.svg`](BATCHER_SLAVE_FUNCTIONAL_UNITS.svg)
  - slave internal functional overview
- [`BATCHER_SLAVE_SLOT_ROUTER_CELL.svg`](BATCHER_SLAVE_SLOT_ROUTER_CELL.svg)
  - one deep per-slot router cell
- [`BATCHER_SLAVE_PERMUTATION_NETWORK.svg`](BATCHER_SLAVE_PERMUTATION_NETWORK.svg)
  - the replicated permutation network
