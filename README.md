# ML-DSA Polynomial Arithmetic Accelerator

Independent DSP course project: reconfigurable 256-point radix-4 NTT/INTT and point-wise arithmetic, configurable processing elements, 23-bit modular arithmetic, a pipelined Barrett multiplier, and four-bank polynomial memory.

## Contents

- `src/`: RTL and parameter header.
- `sim/`: unit, engine, top-level and historical gate-level testbenches.
- `golden/`: Python models/generators and `hex/` reference vectors.
- `constraints.xdc`, `polymul_top.sdc`: timing constraints.
- `syn.tcl`: historical Design Compiler synthesis flow; requires licensed cell libraries. As its header states, stage RTL, headers and SDC together before use.
- `arch_block.png`: architecture diagram.

## RTL tests

Install Icarus Verilog and Python 3 and run from the repository root:

```sh
python run_tests.py
```

The runner stages reference vectors in an ignored build folder and tests each RTL testbench separately. The gate-level testbench is retained for reference but skipped: foundry libraries, SDF, and mapped netlists are excluded.

Obsolete absolute Python import paths were removed in this export. No arithmetic algorithm changes were made. This repository contains arithmetic components, not a complete ML-DSA signing implementation.

## Export verification

2026-09-30: 11 RTL testbenches completed successfully with Icarus Verilog. The gate-level testbench was skipped because external technology files are not distributed. See `run_tests.py` to rerun. Synthesis and board validation were not rerun.
