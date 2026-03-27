# `siso_maxlogmap` Package

This folder contains the exported architecture package for the **current** [`rtl/siso_maxlogmap.vhd`](../../rtl/siso_maxlogmap.vhd).

This is the rolling-window version with:
- optional legacy preload mode
- external pair-fetch mode for the active folded top
- no alpha-seed BRAM prepass
- no branch/gamma recomputation during LLR extraction

Main files:

- [`SISO_MAXLOGMAP_ARCHITECTURE_GUIDE.md`](SISO_MAXLOGMAP_ARCHITECTURE_GUIDE.md)
- [`SISO_MAXLOGMAP_ARCHITECTURE.svg`](SISO_MAXLOGMAP_ARCHITECTURE.svg)
- [`SISO_MAXLOGMAP_DATAPATH.svg`](SISO_MAXLOGMAP_DATAPATH.svg)
- [`SISO_MAXLOGMAP_CONTROL.svg`](SISO_MAXLOGMAP_CONTROL.svg)

Editable Graphviz sources:

- [`SISO_MAXLOGMAP_ARCHITECTURE.dot`](SISO_MAXLOGMAP_ARCHITECTURE.dot)
- [`SISO_MAXLOGMAP_DATAPATH.dot`](SISO_MAXLOGMAP_DATAPATH.dot)
- [`SISO_MAXLOGMAP_CONTROL.dot`](SISO_MAXLOGMAP_CONTROL.dot)

Deeper functional-unit breakdown:

- [`internal_units/`](internal_units/)
- [`internal_control/`](internal_control/)
- [`cell_level/`](cell_level/)
