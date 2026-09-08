# Pipeline-depth sweep (resources & latency)

An architecture experiment: how does cost scale as pipeline depth grows? The
skid-buffer chain (`axis_slice_chain`, one registered stage per unit) is swept
over `STAGES` and synthesized for a Lattice ECP5 with yosys. Reproduce with:

```bash
scripts/sweep.sh 1 2 4 8 16
```

## Results (yosys, ECP5)

| STAGES | LUT4 | Flip-flops | Latency (cycles) |
|-------:|-----:|-----------:|-----------------:|
| 1      | 15   | 18         | 1                |
| 2      | 28   | 36         | 2                |
| 4      | 54   | 72         | 4                |
| 8      | 106  | 144        | 8                |
| 16     | 210  | 288        | 16               |

## Reading the numbers

- **Resources scale linearly with depth** — about 13 LUT4 and exactly 18
  flip-flops per stage (each skid buffer holds two 8-bit data registers plus its
  main/skid valid bits). Cost per stage is constant, so depth is a predictable
  knob.
- **Latency is one cycle per stage** — the direct throughput/latency trade the
  designer controls.
- **Throughput stays at one word/cycle at every depth** — the skid buffer
  registers `tready`, so adding stages does not create a combinational ready path
  that would force bubbles (this is exactly why the skid buffer was chosen over a
  plain register slice; see the journal V1b entry).

## On Fmax

Real Fmax requires place-and-route (Vivado or a working nextpnr), which isn't
available in this headless environment, so it is a documented target rather than
a measured number. yosys `ltp` reports a topological path length, but for a
fully-registered pipeline that number tracks pipeline traversal depth rather than
a single-cycle combinational path, so it is **not** used here as an Fmax proxy.
The honest, measured results are the resource and latency columns above; timing
closure at the 250 MHz target is the remaining Vivado milestone.
