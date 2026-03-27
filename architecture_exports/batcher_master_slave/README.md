# `batcher_master` / `batcher_slave` Package

This folder contains the architecture package for:

- [`rtl/batcher_master.vhd`](../../rtl/batcher_master.vhd)
- [`rtl/batcher_slave.vhd`](../../rtl/batcher_slave.vhd)

Main files:

- [`BATCHER_MASTER_SLAVE_ARCHITECTURE_GUIDE.md`](BATCHER_MASTER_SLAVE_ARCHITECTURE_GUIDE.md)

Master figures:

- [`BATCHER_MASTER_ARCHITECTURE.svg`](BATCHER_MASTER_ARCHITECTURE.svg)
- [`BATCHER_MASTER_DATAPATH.svg`](BATCHER_MASTER_DATAPATH.svg)
- [`BATCHER_MASTER_CONTROL.svg`](BATCHER_MASTER_CONTROL.svg)

Slave figures:

- [`BATCHER_SLAVE_ARCHITECTURE.svg`](BATCHER_SLAVE_ARCHITECTURE.svg)
- [`BATCHER_SLAVE_DATAPATH.svg`](BATCHER_SLAVE_DATAPATH.svg)
- [`BATCHER_SLAVE_CONTROL.svg`](BATCHER_SLAVE_CONTROL.svg)

Editable Graphviz sources are included as `.dot` files with the same base names.

Deeper combinational internal-unit breakdown:

- [`internal_units/`](internal_units/)

Pure isomorphic cell-level package:

- [`cell_level/`](cell_level/)
