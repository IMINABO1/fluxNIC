# fluxNIC — Programmable FPGA Network Data Plane

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

- [ ] **V0** counter + cocotb test (the sim loop)
- [ ] **V1** sync FIFO + AXI-Stream skid buffer + backpressure
- [ ] **V2** Ethernet / IPv4 / UDP parser
- [ ] **V3** configurable exact-match flow table
- [ ] **V4** match-action pipeline
- [ ] **V5** packet rewrite + checksum
- [ ] **V6** timestamping + counters + rate limiting
- [ ] **V7** multi-stage, one word/cycle throughput
- [ ] **V8** SVA assertions + randomized cocotb verification
- [ ] **V9** Vivado synth + P&R + STA @ 250+ MHz
