# `batcher_master` And `batcher_slave` Architecture Guide

This note explains:

- [`rtl/batcher_master.vhd`](../../rtl/batcher_master.vhd)
- [`rtl/batcher_slave.vhd`](../../rtl/batcher_slave.vhd)

These two modules form the routing-network pair used by the paper-aligned parallel top:

- `batcher_master`
  - sorts `8` addresses
  - records the lane permutation
  - emits `19` compare-swap control bits

- `batcher_slave`
  - applies the permutation to a data vector
  - can run in forward or reverse mode

So the master decides the order, and the slave moves the payload.

## 1. Why These Blocks Exist

In the parallel decoder, the QPP scheduler produces one vector of `8` addresses.

That vector is not naturally arranged in lane order. The architecture needs:

1. a block that sorts the addresses and remembers which original lane each sorted slot came from
2. a block that uses that remembered permutation to rearrange data buses

That is exactly the role split:

- `batcher_master`: address ordering and permutation extraction
- `batcher_slave`: payload routing under that permutation

## 2. `batcher_master`

### 2.1 What It Is

`batcher_master` is a fixed combinational sorting network specialized for `8` lanes.

Inputs:
- `addr_in`

Outputs:
- `addr_sorted`
- `perm_out`
- `ctrl_out`

Important structural fact:
- the RTL asserts `G_P = 8`
- so this is not a generic arbitrary-size network
- it is the paper’s `N=8` master Batcher network

### 2.2 Internal State Representation

The module internally builds:

- `addr_v(0..7)`
  - the working address array
- `lane_v(0..7)`
  - the working lane-tag array

Initialization:

```text
addr_v(i) = addr_in(i)
lane_v(i) = i
```

So every address carries its original lane tag through the sorting network.

### 2.3 Compare-Swap Primitive

The only real functional unit is `compare_swap(left_idx, right_idx, ctrl_idx)`.

Behavior:

```text
if addr_v(left) > addr_v(right):
    swap addr_v(left), addr_v(right)
    swap lane_v(left), lane_v(right)
    c_tmp(ctrl_idx) = 1
else
    c_tmp(ctrl_idx) = 0
```

So one compare-swap cell contains:
- one comparator
- an address swap mux pair
- a lane-tag swap mux pair
- one control-bit output

### 2.4 Batcher Stages

The compare-swap cells are arranged in six stages.

Stage 0:
- `(0,1)` -> `ctrl_out(0)`
- `(2,3)` -> `ctrl_out(1)`
- `(4,5)` -> `ctrl_out(2)`
- `(6,7)` -> `ctrl_out(3)`

Stage 1:
- `(0,2)` -> `ctrl_out(4)`
- `(1,3)` -> `ctrl_out(5)`
- `(4,6)` -> `ctrl_out(6)`
- `(5,7)` -> `ctrl_out(7)`

Stage 2:
- `(1,2)` -> `ctrl_out(8)`
- `(5,6)` -> `ctrl_out(9)`

Stage 3:
- `(0,4)` -> `ctrl_out(10)`
- `(1,5)` -> `ctrl_out(11)`
- `(2,6)` -> `ctrl_out(12)`
- `(3,7)` -> `ctrl_out(13)`

Stage 4:
- `(2,4)` -> `ctrl_out(14)`
- `(3,5)` -> `ctrl_out(15)`

Stage 5:
- `(1,2)` -> `ctrl_out(16)`
- `(3,4)` -> `ctrl_out(17)`
- `(5,6)` -> `ctrl_out(18)`

So the `19`-bit `ctrl_out` vector is exactly the history of whether each compare-swap cell exchanged its pair.

### 2.5 Outputs

After the last stage:

- `addr_sorted(i)` is the sorted address in slot `i`
- `perm_out(i)` is the original lane index now occupying slot `i`
- `ctrl_out(i)` indicates whether compare-swap cell `i` swapped

Architecturally:
- `addr_sorted` is the sorted address vector
- `perm_out` is the routing instruction for the slave
- `ctrl_out` is an explicit structural trace of the sorting network

### 2.6 Datapath vs Control

For `batcher_master`, there is no FSM or clocked control.

So the split is:

- datapath:
  - the 6-stage compare-swap network over `addr_v` and `lane_v`
- control:
  - the compare results that drive swap muxes
  - the emitted `ctrl_out` bits

That means the “control” structure is still combinational.

## 3. `batcher_slave`

### 3.1 What It Is

`batcher_slave` is a combinational permutation network for a payload vector.

Inputs:
- `perm_in`
- `data_in`

Output:
- `data_out`

Generic parameters:
- `G_P`
- `G_DATA_W`
- `G_SEL_W`
- `G_REVERSE`

So unlike `batcher_master`, the slave is generic in payload width.

### 3.2 Internal Representation

The module internally builds:

- `in_v(0..G_P-1)`
  - unpacked input lanes
- `out_v(0..G_P-1)`
  - output lanes, initialized to zero

So the slave is:
- unpack bus
- permute array elements
- repack bus

### 3.3 Forward Mode

If `G_REVERSE = false`:

```text
for slot in 0..G_P-1:
    perm_i = perm_in(slot)
    out_v(perm_i) = in_v(slot)
```

Meaning:
- input slots are currently in sorted-slot order
- `perm_in` tells which original lane each slot belongs to
- the slave writes each payload back into lane order

This is used in the feed path of phase 2.

### 3.4 Reverse Mode

If `G_REVERSE = true`:

```text
for slot in 0..G_P-1:
    perm_i = perm_in(slot)
    out_v(slot) = in_v(perm_i)
```

Meaning:
- input data is currently in lane order
- the slave produces slot order
- effectively it undoes the forward routing direction

This is used in phase-2 writeback.

### 3.5 Bounds Check

The slave guards every assignment with:

```text
if perm_i >= 0 and perm_i < G_P
```

So the control logic includes a per-slot validity check before the write or read mapping.

### 3.6 Datapath vs Control

For `batcher_slave`, the split is:

- datapath:
  - unpack input lanes
  - lane crossbar / assignment network
  - repack output bus

- control:
  - per-slot `perm_i` decode
  - mode select by `G_REVERSE`
  - bounds check on destination/source index

Again this is purely combinational control, not sequential control.

## 4. Relationship Between Master And Slave

The clean architectural relation is:

```text
addr_in
  -> batcher_master
     -> addr_sorted
     -> perm_out

payload_in
  + perm_out
  -> batcher_slave
     -> payload_out
```

So:
- the master sorts addresses and emits the permutation
- the slave applies that permutation to the payload

## 5. What To Draw

For `batcher_master`, the clearest figures are:

1. full architecture:
   - input unpack
   - lane-tag initialization
   - 6-stage compare-swap network
   - output pack
2. datapath:
   - address/tag flow through the stages
3. control:
   - comparator outputs driving swap muxes and `ctrl_out`

For `batcher_slave`, the clearest figures are:

1. full architecture:
   - unpack
   - mode-controlled permutation core
   - repack
2. datapath:
   - input-lane to output-lane routing
3. control:
   - `perm_i` decode
   - forward vs reverse selection
   - bounds gating

## 6. Short Description

The short description is:

- `batcher_master` is an `8`-input combinational Batcher sorting network that sorts addresses, tracks original lane tags, and emits both permutation and compare-swap control bits.
- `batcher_slave` is a generic combinational permutation network that routes payload lanes according to the permutation vector, in forward or reverse mode.
