# `siso_maxlogmap` Cell-Level Package

This folder contains a **deeper structural view** of the updated rolling-window
[`rtl/siso_maxlogmap.vhd`](../../../rtl/siso_maxlogmap.vhd).

The diagrams here go below the earlier functional blocks and show the main
adder, mux, compare-select, and register/memory structures for:

- the radix-4 gamma metric generator
- the shared radix-4 ACS block
- the LLR extraction network

Main files:

- [`SISO_MAXLOGMAP_CELL_LEVEL_GUIDE.md`](SISO_MAXLOGMAP_CELL_LEVEL_GUIDE.md)
- [`SISO_GAMMA_METRIC_CELL_LEVEL.svg`](SISO_GAMMA_METRIC_CELL_LEVEL.svg)
- [`SISO_RADIX4_ACS_CELL_LEVEL.svg`](SISO_RADIX4_ACS_CELL_LEVEL.svg)
- [`SISO_LLR_EXTRACTION_CELL_LEVEL.svg`](SISO_LLR_EXTRACTION_CELL_LEVEL.svg)

Editable Graphviz sources:

- [`SISO_GAMMA_METRIC_CELL_LEVEL.dot`](SISO_GAMMA_METRIC_CELL_LEVEL.dot)
- [`SISO_RADIX4_ACS_CELL_LEVEL.dot`](SISO_RADIX4_ACS_CELL_LEVEL.dot)
- [`SISO_LLR_EXTRACTION_CELL_LEVEL.dot`](SISO_LLR_EXTRACTION_CELL_LEVEL.dot)
