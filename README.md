# fluxNIC — Programmable FPGA Network Data Plane

[![ci](https://github.com/IMINABO1/fluxNIC/actions/workflows/ci.yml/badge.svg)](https://github.com/IMINABO1/fluxNIC/actions/workflows/ci.yml)

A low-latency, programmable packet-processing pipeline in SystemVerilog. Packets
enter over AXI-Stream, get parsed (Ethernet / IPv4 / UDP), matched against a
configurable flow table, and acted on — drop, forward, timestamp, or rewrite —
before leaving over AXI-Stream. The match/action tables are loaded at runtime
through an AXI-Lite control plane, giving a clean control-plane / data-plane split.

No physical hardware required: everything is simulated and verified in software,
then taken through Vivado synthesis, place-and-route, and timing closure.

## Architecture (target)

```
        AXI-Stream in
             |
        Ethernet parser
             |
        IPv4 / UDP parser
             |
        Header vector
             |
   +---------------------+       AXI-Lite control plane
   | Match table (BRAM)  | <---- (loads match + action tables,
   +---------------------+        port config, counters)
             |
        Action pipeline
     (drop / forward / rewrite
      / timestamp / count)
             |
        Packet rewriter
             |
        AXI-Stream out
```

## Toolchain

| Layer | Tool |
|-------|------|
| RTL | SystemVerilog |
| Simulator | Verilator |
| Testbenches | cocotb (Python) |
| Waveforms | GTKWave |
| Synthesis / STA | Vivado (final milestone) |
| Python env | uv + `.venv` (Python 3.13) |

All open-source tools run under WSL (Ubuntu).

## Getting started

```bash
# one-time: install simulator + waveform viewer (needs sudo)
sudo apt update && sudo apt install -y verilator gtkwave

# run a module's tests (from repo root)
source .venv/bin/activate
make -C tb MODULE=test_counter TOPLEVEL=counter

# view the waveform
gtkwave tb/sim_build/dump.vcd
```

## Layout

```
rtl/     SystemVerilog sources
tb/      cocotb testbenches + Makefile
docs/    design notes
journal.md               running log of what was built and why
problems-encountered.md  bugs, gotchas, and how they were solved
```

## Milestones

- [x] **V0** counter + cocotb test (the sim loop)
- [x] **V1** sync FIFO + AXI-Stream skid buffer + backpressure
- [x] **V2** Ethernet / IPv4 / UDP header parser
- [x] **V3** configurable exact-match flow table (BRAM-backed)
- [x] **V4** match-action engine (parse → key → lookup → action → decision + stats)
- [x] **V5** top-level store-and-forward integration (drop / forward per rule)
- [x] **V6** packet rewrite (UDP dst port, byte-accurate in egress)
- [ ] **V7** timestamping + rate limiting
- [x] **V8** randomized cocotb verification (reference-model checked) — SVA assertions pending
- [~] **V9** yosys ECP5 synthesis: real LUT/FF/BRAM numbers — Fmax pending Vivado/nextpnr P&R

### Status

The data plane works end to end in simulation: rules are loaded over the config
port, packets stream in over AXI-Stream, matching packets are forwarded to the
decided output port and non-matching packets are dropped, all under backpressure
on both sides, with live packet/hit/drop/forward counters. Every module is
verified with cocotb (several against Python reference models) and synthesizes
for a Lattice ECP5 with yosys.

### Measured resource usage (yosys, ECP5)

| Module | LUT4 | FF | BRAM |
|---|---|---|---|
| flow_table (256 entries) | 912 | 428 | 2× DP16KD |
| match_action | 1044 | 608 | 2× DP16KD |
| header_parser | 173 | 134 | – |
| **fluxnic_top (whole design)** | 1265 | 837 | 7× DP16KD |
